extends Node
const TestEnv := preload("res://tests/test_env.gd")
## 自动巡演（窗口化截图版）：
##   godot --path <项目> -- --test=autotest
## 按真实输入路径走：标题 → 开场剧情 → 商店补货 → 营业 → 劈柴/卡车/暂停覆盖层 →
## 日结算 → 神秘客人剧情 → 未完待续 → 第二天商店 → 营业台账；全程截图留证。

var main: Node
var shot_dir := "res://screenshots/autotest"
var fails: Array = []
var shots: Array = []

var _save_bak := ""
var _ledger_bak := ""
var _had_save := false
var _had_ledger := false

func run(m: Node) -> void:
	main = m
	print("============ AUTOTEST START ============")
	shot_dir = TestEnv.evidence_dir("res://screenshots/autotest", "screenshots/autotest")
	_backup_saves()
	GameState.reset_for_new_game()
	Sfx.set_muted(true)
	await _wait(0.4)
	# 像素点击的前提要自己报出来：窗口尺寸一飘，所有 _click 都会落到别处
	var wsz: Vector2i = get_tree().root.size
	print("[autotest] 窗口 ", wsz)
	if wsz != Vector2i(1280, 720):
		fails.append("窗口尺寸 %s ≠ 1280x720，像素点击全部失准" % str(wsz))

	# 1) 标题页
	main.goto("title")
	await _wait(0.8)
	await _shot("01_title")
	var title_scr = main.current
	# 真实输入管线：Input.parse_input_event 点击「开始营业」
	_click_parse(_hit_center(title_scr, "primary", Vector2(1280 * 0.62, 720 * 0.62 + 29)))
	await _wait(0.9)
	if str(main.current_name) != "story":
		fails.append("real input pipeline: title primary click did not open story (fallback used)")
		if not _click_hit(title_scr, "primary"):
			_click(Vector2(1280 * 0.62, 720 * 0.62 + 29))
		await _wait(0.9)

	# 2) 开场剧情
	if not await _await_screen("story", 5.0):
		fails.append("intro story not shown")
	await _shot("02_intro_story")
	var story = main.current
	# 按 idx 等，不按"点几下"等：打字速度跟帧率走，点快了会直接翻过目标格
	# （有一趟就是这么少了 02c 和八张教学截图，还只报一条"没到商店"）
	if not await _story_to(story, 1):
		fails.append("剧情没能翻到老柴那一格")
	await _wait(0.5)
	await _shot("02b_story_chef")
	# 再翻到 idx==3，那一格才有"扣着的相框"伏笔道具
	if not await _story_to(story, 3):
		fails.append("剧情没能翻到相框那一格")
	if str(main.current_name) != "story":
		fails.append("相框那一格没停住，剧情已经翻走了")
	else:
		await _wait(0.8)
		await _shot("02c_story_photo_prop")
	if not _click_hit(main.current, "skip"):
		_click(Vector2(1280 - 57, 31))
	if not await _await_screen("shop", 5.0):
		fails.append("shop not reached after intro")

	# 3) 商店：补货 + 截图
	await _wait(0.5)
	await _shot("03_shop_day1")
	var shop_scr = main.current
	var bought := false
	for bid in ["b5:lettuce", "b5:tomato", "b1:patty"]:
		if _click_hit(shop_scr, str(bid)):
			bought = true
			await _wait(0.2)
	if not bought:
		# 兜底：直接买
		GameState.coins += 50
		GameState.buy_ingredient("lettuce", 5, 1.0)
	await _shot("04_shop_after_buy")
	# 3b) 商店另外三个标签页：升级/菜谱/说明以前没有任何截图覆盖过，
	# 说明页七条提示全挤在左上那一格，第 4 行起就画到木隔板外面了
	for ti in [1, 2, 3]:
		_click_hit(shop_scr, "tab:%d" % ti)
		await _wait(0.3)
		await _shot("04b_shop_tab%d" % ti)
	# 升级页 7 张卡分 2 页，第 2 页全是新加的「省点击」升级，单独抓一帧
	_click_hit(shop_scr, "tab:1")
	await _wait(0.25)
	_click_hit(shop_scr, "pg:1")
	await _wait(0.25)
	await _shot("04c_shop_tab1_p2")
	_click_hit(shop_scr, "pg:-1")
	await _wait(0.2)
	_click_hit(shop_scr, "tab:0")
	await _wait(0.2)
	_click_parse(_hit_center(shop_scr, "start", Vector2(1280 / 2 + 145, 720 - 64)))
	# 这里原来是固定 await 0.9s 再判 current_name。而 perf 量到首次 goto("play") 要 391ms
	# （建屏 + 载 DaySim + 首次贴图），机器正忙时（比如刚 --import 完）会顶过 900ms，
	# 于是这条真输入断言变成一条会随机红的假失败。改成有界轮询，并把耗时打出来——
	# 慢要看得见，别拿一个魔数当判据。
	var t0 := Time.get_ticks_msec()
	var reached: bool = await _await_screen("play", 5.0)
	print("[input] 商店「开始营业」→ play 换了 %dms" % (Time.get_ticks_msec() - t0))
	if not reached:
		fails.append("real input pipeline: shop start click did not open play (fallback used)")
		if not _click_hit(shop_scr, "start"):
			_click(Vector2(1280 / 2 + 145, 720 - 64))
		await _wait(0.8)

	# 4) 营业：开始
	if not await _await_screen("play", 5.0):
		fails.append("play not reached")
	var play = main.screens.get("play")
	if play == null:
		fails.append("play screen missing")
		_finish()
		return
	var bot = load("res://tests/sim_bot.gd").new()
	# 教学是进 play 后 0.6s 的定时器弹的；只等固定 1.2s 会和它擦身而过
	var tut_seen := false
	for k in 25:
		await _wait(0.1)
		if main.has_overlay():
			tut_seen = true
			break
	if tut_seen:
		await _shot("05a_tutorial")
		var tut_n: int = load("res://scripts/components/ov_tutorial.gd").STAGES.size()
		for k in tut_n - 1:
			_click(Vector2(1280 * 0.5, 720 * 0.62))
			await _wait(2.4)
			await _shot("05a_tutorial_%d" % (k + 2))
		while main.has_overlay():
			_click(Vector2(1280 - 61, 32))
			await _wait(0.4)
	else:
		# 以前这里没有 else：教学没弹出来，八张截图就静悄悄少掉，整条链照样报绿
		fails.append("开场教学没弹出（tut_done=%s，进 play 后 1.2s 仍无覆盖层）" % str(GameState.tut_done))
	await _shot("05_play_start")
	# 真实输入管线：点一下 0 号烤架（应放上肉饼）
	await _wait(0.4)
	_click_parse(_hit_center_nth(play, "grill", 0, Vector2(120, 420)))
	await _wait(0.4)
	var placed := false
	for g in play.sim.grill:
		if float(g["p"]) >= 0.0:
			placed = true
	if not placed:
		fails.append("real input pipeline: grill click failed")

	# 等第一位顾客入座
	var t := 0.0
	while t < 20.0:
		if _any_waiting(play):
			break
		bot.sim = play.sim
		bot.step(0.05)
		await _wait(0.05)
		t += 0.05
	await _shot("06_play_customer")
	# 小票文字防裁切回归位：把台词换成最长的一句
	if _any_waiting(play):
		var lc = play.sim.queue[0]
		lc.say = "听说这里分量足？我胃口可太大了，别让我等太久。"
		lc.say_t = 8.0
		await _wait(0.2)
		await _shot("06b_ticket_long_say")

	# 玩到第一次上餐
	t = 0.0
	while t < 40.0:
		bot.sim = play.sim
		bot.step(0.05)
		if int(play.sim.served) >= 1:
			break
		await _wait(0.05)
		t += 0.05
	if int(play.sim.served) < 1:
		fails.append("no serve within 40s")
	await _wait(0.15)
	await _shot("07_play_served")
	# 4a1) 抛硬币：结算之后钱落在台面上，这一张要拍到它们（顺带证明两枚硬币素材真的进了渲染，
	# 而不只是 sim 里有数据）。bot 下一步就会捡干净，所以必须在这里抢拍。
	var n_before: int = play.sim.coins.size()
	play.sim.toss_coins(37)
	await _wait(0.62)
	await _shot("07k_coins_tossed")
	var ncoin: int = play.sim.coins.size()
	# bot 上完那一单的钱还摊在台面上（它下一步才捡），所以要按"增量"判，不能判绝对数
	print("[coins] 抛 37：台面 %d → %d 枚（这一抛应加 3 金 + 7 银 = 10 枚）" % [n_before, ncoin])
	if ncoin != n_before + 10:
		fails.append("抛 37 应多 10 枚硬币，实多 %d 枚" % (ncoin - n_before))
	# 4a) 火炉只剩两枚图形圆钮当入口（木牌文字已撤）；四瓶酱站在左下前唇上
	var fa := _count_hits(play, "fire_add")
	var fc := _count_hits(play, "fire_chop")
	if fa != 1 or fc != 1:
		fails.append("炉脚两枚图形圆钮的热区没挂上（添柴 %d 个、劈柴 %d 个）" % [fa, fc])
	var s1 := _count_hits(play, "sauce")
	if s1 != 4:
		fails.append("第 1 天应有 4 瓶酱在前唇上，实得 %d 个热区" % s1)

	# 4b) 饮料机：点第 2/3 根柱子必须真的换罐。
	# sim_bot 是自己算 jar 的，所以这条只能从 UI 输入层验——曾经 play.gd 丢掉 jar 参数，人手永远只出可乐。
	play.sim.drink["p"] = -1.0
	for ji in [1, 2]:
		# 每次点之前先让机器空下来：罐子倒到一半时 tap_drink 会拒绝换罐，这是设计如此
		play.sim.drink["p"] = -1.0
		_click_parse(_hit_center_nth(play, "drink", ji, Vector2(1180, 420)))
		await _wait(0.15)
		if int(play.sim.drink_jar) != ji:
			fails.append("drink column #%d click kept drink_jar=%d" % [ji + 1, int(play.sim.drink_jar)])
	play.sim.drink["p"] = -1.0
	play.sim.drink_jar = 1
	await _wait(0.3)
	await _shot("07b_drink_jars")

	# 4c) 倒掉：做错的那份以前没有任何出路，托盘会永久卡死这一局
	play.sim.tray = {"burger": 0, "fries": true, "drink": "cola"}
	var tp: Vector2 = (play.ly()["tray"] as Rect2).get_center()
	var fp: Vector2 = (play.ly()["fire"] as Rect2).get_center()
	_press_parse(tp)
	_move_parse(tp + (fp - tp) * 0.5)
	await _wait(0.2)
	await _shot("07c_dump_drag")
	_move_parse(fp)
	_release_parse(fp)
	await _wait(0.2)
	if play.sim.tray_has():
		fails.append("dragging the tray onto the stove did not dump it")
	play.sim.tray = {"burger": 1, "fries": false, "drink": ""}
	await _wait(0.2)
	_click_parse(_hit_center(play, "bin", Vector2(886, 32)))
	await _wait(0.2)
	if play.sim.tray_has():
		fails.append("HUD bin button did not dump the tray")

	# 4e) 单击托盘＝提起来，再点一下＝放下。全程零拖动。
	# 以前要按住拖过 10px 才算"拿起来"，纯点击只回一句提示，等于逼玩家点两次。
	play.sim.tray = {"burger": 99, "fries": false, "drink": ""}
	await _wait(0.2)
	_click_parse(tp)
	await _wait(0.2)
	if not bool(play.tray_sticky):
		fails.append("单击托盘没有把它提起来（tray_sticky 仍为 false）")
	if str(play.snark_text) != Config.misc("tray_lifted"):
		fails.append("提起托盘后的提示不对：%s" % str(play.snark_text))
	await _shot("07h_tray_lifted")
	# 提着时点空白：那份不能凭空消失，但吸附要解除（否则下一击还是落点）
	_click_parse(Vector2(640, 700))
	await _wait(0.15)
	if not play.sim.tray_has():
		fails.append("提着托盘点空白处，那份居然被弄丢了")
	if bool(play.tray_sticky):
		fails.append("提着托盘点空白处后没解除吸附")
	# 再提一次，这回收尾到灶膛
	_click_parse(tp)
	await _wait(0.15)
	_click_parse(fp)
	await _wait(0.2)
	if play.sim.tray_has():
		fails.append("提着托盘点灶膛没有丢掉")
	if bool(play.tray_sticky):
		fails.append("丢掉之后托盘还吸附在光标上")

	# 4d) 组装中/案板压料/托盘只有一件——以前没有任何截图覆盖过这三种状态
	_hover_parse(Vector2(-1, -1))
	play.sim.target = play.sim.first_waiting()
	play.sim.assembly = ["bun", "lettuce"]
	play.sim.board = {"ing": "tomato", "cuts": 1, "need": 2}
	play.sim.sauces_used = {"ketchup": true}
	play.sim.tray = {"burger": -1, "fries": true, "drink": ""}
	await _wait(0.3)
	await _shot("07d_asm_board")
	# 最坏情况：把菜单上层数最多那道堡叠到只剩最后一层没放、案板上再压一块，
	# 整摞不能顶出工位格。层数从配置反推——以前这里写死 6 项，
	# 第二章加了 8 层的「柴火全家堡」之后这张图就悄悄不测最坏情况了。
	var tallest: Array = []
	for bi in Config.burger_count():
		var st: Array = Config.burger(bi).get("stack", [])
		if st.size() > tallest.size():
			tallest = st
	if tallest.size() < 7:
		fails.append("最长配方只有 %d 层，这张最坏情况图没测到东西" % tallest.size())
	play.sim.assembly = tallest.slice(0, maxi(tallest.size() - 1, 0))
	await _wait(0.3)
	await _shot("07e_asm_tall")
	# 4f) 悬停提示：热区框 + 一句话，饮料机以前"找不到怎么点"就是缺这个。
	# 挑最左那根柱子，免得和"当前选中罐"的高亮混在一起看不清
	var dp: Vector2 = _hit_center_nth(play, "drink", 0, Vector2(1096, 452))
	_hover_parse(dp)
	await _wait(0.25)
	var tipped := 0
	for h in play.get("_hits"):
		if str(h.get("id", "")) == "drink" and (h["rect"] as Rect2).has_point(dp):
			tipped += 1
	if tipped == 0:
		fails.append("hover point missed every drink column")
	await _shot("07f_hover_tip")
	# 悬停在食材格上只报菜名：库存按用户定的规矩用"多摆几个"表达，不给数字角标
	var sp: Vector2 = _hit_center_nth(play, "shelf", 2, Vector2(470, 634))
	_hover_parse(sp)
	await _wait(0.25)
	await _shot("07g_hover_shelf")
	# 悬停在客人身上要报出身份：customers.json 的 role 之前没有任何界面读过
	var cust_hits := _count_hits(play, "cust")
	if cust_hits == 0:
		fails.append("身份悬停这条没测到：画面上一位客人都没有")
	else:
		_hover_parse(_hit_center(play, "cust", Vector2(500, 250)))
		await _wait(0.25)
		await _shot("07i_hover_cust")
	_hover_parse(Vector2(-1, -1))
	_hover_parse(Vector2(-1, -1))
	play.sim.assembly = []
	play.sim.board = {"ing": "", "cuts": 0, "need": 0}
	play.sim.sauces_used = {}
	play.sim.tray = {"burger": -1, "fries": false, "drink": ""}

	# 5) 覆盖层：紧急卡车 / 劈柴 / 暂停
	play._activate({"id": "truck"}, Vector2.ZERO)
	await _wait(0.4)
	await _shot("08_truck_overlay")
	main.close_overlay()
	await _wait(0.3)

	play._activate({"id": "menu"}, Vector2.ZERO)
	await _wait(0.4)
	await _shot("08b_menu_overlay")
	main.close_overlay()
	await _wait(0.3)

	play._activate({"id": "fire_chop"}, Vector2.ZERO)
	await _wait(0.45)
	# 这张图叫 09_chop_overlay，就得先证明劈柴面板真的开着——不然它拍到的是营业台，
	# 而测试照样绿（教学那段就是这么红过一次：少了 else，整块静默跳过）。
	var chop_open := main.overlay != null \
		and str((main.overlay as Node).get_script().resource_path).ends_with("ov_chop.gd")
	if not chop_open:
		fails.append("劈柴面板没开起来，09 那四张图整块没测到（overlay=%s）" % str(main.overlay))
	await _shot("09_chop_overlay")
	var ov = main.overlay
	# `if ov.has_method(...)` 不写 else，方法一改名这三帧就静默消失、整链照报绿。
	# 所以按"实际拍了几帧"判，而不是"看起来跑了"。
	var poses := 0
	if chop_open and ov.has_method("debug_pose"):
		ov.debug_pose("swing")
		await _wait(0.06)
		await _shot("09b_chop_swing")
		poses += 1
		ov.debug_pose("split")
		await _wait(0.06)
		await _shot("09c_chop_split")
		poses += 1
		ov.debug_pose("miss")
		await _wait(0.06)
		await _shot("09d_chop_miss")
		poses += 1
	if chop_open and poses != 3:
		fails.append("劈柴三帧只拍了 %d 帧——debug_pose 改名的话这里会先红，不会再静默少图" % poses)
	var presses := 0
	if chop_open and ov.has_method("press_at"):
		ov.press_at(0.5)
		await _wait(0.75)
		presses += 1
		ov.press_at(0.5)
		await _wait(0.75)
		presses += 1
		ov.press_at(0.12)
		await _wait(0.75)
		presses += 1
	if chop_open and presses != 3:
		fails.append("劈柴只挥了 %d 斧（应为 3），下面那几条轮数/柴数断言的前提不成立" % presses)
	await _wait(2.2)
	if ov != null:
		if ov.round_idx < 3:
			fails.append("劈柴没跑满 3 轮（round_idx=%d）" % ov.round_idx)
		if int(ov.gained) != 5:
			fails.append("两轮命中一轮未命中应得 5 根柴，实得 %d" % int(ov.gained))
		if bool(ov.all_hit):
			fails.append("第三斧落在 0.12，不该还算全中")
	if main.overlay != null:
		main.close_overlay()
	await _wait(0.3)

	play._activate({"id": "pause"}, Vector2.ZERO)
	await _wait(0.4)
	await _shot("10_pause_overlay")
	play.resume_game()
	main.close_overlay()
	await _wait(0.3)

	main.goto("map", {"from": "play"})
	await _wait(0.5)
	await _shot("10b_map")
	main.goto("play")
	await _wait(0.4)

	# 6) 玩完第 1 天
	t = 0.0
	var midday_shot := false
	while t < 180.0:
		if not play.sim.finished:
			bot.sim = play.sim
			bot.step(0.05)
		if not midday_shot and t > 12.0:
			midday_shot = true
			await _shot("11_play_midday")
		if str(main.current_name) == "day_end":
			break
		await _wait(0.05)
		t += 0.05
	if not await _await_screen("day_end", 10.0):
		fails.append("day_end not reached")
	await _wait(0.6)
	await _shot("12_day_end")

	# 7) 结算 → 第 1 天神秘客人剧情
	if not _click_hit(main.current, "settle"):
		_click(Vector2(640, 720 - 69))
	if not await _await_screen("story", 6.0):
		fails.append("mystery story not shown")
	await _wait(0.8)
	await _shot("13_mystery_story")
	# 先点一下推进半句，再跳过
	_click(Vector2(640, 720 - 120))
	await _wait(0.4)
	if not _click_hit(main.current, "skip"):
		_click(Vector2(1280 - 57, 31))

	# 8) 未完待续 → 继续经营 → 第 2 天商店
	if not await _await_screen("ending", 6.0):
		fails.append("teaser not shown")
	await _wait(0.6)
	await _shot("14_teaser")
	if not _click_hit(main.current, "continue"):
		_click(Vector2(640, 720 * 0.78 + 27))
	if not await _await_screen("shop", 6.0):
		fails.append("shop day2 not reached")
	await _wait(0.5)
	await _shot("15_shop_day2")

	# 9) 营业台账
	main.goto("records", {"from": "shop"})
	await _wait(0.8)
	await _shot("16_records")
	if not _click_hit(main.current, "back"):
		_click(Vector2(640, 720 - 51))

	# 10) 说明页
	main.goto("help", {"from": "title"})
	await _wait(0.6)
	await _shot("17_help")

	# 11) 后期状态：第 1 天的流程永远走不到这些画面，以前一张都没渲染过
	GameState.day = 5
	GameState.add_coins(900)
	GameState.add_rep(3.0)
	GameState.buy_upgrade("grill3")
	GameState.buy_upgrade("stove")
	main.goto("play", {"fresh": true})
	if not await _await_screen("play", 6.0):
		fails.append("day5 play not reached")
		_finish()
		return
	var late = main.screens.get("play")
	late.paused = true
	late.sim.tray = {"burger": 4, "fries": true, "drink": "lemon"}
	late.sim.assembly = ["bun", "onion", "pickle"]
	late.sim.board = {"ing": "onion", "cuts": 1, "need": 2}
	await _wait(0.6)
	await _shot("18_play_day5")
	if late.sim.grill.size() < 3:
		fails.append("grill3 upgrade did not add a slot (size=%d)" % late.sim.grill.size())
	# 11a) 两个「省点击」升级：各跑一次买前/买后的对照，确认效果真的绑上了
	GameState.buy_upgrade("autoturn")
	GameState.buy_upgrade("quickcut")
	_probe_auto_turn()
	_probe_quickcut(late)
	_probe_rep_tip()
	await _wait(0.3)
	await _shot("18a2_upgrades_owned")
	# 滚到最右：验 ‹ › 箭头和最后几格（酸黄瓜/培根/煎蛋）
	var shelf_c: Vector2 = (late.ly()["shelf"] as Rect2).get_center()
	for k in 8:
		_wheel_parse(shelf_c, true)
		await _wait(0.05)
	await _wait(0.4)
	await _shot("18b_play_day5_scrolled")
	var s5 := _count_hits(late, "sauce")
	if s5 != 4:
		fails.append("第 5 天应有 4 瓶酱上台面，实得 %d 个热区" % s5)
	# 11a2) 解锁播报：中上方那条飘字必须出现（这套反馈之前整个游戏里根本没有）。
	# 第 5 天这屏是暂停着的，sim.tick 从没被 _process 跑过，所以第一次 tick 走的是
	# "今天新菜上菜单"那一支、顺手才把 _stars_seen 装上——要测升星得再 tick 一次。
	var keep_rep := GameState.rep
	late.sim.tick(0.05)
	var pop_before: int = late.popups.size()
	late.sim._stars_seen = GameState.rep_stars() - 1
	GameState.rep = 5.0
	late.sim.tick(0.05)
	var notice := ""
	if late.popups.size() > pop_before:
		notice = str((late.popups[late.popups.size() - 1] as Dictionary).get("text", ""))
	if notice == "":
		fails.append("声望升星没有飘字（popups 仍只有 %d 条）" % late.popups.size())
	elif not notice.contains("★"):
		fails.append("升星飘字内容不对：%s" % notice)
	elif late.popups.size() >= 2:
		# 两条播报撞在同一行就是一串糊字，堆叠必须错开
		var n0: Dictionary = late.popups[late.popups.size() - 1]
		var n1: Dictionary = late.popups[late.popups.size() - 2]
		var dy: float = absf(((n0.pos as Vector2).y) - ((n1.pos as Vector2).y))
		if dy < 20.0:
			fails.append("两条飘字挤在同一行（间距 %.1fpx）" % dy)
	await _wait(0.2)
	await _shot("18i_star_notice")
	GameState.rep = keep_rep
	# 11b) 三个从没渲染过的反馈状态：炉火熄灭 / 顾客翻脸要走 / 连击飘字
	late.sim.fire = 2.0
	late.sim.wood = 0
	await _wait(0.4)
	await _shot("18c_play_fire_out")
	late.sim.fire = 80.0
	late.sim.wood = 6
	# 暂停状态下 sim 不 tick、不会自己来客，直接催两个出来再摆表情
	for k in 2:
		late.sim._spawn_customer()
	for c in late.sim.queue:
		c.state = "waiting"
		c.walk_t = 99.0
	if late.sim.queue.size() > 0:
		var c0 = late.sim.queue[0]
		c0.mood = "angry"
		c0.patience = c0.max_patience * 0.12
		c0.say = "太久了太久了，我赶时间！"
		c0.say_t = 8.0
		late.sim.combo = 5
		late._on_popup("+86  连击x6", Color("#ffd23c"), 0)
		await _wait(0.3)
		await _shot("18d_play_angry_combo")
		if c0.say_t <= 0.0:
			fails.append("angry customer say-line expired before the shot")
	# 只有薯条的盘子拖给点了薯条的客人：逐件交付之后这一件**该递得出去**，
	# 但他点的堡还没给，所以不能就此结算。以前这一手是"光薯条送不到桌上"。
	var fr: Customer = null
	for cc in late.sim.queue:
		if cc.state == "waiting":
			fr = cc
			break
	if fr == null:
		fails.append("逐件交付用例没抓到等待中的客人，整条没跑")
	else:
		fr.set_want("fries", true)
		fr.got = {}
		fr.slot = 0
		late.sim.tray = {"burger": -1, "fries": true, "drink": "", "burger_tip": 0}
		var s0: Dictionary = late.ly()["slots"][0]
		_press_parse((late.ly()["tray"] as Rect2).get_center())
		_move_parse(Vector2(float(s0.x), 300))
		_release_parse(Vector2(float(s0.x), 260))
		await _wait(0.2)
		if bool(late.sim.tray["fries"]):
			fails.append("把薯条拖给点了薯条的客人，荷叶上那份没被收走")
		if not bool(fr.got.get("fries", false)):
			fails.append("客人没收到那件薯条（got=%s）" % str(fr.got))
		if not late.sim.queue.has(fr):
			fails.append("只收齐一件就把客人结算送走了——他点的堡还没给")
	# 炸锅动画三帧：下篮 / 浸油冒泡 / 提起沥油
	GameState.inv_add("potato", 6)
	late.paused = false
	late.sim.tray = Config.empty_tray()
	late.sim.fryer = late.sim._new_fryer()
	late.sim.wood = 6
	late.sim.fire = 80.0
	late.sim.tap_fryer()
	await _wait(0.16)
	if late.sim.fryer_p() < 0.0:
		fails.append("tap_fryer did not start a fry (potato stock=%d)" % GameState.inv_count("potato"))
	await _shot("18e_fry_down")
	await _wait(0.34)
	late.sim.fryer[0]["p"] = 0.85
	await _wait(0.26)
	await _shot("18f_fry_in")
	late.sim.tap_fryer()
	await _wait(0.40)
	if not bool(late.sim.tray["fries"]):
		fails.append("lifting in-window did not put fries on the tray")
	await _shot("18g_fry_lift")
	# 炸糊那一支：发黑 + 冒烟，走的是 burn 分支（先清盘，否则上面那次起锅会让断言假阳）
	late.sim.tray = Config.empty_tray()
	# 视图的动画是抓「p 从 >=0 跳到 <0」驱动的，所以设完值得**先让视图跑几帧**，
	# 它才可能看见这个跳变、才会进 burn。以前这里设完立刻 tap，一帧都没留——
	# 结果 18h 这张图连续若干轮拍到的都是"只有底图那只空篮"，而断言只判荷叶不判动画，
	# 于是画面一直是错的、测试一直全绿。
	# 但也不能留太多帧：tick 会把 p 推过 burn_auto(1.35) 走"自动烧糊"那条分支，
	# tap 命中的就不是"炸糊起锅"了。取 1.25（> burn_tap 1.22，离 1.35 还有余量）。
	late.sim.fryer = late.sim._new_fryer()
	late.sim.fryer[0]["p"] = 1.25
	late.sim.fryer[0]["warned"] = true
	late.sim.fryer[0]["item"] = "fries"
	await _wait(0.05)
	if late.sim.fryer_p(0) >= 1.35:
		fails.append("等帧期间 p 被推过了 burn_auto，tap 命中的不再是炸糊起锅（p=%.2f）" % late.sim.fryer_p(0))
	late.sim.tap_fryer()
	await _wait(0.30)
	if bool(late.sim.tray["fries"]):
		fails.append("burnt fry still put fries on the tray")
	# 动画本身也要判——不然这张图又会悄悄退回"拍了一只空篮"
	var burn_phase := str(late._anim(0)["phase"])
	if burn_phase != "burn":
		fails.append("炸糊动画没在播，18h 这张图拍不到发黑和冒烟（实得 phase=%s）" % burn_phase)
	await _shot("18h_fry_burn")
	late.paused = true
	late.sim.refund_assembly()
	main.goto("map", {"from": "play"})
	await _wait(0.5)
	await _shot("19_map_day5")
	main.goto("shop", {})
	await _wait(0.5)
	_click_hit(main.current, "tab:1")
	await _wait(0.4)
	await _shot("19b_shop_owned")
	# 第二章的三屏。上面那一整块后期状态停在第 5 天，换章之后的画面一张都没盖过：
	# 地图的第二条路线、章开场剧情（story.gd 里 scene_type=="chapter" 那一支）。
	GameState.day = 10
	main.goto("map", {"from": "play"})
	await _wait(0.5)
	await _shot("19c_map_day10_ch2")
	# day 13 是本章最后一块路牌：六块牌面摆 6 站，未解锁的那几块是另一种画法
	GameState.day = 13
	main.goto("map", {"from": "play"})
	await _wait(0.5)
	await _shot("19d_map_day13_ch2")
	GameState.day = 5
	var ch2: Array = Config.chapter_intro_lines(2)
	if ch2.is_empty():
		fails.append("第二章没有开场剧情，那一段整条没测到")
	else:
		# 不传 on_done：_finish() 只在 Callable 有效时才调，留在这屏上正好接着拍
		main.goto("story", {"lines": ch2, "scene": "chapter"})
		if not await _await_screen("story", 6.0):
			fails.append("章开场剧情没开出来（scene=chapter）")
		else:
			var st = main.current
			await _story_settle(st)
			await _shot("20b_story_ch2_narrator")
			# 旁白那句不画立绘；画的是"说话人按 mood 换表情"那两帧
			if await _story_to(st, 1) and await _story_settle(st):
				await _shot("20c_story_ch2_side")
			else:
				fails.append("章开场剧情推不到第 2 句，换表情那两帧没测到")
			if await _story_to(st, 4) and await _story_settle(st):
				await _shot("20d_story_ch2_shock")
			else:
				fails.append("章开场剧情推不到最后一句")
	main.goto("ending", {"mode": "chapter", "chapter": Config.chapter_count()})
	await _wait(0.8)
	await _shot("20_ending_ch2")
	# 存档损坏那句要真看得见才叫"说得出"：load_error 只是显示用的字段，这里直接摆一个样本
	SaveManager.load_error = "存档文件读不出来，已原样留到 save_slot1.corrupt-2026-09-30T11_22_33.json"
	main.goto("title", {})
	await _wait(0.6)
	await _shot("22_title_save_corrupt")
	SaveManager.load_error = ""
	await _worst_case_copy()
	_finish()

