extends Node
## 程序化音效（Sfx）：沿用原网页版 WebAudio 的合成音色，无需音频素材文件。

const MIX_RATE := 22050

var muted := false
var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _pi := 0

const SOUND_NAMES := ["tap", "place", "flip", "ding", "burnt", "angry", "pour",
	"coin", "coin_pick", "sweep_in", "sweep", "story", "chop", "wood_add", "walkout", "spawn",
	"whoosh", "sizzle", "thud", "spill", "lift", "purchase", "combo", "star", "fanfare", "page",
	"deliver", "settle", "steal"]

## 响度分级。以前每条音效的"多响"是 notes 里那个 vol 顺手决定的，而同一个数还兼着
## 包络深度用——改一个必顺带改另一个。现在 vol 只管形状，最终峰值统一按家族归一。
## ui=界面轻点，ok=做成了事，bad=做错了/损失，big=该被听见的长音。
const LEVELS := {"ui": 0.26, "ok": 0.40, "bad": 0.36, "big": 0.44}
const FAMILY := {
	"tap": "ui", "story": "ui", "spawn": "ui", "page": "ui", "deliver": "ui",
	"coin_pick": "ui", "lift": "ui",
	"place": "ok", "flip": "ok", "ding": "ok", "pour": "ok", "coin": "ok", "purchase": "ok",
	"star": "ok", "settle": "ok", "combo": "ok", "wood_add": "ok", "chop": "ok",
	"angry": "bad", "burnt": "bad", "spill": "bad", "walkout": "bad", "sweep": "bad",
	"sweep_in": "bad", "thud": "bad", "steal": "bad",
	"fanfare": "big", "sizzle": "big", "whoosh": "big",
}

func family_of(name: String) -> String:
	return str(FAMILY.get(name, "ok"))

func target_peak(name: String) -> float:
	return float(LEVELS.get(family_of(name), 0.4))

func _ready() -> void:
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for n in SOUND_NAMES:
		_cache[n] = _build(n)

func set_muted(v: bool) -> void:
	muted = v
	if muted:
		stop_all()

func play(name: String) -> void:
	if muted:
		return
	if not _cache.has(name):
		return
	var p: AudioStreamPlayer = _players[_pi % _players.size()]
	_pi += 1
	p.stream = _cache[name]
	p.play()

func stop_all() -> void:
	for p in _players:
		p.stop()

