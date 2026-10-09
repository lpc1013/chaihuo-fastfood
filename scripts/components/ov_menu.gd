extends OvBase
## 菜单图鉴：摊开的菜谱书，左页右页分列当前已解锁的汉堡与配方。

var _hits: Array = []

## 纸面边界量自 tools/bookfit.py 叠出来的对照图，不是目测：
## 左页纸从 x≈253 才开始（211 那截是压着的书页堆），两页纸的可用底边在 y≈545，
## 再往下就是卷边和封面——原来框画到 573，第七层那颗胚子就是这么掉到书外的。
const PAGES := [Rect2(0.198, 0.115, 0.272, 0.625), Rect2(0.547, 0.115, 0.273, 0.625)]

func panel_rect() -> Rect2:
	var v := vp()
	return Rect2(0, 0, v.x, v.y)

func _page(i: int) -> Rect2:
	var v := vp()
	var p: Rect2 = PAGES[i]
	return Rect2(p.position.x * v.x, p.position.y * v.y, p.size.x * v.x, p.size.y * v.y)

func _draw() -> void:
	_hits = []
	var v := vp()
	draw_rect(Rect2(0, 0, v.x, v.y), Color(0, 0, 0, 0.72))
	UiKit.draw_tex_box(self, UiKit.art("ui/book_bg"), Rect2(0, 0, v.x, v.y))
	var pairs: Array = []
	for i in Config.burgers().size():
		var b: Dictionary = Config.burgers()[i]
		b["_i"] = i
		pairs.append(b)
	var half := int(ceil(float(pairs.size()) / 2.0))
	for pi in 2:
		var slice: Array = pairs.slice(0, half) if pi == 0 else pairs.slice(half)
		_draw_page(_page(pi), slice, pi)
	var bw := 150.0
	_btn(Rect2(v.x / 2 - bw / 2, v.y * 0.885, bw, 44), Config.ui("close"), "close")

