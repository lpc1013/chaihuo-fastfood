extends Node2D
## 开业准备：照参考版式做成"木屋货架 + 左侧木牌页签 + 右侧柜台主厨"，
## 页签切换 食材 / 升级 / 菜谱 / 说明，商品卡嵌进货架的四个格子里。

var main: Node
var _hits: Array = []
var _hover := Vector2(-1, -1)
var msg := ""
var msg_t := 0.0
var t := 0.0
var tab := 0
var page := 0

const TABS := ["食材", "升级", "菜谱", "说明"]
const SHOP_TIPS := ["① 点客人头顶的小票选中订单", "② 从下面木格把食材拖上案板", "③ 要切的食材：点击或划过案板",
	"④ 烤架：放肉 → 翻面 → 金黄起锅", "⑤ 薯条与可乐盯住金色窗口", "⑥ 顶层面包一放即成堡",
	"⑦ 把荷叶上的成品拖给客人", "⑧ 做坏了没人要：整盘拖到灶膛口丢掉"]
# 四格货架的纸衬位置是量自 backgrounds/bg_shop.png 的（架子有透视，左右两列宽度本来就不同），
# 用统一网格会把图标和按钮甩到木隔板上
const CELLS := [
	Rect2(0.418, 0.438, 0.113, 0.111), Rect2(0.545, 0.429, 0.136, 0.124),
	Rect2(0.414, 0.623, 0.115, 0.126), Rect2(0.545, 0.630, 0.136, 0.145),
]
# 升级页不吃货架那四格：卡片要装得下「效果数值」，货架格只有 80~104px 高。
# 这一页把主厨让开，用整条台面摆 2×2 的升级卡。
const UP_CELLS := [
	Rect2(0.412, 0.368, 0.260, 0.140), Rect2(0.690, 0.368, 0.260, 0.140),
	Rect2(0.412, 0.524, 0.260, 0.140), Rect2(0.690, 0.524, 0.260, 0.140),
]
const EFFECT_LABEL := {
	"grill_slots_add": "烤位 +%d",
	"fire_decay_mult": "炉火消耗 ×%s",
	"cook_speed_mult": "出餐提速 ×%s",
	"patience_decay_mult": "耐心流失 ×%s",
	"tip_flat_bonus": "小费 +%d/单",
	"customers_per_day_add": "每日客人 +%d",
	"auto_turn": "到点自动翻面",
	"cut_need_mult": "所需刀数 ×%s",
}

func on_enter(_params: Dictionary) -> void:
	msg = ""
	msg_t = 0.0
	# 每天进店都从「食材」第一页起：这是每天非做不可的那件事。以前 tab/page 会留着
	# 昨天的位置，昨晚翻去看过菜谱，今天早上进来就站在菜谱页上找不到买面包的地方。
	tab = 0
	page = 0

func _process(delta: float) -> void:
	t += delta
	if msg_t > 0.0:
		msg_t -= delta
	queue_redraw()

func _vp() -> Vector2:
	return get_viewport_rect().size

func _preview_count() -> int:
	var sim := DaySim.new()
	return sim.build_day_plan(GameState.day).size()

func _sc(r: Rect2) -> Rect2:
	var W := _vp().x
	var H := _vp().y
	return Rect2(r.position.x * W, r.position.y * H, r.size.x * W, r.size.y * H)