# ---------- 合成核心（三角/方波/锯齿/正弦 + 包络 + 叠音） ----------
func _build(name: String) -> AudioStreamWAV:
	var notes: Array = []
	match name:
		"tap": notes = [[660.0, 0.06, "tri", 0.08, 0.0]]
		"place": notes = [[440.0, 0.08, "tri", 0.10, 0.0], [660.0, 0.08, "tri", 0.08, 0.05]]
		"flip": notes = [[520.0, 0.05, "sq", 0.05, 0.0], [780.0, 0.07, "tri", 0.09, 0.04]]
		"ding": notes = [[880.0, 0.12, "sine", 0.12, 0.0], [1320.0, 0.20, "sine", 0.10, 0.08]]
		"burnt": notes = [[180.0, 0.25, "saw", 0.10, 0.0]]
		"serve": notes = [[660.0, 0.09, "tri", 0.10, 0.0], [880.0, 0.09, "tri", 0.10, 0.07], [1100.0, 0.15, "tri", 0.10, 0.14]]
		"angry": notes = [[220.0, 0.15, "saw", 0.09, 0.0], [160.0, 0.20, "saw", 0.08, 0.10]]
		# 倒饮料：原来是一个 300Hz 正弦"嗒"，听着像按了个键。液体得靠噪声加一点低频涌动
		"pour": notes = [[1500.0, 0.30, "n", 0.035, 0.0], [240.0, 0.26, "sine", 0.045, 0.0],
			[190.0, 0.18, "sine", 0.035, 0.12]]
		"coin": notes = [[988.0, 0.07, "sq", 0.06, 0.0], [1319.0, 0.12, "sq", 0.06, 0.06]]
		# 抛币 / 拾币 / 收币人：三种声音必须分得开，不然玩家不知道钱进没进钱包。
		# 拾币比抛币更高更短（"叮"一下拿走），收币是往下走的一串 + 一下沙沙扫。
		"coin_pick": notes = [[1568.0, 0.05, "sq", 0.05, 0.0], [2093.0, 0.09, "sine", 0.05, 0.03]]
		"sweep_in": notes = [[196.0, 0.18, "saw", 0.07, 0.0], [147.0, 0.22, "saw", 0.06, 0.14]]
		"sweep": notes = [[1400.0, 0.28, "n", 0.04, 0.0], [880.0, 0.10, "sq", 0.05, 0.0],
			[660.0, 0.12, "sq", 0.05, 0.09], [440.0, 0.18, "sq", 0.05, 0.18]]
		# 一枚一枚被装进兜里：比拾币低一截、闷一点，要听得出"不是我在拿"
		"steal": notes = [[520.0, 0.06, "sq", 0.05, 0.0], [392.0, 0.09, "tri", 0.05, 0.05]]
		# 逐件交付：递出一件比整单结算轻一档，免得每递一件都响一次"上餐"
		"deliver": notes = [[740.0, 0.06, "tri", 0.07, 0.0], [980.0, 0.08, "tri", 0.06, 0.05]]
		"settle": notes = [[784.0, 0.08, "sine", 0.07, 0.0], [1047.0, 0.08, "sine", 0.07, 0.07],
			[1319.0, 0.14, "sine", 0.07, 0.14]]
		"story": notes = [[520.0, 0.05, "sine", 0.05, 0.0]]
		"chop": notes = [[130.0, 0.09, "saw", 0.12, 0.0], [392.0, 0.08, "tri", 0.08, 0.05]]
		"wood_add": notes = [[196.0, 0.10, "tri", 0.09, 0.0], [294.0, 0.12, "tri", 0.07, 0.06]]
		# 客人走了：原来是一记 196Hz 单音，和"放下一片菜"的 wood_add 几乎分不出来。
		# 流失是这一局里最该听见的事，给它一个往下掉的两句 + 一点门口的闷响。
		"walkout": notes = [[330.0, 0.14, "tri", 0.09, 0.0], [247.0, 0.18, "tri", 0.08, 0.11],
			[110.0, 0.16, "sine", 0.09, 0.20], [900.0, 0.10, "n", 0.03, 0.0]]
		"spawn": notes = [[440.0, 0.07, "sine", 0.04, 0.0]]
		# 以下都是这一轮补的：挥斧的风声、油锅的滋滋、木头闷响、以及几个界面音。
		# 波形写 "n" 表示走噪声通道，此时第一个数是低通截止频率（越小越闷）。
		# 截止刻意压得低：真实的斧声/油声能量都在 2kHz 以下，往上走就是刺耳。
		"whoosh": notes = [[1100.0, 0.17, "n", 0.085, 0.0], [620.0, 0.11, "n", 0.055, 0.05]]
		"sizzle": notes = [[2100.0, 0.60, "n", 0.038, 0.0], [900.0, 0.50, "n", 0.026, 0.09]]
		"thud": notes = [[420.0, 0.11, "n", 0.11, 0.0], [118.0, 0.15, "sine", 0.13, 0.0],
			[196.0, 0.08, "tri", 0.045, 0.01]]
		"spill": notes = [[1200.0, 0.34, "n", 0.045, 0.0], [280.0, 0.20, "saw", 0.05, 0.02]]
		"lift": notes = [[520.0, 0.06, "tri", 0.055, 0.0], [760.0, 0.07, "tri", 0.05, 0.045]]
		"purchase": notes = [[784.0, 0.07, "tri", 0.075, 0.0], [1047.0, 0.09, "tri", 0.07, 0.06],
			[1319.0, 0.16, "sine", 0.06, 0.13]]
		"combo": notes = [[660.0, 0.06, "tri", 0.055, 0.0], [990.0, 0.06, "tri", 0.055, 0.05],
			[1320.0, 0.12, "sine", 0.055, 0.10]]
		"star": notes = [[1047.0, 0.10, "sine", 0.075, 0.0], [1568.0, 0.22, "sine", 0.06, 0.08]]
		"fanfare": notes = [[523.0, 0.12, "tri", 0.085, 0.0], [659.0, 0.12, "tri", 0.085, 0.11],
			[784.0, 0.14, "tri", 0.085, 0.22], [1047.0, 0.42, "sine", 0.09, 0.34],
			[1319.0, 0.40, "sine", 0.05, 0.36]]
		"page": notes = [[900.0, 0.06, "n", 0.04, 0.0], [620.0, 0.05, "tri", 0.035, 0.02]]
		_: notes = [[440.0, 0.08, "sine", 0.05, 0.0]]
	var dur := 0.0
	for n in notes:
		dur = maxf(dur, float(n[4]) + float(n[1]) + 0.05)
	var total := int(dur * MIX_RATE)
	var samples: Array = []
	samples.resize(total)
	samples.fill(0.0)
	for n in notes:
		if str(n[2]) == "n":
			_mix_noise(samples, float(n[0]), float(n[1]), float(n[3]), float(n[4]))
		else:
			_mix_note(samples, float(n[0]), float(n[1]), str(n[2]), float(n[3]), float(n[4]))
	# 峰值归一：先量这条音效自己有多高，再按家族目标缩放。
	# 短促的点击（tap 只有 0.06 秒）和 1.2 秒的 fanfare 用同一组 vol 数字，
	# 不归一的话"谁更响"完全取决于当初手滑写了 0.08 还是 0.12。
	var peak := 0.0
	for i in total:
		peak = maxf(peak, absf(float(samples[i])))
	if peak > 0.0001:
		var g := target_peak(name) / peak
		for i in total:
			samples[i] = float(samples[i]) * g
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		var v: float = clampf(float(samples[i]), -1.0, 1.0)
		var s := int(round(v * 32767.0))
		if s < 0:
			s += 65536
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav

