extends Node
const TestEnv := preload("res://tests/test_env.gd")
## 冒烟测试（无窗口全逻辑验证）：
##   godot --headless --path <项目> -- --test=smoke
## 覆盖：配置加载、存档往返、连续两日营业、柴火系统、边界情况、升级、配置热重载、稳定性连打。

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
	print("============ SMOKE TEST START ============")
	_backup_saves()
	GameState.reset_for_new_game()
	_test_config()
	_test_music_no_hitch()
	_test_art_refs()
	_test_new_game_and_save()
	var d1 := _run_day(1, 424242)
	var d2 := _run_day(2, 909090)
	_test_ledger_and_reload()
	_test_ledger_trim()
	_test_coins()
	_test_class_cache_ships()
	_test_burger_conservation()
	_test_sound_levels()
	_test_fire_system()
	_test_fryer_baskets()
	_test_edge_cases()
	_test_upgrades()
	_test_config_reload()
	_test_stability_spam()
	# 这两条会改写存档与 GameState，放在所有依赖存档的用例之后
	_test_corrupt_save()
	_test_healthy_save()
	_test_bad_player_type()
	_dump_evidence()
	_restore_saves()
	print("============ RESULT ============")
	if not skipped_source_gates.is_empty():
		print("SOURCE_GATES SKIPPED=%d: %s" % [skipped_source_gates.size(), ", ".join(PackedStringArray(skipped_source_gates))])
	print("checks=%d passed=%d failed=%d" % [checks, passes, fails.size()])
	for f in fails:
		print("FAIL: ", f)
	if fails.is_empty():
		print("SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		print("SMOKE: FAIL")
		get_tree().quit(1)

func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("CHECK FAILED: ", label)

func _test_art_refs() -> void:
	# 新增菜品最容易翻车的地方：配置里加了 id，素材却没人产。
	# 这类缺失不会报错，只会在解锁那天把小票画成一块空白，所以在这里一次性堵死。
	var missing := PackedStringArray()
	var want := PackedStringArray()
	for b in Config.burgers():
		want.append("food/food_burger_" + str((b as Dictionary).get("id", "")))
	for x in Config.drinks():
		want.append(str((x as Dictionary).get("art", "")))
	for x in Config.sauces():
		want.append(str((x as Dictionary).get("art", "")))
	# sides / stations 目前还没有玩法读它们，但既然登记了素材就得能 load 出来，
	# 否则接托盘槽位那天会画成空白
	for k in Config.dishes.get("sides", {}):
		want.append(str((Config.dishes["sides"][k] as Dictionary).get("art", "")))
	for k in Config.dishes.get("stations", {}):
		want.append(str((Config.dishes["stations"][k] as Dictionary).get("art", "")))
	for k in Config.all_shelf_order():
		var key := str(k)
		if not UiKit.ING_ICONS.has(key):
			missing.append("ING_ICONS[" + key + "]")
			continue
		want.append(str(UiKit.ING_ICONS[key]))
	for i in Config.species_count():
		want.append("characters/full_" + str(Config.species(i).get("id", "")))
	for pth in want:
		if str(pth) == "" or UiKit.art(str(pth)) == null:
			missing.append(str(pth))
	# 代码里写死引用的剧情道具，同样得 load 得出来
	for pth in ["props/photo_back", "ui/avatar_frame", "kitchen/wood_pile", "ui/ic_sound"]:
		want.append(pth)
	# 地图站点靠路牌坐标排版，缺了整页会糊在一起
	if Config.map_nodes().is_empty():
		missing.append("data/config/map.json nodes")
	if UiKit.art("ui/map_bg") == null:
		missing.append("ui/map_bg")
	check(missing.is_empty(), "every data-driven art path resolves")
	if not missing.is_empty():
		print("[art] MISSING ", missing.size(), ": ", ", ".join(missing))

# ---------------- 基础 ----------------
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
	print("[setup] saves restored")

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

func _top_inventory(n: int) -> void:
	for k in Config.start_inventory().keys():
		GameState.inventory[k] = n

## 酱料瓶的天数门控是配置驱动的（用户先要"以后过关再加"、回退后又改回开局就在），
## 所以这里不写死天数，只验"跟着 sauce_unlock_day 翻"这件事本身。
func _test_sauce_gate() -> void:
	var keep_day := GameState.day
	var want := Config.sauce_unlock_day()
	GameState.day = want + 3
	check(Config.sauces_open(), "过了 sauce_unlock_day 酱料一定上台面")
	if want > 1:
		GameState.day = want - 1
		check(not Config.sauces_open(), "解锁前一天酱料还不上台面")
	else:
		print("[sauce] sauce_unlock_day=1 → 开局就在台上，前一天无从验")
	GameState.day = keep_day

## 客流表和解锁表必须互相对齐。两个方向都会烂：
## 计划点到当天还没解锁的堡 = 顾客要一份拼不出来的单，变成必走单；
## 菜谱整周无人点 = 素材、货架格、图鉴页全是白做的（培根蛋堡/酸笋堡就这么哑了七天才被发现）。
func _test_plan_gates() -> void:
	var days := Config.total_days()
	var locked_hits: Array = []
	var ing_hits: Array = []
	var ordered := {}
	for d in range(1, days + 1):
		for c in Config.day_plan(d):
			var bi := int((c as Dictionary).get("burger", 0))
			var b := Config.burger(bi)
			if b.is_empty():
				locked_hits.append("day%d burger#%d 不存在" % [d, bi])
				continue
			var b_day := int(b.get("unlock_day", 1))
			if b_day > d:
				locked_hits.append("day%d 点了第%d天解锁的 %s" % [d, b_day, str(b.get("id", bi))])
			for k in b.get("stack", []):
				var kd := int(Config.ingredient(str(k)).get("unlock_day", 1))
				if kd > d:
					ing_hits.append("day%d 的 %s 要第%d天才上架的 %s" % [d, str(b.get("id", bi)), kd, str(k)])
			ordered[bi] = int(ordered.get(bi, 0)) + 1
	check(locked_hits.is_empty(), "客流表不点到未解锁的堡（违例 %d 条）" % locked_hits.size())
	for x in locked_hits:
		print("   ! ", x)
	check(ing_hits.is_empty(), "每天点的堡其配料当天都在架上（违例 %d 条）" % ing_hits.size())
	for x in ing_hits:
		print("   ! ", x)
	var dead: Array = []
	for i in Config.burgers().size():
		if not ordered.has(i):
			dead.append(str(Config.burger(i).get("id", i)))
	check(dead.is_empty(), "每道堡整周至少被点一次（无人点单: %s）" % str(dead))
	var mix: Array = []
	for i in ordered.keys():
		mix.append("%s x%d" % [str(Config.burger(int(i)).get("short", i)), int(ordered[i])])
	print("[plan] 全周点单分布: ", ", ".join(PackedStringArray(mix)))
	# 声望门槛：超过 rep_max 就永远达不到，那道菜等于被删掉
	var rep_max := int(float(Config.economy.get("rep_max", 5.0)))
	var unreachable: Array = []
	for i in Config.burgers().size():
		if int(Config.burgers()[i].get("unlock_rep", 0)) > rep_max:
			unreachable.append(str(Config.burgers()[i].get("id", i)))
	check(unreachable.is_empty(), "每道堡的声望门槛都可达成（超档: %s）" % str(unreachable))
	var mults: Array = Config.economy.get("rep_tip_mult", [])
	check(mults.size() == rep_max + 1, "rep_tip_mult 档数 = 0..rep_max（实得 %d / 应为 %d）" % [mults.size(), rep_max + 1])
	check(absf(Config.rep_tip_mult(3) - 1.0) < 0.0001, "开局 3★ 倍率仍是 1.0，不动既有平衡")
	check(Config.rep_tip_mult(rep_max) > Config.rep_tip_mult(1), "声望越高小费越高")
	# 声望不足时计划必须落到一道真做得出的堡上，否则就是必走单
	var keep_day := GameState.day
	var keep_rep := GameState.rep
	GameState.day = 5
	GameState.rep = 1.0
	check(GameState.rep_stars() < 3, "构造出 3★ 以下的低声望态")
	var fallback_ok := true
	var open5: Array = Config.open_burger_indices()
	for i in Config.burgers().size():
		var r := Config.burger_resolved(i)
		if not open5.has(r):
			fallback_ok = false
	check(fallback_ok, "低声望下第 5 天每张计划单都回退到可点菜单（可点 %s）" % str(open5))
	check(Config.burger_resolved(0) == 0, "已解锁的单不被改动")
	GameState.day = keep_day
	GameState.rep = keep_rep

## 代码里读了的文案键，必须真的取得出非空值。
## 起因：预告页那枚 44 号大标题写的是 `Config.ui("teaser_title")`，而 `ui()` 读的是
## `story["ui"]` 那个块，`teaser_title` 却在 story 顶层；外面判存在的那句
## `Config.story.has("teaser_title")` 查的又是顶层——于是"键在"为真、取回来是空串，
## 「未完待续」从来没画出来过，而所有测试全绿。**判存在的键和取值的键必须指向同一处。**
func _test_copy_keys() -> void:
	var files := _source_files_or_skip("_test_copy_keys 文案键")
	if files.is_empty():
		return
	var re_acc := RegEx.new()
	re_acc.compile("Config\\.(ui|misc|tooltip|snark_lines)\\(\"([A-Za-z0-9_]+)\"\\)")
	var re_top := RegEx.new()
	re_top.compile("Config\\.story\\.get\\(\"([A-Za-z0-9_]+)\"")
	var blocks := {"ui": "ui", "misc": "misc", "tooltip": "tooltips", "snark_lines": "snarks"}
	var scanned := 0
	var judged := 0
	var skipped_comment := 0
	var bad: Array = []
	for f in files:
		if str(f).ends_with("smoke_test.gd"):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string(f)
		var short := str(f).replace("res://", "")
		# 逐行喂：整行注释里出现的 Config.ui("x") 不是引用，是解释。
		# 只跳"行首就是 #"的整行注释——行尾注释不敢按 # 切，Color("#ffd98a") 里就有 #，
		# 切了会把真引用一起吞掉。所以行尾注释里的假阳性仍是这条闸的已知盲区。
		var code_lines := PackedStringArray()
		for ln in text.split("\n"):
			if str(ln).strip_edges().begins_with("#"):
				skipped_comment += 1
				continue
			code_lines.append(ln)
		var code := "\n".join(code_lines)
		for m in re_acc.search_all(code):
			judged += 1
			var acc := str(m.get_string(1))
			var key := str(m.get_string(2))
			var block := str(blocks[acc])
			var table = Config.story.get(block, {})
			var val = null
			if typeof(table) == TYPE_DICTIONARY:
				val = (table as Dictionary).get(key, null)
			var ok := false
			if acc == "snark_lines":
				ok = typeof(val) == TYPE_ARRAY and (val as Array).size() > 0
			else:
				ok = val != null and str(val) != ""
			if not ok:
				bad.append("%s  Config.%s(\"%s\") ← story.%s 取不到非空值" % [short, acc, key, block])
		for m in re_top.search_all(code):
			judged += 1
			var tkey := str(m.get_string(1))
			if not Config.story.has(tkey):
				bad.append("%s  Config.story.get(\"%s\") ← story 顶层没有这个键" % [short, tkey])
	check(scanned >= 30, "文案键闸实扫脚本 %d 个（少于 30 就是扫描器没跑到）" % scanned)
	check(bad.is_empty(), "代码引用的文案键全部取得出值（坏 %d 个 / 判 %d 处）" % [bad.size(), judged])
	for x in bad:
		print("   ! ", x)
	print("[copy] 扫 %d 个脚本、判 %d 处文案取值（跳过整行注释 %d 行），坏的 %d 处" % [
		scanned, judged, skipped_comment, bad.size()])

## 章模型的闸。进度从"按天"改成"按章"之后，第几天属于第几章、章末有没有内容接得住，
## 全部是配置之间要对齐的事，代码里任何一处都查不出来。每条都自报判到几个。
func _test_chapter_gates() -> void:
	var chs: Array = Config.chapters()
	check(not chs.is_empty(), "chapters 表存在（%d 章）" % chs.size())
	var sum_days := 0
	for c in chs:
		sum_days += maxi(1, int((c as Dictionary).get("days", 1)))
	check(Config.total_days() == sum_days, "total_days() = 各章天数之和（%d vs %d）" % [Config.total_days(), sum_days])
	check(Config.chapter_of(1) == 1, "第 1 天落在第 1 章")
	var b1 := Config.chapter_end_day(1)
	check(b1 == Config.chapter_days(1), "第一章末日 = 第一章天数（%d）" % b1)
	check(Config.chapter_of(b1) == 1 and Config.chapter_of(b1 + 1) == 2,
		"第 %d→%d 天正好跨章" % [b1, b1 + 1])
	check(Config.chapter_of(Config.total_days() + 50) == Config.chapter_count(), "endless 归到最后一章")
	check(Config.is_chapter_end(b1) and not Config.is_chapter_end(b1 - 1), "章末只落在每章最后一天")
	var no_end: Array = []
	var no_intro: Array = []
	var no_nodes: Array = []
	var no_plan: Array = []
	for ch in range(1, Config.chapter_count() + 1):
		var end_day := Config.chapter_end_day(ch)
		if Config.ending_lines(ch).is_empty():
			no_end.append("ch%d" % ch)
		if Config.map_nodes(Config.chapter_start_day(ch)).is_empty():
			no_nodes.append("ch%d" % ch)
		if Config.day_plan(end_day).is_empty():
			no_plan.append("ch%d(第%d天)" % [ch, end_day])
		if ch > 1 and not Config.has_chapter_intro(ch):
			no_intro.append("ch%d" % ch)
	check(no_end.is_empty(), "每章都有章末结语（缺: %s）" % str(no_end))
	check(no_intro.is_empty(), "第二章起都有开场剧情（缺: %s）" % str(no_intro))
	check(no_nodes.is_empty(), "每章都有街区地图点位（缺: %s）" % str(no_nodes))
	check(no_plan.is_empty(), "章末那天有显式客流表，不会滚进 endless（缺: %s）" % str(no_plan))
	# 点位天数要落在自己那一章的区间里：否则 _state() 会把上一章走过的站读成"还没解锁"
	var strays: Array = []
	for ch in range(1, Config.chapter_count() + 1):
		var lo := Config.chapter_start_day(ch)
		var hi := Config.chapter_end_day(ch)
		for n in Config.map_nodes(lo):
			var nd := int((n as Dictionary).get("day", 0))
			if nd < lo or nd > hi:
				strays.append("ch%d 点位 day=%d 越界 [%d,%d]" % [ch, nd, lo, hi])
	check(strays.is_empty(), "每章点位都在本章天数区间内（越界 %d 条）" % strays.size())
	for x in strays:
		print("   ! ", x)
	# "难度慢慢上升"的机器化说法：换章第一天不许比上一章最后一天松
	var dips: Array = []
	for ch in range(2, Config.chapter_count() + 1):
		var prev := Config.day_plan(Config.chapter_end_day(ch - 1)).size()
		var cur := Config.day_plan(Config.chapter_start_day(ch)).size()
		if cur < prev:
			dips.append("ch%d 首日 %d 单 < ch%d 末日 %d 单" % [ch, cur, ch - 1, prev])
	check(dips.is_empty(), "换章不许掉客流（违例: %s）" % str(dips))
	# "难度慢慢上升"的第二种说法：本章平均每天要叠的层数不许比上一章低。
	# 判的是编排（配置里写死的），不判 bot 表现——手速放到 3 次/秒时两章都零流失，
	# 拿实测流失率当硬闸就是一条会随机变红的闸；它只打印，不判。
	var load_report: Array = []
	var load_dip: Array = []
	var load_prev := 0.0
	for ch in range(1, Config.chapter_count() + 1):
		var items := 0
		var custs := 0
		var n_days := 0
		for d in range(Config.chapter_start_day(ch), Config.chapter_end_day(ch) + 1):
			var plan: Array = Config.day_plan(d)
			n_days += 1
			custs += plan.size()
			for c in plan:
				var b := Config.burger(int((c as Dictionary).get("burger", 0)))
				items += (b.get("stack", []) as Array).size()
		var per_day := float(items) / float(maxi(n_days, 1))
		load_report.append("ch%d %.1f层/天（%d 客 × %d 天）" % [ch, per_day, custs, n_days])
		if ch > 1 and per_day <= load_prev:
			load_dip.append("ch%d %.1f 不高于 ch%d %.1f" % [ch, per_day, ch - 1, load_prev])
		load_prev = per_day
	check(load_dip.is_empty(), "每章编排负载不低于上一章（违例: %s）" % str(load_dip))
	print("[load] ", " | ".join(PackedStringArray(load_report)))
	var ends: Array = []
	for ch in range(1, Config.chapter_count() + 1):
		ends.append(str(Config.chapter_end_day(ch)))
	print("[chapter] %d 章 / 共 %d 天，章末落在第 %s 天" % [
		Config.chapter_count(), Config.total_days(), ", ".join(PackedStringArray(ends))])

## 切屏不许在主线程现场烘环境音：一床 24 秒的浪要算 1.8 秒，
## 玩家那一下「开始营业」就点在冻住的窗口上（这轮修的就是它）。
func _test_music_no_hitch() -> void:
	var was_muted := Music.muted
	Music.set_muted(false)
	var t0 := Time.get_ticks_msec()
	for id in ["town", "cook", "win"]:
		Music.play_track(String(id))
	var ms := Time.get_ticks_msec() - t0
	Music.stop()
	Music.set_muted(was_muted)
	print("[music] 三次换床 %dms，启动已烘好=%s" % [ms, str(Music.warm())])
	check(ms < 150, "换床不许现场烘（实测 %dms，主线程烘一首要 ~1800ms）" % ms)

## 工位吃掉的原料必须买得到，而且买的时候要有自己的图标。
## 可乐是饮料机的原料，却只出现在 start_inventory 和 ingredients 表里、不在任何补货列表上：
## 开局那 10 杯用完，之后所有带饮料的单永远做不出来。经济闸门用 buy_ingredient 直接补货，
## 恰好绕开了"UI 里买不到"这件事，所以这条必须单独立闸。
func _test_stock_purchasable() -> void:
	var buyable: Array = Config.shop_order()
	var missing: Array = []
	var noicon: Array = []
	for k in ["patty", "potato", "drink"] + Config.all_shelf_order():
		var key := str(k)
		if not buyable.has(key):
			missing.append(key)
		if not UiKit.ING_ICONS.has(key):
			noicon.append(key)
	check(missing.is_empty(), "工位消耗的原料全部买得到（商店/卡车缺: %s）" % str(missing))
	check(noicon.is_empty(), "可买原料都有专属图标，不会退回面包胚（缺: %s）" % str(noicon))
	# 注意：Godot 的 JSON 把所有数字都读成 float，这里必须 int(...) 取值，不能判 is int
	check(int(Config.ingredient("drink").get("cost", 0)) > 0, "可乐有单价，补货才收得到钱")

## ui/plaque 四角的花叶会啃掉牌面 0~14% 和 80%~100%（量自素材中段净空 0.139~0.802）。
## draw_title 现在按这个净空反推牌宽，所以任何一条标题文案变长到牌撑不下时必须当场红。
func _test_plaque_fit() -> void:
	var sites: Array = [
		["title", str(Config.ui("title")), 40],
		["day_end", str(Config.ui("dayend_title_fmt")) % 7, 32],
		["help", str(Config.ui("help_title")), 30],
		["records", str(Config.ui("records_title")), 30],
		["shop", str(Config.ui("shop_title_fmt")) % 7, 26],
		["map", str(Config.map_caption()), 28],
	]
	var bad: Array = []
	var worst := 0.0
	var worst_at := ""
	for s in sites:
		var tw := UiKit.text_width(str(s[1]), int(s[2]), true)
		var bw := minf(maxf(tw + float(s[2]) * 3.0, tw / UiKit.PLAQUE_TEXT_FRAC), 1100.0)
		var frac := tw / bw
		if frac > worst:
			worst = frac
			worst_at = str(s[0])
		if frac > UiKit.PLAQUE_TEXT_FRAC + 0.001:
			bad.append("%s「%s」占牌面 %.0f%%" % [str(s[0]), str(s[1]), frac * 100.0])
	print("[plaque] 扫 %d 个木牌标题，最挤 %s 占 %.0f%%（净空上限 %.0f%%）"
		% [sites.size(), worst_at, worst * 100.0, UiKit.PLAQUE_TEXT_FRAC * 100.0])
	check(bad.is_empty(), "木牌标题全部落在花叶净空内（已覆盖 %d 处，最挤 %.0f%%/上限 %.0f%%%s）"
		% [sites.size(), worst * 100.0, UiKit.PLAQUE_TEXT_FRAC * 100.0, "" if bad.is_empty() else " → " + "; ".join(PackedStringArray(bad))])
	check(sites.size() == 6, "这条闸自己扫满 6 个 draw_title 调用点")

## 包内自检和玩家玩的那份用的是同一个 user://saves/，收尾的 _restore_saves() 会把
## 开测前的内容写回去。测试模式必须整体换目录——这条拿"另一条路径"当被告，不是复读 save_dir。
func _test_save_isolation() -> void:
	var player_dir := SaveManager.save_dir_player
	var cur := SaveManager.save_dir
	print("[saves] 测试目录=%s 玩家目录=%s" % [cur, player_dir])
	check(cur == SaveManager.TEST_SAVE_DIR, "自检写的是隔离目录（实为 %s）" % cur)
	check(not cur.is_empty() and cur != player_dir, "自检目录和玩家存档目录不是同一个")
	check(not player_dir.is_empty(), "玩家存档目录仍被记录着，envcheck 才报得出真实落点")

## 存档"读不出来"和"没玩过"以前走的是同一条分支：悄悄开新局，下一局 save_all()
## 就把那份文件原地盖掉，进度彻底没了、也没人说过一句。这条验的是留底 + 说得出。
func _test_corrupt_save() -> void:
	# 这条要往存档路径写垃圾，所以必须自己确认隔离还在——万一 use_isolated_saves() 被谁挪掉，
	# 没有这道闩就会把玩家真正那份存档写成损坏文件。
	if SaveManager.save_dir != SaveManager.TEST_SAVE_DIR:
		check(false, "损坏存档用例拒绝执行：当前不在隔离目录（%s）" % SaveManager.save_dir)
		return
	var path := SaveManager.save_path()
	var junk := '{"version":1,"saved_at":"2026-09-30T11:22:33","player":{"coins":4'
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		check(false, "损坏存档用例没能写入（拿不到写权限，整条没测）")
		return
	f.store_string(junk)
	f.close()
	SaveManager.load_all()
	check(str(SaveManager.load_error) != "", "损坏存档会给出原因（实为「%s」）" % str(SaveManager.load_error))
	check(not SaveManager.has_save, "损坏存档不会被当成「有档可继续」")
	check(not FileAccess.file_exists(path), "损坏的原文件已挪走，下一局 save_all() 不会原地盖掉它")
	var kept := ""
	var backups := 0
	var dir := DirAccess.open(SaveManager.save_dir)
	if dir != null:
		for fn in dir.get_files():
			if str(fn).contains(".corrupt-"):
				backups += 1
				kept = FileAccess.get_file_as_string(SaveManager.save_dir + str(fn))
	check(backups == 1, "留底文件恰好一份（实为 %d 份）" % backups)
	check(kept == junk, "留底里是原字节，一个字符都没改")
	# 收尾：把留底清掉，别在隔离目录里堆垃圾
	if dir != null:
		for fn in dir.get_files():
			if str(fn).contains(".corrupt-"):
				dir.remove(str(fn))
	SaveManager.load_all()
	check(str(SaveManager.load_error) == "", "清干净之后不再报损坏")

## 好档路径也要一起判，否则"损坏"改对了、"正常"改坏了也看不出来。
## 注意这里不能用 reset_for_new_game()——它里面调 SaveManager.wipe() 会把刚存的档删掉
## （第一版就栽在这儿，报"金币 0 / 第 1 天"，看着像 load_all 坏了）。要清内存态用 initialize_new()。
func _test_healthy_save() -> void:
	GameState.initialize_new()
	GameState.coins = 1234
	GameState.day = 3
	check(SaveManager.save_all(), "正常存档写入成功")
	GameState.initialize_new()
	SaveManager.load_all()
	check(str(SaveManager.load_error) == "", "正常存档不会被误判成损坏")
	check(SaveManager.has_save and GameState.coins == 1234 and GameState.day == 3,
		"正常存档读得回来（金币 %d / 第 %d 天）" % [GameState.coins, GameState.day])

## 能解析、但 player 不是字典（手改过 / 半截写入）：apply_save_dict 的形参是 Dictionary，
## 传 Array 进去会在 SaveManager._ready 里抛 SCRIPT ERROR，游戏直接起不来。
## 这种也要归到"损坏"那条路，而不是当成坏输入硬喂下去。
func _test_bad_player_type() -> void:
	if SaveManager.save_dir != SaveManager.TEST_SAVE_DIR:
		check(false, "player 类型用例拒绝执行：当前不在隔离目录（%s）" % SaveManager.save_dir)
		return
	var path := SaveManager.save_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		check(false, "player 类型用例没能写入（整条没测）")
		return
	f.store_string('{"version":1,"saved_at":"2026-09-30T11:22:33","player":[1,2]}')
	f.close()
	SaveManager.load_all()
	check(str(SaveManager.load_error) != "", "player 类型不对也报损坏，而不是硬喂给 typed 形参（实为「%s」）" % str(SaveManager.load_error))
	check(not SaveManager.has_save, "player 类型不对时不会假装「有档可继续」")
	check(GameState.day >= 1 and GameState.coins >= 0, "兜底出来的是一份能玩的初始档")
	var dir := DirAccess.open(SaveManager.save_dir)
	if dir != null:
		for fn in dir.get_files():
			if str(fn).contains(".corrupt-"):
				dir.remove(str(fn))
	SaveManager.wipe()
	SaveManager.load_all()
	check(str(SaveManager.load_error) == "", "清干净之后不再报损坏")

## 七条"点了没反应"的路径以前全是静默 return：案板压着别的食材、堡已叠满、同一瓶酱挤第二次、
## 酱到上限、正在接杯中点另一罐、客人还在走进来、客人已经走开。
## 玩家把这些读成"这玩意要双击"，所以每条都必须自己说出原因。
func _test_no_silent_clicks() -> void:
	_top_inventory(24)
	var sim := DaySim.new()
	sim.start(2, 4242)
	var heard: Array = []
	sim.snark_requested.connect(func(t: String) -> void: heard.append(t))
	var mute: Array = []

	## 每条都比对"该说的那句原话"，只数句数的话，冒名顶替的另一条提示也能让它过。
	var expect := func(key: String, args: Array) -> String:
		var want := str(Config.misc(key))
		return want % args if not args.is_empty() else want
	var judged := [0]
	var judge := func(label: String, want: String) -> void:
		judged[0] += 1
		if heard.size() != 1:
			mute.append("%s（听到 %d 句: %s）" % [label, heard.size(), str(heard)])
		elif str(heard[0]) != want:
			mute.append("%s（说的是「%s」，该说「%s」）" % [label, str(heard[0]), want])

	# 1) 案板压着生菜，去点番茄
	sim.board["ing"] = "lettuce"
	heard.clear()
	sim.tap_shelf("tomato")
	judge.call("board_busy", expect.call("board_busy", [Config.ingredient_name("lettuce")]))

	# 2) 堡已经叠满，再点食材架
	sim.board["ing"] = ""
	sim._spawn_customer()
	var c = sim.queue[sim.queue.size() - 1]
	c.state = "waiting"
	c.walk_t = 99.0
	sim.target = sim.queue.size() - 1
	var rec := Config.burger(c.burger_idx())
	var stack: Array = rec.get("stack", [])
	sim.assembly.clear()
	for k in stack:
		sim.assembly.append(str(k))
	heard.clear()
	sim.tap_shelf(str(stack[0]))
	judge.call("stack_full", expect.call("stack_full", [str(rec.get("name", ""))]))

	# 3) 同一瓶酱挤第二次
	sim.sauces_used = {}
	check(sim.apply_sauce(0), "第一瓶酱能挤上")
	heard.clear()
	sim.apply_sauce(0)
	judge.call("sauce_once", expect.call("sauce_once", []))

	# 4) 酱到上限还挤第四瓶
	sim.sauces_used = {}
	var defs: Array = Config.sauces()
	for i in DaySim.SAUCE_MAX:
		sim.sauces_used[str((defs[i] as Dictionary).get("id", i))] = true
	heard.clear()
	sim.apply_sauce(DaySim.SAUCE_MAX)
	judge.call("sauce_full", expect.call("sauce_full", [DaySim.SAUCE_MAX]))

	# 5) 正在接杯中点另一罐
	sim.drink["p"] = 0.5
	sim.drink_jar = 0
	heard.clear()
	sim.tap_drink(1)
	judge.call("drink_pouring", expect.call("drink_pouring", []))

	# 6/7) 客人还在走进来 / 已经走开时点他（整副身体都是热区）
	if sim.queue.is_empty():
		sim._spawn_customer()
	var cw = sim.queue[sim.queue.size() - 1]
	cw.state = "walking"
	heard.clear()
	sim.tap_customer(cw)
	judge.call("cust_walking", expect.call("cust_walking", []))
	cw.state = "leaving"
	heard.clear()
	sim.tap_customer(cw)
	judge.call("cust_gone", expect.call("cust_gone", []))

	print("[silent] 查 %d 条静默点击路径（实到 %d 条），仍哑或说错 %d 条" % [7, judged[0], mute.size()])
	check(judged[0] == 7, "七条路径全部判到了（实到 %d 条，少了就是有的分支没跑起来）" % judged[0])
	check(mute.is_empty(), "七条静默点击路径全部说出该说的那句（问题: %s）" % str(mute))

func _test_config() -> void:
	print("[config] load_errors=", Config.load_errors.size())
	check(Config.load_errors.is_empty(), "config loads without errors")
	check(Config.burgers().size() >= 3, "burgers defined")
	var stack_ok := true
	for b in Config.burgers():
		for k in b.get("stack", []):
			if Config.ingredient(str(k)).is_empty():
				stack_ok = false
	check(stack_ok, "every recipe ingredient exists")
	var day1_ok := true
	for k in Config.shelf_order():
		if int(Config.ingredient(str(k)).get("unlock_day", 1)) > 1:
			day1_ok = false
	check(day1_ok and not Config.shelf_order().is_empty(), "day1 shelf only shows unlocked")
	check(Config.species_count() == 5, "5 species defined")
	check(Config.day_plan(1).size() == 8, "day1 plan has 8 customers")
	check(Config.day_plan(7).size() == 14, "day7 plan has 14 customers")
	check(Config.upgrade_defs().size() >= 5, "at least 5 upgrades defined")
	check(not Config.upgrade_def("autoturn").is_empty() and not Config.upgrade_def("quickcut").is_empty(),
		"两个「省点击」升级已登记")
	check(float(Config.cook("grill").get("full_seconds", 0)) > 0.0, "grill cooking config present")
	check(float(Config.fire.get("decay_per_sec", 0)) > 0.0, "fire decay config present")
	check(Config.intro_lines().size() == 4, "intro has 4 lines")
	check(Config.mystery_lines().size() == 6, "mystery has 6 lines")
	check(Config.tutorial_steps().size() == 5, "5 tutorial steps")
	# 解锁播报的三条文案：占位符丢了就会把 "%s" 原样飘给玩家看
	var ma := Config.misc("menu_added")
	var su := Config.misc("star_up")
	var sl := Config.misc("star_unlocked")
	check(ma.contains("%s") and su.contains("%d") and sl.contains("%d") and sl.contains("%s"),
		"解锁播报三条文案都带占位符")
	_test_sauce_gate()
	_test_stock_purchasable()
	_test_plaque_fit()
	_test_save_isolation()
	_test_no_silent_clicks()
	_test_plan_gates()
	_test_chapter_gates()
	_test_copy_keys()
	# 素材引用完整性：脚本里字面量 art("路径") 必须都有对应文件（跳过本测试脚本自身）
	_scan_art_refs()
	_scan_sound_refs()
	_test_font_floor()
	# 动态拼接 / 间接引用的关键素材清单
	var dynamic_refs: Array = [
		"backgrounds/bg_title", "backgrounds/bg_play_pov", "backgrounds/bg_mystery",
		"kitchen/bg_dev_table", "kitchen/dev_grill", "kitchen/dev_fryer", "kitchen/dev_dispenser",
		"kitchen/dev_board", "kitchen/dev_tray_empty",
		"characters/chef_smirk", "characters/chef_shock", "characters/chef_side",
		"food/food_fries", "food/food_cola",
		"food/food_burger_classic", "food/food_burger_veggie", "food/food_burger_double"
	]
	for rel in dynamic_refs:
		check(ResourceLoader.exists(UiKit.ART_DIR + str(rel) + ".png"), "dynamic art " + str(rel) + " exists")
	# 动态拼接的关键素材族
	for sp_def in Config.customers.get("species", []):
		var sid := str(sp_def.get("id", ""))
		check(ResourceLoader.exists(UiKit.ART_DIR + "characters/full_" + sid + ".png"), "art full_" + sid + " exists")
	for mood in ["smirk", "shock", "side"]:
		check(ResourceLoader.exists(UiKit.ART_DIR + "characters/chef_" + mood + ".png"), "art chef_" + mood + " exists")
	for ing_key in UiKit.ING_ICONS.keys():
		check(ResourceLoader.exists(UiKit.ART_DIR + UiKit.ING_ICONS[ing_key] + ".png"), "art icon " + str(ing_key) + " exists")

func _scan_art_refs() -> void:
	var re := RegEx.new()
	re.compile("art\\(\"([^\"]+)\"\\)")
	var missing := 0
	var scanned := 0
	var files := _source_files_or_skip("_scan_art_refs 素材引用")
	if files.is_empty():
		return
	for f in files:
		if str(f).ends_with("smoke_test.gd"):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string(f)
		for m in re.search_all(text):
			var rel := m.get_string(1)
			if not ResourceLoader.exists(UiKit.ART_DIR + rel + ".png"):
				missing += 1
				print("MISSING ART: ", rel, " <- ", f)
	print("[scan] 素材引用闸实扫 %d 个脚本文件" % scanned)
	check(missing == 0, "all literal art() references exist")

func _scan_sound_refs() -> void:
	var re1 := RegEx.new()
	re1.compile("Sfx\\.play\\(\"([^\"]+)\"\\)")
	var re2 := RegEx.new()
	re2.compile("sfx_requested\\.emit\\(\"([^\"]+)\"\\)")
	var bad := 0
	var scanned := 0
	var files := _source_files_or_skip("_scan_sound_refs 音效名")
	if files.is_empty():
		return
	for f in files:
		scanned += 1
		var text := FileAccess.get_file_as_string(f)
		for m in re1.search_all(text):
			if not (str(m.get_string(1)) in Sfx.SOUND_NAMES):
				bad += 1
				print("UNKNOWN SOUND: ", m.get_string(1), " <- ", f)
		for m2 in re2.search_all(text):
			if not (str(m2.get_string(1)) in Sfx.SOUND_NAMES):
				bad += 1
				print("UNKNOWN SOUND: ", m2.get_string(1), " <- ", f)
	check(bad == 0, "all sound names registered")
	print("[scan] 音效名闸实扫 %d 个脚本文件" % scanned)

## 从 "(" 之后开始按顶层逗号切参数（跟着引号和嵌套括号走），返回实参列表。
func _call_args(text: String, open_at: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var depth := 0
	var instr := false
	var i := open_at + 1
	while i < text.length():
		var ch := text[i]
		if ch == "\"":
			instr = not instr
		if not instr:
			if ch == "(":
				depth += 1
			elif ch == ")":
				if depth == 0:
					out.append(cur.strip_edges())
					return out
				depth -= 1
			elif ch == "," and depth == 0:
				out.append(cur.strip_edges())
				cur = ""
				i += 1
				continue
		cur += ch
		i += 1
	out.append(cur.strip_edges())
	return out

## 字号下限 12px。酱料标签的 11 号是 v13 那版窄布局留下的，回退 v12 之后 pitch 翻倍却没人回去调，
## 所以这条要常驻。只能判字面量（表达式取不到值），因此"扫了几处 / 判到几处"必须一起印出来，
## 不然覆盖塌了看不出来。
const FONT_MIN := 12
const FONT_ARG := {"draw_text": 3, "draw_text_in": 3, "draw_text_centered": 4, "draw_text_right": 4}

func _test_font_floor() -> void:
	var files := _source_files_or_skip("_test_font_floor 字号下限")
	if files.is_empty():
		# 读不到源码就整条跳过：这时 total 是 0，拿它去比下限会报一个假的"覆盖塌了"
		return
	var total := 0
	var literal := 0
	var via_var := 0
	var bad: Array = []
	for f in files:
		if str(f).ends_with("smoke_test.gd"):
			continue
		var text := FileAccess.get_file_as_string(f)
		# 记每处 "var 名字 := 整数字面量" 的位置。字号常走变量传进来（酱料标签就是），
		# 只认字面量抓不到；而按"文件内唯一值"来认又会被同名局部变量撞掉
		# （play.gd 里饮料标签和酱料标签各有一个 tsz），所以要按位置回到它所属的那个函数。
		var assigns: Array = []
		var vr := RegEx.create_from_string("var\\s+(\\w+)\\s*:?\\s*=\\s*(\\d+)(?![\\d.])")
		for vm in vr.search_all(text):
			assigns.append([vm.get_start(), vm.get_string(1), int(vm.get_string(2))])
		var funcs := PackedInt32Array()
		var fr := RegEx.create_from_string("(?m)^func ")
		for fm in fr.search_all(text):
			funcs.append(fm.get_start())
		var pos := 0
		while true:
			var best := -1
			var best_name := ""
			for n in FONT_ARG.keys():
				var p := text.find(str(n) + "(", pos)
				if p >= 0 and (best < 0 or p < best):
					best = p
					best_name = str(n)
			if best < 0:
				break
			total += 1
			var args := _call_args(text, best + best_name.length())
			var want := int(FONT_ARG[best_name])
			var sz := -1
			if args.size() > want:
				var a := str(args[want])
				if a.is_valid_int():
					sz = int(a)
					literal += 1
				else:
					# 非字面量一律试着按位置回退查一次，查不到返回 -1（判不了，不算违例）
					sz = _nearest_int_before(assigns, funcs, best, a)
					if sz >= 0:
						via_var += 1
			if sz >= 0 and sz < FONT_MIN:
				bad.append("%s:%d 处 %s 用了 %d 号字" % [f, text.substr(0, best).count("\n") + 1, best_name, sz])
			pos = best + 1
	print("[font] 扫 %d 处 draw_text*，判到字号 %d 处（字面量 %d / 变量回溯 %d），低于 %dpx 的 %d 处"
		% [total, literal + via_var, literal, via_var, FONT_MIN, bad.size()])
	# 下限要写绝对值：以前写的是 >= total*0.6，total 为 0 时 0>=0 恒真，等于没闸
	check(total >= 60 and literal + via_var >= 50,
		"字号闸覆盖下限：扫到 %d 处、判到 %d 处（下限 60/50，掉了就是扫不到源码）" % [total, literal + via_var])
	check(bad.is_empty(), "没有低于 %dpx 的文字（判到 %d/%d 处：%s）" % [FONT_MIN, literal + via_var, total, "; ".join(PackedStringArray(bad))])

## 取调用点之前、且不出所在函数的最后一次赋值；找不到就返回 -1（判不了，不算违例）
func _nearest_int_before(assigns: Array, funcs: PackedInt32Array, at: int, name: String) -> int:
	var floor_at := 0
	for fo in funcs:
		if fo < at:
			floor_at = fo
		else:
			break
	var found := -1
	for asg in assigns:
		if int(asg[0]) < at and int(asg[0]) >= floor_at and str(asg[1]) == name:
			found = int(asg[2])
	return found

func _all_scripts() -> Array:
	var out: Array = []
	out.append_array(_collect("res://scripts"))
	out.append_array(_collect("res://tests"))
	return out

## 导出包里的 .gd 是编译过的，FileAccess 读不到源码文本。三条"扫源码"的闸因此在包内
## 一条都扫不到，而"扫到 0 处、违例 0 处"和"全部通过"打印出来一模一样——
## 这是个一直在的洞，直到字号那条闸自己报出"扫 0 处"才暴露。
## 统一走这里：文件数不够就明确记为"跳过"，绝不让 0 冒充通过。
const SOURCE_MIN_FILES := 30
var skipped_source_gates: Array = []

func _source_files_or_skip(who: String) -> Array:
	# 注意不能只看 DirAccess 列不列得到：导出包里 .gd 是**列得到但读不出文本**
	# （已被编译），第一版就是栽在这里，"只列到 40 个"于是放行、扫出 0 处还报绿。
	var readable: Array = []
	for f in _all_scripts():
		if FileAccess.get_file_as_string(f).length() > 40:
			readable.append(f)
	if readable.size() >= SOURCE_MIN_FILES:
		return readable
	if skipped_source_gates.is_empty():
		print("[scan] 只读到 %d 个可读源码文件（导出包内 .gd 已编译，列得到但读不出文本）——"
			% readable.size())
	print("[scan] 源码闸跳过：%s（这是跳过，不是通过）" % who)
	skipped_source_gates.append(who)
	return []

func _collect(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := dir_path + "/" + name
		if d.current_is_dir():
			out.append_array(_collect(path))
		elif name.get_extension().to_lower() == "gd":
			out.append(path)
		name = d.get_next()
	d.list_dir_end()
	return out

func _test_new_game_and_save() -> void:
	check(not SaveManager.has_save, "fresh state has no save file")
	check(GameState.coins == 0 and GameState.day == 1, "fresh state defaults")
	GameState.coins = 999
	GameState.day = 3
	GameState.best_combo = 7
	GameState.inventory["patty"] = 5
	SaveManager.save_all()
	check(FileAccess.file_exists(SaveManager.save_path()), "save file written")
	check(FileAccess.file_exists(SaveManager.ledger_path()), "ledger file written")
	# 脏化内存后重读
	GameState.coins = -1
	GameState.day = 99
	GameState.best_combo = 0
	GameState.inventory["patty"] = 0
	SaveManager.load_all()
	check(GameState.coins == 999, "reload restores coins")
	check(GameState.day == 3, "reload restores day")
	check(GameState.best_combo == 7, "reload restores best combo")
	check(GameState.inv_count("patty") == 5, "reload restores inventory")
	# 复位为第 1 天再开始营业测试
	GameState.reset_for_new_game()
	check(not SaveManager.has_save, "reset wipes save")

func _run_day(day_num: int, seed_v: int) -> Dictionary:
	_top_inventory(24)
	var coins0 := GameState.coins
	var sim := DaySim.new()
	sim.start(day_num, seed_v)
	var bot = load("res://tests/sim_bot.gd").new()
	bot.sim = sim
	var t := 0.0
	var dt := 0.05
	while not sim.finished and t < 900.0:
		bot.step(dt)
		sim.tick(dt)
		t += dt
	var plan := sim.total_plan()
	print("[day %d] finished=%s t=%.1fs served=%d missed=%d perfects=%d coins=%d tips=%d bestCombo=%d" % [
		day_num, str(sim.finished), t, sim.served, sim.missed, sim.perfects, sim.today_coins, sim.tips_total, sim.best_combo_day])
	check(sim.finished, "day %d finished within time limit" % day_num)
	check(sim.served + sim.missed == plan, "day %d all customers accounted (%d+%d=%d)" % [day_num, sim.served, sim.missed, plan])
	check(sim.served >= int(plan * 0.6), "day %d served ratio >= 60%%" % day_num)
	check(sim.missed <= int(plan * 0.4), "day %d missed ratio <= 40%%" % day_num)
	var rec := sim.settlement_record()
	SaveManager.commit_day(rec, sim.today_orders)
	var sum := 0
	for o in sim.today_orders:
		sum += int(o.get("total", 0))
	# 逐件交付 + 抛硬币之后这条账变成三段：各单应付之和 == 实收 + 被收走。
	# bot 每步先捡干净，所以这里 swept 应当是 0；一旦哪天有人漏捡，等式立刻不平。
	check(sum == sim.today_coins + sim.coins_swept,
		"day %d 对账：各单应付 %d == 实收 %d + 被收走 %d" % [day_num, sum, sim.today_coins, sim.coins_swept])
	check(sim.coins.is_empty(), "day %d 打烊时台面上没有遗留硬币" % day_num)
	check(GameState.coins == coins0 + sim.today_coins, "day %d coins delta consistent" % day_num)
	check(sim.today_orders.size() == sim.served, "day %d order log per serve" % day_num)
	return {"sim": sim, "rec": rec}

## MAX_ORDERS 那条裁剪线以前从没被跑到过：一天只十几笔订单，离 500 差得远。
## 这里连提 600 笔，要求窗口只剩最近 500，而且裁掉的必须是旧的那一头。
## 抛硬币 / 拾取 / 收币人的账目闸。逐条自报实数，且每条都对应一个可灌坏的点：
## 拆枚写反（金当银）、抛出即到账、被收走的钱也进钱包、第 1 天就来收币。
## 响度闸：每条音效都要合成得出、且峰值落在自己家族的目标上。
## 它不判"好不好听"（我听不见），判的是三件真能出错的事：合成出空、归一没跑、
## 某条被后来的改动弄成静音。自报查了几条、哪几条不合标。
func _test_sound_levels() -> void:
	var rows: Array = []
	var bad := 0
	for n in Sfx.SOUND_NAMES:
		var wav: AudioStreamWAV = Sfx._build(str(n))
		if wav == null or wav.data.size() < 64:
			rows.append("%s=合成不出" % str(n))
			bad += 1
			continue
		var s := wav.data
		var peak := 0
		for i in range(0, s.size() - 1, 2):
			var v: int = int(s[i]) | (int(s[i + 1]) << 8)
			if v >= 32768:
				v -= 65536
			peak = maxi(peak, absi(v))
		var want := Sfx.target_peak(str(n))
		var got := float(peak) / 32767.0
		if got < want * 0.8 or got > want * 1.25:
			rows.append("%s 峰值 %.2f（%s 族目标 %.2f）" % [str(n), got, Sfx.family_of(str(n)), want])
			bad += 1
	print("[sfx] 查了 %d 条，峰值不合标 %d 条：%s" % [
		Sfx.SOUND_NAMES.size(), bad, ", ".join(PackedStringArray(rows))])
	check(bad == 0, "%d 条音效峰值不在家族目标 ±20%% 内：%s" % [bad, ", ".join(PackedStringArray(rows))])
	# 定义了却从没被发出的音效＝那条声音永远不会响，同样是缺陷。
	# 这条要读源码文本，导出包里读不到 → 走 _source_files_or_skip，别拿空串当"全没用到"。
	var files: Array = _source_files_or_skip("sfx_dead 音效发出方扫描")
	var src := ""
	for f in files:
		src += FileAccess.get_file_as_string(str(f))
	var dead: Array = []
	if not files.is_empty():
		for n in Sfx.SOUND_NAMES:
			# 只认"发出"的形状，不能拿 `"%s" in 源码` 判：sfx.gd 自己就带着 SOUND_NAMES
			# 那份名单，任何新加的名字都会在自己的定义行里被"用到"，那条闸就恒绿。
			# （第一版就是这么写的，注入一个没人发的名字照样报"无"。）
			var emitted := src.contains('play("%s")' % str(n)) or src.contains('emit("%s")' % str(n))
			if not emitted:
				dead.append(str(n))
		print("[sfx] 查了 %d 个文件，定义了却没人发的音效：%s" % [
			files.size(), ", ".join(PackedStringArray(dead)) if not dead.is_empty() else "无"])
		check(dead.is_empty(), "%d 个音效定义了却没人发：%s" % [dead.size(), ", ".join(PackedStringArray(dead))])

## 用户报的"同时做两个汉堡，食材只出一个汉堡"。这里钉两条守恒：
## ① 荷叶已占时再做第二只，必须**整份退料**（不能吞）；
## ② 目标客人中途走了，手里叠了一半的 assembly **不许无主滞留**（要么退料要么有人接盘）。
func _tap_through(sim: DaySim, ing: String) -> void:
	sim.tap_shelf(ing)
	var guard := 0
	while str(sim.board["ing"]) == ing and guard < 40:
		sim.slice_board()
		guard += 1

func _inv_sum(keys: Array) -> int:
	var s := 0
	var seen := {}
	for k in keys:
		# 配料链里 bun / patty 本来就出现两次（上下两半面包、双层堡两块饼），
		# 按列表逐项求和会把同一个库存键数两遍——退料退对了也照样报"多退一件"。
		if seen.has(str(k)) or str(k) == "patty":
			continue
		seen[str(k)] = true
		s += GameState.inv_count(str(k))
	return s

## 手里占着的料：组装层 + 案板上正在切的那一块（后者不在 assembly 里，
## 但 refund_assembly 会一起退，守恒式漏了它就会把正确的退料判成"多退一件"）。
func _held_count(sim: DaySim) -> int:
	var n := sim.assembly.size()
	if str(sim.board["ing"]) != "":
		n += 1
	return n

func _two_waiting(order_a: int, order_b: int) -> Array:
	var a := Customer.new()
	a.sp = 0; a.state = "waiting"; a.set_want("burger", order_a); a.slot = 0
	a.max_patience = 90.0; a.patience = 90.0
	var b := Customer.new()
	b.sp = 1; b.state = "waiting"; b.set_want("burger", order_b); b.slot = 1
	b.max_patience = 90.0; b.patience = 90.0
	return [a, b]

## 全局类名必须解析到"真的会打进包里"的路径。
## 踩过的坑：做证伪注入时在 tools/_scratch/ 留了一份 `bak_daysim.gd`，它带着
## `class_name DaySim`，于是 Godot 的类缓存把 DaySim 指到了那份备份；而导出包的
## exclude_filter 排掉了 tools/* → 包里根本没有那个文件 → **游戏一开机就 Parse Error、
## 双击打不开**，而源码树里跑测试全绿（两份文件都在，看不出被抢注）。
func _test_class_cache_ships() -> void:
	var excluded: Array = ["res://tools/", "res://screenshots/", "res://saves/", "res://legacy_web_v1/"]
	var total := 0
	var bad: Array = []
	for c in ProjectSettings.get_global_class_list():
		total += 1
		var cd: Dictionary = c
		var p := str(cd.get("path", ""))
		for pre in excluded:
			if p.begins_with(str(pre)):
				bad.append("%s -> %s" % [str(cd.get("class", "")), p])
	print("[classcache] 注册了 %d 个全局类，落在排除目录里的 %d 个：%s" % [
		total, bad.size(), ", ".join(PackedStringArray(bad)) if not bad.is_empty() else "无"])
	check(total >= 4, "全局类只有 %d 个，缓存本身没读到（用例前提不成立）" % total)
	check(bad.is_empty(), "%d 个全局类指向不会导出的目录，包内会开机崩：%s" % [
		bad.size(), ", ".join(PackedStringArray(bad))])
	# 类名被抢注时，DaySim 必须还能 new 出来（这条在包内同样成立）
	var probe := DaySim.new()
	check(probe != null and probe is DaySim, "DaySim 实例化失败（类名可能被别的文件抢注）")

func _test_burger_conservation() -> void:
	GameState.initialize_new()
	# 找两道配料链一长一短的堡，第二条用例才成立
	var long_i := 0
	var short_i := 0
	for i in Config.burgers().size():
		if int(Config.burger(i).get("stack", []).size()) > int(Config.burger(long_i).get("stack", []).size()):
			long_i = i
		if int(Config.burger(i).get("stack", []).size()) < int(Config.burger(short_i).get("stack", []).size()):
			short_i = i
	var stack: Array = Config.burger(long_i).get("stack", [])
	var sim := DaySim.new()
	sim.start(1, 4242)
	sim.plan = []
	sim.queue = _two_waiting(long_i, long_i)
	for k in stack:
		if str(k) != "patty":
			GameState.inv_add(str(k), 20)
	sim.cooked = 30
	sim.target = 0
	for k in stack:
		_tap_through(sim, str(k))
	check(int(sim.tray["burger"]) == long_i, "第一只堡上了荷叶（tray=%d，应为 %d）" % [int(sim.tray["burger"]), long_i])
	# ① 荷叶已占，再做第二只
	sim.target = 1
	var before := _inv_sum(stack) + sim.cooked
	for k in stack:
		_tap_through(sim, str(k))
	var after := _inv_sum(stack) + sim.cooked
	print("[2burger] 荷叶=%d；第二只尝试前后 食材+熟饼 %d → %d；组装里卡着 %d 件" % [
		int(sim.tray["burger"]), before, after, sim.assembly.size()])
	check(int(sim.tray["burger"]) == long_i, "第二只不该换掉荷叶上那只（tray=%d）" % int(sim.tray["burger"]))
	check(after == before, "做不成的第二只必须整份退料：%d → %d" % [before, after])
	check(sim.assembly.is_empty(), "第二只的残料不能卡在组装里（%d 件）" % sim.assembly.size())
	# ② 叠到一半，目标客人走了
	sim.tray = sim.call("_empty_tray")
	sim.target = 0
	var half: int = maxi(2, int(stack.size()) - 1)
	for i in half:
		_tap_through(sim, str(stack[i]))
	# refund_assembly 连**案板上正在切的那一块**一起退（它不在 assembly 里），
	# 所以"手里"必须算上它，否则退料正确反而被判成多退了一件。
	var before2 := _inv_sum(stack) + sim.cooked + _held_count(sim)
	check(sim.assembly.size() > 0, "用例前提：手里应该正叠着一半")
	var a0 = sim.queue[0]
	a0.state = "leaving"
	sim.call("_fix_target")
	var after2 := _inv_sum(stack) + sim.cooked + _held_count(sim)
	print("[orphan] 目标走掉：target=%d，手里 %d 件，库存+熟饼+手里 %d → %d" % [
		int(sim.target), sim.assembly.size(), before2, after2])
	# 判"手里那半只退回了货架"，不是判守恒式——把 assembly.size() 同时加到等式两边
	# 是条永远为真的断言（第一版就是这么写的，注入死局它照样绿）。
	check(sim.assembly.is_empty(), "目标客人走掉时手里那半只必须退料，实剩 %d 件" % sim.assembly.size())
	check(after2 == before2, "退料前后总量不该变：%d → %d" % [before2, after2])
	# 换一道更短的堡接盘：不能把上一道剩下的层硬塞进短配方里
	sim.queue = _two_waiting(short_i, short_i)
	sim.target = 0
	for k in Config.burger(long_i).get("stack", []):
		if str(k) != "patty":
			GameState.inv_add(str(k), 20)
	sim.cooked = 30
	var long_stack: Array = Config.burger(long_i).get("stack", [])
	for i in mini(long_stack.size(), Config.burger(short_i).get("stack", []).size()):
		_tap_through(sim, str(long_stack[i]))
	print("[orphan] 短配方接盘：手里 %d 件 / 短配方要 %d 件，tray=%d" % [
		sim.assembly.size(), int(Config.burger(short_i).get("stack", []).size()), int(sim.tray["burger"])])
	check(sim.assembly.size() <= int(Config.burger(short_i).get("stack", []).size()),
		"手里层数不能超过当前配方需要的层数（%d > %d 就是死局）" % [
			sim.assembly.size(), int(Config.burger(short_i).get("stack", []).size())])

func _test_coins() -> void:
	var cc := Config.coins_cfg()
	var gv := maxi(2, int(cc.get("gold_value", 10)))
	var coins0 := GameState.coins
	var sim := DaySim.new()
	sim.start(1, 7)
	sim.toss_coins(gv * 3 + 7)
	var gold := 0
	var silver := 0
	var sumv := 0
	for c in sim.coins:
		var v := int((c as Dictionary)["v"])
		sumv += v
		if v >= gv:
			gold += 1
		else:
			silver += 1
	print("[coins] 抛 %d → 金 %d 枚 + 银 %d 枚，面值合计 %d（上限每次 %d 枚）" % [
		gv * 3 + 7, gold, silver, sumv, int(cc.get("max_per_toss", 40))])
	check(gold == 3 and silver == 7, "%d 应拆成 3 金 7 银，实得 %d 金 %d 银" % [gv * 3 + 7, gold, silver])
	check(sumv == gv * 3 + 7, "拆完面值合计 %d，应等于应付 %d" % [sumv, gv * 3 + 7])
	# 拾到才算钱：抛出后钱包不动，pick 一枚才涨
	var before := GameState.coins
	sim.toss_coins(12)
	check(GameState.coins == before, "抛币之后钱包没动（拾到才算钱）")
	var got := sim.pick_coin(sim.coins.size() - 1)
	check(got > 0 and GameState.coins == before + got, "拾一枚进账 %d" % got)
	check(sim.today_coins == got and sim.coins_collected == got,
		"today_coins / 实收都只算拾到的：today=%d collected=%d 拾=%d" % [sim.today_coins, sim.coins_collected, got])
	# 收币人：第 1 天不来，第 2 天起放太久就来扫，被扫走的绝不进钱包
	var d1 := DaySim.new()
	d1.start(1, 11)
	d1.toss_coins(gv * 2 + 5)
	for i in 240:
		d1._tick_coins(0.05)
	check(d1.sweeper_t < 0.0 and d1.coins.size() == 7,
		"第 1 天不该有人来收钱（sweeper=%s，台面剩 %d/7 枚）" % [str(d1.sweeper_t), d1.coins.size()])
	var d2 := DaySim.new()
	var b2 := GameState.coins
	d2.start(2, 12)
	d2.toss_coins(gv * 2 + 5)
	for i in 300:
		d2._tick_coins(0.05)
	print("[coins] 第 2 天放 15 秒后：台面剩 %d 枚、被收走 %d、钱包 +%d" % [
		d2.coins.size(), d2.coins_swept, GameState.coins - b2])
	check(d2.coins.is_empty(), "第 2 天放太久该被收走，台面实剩 %d 枚" % d2.coins.size())
	check(d2.coins_swept == gv * 2 + 5 and GameState.coins == b2,
		"被收走的 %d 不该进钱包（swept=%d，钱包实际 +%d）" % [gv * 2 + 5, d2.coins_swept, GameState.coins - b2])
	# ③ 点他可以打断：他兜里的钱全吐回来，台面上剩下的还能继续捡
	var d3 := DaySim.new()
	var b3 := GameState.coins
	d3.start(2, 13)
	d3.toss_coins(gv * 2 + 5)
	for i in 180:
		d3._tick_coins(0.05)
	var taken := int(d3.sweeper_taken)
	var back := d3.swat_sweeper()
	print("[coins] 打断收币人：他兜里 %d、台面还 %d 枚；抢回 %d，钱包 +%d，被收走 %d" % [
		taken, d3.coins.size(), back, GameState.coins - b3, d3.coins_swept])
	check(taken > 0, "用例前提：9 秒后他兜里应当已经有钱（实得 %d）" % taken)
	check(back == taken and GameState.coins == b3 + taken, "点他应吐回 %d，实得 %d" % [taken, back])
	check(d3.coins_swept == 0 and d3.sweeper_t < 0.0, "打断之后不该记成'被收走'（swept=%d）" % d3.coins_swept)
	d3.collect_all()
	check(GameState.coins == b3 + gv * 2 + 5, "抢回 + 捡完应当一分不少：+%d / %d" % [GameState.coins - b3, gv * 2 + 5])
	# ④ 打烊：最后一个客人之后，台面上没捡的钱归玩家（不再算被收走）
	var d4 := DaySim.new()
	var b4 := GameState.coins
	d4.start(2, 14)
	d4.toss_coins(gv * 2 + 5)
	d4.plan = []
	d4.plan_idx = 0
	d4.queue = []
	d4.leaving = []
	d4.tick(0.05)
	print("[coins] 打烊：台面剩 %d、实收 %d、被收走 %d、钱包 +%d" % [
		d4.coins.size(), d4.coins_collected, d4.coins_swept, GameState.coins - b4])
	check(d4.finished, "用例前提：队列空了应当打烊")
	check(d4.coins.is_empty() and d4.coins_swept == 0 and d4.coins_collected == gv * 2 + 5,
		"打烊时没捡的钱应归玩家（collected=%d swept=%d）" % [d4.coins_collected, d4.coins_swept])
	GameState.coins = coins0

func _test_ledger_trim() -> void:
	var bak: Dictionary = SaveManager.ledger.duplicate(true)
	var before := SaveManager.orders().size()
	var seq := 0
	for d in 60:
		var orders: Array = []
		for i in 10:
			seq += 1
			orders.append({"seq": seq, "day": d, "customer": "客%d" % seq,
				"items": ["经典芝士堡"], "total": 10 + seq})
		SaveManager.commit_day({"day": d, "coins": 1, "served": 10, "missed": 0,
			"perfects": 0, "planned": 10, "rep_after": 1.0}, orders)
	var kept: Array = SaveManager.orders()
	print("[trim] 提交 %d 笔（原有 %d）→ 台账剩 %d 笔，上限 %d" % [seq, before, kept.size(), SaveManager.MAX_ORDERS])
	check(kept.size() == SaveManager.MAX_ORDERS, "订单裁到上限，实得 %d" % kept.size())
	check(int(kept[kept.size() - 1].get("seq", -1)) == seq, "留着的末尾是最新那笔 seq=%d" % seq)
	check(int(kept[0].get("seq", -1)) == seq - SaveManager.MAX_ORDERS + 1,
		"窗口起点 seq=%d，应为 %d" % [int(kept[0].get("seq", -1)), seq - SaveManager.MAX_ORDERS + 1])
	SaveManager.ledger = bak

func _test_ledger_and_reload() -> void:
	check(SaveManager.day_records().size() == 2, "ledger has 2 day records")
	check(SaveManager.orders().size() >= 8, "ledger has order entries")
	var recs := SaveManager.day_records()
	var d1: Dictionary = recs[0]
	check(int(d1.get("day", 0)) == 1, "first record is day1")
	check(int(d1.get("planned", 0)) == 8, "day1 record planned=8")
	var orders := SaveManager.orders()
	var o1: Dictionary = orders[0]
	for field in ["seq", "day", "customer", "items", "price", "tip", "combo_bonus", "total", "patience_frac", "time"]:
		check(o1.has(field), "order entry has field " + field)
	# 模拟“中途退出”：保存后重读，验证与台账一致
	var coins_now := GameState.coins
	var days_now := GameState.day
	var orders_now := SaveManager.orders().size()
	GameState.coins = -500
	GameState.day = 42
	SaveManager.load_all()
	check(GameState.coins == coins_now and GameState.day == days_now, "reload keeps coins & day")
	check(SaveManager.orders().size() == orders_now, "reload keeps ledger orders")

func _test_fire_system() -> void:
	_top_inventory(24)
	var sim := DaySim.new()
	sim.start(3, 111)
	# 火候门槛：火太低不能开火
	sim.fire = 0.0
	var inv0 := GameState.inv_count("patty")
	sim.tap_grill(0)
	check(GameState.inv_count("patty") == inv0, "fire gate blocks grill placement")
	check(float(sim.grill[0]["p"]) < 0.0, "grill slot still empty after blocked place")
	# 添柴
	sim.fire = 10.0
	sim.wood = 2
	check(sim.add_wood(), "add wood succeeds with stock")
	check(sim.wood == 1, "wood consumed")
	check(sim.fire > 10.0, "fire raised by wood")
	# 无柴时添柴失败
	sim.wood = 0
	check(not sim.add_wood(), "add wood fails without stock")
	# 劈柴
	sim.wood = 0
	sim.apply_chop(4, true)
	check(sim.wood == 4, "chop adds wood")
	sim.wood = int(Config.fire.get("wood_max", 10))
	sim.apply_chop(6, true)
	check(sim.wood == int(Config.fire.get("wood_max", 10)), "wood capped at max")
	# 放肉 + 计时窗口逻辑
	sim.fire = 80.0
	sim.wood = 3
	sim.tap_grill(0)
	check(float(sim.grill[0]["p"]) >= 0.0, "place patty on grill")
	var dt := 0.05
	var steps := 0
	while float(sim.grill[0]["p"]) < float(Config.cook("grill").get("flip_min", 0.4)) and steps < 400:
		sim.tick(dt)
		steps += 1
	sim.tap_grill(0)
	check(bool(sim.grill[0]["flipped"]), "flip patty after min time")
	var win: Array = Config.cook("grill").get("window", [0.78, 1.02])
	while float(sim.grill[0]["p"]) < float(win[0]) and steps < 800:
		sim.tick(dt)
		steps += 1
	sim.tap_grill(0)
	check(sim.cooked == 1, "collect cooked patty in window")
	check(float(sim.grill[0]["p"]) < 0.0, "grill slot freed after collect")

func _test_edge_cases() -> void:
	_top_inventory(24)
	var sim := DaySim.new()
	sim.start(3, 222)
	# 越界与无效操作
	sim.tap_grill(9)
	sim.tap_shelf("not_an_ingredient")
	check(true, "invalid calls do not crash")
	# 无订单时叠食材：提示而非扣除
	var inv_lettuce := GameState.inv_count("lettuce")
	sim.tap_shelf("lettuce")
	check(GameState.inv_count("lettuce") == inv_lettuce, "no order: no ingredient consumed")
	# 错误顺序不扣除
	var c := Customer.new()
	c.sp = 0
	c.set_want("burger", 0)
	c.set_want("fries", false)
	c.set_want("drink", "")
	c.state = "waiting"
	c.max_patience = 46.0
	c.patience = 46.0
	sim.queue.append(c)
	sim.target = 0
	var inv_cheese := GameState.inv_count("cheese")
	sim.tap_shelf("cheese")  # 应该先放 bun
	check(GameState.inv_count("cheese") == inv_cheese, "wrong order: no ingredient consumed")
	check(sim.assembly.is_empty(), "wrong order: assembly empty")
	# 正确顺序
	sim.tap_shelf("bun")
	check(sim.assembly.size() == 1, "correct ingredient stacked")
	# 案板切割：生菜要切三刀才落进组装层，重复点击不重复扣库存
	var inv_l := GameState.inv_count("lettuce")
	sim.tap_shelf("lettuce")
	check(str(sim.board["ing"]) == "lettuce" and sim.assembly.size() == 1, "lettuce staged on board")
	sim.tap_shelf("lettuce")
	check(int(sim.board["cuts"]) == 1 and GameState.inv_count("lettuce") == inv_l - 1, "re-tap slices, no double charge")
	sim.slice_board()
	check(sim.assembly.size() == 1 and int(sim.board["cuts"]) == 2, "two cuts not enough")
	sim.slice_board()
	check(sim.assembly.size() == 2 and str(sim.board["ing"]) == "", "third cut lands in assembly")
	# 空荷叶上递不出任何东西
	check(not sim.deliver(c, "burger"), "deliver with empty tray fails")
	# 非等待状态不可交付
	c.state = "walking"
	sim.tray["burger"] = 0
	sim.tray["fries"] = false
	sim.tray["drink"] = ""
	check(not sim.deliver(c, "burger"), "deliver to walking customer fails")
	c.state = "waiting"
	# 逐件交付：这位只点了堡，所以递出这一件就算收齐、当场结算
	check(sim.deliver(c, "burger"), "deliver the burger this customer ordered")
	check(sim.served == 1, "served counter increments")
	# 耐心归零离店
	var c2 := Customer.new()
	c2.sp = 1
	c2.set_want("burger", 0)
	c2.state = "waiting"
	c2.max_patience = 10.0
	c2.patience = 0.01
	sim.queue.append(c2)
	var missed0 := sim.missed
	sim.tick(0.2)
	check(sim.missed == missed0 + 1, "patience zero causes walkout")

func _test_upgrades() -> void:
	GameState.upgrades = {}
	GameState.coins = 10
	check(not GameState.buy_upgrade("grill3"), "upgrade fails without enough coins")
	check(GameState.coins == 10, "no coin spent on failed buy")
	GameState.coins = 200
	check(GameState.buy_upgrade("grill3"), "upgrade bought with enough coins")
	check(GameState.coins == 140, "upgrade cost deducted")
	check(not GameState.buy_upgrade("grill3"), "upgrade cannot be bought twice")
	check(GameState.grill_slots() == 3, "grill slots upgraded to 3")
	_top_inventory(24)
	var sim := DaySim.new()
	sim.start(4, 333)
	check(sim.grill.size() == 3, "day sim uses upgraded grill slots")
	# 收尾复位，避免影响后续
	GameState.upgrades = {}
	check(GameState.grill_slots() == 2, "upgrade reset works")

func _test_config_reload() -> void:
	# A) 用户目录覆盖（编辑器与导出包通用）：user://config/dishes.json 优先于随包默认
	var ov := "user://config/dishes.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://config"))
	var original := FileAccess.get_file_as_string("res://data/config/dishes.json")
	check(original.length() > 0, "read dishes.json for reload test")
	var parsed = JSON.parse_string(original)
	var changed := false
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("burgers"):
		parsed["burgers"][0]["price"] = 999
		changed = true
	check(changed, "mutate price in memory (override)")
	_write(ov, JSON.stringify(parsed, "  "))
	Config.reload_all()
	check(int(Config.burger(0).get("price", 0)) == 999, "user override price 999 effective")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ov))
	Config.reload_all()
	check(int(Config.burger(0).get("price", 0)) == 18, "override removed restores price 18")
	# B) 直接修改 res:// 配置文件（仅编辑器/源码运行可写；导出运行时 res:// 只读，自动跳过）
	if TestEnv.res_dir_writable("res://data/config"):
		var path := "res://data/config/dishes.json"
		var p2 = JSON.parse_string(original)
		if typeof(p2) == TYPE_DICTIONARY and p2.has("burgers"):
			p2["burgers"][0]["price"] = 25
		_write(path, JSON.stringify(p2, "  "))
		Config.reload_all()
		check(int(Config.burger(0).get("price", 0)) == 25, "reload sees new price 25 (res path)")
		_write(path, original)
		Config.reload_all()
		check(int(Config.burger(0).get("price", 0)) == 18, "restore original price 18")
	else:
		print("[config] res://data/config not writable (export run); res-path edit test skipped")