func _draw() -> void:
	_hits = []
	var W := _vp().x
	var H := _vp().y
	UiKit.draw_cover(self, UiKit.art("backgrounds/bg_shop"), Rect2(0, 0, W, H))
	UiKit.draw_title(self, W * 0.5, H * 0.088, Config.ui("shop_title_fmt") % GameState.day, 26)
	var cw := W * 0.15
	var wallet := Rect2(W * 0.025, H * 0.038, cw, H * 0.072)
	UiKit.draw_tex_box(self, UiKit.art("ui/chip"), wallet)
	UiKit.draw_text_in(self, wallet, Config.ui("wallet_fmt") % GameState.coins, 15, Color("#8a4a12"), true)
	var sub := "今日预计接待 %d 位 · 备货支出 %d" % [_preview_count(), GameState.shop_spent_pending]
	var sw := UiKit.text_width(sub, 13, true) + W * 0.06
	var subr := Rect2(W * 0.5 - sw / 2.0, H * 0.145, sw, H * 0.06)
	UiKit.draw_tex_box(self, UiKit.art("ui/chip"), subr)
	UiKit.draw_text_in(self, subr, sub, 14, Color("#5a4230"), true)
	for i in TABS.size():
		var r := _sc(Rect2(0.290, 0.372 + i * 0.090, 0.105, 0.078))
		UiKit.draw_tex_box(self, UiKit.art("ui/tag"), r, Color(1.08, 1.05, 1.0) if tab == i else Color(0.88, 0.85, 0.80))
		UiKit.draw_text_in(self, r, TABS[i], 15, Color("#7a3c12") if tab == i else Color("#6a5a48"), true)
		_hits.append({"rect": r, "id": "tab:%d" % i})
	if tab != 1:
		UiKit.draw_sprite(self, UiKit.art("characters/chef_smirk"), W * 0.795, H * 0.655, H * 0.36)
	_draw_cards(W, H)

func _items() -> Array:
	var items: Array = []
	match tab:
		0:
			for k in Config.shop_order():
				items.append({"key": str(k)})
		1:
			for u in Config.upgrade_defs():
				items.append({"up": u})
		2:
			for b in Config.burgers():
				items.append({"dish": b})
		3:
			for s in SHOP_TIPS:
				items.append({"tip": str(s)})
	return items

func _page_count() -> int:
	return maxi(1, int(ceil(float(_items().size()) / float(CELLS.size()))))

func _draw_cards(W: float, H: float) -> void:
	var items: Array = _items()
	var per := CELLS.size()
	var cells := CELLS if tab != 1 else UP_CELLS
	var pages := _page_count()
	page = clampi(page, 0, pages - 1)
	for i in per:
		var idx := page * per + i
		if idx >= items.size():
			continue
		_card(_sc(cells[i]), items[idx])
	if pages > 1:
		_btn(Rect2(W * 0.430, H * 0.812, W * 0.055, H * 0.058), "◀", "pg:-1", page > 0)
		_btn(Rect2(W * 0.615, H * 0.812, W * 0.055, H * 0.058), "▶", "pg:1", page < pages - 1)
		UiKit.draw_text_centered(self, W * 0.55, H * 0.850, "%d / %d" % [page + 1, pages], 14, Color("#f0dfc0"), true)
	_btn(Rect2(W * 0.42, H * 0.888, W * 0.24, H * 0.082), Config.ui("open_business"), "start", true)
	_btn(Rect2(W * 0.025, H * 0.888, W * 0.12, H * 0.072), "返回", "back", true)
	if msg_t > 0.0:
		var mw := UiKit.text_width(msg, 14, true) + 44.0
		# 原来落在 H*0.790，正好和翻页的 ◀ 撞在一块；副标题下方那条带是空的
		var mr := Rect2(W * 0.5 - mw / 2.0, H * 0.218, mw, H * 0.062)
		UiKit.draw_tex_box(self, UiKit.art("ui/tag"), mr)
		UiKit.draw_text_in(self, mr, msg, 14, Color("#a03a22"), true)

func _card(r: Rect2, it: Dictionary) -> void:
	if it.has("key"):
		_card_ing(r, str(it["key"]))
	elif it.has("up"):
		_card_up(r, it["up"])
	elif it.has("dish"):
		_card_dish(r, it["dish"])
	elif it.has("tip"):
		_card_tip(r, str(it["tip"]))

