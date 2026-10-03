extends Node2D
## 剧情页：对白打字机、人物立绘、跳过。场景类型 intro / mystery / chapter。

var main: Node
var lines: Array = []
var scene_type := "intro"
var on_done: Callable = Callable()
var idx := 0
var chars := 0.0
var t := 0.0
var done := false
var _hits: Array = []

func on_enter(params: Dictionary) -> void:
	lines = params.get("lines", [])
	scene_type = str(params.get("scene", "intro"))
	on_done = params.get("on_done", Callable())
	idx = 0
	chars = 0.0
	t = 0.0
	done = false

func _process(delta: float) -> void:
	t += delta
	if idx < lines.size():
		var L: Dictionary = lines[idx]
		var full := str(L.get("text", ""))
		if chars < full.length():
			chars = minf(full.length(), chars + delta * 30.0)
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	var bg_name := "backgrounds/bg_title"
	if scene_type == "chapter":
		bg_name = "backgrounds/bg_shop"
	elif scene_type != "intro":
		bg_name = "backgrounds/bg_mystery"
	UiKit.draw_cover(self, UiKit.art(bg_name), Rect2(0, 0, W, H))
	draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.04, 0.10, 0.44) if scene_type == "intro" else Color(0.03, 0.02, 0.08, 0.36))
	if scene_type == "intro":
		_draw_intro_scene(W, H)
	elif scene_type == "chapter":
		_draw_chapter_scene(W, H)
	else:
		_draw_mystery_scene(W, H)
	_draw_dialogue(W, H)

## 章开场：店门口 + 当前说话的人，按台词自己的 mood 换表情。
## 不借用 mystery 那一支——它是按神秘人那 6 句的 idx 逐帧排的（idx==4 会掏出「厨神会」那张卡）。
func _draw_chapter_scene(W: float, H: float) -> void:
	var L := _current_line()
	var u := minf(W, H) * 0.42
	var who := str(L.get("who", ""))
	if who == "老柴":
		UiKit.draw_portrait_crop(self, _chef_art(str(L.get("mood", "smirk"))), Vector2(W * 0.33, H * 0.52), u * 0.5)
	elif who == "???":
		_draw_mystery_guest(Vector2(W * 0.33, H * 0.56), u * 0.46)

func _current_line() -> Dictionary:
	if idx >= 0 and idx < lines.size():
		return lines[idx]
	return {}

func _draw_intro_scene(W: float, H: float) -> void:
	var L := _current_line()
	var who := str(L.get("who", ""))
	var d := minf(W, H) * 0.44
	if idx >= 3:
		UiKit.draw_portrait(self, UiKit.art("characters/chef_smirk"), Vector2(W * 0.36, H * 0.48), d * 0.5)
		# 扣着的相框（伏笔）
		var fs := minf(W, H) * 0.25
		UiKit.draw_sprite(self, UiKit.art("props/photo_back"), W * 0.66, H * 0.34 + fs / 2.0, fs)
	elif who == "老柴":
		var mood := str(L.get("mood", "smirk"))
		UiKit.draw_portrait(self, _chef_art(mood), Vector2(W * 0.5, H * 0.46), d * 0.56)
	else:
		var pulse := 0.6 + 0.4 * sin(t * 2.5)
		UiKit.draw_text_centered(self, W * 0.5, H * 0.38, Config.ui("title"), 44, Color(1.0, 0.62, 0.28, pulse), true)

func _draw_mystery_scene(W: float, H: float) -> void:
	var u := minf(W, H) * 0.42
	if idx >= 5:
		UiKit.draw_portrait_crop(self, UiKit.art("characters/chef_smirk"), Vector2(W * 0.38, H * 0.48), u * 0.42)
		_draw_mystery_guest(Vector2(W * 0.62, H * 0.6), u * 0.4)
	elif idx == 0:
		_draw_mystery_guest(Vector2(W * 0.5, H * 0.62), u * 0.52)
	elif idx == 1 or idx == 3:
		_draw_mystery_guest(Vector2(W * 0.66, H * 0.62), u * 0.46)
		var mood := "shock" if idx == 1 else "side"
		UiKit.draw_portrait_crop(self, UiKit.art("characters/chef_" + mood), Vector2(W * 0.3, H * 0.62), u * 0.4)
	elif idx == 2:
		UiKit.draw_portrait_crop(self, UiKit.art("characters/chef_shock"), Vector2(W * 0.38, H * 0.6), u * 0.42)
		_draw_mystery_guest(Vector2(W * 0.7, H * 0.6), u * 0.42)
	elif idx == 4:
		UiKit.draw_portrait_crop(self, UiKit.art("characters/chef_side"), Vector2(W * 0.5, H * 0.52), u * 0.44)
		var cw := minf(W, H) * 0.17
		UiKit.draw_panel(self, Rect2(W * 0.5 - cw / 2, H * 0.76, cw, cw * 0.62), 4, Color("#1a1a24"))
		UiKit.draw_text_centered(self, W * 0.5, H * 0.76 + cw * 0.38, "厨神会", int(cw * 0.17), Color("#ffd23c"), true)

