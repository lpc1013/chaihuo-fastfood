extends OvBase
## 暂停覆盖层：继续、重看引导、声音、台账、保存回标题。

var _hits: Array = []

func panel_rect() -> Rect2:
	var W := vp().x
	var H := vp().y
	var pw := 440.0
	var ph := 600.0
	return Rect2(W / 2 - pw / 2, H / 2 - ph / 2, pw, ph)

func _draw() -> void:
	_hits = []
	var W := vp().x
	var H := vp().y
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.72))
	var rect := panel_rect()
	UiKit.draw_nine(self, UiKit.art("ui/panel"), rect)
	var c := UiKit.panel_frame(rect)
	var ccx := c.position.x + c.size.x / 2
	UiKit.draw_text_centered(self, ccx, c.position.y + 30, Config.ui("pause"), 24, UiKit.INK, true)
	UiKit.draw_text_centered(self, ccx, c.position.y + 56, "第 %d 天 · 金币 %d" % [GameState.day, GameState.coins], 13, UiKit.INK_SOFT)
	var bw := minf(300.0, c.size.x)
	var bh := 44.0
	var bx := ccx - bw / 2
	var y := c.position.y + 74.0
	_btn(Rect2(bx, y, bw, bh), Config.ui("resume"), "resume", true)
	y += bh + 10
	_btn(Rect2(bx, y, bw, bh), Config.ui("replay_tutorial"), "tutorial", false)
	y += bh + 10
	_btn(Rect2(bx, y, bw, bh), "声音：开" if not GameState.muted else "声音：关", "sound", false)
	y += bh + 10
	_btn(Rect2(bx, y, bw, bh), "营业台账", "records", false)
	y += bh + 10
	_btn(Rect2(bx, y, bw, bh), "街区地图", "map", false)
	y += bh + 10
	_btn(Rect2(bx, y, bw, bh), Config.ui("save_exit"), "save_exit", false)

func _btn(rect: Rect2, label: String, id: String, primary: bool) -> void:
	var hovered := rect.has_point(_hover)
	var tex := "ui/plaque" if primary else "ui/tag"
	UiKit.draw_tex_box(self, UiKit.art(tex), rect,
		Color(1.12, 1.07, 0.98) if hovered else Color.WHITE)
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0 + 6,
		label, 18 if primary else 15, Color("#fff3dd") if primary else Color("#4a3524"), primary)
	_hits.append({"rect": rect, "id": id})

func _on_click(pos: Vector2) -> void:
	for h in _hits:
		if (h["rect"] as Rect2).has_point(pos):
			Sfx.play("tap")
			_action(str(h["id"]))
			return

func _on_escape() -> void:
	_do_resume()

func _on_outside_click() -> void:
	_do_resume()

func _do_resume() -> void:
	if main.current != null and main.current.has_method("resume_game"):
		main.current.call("resume_game")
	close()

func _action(id: String) -> void:
	match id:
		"resume":
			_do_resume()
		"tutorial":
			GameState.tut_done = false
			# 必须先关自己再开教学：restart_tutorial 走的闸是"已经有覆盖层就不开"，
			# 顺序反了一按就只是把暂停菜单关掉，引导根本没重放。
			close()
			if main.current != null and main.current.has_method("restart_tutorial"):
				main.current.call("restart_tutorial")
		"sound":
			GameState.toggle_muted()
			SaveManager.save_all()
		"records":
			var back_to_play: bool = str(main.current_name) == "play"
			close()
			main.goto("records", {"from": "play" if back_to_play else "title"})
		"map":
			var back2 := str(main.current_name) == "play"
			close()
			main.goto("map", {"from": "play" if back2 else "title"})
		"save_exit":
			SaveManager.save_all()
			close()
			main.goto("title")
