extends Node2D
## 营业台账：总览指标 + 每日记录 + 订单明细（可滚动回溯）。

var main: Node
var from := "title"
var _hits: Array = []
var _hover := Vector2(-1, -1)
var left_scroll := 0.0
var right_scroll := 0.0
## 最近一帧订单明细真的画了几行。表头写着"最近 N 笔"而列表画空（比如某条记录字段类型
## 不对、_draw_order_panel 中途抛错）只有像素层看得出来，而像素判据又极易被纸色/夜色骗过，
## 所以让画的人自己报数。
var drawn_orders := 0

func on_enter(params: Dictionary) -> void:
	from = str(params.get("from", "title"))
	left_scroll = 0.0
	right_scroll = 0.0

func _process(_delta: float) -> void:
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	UiKit.draw_cover(self, UiKit.art("backgrounds/bg_title"), Rect2(0, 0, W, H))
	draw_rect(Rect2(0, 0, W, H), Color(0.06, 0.05, 0.12, 0.64))
	UiKit.draw_title(self, W / 2, 62, Config.ui("records_title"), 30)
	var records: Array = SaveManager.day_records()
	var orders: Array = SaveManager.orders()
	# 指标卡
	var gap := 16.0
	var mx := W * 0.05
	var mw := (W * 0.90 - gap * 3.0) / 4.0
	var mh := 72.0
	var my := 98.0
	UiKit.draw_metric(self, Rect2(mx, my, mw, mh), str(GameState.total_coins), "累计收入（金币）", UiKit.GOLD)
	UiKit.draw_metric(self, Rect2(mx + mw + gap, my, mw, mh), str(GameState.total_served), "累计出餐", UiKit.EMBER)
	UiKit.draw_metric(self, Rect2(mx + (mw + gap) * 2, my, mw, mh), "x%d" % GameState.best_combo, "最高连击", UiKit.EMBER)
	UiKit.draw_metric(self, Rect2(mx + (mw + gap) * 3, my, mw, mh), "%d" % GameState.day, "当前天数", UiKit.GREEN)
	var py := 192.0
	var ph := H - py - 92.0
	if records.is_empty():
		UiKit.draw_nine(self, UiKit.art("ui/panel"), Rect2(W * 0.18, py, W * 0.64, ph))
		UiKit.draw_text_centered(self, W / 2, py + ph * 0.45, Config.ui("records_empty"), 18, UiKit.INK_SOFT)
	else:
		_draw_day_panel(Rect2(W * 0.05, py, W * 0.42, ph), records)
		_draw_order_panel(Rect2(W * 0.53, py, W * 0.42, ph), orders)
	_btn(Rect2(W / 2 - 90, H - 74, 180, 46), Config.ui("back"), "back")

