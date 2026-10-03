extends Node
## 环境音（Music）：海风 + 海浪的背景噪声床，不是旋律。
## 做法是把噪声按截止频率劈成三条带（风声 / 浪的主体 / 浪花嘶声），每条各自套一个
## 慢包络，浪的起伏用「循环长度的整数倍频」叠加，所以 loop_forward 听不出接缝。
## 和 Sfx 一样零音频素材：整段在需要时烘成一段 AudioStreamWAV。

const RATE := 22050

var muted := false
var _players := {}
var _cur := ""
var _cache := {}
# 烘一床 24 秒的浪要 1.8 秒 CPU。以前是"第一次切到这条"时在**主线程**现场算，
# 于是标题页刚出来就冻住，玩家那一下「开始营业」点在了冻结的窗口上。
# 现在三条床启动时并行烘到工作线程，谁先烘完谁上岗；没烘好就先不出声，绝不卡主线程。
var _tasks := {}
var _pending := {}
var _mutex := Mutex.new()
var _want := ""

## low/mid/high = 三条带的截止频率；swell 是浪涌的谐波组合（[倍数, 权重, 相位]）
## 截止都压得偏低：真实的拍岸声能量集中在 1kHz 以下，高频只是薄薄一层泡沫嘶声。
## 但也不能全压在 150Hz 以下——笔记本喇叭重放不出来，等于悄悄没声音。
## 所以让"浪身的嘶"（150~800Hz）占大头，低频只做底。
const TRACKS := {
	# 夜里收摊后的海滩：浪远、风长、几乎没有嘶声
	"town": {
		"secs": 24.0, "low": 175.0, "mid": 700.0, "high": 1900.0,
		"g_low": 0.40, "g_mid": 0.46, "g_high": 0.06,
		"swell": [[1, 0.55, 0.0], [2, 0.30, 0.35], [3, 0.15, 0.62]], "sharp": 2.2,
		"wind_harsh": 0.55, "seed": 91337,
	},
	# 营业高峰：浪更近、更密，嘶声多一点，推着人动手
	"cook": {
		"secs": 24.0, "low": 190.0, "mid": 820.0, "high": 2300.0,
		"g_low": 0.34, "g_mid": 0.50, "g_high": 0.11,
		"swell": [[2, 0.50, 0.0], [3, 0.30, 0.42], [5, 0.20, 0.17]], "sharp": 1.7,
		"wind_harsh": 0.70, "seed": 44209,
	},
	# 结算：只剩很轻的拍岸
	"win": {
		"secs": 16.0, "low": 165.0, "mid": 640.0, "high": 1700.0,
		"g_low": 0.36, "g_mid": 0.44, "g_high": 0.05,
		"swell": [[1, 0.62, 0.0], [2, 0.26, 0.5], [4, 0.12, 0.28]], "sharp": 2.6,
		"wind_harsh": 0.45, "seed": 7051,
	},
}

func _ready() -> void:
	# 暂停（结算页、暂停浮层）不能停掉"烘好了就接上"这件事
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in TRACKS.keys():
		var p := AudioStreamPlayer.new()
		p.volume_db = -13.0
		add_child(p)
		_players[id] = p
		_start_bake(String(id))

func _process(_delta: float) -> void:
	if _tasks.is_empty():
		return
	var done: Array = []
	var raws: Array = []
	_mutex.lock()
	for id in _pending.keys():
		done.append(String(id))
		raws.append(_pending[id] as PackedByteArray)
		_pending.erase(id)
	_mutex.unlock()
	if done.is_empty():
		return
	for i in done.size():
		var tid := int(_tasks[done[i]])
		_tasks.erase(done[i])
		# 结果已经交出来了，这里只是归还 Godot 的任务槽，不会真的等
		WorkerThreadPool.wait_for_task_completion(tid)
		_cache[done[i]] = _make_wav(raws[i])
	if _want != "" and _cache.has(_want):
		var want := _want
		_want = ""
		_cur = want
		_start(want)

## 起一趟后台烘焙；已在烘或已烘好就跳过
func _start_bake(id: String) -> void:
	if _cache.has(id) or _tasks.has(id):
		return
	_tasks[id] = WorkerThreadPool.add_task(_bake_worker.bind(id), false, "music bake " + id)

func _bake_worker(id: String) -> void:
	var data := _render_samples(TRACKS[id])
	_mutex.lock()
	_pending[id] = data
	_mutex.unlock()

func track() -> String:
	return _cur

## 三条床是否都已烘好。给自检用：没烘好就说明切屏时可能还要在主线程现场算。
func warm() -> bool:
	_mutex.lock()
	var n := _cache.size()
	_mutex.unlock()
	return n >= TRACKS.size()

## 自检会在烘焙还没落地时就 quit（headless 跑测试），这里兜住任务槽，
## 否则退出时 WorkerThreadPool 里留着没人归还的槽。
## 还要先把播放器停下来：正在播的 AudioStreamPlayer 持有 AudioStreamWAV 和它的
## AudioStreamPlaybackWAV，退出顺序赶不上就会报 "2 ObjectDB instances were leaked"。
func _exit_tree() -> void:
	# 退出前先静音：正在播的床音在 dummy 音频驱动下会拖到 ObjectDB 清理之后才放开
	stop()
	for id in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(int(_tasks[id]))
	_tasks.clear()

