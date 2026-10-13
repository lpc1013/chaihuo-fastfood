class_name PlayLayout
extends RefCounted
## 营业界面的工位布局（PlayLayout）：把"六个工位画在哪、点在哪"从 play.gd 里独立出来。
##
## 审计点名的耦合：以前布局比例、绘制、点击热区三者都长在 play.gd 的 `_draw()` 里，
## 热区在绘制阶段生成、输入逻辑再去读绘制的副产物，于是"背景一改就得同步改代码"。
## 现在布局在这里一次性算成确定的 Rect2，绘制和输入都读同一份结果：
##   - 布局可单独测试（不需要场景节点）；
##   - 换背景/换分辨率只改这里，交互层不动；
##   - 输入不再依赖"上一帧画过什么"。
## `compute()` 是纯函数：同样的视口尺寸 + 布局档，永远给出同样的结果。

## 六个工位各自的位置，量自 v12 背景（tools/bgfit.py + 5% 网格读数校）。
## 顺序 [x, w, y, h]：柴火炉 / 圆形烤网 / 三池炸炉 / 花纹铁板 / 芭蕉叶 / 三连饮料机。
## 虽然是一排，每件高度差仍然很大（炉顶 47.5%、铁板只到 61.5%），共用一条 row_y 会飘。
## ⚠ 相邻两件的 x 区间**必须无缝衔接**（左件 x+w == 右件 x）。以前本表是直接写 x 的，
##   独立量出来时有 0.002~0.005 的重叠：在边界上点击会同时命中两个工位，命中哪个取决于
##   绘制顺序——这正是审计问题 07 说的"热区与背景绑定、边界不确定"。改成由左边界累加得出，
##   几何关系变成"不变量"而不是"靠人手对齐"（smoke 的跨分辨率闸会守着它）。
const BOX_W := [0.185, 0.150, 0.145, 0.162, 0.175, 0.175]
const BOX_X0 := 0.010
## 每件的高度与顶部（纵向不需要无缝，各工位高矮本就不同）
const BOX_YH := [
	[0.475, 0.270],
	[0.585, 0.160],
	[0.505, 0.255],
	[0.615, 0.150],
	[0.575, 0.190],
	[0.465, 0.260],
]
const NAMES := ["fire", "grill", "fryer", "asm", "tray", "drink"]
## 四个柜位（客人站位）的横向比例
const SLOT_X := [0.36, 0.52, 0.68, 0.84]

## 每只炸篮的挂架位与油井位（都是工位格内分数，所以和分辨率无关）。
## 0 号是按底图那只画上去的空篮量的——篮子尺寸也量到同一个宽度，这样"提起来"
## 是同一只篮子回到它本来的姿态，而不是画面里同时出现两只漏勺。
## **加篮子必须同时在这里加一行**：漏了就会有两支篮子画在同一个位置。
## smoke 里有一条闸盯着 `Config.fryer_baskets() <= FRY_GEO.size()`，漏加会当场红。
const FRY_GEO := [
	{"home": Vector2(0.48, 0.41), "well": Vector2(0.58, 0.56)},
]

## 柴堆：库存几根就垒几根，两行错缝。行数按每行 5 根算，wood_max=10 正好两行。
const WOOD_PER_ROW := 5