## 文案最坏情况：第 7 天 + 声望拉满（五道堡全部解锁，图鉴里全是长名字和满配配料链）
## + 台账堆到最多行。第 1 天那些画面里每条文案都还是短的，量不出溢出。
func _worst_case_copy() -> void:
	GameState.day = Config.total_days()
	GameState.add_rep(50.0)
	GameState.add_coins(4000)
	# 数字最坏情况：金币拉到六位数。HUD 那枚金币药丸以前写死 124px，
	# 而 coins_fmt 是用户能在 user://config 里改的，格式一长字就骑出药丸外。
	GameState.coins = 999999
	var locked: Array = []
	for i in Config.burgers().size():
		if not Config.burger_open(i):
			locked.append(i)
	print("[copy] 第 %d 天 / %d★，仍未解锁的堡: %s" % [GameState.day, GameState.rep_stars(), str(locked)])
	if not locked.is_empty():
		fails.append("声望拉满后还有堡没解锁: %s（最坏情况文案没测到）" % str(locked))
	main.goto("play", {"fresh": true})
	if not await _await_screen("play", 6.0):
		fails.append("worst-case play not reached")
		return
	var w: Node = main.screens.get("play")
	w.paused = true
	await _wait(0.4)
	await _shot("21a_copy_play_day7")
	# 收币人（第 2 天起才有）：摆到"他正走进来、台面上还摊着钱"那一帧拍下来。
	# 这里 paused=true，sim.tick 不跑，所以要手动把每枚的 t 推到落地之后，
	# 否则全叠在抛出点上，拍出来像一摞而不是散开的。
	w.sim.toss_coins(43)
	for c in w.sim.coins:
		(c as Dictionary)["t"] = 0.62
	w.sim.sweeper_t = 2.6
	# 兜里那 20 必须先从台面上消失，否则这张图会同时画出"两份钱"，看着像 bug
	var pocket := 0
	while pocket < 20 and not w.sim.coins.is_empty():
		pocket += int(w.sim.coins[0]["v"])
		w.sim.coins.remove_at(0)
	w.sim.sweeper_taken = pocket
	await _wait(0.3)
	await _shot("21h_sweeper_in")
	w.sim.sweeper_t = -1.0
	w.sim.sweeper_taken = 0
	w.sim.coins = []
	# 每个热区都必须给得出悬停说明：_draw_hover_tip 在 tip 为空时连焦点框都不画，
	# 所以"漏一条 tooltip"在画面上的表现是"这个工位划上去完全没反应"，而不是"少了行字"。
	var notip: Array = []
	for h in w._hits:
		var hd: Dictionary = h
		var t := str(w.call("_tip_for", hd))
		if t.strip_edges() == "":
			notip.append("%s%s" % [str(hd.get("id", "?")), ("=" + str(hd.get("key", hd.get("jar", hd.get("i", ""))))) if str(hd.get("key", hd.get("jar", hd.get("i", "")))) != "" else ""])
	print("[tip] 第 7 天画面共 %d 个热区，说不出说明的 %d 个%s"
		% [w._hits.size(), notip.size(), ("：" + "; ".join(PackedStringArray(notip))) if not notip.is_empty() else ""])
	if not notip.is_empty():
		fails.append("%d 个热区没有悬停说明（划上去连框都不会出）：%s" % [notip.size(), "; ".join(PackedStringArray(notip))])
	# 图鉴：一本摊开的书，两页五个堡一次全渲染出来（没有翻页热区）
	main.open_overlay(load("res://scripts/components/ov_menu.gd").new())
	await _wait(0.5)
	await _shot("21b_copy_menu")
	main.close_overlay()
	await _wait(0.3)
	# 卡车补货：11 行三栏，是最挤的一张表
	main.open_overlay(load("res://scripts/components/ov_truck.gd").new())
	await _wait(0.5)
	await _shot("21d_copy_truck")
	main.close_overlay()
	await _wait(0.3)
	# 商店：食材页（11 格）与图鉴页（5 道菜）
	main.goto("shop", {})
	await _wait(0.5)
	_click_hit(main.current, "tab:0")
	await _wait(0.3)
	await _shot("21e_copy_shop_food")
	# 食材页一格四张、11 样要三页，可乐正好在最后一页——不翻过去就永远没渲染过它
	_click_hit(main.current, "pg:1")
	await _wait(0.35)
	await _shot("21e2_copy_shop_food_p2")
	_click_hit(main.current, "pg:1")
	await _wait(0.35)
	await _shot("21e3_copy_shop_food_p3")
	# 翻页不能吞货：三页的 +1 热区加起来必须等于可买原料总数，末页数也要对
	var last_cards := _count_hits_prefix(main.current, "b1:")
	var per := 4
	var total := Config.shop_order().size()
	var want_last := total - (int(ceil(float(total) / float(per))) - 1) * per
	print("[shop] 可买 %d 样 / 末页 %d 张卡（应为 %d）" % [total, last_cards, want_last])
	if last_cards != want_last:
		fails.append("商店食材末页张数不对：%d，应为 %d（翻页在吞货或多画）" % [last_cards, want_last])
	_click_hit(main.current, "tab:2")
	await _wait(0.4)
	await _shot("21f_copy_shop_dishes")
	# 台账：造到 total_days 行、每格都填最长/最宽的值，末行不能掉出剪贴板。
	# 键名照 day_sim.day_stats() 抄，之前瞎猜键名时"完美/流失"两列全是 0，等于没测。
	var long_burger := ""
	for b in Config.burgers():
		var nm := str((b as Dictionary).get("name", ""))
		if nm.length() > long_burger.length():
			long_burger = nm
	var long_drink := ""
	for dd in Config.dishes.get("drinks", []):
		var dn := str((dd as Dictionary).get("name", ""))
		if dn.length() > long_drink.length():
			long_drink = dn
	var long_cust := ""
	for i in Config.species_count():
		var cn := str(Config.species(i).get("name", ""))
		if cn.length() > long_cust.length():
			long_cust = cn
	var items: Array = [long_burger, "炸薯条", long_drink]
	print("[copy] 最长客人「%s」 最长堡「%s」 明细行「%s」" % [long_cust, long_burger, " / ".join(items)])
	var wide_orders: Array = []
	for k in 6:
		wide_orders.append({
			"seq": 900 + k, "day": Config.total_days(), "customer": long_cust, "items": items,
			"price": 32, "tip": 99, "rep_mult": 1.45, "combo_bonus": 88,
			"total": 9999, "patience_frac": 0.99, "time": "23:59:59"
		})
	# 掺一条 items 写成字符串的：ledger.json 是磁盘上的 JSON，不保证类型；
	# 以前这种记录会让整帧 _draw_order_panel 抛错、右栏画空
	wide_orders.append({
		"seq": 999, "day": Config.total_days(), "customer": long_cust, "items": long_burger,
		"price": 32, "tip": 99, "rep_mult": 1.45, "combo_bonus": 88,
		"total": 9999, "patience_frac": 0.99, "time": "23:59:59"
	})
	for d in range(3, Config.total_days() + 1):
		SaveManager.commit_day({
			"day": d, "coins": 99999, "served": 14, "missed": 14, "perfects": 14,
			"tips": 9999, "combo_peak": 99, "planned": 14, "rep_after": 5.0,
			"orders_count": 999, "saved_at": "2026-09-30T23:59:59"
		}, wide_orders)
	main.goto("records", {"from": "shop"})
	await _wait(0.7)
	await _shot("21g_copy_records")
	# 表头写着"最近 N 笔"而列表画空，只有画的人自己报数才测得出来：
	# 上一版就是 items 类型不对让 _draw_order_panel 每帧抛错，autotest 照样报 0 fail。
	# （试过用"区域里暗色像素占比"判，实测骗人——空白纸区 1.0、画了字的区 0.09。）
	var drawn := int(main.current.get("drawn_orders"))
	var have := mini(SaveManager.orders().size(), 60)
	print("[copy] 订单明细：台账 %d 笔 / 应画 %d 行 / 实画 %d 行" % [SaveManager.orders().size(), have, drawn])
	if have > 0 and drawn == 0:
		fails.append("订单明细表头有 %d 笔却一行都没画出来" % have)

