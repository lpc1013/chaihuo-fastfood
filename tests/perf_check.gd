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
	var worst_goto := 0
	for s in SCREENS:
		var t0 := Time.get_ticks_msec()
		main.goto(s, {"fresh": true} if s == "play" else {})
		await get_tree().process_frame
		await get_tree().process_frame
		var dt := Time.get_ticks_msec() - t0
		worst_goto = maxi(worst_goto, dt)
		print("[goto] %-8s %4d ms" % [s, dt])
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