## 计算整屏布局。`vp` 是视口尺寸（get_viewport_rect().size 的等效值）。
## 返回的字典键与旧 play.ly() 完全一致，调用方（绘制、输入、测试）无需改动。
static func compute(vp: Vector2) -> Dictionary:
	var W := vp.x
	var H := vp.y
	var pad := maxf(6.0, roundf(minf(W, H) * 0.02))
	# 背景 v12 是砖砌台身 + 单排六件：街面 0~44%，台面设备 47%~76%，砖前立面 52%~79%，
	# 木框食材格 82.8%~93.3%（白bin实测只有这一段），底下 96%~100% 是木护栏。
	var scene_h := roundf(H * 0.45)
	var counter_y := roundf(H * 0.44)
	var cust_h := roundf(H * 0.245)
	var k_top := roundf(H * 0.45)
	var row_y := roundf(H * 0.48)
	var row_h := roundf(H * 0.28)
	var shelf_y := roundf(H * 0.828)
	var shelf_h := roundf(H * 0.105)
	var u := W - pad * 2.0
	var rects := {}
	# 工位排：先算出六个**共享的边界像素**（edge[0..6]），再让每件的 x 取 edge[i]、宽度取
	# edge[i+1]-edge[i]。这样无论怎么取整，相邻两件都恰好首尾相接，既不会重叠也不会留缝——
	# 如果分别 roundf(x) 和 roundf(w)，在某些分辨率下 end 会比下一件的 start 多出 1px。
	# 自适应宽度：整排的目标跨度是 BOX_X0 .. BOX_X0+Σw；把它按比例铺满到视口宽度，
	# 并整体右移，保证最后一件不越过右边缘（旧表把 drink 的右界定到 0.995，1280 下已越界）。
	var total_w := 0.0
	for w in BOX_W:
		total_w += float(w)
	var max_right := 1.0 - BOX_X0           # 留出与左侧对称的边距，避免贴边
	var span := minf(total_w, max_right - BOX_X0)
	var edges: Array = []
	for i in range(BOX_W.size() + 1):
		var frac := 0.0
		for j in i:
			frac += float(BOX_W[j])
		edges.append(roundf(W * (BOX_X0 + span * (frac / total_w)))) 
	for i in BOX_W.size():
		var x0 := float(edges[i])
		var x1 := float(edges[i + 1])
		rects[NAMES[i]] = Rect2(x0, roundf(H * float(BOX_YH[i][0])),
			maxf(1.0, x1 - x0), roundf(H * float(BOX_YH[i][1])))
	rects["bench"] = Rect2(pad, row_y, u, row_h)
	var slots: Array = []
	var sw := minf(W * 0.20, 190.0)
	for s in SLOT_X.size():
		slots.append({"x": roundf(W * SLOT_X[s]), "y": counter_y, "w": sw})
	rects["shelf"] = Rect2(pad, shelf_y, u, shelf_h)
	# 四瓶酱料站在设备那一排上方的石质后沿上：v12 从左到右是 街面 0~44% → 台面后沿 47~52%
	# → 砖砌矮墙 52~56% → 工作台面 56~78%。瓶子踩在后沿上往上长，木牌挂在它们下面的砖矮墙上；
	# 左端从 19% 起是给柴堆让开的（柴堆站在炉顶石板上，占 1%~19%），右端收到 50% 免得压到案板格。
	rects["ledge"] = Rect2(roundf(W * 0.19), roundf(H * 0.470), roundf(W * 0.31), roundf(H * 0.052))
	rects["counter_y"] = counter_y
	rects["cust_h"] = cust_h
	rects["head_y"] = counter_y - cust_h
	rects["slots"] = slots
	rects["k_top"] = k_top
	rects["scene_h"] = scene_h
	return rects


## 工位的状态叠加区：设备画在背景图的下半段，状态（进度/高亮）要落在设备身上。
static func cell_zone(rect: Rect2) -> Rect2:
	return Rect2(rect.position.x + 6.0, rect.position.y + rect.size.y * 0.30,
		rect.size.x - 12.0, rect.size.y * 0.60)


## 第 i 只篮子当前的挂架/油井坐标。表比篮子短时退回最后一行——
## 但那种情况 smoke 会先红，不该靠这里兜住。
static func fry_geo(i: int) -> Dictionary:
	if FRY_GEO.is_empty():
		return {"home": Vector2(0.48, 0.41), "well": Vector2(0.58, 0.56)}
	return FRY_GEO[mini(i, FRY_GEO.size() - 1)]
