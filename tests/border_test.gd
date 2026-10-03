extends Node
## 边界/压力测试：
##   godot --headless --path <项目> -- --test=border
## 覆盖：狂点、覆盖层连开、顾客堆积、中途退出重进、零库存零金币、保存一致性、
##   页边翻页、暂停里重看引导、HUD 六枚圆钮各有后果、抛币拾取、章与章之间的真实点击跳转。

var main: Node
var fails: Array = []
var passes := 0
var checks := 0

var _save_bak := ""
var _ledger_bak := ""
var _had_save := false
var _had_ledger := false

func run(m: Node) -> void:
	main = m
	print("============ BORDER TEST START ============")
	_backup_saves()
	GameState.reset_for_new_game()
	await _t_rapid_clicks()
	await _t_overlay_spam()
	await _t_pileup()
	await _t_midday_exit()
	await _t_zero_stock()
	await _t_save_consistency()
	await _t_broke_buy()
	await _t_page_edges()
	await _t_replay_tutorial()
	await _t_hud_buttons()
	await _t_coin_pickup()
	await _t_chapter_transition()
	_restore_saves()
	# 退出前清理：关闭覆盖层并等待一帧，确保 queue_free 生效
	if main.overlay != null:
		main.close_overlay()
	await _frames(3)
	print("============ RESULT ============")
	print("checks=%d passed=%d failed=%d" % [checks, passes, fails.size()])
	for f in fails:
		print("FAIL: ", f)
	if fails.is_empty():
		print("BORDER: ALL PASS")
		get_tree().quit(0)
	else:
		print("BORDER: FAIL")
		get_tree().quit(1)

func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("CHECK FAILED: ", label)

# ---------------- 1) 狂点 ----------------
func _t_rapid_clicks() -> void:
	main.goto("play", {"fresh": true})
	await _frames(3)
	var play = main.screens.get("play")
	if play == null:
		fails.append("play missing in rapid clicks")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 500:
		var pos := Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
		_click(pos)
		if i % 25 == 0:
			await _frames(1)
	await _frames(30)
	var ok := true
	for k in GameState.inventory.keys():
		if GameState.inv_count(str(k)) < 0:
			ok = false
	check(ok, "inventory >= 0 after 500 rapid clicks")
	check(play.sim.fire >= 0.0 and play.sim.fire <= float(Config.fire.get("fire_max", 100.0)) + 0.01, "fire bounded after rapid clicks")
	check(play.sim.wood >= 0 and play.sim.wood <= int(Config.fire.get("wood_max", 10)), "wood bounded after rapid clicks")
	check(true, "500 rapid clicks without crash")