func _test_stability_spam() -> void:
	_top_inventory(24)
	var sim := DaySim.new()
	sim.start(5, 444)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 3000:
		var r := rng.randi_range(0, 8)
		match r:
			0:
				sim.tap_grill(rng.randi_range(0, 4))
			1:
				sim.tap_fryer()
			2:
				sim.tap_drink()
			3:
				sim.tap_shelf(str(["bun", "lettuce", "tomato", "cheese", "patty", "potato", "fries", "drink"][rng.randi_range(0, 7)]))
			4:
				if not sim.queue.is_empty():
					sim.tap_customer(sim.queue[rng.randi_range(0, sim.queue.size() - 1)])
			5:
				if not sim.queue.is_empty():
					var tc: Customer = sim.queue[rng.randi_range(0, sim.queue.size() - 1)]
					var k2 := sim.next_kind_for(tc)
					if k2 != "":
						sim.deliver(tc, k2)
			6:
				sim.add_wood()
			7:
				sim.apply_chop(rng.randi_range(0, 6), rng.randf() > 0.5)
			8:
				sim.tick(rng.randf_range(0.01, 0.5))
		if i % 500 == 0:
			sim.tick(0.05)
	# 连打后的不变量
	var ok := true
	for k in GameState.inventory.keys():
		if GameState.inv_count(str(k)) < 0:
			ok = false
	check(ok, "inventory never negative after spam")
	check(GameState.coins >= 0, "coins never negative after spam")
	check(sim.fire >= 0.0 and sim.fire <= float(Config.fire.get("fire_max", 100.0)) + 0.01, "fire within bounds")
	check(sim.wood >= 0 and sim.wood <= int(Config.fire.get("wood_max", 10)), "wood within bounds")
	check(sim.assembly.size() <= 8, "assembly bounded")
	check(true, "3000 random actions without crash")

