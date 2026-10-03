extends Node2D
## 玩法说明页：两栏排版，正文按面板内容区宽度自动换行。

var main: Node
var from := "title"
var _hits: Array = []
var _hover := Vector2(-1, -1)

const HEAD_H := 30.0
const LINE_H := 20.0
const SIZE := 13

func on_enter(params: Dictionary) -> void:
	from = str(params.get("from", "title"))

func _process(_delta: float) -> void:
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _sections() -> Array:
	return [
		["目标", [
			"按时出餐、攒声望、升级店面。一章七天，收满一章接着开下一章。",
			"客人等得越短小费越高，连续「完美」出餐会叠连击加成。",
		]],
		["点单与出餐", [
			"点小客人头顶的小票，选中这一单。",
			"按小票顺序点底部木格里的食材，一层层叠到案板上。",
			"汉堡 + 薯条 + 饮料凑齐后，把荷叶上的托盘拖给客人。",
		]],
		["厨房四件套", [
			"烤架：点空灶位放生肉饼，进度走到金色窗口再点一次翻面起锅。",
			"案板：生菜、番茄、洋葱、酸黄瓜要切——点一下或按住划过案板下刀。一次只压一种，切完才腾得出手拿下一个。",
			"炸锅：木格里先备土豆，点炸锅开炸，看准窗口捞起。",
			"饮料机：想接哪种就点哪一格（罐体整条都能点），点一次开始接，看准液位再点一次收。",
			"酱料台：台面左前方那四瓶。出餐前点酱料挤在小票上，最多三种，每加一种多给一截小费。",
		]],
		["柴火·声望·存档", [
			"炉火随时间变弱：点炉脚那枚「柴块压火口」续火，旁边那枚斧头进劈柴小游戏。炉边柴垛堆几根，就是还剩几根。",
			"左上那排声望星管两件事：星越多小费越厚，新菜也要够星才上得了桌。放走客人会掉星。",
			"做错没人要的托盘：点一下提起来、再点灶膛口丢掉（按住拖过去也一样），或点右上角那枚火焰圆钮——食材成本不退。",
			"开业前补货便宜，营业中补货算紧急补货，价格 ×1.5。",
			"空格 / 回车推进对话，Esc 暂停；进度自动存到 saves/。",
		]],
	]

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	UiKit.draw_cover(self, UiKit.art("backgrounds/bg_title"), Rect2(0, 0, W, H))
	draw_rect(Rect2(0, 0, W, H), Color(0.06, 0.05, 0.12, 0.66))
	UiKit.draw_title(self, W / 2, 62, Config.ui("help_title"), 30)
	var prect := Rect2(W * 0.10, 86.0, W * 0.80, H - 148.0)
	UiKit.draw_nine(self, UiKit.art("ui/panel"), prect)
	var c := UiKit.panel_frame(prect)
	var col_w := (c.size.x - 44.0) / 2.0
	var secs: Array = _sections()
	for col in 2:
		var x := c.position.x + col * (col_w + 44.0)
		var y := c.position.y + 10.0
		for i in range(col * 2, col * 2 + 2):
			if i >= secs.size():
				break
			y = _draw_section(x, y, col_w, secs[i] as Array)
	_btn(Rect2(W / 2 - 90, H - 52, 180, 40), Config.ui("back"), "back")

func _draw_section(x: float, y: float, col_w: float, sec: Array) -> float:
	UiKit.draw_text(self, Vector2(x, y + 16), str(sec[0]), 17, Color("#a8541c"), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var yy := y + HEAD_H
	for line in sec[1]:
		var wrapped := UiKit.wrap_text(str(line), col_w - 30.0, SIZE)
		for wi in wrapped.size():
			# 圆点只给首行；折下来的续行缩进对齐正文，否则一段话看着像三条并列要点
			var tx := x + 14.0 + (13.0 if wi > 0 else 0.0)
			UiKit.draw_text(self, Vector2(tx, yy + 13), ("· " if wi == 0 else "") + str(wrapped[wi]), SIZE, UiKit.INK)
			yy += LINE_H
		yy += 3.0
	return yy + 12.0

func _btn(rect: Rect2, label: String, id: String) -> void:
	var hovered := rect.has_point(_hover)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), rect, Color(1.1, 1.06, 1.0) if hovered else Color(1, 1, 1, 1))
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0 + 6, label, 15, Color("#5a3f26"), true)
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
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		main.goto(from)
