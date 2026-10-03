extends Node2D
## 主控（Main）：屏幕切换、覆盖层管理、剧情流程、命令行测试模式入口。

const SCREEN_SCENES := {
	"title": "res://scenes/screens/title.tscn",
	"story": "res://scenes/screens/story.tscn",
	"shop": "res://scenes/screens/shop.tscn",
	"play": "res://scenes/screens/play.tscn",
	"day_end": "res://scenes/screens/day_end.tscn",
	"records": "res://scenes/screens/records.tscn",
	"ending": "res://scenes/screens/ending.tscn",
	"help": "res://scenes/screens/help.tscn",
	"map": "res://scenes/screens/map.tscn",
}

## 每个界面配哪段 BGM。营业中用快的，其余用镇上那段慢的，结算和结局用短铃铛。
const SCREEN_MUSIC := {
	"title": "town", "story": "town", "shop": "town", "map": "town",
	"records": "town", "help": "town", "play": "cook", "day_end": "win", "ending": "win",
}

var screens := {}
var current: Node = null
var current_name := ""
var overlay: Node = null
var overlay_closer: Callable = Callable()
var test_mode := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if str(a).begins_with("--test="):
			test_mode = str(a).substr(7)
	if test_mode != "":
		_run_test_mode()
		return
	goto("title")

func goto(name: String, params: Dictionary = {}) -> void:
	if overlay != null:
		close_overlay()
	if current != null:
		# 保留实例（保留状态），仅隐藏并停止处理，避免退出时节点泄漏
		current.visible = false
		current.set_process(false)
	var node: Node = screens.get(name, null)
	if node == null:
		var scene: PackedScene = load(SCREEN_SCENES[name])
		node = scene.instantiate()
		node.set("main", self)
		screens[name] = node
		add_child(node)
	current = node
	current_name = name
	if node is Node2D:
		(node as Node2D).visible = true
	node.set_process(true)
	if node.has_method("on_enter"):
		node.call("on_enter", params)
	if node.has_method("refresh"):
		node.call("refresh")
	Music.play_track(str(SCREEN_MUSIC.get(name, "town")))
	if node.has_method("queue_redraw"):
		node.call("queue_redraw")

func open_overlay(node: Node, on_closed: Callable = Callable()) -> void:
	if overlay != null:
		return
	overlay = node
	overlay_closer = on_closed
	overlay.set("main", self)
	add_child(overlay)

func close_overlay() -> void:
	if overlay == null:
		return
	overlay.queue_free()
	overlay = null
	var cb := overlay_closer
	overlay_closer = Callable()
	if cb.is_valid():
		cb.call()

func has_overlay() -> bool:
	return overlay != null

func _unhandled_input(event: InputEvent) -> void:
	if overlay != null:
		if overlay.has_method("handle_input"):
			overlay.call("handle_input", event)
		return
	if current != null and current.has_method("handle_input"):
		current.call("handle_input", event)

# ---------------- 流程 ----------------
func show_story(lines: Array, scene_type: String, on_done: Callable) -> void:
	goto("story", {"lines": lines, "scene": scene_type, "on_done": on_done})

func after_intro() -> void:
	GameState.intro_seen = true
	SaveManager.save_all()
	goto("shop")

func after_mystery() -> void:
	GameState.mystery_seen = true
	SaveManager.save_all()
	goto("ending", {"mode": "teaser"})

## 日结算提交：写台账 → 分支（第1天剧情 / 章末页 / 下一天）
func after_day_settled(stats: Dictionary, orders: Array, shop_spent: int = 0) -> void:
	var rec := stats.duplicate()
	rec["shop_spent"] = shop_spent
	SaveManager.commit_day(rec, orders)
	var finished_day := int(stats.get("day", GameState.day))
	var ch := Config.chapter_of(finished_day)
	if finished_day == 1 and not GameState.mystery_seen:
		show_story(Config.mystery_lines(), "mystery", after_mystery)
	elif Config.is_chapter_end(finished_day) and GameState.ending_chapter < ch:
		goto("ending", {"mode": "chapter", "chapter": ch})
	else:
		advance_day()

## 章末页上按了「继续」。还有下一章就先放那一章的开场剧情，放完再进新的一天；
## 已经走到最后一章（往后的 endless）就没有剧情可放，直接进下一天。
func after_chapter_page(ch: int) -> void:
	var nxt := ch + 1
	if nxt > Config.chapter_count() or not Config.has_chapter_intro(nxt):
		advance_day()
		return
	show_story(Config.chapter_intro_lines(nxt), "chapter", after_chapter_intro)

func after_chapter_intro() -> void:
	advance_day()

func advance_day() -> void:
	GameState.day += 1
	SaveManager.save_all()
	goto("shop")

# ---------------- 测试模式 ----------------
func _run_test_mode() -> void:
	# 测试是拿像素坐标点鼠标的，窗口尺寸必须钉死在 1280x720。
	# Godot 会沿用上一趟的窗口大小：被拖大过一次之后，_click(640,300) 就落到别的工位上，
	# 表现成一串"点了没反应"的假失败（截图文件会莫名大三倍，那就是分辨率变了）。
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	# 存档整体挪进隔离目录：包内自检和玩家那份是同一个 user://saves/，
	# 测试收尾的 _restore_saves() 会把开测前的内容写回去，覆盖掉这期间打出来的进度。
	SaveManager.use_isolated_saves()
	var script_path := ""
	match test_mode:
		"smoke":
			script_path = "res://tests/smoke_test.gd"
		"autotest":
			script_path = "res://tests/autotest.gd"
		"soak":
			script_path = "res://tests/soak_test.gd"
		"border":
			script_path = "res://tests/border_test.gd"
		"probe":
			script_path = "res://tests/probe.gd"
		"persist_write":
			script_path = "res://tests/persist_check.gd"
		"persist_read":
			script_path = "res://tests/persist_check.gd"
		"artcheck":
			script_path = "res://tests/artcheck.gd"
		"music":
			script_path = "res://tests/music_check.gd"
		"chapter":
			script_path = "res://tests/chapter_check.gd"
		"perf":
			script_path = "res://tests/perf_check.gd"
		"envcheck":
			script_path = "res://tests/envcheck.gd"
		_:
			push_warning("未知测试模式: " + test_mode)
			get_tree().quit(1)
			return
	var scr = load(script_path)
	if scr == null:
		push_error("测试脚本加载失败: " + script_path)
		get_tree().quit(2)
		return
	var t := Node.new()
	t.name = "TestRunner"
	t.set_script(scr)
	add_child(t)
	# 看门狗：万一测试卡死，15 分钟后强制退出并标记失败
	var wd := get_tree().create_timer(900.0)
	wd.timeout.connect(func():
		push_error("TEST WATCHDOG TIMEOUT")
		get_tree().quit(3))
	t.call("run", self)
