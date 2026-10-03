extends Node2D
## 标题页：开始/继续营业、台账、说明、重开、声音、退出。

var main: Node
var confirm_restart := false
var confirm_t := 0.0
var _hits: Array = []
var _hover := Vector2(-1, -1)
var t := 0.0

func on_enter(_params: Dictionary) -> void:
	confirm_restart = false
	confirm_t = 0.0

func _process(delta: float) -> void:
	t += delta
	if confirm_restart:
		confirm_t -= delta
		if confirm_t <= 0.0:
			confirm_restart = false
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	UiKit.draw_cover(self, UiKit.art("backgrounds/bg_title"), Rect2(0, 0, W, H))
	draw_rect(Rect2(0, 0, W, H), Color(0.08, 0.06, 0.15, 0.46))
	# 主厨头像：圆框用 ui/avatar_frame，和营业界面左上角那枚是同一套
	var d := minf(W, H) * 0.46
	var ac := Vector2(W * 0.235, H * 0.52)
	UiKit.draw_portrait(self, UiKit.art("characters/chef_smirk"), ac, d * 0.5)
	# 标题：木牌横幅，和其他页面同一套
	UiKit.draw_title(self, W * 0.62, H * 0.215, Config.ui("title"), 40)
	UiKit.draw_text_centered(self, W * 0.62, H * 0.315, Config.ui("subtitle"), 19, Color("#f3ecf9"), true)
	var has_save := SaveManager.has_save
	# 存档损坏必须说得出：不然标题页只是把「继续」悄悄换成「开始营业」，
	# 玩家接着打一局，那份还能留底的文件就被原地盖掉了。
	if str(SaveManager.load_error) != "":
		var warn := str(SaveManager.load_error)
		var wl := UiKit.wrap_text(warn, W * 0.34, 14, true)
		var wy := H * 0.365
		for li in wl.size():
			UiKit.draw_text_centered(self, W * 0.62, wy, str(wl[li]), 14, Color("#ffb4a2"), true)
			wy += 20.0
	# 主按钮：花朵木牌，比次一级的木签明显重一档
	var bw := minf(300.0, W * 0.40)
	var bh := bw / 3.46
	var bx := W * 0.62 - bw / 2.0
	var by := H * 0.60
	_btn(Rect2(bx, by, bw, bh), Config.ui("continue") if has_save else Config.ui("start"), "primary", true)
	# 次按钮行：木签
	var sw := 138.0
	var sh := 46.0
	var gap := 12.0
	var row_y := by + bh + 18.0
	var sub_defs: Array = [["records", Config.ui("records")], ["map", "街区地图"], ["help", Config.ui("help")]]
	if has_save:
		sub_defs.append(["restart", Config.ui("restart")])
	sub_defs.append(["quit", Config.ui("quit")])
	var total_w := sub_defs.size() * sw + (sub_defs.size() - 1) * gap
	var sx := W * 0.62 - total_w / 2.0
	for d2 in sub_defs:
		var label := str(d2[1])
		if str(d2[0]) == "restart" and confirm_restart:
			label = "确认重开？"
		_btn(Rect2(sx, row_y, sw, sh), label, str(d2[0]), true)
		sx += sw + gap
	# 声音开关
	_btn(Rect2(W - 152, H - 56, 132, 40), "声音：开" if not GameState.muted else "声音：关", "sound", true)
	# 底注
	UiKit.draw_text_centered(self, W * 0.235, H * 0.885, "深夜十一点，城南老街。", 15, Color(0.94, 0.91, 0.97, 0.88), true)
	UiKit.draw_text(self, Vector2(24, H - 18), "v2.0", 12, Color(0.88, 0.85, 0.92, 0.5))

func _btn(rect: Rect2, label: String, id: String, enabled: bool) -> void:
	var hovered := enabled and rect.has_point(_hover)
	var primary := id == "primary"
	var tex := "ui/plaque" if primary else "ui/tag"
	var mod := Color.WHITE if enabled else Color(0.62, 0.58, 0.55, 0.62)
	if hovered:
		mod = Color(1.12, 1.07, 0.98)
	UiKit.draw_tex_box(self, UiKit.art(tex), rect, mod)
	var col := Color("#fff3dd") if primary else Color("#4a3524")
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0,
		rect.position.y + rect.size.y / 2.0 + (7 if primary else 5), label, 21 if primary else 14, col, true)
	_hits.append({"rect": rect, "id": id})

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_click(Vector2(-1, -1), "primary")

func _click(pos: Vector2, force_id: String = "") -> void:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if force_id != "" or (h["rect"] as Rect2).has_point(pos):
			if force_id != "" and h["id"] != force_id:
				continue
			Sfx.play("tap")
			_action(str(h["id"]))
			return

func _action(id: String) -> void:
	match id:
		"primary":
			if SaveManager.has_save:
				main.goto("shop")
			else:
				if GameState.intro_seen:
					main.goto("shop")
				else:
					main.show_story(Config.intro_lines(), "intro", main.after_intro)
		"records":
			main.goto("records", {"from": "title"})
		"map":
			main.goto("map", {"from": "title"})
		"help":
			main.goto("help", {"from": "title"})
		"restart":
			if confirm_restart:
				GameState.reset_for_new_game()
				confirm_restart = false
			else:
				confirm_restart = true
				confirm_t = 3.0
		"quit":
			get_tree().quit()
		"sound":
			GameState.toggle_muted()
			SaveManager.save_all()