func _dump_evidence() -> void:
	var dir := TestEnv.evidence_dir("res://screenshots/test_saves", "screenshots/test_saves")
	if FileAccess.file_exists(SaveManager.save_path()):
		_write(dir + "/save_slot1.json", FileAccess.get_file_as_string(SaveManager.save_path()))
	if FileAccess.file_exists(SaveManager.ledger_path()):
		_write(dir + "/ledger.json", FileAccess.get_file_as_string(SaveManager.ledger_path()))
	print("[evidence] saves copied to ", dir)

## 炸炉的多篮路径。`economy.cooking.fryer.baskets` 现在是 **1**，也就是默认配置下
## 第二篮永远不会被用到——不写这条，多篮那套分支就是一段谁都没跑过的代码，
## 等第三章真扩到 2 篮时才发现它是坏的（实测把 baskets 改成 2，SimBot 仍然只看
## 0 号篮，所以两篮同时在炸的行数是 0：结构在、没人用）。
## 这里直接把 fryer 摆成两篮，测的就是"多篮"这套分支本身。
func _test_fryer_baskets() -> void:
	var c0 := checks
	var sim := DaySim.new()
	sim.start(3, 4003)
	sim.fryer = [{"p": -1.0, "warned": false}, {"p": -1.0, "warned": false}]
	GameState.inv_add("potato", 10)
	sim.tap_fryer()
	sim.tick(0.1)
	check(sim.fryer_p(0) >= 0.0 and sim.fryer_p(1) < 0.0,
		"第一次点击只该起 0 号篮（实得 p0=%.2f p1=%.2f）" % [sim.fryer_p(0), sim.fryer_p(1)])
	sim.fryer[0]["p"] = 0.30
	check(sim._fryer_focus() == 1, "0 号还没到起锅窗口时，点击该落到空着的 1 号篮")
	sim.tap_fryer()
	sim.tick(0.1)
	check(sim.fryer_p(1) >= 0.0, "第二篮要能同时开炸，否则扩篮只是摆设")
	var p0a := sim.fryer_p(0)
	var p1a := sim.fryer_p(1)
	for i in 20:
		sim.tick(0.1)
	check(sim.fryer_p(0) > p0a and sim.fryer_p(1) > p1a,
		"两篮必须各自独立推进（%.2f→%.2f / %.2f→%.2f）" % [p0a, sim.fryer_p(0), p1a, sim.fryer_p(1)])
	# 一只到窗口、一只没到：该起的是到窗口那只，另一只不许被顺手清掉
	sim.fryer[0]["p"] = 0.55
	sim.fryer[1]["p"] = 0.80
	check(sim._fryer_focus() == 1, "只有 1 号在起锅窗口时该选中 1 号")
	sim.tray = Config.empty_tray()
	sim.tap_fryer()
	check(sim.fryer_p(1) < 0.0 and sim.fryer_p(0) > 0.4,
		"点一下只起锅 1 号，0 号必须还在炸（实得 p0=%.2f p1=%.2f）" % [sim.fryer_p(0), sim.fryer_p(1)])
	check(bool(sim.tray["fries"]), "起锅那篮要把薯条放到荷叶上")
	# 单篮时选择器必须永远指 0——这是"baskets=1 行为没变"那句结论的根据
	var one := DaySim.new()
	one.start(3, 4003)
	check(one.fryer.size() == 1, "默认配置下只有一只篮子（实得 %d）" % one.fryer.size())
	var always0 := true
	for probe_p in [-1.0, 0.20, 0.80, 1.10, 1.30]:
		one.fryer[0]["p"] = probe_p
		if one._fryer_focus() != 0:
			always0 = false
	check(always0, "单篮时选择器对任何 p 都只能指到 0 号篮，否则泛化改了行为")
	print("[fryer] 多篮路径判了 %d 条；配置 baskets=%d" % [checks - c0, Config.fryer_baskets()])