func _card_ing(r: Rect2, key: String) -> void:
	var locked := int(Config.ingredient(key).get("unlock_day", 1)) > GameState.day
	var isz := r.size.y * 0.58
	UiKit.draw_sprite(self, UiKit.icon_ingredient(key), r.position.x + r.size.x * 0.24,
		r.position.y + r.size.y * 0.56, isz, Color(1, 1, 1, 0.32) if locked else Color(1, 1, 1, 1.0))
	var tx := r.position.x + r.size.x * 0.46
	UiKit.draw_text(self, Vector2(tx, r.position.y + r.size.y * 0.28), Config.ingredient_name(key),
		16, Color("#4a3524"), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var stock := GameState.inv_count(key)
	UiKit.draw_text(self, Vector2(tx, r.position.y + r.size.y * 0.50), "库存 %d" % stock,
		14, UiKit.GREEN if stock > 0 else UiKit.RED)
	if locked:
		UiKit.draw_text(self, Vector2(tx, r.position.y + r.size.y * 0.72),
			"第 %d 天解锁" % int(Config.ingredient(key).get("unlock_day", 1)), 13, Color("#8a7a66"))
		return
	var unit := int(Config.ingredient(key).get("cost", 1))
	var bh := r.size.y * 0.27
	_btn(Rect2(r.position.x + r.size.x * 0.05, r.end.y - bh - 4.0, r.size.x * 0.43, bh), "+1 ¥%d" % unit, "b1:" + key, true)
	_btn(Rect2(r.position.x + r.size.x * 0.52, r.end.y - bh - 4.0, r.size.x * 0.43, bh), "+5 ¥%d" % (unit * 5), "b5:" + key, true)

func _card_up(r: Rect2, u: Dictionary) -> void:
	var uid := str(u.get("id", ""))
	var owned := GameState.has_upgrade(uid)
	var cost := int(u.get("cost", 0))
	# 别用 ui/chip 当卡底：那是一圈绳结，可写区域是个椭圆，左端第一两个字必然压到绳子上
	UiKit.draw_panel(self, r, 10.0,
		Color("#eef3e6") if owned else Color("#fdf6e8"), 2.0, Color("#8a6a44"))
	if not owned and r.has_point(_hover):
		UiKit.draw_focus(self, r.grow(-2.0), Color(1.0, 0.86, 0.52, 0.72))
	UiKit.draw_text(self, Vector2(r.position.x + 14, r.position.y + 28), str(u.get("name", "")),
		17, UiKit.GREEN if owned else Color("#4a3524"), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	# 效果直接按 upgrades.json 里的数字生成，不另写一份文案，免得两边说得不一样
	UiKit.draw_text(self, Vector2(r.position.x + 14, r.position.y + 52), _effect_line(u),
		14, Color("#2f6b4a"), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var dl := UiKit.wrap_text(str(u.get("desc", "")), r.size.x - 28.0, 12)
	for j in mini(dl.size(), 2):
		UiKit.draw_text(self, Vector2(r.position.x + 14, r.position.y + 72.0 + j * 14.0),
			str(dl[j]), 12, Color("#6a5a48"))
	var badge := Rect2(r.end.x - 96.0, r.position.y + 10, 84.0, 26.0)
	var poor := not owned and GameState.coins < cost
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), badge,
		Color(0.88, 0.94, 0.86) if owned else (Color(0.80, 0.76, 0.74) if poor else Color.WHITE))
	UiKit.draw_text_in(self, badge, "已拥有" if owned else "¥%d" % cost, 14,
		UiKit.GREEN if owned else (UiKit.RED if poor else Color("#8a4a12")), true)
	if not owned:
		_hits.append({"rect": r, "id": "up:" + uid})

func _num(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

func _effect_line(u: Dictionary) -> String:
	var eff: Dictionary = u.get("effects", {})
	var parts: Array = []
	for k in eff.keys():
		var key := str(k)
		var tpl := str(EFFECT_LABEL.get(key, key))
		if tpl.contains("%d"):
			parts.append(tpl % int(eff[key]))
		elif tpl.contains("%s"):
			parts.append(tpl % _num(float(eff[key])))
		else:
			parts.append(tpl)
	return " · ".join(parts)

func _card_dish(r: Rect2, b: Dictionary) -> void:
	var idx := Config.burgers().find(b)
	var isz := r.size.y * 0.46
	UiKit.draw_tex_contain(self, UiKit.icon_burger(idx), Rect2(r.position.x + 8, r.position.y + 8, isz, isz))
	UiKit.draw_text(self, Vector2(r.position.x + isz + 16, r.position.y + r.size.y * 0.24),
		str(b.get("name", "")), 16, Color("#4a3524"), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	UiKit.draw_text(self, Vector2(r.position.x + isz + 16, r.position.y + r.size.y * 0.44),
		"售价 ¥%d" % int(b.get("price", 0)), 14, Color("#8a4a12"))
	var stack: Array = b.get("stack", [])
	var iw := (r.size.x - 20.0) / float(maxi(stack.size(), 1))
	for j in stack.size():
		UiKit.draw_tex_contain(self, UiKit.icon_ingredient(str(stack[j])),
			Rect2(r.position.x + 10 + j * iw, r.end.y - r.size.y * 0.42, iw - 4.0, r.size.y * 0.36))

func _card_tip(r: Rect2, text: String) -> void:
	# 一条提示一格：以前七条全塞进左上那一格，第 4 行起就画到木隔板外面去了
	var wrapped := UiKit.wrap_text(text, r.size.x - 24.0, 14)
	for j in mini(wrapped.size(), 3):
		UiKit.draw_text(self, Vector2(r.position.x + 12, r.position.y + r.size.y * 0.42 + j * 20.0),
			str(wrapped[j]), 14, Color("#4a3524"))

func _btn(rect: Rect2, label: String, id: String, enabled: bool) -> void:
	var hovered := enabled and rect.has_point(_hover)
	var tint := Color(1.10, 1.08, 1.03) if hovered else Color(1, 1, 1, 1)
	if not enabled:
		tint = Color(0.74, 0.72, 0.69, 0.92)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), rect, tint)
	var big := rect.size.y > _vp().y * 0.07
	var fs := 20 if big else 14
	UiKit.draw_text_in(self, rect, label, fs, Color("#7a3c12") if enabled else Color("#8a8078"), true)
	_hits.append({"rect": rect, "id": id})

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(_hits.size() - 1, -1, -1):
			var h: Dictionary = _hits[i]
			if (h["rect"] as Rect2).has_point(event.position):
				_click(str(h["id"]))
				return
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		_click("start")

func _click(id: String) -> void:
	Sfx.play("tap")
	if id.begins_with("tab:"):
		tab = int(id.substr(4))
		page = 0
		return
	if id.begins_with("pg:"):
		var step := 1 if id.substr(3) == "1" else -1
		# 到头那一侧的箭头只是画灰了，热区还在：以前直接把 page 加出界，靠下一帧
		# _draw_cards 的 clamp 悄悄修回来，玩家听到一声"点中了"却看到画面纹丝不动。
		var n := clampi(page + step, 0, _page_count() - 1)
		if n == page:
			_flash(Config.misc("page_start") if step < 0 else Config.misc("page_end"), false)
			return
		page = n
		# 翻页有自己的声音：和"点了一下按钮"的 tap 分开，翻没翻成功闭着眼也知道
		Sfx.play("page")
		return
	if id == "back":
		main.goto("title")
		return
	if id.begins_with("b1:") or id.begins_with("b5:"):
		var n := 1 if id.begins_with("b1:") else 5
		var key := id.substr(3)
		var cost := GameState.ingredient_cost(key, n, 1.0)
		if GameState.buy_ingredient(key, n, 1.0):
			Sfx.play("coin")
			GameState.shop_spent_pending += cost
			SaveManager.save_all()
		else:
			_flash(Config.misc("no_coins"))
	elif id.begins_with("up:"):
		var uid := id.substr(3)
		var u := Config.upgrade_def(uid)
		var cost2 := int(u.get("cost", 0))
		if GameState.buy_upgrade(uid):
			Sfx.play("purchase")
			GameState.shop_spent_pending += cost2
			SaveManager.save_all()
		else:
			_flash(Config.misc("no_coins"))
	elif id == "menu":
		main.open_overlay(load("res://scripts/components/ov_menu.gd").new())
	elif id == "start":
		if main.current_name == "shop":
			main.goto("play", {"fresh": true})

func _flash(text: String, hurt: bool = true) -> void:
	msg = text
	msg_t = 2.4
	# 翻到页边不是玩家做错事，不该挨一声"angry"
	if hurt:
		Sfx.play("angry")