## 给自检用：直接烘一首，不经播放器（测试里可以慢慢等）。
func bake(id: String) -> AudioStreamWAV:
	if not _cache.has(id):
		_cache[id] = _render(TRACKS[id])
	return _cache[id]

## 换床。同一条在放就不动，免得每次切屏浪都从头涌一遍。
## 静音时也要记住该放哪条——否则取消静音后要等下一次切屏才有声音。
func play_track(id: String) -> void:
	if not _players.has(id):
		return
	var p: AudioStreamPlayer = _players[id]
	if _cur == id and p.playing:
		return
	_cur = id
	if muted:
		return
	if not _cache.has(id):
		_start_bake(id)
		_want = id
		return
	_start(id)

func _start(id: String) -> void:
	var p: AudioStreamPlayer = _players[id]
	p.stream = _cache[id]
	for k in _players.keys():
		if k != id:
			(_players[k] as AudioStreamPlayer).stop()
	p.play()

func stop() -> void:
	for p in _players.values():
		(p as AudioStreamPlayer).stop()
	_cur = ""

func set_muted(v: bool) -> void:
	muted = v
	if v:
		# 直接停播放器而不是调 stop()——stop() 会清掉 _cur，取消静音后就不知道该恢复哪条了
		for p in _players.values():
			(p as AudioStreamPlayer).stop()
	elif _cur != "":
		play_track(_cur)

# ---------------- 合成 ----------------
## 一阶低通的系数：cut 是截止频率（Hz）
func _pole(cut: float) -> float:
	return clampf(TAU * cut / RATE, 0.0002, 1.0)

func _render(def: Dictionary) -> AudioStreamWAV:
	return _make_wav(_render_samples(def))

## 只算样本字节（16bit 单声道）：全程不碰任何引擎对象，所以能丢在工作线程里跑。
func _render_samples(def: Dictionary) -> PackedByteArray:
	var total := int(float(def["secs"]) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	buf.fill(0.0)
	var L := float(def["secs"])
	# 三条带各用一条独立噪声，否则同一份噪声劈出来的三带完全相关，听着像一个人说话
	var bands := [
		[float(def["low"]) * 0.55, float(def["g_low"]), int(def["seed"]) + 11],
		[float(def["mid"]), float(def["g_mid"]), int(def["seed"]) + 2203],
		[float(def["high"]), float(def["g_high"]), int(def["seed"]) + 51197],
	]
	for bi in bands.size():
		var cut := float(bands[bi][0])
		var gain := float(bands[bi][1])
		if gain <= 0.0:
			continue
		var s := RandomNumberGenerator.new()
		s.seed = int(bands[bi][2])
		# 四阶级联低通（24dB/oct）。一阶只有 6dB/oct，等于没滤——
		# 之前 cook 的频谱质心跑到 4600Hz、一半能量在 2.5kHz 以上，听着就是嘶而不是浪。
		var k := _pole(cut)
		var a := 0.0
		var b := 0.0
		var c := 0.0
		var dd := 0.0
		# 浪越靠上（带越高）涌得越快，泡沫比浪身早一点点拍上来
		var swell_mix := 0.35 + 0.65 * float(bi)
		var lead := 0.012 * float(bi)
		for i in total:
			var white := s.randf() * 2.0 - 1.0
			a += (white - a) * k
			b += (a - b) * k
			c += (b - c) * k
			dd += (c - dd) * k
			var env := _swell(float(i) / RATE / L + lead, def, swell_mix, bi)
			buf[i] = buf[i] + dd * env * gain
	# 归一化到 0.6 峰值：环境床要能压在音效下面，不该和点击声抢响度
	var peak := 0.0001
	for i in total:
		peak = maxf(peak, absf(buf[i]))
	var g := 0.6 / peak
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		var v := clampf(buf[i] * g, -1.0, 1.0)
		var q := int(round(v * 32767.0))
		if q < 0:
			q += 65536
		data[i * 2] = q & 0xFF
		data[i * 2 + 1] = (q >> 8) & 0xFF
	return data

## WAV 头留在主线程组装：工作线程只负责那 50 多万个采样点。
func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = data.size() / 2
	return wav

## 浪涌包络。ph 是 0..1 的一整圈循环，谐波倍数全取整数，所以首尾严格接得上。
## flat=0 时只剩一点点底噪（风声），flat=1 时涌得最满（浪头）。
func _swell(ph: float, def: Dictionary, flat: float, band: int) -> float:
	var t := TAU * ph
	var s := 0.0
	var wsum := 0.0
	for h in def["swell"]:
		var arr: Array = h
		s += float(arr[1]) * (0.5 + 0.5 * sin(t * float(arr[0]) + float(arr[2]) * TAU))
		wsum += float(arr[1])
	s /= maxf(wsum, 0.0001)
	var sharp := float(def["sharp"])
	# 幂一下把浪头削尖、把浪谷拉长，否则听着像呼吸器而不是拍岸
	var crest := pow(s, sharp)
	var base := 1.0 - flat
	var env := base + flat * crest
	# 风带再叠一层更慢的游走，免得整条低频稳得像台风机
	if band == 0:
		env *= 0.75 + 0.25 * (0.5 + 0.5 * sin(t * 2.0 + 1.1))
		env *= lerpf(0.85, 1.15, float(def["wind_harsh"]))
	return env
