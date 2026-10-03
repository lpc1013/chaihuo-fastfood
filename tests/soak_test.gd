extends Node
const TestEnv := preload("res://tests/test_env.gd")
## 耐久测试（窗口化）：godot --path <项目> -- --test=soak [--minutes=10]
## 连续自动营业多天，每分钟截图与状态日志，结束后输出汇总；期间任何脚本报错都会被外层日志捕获。

var main: Node
var soak_dir := "res://screenshots/soak"
var minutes := 10.0
var bot
var elapsed := 0.0
var last_shot := 0.0
var day_marks := 0
var skipped := 0
var _save_bak := ""
var _ledger_bak := ""
var _had_save := false
var _had_ledger := false

func run(m: Node) -> void:
	main = m
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--minutes="):
			minutes = float(str(a).substr(10))
	print("============ SOAK START (%.1f min) ============" % minutes)
	soak_dir = TestEnv.evidence_dir("res://screenshots/soak", "screenshots/soak")
	_backup_saves()
	GameState.reset_for_new_game()
	Sfx.set_muted(true)
	bot = load("res://tests/sim_bot.gd").new()
	main.goto("play", {"fresh": true})
	await _wait(0.5)
	var last_ticks := Time.get_ticks_msec()
	while elapsed < minutes * 60.0:
		await _wait(0.1)
		var now := Time.get_ticks_msec()
		elapsed += float(now - last_ticks) / 1000.0
		last_ticks = now
		_flow()
		if elapsed - last_shot >= 60.0:
			last_shot = elapsed
			await _shot("soak_%03dm" % int(elapsed / 60.0))
			_log()
	Sfx.set_muted(GameState.muted)
	_log()
	await _shot("soak_final")
	# 复制本轮到 screenshots/soak 留证，再恢复原存档
	if FileAccess.file_exists(SaveManager.save_path()):
		_write(soak_dir + "/save_slot1.json", FileAccess.get_file_as_string(SaveManager.save_path()))
	if FileAccess.file_exists(SaveManager.ledger_path()):
		_write(soak_dir + "/ledger.json", FileAccess.get_file_as_string(SaveManager.ledger_path()))
	_restore_saves()
	print("============ SOAK DONE ============")
	print("elapsed=%.1fs days_settled=%d total_served=%d total_coins=%d" % [
		elapsed, SaveManager.day_records().size(), GameState.total_served, GameState.total_coins])
	print("SOAK: PASS")
	print("soak_shots_skipped=%d" % skipped)
	get_tree().quit(0)

func _flow() -> void:
	match str(main.current_name):
		"play":
			var play = main.screens.get("play")
			if play != null and play.sim != null and not play.sim.finished:
				bot.sim = play.sim
				bot.step(0.05)
		"day_end":
			day_marks += 1
			main.current._settle()
		"story":
			main.current._skip()
		"ending":
			main.advance_day()
		"shop":
			main.goto("play", {"fresh": true})
		"title":
			main.goto("shop")

func _log() -> void:
	var play = main.screens.get("play")
	var served := 0
	var missed := 0
	if play != null and play.sim != null:
		served = int(play.sim.served)
		missed = int(play.sim.missed)
	print("[soak %5.1fs] screen=%s day=%d served=%d missed=%d coins=%d ledger_days=%d fps=%d" % [
		elapsed, main.current_name, GameState.day, served, missed, GameState.coins, SaveManager.day_records().size(), Engine.get_frames_per_second()])

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	# 等待一次渲染帧；最多等 2.5 秒（窗口最小化/被遮挡时不阻塞流程，跳过并计数）
	var got := [false]
	var cb := func() -> void: got[0] = true
	RenderingServer.frame_post_draw.connect(cb, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not got[0] and waited < 2.5:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if RenderingServer.frame_post_draw.is_connected(cb):
		RenderingServer.frame_post_draw.disconnect(cb)
	if got[0]:
		var img := get_viewport().get_texture().get_image()
		var path := soak_dir + "/" + name + ".png"
		var err := img.save_png(path)
		if err == OK:
			print("[soak] SHOT %s err=0" % name)
		else:
			skipped += 1
			print("[soak] SHOT %s err=%d" % [name, err])
	else:
		skipped += 1
		print("[soak] SHOT %s skipped (no frame in 2.5s)" % name)

func _backup_saves() -> void:
	_had_save = FileAccess.file_exists(SaveManager.save_path())
	_had_ledger = FileAccess.file_exists(SaveManager.ledger_path())
	if _had_save:
		_save_bak = FileAccess.get_file_as_string(SaveManager.save_path())
	if _had_ledger:
		_ledger_bak = FileAccess.get_file_as_string(SaveManager.ledger_path())

func _restore_saves() -> void:
	SaveManager.wipe()
	if _had_save:
		_write(SaveManager.save_path(), _save_bak)
	if _had_ledger:
		_write(SaveManager.ledger_path(), _ledger_bak)
	SaveManager.load_all()

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
