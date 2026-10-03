extends Node
## 视觉工具包（UiKit）：字体、配色与绘制辅助。
## 设计基调：Build 式极简（暖白中性色 + 单一强调色「柴火橙」，克制留白），
## 与游戏既有的暖色卡通美术共存：游戏世界保留原画风，界面层用极简语言。

# ---------- 字体 ----------
var font_regular: Font
var font_bold: Font

func _ready() -> void:
	font_regular = _make_font(400)
	font_bold = _make_font(700)

func _make_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans SC", "SimHei", "sans-serif"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f

func font(bold_text: bool = false) -> Font:
	return font_bold if bold_text else font_regular

# ---------- 配色 ----------
const INK := Color("#2b231c")          # 主文字（暖黑）
const INK_SOFT := Color("#6f6257")     # 次级文字
const INK_FAINT := Color("#a2948a")    # 弱化文字
const CREAM := Color("#faf6ef")        # 面板底（暖白）
const CREAM_DEEP := Color("#f1e9dd")   # 次级面板底
const NIGHT := Color("#191411")        # 深色底
const NIGHT_PANEL := Color("#241d17")  # 深色面板
const EMBER := Color("#e8722c")        # 强调色：柴火橙（只给关键动作）
const EMBER_SOFT := Color("#f4a261")
const GOLD := Color("#d9a441")         # 金币功能色（克制使用）
const GREEN := Color("#3f8f6b")
const RED := Color("#c24b3a")
const WHITE := Color("#fffaf3")

var _sb_cache := {}

# ---------- 绘制辅助 ----------
func style_box(radius: float = 12.0, fill: Color = CREAM, border_w: float = 0.0,
		border: Color = INK) -> StyleBoxFlat:
	var key := "%.1f|%s|%.1f|%s" % [radius, fill.to_html(true), border_w,
		border.to_html(true)]
	if _sb_cache.has(key):
		return _sb_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	var r := int(radius)
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_right = r
	sb.corner_radius_bottom_left = r
	if border_w > 0.0:
		var bw := int(border_w)
		sb.border_width_left = bw
		sb.border_width_top = bw
		sb.border_width_right = bw
		sb.border_width_bottom = bw
		sb.border_color = border
	_sb_cache[key] = sb
	return sb

## 2026-09 美术修整：面板不再绘制「软黑影」垫层；层级一律用 hairline 描边与色差表达。
func draw_panel(ci: CanvasItem, rect: Rect2, radius: float = 12.0, fill: Color = CREAM,
		border_w: float = 0.0, border: Color = INK) -> void:
	ci.draw_style_box(style_box(radius, fill, border_w, border), rect)

func draw_text(ci: CanvasItem, pos: Vector2, text: String, size: int = 14, color: Color = INK,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, bold: bool = false) -> void:
	ci.draw_string(font(bold), pos, text, align, width, size, color)

func draw_text_centered(ci: CanvasItem, center_x: float, baseline_y: float, text: String,
		size: int = 14, color: Color = INK, bold: bool = false) -> void:
	var w := text_width(text, size, bold)
	draw_text(ci, Vector2(center_x - w / 2.0, baseline_y), text, size, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, bold)

func draw_text_right(ci: CanvasItem, right_x: float, baseline_y: float, text: String,
		size: int = 14, color: Color = INK, bold: bool = false) -> void:
	var w := text_width(text, size, bold)
	draw_text(ci, Vector2(right_x - w, baseline_y), text, size, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, bold)

func text_width(text: String, size: int = 14, bold: bool = false) -> float:
	return font(bold).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## 在矩形里双向居中一行字。垂直基线按 center + 0.36*size 抬，
## 用 h*0.64 这类固定比例时，框一矮字就飘到上半格（商店那些购买按钮就是这样）。
func draw_text_in(ci: CanvasItem, rect: Rect2, text: String, size: int = 14,
		color: Color = INK, bold: bool = false) -> void:
	draw_text_centered(ci, rect.position.x + rect.size.x / 2.0,
		rect.position.y + rect.size.y / 2.0 + size * 0.36, text, size, color, bold)

func draw_cover(ci: CanvasItem, tex: Texture2D, rect: Rect2) -> void:
	if tex == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var s := maxf(rect.size.x / ts.x, rect.size.y / ts.y)
	var ds := ts * s
	ci.draw_texture_rect(tex, Rect2(rect.position + (rect.size - ds) / 2.0, ds), false)