func _wheel_parse(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = pos
	Input.parse_input_event(e)

func _finish() -> void:
	# 收尾：恢复存档与声音设置
	Sfx.set_muted(GameState.muted)
	_restore_saves()
	print("============ AUTOTEST RESULT ============")
	var uniq := {}
	for d in dead_hits:
		var parts: PackedStringArray = str(d).split(" → ")
		uniq[parts[1]] = str(d)
	print("[hotspots] 扫 %d 帧 / %d 个热区矩形，可疑 %d 处（去重后 %d 类）"
		% [hit_scans, hit_rects, dead_hits.size(), uniq.size()])
	# 下限：0 命中和"扫描器根本没跑到"长得一样，所以命中数掉了要能看见
	if hit_scans < 40 or hit_rects < 600:
		fails.append("热区普查覆盖塌了：扫 %d 帧 / %d 矩形（下限 40 帧 / 600 矩形）" % [hit_scans, hit_rects])
	for k in uniq:
		print("[hotspots] ", uniq[k])
	print("shots=%d fails=%d" % [shots.size(), fails.size()])
	for f in fails:
		print("FAIL: ", f)
	for s in shots:
		print("SHOT: ", s)
	if fails.is_empty():
		print("AUTOTEST: ALL PASS")
		get_tree().quit(0)
	else:
		print("AUTOTEST: FAIL")
		get_tree().quit(1)

# ---------------- 工具 ----------------
## 数某个热区在上一帧里被登记了几次。热区是 _draw 时现建的，
## 所以这一条同时验了"画出来了"和"点得着"——只查配置表或只调 sim 层都验不到这两件事。
func _count_hits(scr, id: String) -> int:
	var n := 0
	for h in scr._hits:
		if str((h as Dictionary).get("id", "")) == id:
			n += 1
	return n

## 一排同族热区的 id 带后缀（"b1:lettuce" / "grill:i"），要按前缀数
func _count_hits_prefix(scr, pfx: String) -> int:
	var n := 0
	for h in scr._hits:
		if str((h as Dictionary).get("id", "")).begins_with(pfx):
			n += 1
	return n

## 声望双挂钩（挂小费、挂解锁）必须在真实出餐路径上跑出差异，只翻配置表等于没验。
## 前半段固定耐心比例做 1★/3★/5★ 三档 A/B，后半段把第 5 天压到 1★ 看来客是否真的回退。
func _probe_rep_tip() -> void:
	var keep_day := GameState.day
	var keep_rep := GameState.rep
	var keep_coins := GameState.coins
	var keep_served := GameState.total_served
	var keep_combo := GameState.best_combo
	var by_star := {}
	for stars in [1, 3, 5]:
		GameState.day = 1
		GameState.rep = float(stars)
		var probe := DaySim.new()
		probe.start(1)
		var c := Customer.new()
		c.sp = 0
		c.state = "waiting"
		c.walk_t = 99.0
		c.set_want("burger", 0)
		c.max_patience = 40.0
		c.patience = 32.0          # 钉死 0.8 的耐心比例，全场只让星级这一个变量动
		probe.queue.append(c)
		# 荷叶初值一律从注册表拿，别再手抄一份三格字面量
		probe.tray = Config.empty_tray()
		probe.tray[Config.burger_slot()] = 0
		# 这位只点了堡（fries / drink 两格他都没要），所以递出这一件就算收齐
		if not probe.deliver(c, "burger"):
			fails.append("声望 A/B：%d★ 那单没出餐，探针没跑起来" % stars)
			break
		by_star[stars] = int(probe.tips_total)
	if by_star.size() == 3:
		var t1 := int(by_star[1])
		var t3 := int(by_star[3])
		var t5 := int(by_star[5])
		print("[rep-tip] 1★/3★/5★ 小费 = %d / %d / %d" % [t1, t3, t5])
		if not (t1 < t3 and t3 < t5):
			fails.append("小费没随声望星级单调上涨: %d / %d / %d" % [t1, t3, t5])
		elif t5 < int(ceilf(float(t3) * 1.3)):
			fails.append("5★ 相对 3★ 的加成太小（%d -> %d）" % [t3, t5])
		# 3★ 是开局水位，必须精确等于不吃声望的老基线，否则这次改动动了平衡却没声明
		var base := int(roundf(float(Config.burger(0).get("price", 0))
			* float(Config.economy.get("tip_rate", 0.5)) * 0.8
			* float(Config.species(0).get("tip_mult", 1.0)))) + int(GameState.effect_sum("tip_flat_bonus"))
		if t3 != base:
			fails.append("3★ 小费 %d 与基线 %d 不一致（开局平衡被动过了）" % [t3, base])
	GameState.day = 5
	GameState.rep = 1.0
	var low := DaySim.new()
	low.start(5)
	for k in low.plan.size():
		low._spawn_customer()
	var remapped := 0
	var locked := 0
	for i in low.queue.size():
		var cust: Customer = low.queue[i]
		if cust.burger_idx() != int((low.plan[i] as Dictionary).get("burger", 0)):
			remapped += 1
		if not Config.burger_open(cust.burger_idx()):
			locked += 1
	print("[rep-gate] 第5天 1★：来客 %d 位，回退 %d 位，仍点到未解锁 %d 位" % [low.queue.size(), remapped, locked])
	if locked > 0:
		fails.append("低声望下仍有 %d 位顾客点到做不出的堡（必走单）" % locked)
	elif remapped == 0:
		fails.append("第 5 天 1★ 一张计划单都没回退，声望门槛其实没生效")
	GameState.day = keep_day
	GameState.rep = keep_rep
	GameState.coins = keep_coins
	GameState.total_served = keep_served
	GameState.best_combo = keep_combo

## 自动翻面夹：只有买了升级才该替玩家翻面——买前买后各跑一次对照
func _probe_auto_turn() -> void:
	for owned in [false, true]:
		if owned:
			GameState.buy_upgrade("autoturn")
		else:
			GameState.upgrades.erase("autoturn")
		var probe := DaySim.new()
		probe.start(GameState.day)
		probe.fire = 90.0
		probe.grill[0] = {"p": 0.0, "flipped": false, "warned": false}
		for k in 12:
			probe.tick(0.5)
		var fl := bool(probe.grill[0]["flipped"])
		if fl != owned:
			fails.append("auto_turn=%s 时烤架自己翻面=%s（6 秒模拟）" % [str(owned), str(fl)])
	GameState.buy_upgrade("autoturn")

## 快刃菜板：案板所需刀数要真的按升级倍率缩减，没买时不缩减
func _probe_quickcut(late) -> void:
	var pick := _pick_cut_ingredient()
	if pick.is_empty():
		fails.append("没有任何配方带 cuts>=2 的食材，快刃菜板没被测到")
		return
	# 暂停的 sim 不会自己来客，造一位并把点单钉成含切菜料的那款
	if late.sim.queue.is_empty():
		late.sim._spawn_customer()
	if late.sim.queue.is_empty():
		fails.append("造不出顾客，快刃菜板没被测到")
		return
	var cc = late.sim.queue[0]
	cc.set_want("burger", int(pick["burger"]))
	cc.state = "waiting"
	cc.walk_t = 99.0
	var ing := str(pick["ing"])
	var full := int(Config.ingredient_cuts(ing))
	var keep_target := int(late.sim.target)
	var keep_asm: Array = late.sim.assembly.duplicate()
	var keep_board: Dictionary = late.sim.board.duplicate()
	for owned in [false, true]:
		if owned:
			GameState.buy_upgrade("quickcut")
		else:
			GameState.upgrades.erase("quickcut")
		late.sim.board = {"ing": "", "cuts": 0, "need": 0}
		late.sim.assembly = (pick["pre"] as Array).duplicate()
		late.sim.target = 0
		GameState.inv_add(ing, 4)
		late.sim.tap_shelf(ing)
		var got := int(late.sim.board["need"])
		var want := full if not owned else maxi(1, int(round(float(full) * 0.5)))
		if got != want:
			fails.append("quickcut=%s 时 %s 需 %d 刀，期望 %d 刀" % [str(owned), ing, got, want])
	GameState.buy_upgrade("quickcut")
	# 探针借用了 play 的 sim，跑完要还原，后面的截图还指着这份状态
	late.sim.assembly = keep_asm
	late.sim.board = keep_board
	late.sim.target = keep_target

## 从配方表里找一款「stack 里带需要切的食材」的汉堡，返回它的 id 和该食材前的前缀
func _pick_cut_ingredient() -> Dictionary:
	for bi in Config.burgers().size():
		var stk: Array = Config.burger(bi).get("stack", [])
		for k in stk.size():
			if int(Config.ingredient_cuts(str(stk[k]))) >= 2:
				return {"ing": str(stk[k]), "pre": stk.slice(0, k), "burger": bi}
	return {}

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

## 剧情页只能按 idx 等：打字速度跟帧率走，按"点几下"等会在快机器上翻过目标格。
func _story_to(scr, want: int, timeout := 8.0) -> bool:
	var el := 0.0
	while el < timeout:
		if str(main.current_name) != "story":
			return false
		if int(scr.idx) >= want:
			return true
		_click(Vector2(640, 300))
		await _wait(0.3)
		el += 0.3
	return str(main.current_name) == "story" and int(scr.idx) >= want

## 等当前这一句自己打完字（30 字/秒）。不能用点击补全：点击在"已经打完"的那一帧
## 会推进 idx，等于把要拍的那一格翻过去。
func _story_settle(scr, timeout := 5.0) -> bool:
	var el := 0.0
	while el < timeout:
		var i := int(scr.idx)
		var ls: Array = scr.lines
		if i < 0 or i >= ls.size():
			return true
		if float(scr.chars) >= str((ls[i] as Dictionary).get("text", "")).length():
			return true
		await _wait(0.1)
		el += 0.1
	return false

func _await_screen(name: String, timeout := 8.0) -> bool:
	var t := 0.0
	while t < timeout:
		if str(main.current_name) == name:
			return true
		await _wait(0.1)
		t += 0.1
	return false

func _any_waiting(play) -> bool:
	for c in play.sim.queue:
		if c.state == "waiting":
			return true
	return false

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

## 真实输入管线点击：经 Input.parse_input_event 注入，走引擎完整派发流程
func _click_parse(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)

func _press_parse(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	Input.parse_input_event(e)

func _move_parse(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = pos
	Input.parse_input_event(e)

## 纯悬停（不按键）：验 hover 提示用
func _hover_parse(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	Input.parse_input_event(e)

func _release_parse(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pos
	Input.parse_input_event(e)

func _hit_center(scr: Node, id: String, fallback: Vector2) -> Vector2:
	var hits = scr.get("_hits")
	if hits != null:
		for h in hits:
			if str(h.get("id", "")) == id:
				var r: Rect2 = h["rect"]
				return r.get_center()
	return fallback

func _hit_center_nth(scr: Node, id: String, nth: int, fallback: Vector2) -> Vector2:
	var hits = scr.get("_hits")
	if hits != null:
		var count := 0
		for h in hits:
			if str(h.get("id", "")) == id:
				if count == nth:
					var r: Rect2 = h["rect"]
					return r.get_center()
				count += 1
	return fallback

func _click_hit(scr: Node, id: String) -> bool:
	if scr == null:
		return false
	var hits = scr.get("_hits")
	if hits == null:
		return false
	for h in hits:
		if str(h.get("id", "")) == id:
			var r: Rect2 = h["rect"]
			_click(r.get_center())
			return true
	return false

## 死热区普查。`_press` 是从后往前扫 `_hits` 的，所以**被更晚绘制的矩形整块盖住**的那个
## 热区永远扫不到：图上画着、hover 也亮，点下去没反应。现有测试一条都看不见这类问题。
## 先只报不判（逐条核过再翻硬闸），并自报扫了多少节点/多少矩形——0 命中和没跑长得一样。
var hit_scans := 0
var hit_rects := 0
var dead_hits: Array = []
const HOTSPOT_STRICT := true

func _scan_hits(tag: String) -> void:
	var nodes: Array = []
	if main.current != null:
		nodes.append([str(main.current_name), main.current])
	if main.overlay != null:
		nodes.append(["overlay:" + str(main.overlay.name), main.overlay])
	var vp: Vector2i = get_tree().root.size
	for pair in nodes:
		var node: Node = pair[1]
		var raw = node.get("_hits")
		if typeof(raw) != TYPE_ARRAY:
			continue
		var hits: Array = raw
		var label := "%s/%s" % [tag, str(pair[0])]
		hit_scans += 1
		hit_rects += hits.size()
		for i in hits.size():
			var h: Dictionary = hits[i]
			var r: Rect2 = h.get("rect", Rect2())
			var id := str(h.get("id", h.get("cb", "?")))
			var area := r.size.x * r.size.y
			if area <= 1.0:
				_dead_hotspot(label, "%s 面积为零 %s" % [id, str(r)])
				continue
			if r.end.x <= 0.0 or r.end.y <= 0.0 or r.position.x >= float(vp.x) or r.position.y >= float(vp.y):
				_dead_hotspot(label, "%s 整个出屏 %s" % [id, str(r)])
				continue
			for j in range(i + 1, hits.size()):
				var k: Dictionary = hits[j]
				if _hit_key(k) == _hit_key(h):
					continue
				var inter := r.intersection(k.get("rect", Rect2()))
				if inter.size.x * inter.size.y >= area * 0.98:
					_dead_hotspot(label, "%s 被更晚画的 %s 整块盖住 %s" % [id, str(k.get("id", "cb")), str(r)])
					break

## 同一个 id 可能是一排格子（map 的 6 个 "node"、烤架的 "grill"），只比 id 会把
## "A 格被 B 格盖住" 这种真死区直接放过，所以身份要带上除 rect 以外的全部字段。
func _hit_key(h: Dictionary) -> String:
	var parts: Array = []
	for k in h.keys():
		if k == "rect":
			continue
		parts.append("%s=%s" % [k, str(h[k])])
	parts.sort()
	return "|".join(PackedStringArray(parts))

func _dead_hotspot(label: String, msg: String) -> void:
	dead_hits.append(label + " → " + msg)
	if HOTSPOT_STRICT:
		fails.append("死热区 " + label + " " + msg)

func _shot(name: String) -> void:
	# 等待一次渲染帧；最多等 5 秒（窗口被隐藏/最小化时不无限阻塞，标记失败并继续）
	var got := [false]
	var cb := func() -> void: got[0] = true
	RenderingServer.frame_post_draw.connect(cb, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not got[0] and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if RenderingServer.frame_post_draw.is_connected(cb):
		RenderingServer.frame_post_draw.disconnect(cb)
	if not got[0]:
		fails.append("screenshot no frame within 5s: " + name)
		print("[autotest] SHOT FAIL no-frame ", name)
		return
	_scan_hits(name)
	var img := get_viewport().get_texture().get_image()
	var path := shot_dir + "/" + name + ".png"
	var err := img.save_png(path)
	if err == OK:
		var sz := 0
		if FileAccess.file_exists(path):
			sz = FileAccess.open(path, FileAccess.READ).get_length()
		print("[autotest] SHOT %s size=%d" % [name, sz])
		if sz < 5000:
			fails.append("screenshot suspiciously small: " + name)
		shots.append(path)
	else:
		fails.append("screenshot failed: " + name)
		print("[autotest] SHOT FAIL ", name, " err=", err)

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
