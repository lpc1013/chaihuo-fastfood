extends OvBase
## 进货卡车覆盖层：常规补货 / 营业中紧急补货（价格 ×1.5）。

var emergency := false
var msg := ""
var msg_t := 0.0
var _hits: Array = []

func setup(params: Dictionary) -> void:
	emergency = bool(params.get("emergency", false))

func _on_tick(delta: float) -> void:
	if msg_t > 0.0:
		msg_t -= delta

func panel_rect() -> Rect2:
	var W := vp().x
	var H := vp().y
	var pw := minf(W * 0.62, 640.0)
	var ph := H * 0.82
	return Rect2(W / 2 - pw / 2, H / 2 - ph / 2, pw, ph)

func _draw() -> void:
	_hits = []
	var W := vp().x
	var H := vp().y
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.72))
	var rect := panel_rect()
	UiKit.draw_nine(self, UiKit.art("ui/panel"), rect)
	var c := UiKit.panel_frame(rect)
	var mult := float(Config.economy.get("emergency_restock_mult", 1.5)) if emergency else 1.0
	var title := Config.ui("truck_emergency") if emergency else Config.ui("truck_title")
	UiKit.draw_text(self, Vector2(c.position.x + 10, c.position.y + 26), title, 20, UiKit.INK if not emergency else UiKit.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	UiKit.draw_text_right(self, c.end.x - 10, c.position.y + 26, "钱包 %d 金币" % GameState.coins, 15, UiKit.GOLD, true)
	var keys: Array = Config.shop_order()
	var top := c.position.y + 48.0
	var row_h := (c.size.y - 100.0) / float(keys.size())
	# 按钮高度跟着行高收：多摆一样东西（比如可乐）时不能再按死 32px，否则上下两排按钮会贴在一起
	var bh := minf(32.0, row_h - 2.0)
	for i in keys.size():
		var key := str(keys[i])
		var ry := top + i * row_h
		var icon := UiKit.icon_ingredient(key)
		UiKit.draw_tex_contain(self, icon, Rect2(c.position.x + 12, ry + row_h / 2 - 19, 38, 38))
		UiKit.draw_text(self, Vector2(c.position.x + 60, ry + row_h / 2 + 3), Config.ingredient_name(key), 16, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		var stock := GameState.inv_count(key)
		UiKit.draw_text(self, Vector2(c.position.x + 158, ry + row_h / 2 + 3), "库存 %d" % stock, 14, UiKit.GREEN if stock > 0 else UiKit.RED)
		var unit := int(ceil(float(Config.ingredient(key).get("cost", 1)) * mult))
		_btn(Rect2(c.end.x - 196, ry + row_h / 2 - bh / 2, 84, bh), "+1 ¥%d" % unit, "b1:" + key)
		_btn(Rect2(c.end.x - 102, ry + row_h / 2 - bh / 2, 84, bh), "+5 ¥%d" % (unit * 5), "b5:" + key)
	_btn(Rect2(c.position.x + c.size.x / 2 - 60, c.end.y - 44, 120, 38), Config.ui("close"), "close")
	if msg_t > 0.0:
		UiKit.draw_text_centered(self, c.position.x + c.size.x / 2, c.end.y - 54, msg, 13, UiKit.RED)

func _btn(rect: Rect2, label: String, id: String) -> void:
	var hovered := rect.has_point(_hover)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), rect, Color(1.1, 1.06, 1.0) if hovered else Color(1, 1, 1, 1))
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0 + 5, label, 13, Color("#5a3f26"), true)
	_hits.append({"rect": rect, "id": id})

func _on_click(pos: Vector2) -> void:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if (h["rect"] as Rect2).has_point(pos):
			_action(str(h["id"]))
			return

func _action(id: String) -> void:
	Sfx.play("tap")
	if id == "close":
		close()
		return
	if id.begins_with("b1:") or id.begins_with("b5:"):
		var n := 1 if id.begins_with("b1:") else 5
		var key := id.substr(3)
		var mult := float(Config.economy.get("emergency_restock_mult", 1.5)) if emergency else 1.0
		var cost := GameState.ingredient_cost(key, n, mult)
		if GameState.buy_ingredient(key, n, mult):
			Sfx.play("coin")
			GameState.shop_spent_pending += cost
			SaveManager.save_all()
		else:
			msg = Config.misc("no_coins")
			msg_t = 2.2
			Sfx.play("angry")