func draw_tex_box(ci: CanvasItem, tex: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	if tex == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	# 区域内采样：居中裁剪填满 rect，绝不溢出（避免贴图压到相邻面板）
	var s := maxf(rect.size.x / ts.x, rect.size.y / ts.y)
	var src := Rect2((ts.x - rect.size.x / s) / 2.0, (ts.y - rect.size.y / s) / 2.0, rect.size.x / s, rect.size.y / s)
	ci.draw_texture_rect_region(tex, rect, src, modulate)

var _nine_cache := {}

func _nine_src_margin(tex: Texture2D) -> float:
	var ts := tex.get_size()
	return maxf(2.0, minf(minf(ts.x, ts.y) * 0.24, minf(ts.x, ts.y) * 0.46))

func _nine_dm(tex: Texture2D, rect: Rect2, sm: float) -> float:
	return maxf(2.0, minf(sm, minf(rect.size.x, rect.size.y) * 0.30))

## ui/panel 是带木框和绳结角铁的剪贴板，画框实际要吃掉一圈边宽，
## 正文如果按 rect 左上角起排就会压在绳子上（进货卡车/暂停/玩法说明都踩过）。
func panel_frame(rect: Rect2, path: String = "ui/panel") -> Rect2:
	var tex := art(path)
	if tex == null:
		return rect
	var sm := _nine_src_margin(tex)
	var inset := _nine_dm(tex, rect, sm) * 0.58
	return Rect2(rect.position.x + inset, rect.position.y + inset,
		rect.size.x - inset * 2.0, rect.size.y - inset * 2.0)

## 九宫格贴图：源图按 sm 切九块，绘制时按 dm 缩放摆放。
## 源边距取自贴图（保证边框纹样完整），目标边距随面板尺寸收放，
## 否则小面板会被两个 150px 的角标吃掉中间，只剩几块散落的边框碎片。
func draw_nine(ci: CanvasItem, tex: Texture2D, rect: Rect2, modulate: Color = Color.WHITE, margin: float = -1.0) -> void:
	if tex == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	if margin < 0.0:
		margin = minf(ts.x, ts.y) * 0.24
	var sm := maxf(2.0, minf(margin, minf(ts.x, ts.y) * 0.46))
	var dm := _nine_dm(tex, rect, sm)
	var key := str(tex.resource_path) + "|" + str(int(sm))
	var pieces: Array = []
	if _nine_cache.has(key):
		pieces = _nine_cache[key]
	else:
		var sx := [0.0, sm, ts.x - sm, ts.x]
		var sy := [0.0, sm, ts.y - sm, ts.y]
		for r in 3:
			for c in 3:
				var a := AtlasTexture.new()
				a.atlas = tex
				a.region = Rect2(sx[c], sy[r], sx[c + 1] - sx[c], sy[r + 1] - sy[r])
				pieces.append(a)
		_nine_cache[key] = pieces
	var dw := [dm, maxf(rect.size.x - dm * 2.0, 1.0), dm]
	var dh := [dm, maxf(rect.size.y - dm * 2.0, 1.0), dm]
	var ox := [rect.position.x, rect.position.x + dm, rect.end.x - dm]
	var oy := [rect.position.y, rect.position.y + dm, rect.end.y - dm]
	for r in 3:
		for c in 3:
			ci.draw_texture_rect(pieces[r * 3 + c], Rect2(ox[c], oy[r], dw[c], dh[r]), false, modulate)

## 竖向渐变矩形（背景与 HUD 的衔接遮罩）
func draw_rect_gradient(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	ci.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))

