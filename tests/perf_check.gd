extends Node
## 性能实测（窗口化跑）：
##   E:/godot/Godot_v4.7.2-stable_win64_console.exe --path E:/restauran -- --test=perf
## 报三件事，每件都带一条阈值，超了就红：
##   ① 开机到自检脚本开跑的毫秒数（autoload 全在里面）
##   ② 每个界面换屏耗时（载场景 + on_enter + 首帧）
##   ③ play 屏最忙状态下，_draw 各段每帧多少微秒
## 之所以要分段：soak 报 60fps 只证明"没掉帧"，不证明余量有多少。

var main: Node
var fails: Array = []

## day_end / ending 要带结算数据才画得出来，硬 goto 会抛错污染这一趟，故不在列
const SCREENS := ["title", "shop", "play", "map", "help", "records"]

const BOOT_MS_MAX := 6000
const GOTO_MS_MAX := 1500
const DRAW_US_MAX := 9000.0

func run(m: Node) -> void:
	main = m
	print("============ PERF START ============")
	var boot := Time.get_ticks_msec()
	print("[boot] 自检脚本开跑时引擎已起 %d ms（Config/GameState/SaveManager/Sfx/Music 五个 autoload 都在里面）" % boot)
	if boot > BOOT_MS_MAX:
		fails.append("开机 %d ms 超过 %d" % [boot, BOOT_MS_MAX])
	Sfx.set_muted(true)
	GameState.reset_for_new_game()
	GameState.add_coins(5000)
	GameState.day = 5
	# 预热：goto 的第一次进屏包含 GDScript 编译 + 场景实例化 + 贴图首次载入，
	# 是每会话一次的冷启动成本（实测 play 首进 ~1.4s、热进 ~15ms），不是"换屏耗时"。
	# 把它算进阈值只会永远红，且掩盖真正的热切换回归——所以先各进一遍再正式计时。
	# 冷启动数只打点、不判红：它是引擎编译成本，不是我们能改的东西，硬卡没意义。
	for s in SCREENS:
		var c0 := Time.get_ticks_msec()
		main.goto(s, {"fresh": true} if s == "play" else {})
		await get_tree().process_frame
		print("[goto-cold] %-8s %4d ms" % [s, Time.get_ticks_msec() - c0])
	var worst_goto := 0
	for s in SCREENS:
		var t0 := Time.get_ticks_msec()
		main.goto(s, {"fresh": true} if s == "play" else {})
		await get_tree().process_frame
		await get_tree().process_frame
		var dt := Time.get_ticks_msec() - t0
		worst_goto = maxi(worst_goto, dt)
		print("[goto] %-8s %4d ms（热）" % [s, dt])
	if worst_goto > GOTO_MS_MAX:
		fails.append("最贵的一次换屏 %d ms 超过 %d" % [worst_goto, GOTO_MS_MAX])
	await _busy_draw_probe()
	print("============ PERF RESULT ============")
	if fails.is_empty():
		print("PERF: ALL PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("FAIL: ", f)
		print("PERF: FAIL")
		get_tree().quit(1)

## 把 play 屏塞到最忙：4 个客人带小票、三个炉子都在跑、托盘满、柴火旺
func _busy_draw_probe() -> void:
	main.goto("play", {"fresh": true})
	await get_tree().process_frame
	var play = main.screens.get("play")
	if play == null:
		fails.append("perf 拿不到 play 屏")
		return
	play.paused = false
	for i in 4:
		play.sim._spawn_customer()
	for c in play.sim.queue:
		c.state = "waiting"
		c.walk_t = 99.0
	play.sim.wood = 8
	play.sim.fire = 90.0
	GameState.inv_add("patty", 24)
	GameState.inv_add("potato", 24)
	GameState.inv_add("drink", 24)
	play.sim.tap_grill(0)
	play.sim.tap_fryer()
	play.sim.tap_drink(0)
	play.sim.tray = {"burger": 0, "fries": true, "drink": "cola"}
	play.perf_acc = {}
	play.perf_frames = 0
	play.perf_probe = true
	var frames := 180
	var t0 := Time.get_ticks_msec()
	for i in frames:
		await get_tree().process_frame
	var wall := Time.get_ticks_msec() - t0
	play.perf_probe = false
	var nf := maxi(play.perf_frames, 1)
	print("[draw] %d 帧 / %d ms = %.2f ms 每帧（vsync 目标 16.67），进探针 %d 帧"
		% [frames, wall, float(wall) / float(frames), play.perf_frames])
	var rows: Array = []
	var seg_sum := 0.0
	for k in play.perf_acc.keys():
		if str(k) == "total":
			continue
		var v := float(play.perf_acc[k]) / float(nf)
		seg_sum += v
		rows.append([str(k), v])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for r in rows:
		print("   %-14s %7.1f us/帧" % [r[0], r[1]])
	var total := float(play.perf_acc.get("total", 0)) / float(nf)
	print("   %-14s %7.1f us/帧（分段之和 %.1f，差的是 ly()/热区登记等未分段部分）" % ["total", total, seg_sum])
	if total > DRAW_US_MAX:
		fails.append("play 屏 _draw total %.1f us/帧 超过 %.0f" % [total, DRAW_US_MAX])
	# 审计问题 08：整屏逐帧重绘是"潜在"成本，必须用实测决定值不值得改渲染路线。
	# 下面按审计给的四类场景各测一遍，并把空闲帧与忙帧的差额算出来——
	# 若空闲帧的绘制成本也接近忙帧，说明静态重绘在被无谓地烧掉，才有优化理由。
	await _scenario_probe("普通营业", 0, 0)
	await _scenario_probe("满负荷", 4, 0)
	await _scenario_probe("关动画（满负荷）", 4, 1)
	await _long_run_memory()
	# ly() 是每帧预算的一部分（审计问题 07 的布局计算），单独量一下它自身的成本
	await _layout_cost_probe()

## 一个绘制场景：n_cust 位满客、anim_off 时关掉飘字/抖动/动画，测 play 屏每帧 _draw 微秒。
func _scenario_probe(tag: String, n_cust: int, anim_off: int) -> void:
	main.goto("play", {"fresh": true})
	await get_tree().process_frame
	var play = main.screens.get("play")
	if play == null:
		fails.append("perf 场景「%s」拿不到 play 屏" % tag)
		return
	play.paused = false
	for i in n_cust:
		play.sim._spawn_customer()
	for c in play.sim.queue:
		c.state = "waiting"
		c.walk_t = 99.0
	play.sim.wood = 8
	play.sim.fire = 90.0
	GameState.inv_add("patty", 24)
	GameState.inv_add("potato", 24)
	GameState.inv_add("drink", 24)
	if n_cust > 0:
		play.sim.tap_grill(0)
		play.sim.tap_fryer()
		play.sim.tap_drink(0)
		play.sim.tray = {"burger": 0, "fries": true, "drink": "cola"}
	# 关动画档：清空所有飘字/抖动/案板特效，测"纯静态重绘"的下限。
	# 注意：不能 set_process(false)——探针的计时在 _process 里累加，停了就没帧数。
	# 静态重绘的语义是"没有动画数据参与绘制"，不是"不跑 _process"。
	if anim_off == 1:
		play.popups = []
		play.board_fx = []
		play.sauce_fx = []
		play.snark_text = ""
		play.snark_t = 0.0
		play.shake_t = 0.0
	play.perf_acc = {}
	play.perf_frames = 0
	play.perf_probe = true
	var frames := 150
	for i in frames:
		await get_tree().process_frame
	play.perf_probe = false
	var nf := maxi(play.perf_frames, 1)
	var total := float(play.perf_acc.get("total", 0)) / float(nf)
	print("[scenario] %-16s 客人=%d 关动画=%d → _draw %.1f us/帧（进探针 %d 帧）" % [tag, n_cust, anim_off, total, play.perf_frames])
	if total > DRAW_US_MAX:
		fails.append("场景「%s」_draw %.1f us/帧 超过 %.0f" % [tag, total, DRAW_US_MAX])
	if anim_off == 1 and total > DRAW_US_MAX * 0.9:
		fails.append("关掉动画后仍有 %.1f us/帧：静态重绘本身就很贵，值得考虑脏矩形/缓存" % total)

## 长时间运行：反复进出 play 屏，观察内存与帧时间是否持续增长（审计问题 08 的"长时间运行"项）。
func _long_run_memory() -> void:
	var mem0 := OS.get_static_memory_usage()
	var f0 := Engine.get_frames_per_second()
	for i in 6:
		main.goto("play", {"fresh": true})
		for j in 30:
			await get_tree().process_frame
		main.goto("shop", {})
		for j in 10:
			await get_tree().process_frame
	var mem1 := OS.get_static_memory_usage()
	var f1 := Engine.get_frames_per_second()
	var grow := 0.0 if mem0 == 0 else float(mem1 - mem0) / float(mem0) * 100.0
	print("[longrun] 6 轮进出 play：静态内存 %.1f MB → %.1f MB（%+.2f%%），fps %d → %d" % [
		float(mem0) / 1048576.0, float(mem1) / 1048576.0, grow, f0, f1])
	if grow > 25.0:
		fails.append("6 轮进出 play 后静态内存增长 %.1f%%（>25%%），疑似泄漏" % grow)

## 单独量 ly()（PlayLayout.compute）的成本：审计问题 07 关心它是不是每帧开销的大头。
func _layout_cost_probe() -> void:
	var play = main.screens.get("play")
	if play == null:
		fails.append("布局成本探针拿不到 play 屏")
		return
	var vp: Vector2 = play._vp()
	var n := 20000
	var t0 := Time.get_ticks_usec()
	for i in n:
		PlayLayout.compute(vp)
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	print("[layout] PlayLayout.compute 单次 %.3f us（%d 次合计 %.1f ms）" % [us, n, float(Time.get_ticks_usec() - t0) / 1000.0])
	if us > 50.0:
		fails.append("PlayLayout.compute 单次 %.3f us 偏贵（>50us），每帧预算会被吃掉" % us)
