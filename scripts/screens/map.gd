extends Node2D
## 街区地图：本章走过的城南老街六个点位，标出已完成 / 今晚 / 未解锁。
## 一章一条路线、复用同六块路牌——ui/map_bg 上只有六块空白牌面，画不下十四章。

var main: Node
var from := "title"
var _hits: Array = []
var _hover := Vector2(-1, -1)
var t := 0.0
var selected := -1

func on_enter(params: Dictionary) -> void:
	from = str(params.get("from", "title"))
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _state(day: int) -> String:
	if day < GameState.day:
		return "done"
	if day == GameState.day:
		return "now"
	return "next"

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	UiKit.draw_tex_box(self, UiKit.art("ui/map_bg"), Rect2(0, 0, W, H))
	UiKit.draw_title(self, W / 2, 74, Config.map_caption(), 28)
	var nodes: Array = Config.map_nodes(GameState.day)
	var done_n := 0
	for n in nodes:
		if int((n as Dictionary).get("day", 0)) < GameState.day:
			done_n += 1
	var prog := "已走完 %d / %d 站" % [done_n, nodes.size()]
	var pw := UiKit.text_width(prog, 13, true) + 30.0
	UiKit.draw_tex_box(self, UiKit.art("ui/chip"), Rect2(W - pw - 18, 16, pw, 26))
	UiKit.draw_text_centered(self, W - 18 - pw / 2, 34, prog, 13, Color("#5a3f26"), true)
	for n in nodes:
		var nd: Dictionary = n
		var day := int(nd.get("day", 0))
		var st := _state(day)
		var sign := nd.get("sign", [0.5, 0.5]) as Array
		var pin := nd.get("pin", [0.5, 0.5]) as Array
		var sx := float(sign[0]) * W
		var sy := float(sign[1]) * H
		var px := float(pin[0]) * W
		var py := float(pin[1]) * H
		var col := Color("#5a3f26") if st != "next" else Color(0.42, 0.36, 0.30, 0.55)
		if st == "now" or selected == day:
			var gp := 0.5 + 0.5 * sin(t * 4.0)
			UiKit.draw_focus(self, Rect2(px - 62, py - 58, 124, 116), Color(1.0, 0.82, 0.30, 0.55 + 0.4 * gp))
		# 站名直接刷在木路牌上：一块 ui/tag 盖住原画里那块空白牌面
		var label := "D%d  %s" % [day, str(nd.get("name", ""))]
		# 站名直接刷在木路牌上：一块 ui/tag 盖住原画里那块空白牌面。
		# 留白要按 ui/tag 两端那两颗绳结算：只加 30px 时结会压住首尾一个字（D6 城南旅馆最明显）
		var lw := UiKit.text_width(label, 14, true) + 48.0
		var plate := Rect2(sx - lw / 2.0, sy - 13.0, lw, 26.0)
		UiKit.draw_tex_box(self, UiKit.art("ui/tag"), plate,
			Color(1, 1, 1, 1.0) if st != "next" else Color(0.80, 0.77, 0.72, 0.75))
		UiKit.draw_text_centered(self, sx, sy + 5, label, 14, col, true)
		if st == "done":
			UiKit.draw_tex_box(self, UiKit.art("ui/chip"), Rect2(plate.end.x - 8, plate.position.y - 6, 30, 22))
			UiKit.draw_text_centered(self, plate.end.x + 7, plate.position.y + 11, "√", 14, Color("#2f5a38"), true)
		_hits.append({"rect": Rect2(px - 66, py - 80, 132, 130), "id": "node", "day": day})
	var hint := _hint_for(nodes)
	var hw := minf(UiKit.text_width(hint, 15, true) + 46.0, W * 0.72)
	var hb := Rect2(W / 2 - hw / 2, H - 108, hw, 40)
	UiKit.draw_tex_box(self, UiKit.art("ui/bubble"), hb)
	UiKit.draw_text_centered(self, W / 2, hb.position.y + 26, hint, 15, Color("#4a3a2a"))
	_btn(Rect2(W / 2 - 90, H - 56, 180, 40), Config.ui("back"), "back")

func _hint_for(nodes: Array) -> String:
	var want := selected if selected > 0 else GameState.day
	for n in nodes:
		var nd: Dictionary = n
		if int(nd.get("day", 0)) == want:
			return "%s：%s" % [str(nd.get("name", "")), str(nd.get("flavor", ""))]
	# 走到最后一站之后（每章那天没有牌子，是章末本身），提示换成收账那句
	var last_day := 0
	for n in nodes:
		last_day = maxi(last_day, int((n as Dictionary).get("day", 0)))
	if GameState.day > last_day:
		return Config.map_hint("hint_all_done")
	return Config.map_hint("hint_browse")

func _btn(rect: Rect2, label: String, id: String) -> void:
	var hovered := rect.has_point(_hover)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), rect, Color(1.1, 1.06, 1.0) if hovered else Color(1, 1, 1, 1))
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0 + 6,
		label, 15, Color("#5a3f26"), true)
	_hits.append({"rect": rect, "id": id})

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h["rect"] as Rect2).has_point(event.position):
				Sfx.play("tap")
				if str(h["id"]) == "node":
					selected = int(h["day"])
				else:
					main.goto(from)
				return
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		main.goto(from)