func _draw_mystery_guest(center: Vector2, u: float) -> void:
	UiKit.draw_sprite(self, UiKit.art("characters/full_mystery"), center.x, center.y + u * 0.15, u * 1.9)

func _draw_dialogue(W: float, H: float) -> void:
	var L := _current_line()
	if L.is_empty():
		return
	var bx := 14.0
	var bw := W - 28.0
	var who := str(L.get("who", ""))
	var size := 18
	var nsize := 15
	var pad_l := 30.0
	var bd := 0.0
	if who == "老柴":
		bd = 88.0
		pad_l = 18 + bd + 26
	var full := str(L.get("text", ""))
	var max_w := bw - pad_l - 46.0
	# 高度按**整句**换行结果算，不按逐字揭示中的那一截——否则字打多了盒子会往下长
	var nl := maxi(2, UiKit.wrap_text(full, max_w, size).size())
	var bh := minf(maxf(112.0 if bd > 0.0 else 92.0, 74.0 + size * 1.5 * float(nl - 1)), H * 0.34)
	var by := H - bh - 14.0
	# 参考版式：深色对话框 + 白字 + 说话人色条压在框的上沿。
	# 原来铺的是 ui/dialog 那张浅色纸，配深字在整页夜景里像贴了张便签，配白字又读不出。
	UiKit.draw_panel(self, Rect2(bx, by, bw, bh), 14.0, Color(UiKit.NIGHT_PANEL, 0.94), 2.0, Color("#6b4a2c"))
	var accent := _speaker_color(who)
	if bd > 0.0:
		var ac := Vector2(bx + 18 + bd / 2, by + bh / 2)
		UiKit.draw_texture_circle(self, _chef_avatar(str(L.get("mood", "smirk"))), ac, bd / 2)
		UiKit.draw_ring(self, ac, bd / 2 + 2.0, Color("#8a5a30"), 2.0)
	var nw := UiKit.text_width(who, nsize, true) + 34.0
	var nb := Rect2(bx + pad_l - 10.0, by - nsize * 0.92, nw, nsize * 1.84)
	UiKit.draw_panel(self, nb, 8.0, accent, 0.0, accent)
	UiKit.draw_text_in(self, nb, who, nsize, Color("#fff6e6"), true)
	var shown := full.substr(0, int(chars))
	var wrapped := UiKit.wrap_text(shown, max_w, size)
	for j in wrapped.size():
		UiKit.draw_text(self, Vector2(bx + pad_l, by + 40.0 + size * 1.5 * (j + 0.7)),
			wrapped[j], size, Color("#f2ece0"))
	if chars >= full.length() and idx < lines.size():
		var bl := 0.5 + 0.5 * sin(t * 5.0)
		UiKit.draw_text(self, Vector2(bx + bw - 34, by + bh - 18), "▼", 14, Color(0.95, 0.80, 0.55, bl))
	# 跳过按钮
	var sk := Rect2(W - 96, 14, 78, 34)
	UiKit.draw_nine(self, UiKit.art("ui/chip"), sk)
	UiKit.draw_text_in(self, sk, "跳过", 14, Color("#7a3c12"), true)
	_hits.append({"rect": sk, "id": "skip"})

## 名字条的底色：老柴是柴火橙，神秘客人偏紫，旁白压成灰绿免得抢戏
func _speaker_color(who: String) -> Color:
	if who == "老柴":
		return Color("#c8632a")
	if who == "???":
		return Color("#6a4478")
	return Color("#4e5a4a")

func _chef_avatar(mood: String) -> Texture2D:
	match mood:
		"shock":
			return UiKit.art("characters/avatar_shock")
		"side":
			return UiKit.art("characters/avatar_side")
	return UiKit.art("characters/avatar_chef")

func _chef_art(mood: String) -> Texture2D:
	match mood:
		"shock":
			return UiKit.art("characters/chef_shock")
		"side":
			return UiKit.art("characters/chef_side")
		_:
			return UiKit.art("characters/chef_smirk")

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h["rect"] as Rect2).has_point(event.position):
				_skip()
				return
		_advance()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_advance()
		elif event.keycode == KEY_ESCAPE:
			_skip()

func _advance() -> void:
	if idx >= lines.size():
		return
	var L: Dictionary = lines[idx]
	var full := str(L.get("text", ""))
	if chars < full.length():
		chars = full.length()
		Sfx.play("story")
		return
	Sfx.play("story")
	idx += 1
	chars = 0.0
	if idx >= lines.size():
		_finish()

func _skip() -> void:
	_finish()

func _finish() -> void:
	if done:
		return
	done = true
	if on_done.is_valid():
		on_done.call()
