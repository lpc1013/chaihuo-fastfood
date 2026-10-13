extends Node
## 截图工具（窗口化跑）：godot --path <项目> -- --test=shot
## 进营业屏并等两帧后截一张图，用来人眼确认工位布局/热区改动没有把画面弄乱。
func run(m: Node) -> void:
	var main: Node = m
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.reset_for_new_game()
	GameState.add_coins(500)
	main.goto("play", {"fresh": true})
	# 造出满负荷画面：几个客人 + 炉子都在跑
	var play
	for i in 60:
		await get_tree().process_frame
		if main.screens.has("play"):
			play = main.screens.get("play")
			if play != null and play.sim != null:
				break
	if play != null:
		for i in 3:
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
	for i in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var dir := "res://screenshots/layout_check"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/play_layout.png"
	var err := img.save_png(path)
	print("SHOT %s err=%d" % [path, err])
	get_tree().quit(0)