func _draw_page(page: Rect2, burgers: Array, pi: int) -> void:
	var head := "菜单 · 图鉴" if pi == 0 else "配方"
	# 右页的纸在书脊那侧卷起来，实际可写边比 PAGES[1] 的矩形靠左一截：
	# 解锁提示从"未解锁"改成"第5天解锁"之后，最后一个字正好被卷边啃掉
	var rx := page.end.x - (16.0 if pi == 0 else 46.0)
	UiKit.draw_text_centered(self, page.position.x + page.size.x / 2, page.position.y + 30, head, 22,
		Color("#4a3524"), true)
	if burgers.is_empty():
		return
	var top := page.position.y + 52.0
	var row_h := (page.size.y - 70.0) / float(burgers.size())
	# 配料链允许换行：横着一排排到页边会冲出纸面（右页最后那格就压在皮脊上），
	# 而每行下面还空着一大片没用。字号按这一页最长的那条链统一算一次，
	# 同页各格才不会一格 52、一格 34 地参差
	var isz := minf(58.0, row_h * 0.56)
	var area_x := page.position.x + isz + 24.0
	# 配料链的右边界要用和文字同一个 rx：以前写死 page.end.x-18，比右页可写边宽出 28px，
	# 于是右页那条 4 连的煎蛋整个压在卷边上。
	var area_w := rx - area_x
	var room := row_h - 38.0 - 13.0
	var maxn := 1
	for b in burgers:
		maxn = maxi(maxn, (b as Dictionary).get("stack", []).size())
	var cs := 26.0
	var per := 1
	for want in [52.0, 46.0, 40.0, 34.0, 28.0]:
		var fit := maxi(1, int((area_w + 7.0) / (want + 7.0)))
		var rows := int(ceil(float(maxn) / float(fit)))
		if float(rows) * (want + 7.0) - 7.0 <= room:
			cs = want
			per = fit
			break
	for i in burgers.size():
		var b: Dictionary = burgers[i]
		var ry := top + i * row_h
		var idx := int(b.get("_i", 0))
		# 两道门槛分开报：差天数是"还不到时候"，差声望是"这周失误太多"，玩家要能看到自己卡在哪一头
		var day_locked := int(b.get("unlock_day", 1)) > GameState.day
		var locked := not Config.burger_open(idx)
		var gate := "¥%d" % int(b.get("price", 0))
		if locked:
			gate = "第%d天解锁" % int(b.get("unlock_day", 1)) if day_locked else "需%d★" % int(b.get("unlock_rep", 0))
		var ink := UiKit.INK_FAINT if locked else UiKit.INK
		UiKit.draw_tex_box(self, UiKit.art("ui/bar_track"),
			Rect2(page.position.x + 14, ry + row_h - 11, rx - page.position.x - 14.0, 5), Color(0.42, 0.30, 0.18, 0.16))
		UiKit.draw_tex_contain(self, UiKit.icon_burger(int(b.get("_i", 0))),
			Rect2(page.position.x + 10, ry + 6, isz, isz), Color(1, 1, 1, 0.45) if locked else Color.WHITE)
		var tx := page.position.x + isz + 24.0
		UiKit.draw_text(self, Vector2(tx, ry + 28), str(b.get("name", "")), 17, ink, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		UiKit.draw_text_right(self, rx, ry + 28, gate, 15,
			UiKit.GOLD if not locked else UiKit.INK_FAINT, true)
		# 做过的菜在图上盖一枚绿勾。已做过又被声望门槛锁回去的菜也照样留着——
		# 那记勾记的是"你确实做出来过"，是事实，不是当前可点状态。
		if GameState.dish_done(str(b.get("id", ""))):
			var r := maxf(7.0, isz * 0.22)
			_draw_done_stamp(page.position.x + 10.0 + isz - r * 0.34, ry + 6.0 + r * 0.34, r, not locked)
		var stack: Array = b.get("stack", [])
		var area_top := ry + 38.0
		for j in stack.size():
			var col := j % per
			var rw := int(float(j) / float(per))
			var ix := area_x + float(col) * (cs + 7.0)
			var iy := area_top + float(rw) * (cs + 7.0)
			UiKit.draw_tex_contain(self, UiKit.icon_ingredient(str(stack[j])), Rect2(ix, iy, cs, cs),
				Color(1, 1, 1, 0.5) if locked else Color.WHITE)
			if j < stack.size() - 1 and col < per - 1:
				UiKit.draw_text_centered(self, ix + cs + 3.5, iy + cs * 0.72, "+", 14, UiKit.INK_FAINT)

## 一枚绿勾章。**用 draw_line 画，不是打 "✓" 字符**——主题字体不一定有 U+2713，
## 缺字会静默画成豆腐块，而图鉴这张图没人会天天盯着看，根本发现不了。
func _draw_done_stamp(cx: float, cy: float, r: float, bright: bool) -> void:
	draw_circle(Vector2(cx, cy), r * 1.06, Color(0.98, 0.95, 0.86, 0.92))
	draw_circle(Vector2(cx, cy), r * 0.9,
		Color(0.24, 0.55, 0.26, 0.97) if bright else Color(0.44, 0.50, 0.44, 0.72))
	var w := maxf(1.8, r * 0.26)
	var ink := Color(0.99, 0.99, 0.95, 1.0)
	draw_line(Vector2(cx - r * 0.46, cy + r * 0.02), Vector2(cx - r * 0.13, cy + r * 0.38), ink, w, true)
	draw_line(Vector2(cx - r * 0.13, cy + r * 0.38), Vector2(cx + r * 0.50, cy - r * 0.40), ink, w, true)

func _btn(rect: Rect2, label: String, id: String) -> void:
	var hovered := rect.has_point(_hover)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), rect, Color(1.1, 1.06, 1.0) if hovered else Color(1, 1, 1, 1))
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0 + 6,
		label, 15, Color("#5a3f26"), true)
	_hits.append({"rect": rect, "id": id})

func _on_click(pos: Vector2) -> void:
	for h in _hits:
		if (h["rect"] as Rect2).has_point(pos):
			Sfx.play("tap")
			close()
			return

func _on_outside_click() -> void:
	close()