func _mix_note(samples: Array, freq: float, dur: float, wave: String, vol: float, delay: float) -> void:
	var start := int(delay * MIX_RATE)
	var count := int(dur * MIX_RATE)
	var attack := maxi(1, int(0.012 * MIX_RATE))
	for i in count:
		var idx := start + i
		if idx >= samples.size():
			break
		var t := float(i) / float(MIX_RATE)
		var phase := fmod(freq * t, 1.0)
		var s := 0.0
		match wave:
			"tri":
				s = 4.0 * absf(phase - 0.5) - 1.0
			"sq":
				s = 1.0 if phase < 0.5 else -1.0
			"saw":
				s = phase * 2.0 - 1.0
			_:
				s = sin(phase * TAU)
		var env := 1.0
		if i < attack:
			env = float(i) / float(attack)
		else:
			var k := float(i - attack) / maxf(1.0, float(count - attack))
			env = pow(0.0001, k)
		samples[idx] = float(samples[idx]) + s * env * vol

## 噪声通道：白噪声过一阶低通（freq 就是截止频率），指数衰减。
## 风声/油锅/木头闷响都得靠它，纯振荡器做不出"没有音高"的声音。
func _mix_noise(samples: Array, cutoff: float, dur: float, vol: float, delay: float) -> void:
	var start := int(delay * MIX_RATE)
	var count := maxi(1, int(dur * MIX_RATE))
	var k := clampf(TAU * cutoff / MIX_RATE, 0.0002, 1.0)
	var a := 0.0
	var b := 0.0
	for i in count:
		var idx := start + i
		if idx >= samples.size():
			break
		var white := randf() * 2.0 - 1.0
		a += (white - a) * k
		b += (a - b) * k
		var t := float(i) / float(count)
		var env := pow(0.0025, t)
		if i < 66:
			env *= float(i) / 66.0
		samples[idx] = float(samples[idx]) + b * env * vol * 1.7