func _draw_day_panel(rect: Rect2, records: Array) -> void:
	UiKit.draw_nine(self, UiKit.art("ui/panel"), rect)
	# ui/panel 的绳边加四角绳结要吃掉一圈，正文一律从 panel_frame 内沿起排；
	# 早先按 rect+20/30 起排时表头被左上的绳结盖住、行尾压到右边的绳子上
	var c := UiKit.panel_frame(rect)
	UiKit.draw_text(self, Vector2(c.position.x + 8, c.position.y + 16), Config.ui("records_days"), 17, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var cols := [8.0, 46.0, 108.0, 170.0, 232.0, 310.0]
	var header_y := c.position.y + 40.0
	var heads: Array = ["日", "出餐", "流失", "完美", "收入", "声望"]
	for hi in heads.size():
		UiKit.draw_text(self, Vector2(c.position.x + cols[hi], header_y), str(heads[hi]), 14, UiKit.INK_FAINT)
	var row_h := 32.0
	var list_top := c.position.y + 50.0
	var list_h := c.end.y - 8.0 - list_top
	var content_h := records.size() * row_h
	left_scroll = clampf(left_scroll, 0.0, maxf(0.0, content_h - list_h))
	draw_set_transform(Vector2(0, -left_scroll))
	for i in records.size():
		var r: Dictionary = records[i]
		var ry := list_top + i * row_h
		# 只画整行都放得下的：末行差半截时它的副标题会压到底部绳边上
		if ry + row_h < list_top or ry + row_h > list_top + list_h:
			continue
		if i % 2 == 0:
			# 斑马纹改用木轨素材，不再画圆角色块
			UiKit.draw_tex_box(self, UiKit.art("ui/bar_track"),
				Rect2(c.position.x + 4, ry, c.size.x - 26.0, row_h - 4), Color(0.55, 0.38, 0.22, 0.20))
		# 收入这一列是**实收**；当天有硬币没捡到就被收币人扫走，就写成 "520-25"，
		# 免得台账的数跟玩家手里的钱对不上又找不到原因。
		var swept_r := int(r.get("swept", 0))
		var coins_txt := str(int(r.get("coins", 0)))
		if swept_r > 0:
			coins_txt += "-%d" % swept_r
		var vals: Array = [
			"D%d" % int(r.get("day", 0)),
			"%d/%d" % [int(r.get("served", 0)), int(r.get("planned", 0))],
			str(int(r.get("missed", 0))),
			str(int(r.get("perfects", 0))),
			coins_txt,
			"%.1f" % float(r.get("rep_after", 0)),
		]
		var cols_color: Array = [UiKit.INK, UiKit.INK,
			UiKit.RED if int(r.get("missed", 0)) > 0 else UiKit.INK, UiKit.INK, UiKit.GOLD, UiKit.INK]
		for vi in vals.size():
			UiKit.draw_text(self, Vector2(c.position.x + cols[vi], ry + 21), str(vals[vi]), 14,
				cols_color[vi] as Color, HORIZONTAL_ALIGNMENT_LEFT, -1, vi == 0 or vi == 4)
	draw_set_transform(Vector2.ZERO)
	# 滚动条示意
	var max_scroll := maxf(0.0, content_h - list_h)
	if max_scroll > 0.0:
		var sbh := maxf(30.0, list_h * (list_h / content_h))
		var sby := list_top + (list_h - sbh) * (left_scroll / max_scroll)
		UiKit.draw_scrollbar(self, Rect2(c.end.x - 15, sby, 17, sbh))

func _draw_order_panel(rect: Rect2, orders: Array) -> void:
	UiKit.draw_nine(self, UiKit.art("ui/panel"), rect)
	var c := UiKit.panel_frame(rect)
	UiKit.draw_text(self, Vector2(c.position.x + 8, c.position.y + 16),
		Config.ui("records_orders") + "（最近 %d 笔）" % mini(orders.size(), 60), 17, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var row_h := 42.0
	var list_top := c.position.y + 30.0
	var list_h := c.end.y - 8.0 - list_top
	var recent: Array = []
	var start := maxi(0, orders.size() - 60)
	for i in range(orders.size() - 1, start - 1, -1):
		recent.append(orders[i])
	var content_h := recent.size() * row_h
	right_scroll = clampf(right_scroll, 0.0, maxf(0.0, content_h - list_h))
	drawn_orders = 0
	draw_set_transform(Vector2(0, -right_scroll))
	for i in recent.size():
		var o: Dictionary = recent[i]
		var ry := list_top + i * row_h
		# 只画整行都放得下的：末行差半截时它的副标题会压到底部绳边上
		if ry + row_h < list_top or ry + row_h > list_top + list_h:
			continue
		# items 是从磁盘上的 ledger.json 读回来的，JSON 不保证它是数组：
		# 一条写成字符串的记录就能让 _draw_order_panel 整帧抛错，右边那一栏直接画空。
		var raw = o.get("items", [])
		var items: PackedStringArray = []
		if raw is Array:
			for it in raw:
				items.append(str(it))
		elif str(raw) != "":
			items.append(str(raw))
		var label := "D%d-%d  %s" % [int(o.get("day", 0)), int(o.get("seq", 0)), str(o.get("customer", ""))]
		UiKit.draw_text(self, Vector2(c.position.x + 8, ry + 15), label, 14, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		UiKit.draw_text(self, Vector2(c.position.x + 8, ry + 32), " / ".join(items), 12, UiKit.INK_SOFT)
		# 让出右侧一条滚动条的位置，否则 ¥ 数字会被滑块压在下面
		UiKit.draw_text_right(self, c.end.x - 26, ry + 23, "¥%d" % int(o.get("total", 0)), 15, UiKit.GOLD, true)
		drawn_orders += 1
	draw_set_transform(Vector2.ZERO)
	var max_scroll := maxf(0.0, content_h - list_h)
	if max_scroll > 0.0:
		var sbh := maxf(30.0, list_h * (list_h / content_h))
		var sby := list_top + (list_h - sbh) * (right_scroll / max_scroll)
		UiKit.draw_scrollbar(self, Rect2(c.end.x - 16, sby, 14, sbh))

func _btn(rect: Rect2, label: String, id: String) -> void:
	var hovered := rect.has_point(_hover)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), rect, Color(1.1, 1.06, 1.0) if hovered else Color(1, 1, 1, 1))
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0 + 6, label, 16, Color("#5a3f26"), true)
	_hits.append({"rect": rect, "id": id})

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h["rect"] as Rect2).has_point(event.position):
				Sfx.play("tap")
				main.goto(from)
				return
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll(event.position, 42.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll(event.position, -42.0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		main.goto(from)

func _scroll(pos: Vector2, dy: float) -> void:
	var W := _vp().x
	if pos.x < W * 0.5:
		left_scroll += dy
	else:
		right_scroll += dy