# ---------------- 2) 覆盖层连开 ----------------
func _t_overlay_spam() -> void:
	var play = main.screens.get("play")
	if play == null:
		fails.append("play missing in overlay spam")
		return
	for i in 15:
		play._activate({"id": "truck"}, Vector2.ZERO)
		await _frames(1)
		main.close_overlay()
		await _frames(1)
	for i in 15:
		play._activate({"id": "menu"}, Vector2.ZERO)
		await _frames(1)
		main.close_overlay()
		await _frames(1)
	for i in 8:
		play._activate({"id": "pause"}, Vector2.ZERO)
		await _frames(1)
		play.resume_game()
		main.close_overlay()
		await _frames(1)
	check(main.overlay == null, "no overlay left open after spam")
	# 劈柴面板狂点
	play._activate({"id": "fire_chop"}, Vector2.ZERO)
	await _frames(2)
	var spammed := 0
	if main.overlay != null and main.overlay.has_method("press_at"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 40:
			# 引用每轮重取：三轮打完面板会自己 close()，攥着旧对象再按就变成对 freed 实例调方法，
			# 之前这里就是在第 4 击上炸出一句 SCRIPT ERROR，而这条 check 照样报绿
			var ov = main.overlay
			if ov == null or not ov.has_method("press_at"):
				break
			ov.press_at(rng.randf())
			spammed += 1
			await _frames(1)
	print("[border] 劈柴面板连打实收 ", spammed, " 击")
	check(spammed >= 3, "劈柴面板至少要能吃满三轮点击（实收 %d 击）" % spammed)
	await _wait(2.0)
	if main.overlay != null:
		main.close_overlay()
	check(true, "chop overlay spam without crash")

# ---------------- 3) 顾客堆积 ----------------
func _t_pileup() -> void:
	var sim := DaySim.new()
	sim.start(6, 1234)
	var max_c := int(Config.economy.get("spawn", {}).get("max_concurrent", 3))
	var ok := true
	var t := 0.0
	while t < 420.0 and not sim.finished:
		sim.tick(0.05)
		t += 0.05
		if sim.queue.size() > max_c:
			ok = false
			break
	check(ok, "concurrent customers stay <= %d during pileup" % max_c)
	check(sim.finished, "day 6 finishes when nobody is served")
	check(sim.served == 0 and sim.missed == sim.total_plan(), "all customers walk out when unserved (%d/%d)" % [sim.missed, sim.total_plan()])
	check(t < 420.0, "pileup resolves within time limit")

# ---------------- 4) 中途退出重进 ----------------
func _t_midday_exit() -> void:
	GameState.reset_for_new_game()
	GameState.coins = 66
	SaveManager.save_all()
	main.goto("play", {"fresh": true})
	await _frames(2)
	var play = main.screens.get("play")
	var bot = load("res://tests/sim_bot.gd").new()
	bot.sim = play.sim
	for i in 200:
		bot.step(0.05)
		await _frames(1)
	# 模拟“回标题退出”再进入
	main.goto("title")
	await _frames(2)
	check(str(main.current_name) == "title", "back to title ok")
	main.goto("play", {"fresh": true})
	await _frames(2)
	check(main.screens.get("play").sim != null, "re-enter play creates fresh sim")
	var coins_now := GameState.coins
	var day_now := GameState.day
	SaveManager.load_all()
	check(GameState.coins == coins_now and GameState.day == day_now, "coins/day stable across exit & re-enter")

# ---------------- 5) 零库存零金币 ----------------
func _t_zero_stock() -> void:
	GameState.reset_for_new_game()
	for k in GameState.inventory.keys():
		GameState.inventory[k] = 0
	GameState.coins = 0
	var sim := DaySim.new()
	sim.start(1, 555)
	for i in 300:
		sim.tap_grill(0)
		sim.tap_grill(1)
		sim.tap_fryer()
		sim.tap_drink()
		sim.tap_shelf("bun")
		sim.tap_shelf("patty")
		sim.tick(0.05)
	var ok := true
	for k in GameState.inventory.keys():
		if GameState.inv_count(str(k)) < 0:
			ok = false
	check(ok, "inventory >= 0 with empty stock spam")
	check(not GameState.buy_ingredient("patty", 5, 1.0), "buy fails with 0 coins")
	check(not GameState.buy_ingredient("patty", 5, 1.5), "emergency buy fails with 0 coins")
	check(GameState.coins == 0, "coins untouched by failed buys")

# ---------------- 6) 保存一致性 ----------------
func _t_save_consistency() -> void:
	GameState.coins = 123
	GameState.day = 2
	GameState.best_combo = 4
	SaveManager.save_all()
	var saved := FileAccess.get_file_as_string(SaveManager.save_path())
	check(saved.length() > 0, "save file non-empty")
	var parsed = JSON.parse_string(saved)
	check(typeof(parsed) == TYPE_DICTIONARY, "save file is valid JSON")
	if typeof(parsed) == TYPE_DICTIONARY:
		check(int(parsed.get("player", {}).get("coins", -1)) == 123, "save file coins=123")
	var ledger := FileAccess.get_file_as_string(SaveManager.ledger_path())
	var lparsed = JSON.parse_string(ledger)
	check(typeof(lparsed) == TYPE_DICTIONARY, "ledger file is valid JSON")

# ---------------- 工具 ----------------
## 钱不够时的购买必须自己开口，而且要**走真实输入层点按钮**去测：
## 直接调 buy_ingredient() 只能证明它返回 false，证明不了界面有没有吭声
## （可乐那次"经济闸门查不到 UI 断链"就是同一个道理）。
func _t_broke_buy() -> void:
	GameState.reset_for_new_game()
	GameState.coins = 0
	main.goto("shop", {})
	await _frames(3)
	var shop = main.screens.get("shop")
	if shop == null:
		fails.append("商店屏没拿到，买不起反馈整条没测")
		return
	var tried := 0
	# 1) 食材页 +1
	var c := _hit_center(shop, "b1:")
	if c.x < 0.0:
		fails.append("商店食材页没有 +1 热区")
	else:
		tried += 1
		shop.msg = ""
		_click(c)
		await _frames(2)
		check(str(shop.msg) != "", "商店买食材买不起时说了「%s」" % str(shop.msg))
	# 2) 升级页整卡热区
	_click(_hit_center(shop, "tab:1"))
	await _frames(3)
	var uc := _hit_center(shop, "up:")
	if uc.x < 0.0:
		fails.append("升级页没有可点的升级卡（reset 之后应该全没拥有）")
	else:
		tried += 1
		shop.msg = ""
		_click(uc)
		await _frames(2)
		check(str(shop.msg) != "", "商店买升级买不起时说了「%s」" % str(shop.msg))
	check(tried == 2, "商店这条闸实到 %d 个页签（应为 2），少了等于有的分支没跑" % tried)
	# 3) 卡车紧急补货
	main.goto("play", {"fresh": true})
	await _frames(3)
	var play = main.screens.get("play")
	if play == null:
		fails.append("play 屏没拿到，卡车买不起反馈没测")
		return
	play._activate({"id": "truck"}, Vector2.ZERO)
	await _frames(3)
	var ov = main.overlay
	if ov == null:
		fails.append("卡车面板没开起来")
		return
	var tc := _hit_center(ov, "b1:")
	if tc.x < 0.0:
		fails.append("卡车面板上没有 +1 热区")
	else:
		ov.msg = ""
		_click(tc)
		await _frames(2)
		check(str(ov.msg) != "", "卡车买不起时说了「%s」" % str(ov.msg))
	main.close_overlay()
	await _frames(2)

## 翻页到头：页边那一侧的箭头只是画灰了，热区一直都在。点它过去只响一声 tap、
## page 加出界再被下一帧的 clamp 悄悄修回来，画面纹丝不动——玩家听到的那一声
## "点中了"就是假的。走真实输入层点，要求 page 原地不动且界面把原因说出来。
func _t_page_edges() -> void:
	GameState.reset_for_new_game()
	main.goto("shop", {})
	await _frames(3)
	var shop = main.screens.get("shop")
	if shop == null:
		fails.append("商店屏没拿到，翻页页边整条没测")
		return
	var pc := int(shop.call("_page_count"))
	print("[page] 进店 tab=%d page=%d，当前页签共 %d 页" % [int(shop.tab), int(shop.page), pc])
	check(int(shop.tab) == 0 and int(shop.page) == 0, "进店应落在食材页第一页")
	if pc < 2:
		fails.append("页签 0 只有 %d 页，页边用例根本没地方跑（需要 >=2 页）" % pc)
		return
	var left := _hit_center(shop, "pg:-1")
	var right := _hit_center(shop, "pg:1")
	if left.x < 0.0 or right.x < 0.0:
		fails.append("翻页箭头热区没挂上（左 %.0f 右 %.0f）" % [left.x, right.x])
		return
	print("[page] main.current=%s 取到的就是它=%s" % [str(main.current_name), str(main.current == shop)])
	# 首页往回翻
	shop.msg = ""
	_click(left)
	await _frames(2)
	var held_l := int(shop.page) == 0
	var spoke_l := str(shop.msg) != ""
	check(held_l, "首页点左箭头后 page=%d，应为 0" % int(shop.page))
	check(spoke_l, "首页点左箭头说了「%s」" % str(shop.msg))
	# 翻到末页
	for i in pc - 1:
		_click(right)
		await _frames(2)
	check(int(shop.page) == pc - 1, "连翻 %d 次后落在末页 page=%d" % [pc - 1, int(shop.page)])
	shop.msg = ""
	_click(right)
	await _frames(2)
	var held_r := int(shop.page) == pc - 1
	var spoke_r := str(shop.msg) != ""
	check(held_r, "末页点右箭头后 page=%d，应为 %d" % [int(shop.page), pc - 1])
	check(spoke_r, "末页点右箭头说了「%s」" % str(shop.msg))
	# 计数全来自上面实测的四个量，不写死"都成功了"——上一版这里无条件打印
	# "两侧都开了口"，注入回归把那三条 check 打红了，这句还在报喜。
	print("[page] 共 %d 页，页边两侧各点 1 次：page 原地留住 %d/2、开口 %d/2" % [
		pc, int(held_l) + int(held_r), int(spoke_l) + int(spoke_r)])

func _hit_center(scr, pfx: String) -> Vector2:
	for h in scr._hits:
		var hd: Dictionary = h
		if not str(hd.get("id", "")).begins_with(pfx):
			continue
		var r: Rect2 = hd.get("rect", Rect2())
		if r.size.x > 0.0 and r.size.y > 0.0:
			return r.get_center()
	return Vector2(-1.0, -1.0)

## 「重看引导」以前点了只是把暂停菜单关掉：restart_tutorial 走的闸是"已有覆盖层就不开"，
## 而它是在 close() 之前调的。这条走真实输入层点那颗按钮，要求教学层真的盖出来；
## 顺带验另一头——开场的 0.6s 延迟定时器不能在别的屏上把教学盖出来（实测盖到商店上，
## 把商店的点击整条吃掉过：border 里连点三下只到一下）。
func _t_replay_tutorial() -> void:
	GameState.reset_for_new_game()
	GameState.tut_done = true
	main.goto("play", {"fresh": true})
	await _frames(4)
	var play = main.screens.get("play")
	if play == null:
		fails.append("play 屏没拿到，重看引导整条没测")
		return
	# 上一段用例进 play 时挂的 0.6s 教学定时器可能这会儿才落地；open_overlay 在
	# "已经有覆盖层"时是直接 return 的，那样我下面点的就不是暂停面板了（包内实测中过）。
	await _wait(0.85)
	if main.has_overlay():
		main.close_overlay()
		await _frames(2)
	play._activate({"id": "pause"}, Vector2.ZERO)
	await _frames(3)
	var ov = main.overlay
	if ov == null:
		fails.append("暂停面板没开起来，重看引导没测")
		return
	if not str((ov as Node).get_script().resource_path).ends_with("ov_pause.gd"):
		fails.append("要点的是暂停面板，结果当前覆盖层是 %s（多半是别的定时器插进来了）" % str((ov as Node).get_script().resource_path))
		return
	var tc := _hit_center(ov, "tutorial")
	if tc.x < 0.0:
		fails.append("暂停面板上没有「重看引导」热区")
		return
	_click(tc)
	await _frames(3)
	var after = main.overlay
	# opened 当场就取好：close_overlay() 之后 after 指向的是已释放实例，
	# 再写 after != null 会读到 false，一个通过的用例反而报成"没开"。
	var opened := after != null
	check(opened, "点「重看引导」后教学层真的开起来了（overlay=%s）" % str(after))
	if after != null:
		var sp := str((after as Node).get_script().resource_path)
		check(sp.ends_with("ov_tutorial.gd"), "开起来的是教学层，实得 %s" % sp.get_file())
		main.close_overlay()
		await _frames(2)
	# 延迟定时器落晚了的场景：此刻人已经在商店，教学不该盖出来
	GameState.tut_done = false
	main.goto("shop", {})
	await _frames(3)
	play.call("_open_tut_anim")
	await _frames(2)
	check(not main.has_overlay(), "人在商店时教学开层动作不该盖出面板")
	print("[tutorial] 重看引导 1 次点击 → 教学层 %s；商店里补放 1 次 → 覆盖层 %s" % [
		"开出来了" if opened else "没开", str(main.has_overlay())])

## HUD 右上那排圆钮里有一枚从来没有人处理：`_activate` 的 match 没有 "records" 这一支，
## 点它既不出声也不换屏，而它和旁边五枚长得一模一样、悬停说明还写着"营业台账"。
## 已有的两条闸都看不见它——热区扫描只判几何，tip 闸只判"说不说得出说明"。
## 所以这条按"每枚都必须留下可观察后果"来判，六枚各查一种后果。
func _t_hud_buttons() -> void:
	GameState.reset_for_new_game()
	GameState.tut_done = true
	main.goto("play", {"fresh": true})
	await _frames(4)
	if main.has_overlay():
		main.close_overlay()
		await _frames(2)
	var play = main.screens.get("play")
	if play == null:
		fails.append("play 屏没拿到，HUD 六枚圆钮整条没测")
		return
	# 同上：等那颗 0.6s 教学定时器落地再开测，否则它会把 HUD 的点击整条吞掉
	await _wait(0.85)
	if main.has_overlay():
		main.close_overlay()
		await _frames(2)
	var ids: Array = ["bin", "truck", "menu", "pause", "records", "sound"]
	var missing := ""
	for id in ids:
		if _hit_center(play, str(id)).x < 0.0:
			missing += str(id) + " "
	check(missing == "", "HUD 圆钮的热区没挂上：%s" % missing)
	if missing != "":
		return
	var done: Array = []
	# ① 倒掉：盘是空的，也得说一句
	play.snark_text = ""
	_click(_hit_center(play, "bin"))
	await _frames(2)
	if str(play.snark_text) != "":
		done.append("bin")
	# ② 声音：静音位要真的翻过去
	var muted0 := GameState.muted
	_click(_hit_center(play, "sound"))
	await _frames(2)
	if GameState.muted != muted0:
		done.append("sound")
	GameState.muted = muted0
	# ③④ 卡车 / 图鉴：要盖出自己那块面板
	for pair in [["truck", "ov_truck.gd"], ["menu", "ov_menu.gd"]]:
		_click(_hit_center(play, str(pair[0])))
		await _frames(3)
		var ov = main.overlay
		if ov != null and str((ov as Node).get_script().resource_path).ends_with(str(pair[1])):
			done.append(str(pair[0]))
		main.close_overlay()
		await _frames(2)
	# ⑤ 暂停：面板盖出来，而且当天真的冻住了
	_click(_hit_center(play, "pause"))
	await _frames(3)
	if main.overlay != null and bool(play.paused):
		done.append("pause")
	main.close_overlay()
	play.resume_game()
	await _frames(2)
	# ⑥ 台账：整屏换得过去，返回还要回到同一天（sim 没被重建）
	_click(_hit_center(play, "records"))
	await _frames(3)
	if str(main.current_name) == "records":
		var sim_before = play.sim
		_click(_hit_center(main.current, "back"))
		await _frames(3)
		check(str(main.current_name) == "play", "从 HUD 进台账再返回，落点是 %s，应为 play" % str(main.current_name))
		check(play.sim == sim_before, "返回后还是那一天的进程，没被重开")
		done.append("records")
	print("[hud] 六枚圆钮各查一种后果，实到反应的 %d/6：%s" % [done.size(), ", ".join(PackedStringArray(done))])
	check(done.size() == 6, "HUD 圆钮里有 %d 枚点了没任何反应（应 6 枚全活）" % (6 - done.size()))

## 划过拾取是**视图层**的接线：sim 侧的账 smoke 已经钉死了，这里要证的是
## "鼠标滑过去真的会捡起来"，以及"暂停/覆盖层开着时不许偷偷捡钱"。
func _t_coin_pickup() -> void:
	GameState.reset_for_new_game()
	GameState.tut_done = true
	main.goto("play", {"fresh": true})
	await _frames(4)
	if main.has_overlay():
		main.close_overlay()
		await _frames(2)
	var play = main.screens.get("play")
	if play == null:
		fails.append("play 屏没拿到，划过拾取整条没测")
		return
	play.sim.toss_coins(23)
	await _frames(2)
	var n0: int = play.sim.coins.size()
	var c0 := GameState.coins
	print("[coinpick] 抛出 23 → 台面 %d 枚，钱包 %d" % [n0, c0])
	if n0 == 0:
		fails.append("抛币后台面是空的，拾取用例没地方跑")
		return
	var W: float = play._vp().x
	var H: float = play._vp().y
	var cd: Dictionary = play.sim.coins[0]
	var pos := Vector2(float(cd["x"]) * W, float(cd["y"]) * H)
	# 覆盖层开着的时候不许捡（is_paused 挡住）：先验这条，再验正常那条
	play._activate({"id": "pause"}, Vector2.ZERO)
	await _frames(3)
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	main._unhandled_input(mv)
	await _frames(4)
	check(int(play.sim.coins.size()) == n0, "暂停面板开着时划过硬币，居然也捡了（%d→%d）" % [n0, play.sim.coins.size()])
	main.close_overlay()
	play.resume_game()
	await _frames(3)
	var mv2 := InputEventMouseMotion.new()
	mv2.position = pos
	main._unhandled_input(mv2)
	await _frames(4)
	var n1 := int(play.sim.coins.size())
	check(n1 == n0 - 1, "划过硬币应当少一枚：%d → %d" % [n0, n1])
	check(GameState.coins > c0, "拾到的钱进了钱包：+%d" % (GameState.coins - c0))
	# 剩下的全部滑一遍捡干净，验"一枚不落"
	for k in range(n1):
		var cd2: Dictionary = play.sim.coins[0]
		var p2 := Vector2(float(cd2["x"]) * W, float(cd2["y"]) * H)
		var mv3 := InputEventMouseMotion.new()
		mv3.position = p2
		main._unhandled_input(mv3)
		await _frames(2)
	print("[coinpick] 逐个划过之后：台面剩 %d 枚，钱包 +%d" % [play.sim.coins.size(), GameState.coins - c0])
	check(play.sim.coins.is_empty(), "逐枚划过应当捡干净，实剩 %d 枚" % play.sim.coins.size())
	check(GameState.coins - c0 == 23, "23 枚面额应全进钱包，实收 %d" % (GameState.coins - c0))

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _click(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	main._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	main._unhandled_input(up)

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

## 章与章之间那一跳是第二十一章新接的线：第 7 天结算 → 章末页 → 点「进入第二章」
## → 章开场剧情 → after_chapter_intro → advance_day → 第 8 天商店。
## autotest 是把这几屏**分别摆出来**拍的，谁也没被点过；这条走真实点击，
## 判的是"点了真的走到下一章"，顺带守住 ending_chapter（不记的话 endless 里每天重弹章末页）。
func _t_chapter_transition() -> void:
	GameState.reset_for_new_game()
	GameState.tut_done = true
	GameState.day = Config.chapter_end_day(1)
	GameState.ending_chapter = 0
	main.after_day_settled({"day": GameState.day, "served": 8, "missed": 0}, [], 0)
	await _frames(4)
	if str(main.current_name) != "ending":
		fails.append("第 %d 天结算没走章末页，实得 %s（后面整条没测）" % [GameState.day, str(main.current_name)])
		return
	var end = main.current
	check(str(end.mode) == "chapter", "章末页 mode 该是 chapter，实得 %s" % str(end.mode))
	check(int(end.chapter) == 1, "章末页该停在第一章，实得 %d" % int(end.chapter))
	check(int(GameState.ending_chapter) == 1, "章末页没记下走到过第 1 章（endless 里会天天重弹）")
	var cc := _hit_center(end, "continue")
	if cc.x < 0.0:
		fails.append("章末页上没有「进入下一章」热区，跳转整条没测")
		return
	_click(cc)
	await _frames(4)
	if str(main.current_name) != "story":
		fails.append("点「进入第二章」没放出章开场剧情，实得 %s" % str(main.current_name))
		return
	var st = main.current
	check(str(st.scene_type) == "chapter", "该开 chapter 分支，实得 scene=%s" % str(st.scene_type))
	# 少于两句就测不出"一路点到放完"这个循环，等于白跑
	check(st.lines.size() >= 2, "章开场剧情只有 %d 句，推进循环没测到东西" % st.lines.size())
	var guard := 0
	while str(main.current_name) == "story" and guard < 40:
		_click(Vector2(640, 360))
		await _wait(0.12)
		guard += 1
	check(str(main.current_name) != "story", "点了 %d 下章开场剧情还没放完（on_done 没接上？）" % guard)
	check(int(GameState.day) == Config.chapter_start_day(2),
		"放完开场剧情没进第二章第一天：day=%d 应为 %d" % [GameState.day, Config.chapter_start_day(2)])
	check(str(main.current_name) == "shop", "advance_day 该落到商店，实得 %s" % str(main.current_name))
	print("[chapter] 第 %d 天结算 → 章末页(ch%s) → 点「进入第二章」→ 剧情 %d 句 / 点了 %d 下 → day=%d / %s" % [
		Config.chapter_end_day(1), str(end.chapter), st.lines.size(), guard, GameState.day, str(main.current_name)])

