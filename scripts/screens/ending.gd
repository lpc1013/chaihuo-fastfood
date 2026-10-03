extends Node2D
## 结局页：teaser（第 1 天打烊后的「未完待续」）与 chapter（每一章最后一天的阶段达成）。

var main: Node
var mode := "chapter"
var chapter := 1
var _hits: Array = []
var _hover := Vector2(-1, -1)
var t := 0.0

func on_enter(params: Dictionary) -> void:
	mode = str(params.get("mode", "chapter"))
	chapter = clampi(int(params.get("chapter", Config.chapter_count())), 1, Config.chapter_count())
	t = 0.0
	if mode != "teaser":
		# 记住走到过哪一章：不然 endless 里每天打烊都会再弹一次章末页
		GameState.ending_chapter = maxi(GameState.ending_chapter, chapter)
		SaveManager.save_all()

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	var bg := "backgrounds/bg_mystery" if mode == "teaser" else "backgrounds/bg_title"
	UiKit.draw_cover(self, UiKit.art(bg), Rect2(0, 0, W, H))
	draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.04, 0.10, 0.58))
	if mode == "teaser":
		# 圆框往下挪：0.42 时圆顶在 y=151，正好把 0.23 那行副标题压在柴犬的毛上
		UiKit.draw_portrait(self, UiKit.art("characters/chef_side"), Vector2(W / 2, H * 0.48), minf(W, H) * 0.21)
		# 三行都从 story 顶层取。以前标题那行写的是 Config.ui("teaser_title")，
		# 而 ui() 读的是 story["ui"] 那个块——teaser_title 根本不在里面，取回来是空串，
		# 外面那圈 Config.story.has("teaser_title") 判的却是顶层，于是"键在"为真、
		# 画出来为空。判存在的键和取值的键必须指向同一处，否则 44 号大标题静默消失。
		UiKit.draw_text_centered(self, W / 2, H * 0.16, str(Config.story.get("teaser_title", "")), 44, Color("#ffd98a"), true)
		UiKit.draw_text_centered(self, W / 2, H * 0.23, str(Config.story.get("teaser_subtitle", "")), 18, Color("#e0d4ea"))
		_btn(Rect2(W / 2 - 130, H * 0.78, 260, 54), str(Config.story.get("teaser_button", "")), "continue", true)
	else:
		# 圆框从 0.36 抬到 0.27：原来四行结语（173~263）正好横压在柴犬脸上，
		# 毛色底上那几行白字根本读不了。抬上去之后结语落在圆框下方。
		UiKit.draw_portrait(self, UiKit.art("characters/chef_smirk"), Vector2(W / 2, H * 0.27), minf(W, H) * 0.155)
		UiKit.draw_text_centered(self, W / 2, H * 0.085,
			Config.ui("chapter_end_title_fmt") % [UiKit.cn_num(chapter), Config.chapter_name(chapter)],
			34, Color("#ffd98a"), true)
		var lines := Config.ending_lines(chapter)
		var ly := H * 0.445
		for i in lines.size():
			UiKit.draw_text_centered(self, W / 2, ly + i * 27, str(lines[i]), 17 if i < lines.size() - 1 else 15, Color(0.94, 0.9, 0.96, 0.92 if i < lines.size() - 1 else 0.7))
		# 总览指标
		var mw := 170.0
		var mh := 84.0
		var gap := 22.0
		var mx := W / 2 - (mw * 4 + gap * 3) / 2.0
		var my := H * 0.60
		UiKit.draw_metric(self, Rect2(mx, my, mw, mh), str(GameState.total_coins), "累计收入（金币）", UiKit.GOLD)
		UiKit.draw_metric(self, Rect2(mx + mw + gap, my, mw, mh), str(GameState.total_served), "累计出餐", UiKit.EMBER)
		UiKit.draw_metric(self, Rect2(mx + (mw + gap) * 2, my, mw, mh), "x%d" % GameState.best_combo, "最高连击", UiKit.EMBER)
		UiKit.draw_metric(self, Rect2(mx + (mw + gap) * 3, my, mw, mh), "%.1f" % GameState.rep, "声望", UiKit.GREEN)
		# 天数那一行落在指标条和按钮之间那条空带里（指标到 516、按钮从 590 起）。
		# 挂在标题下面会骑到圆框上——结语那四行本来就在读圆框下方的空档。
		UiKit.draw_text_centered(self, W / 2, H * 0.755,
			Config.ui("chapter_end_day_fmt") % Config.chapter_end_day(chapter), 15, Color(0.86, 0.82, 0.9, 0.8))
		var last_chapter := chapter >= Config.chapter_count()
		var go_label := Config.ui("chapter_end_final")
		if not last_chapter:
			go_label = Config.ui("chapter_next_fmt") % UiKit.cn_num(chapter + 1)
		_btn(Rect2(W / 2 - 290, H * 0.82, 270, 54), go_label, "continue", true)
		_btn(Rect2(W / 2 + 20, H * 0.82, 270, 54), "回到标题", "title", false)

func _btn(rect: Rect2, label: String, id: String, primary: bool) -> void:
	var hovered := rect.has_point(_hover)
	var tex := "ui/plaque" if primary else "ui/tag"
	var mod := Color(1.12, 1.07, 0.98) if hovered else Color.WHITE
	UiKit.draw_tex_box(self, UiKit.art(tex), rect, mod)
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0 + 6,
		label, 19 if primary else 14, Color("#fff3dd") if primary else Color("#4a3524"), primary)
	_hits.append({"rect": rect, "id": id})

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h["rect"] as Rect2).has_point(event.position):
				Sfx.play("tap")
				if str(h["id"]) == "continue":
					# teaser（第 1 天后那张「未完待续」）直接进下一天；
					# 章末页要走 main 那一步，好让下一章的开场剧情有地方插进去。
					if mode == "teaser":
						main.advance_day()
					else:
						main.after_chapter_page(chapter)
				else:
					main.goto("title")
				return
