extends Node2D
## 打烊结算页：展示当日经营数据，提交台账并进入下一步流程。

var main: Node
var stats: Dictionary = {}
var orders: Array = []
var _hits: Array = []
var _hover := Vector2(-1, -1)
var t := 0.0

func on_enter(params: Dictionary) -> void:
	stats = params.get("stats", {})
	orders = params.get("orders", [])
	t = 0.0
	Sfx.play("fanfare")

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	UiKit.draw_cover(self, UiKit.art("backgrounds/bg_play_full"), Rect2(0, 0, W, H))
	draw_rect(Rect2(0, 0, W, H), Color(0.09, 0.06, 0.15, 0.60))
	var day := int(stats.get("day", GameState.day))
	UiKit.draw_title(self, W / 2, H * 0.135, Config.ui("dayend_title_fmt") % day, 32)
	var rows: Array = [
		[Config.ui("served"), "%d / %d" % [int(stats.get("served", 0)), int(stats.get("planned", 0))], UiKit.INK],
		[Config.ui("perfect"), "%d 份" % int(stats.get("perfects", 0)), UiKit.GREEN],
		[Config.ui("missed"), "%d 位" % int(stats.get("missed", 0)), UiKit.RED if int(stats.get("missed", 0)) > 0 else UiKit.INK],
		[Config.ui("today_coins"), "%d 金币" % int(stats.get("coins", 0)), Color("#8c6115")],
		[Config.ui("tips_total"), "%d 金币" % int(stats.get("tips", 0)), Color("#b34a1e")],
		[Config.ui("combo_peak"), "x%d" % int(stats.get("combo_peak", 0)), UiKit.INK],
		[Config.ui("rep_label"), "%.1f / 5" % float(stats.get("rep_after", GameState.rep)), Color("#8c6115")],
	]
	# 声望挂小费的倍率单独一行列出来：不写出来的话玩家只看到钱多了少了，不知道是星数在动
	var end_stars := int(roundf(float(stats.get("rep_after", GameState.rep))))
	rows.append(["声望小费倍率", "×%.2f（%d★）" % [Config.rep_tip_mult(end_stars), end_stars], UiKit.GREEN])
	# 钱是抛在台面上的，没捡到的那部分要单独说：不然"今日收入"比预期少，玩家只会以为
	# 是小费变薄了，猜不到有一笔被收币人扫走。
	var swept := int(stats.get("swept", 0))
	if swept > 0:
		rows.append(["没捡到的钱", "-%d 金币" % swept, UiKit.RED])
	var card := Rect2(W * 0.30, H * 0.215, W * 0.40, H * 0.575)
	UiKit.draw_nine(self, UiKit.art("ui/panel"), card)
	# ui/panel 是带绳边和角铁的剪贴板，正文必须按 panel_frame 的内沿起排，
	# 否则第一行会被顶绳吃掉一半（这页以前就是从 card.position.y+22 起排的）
	var c := UiKit.panel_frame(card)
	var rh := c.size.y / float(rows.size())
	for i in rows.size():
		var yy := c.position.y + i * rh
		if i > 0:
			draw_line(Vector2(c.position.x + 4.0, yy), Vector2(c.end.x - 4.0, yy), Color(0.72, 0.62, 0.48, 0.5), 1.0)
		UiKit.draw_text(self, Vector2(c.position.x + 14.0, yy + rh * 0.63), str(rows[i][0]), 16, UiKit.INK_SOFT)
		UiKit.draw_text_right(self, c.end.x - 14.0, yy + rh * 0.63, str(rows[i][1]), 16, rows[i][2] as Color, true)
	# 提示
	var tip := "提示：攒金币可在「设备升级」里升级店面，明天更好过。"
	if Config.is_chapter_end(day):
		tip = Config.ui("dayend_chapter_fmt") % UiKit.cn_num(Config.chapter_of(day))
	UiKit.draw_text_centered(self, W / 2, card.end.y + 30.0, tip, 13, Color(0.88, 0.83, 0.92, 0.85))
	# 按钮
	var bw := 280.0
	var bh := 54.0
	var brow := Rect2(W / 2 - bw / 2, H - 96, bw, bh)
	var hovered := brow.has_point(_hover)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), brow, Color(1.1, 1.06, 1.0) if hovered else Color(1, 1, 1, 1))
	UiKit.draw_text_centered(self, brow.position.x + bw / 2, brow.position.y + bh / 2 + 7, Config.ui("dayend_next"), 18, Color("#5a3f26"), true)
	_hits.append({"rect": brow, "id": "settle"})

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h["rect"] as Rect2).has_point(event.position):
				_settle()
				return
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		_settle()

func _settle() -> void:
	Sfx.play("tap")
	var spent := GameState.shop_spent_pending
	GameState.shop_spent_pending = 0
	main.after_day_settled(stats, orders, spent)