## 四角括号式高亮框：ui/focus 的四角是圆弧、四边中段是细线，
## 走九宫格会把细线拉成两条光柱，所以只取四角分别绘制。
func draw_focus(ci: CanvasItem, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var tex := art("ui/focus")
	if tex == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var ts := tex.get_size()
	var sm := minf(ts.x, ts.y) * 0.30
	var dm := minf(rect.size.x, rect.size.y) * 0.30
	var src := [Rect2(0, 0, sm, sm), Rect2(ts.x - sm, 0, sm, sm),
		Rect2(0, ts.y - sm, sm, sm), Rect2(ts.x - sm, ts.y - sm, sm, sm)]
	var dst := [Rect2(rect.position, Vector2(dm, dm)),
		Rect2(Vector2(rect.end.x - dm, rect.position.y), Vector2(dm, dm)),
		Rect2(Vector2(rect.position.x, rect.end.y - dm), Vector2(dm, dm)),
		Rect2(rect.end - Vector2(dm, dm), Vector2(dm, dm))]
	for i in 4:
		ci.draw_texture_rect_region(tex, dst[i], src[i], modulate)

## 等比缩放绘制（完整显示、不溢出，用于小图标）
func draw_tex_contain(ci: CanvasItem, tex: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	if tex == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var s := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var ds := ts * s
	ci.draw_texture_rect(tex, Rect2(rect.position + (rect.size - ds) / 2.0, ds), false, modulate)

func draw_sprite(ci: CanvasItem, tex: Texture2D, center_x: float, bottom_y: float, h: float, modulate: Color = Color.WHITE) -> void:
	if tex == null or h <= 0.0:
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var dh := h
	var dw := h * ts.x / ts.y
	ci.draw_texture_rect(tex, Rect2(Vector2(center_x - dw / 2.0, bottom_y - dh), Vector2(dw, dh)), false, modulate)

# ---------- 纹理 ----------
const ART_DIR := "res://assets/art/"

var _tex_cache := {}

func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t

func art(rel: String) -> Texture2D:
	return tex(ART_DIR + rel + ".png")

const ING_ICONS := {
	"bun": "ingredients/ing_bun_t",
	"lettuce": "ingredients/ing_lettuce",
	"tomato": "ingredients/ing_tomato",
	"cheese": "ingredients/ing_cheese",
	"patty": "ingredients/ing_patty",
	"onion": "ingredients/ing_onion",
	"bacon": "ingredients/ing_bacon",
	"egg": "ingredients/ing_egg",
	"pickle": "ingredients/ing_pickle",
	"potato": "ingredients/ing_potato",
	"fries": "food/food_fries",
	"drink": "food/food_cola"
}

func icon_ingredient(key: String) -> Texture2D:
	return art(ING_ICONS.get(key, "ingredients/ing_bun_t"))

## 肉饼三态：生 / 煎好 / 煎糊
func patty_tex(p: float) -> Texture2D:
	if p > 1.18:
		return art("ingredients/pt_burnt")
	if p >= 0.42:
		return art("ingredients/pt_cooked")
	return art("ingredients/pt_raw")

func icon_burger(idx: int) -> Texture2D:
	var b := Config.burger(idx)
	var id := str(b.get("id", "classic"))
	return art("food/food_burger_" + id)

func drink_icon(did: String) -> Texture2D:
	for i in Config.drinks().size():
		if str(Config.drinks()[i].get("id", "")) == did:
			return art(str(Config.drinks()[i].get("art", "food/drink_cola")))
	return art("food/drink_cola")

func icon_food(kind: String) -> Texture2D:
	if kind == "fries":
		return art("food/food_fries")
	if kind == "drink":
		return art("food/food_cola")
	return art("food/food_fries")

## 把纹理裁成正方形后画进圆里。
## 直接整张贴进圆会把非正方形的立绘挤扁（老柴头像 640×355 就是这样变形的），
## 所以先按短边居中裁出正方形；focus 只在被裁的那根轴上起作用。
func draw_texture_circle(ci: CanvasItem, texture: Texture2D, center: Vector2, radius: float,
		modulate: Color = Color.WHITE, focus: Vector2 = Vector2(0.5, 0.5), zoom: float = 1.0) -> void:
	if texture == null or radius <= 0.0:
		return
	var ts := texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	# zoom>1 表示把裁切方框缩小（＝画面放大），圆框人像要能凑到脸上而不是拍到胸腔
	var s := minf(ts.x, ts.y) / maxf(zoom, 0.01)
	var uw := s / ts.x
	var vh := s / ts.y
	var u0 := clampf(focus.x - uw / 2.0, 0.0, 1.0 - uw)
	var v0 := clampf(focus.y - vh / 2.0, 0.0, 1.0 - vh)
	var n := 48
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	pts.resize(n + 1)
	uvs.resize(n + 1)
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		var p := center + Vector2(cos(a), sin(a)) * radius
		pts[i] = p
		var q := (p - center) / (radius * 2.0) + Vector2(0.5, 0.5)
		uvs[i] = Vector2(u0 + q.x * uw, v0 + q.y * vh)
	ci.draw_polygon(pts, PackedColorArray([modulate]), uvs, texture)

## 圆框人像该对准哪里：[焦点x, 焦点y, 缩放]，归一化到各张 png 自身。
## 数值由 tools/portraitfit.py 算：焦点=头心，缩放取"头部所有像素都落在圆弧内"的最大值。
## 三张全身立绘的头宽占图 0.81~0.85，所以**一点都不能放大**（原来写 1.61，
## 耳朵尖整个被圆框切掉 —— 用户报的"抠图漏了耳朵"）。方头像那张占图小，还能吃 1.12。
## 章号用汉字写（第一章 / 第二章），阿拉伯数字贴在"第""章"中间读着像漏字
const CN_NUM := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

func cn_num(n: int) -> String:
	if n >= 1 and n <= CN_NUM.size():
		return CN_NUM[n - 1]
	return str(n)

const PORTRAIT_HEAD := {
	"characters/chef_smirk": [0.5, 0.415, 1.0],
	"characters/chef_side": [0.5, 0.396, 1.0],
	"characters/chef_shock": [0.5, 0.328, 1.0],
	# 左上角 HUD 那枚方头像：狗头压在画布右下、左上一整块是空的，默认按短边居中裁
	# 会把脸甩到圆心右下方（focus 在 zoom=1 时根本不生效，必须同时 zoom>1 才挪得动）。
	# 1.12 是上限——再放大一点，两只耳朵尖就被圆框切掉。
	"characters/avatar_chef": [0.54, 0.525, 1.12],
}

func _portrait_anchor(texture: Texture2D) -> Array:
	var p := str(texture.resource_path)
	for k in PORTRAIT_HEAD.keys():
		if p.ends_with(str(k) + ".png"):
			return PORTRAIT_HEAD[k]
	return [0.5, 0.3, 1.0]

## 圆框人像：头像 + ui/avatar_frame，取代之前那种画一圈实心描边的圆环
func draw_portrait(ci: CanvasItem, tex: Texture2D, center: Vector2, radius: float) -> void:
	var a := _portrait_anchor(tex)
	draw_texture_circle(ci, tex, center, radius * 0.93, Color.WHITE,
		Vector2(float(a[0]), float(a[1])), float(a[2]))
	var f := art("ui/avatar_frame")
	if f != null:
		draw_tex_contain(ci, f, Rect2(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0))

## 只按锚点圆裁、不套绳框：剧情页那种"浮在场景里的圆头像"用这个。
## 以前它们直接调 draw_texture_circle（默认 focus 0.5/0.5、zoom 1），等于绕开
## PORTRAIT_HEAD 整张表 —— 耳朵尖被圆弧切掉就是这么来的。
func draw_portrait_crop(ci: CanvasItem, tex: Texture2D, center: Vector2, radius: float) -> void:
	if tex == null or radius <= 0.0:
		return
	var a := _portrait_anchor(tex)
	draw_texture_circle(ci, tex, center, radius, Color.WHITE,
		Vector2(float(a[0]), float(a[1])), float(a[2]))

## 竖向滚动条滑块。
## ui/chip 是横放的胶囊，圆头在左右两端：九宫格或居中裁切都会把圆头切掉、
## 只剩一条平口细线。所以整颗按原生宽高比画好，再转 90 度立起来。
func draw_scrollbar(ci: CanvasItem, rect: Rect2) -> void:
	var tex := art("ui/chip")
	if tex == null:
		return
	var w := maxf(rect.size.x, 20.0)
	var h := clampf(rect.size.y, w * 2.34, w * 3.4)
	var cx := rect.position.x + rect.size.x / 2.0
	var cy := rect.position.y + h / 2.0
	ci.draw_set_transform(Vector2(cx, cy), PI / 2.0, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(-h / 2.0, -w / 2.0, h, w), false)
	ci.draw_set_transform(Vector2.ZERO)

func draw_ring(ci: CanvasItem, center: Vector2, radius: float, color: Color, width: float = 3.0) -> void:
	ci.draw_arc(center, radius, 0.0, TAU, 64, color, width, true)

# ---------- 通用控件绘制 ----------
## ui/plaque 左上/右上角画着白花、右下角画着枝叶：牌面**中段**（纵向 35%~65%）的横向净空
## 是 0.139~0.802，而**上段**（0~35%）只剩 0.249~0.772。所以两件事都要成立文字才不被啃：
## ① 牌子按文字宽度撑到文字落在中段；② 牌宽按中段净空反推。
## PLAQUE_TEXT_FRAC 就是中段净空占比（量自 assets/art/ui/plaque.png）。
const PLAQUE_TEXT_FRAC := 0.64
## CJK 字面光学中心相对基线的高度，按 size 计（实测 32 号字顶到基线 1.16size、底 0.09size）
const PLAQUE_TEXT_LIFT := 0.52

## 木牌标题横幅：ui/plaque 作底，让牌绕着字的光学中心居中
func draw_title(ci: CanvasItem, cx: float, baseline_y: float, text: String, size: int = 30, max_w: float = 1100.0) -> void:
	var tw := text_width(text, size, true)
	var bw := minf(maxf(tw + size * 3.0, tw / PLAQUE_TEXT_FRAC), max_w)
	var bh := bw / 3.46
	var r := Rect2(cx - bw / 2.0, baseline_y - size * PLAQUE_TEXT_LIFT - bh / 2.0, bw, bh)
	var tex := art("ui/plaque")
	if tex != null:
		ci.draw_texture_rect(tex, r, false)
	draw_text_centered(ci, cx, baseline_y, text, size, Color("#fff3dd"), true)

func draw_metric(ci: CanvasItem, rect: Rect2, value: String, label: String,
		value_col: Color = EMBER, value_size: int = 30) -> void:
	draw_nine(ci, art("ui/chip"), rect)
	var cx := rect.position.x + rect.size.x / 2.0
	# 两行整体要在胶囊里上下居中。早先按 0.42 / 0.72 铺时，30 号数字的上沿会顶穿
	# 边框纹样，底下却空出一截，看着就是「数字没在框里」。
	var cy := rect.position.y + rect.size.y / 2.0
	var gap := value_size * 0.42 + 12.0
	draw_text_centered(ci, cx, cy - gap * 0.5 + value_size * 0.36, value, value_size, value_col, true)
	draw_text_centered(ci, cx, cy + gap * 0.5 + 12.0 * 0.36, label, 12, INK_SOFT)

# ---------- 文本换行 ----------
## 换行结果缓存。`wrap_text` 是逐字符调 `text_width(line + ch)`，长度 n 就是 O(n²)；
## 而顾客小票每帧都要按同一句话、同一个宽度重算一遍，是 play 屏最贵的一段（实测 459us/帧）。
## 键带上全部四个入参，所以任何一项变了都不会命中错的旧结果。
var _wrap_cache := {}
const WRAP_CACHE_MAX := 512

func wrap_text(text: String, max_w: float, size: int = 14, bold: bool = false) -> PackedStringArray:
	var key := "%s|%0.2f|%d|%d" % [text, max_w, size, 1 if bold else 0]
	if _wrap_cache.has(key):
		return _wrap_cache[key]
	var lines := _wrap_uncached(text, max_w, size, bold)
	if _wrap_cache.size() >= WRAP_CACHE_MAX:
		_wrap_cache.clear()
	_wrap_cache[key] = lines
	return lines

func _wrap_uncached(text: String, max_w: float, size: int, bold: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if text_width(line + ch, size, bold) > max_w and line.length() > 0:
			# 避免把连续 ASCII 片段（如 +10%、35%）从中间拆开
			if _is_token_char(ch) and _is_token_char(line.substr(line.length() - 1, 1)):
				var cut := line.length() - 1
				while cut > 0 and _is_token_char(line.substr(cut - 1, 1)):
					cut -= 1
				if cut > 0:
					lines.append(line.substr(0, cut))
					line = line.substr(cut) + ch
					continue
			if _no_break_before(ch) and line.length() > 1:
				# 收尾标点不能单独成行，把前一个字一起挪到下一行
				lines.append(line.substr(0, line.length() - 1))
				line = line.substr(line.length() - 1) + ch
				continue
			lines.append(line)
			line = ch
		else:
			line += ch
	lines.append(line)
	# 孤行控制：末行只剩一两个字（「…第二章预 / 告。」）比首行短得更难看，从上一行拽字补下来
	while lines.size() > 1 and lines[lines.size() - 1].length() < 3 and lines[lines.size() - 2].length() > 3:
		var prev := lines[lines.size() - 2]
		lines[lines.size() - 1] = prev.substr(prev.length() - 1, 1) + lines[lines.size() - 1]
		lines[lines.size() - 2] = prev.substr(0, prev.length() - 1)
	return lines

const TAIL_PUNCT := "。，、；：？！）』」〉…—·%×"

func _no_break_before(ch: String) -> bool:
	return ch.length() == 1 and TAIL_PUNCT.find(ch) >= 0

func _is_token_char(ch: String) -> bool:
	if ch.length() == 0:
		return false
	var c := ch.unicode_at(0)
	if c >= 48 and c <= 57:
		return true  # 0-9
	if c >= 65 and c <= 90:
		return true  # A-Z
	if c >= 97 and c <= 122:
		return true  # a-z
	# 下划线也要算进 token：存档留底的文件名是 save_slot1.corrupt-..._11_22_33.json，
	# 少了 95 就会在 "save_" 后面断行，而那是玩家要照着去找/打的那个名字
	return c == 37 or c == 43 or c == 45 or c == 46 or c == 95 or c == 165  # % + - . _ ¥
