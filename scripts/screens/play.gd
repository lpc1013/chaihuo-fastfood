extends Node2D
## 营业主界面（Play）：顾客排队与点单、烤架/炸锅/可乐机、组装台、托盘、柴火炉、
## 上餐与结算触发。逻辑取 DaySim，本文件只负责绘制与输入。

var main: Node
var sim: DaySim = null
var paused := false

var _hits: Array = []
var _hover := Vector2(-1, -1)
var cust_x := {}
var popups: Array = []
var board_fx: Array = []
var sauce_fx: Array = []
var drag_ing := ""
var drag_ing_pos := Vector2.ZERO
var slice_travel := 0.0
var snark_text := ""
var snark_t := 0.0
var shake_t := 0.0
var t := 0.0

var drag_tray := false
var drag_moved := false
var drag_pos := Vector2.ZERO
var drag_press := Vector2.ZERO
# 单击托盘＝拿起来吸附在光标上，下一次点击就是落点（不用按住拖）
var tray_sticky := false

var shelf_scroll := 0.0
var shelf_drag := false
var shelf_drag_start := 0.0
var shelf_drag_scroll0 := 0.0
var shelf_drag_moved := false
var shelf_drag_idx := -1

# 炸锅动画：背景那台炸炉的挂架位与井位（工位格内的比例，跟着分辨率走）。
# v12 底图**本身就画了一只空漏勺搁在后沿两池上**，实测它的中心在整屏 (41.5%, 61%)、
# 宽约 10.5% 屏宽。挂架位就按它反推（x=(0.415-0.345)/0.145、y=(0.610-0.505)/0.255），
# 篮子尺寸也量到同一个宽度——这样"提起来"是同一只篮子回到它本来的姿态，
# 而不是画面里同时出现两只漏勺（用户就是指着这个问的）。
const FRY_HOME := Vector2(0.48, 0.41)
const FRY_WELL := Vector2(0.58, 0.56)
var fry_phase := ""
var fry_t := 0.0
var _fry_p_prev := -1.0

# ---------------- 生命周期 ----------------
func on_enter(params: Dictionary) -> void:
	if sim == null or bool(params.get("fresh", false)):
		sim = DaySim.new()
		sim.start(GameState.day)
		_connect_sim()
		paused = false
		if not GameState.tut_done:
			get_tree().create_timer(0.6).timeout.connect(_open_tut_anim)
		snark_text = Config.misc("welcome")
		snark_t = 3.4
		# 酱料瓶是到日子才上台面的，不预告一句就是凭空多出四瓶东西；第 1 天就在的不用报
		if GameState.day == Config.sauce_unlock_day() and GameState.day > 1:
			snark_text = Config.misc("sauces_arrived")
		cust_x.clear()
		popups.clear()
		shelf_scroll = 0.0
		fry_phase = ""
		fry_t = 0.0
		_fry_p_prev = -1.0
		tray_sticky = false
		drag_tray = false
	else:
		# 从中断处恢复（例如从台账返回时保持暂停）
		if paused and not main.has_overlay():
			main.open_overlay(load("res://scripts/components/ov_pause.gd").new())

func _on_chop_done(gained: int, all_hit: bool) -> void:
	if gained > 0:
		sim.apply_chop(gained, all_hit)

func _connect_sim() -> void:
	sim.snark_requested.connect(_on_snark)
	sim.popup_requested.connect(_on_popup)
	sim.sfx_requested.connect(func(n: String): Sfx.play(n))
	sim.shake_requested.connect(func(): shake_t = 0.35)
	sim.day_finished.connect(_on_day_finished)
	sim.menu_notice_requested.connect(_on_menu_notice)

func _on_snark(text: String) -> void:
	snark_text = text
	snark_t = 3.4

## 解锁好消息只走中上方那条飘字（用户定的"获得反馈"样式），不再同时占吐槽条，
## 同一句话说两遍反而像报错。飘字停留时间给足：这是一整句话，不是"+26"。
func _on_menu_notice(text: String) -> void:
	_on_popup(text, DaySim.POPUP_MENU, -1, 2.6)
	Sfx.play("star")

func _on_popup(text: String, color: Color, slot: int, life: float = 1.2) -> void:
	var L := ly()
	var slots: Array = L["slots"]
	var x: float = _vp().x / 2.0 if slot < 0 else float(slots[clampi(slot, 0, slots.size() - 1)].x)
	var min_y := float(L["scene_h"]) * 0.10 + 46.0
	# 同一条竖线上已经飘着几条，新的就往上叠几条——原来全都画在同一个 y，
	# 两条播报撞在一起就是一串糊字（解锁播报和升星提示同一帧发就会撞上）
	var same := 0
	for q in popups:
		if absf(((q as Dictionary).pos as Vector2).x - x) < 46.0:
			same += 1
	var y := maxf(min_y, float(L["head_y"]) + 26.0 - float(same) * 27.0)
	popups.append({
		"pos": Vector2(x, y),
		"text": text, "color": color, "t": life, "min_y": min_y
	})

func _on_day_finished() -> void:
	if main == null or main.current_name != "play":
		return
	get_tree().create_timer(0.9).timeout.connect(_go_day_end)

func _go_day_end() -> void:
	if main == null or main.current_name != "play":
		return
	if main.has_overlay():
		get_tree().create_timer(0.5).timeout.connect(_go_day_end)
		return
	main.goto("day_end", {"stats": sim.settlement_record(), "orders": sim.today_orders})

func is_paused() -> bool:
	return paused or (main != null and main.has_overlay())

func resume_game() -> void:
	paused = false

func restart_tutorial() -> void:
	_open_tut_anim()

## 开场教学动画（可跳过）：放完或跳过后不再打扰
func _open_tut_anim() -> void:
	# 这一句是 0.6 秒后的定时器回调，玩家在这 0.6 秒里离开营业台是常事：
	# 不挡掉就会把教学盖到商店/台账上，把那一屏的点击全吃掉。
	if main == null or main.has_overlay() or str(main.current_name) != "play":
		return
	var ov = load("res://scripts/components/ov_tutorial.gd").new()
	ov.main = main
	ov.on_done = func():
		GameState.tut_done = true
		SaveManager.save_all()
		_on_snark(Config.misc("tut_done"))
	main.open_overlay(ov)

func wood_count() -> int:
	return sim.wood if sim != null else 0

func _process(delta: float) -> void:
	t += delta
	if sim != null and not is_paused() and not sim.finished:
		sim.tick(delta)
	_tick_fry(delta)
	# 盘里那份没了（送出/丢掉）就别再让它吸附在光标上
	if tray_sticky and not sim.tray_has():
		tray_sticky = false
	_update_positions(delta)
	_pick_coins()
	for p in popups.duplicate():
		p.t -= delta
		p.pos.y -= delta * 34.0
		if p.pos.y < float(p["min_y"]):
			p.pos.y = float(p["min_y"])
		if p.t <= 0.0:
			popups.erase(p)
	for f in sauce_fx.duplicate():
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) <= 0.0:
			sauce_fx.erase(f)
	for f in board_fx.duplicate():
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) <= 0.0:
			board_fx.erase(f)
	if snark_t > 0.0:
		snark_t -= delta
	if shake_t > 0.0:
		shake_t -= delta
	queue_redraw()

func _update_positions(delta: float) -> void:
	var slots: Array = ly()["slots"]
	var alive := {}
	for c in sim.queue:
		alive[c] = true
	for c in sim.leaving:
		alive[c] = true
	for c in cust_x.keys():
		if not alive.has(c):
			cust_x.erase(c)
	for c in sim.queue + sim.leaving:
		if not cust_x.has(c):
			cust_x[c] = get_viewport_rect().size.x + 90.0
		var tx: float = slots[clampi(c.slot, 0, 3)].x if c.slot >= 0 else get_viewport_rect().size.x + 90.0
		if c.state == "leaving":
			cust_x[c] = float(cust_x[c]) + delta * float(c.out_dir) * get_viewport_rect().size.x * 0.55
		else:
			cust_x[c] = lerpf(float(cust_x[c]), tx, minf(1.0, delta * 4.0))

func _vp() -> Vector2:
	return get_viewport_rect().size

# ---------------- 布局 ----------------
func ly() -> Dictionary:
	var W := _vp().x
	var H := _vp().y
	var pad := maxf(6.0, roundf(minf(W, H) * 0.02))
	# 背景回退到 v12（用户：扩第二排那一串版本"太差劲"，回到扩建之前那版）。
	# v12 是砖砌台身 + **单排六件**：街面 0~44%，台面设备 47%~76%，砖前立面 52%~79%，
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
	# 六个工位各自的位置，量自 v12 背景（tools/bgfit.py + 5% 网格读数校）。
	# 顺序 [x, w, y, h]：柴火炉 / 圆形烤网 / 三池炸炉 / 花纹铁板 / 芭蕉叶 / 三连饮料机。
	# 虽然是一排，每件高度差仍然很大（炉顶 47.5%、铁板只到 61.5%），共用一条 row_y 会飘。
	var boxes := [
		[0.010, 0.185, 0.475, 0.270],
		[0.195, 0.150, 0.585, 0.160],
		[0.345, 0.145, 0.505, 0.255],
		[0.488, 0.162, 0.615, 0.150],
		[0.650, 0.175, 0.575, 0.190],
		[0.820, 0.175, 0.465, 0.260],
	]
	var names := ["fire", "grill", "fryer", "asm", "tray", "drink"]
	var rects := {}
	for i in 6:
		rects[names[i]] = Rect2(roundf(W * boxes[i][0]), roundf(H * boxes[i][2]),
			roundf(W * boxes[i][1]), roundf(H * boxes[i][3]))
	rects["bench"] = Rect2(pad, row_y, u, row_h)
	var slots: Array = []
	var sw := minf(W * 0.20, 190.0)
	for s in 4:
		slots.append({"x": roundf(W * [0.36, 0.52, 0.68, 0.84][s]), "y": counter_y, "w": sw})
	rects["shelf"] = Rect2(pad, shelf_y, u, shelf_h)
	# 四瓶酱料站在**设备那一排上方的石质后沿**上（用户红框指的那条小平台）：
	# v12 从左到右是 街面 0~44% → 台面后沿 47~52% → 砖砌矮墙 52~56% → 工作台面 56~78%。
	# 瓶子踩在后沿上往上长，木牌挂在它们下面的砖矮墙上；左端从 19% 起是给柴堆让开的
	# （柴堆站在炉顶石板上，占 1%~19%），右端收到 50% 免得压到案板格。
	rects["ledge"] = Rect2(roundf(W * 0.19), roundf(H * 0.470), roundf(W * 0.31), roundf(H * 0.052))
	rects["counter_y"] = counter_y
	rects["cust_h"] = cust_h
	rects["head_y"] = counter_y - cust_h
	rects["slots"] = slots
	rects["k_top"] = k_top
	rects["scene_h"] = scene_h
	return rects

# ---------------- 绘制 ----------------
func _draw() -> void:
	_hits = []
	if sim == null:
		return
	var W := _vp().x
	var H := _vp().y
	var L := ly()
	var t_start := Time.get_ticks_usec()
	var tt := t_start
	_draw_scene(W, H, L)
	tt = _pt("scene", tt)
	_draw_sauces(L)
	tt = _pt("sauces", tt)
	_draw_customers(L)
	tt = _pt("customers", tt)
	_draw_topbar(W, L)
	tt = _pt("topbar", tt)
	var shk := Vector2.ZERO
	if shake_t > 0.0:
		shk = Vector2(sin(shake_t * 40.0) * 4.0, 0)
	draw_set_transform(shk)
	_draw_fire(L["fire"])
	tt = _pt("fire", tt)
	_draw_grill(L["grill"])
	tt = _pt("grill", tt)
	_draw_fryer(L["fryer"])
	tt = _pt("fryer", tt)
	_draw_drink(L["drink"])
	tt = _pt("drink", tt)
	_draw_asm(L["asm"])
	tt = _pt("asm", tt)
	_draw_tray(L["tray"])
	tt = _pt("tray", tt)
	_draw_coins()
	tt = _pt("coins", tt)
	_draw_shelf(L)
	draw_set_transform(Vector2.ZERO)
	tt = _pt("shelf", tt)
	_draw_snark(L)
	_draw_popups(L)
	tt = _pt("overlay_text", tt)
	_draw_hover_tip()
	_draw_drag_ghost()
	if perf_probe:
		perf_acc["total"] = int(perf_acc.get("total", 0)) + (Time.get_ticks_usec() - t_start)
		perf_frames += 1

## 分段计时探针：只在 perf_probe 打开时累加，正常玩的时候每条 _pt 只是一次 bool 判断。
## 之所以要分段而不是只看 fps：soak 报 60fps 只证明"没掉帧"，不证明余量有多少。
var perf_probe := false
var perf_acc := {}
var perf_frames := 0

func _pt(name: String, t0: int) -> int:
	if not perf_probe:
		return t0
	var n := Time.get_ticks_usec()
	perf_acc[name] = int(perf_acc.get(name, 0)) + (n - t0)
	return n

func _draw_scene(_W: float, _H: float, _L: Dictionary) -> void:
	UiKit.draw_tex_box(self, UiKit.art("backgrounds/bg_play_full"), Rect2(0, 0, _W, _H))

func _draw_customers(L: Dictionary) -> void:
	for c in sim.queue:
		if c.slot >= 0 and cust_x.has(c):
			_draw_customer(c, L, 1.0)
	for c in sim.queue:
		if c.slot >= 0 and c.state == "waiting":
			_draw_order_bubble(c, L)
	# 表情要压在小票之上：它原来画在头顶同一带，被小票纸整个盖掉，
	# 顾客催单的怒脸等于从来没露过面
	for c in sim.queue:
		if c.slot >= 0 and cust_x.has(c):
			_draw_mood(c, L, 1.0)
	for c in sim.leaving:
		if cust_x.has(c):
			var alpha := clampf(1.5 - c.out_t, 0.0, 1.0)
			_draw_customer(c, L, alpha)

func _draw_mood(c: Customer, L: Dictionary, alpha: float) -> void:
	var h := float(L["cust_h"])
	var x := float(cust_x[c])
	if c.mood == "angry":
		UiKit.draw_text_centered(self, x + h * 0.34, float(L["counter_y"]) - h * 0.60, "!", int(maxf(16.0, h * 0.19)), Color(0.91, 0.35, 0.29, alpha), true)
	elif c.mood == "happy":
		UiKit.draw_text_centered(self, x + h * 0.34, float(L["counter_y"]) - h * 0.60, "♥", int(maxf(16.0, h * 0.19)), Color(0.23, 0.78, 0.48, alpha), true)

func _draw_customer(c: Customer, L: Dictionary, alpha: float) -> void:
	var h := float(L["cust_h"])
	var x := float(cust_x[c])
	var bob := absf(sin(c.bob)) * h * 0.015
	var col := Color(1, 1, 1, alpha)
	var img_name := str(Config.species(c.sp).get("id", "rabbit"))
	# 接触阴影：让角色“站”在地上（暖色低透明度，双层渐弱）
	var foot_y := float(L["counter_y"]) + 4.0 - bob
	draw_set_transform(Vector2(x, foot_y - 2.0), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, h * 0.24, Color(0.16, 0.11, 0.07, 0.10 * alpha))
	draw_circle(Vector2.ZERO, h * 0.15, Color(0.15, 0.10, 0.06, 0.18 * alpha))
	draw_set_transform(Vector2.ZERO)
	UiKit.draw_sprite(self, UiKit.art("characters/full_" + img_name), x, foot_y, h)

func _draw_order_bubble(c: Customer, L: Dictionary) -> void:
	var items := 1 + (1 if c.order_fries else 0) + (1 if c.order_drink != "" else 0)
	var ic := 52.0
	var say := str(c.say)
	var has_say := say != "" and c.say_t > 0.0
	var say_size := 15
	var say_lines := PackedStringArray()
	# 小票最宽不能超过柜位间距（4 个柜位间隔 = W*0.16），否则相邻两个客人的纸互相压住，
	# 台词正好被隔壁那张盖掉半行
	var gap_x := float(L["slots"][1].x) - float(L["slots"][0].x) - 10.0
	var min_bw := minf(190.0, gap_x)
	# 先靠加宽小票把台词放进一行，实在放不下才折行
	var bw := maxf(items * ic + (items + 1) * 6.0, min_bw)
	if has_say:
		bw = clampf(maxf(bw, UiKit.text_width(say, say_size, true) + 28.0), min_bw, maxf(gap_x, items * ic + (items + 1) * 6.0))
		say_lines = UiKit.wrap_text(say, bw - 24.0, say_size)
		# 三行纸会把顾客整张脸盖掉，宁可字号掉一档换两行
		while say_size > 13 and say_lines.size() > 2:
			say_size -= 1
			say_lines = UiKit.wrap_text(say, bw - 24.0, say_size)
	var say_h := float(say_size) * 1.35 * float(maxi(say_lines.size(), 1)) if has_say else 0.0
	# 点单小票与催单台词合并成一张纸：两块浮层在头顶必然互相压字
	var bh := 6.0 + ic + say_h + 22.0
	var slot_x := float(cust_x[c]) if cust_x.has(c) else float(L["slots"][clampi(c.slot, 0, 3)].x)
	var bx := clampf(slot_x - bw / 2.0, 6.0, _vp().x - bw - 6.0)
	# 右上角那排圆钮占 x>870、y<62：纸在左边时不必硬停在 66，可以贴更高、少盖脸
	var top_lim := 66.0 if bx + bw > _vp().x - 410.0 else 12.0
	var by := maxf(top_lim, float(L["head_y"]) - bh - 4.0)
	UiKit.draw_tex_box(self, UiKit.art("ui/ticket_paper"), Rect2(bx, by, bw, bh))
	var ix := bx + (bw - (items * ic + (items - 1) * 6.0)) / 2.0
	for tex in [UiKit.icon_burger(c.order_burger)] + ([UiKit.icon_food("fries")] if c.order_fries else []) + ([UiKit.drink_icon(c.order_drink)] if c.order_drink != "" else []):
		UiKit.draw_tex_contain(self, tex, Rect2(ix, by + 6, ic, ic))
		ix += ic + 6.0
	for li in say_lines.size():
		UiKit.draw_text_centered(self, bx + bw / 2.0, by + 6.0 + ic + say_size * (1.15 + 1.35 * float(li)),
			say_lines[li], say_size, Color("#5a4a3a"), true)
	# 耐心条
	var frac := c.patience_frac()
	var col := Color("#3ac77a") if frac > 0.5 else (Color("#f8a93c") if frac > 0.25 else Color("#e85a4a"))
	var pb := Rect2(bx + 10, by + bh - 18, bw - 20, 12)
	UiKit.draw_tex_box(self, UiKit.art("ui/bar_track"), pb)
	UiKit.draw_tex_box(self, UiKit.art("ui/bar_fill"), Rect2(pb.position.x + 3, pb.position.y + 3, (pb.size.x - 6) * frac, 6), col)
	# 高亮：当前目标 or 托盘可上餐
	if sim.target >= 0 and sim.target < sim.queue.size() and sim.queue[sim.target] == c:
		UiKit.draw_focus(self, Rect2(bx - 8, by - 8, bw + 16, bh + 16), Color(1, 0.9, 0.62, 0.95))
	elif sim.tray_has_for(c):
		var gp := 0.5 + 0.5 * sin(t * 5.0)
		UiKit.draw_focus(self, Rect2(bx - 8, by - 8, bw + 16, bh + 16), Color(0.5, 1.0, 0.72, 0.45 + 0.5 * gp))
	_hits.append({"rect": Rect2(bx, by - 6, bw, bh + 18), "id": "cust", "c": c})

func _draw_topbar(W: float, _L: Dictionary) -> void:
	# 参考版式：HUD 悬浮在场景上，左上圆形头像框 + 名字 + 金币药丸 + 声望星，右上排圆木按钮
	var r := maxf(26.0, _vp().y * 0.062)
	var ac := Vector2(r + 14.0, r + 12.0)
	draw_circle(ac, r + 5.0, Color(0.16, 0.11, 0.07, 0.55))
	# 头像必须圆裁，而且脸心要对上圆心：avatar_chef 的狗头压在画布右下 2/3、左上整块是空的，
	# 按短边居中裁就会把脸甩到圆框的右下方。焦点和缩放逐张量在 UiKit.PORTRAIT_HEAD 里。
	UiKit.draw_portrait(self, UiKit.art("characters/avatar_chef"), ac, r + 4.0)
	var nx := ac.x + r + 12.0
	# 天数/出餐这一条挪到名字**上方**，名字→金币→星往下排，左侧一列读起来是"哪天—谁—多少钱—口碑"
	var day := "第%d天 · 已出餐 %d/%d" % [GameState.day, sim.served, sim.total_plan()]
	var dw := UiKit.text_width(day, 15, true) + 28.0
	var dp := Rect2(nx - 6, maxf(4.0, ac.y - r * 0.5 - 27.0), dw, 26.0)
	UiKit.draw_tex_box(self, UiKit.art("ui/chip"), dp)
	UiKit.draw_text_in(self, dp, day, 15, Color("#5a3f26"), true)
	UiKit.draw_text(self, Vector2(nx, ac.y - r * 0.16), "老柴", 18, Color("#fff3dd"), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	# 宽度按字量：以前写死 124px，而 coins_fmt 是用户可以在 user://config 里改的
	# （使用说明里就教人改 JSON），格式一长或者钱上到六七位，字就会骑出药丸右边。
	var coin_txt := Config.ui("coins_fmt") % GameState.coins
	var pill := Rect2(nx, ac.y + 2.0, maxf(124.0, UiKit.text_width(coin_txt, 16, true) + 24.0), r * 0.92)
	UiKit.draw_tex_box(self, UiKit.art("ui/chip"), pill)
	UiKit.draw_text_in(self, pill, coin_txt, 16, Color("#8a4a12"), true)
	for i in 5:
		var filled := i < GameState.rep_stars()
		UiKit.draw_text(self, Vector2(nx + 2.0 + i * 19.0, pill.end.y + 18.0),
			"★" if filled else "☆", 16, UiKit.GOLD if filled else Color(0.48, 0.42, 0.36))
	# 星条挂一条悬停说明：声望同时挂小费和菜品解锁，不写出来玩家只会看到钱忽多忽少
	_hits.append({"rect": Rect2(nx - 2.0, pill.end.y + 2.0, 5 * 19.0 + 12.0, 20.0), "id": "rep"})
	var br := maxf(21.0, _vp().y * 0.042)
	var bcy := br + 2.0
	# 圆木按钮上的图形全用即梦产的图标，静音时在音符上补一道斜杠
	# 「倒掉」用灶膛那团火：这一枚的动作就是把做坏的那份丢回炉子里
	var icons: Array = ["kitchen/flame", "ui/ic_truck", "ui/ic_book", "ui/ic_pause", "ui/ic_ledger", "ui/ic_sound"]
	var ids: Array = ["bin", "truck", "menu", "pause", "records", "sound"]
	for i in ids.size():
		var cx := W - 22.0 - br - float(i) * (br * 2.0 + 8.0)
		var rc := Rect2(cx - br, bcy - br, br * 2.0, br * 2.0)
		var id := str(ids[ids.size() - 1 - i])
		var full := id == "bin" and sim != null and sim.tray_has()
		UiKit.draw_tex_contain(self, UiKit.art("ui/button_round"), rc)
		UiKit.draw_tex_contain(self, UiKit.art(icons[icons.size() - 1 - i]),
			Rect2(cx - br * 0.56, bcy - br * 0.56, br * 1.12, br * 1.12),
			Color(1, 1, 1, 0.42) if (id == "bin" and not full) else Color.WHITE)
		if id == "sound" and GameState.muted:
			UiKit.draw_tex_box(self, UiKit.art("ui/bar_fill"),
				Rect2(cx - br * 0.52, bcy + br * 0.10, br * 1.04, br * 0.19), Color("#c2492f"))
		if full:
			var bp := 0.5 + 0.5 * sin(t * 4.5)
			UiKit.draw_focus(self, rc.grow(4.0), Color(1.0, 0.88, 0.55, 0.35 + 0.4 * bp))
		_hits.append({"rect": rc, "id": id})

# ---------------- 柴火炉 ----------------
func _draw_fire(rect: Rect2) -> void:
	var zone := _cell_zone(rect)
	var cx := rect.position.x + rect.size.x / 2.0
	var intensity := clampf(sim.fire / float(Config.fire.get("fire_max", 100.0)), 0.0, 1.0)
	var low := sim.fire_low()
	_draw_flame(Vector2(cx, zone.position.y + zone.size.y * 0.44), rect.size.x * 0.22, intensity, low)
	# 拖着或提着托盘时炉口就是垃圾桶：整圈高亮 + 一句话，不然没人知道能往这儿丢
	if _carrying():
		var gpd := 0.5 + 0.5 * sin(t * 6.0)
		UiKit.draw_focus(self, Rect2(zone.position.x + 10.0, zone.position.y + zone.size.y * 0.10,
			zone.size.x - 20.0, zone.size.y * 0.72), Color(1.0, 0.74, 0.34, 0.5 + 0.45 * gpd))
		var lbl := Config.misc("dump_hint")
		var hw := UiKit.text_width(lbl, 15, true) + 28.0
		UiKit.draw_tex_box(self, UiKit.art("ui/chip"), Rect2(cx - hw / 2.0, zone.position.y - 34.0, hw, 26.0))
		UiKit.draw_text_centered(self, cx, zone.position.y - 15.0, lbl, 15, Color("#5a3f26"), true)
	# 火候条压在炉脚：以前挂在 zone 的 0.52，正好横切过火焰和背景炉膛里那堆柴，像一道栅栏
	var bar := Rect2(rect.position.x + 12.0, rect.end.y - 13.0, rect.size.x * 0.46, 9.0)
	UiKit.draw_tex_box(self, UiKit.art("ui/bar_track"), bar)
	var fcol := UiKit.EMBER if not low else Color("#e0503a")
	UiKit.draw_tex_box(self, UiKit.art("ui/bar_fill"),
		Rect2(bar.position.x + 3, bar.position.y + 2, (bar.size.x - 6.0) * intensity, bar.size.y - 4), fcol)
	# 库存用真柴堆表达：有几根画几根，不写数字（和食材架"多摆几个"是同一条原则）
	_draw_wood_pile(rect)
	# 两个动作换成图形圆钮，字全部退到悬停提示里 —— 这一带画面上不再出现文字。
	# 半径按格子宽反推，且要和 HUD 那排圆钮差不多大，否则去掉文字之后图形根本读不出来。
	var br := maxf(20.0, rect.size.x * 0.122)
	var bcy := rect.end.y - br - 4.0
	var bx2 := rect.end.x - br - 4.0
	_rbtn(Vector2(bx2, bcy), br, ["fx/axe"], "fire_chop", true)
	_rbtn(Vector2(bx2 - br * 2.0 - 7.0, bcy), br, ["fx/log", "kitchen/flame"], "fire_add", sim.wood > 0)

func _draw_flame(center: Vector2, size: float, intensity: float, low: bool) -> void:
	if intensity <= 0.02:
		UiKit.draw_sprite(self, UiKit.art("kitchen/flame"), center.x, center.y + size * 0.3, size * 0.42, Color(0.42, 0.36, 0.32, 0.55))
		return
	var flick := 1.0 + 0.07 * sin(t * 9.0) + 0.04 * sin(t * 21.0)
	var h := size * (0.9 + 0.75 * intensity) * flick
	var tint := Color(1, 1, 1, 1.0) if not low else Color(0.86, 0.62, 0.55, 0.92)
	UiKit.draw_sprite(self, UiKit.art("kitchen/flame"), center.x, center.y + size * 0.34, h, tint)

## 柴堆：库存几根就垒几根，两行错缝（和食材架"多摆几个表达库存"同一条原则，不留数字角标）。
## 行数按每行 5 根算，wood_max=10 正好两行。
func _draw_wood_pile(rect: Rect2) -> void:
	var tex := UiKit.art("fx/log")
	if tex == null:
		return
	var per := 5
	var lw := minf(rect.size.x * 0.135, 30.0)
	var lh := lw * 0.40
	var x0 := rect.position.x + rect.size.x * 0.05
	# 石板在炉拱正上方（格顶往下约 15%）。柴堆垒那儿，炉脚那条带子才腾得出来放
	# 火候条和两枚圆钮——以前三样全挤在炉体下沿的砖面上，谁都读不出来。
	var base_y := rect.position.y + rect.size.y * 0.155
	for i in sim.wood:
		var row := int(i / per)
		var col := int(i % per)
		var off := lw * 0.32 if row % 2 == 1 else 0.0
		UiKit.draw_tex_contain(self, tex, Rect2(
			x0 + float(col) * lw * 0.88 + off,
			base_y - float(row + 1) * (lh + 1.0), lw, lh))

## 图形圆钮：ui/button_round 上压一到两个现成图形，读法交给悬停提示。
func _rbtn(center: Vector2, r: float, glyphs: Array, id: String, enabled: bool) -> void:
	var rc := Rect2(center.x - r, center.y - r, r * 2.0, r * 2.0)
	var tint := Color.WHITE if enabled else Color(0.60, 0.56, 0.53, 0.82)
	UiKit.draw_tex_contain(self, UiKit.art("ui/button_round"), rc, tint)
	var g := Rect2(center.x - r * 0.60, center.y - r * 0.60, r * 1.20, r * 1.20)
	if glyphs.size() > 1:
		# 添柴＝柴块压在火口上：两个图形叠起来才读得出"往炉子里塞"
		UiKit.draw_tex_contain(self, UiKit.art(str(glyphs[1])),
			Rect2(g.position.x, g.position.y + g.size.y * 0.40, g.size.x, g.size.y * 0.60), tint)
		UiKit.draw_tex_contain(self, UiKit.art(str(glyphs[0])),
			Rect2(g.position.x, g.position.y, g.size.x, g.size.y * 0.62), tint)
	else:
		UiKit.draw_tex_contain(self, UiKit.art(str(glyphs[0])), g, tint)
	_hits.append({"rect": rc, "id": id})


func _cell_zone(rect: Rect2) -> Rect2:
	# 设备画在背景图的下半段，状态叠加层要落在设备身上
	return Rect2(rect.position.x + 6.0, rect.position.y + rect.size.y * 0.30, rect.size.x - 12.0, rect.size.y * 0.60)


func _progress_bar(rect: Rect2, frac: float, win_a: float, win_b: float, _color: Color) -> void:
	var bh := maxf(12.0, rect.size.y * 0.062)
	var bx := rect.position.x + 8.0
	var bw := rect.size.x - 16.0
	# 贴在设备正下方，不要飘在设备上方的砖墙上
	var by := rect.end.y - bh - 3.0
	UiKit.draw_tex_box(self, UiKit.art("ui/bar_track"), Rect2(bx, by, bw, bh))
	if win_b > win_a:
		var pad := bw * 0.06
		UiKit.draw_tex_box(self, UiKit.art("ui/bar_fill"),
			Rect2(bx + pad + (bw - pad * 2.0) * win_a, by + bh * 0.30, (bw - pad * 2.0) * (win_b - win_a), bh * 0.40),
			Color(1, 1, 1, 0.42))
	if frac >= 0.0:
		var pad2 := bw * 0.07
		UiKit.draw_tex_box(self, UiKit.art("ui/bar_fill"),
			Rect2(bx + pad2, by + bh * 0.18, (bw - pad2 * 2.0) * clampf(frac, 0.0, 1.0), bh * 0.64))

func _draw_grill(rect: Rect2) -> void:
	var zone := _cell_zone(rect)
	var n := sim.grill.size()
	var slot_gap := 8.0
	var sw := (zone.size.x - slot_gap * float(n - 1)) / float(n)
	for i in n:
		var sx := zone.position.x + i * (sw + slot_gap)
		var slot := Rect2(sx, zone.position.y + 4.0, sw, zone.size.y - 18.0)
		var g: Dictionary = sim.grill[i]
		var cx := slot.position.x + slot.size.x / 2.0
		var cy := slot.position.y + slot.size.y * 0.46
		var pr := minf(slot.size.x, slot.size.y) * 0.30
		var p := float(g["p"])
		var ph := pr * 2.6
		if p >= 0.0:
			UiKit.draw_sprite(self, UiKit.patty_tex(p), cx, cy + ph * 0.66, ph)
			var win: Array = Config.cook("grill").get("window", [0.78, 1.02])
			if p >= float(win[0]) and p <= float(win[1]):
				var gp := 0.5 + 0.5 * sin(t * 8.0)
				UiKit.draw_ring(self, Vector2(cx, cy), ph * 0.5, Color(1.0, 0.82, 0.24, 0.45 + 0.4 * gp), 3.0)
		else:
			# 空格子的虚影：0.13 在黑色烤网上根本看不见，升级成 3 眼之后尤其要能数出位置
			UiKit.draw_sprite(self, UiKit.art("ingredients/pt_raw"), cx, cy + ph * 0.45, ph * 0.86, Color(1, 1, 1, 0.26))
		_hits.append({"rect": slot.grow(6.0), "id": "grill", "i": i})
	var p0 := -1.0
	for g in sim.grill:
		if float(g["p"]) >= 0.0:
			p0 = float(g["p"])
			break
	var win2: Array = Config.cook("grill").get("window", [0.78, 1.02])
	_progress_bar(rect, p0, float(win2[0]), float(win2[1]), Color("#e8963c"))


func _draw_fryer(rect: Rect2) -> void:
	var p := float(sim.fryer["p"])
	var win: Array = Config.cook("fryer").get("window", [0.72, 1.0])
	# 篮子在「挂架」和「油井」之间的插值位置：0=挂在后沿（背景那个姿态），1=沉进前右井
	var k := _fry_k()
	var home := _fry_at(rect, FRY_HOME)
	var well := _fry_at(rect, FRY_WELL)
	var burning := fry_phase == "burn"
	var shake := 0.0
	if fry_phase == "up" or burning:
		# 提起来中段抖两下沥油
		var s := clampf((fry_t - 0.22) / 0.34, 0.0, 1.0)
		shake = sin(s * PI * 3.0) * rect.size.x * 0.045 * (1.0 - s)
	var bp := home.lerp(well, k) + Vector2(shake, 0.0)
	var tint := Color(0.40, 0.30, 0.24, 1.0) if burning else (
		Color(0.90, 0.92, 0.95, 1.0) if (p >= 0.0 and p < float(win[0])) else Color(1, 1, 1, 1.0))
	var bsz := rect.size.x * 0.70
	# 井口的油面：篮子沉进去时压在篮子之上，才读得出「在油里」而不是「浮在机器前面」
	var oil := Rect2(well.x - rect.size.x * 0.24, well.y + bsz * 0.16, rect.size.x * 0.48, bsz * 0.16)
	if k > 0.02:
		UiKit.draw_tex_box(self, UiKit.art("ui/bar_track"), oil, Color(0.30, 0.24, 0.16, 0.62 * k))
		# 浸油时冒泡：用 t 做确定性排布，省一套粒子
		if k > 0.86 and not burning:
			for bi in 7:
				var ph := t * 2.4 + float(bi) * 0.9
				var frac := fmod(ph, 1.0)
				draw_circle(Vector2(oil.position.x + oil.size.x * (0.10 + 0.145 * float(bi % 6)),
					oil.position.y + oil.size.y * (1.0 - frac)),
					(2.4 + float(bi % 3)) * (1.0 - frac), Color(0.99, 0.93, 0.74, 0.55 * (1.0 - frac)))
	# 空闲（锅里没东西、也不在放/捞的动画里）就根本不画我们这只：
	# pr_basket 是「一篮薯条」，凭空挂在炸炉上就是玩家看到的第二只漏勺。
	if p >= 0.0 or fry_phase != "":
		UiKit.draw_tex_contain(self, UiKit.art("kitchen/pr_basket"),
			Rect2(bp.x - bsz / 2.0, bp.y - bsz * 0.42, bsz, bsz * 0.84), tint)
	# 提起/糊了时甩出的油珠：落在井口里
	if (fry_phase == "up" or burning) and fry_t > 0.24 and fry_t < 0.60:
		for di in 5:
			var dp := clampf((fry_t - 0.24 - float(di) * 0.045) / 0.22, 0.0, 1.0)
			if dp <= 0.0 or dp >= 1.0:
				continue
			draw_circle(Vector2(bp.x + rect.size.x * (0.06 * float(di) - 0.12),
				bp.y + bsz * 0.30 + dp * (well.y - bp.y + bsz * 0.2)),
				3.0 * (1.0 - dp * 0.5), Color(0.93, 0.79, 0.42, 0.8))
	if burning:
		for si in 3:
			var sp := clampf((fry_t - 0.10 - float(si) * 0.12) / 0.55, 0.0, 1.0)
			if sp > 0.0:
				draw_circle(Vector2(bp.x + rect.size.x * 0.05 * float(si - 1), bp.y - bsz * (0.20 + sp * 0.55)),
					bsz * (0.07 + sp * 0.13), Color(0.34, 0.32, 0.33, 0.42 * (1.0 - sp)))
	if p >= 0.0 and p >= float(win[0]) and p <= float(win[1]):
		var gp := 0.5 + 0.5 * sin(t * 8.0)
		UiKit.draw_focus(self, Rect2(well.x - rect.size.x * 0.30, well.y - bsz * 0.40, rect.size.x * 0.60, bsz * 0.80),
			Color(1, 0.9, 0.6, 0.45 + 0.45 * gp))
	_progress_bar(rect, p, float(win[0]), float(win[1]), Color("#ffd23c"))
	_hits.append({"rect": rect, "id": "fryer"})

## 篮子当前位置在挂架(HOME)与油井(WELL)之间的比例：0 挂著、1 沉下去
func _fry_k() -> float:
	match fry_phase:
		"down":
			var d := clampf(fry_t / 0.30, 0.0, 1.0)
			return d * d * (3.0 - 2.0 * d)
		"up", "burn":
			var u := clampf(fry_t / 0.62, 0.0, 1.0)
			return 1.0 - u * u * (3.0 - 2.0 * u)
	return 1.0 if (sim != null and float(sim.fryer["p"]) >= 0.0) else 0.0

func _fry_at(rect: Rect2, f: Vector2) -> Vector2:
	return Vector2(rect.position.x + f.x * rect.size.x, rect.position.y + f.y * rect.size.y)

## 模拟层只管逻辑，下篮/提篮这些动画状态全在视图层，靠 fryer.p 的跳变驱动
func _tick_fry(delta: float) -> void:
	if sim == null:
		return
	var burn_at := float(Config.cook("fryer").get("burn_tap", 1.22))
	var fp := float(sim.fryer["p"])
	if _fry_p_prev < 0.0 and fp >= 0.0:
		fry_phase = "down"
		fry_t = 0.0
		Sfx.play("sizzle")
	elif _fry_p_prev >= 0.0 and fp < 0.0:
		if _fry_p_prev >= burn_at:
			fry_phase = "burn"
		elif bool(sim.tray["fries"]):
			fry_phase = "up"
		else:
			fry_phase = ""
		fry_t = 0.0
	_fry_p_prev = fp
	if fry_phase == "":
		return
	fry_t += delta
	if fry_t >= (0.34 if fry_phase == "down" else 0.95):
		fry_phase = ""

func _draw_drink(rect: Rect2) -> void:
	var zone := _cell_zone(rect)
	var cx := zone.position.x + zone.size.x / 2.0
	# 饮料机整台用独立素材放大盖在背景机器上
	var mach := UiKit.art("kitchen/pr_machine")
	var mh := _vp().y * 0.40
	var mb := zone.end.y + 6.0
	var asp := 0.84
	if mach != null and mach.get_size().y > 0.0:
		asp = mach.get_size().x / mach.get_size().y
	var mw := mh * asp
	var mtop := mb - mh
	UiKit.draw_sprite(self, mach, cx, mb, mh)
	var defs: Array = Config.drinks()
	var n := maxi(defs.size(), 1)
	var colw := mw / float(n)
	var p := float(sim.drink["p"])
	var win: Array = Config.cook("drink").get("window", [0.62, 0.95])
	var sel := clampi(int(sim.drink_jar), 0, n - 1)
	# 一整根柱子（罐体＋龙头＋杯位）都是热区；原来只有龙头上 40×40，画面里根本找不到
	for i in n:
		var colx := cx - mw / 2.0 + colw * (float(i) + 0.5)
		var on := i == sel
		if on:
			var gp := 0.5 + 0.5 * sin(t * 4.0)
			UiKit.draw_focus(self, Rect2(colx - colw * 0.47, mtop + mh * 0.02, colw * 0.94, mh * 0.44),
				Color(1.0, 0.92, 0.62, 0.5 + 0.4 * gp))
		var nm := str(defs[i].get("name", ""))
		var tsz := 15
		var tw := UiKit.text_width(nm, tsz, true) + 18.0
		var th2 := tw * 0.40
		var ty := mtop + mh * 0.60
		# 机器右边是出血到画外的，最右那格的标签要夹回视口里，否则「柠檬茶」被切掉半截
		var tx := clampf(colx - tw / 2.0, 4.0, _vp().x - tw - 4.0)
		UiKit.draw_tex_box(self, UiKit.art("ui/tag"), Rect2(tx, ty, tw, th2))
		UiKit.draw_text_centered(self, tx + tw / 2.0, ty + th2 * 0.70, nm, tsz,
			Color("#4a3524") if on else Color("#6f5c49"), true)
		_hits.append({"rect": Rect2(colx - colw / 2.0, mtop + mh * 0.03, colw, mh * 0.86),
			"id": "drink", "jar": i})
	# 杯子位置跟着选中的那根柱子走，机器底部本来就是三个杯位；
	# 只让"可见的部分"从下往上长：整张杯子按液位裁切显示，
	# 空杯用同一张素材的淡虚影占位（透明杯单独抠会透出绿幕，所以不复用它）
	var ch := zone.size.y * 0.62
	var cup_x := cx - mw / 2.0 + colw * (float(sel) + 0.5)
	var cup := Rect2(cup_x - ch * 0.31, zone.end.y - ch, ch * 0.62, ch)
	var pour_id := str(Config.drink_def(sel).get("id", "cola"))
	var cup_tex := UiKit.drink_icon(pour_id)
	if cup_tex != null:
		UiKit.draw_sprite(self, cup_tex, cup.position.x + cup.size.x / 2.0, cup.end.y, ch, Color(1, 1, 1, 0.20))
		if p >= 0.0:
			var cs := cup_tex.get_size()
			var f := clampf(p, 0.0, 1.0)
			draw_texture_rect_region(cup_tex,
				Rect2(cup.position.x, cup.end.y - cup.size.y * f, cup.size.x, cup.size.y * f),
				Rect2(0, cs.y * (1.0 - f), cs.x, cs.y * f))
			if p >= float(win[0]) and p <= float(win[1]):
				var gp2 := 0.5 + 0.5 * sin(t * 8.0)
				UiKit.draw_focus(self, Rect2(cup.position.x - 8, cup.position.y - 8, cup.size.x + 16, cup.size.y + 16),
					Color(1, 0.9, 0.6, 0.5 + 0.45 * gp2))
	_progress_bar(rect, p, float(win[0]), float(win[1]), Color("#e85a4a"))

func _draw_asm(rect: Rect2) -> void:
	var zone := _cell_zone(rect)
	var cx := zone.position.x + zone.size.x / 2.0
	var base_y := zone.end.y - 4.0
	var n := sim.assembly.size()
	var b_ing := str(sim.board["ing"])
	# 整摞（连案板上那块一起算）必须长在工位格里：层数越多每层越小。
	# 写死 108px 的话，双层至尊堡叠到第 6、7 层就顶穿柜台压到街上去了。
	var layers := n + (1 if b_ing != "" else 0)
	# 净空从堆底量到柜台那条白边：v12 背景里再往上就是街面。
	# 早先这笔预算写的是 rect.size.y * 0.85，可 v12 的 asm 格本身只有 108px 高，
	# 回退 v12 之后预算跟着缩掉——案板上单摆一块食材都只剩 73px，
	# 层数惩罚全打在根本没东西的空档上。
	var room := maxf(70.0, base_y - _vp().y * 0.514)
	var ih := minf(_vp().y * 0.150, room / (1.0 + 0.26 * float(maxi(layers - 1, 0))))
	var step := ih * 0.26
	for ai in n:
		UiKit.draw_sprite(self, UiKit.icon_ingredient(str(sim.assembly[ai])), cx, base_y - float(ai) * step, ih)
	if b_ing != "":
		var need := int(sim.board["need"])
		var cuts := int(sim.board["cuts"])
		var by := base_y - float(n) * step
		# 背景里这块是黑色铁板，不铺一层案板素材根本看不出是切菜的地方
		UiKit.draw_sprite(self, UiKit.art("kitchen/dev_board"), cx, by, ih * 0.78)
		UiKit.draw_sprite(self, UiKit.icon_ingredient(b_ing), cx, by - ih * 0.10, ih)
		# 案板和面包胚是同一个色系，光看形状会以为那块木板是叠上去的一片面包。
		# 架一把现成的 fx/knife 在食材上沿，"正在切"这件事就不用猜了
		UiKit.draw_sprite(self, UiKit.art("fx/knife"), cx + ih * 0.20, by - ih * 0.86, ih * 0.46)
		for k in cuts:
			var lx := cx - ih * 0.24 + float(k) * ih * 0.24
			draw_line(Vector2(lx, by - ih * 0.82), Vector2(lx + 3.0, by - ih * 0.08), Color(1.0, 0.97, 0.90, 0.85), 2.0)
		# 切菜进度和烤架/炸锅/饮料机共用同一条基准（设备正下方那排），
		# 以前画在案板上方，看着像半根木棍悬在砖墙上
		_progress_bar(rect, float(cuts) / float(maxi(need, 1)), 0.0, 0.0, Color("#ffd23c"))

	for f in board_fx:
		var a := clampf(float(f["t"]) / 0.26, 0.0, 1.0)
		var sx := float(f["x"])
		var sy := float(f["y"])
		draw_line(Vector2(sx - 30, sy - 16), Vector2(sx + 30, sy + 14), Color(1.0, 0.97, 0.88, a), 3.0)
		draw_line(Vector2(sx - 22, sy - 26), Vector2(sx + 34, sy + 2), Color(1.0, 0.85, 0.45, a * 0.65), 2.0)
	_hits.append({"rect": rect, "id": "asm"})

func _draw_tray(rect: Rect2) -> void:
	var zone := _cell_zone(rect)
	var ih := float((_shelf_metrics(ly())["cell"] as float)) * 0.80
	var cx := zone.position.x + zone.size.x / 2.0
	var base_y := zone.end.y - 2.0
	var b := int(sim.tray["burger"])
	if b >= 0:
		UiKit.draw_sprite(self, UiKit.icon_burger(b), cx, base_y, ih * 1.15)
	if bool(sim.tray["fries"]):
		UiKit.draw_sprite(self, UiKit.icon_food("fries"), zone.position.x + ih * 0.40, base_y, ih * 0.80)
	if str(sim.tray["drink"]) != "":
		UiKit.draw_sprite(self, UiKit.drink_icon(str(sim.tray["drink"])), zone.end.x - ih * 0.40, base_y, ih * 0.86)
	if b >= 0 or bool(sim.tray["fries"]) or str(sim.tray["drink"]) != "":
		var gp := 0.5 + 0.5 * sin(t * 4.0)
		UiKit.draw_focus(self, Rect2(rect.position.x + 2, rect.position.y + 2, rect.size.x - 4, rect.size.y - 4),
			Color(0.55, 1.0, 0.72, 0.2 + 0.35 * gp))
	_hits.append({"rect": rect, "id": "tray"})

## 结算抛到台面上的硬币：先抛物线飞一段，落定后等鼠标划过拾取。
## 收币人（sim.sweeper_t >= 0）画在硬币**下面**，让他先走进来、硬币仍然看得见。
func _draw_coins() -> void:
	if sim == null or (sim.coins.is_empty() and sim.sweeper_t < 0.0):
		return
	var W := _vp().x
	var H := _vp().y
	var cc := Config.coins_cfg()
	if sim.sweeper_t >= 0.0:
		var walk_in := maxf(0.2, float(cc.get("sweep_walk", 1.2)))
		var kw := clampf(sim.sweeper_t / walk_in, 0.0, 1.0)
		var sh := H * 0.30
		# 他和排队客人同一条脚线（站在柜台外侧的马路上），手伸向台面那条石板带。
		# 画在硬币之前，所以钱始终压在他身上、不会被挡。
		var sx := lerpf(W * 1.12, W * 0.60, kw)
		var feet := H * 0.465
		UiKit.draw_sprite(self, UiKit.art("characters/cust_bear"), sx, feet, sh,
			Color(0.26, 0.22, 0.32, 0.96))
		# 已经装进兜里的钱堆在他脚边：看得见"他拿了多厚一摞"，才有点击的动力
		var gv2 := maxf(1.0, float(cc.get("gold_value", 10)))
		var piled := mini(int(float(sim.sweeper_taken) / gv2) + (1 if fmod(float(sim.sweeper_taken), gv2) > 0.0 else 0), 8)
		for pi in piled:
			UiKit.draw_tex_contain(self, UiKit.art("fx/coin_gold"), Rect2(
				sx - sh * 0.26 + float(pi % 4) * 14.0, feet - 16.0 - float(pi / 4) * 13.0, 16.0, 16.0))
		_hits.append({"rect": Rect2(sx - sh * 0.30, feet - sh, sh * 0.60, sh), "id": "sweeper"})
	if sim.coins.is_empty():
		return
	var toss := maxf(0.05, float(cc.get("toss_seconds", 0.5)))
	var sz := maxf(12.0, float(cc.get("coin_size", 30.0)) * (H / 720.0))
	var gv := maxi(2, int(cc.get("gold_value", 10)))
	for c in sim.coins:
		var cd: Dictionary = c
		var tx := float(cd["x"]) * W
		var ty := float(cd["y"]) * H
		var t := float(cd["t"])
		if t < toss:
			var f := clampf(t / toss, 0.0, 1.0)
			tx = lerpf(float(cc.get("anchor_x", 0.52)) * W, tx, f)
			ty -= sin(f * PI) * H * 0.15
		# 银币在浅色石面上会糊成一片，垫一圈接触阴影才读得出是一枚硬币
		draw_circle(Vector2(tx, ty + sz * 0.30), sz * 0.44, Color(0.10, 0.07, 0.05, 0.28))
		UiKit.draw_tex_contain(self,
			UiKit.art("fx/coin_gold" if int(cd["v"]) >= gv else "fx/coin_silver"),
			Rect2(tx - sz / 2.0, ty - sz / 2.0, sz, sz))

## 鼠标划过就拾取（用户定的规则：拾到才算钱）。倒着遍历，因为 pick_coin 会删元素。
func _pick_coins() -> void:
	if sim == null or sim.coins.is_empty() or is_paused() or _hover.x < 0.0:
		return
	var W := _vp().x
	var H := _vp().y
	var r := maxf(8.0, float(Config.coins_cfg().get("pickup_radius", 20)) * (H / 720.0))
	var i := sim.coins.size() - 1
	while i >= 0:
		var cd: Dictionary = sim.coins[i]
		var p := Vector2(float(cd["x"]) * W, float(cd["y"]) * H)
		if _hover.distance_to(p) <= r:
			var v := sim.pick_coin(i)
			if v > 0:
				_popup_at(p, "+%d" % v, DaySim.POPUP_GOLD)
		i -= 1

## 在指定位置冒一条飘字（+_on_popup 按客人站位排，硬币要就地冒）。
func _popup_at(pos: Vector2, text: String, color: Color) -> void:
	popups.append({"pos": pos, "text": text, "color": color, "t": 0.9, "min_y": 0.0})

func _shelf_metrics(L: Dictionary) -> Dictionary:
	var s: Rect2 = L["shelf"]
	var W := _vp().x
	var keys: Array = Config.shelf_order()
	# first/pitch 量自 v12 背景那排木格的隔条（白bin中心 135/301/470/636/804/973/1137，
	# 共 7 格、pitch≈0.1305、首格中心 0.1055）。图标必须落在白bin正中，差十几像素就会骑在木梁上。
	# 换底图后用 tools/bgfit.py 重量。
	var pitch := W * 0.1305
	var cell := W * 0.115
	var content := float(keys.size()) * pitch
	var max_scroll := maxf(0.0, content - W * 0.98)
	return {"cell": cell, "pitch": pitch, "first": W * 0.1055, "keys": keys, "max_scroll": max_scroll}

func _draw_shelf(L: Dictionary) -> void:
	var s: Rect2 = L["shelf"]
	var m := _shelf_metrics(L)
	var cell := float(m["cell"])
	var pitch := float(m["pitch"])
	var first := float(m["first"])
	var keys: Array = m["keys"]
	var max_scroll := float(m["max_scroll"])
	shelf_scroll = clampf(shelf_scroll, 0.0, max_scroll)
	var need := sim.next_need_ing()
	for i in keys.size():
		var key := str(keys[i])
		var cx0 := first + i * pitch - cell / 2.0 - shelf_scroll
		if cx0 + cell < s.position.x - 4 or cx0 > s.position.x + s.size.x + 4:
			continue
		var cxm := cx0 + cell / 2.0
		var stock := sim.cooked if key == "patty" else GameState.inv_count(key)
		var is_need := need == key
		var bin_r := Rect2(cxm - cell / 2.0, s.position.y, cell, s.size.y)
		if is_need and stock > 0:
			var gp := 0.5 + 0.5 * sin(t * 5.0)
			UiKit.draw_focus(self, bin_r.grow(3.0), Color(1.0, 0.89, 0.55, 0.5 + 0.4 * gp))
		# 一格一格摆实物，允许互相压一点边，像真的摊在木格里；不再用「一个图标 + 数字」
		var tex := UiKit.icon_ingredient(key)
		var shown := clampi(stock, 0, 5)
		# 木格白bin实际只有 606~672 这一段，图标顶到 65px 就贴边了，再大要压到木梁
		var ih := minf(cell * 0.46, s.size.y * 0.86)
		var iw := ih * 1.2
		if tex != null and tex.get_size().y > 0.0:
			iw = ih * tex.get_size().x / tex.get_size().y
		# 间距按格子可用宽度反推，堆得再满也不溢到隔壁格
		var gap2 := (cell * 0.94 - iw) / float(maxi(shown - 1, 1))
		gap2 = clampf(gap2, iw * 0.12, iw * 1.30)
		var span := gap2 * float(maxi(shown - 1, 0))
		var base_y := bin_r.end.y - 4.0
		if shown == 0:
			UiKit.draw_sprite(self, tex, cxm, base_y, ih, Color(0.62, 0.56, 0.5, 0.34))
		for k in shown:
			var ox := cxm - span / 2.0 + gap2 * float(k)
			var sc := 0.92 + 0.08 * float((k * 3 + i) % 3)
			var oy := base_y - (ih * 0.08 if k % 2 == 1 else 0.0)
			UiKit.draw_sprite(self, tex, ox, oy, ih * sc)
		# 热区按格间距铺满，不留两格之间的死缝
		_hits.append({"rect": Rect2(cxm - pitch / 2.0, s.position.y, pitch, s.size.y),
			"id": "shelf", "key": key, "idx": i})
	if max_scroll > 0.0:
		# 箭头以前是淡奶油色直接刷在白bin衬上，等于没画；垫一块木牌、字改深棕才看得见
		var ay := s.position.y + s.size.y / 2.0
		for side in 2:
			var on := shelf_scroll > 2.0 if side == 0 else shelf_scroll < max_scroll - 2.0
			if not on:
				continue
			var ax := s.position.x + 4.0 if side == 0 else s.end.x - 34.0
			UiKit.draw_tex_box(self, UiKit.art("ui/chip"), Rect2(ax, ay - 19.0, 30.0, 38.0))
			UiKit.draw_text_centered(self, ax + 15.0, ay + 10.0, "‹" if side == 0 else "›", 26, Color("#5a3f26"), true)


# ---------------- 酱料台 ----------------
func _draw_sauces(L: Dictionary) -> void:
	if not Config.sauces_open():
		return
	var ledge: Rect2 = L["ledge"]
	var defs: Array = Config.sauces()
	if defs.is_empty():
		return
	var n := defs.size()
	var pitch := ledge.size.x / float(n)
	# 瓶子站在前唇上、往上长过砖面，所以尺寸按带高放大到 1.45 倍；木牌挂在瓶底下面。
	# 字号 11 是 v13 那版"四瓶挤在 15% 宽里、pitch 只有 46px"留下的；回退 v12 之后
	# ledge 占 29.5% 宽、pitch 94px，14 号的"番茄酱"木牌要 64px，放得下。
	# 牌高跟着改用饮料标签那套 0.40（原来 0.46 会把牌底顶到食材架上沿）。
	var tsz := 14
	var ih := minf(ledge.size.y * 1.45, pitch * 0.94)
	var tag_y := ledge.end.y + 2.0
	var used: Dictionary = sim.sauces_used
	for i in n:
		var cx := ledge.position.x + pitch * (float(i) + 0.5)
		var r := Rect2(cx - ih / 2.0, tag_y - 6.0 - ih, ih, ih)
		var tex := UiKit.art(str(defs[i].get("art", "")))
		var on := used.has(str(defs[i].get("id", i)))
		UiKit.draw_tex_contain(self, tex, r, Color(1, 1, 1, 1.0) if not on else Color(0.62, 0.60, 0.56, 0.75))
		var nm := str(defs[i].get("name", ""))
		var tw := minf(pitch - 3.0, UiKit.text_width(nm, tsz, true) + 22.0)
		var th2 := tw * 0.40
		UiKit.draw_tex_box(self, UiKit.art("ui/tag"), Rect2(cx - tw / 2.0, tag_y, tw, th2))
		UiKit.draw_text_centered(self, cx, tag_y + th2 * 0.68, nm, tsz, Color("#5a4230"), true)
		_hits.append({"rect": r, "id": "sauce", "i": i})
	for f in sauce_fx:
		var a := clampf(float(f["t"]) / 0.5, 0.0, 1.0)
		var fx0 := float(f["x"])
		var fy := float(f["y"])
		for k in 5:
			var yy := fy + float(k) * 13.0 * (1.0 - a)
			draw_circle(Vector2(fx0 + sin(float(k) * 2.1 + t * 9.0) * 7.0, yy), 4.0 * a, Color(str(f["color"]), a))

# ---------------- 吐槽/飘字/提示 ----------------
func _draw_snark(_L: Dictionary) -> void:
	if snark_t <= 0.0 or snark_text == "":
		return
	var size := 17
	var max_w := _vp().x * 0.34
	var wrapped := UiKit.wrap_text(snark_text, max_w - 62.0, size)
	var tw := 0.0
	for line in wrapped:
		tw = maxf(tw, UiKit.text_width(line, size))
	var bw := minf(tw + 66.0, max_w)
	var bh := size * 1.5 * wrapped.size() + 16.0
	# 固定贴在左侧 HUD 下方：这里既没有酱料台也没有小票，不会盖住任何可点的东西
	var bx := 12.0
	var by := 158.0
	var a := clampf(snark_t / 0.5, 0.0, 1.0)
	UiKit.draw_tex_box(self, UiKit.art("ui/bubble"), Rect2(bx, by, bw, bh), Color(1, 1, 1, a))
	UiKit.draw_text(self, Vector2(bx + 12, by + 16 + size * 0.7), "老柴", size * 0.85, Color("#e8963c"), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var yy := by + 10.0
	for line in wrapped:
		UiKit.draw_text(self, Vector2(bx + 52, yy + size), line, size, Color(0.29, 0.23, 0.16, a))
		yy += size * 1.5

func _draw_popups(L: Dictionary) -> void:
	for p in popups:
		var a := clampf(float(p.t), 0.0, 1.0)
		var pos: Vector2 = p.pos
		# 描边：以前只有"+26"这种短字、又基本压在深色客人身上，不描也读得清；
		# 解锁播报是一整句话，落在亮色街景上时会直接糊成一片
		for d in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
			UiKit.draw_text_centered(self, pos.x + d.x, pos.y + d.y, str(p.text), 22,
				Color(0.13, 0.08, 0.05, a * 0.88), true)
		UiKit.draw_text_centered(self, pos.x, pos.y, str(p.text), 22, Color(p.color, a), true)

## 悬停提示：营业台以前只记了 _hover 却从没读过，鼠标划过任何工位都没有反馈，
## 结果就是"饮料机找不到怎么点"这类问题。热区框 + 一句话，文案在 story.json 的 tooltips。
func _draw_hover_tip() -> void:
	if _hover.x < 0.0 or _carrying() or shelf_drag or is_paused():
		return
	var hit: Dictionary = {}
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if (h["rect"] as Rect2).has_point(_hover):
			hit = h
			break
	if hit.is_empty():
		return
	var tip := _tip_for(hit)
	if tip == "":
		return
	var r: Rect2 = hit["rect"] as Rect2
	UiKit.draw_focus(self, r.grow(2.0), Color(1.0, 0.86, 0.52, 0.72))
	var size := 14
	var lines := UiKit.wrap_text(tip, 280.0, size, true)
	var tw := 0.0
	for li in lines.size():
		tw = maxf(tw, UiKit.text_width(str(lines[li]), size, true))
	tw += 24.0
	var lh := size * 1.42
	var th := 10.0 + lh * float(lines.size())
	var tx := clampf(_hover.x - tw / 2.0, 6.0, _vp().x - tw - 6.0)
	var ty := r.position.y - th - 6.0
	if ty < 64.0:
		ty = minf(r.end.y + 6.0, _vp().y - th - 6.0)
	UiKit.draw_tex_box(self, UiKit.art("ui/chip"), Rect2(tx, ty, tw, th))
	for li in lines.size():
		UiKit.draw_text_centered(self, tx + tw / 2.0, ty + 8.0 + lh * (float(li) + 0.72),
			str(lines[li]), size, Color("#5a3f26"), true)

func _tip_for(h: Dictionary) -> String:
	var id := str(h.get("id", ""))
	match id:
		"shelf":
			return Config.ingredient_name(str(h.get("key", "")))
		"drink":
			return "%s：点一下接这杯，看准液位再点一下收" % str(Config.drink_def(int(h.get("jar", 0))).get("name", ""))
		"sauce":
			var defs: Array = Config.sauces()
			var si := int(h.get("i", 0))
			if si < defs.size():
				return "%s：加在小票上多给 %d 点小费" % [str(defs[si].get("name", "")), int(defs[si].get("tip_bonus", 2))]
			return ""
		"cust":
			# customers.json 里每位客人有一句身份（role），之前没有任何界面读过——
			# 挂在悬停上，玩家划过人就报得出"这是谁"，老街的居民才立得起来
			var cu = h.get("c")
			if cu == null:
				return Config.tooltip("cust")
			var sd: Dictionary = Config.species(int(cu.sp))
			var role := str(sd.get("role", ""))
			if role == "":
				return Config.tooltip("cust")
			return "%s·%s｜%s" % [str(sd.get("name", "")), role, Config.tooltip("cust")]
		_:
			return Config.tooltip(id)
	return ""

func _do_slice(pos: Vector2) -> void:
	if sim.slice_board():
		board_fx.append({"x": pos.x, "y": pos.y, "t": 0.26})

func _draw_drag_ghost() -> void:
	if drag_ing != "" and shelf_drag:
		var h := maxf(56.0, _vp().y * 0.10)
		UiKit.draw_sprite(self, UiKit.icon_ingredient(drag_ing), drag_ing_pos.x, drag_ing_pos.y + h * 0.5, h)
	if not _carrying():
		return
	# 手里提的是**哪一件**要说得出口：选中了客人就按他接下来要收的那件显示，
	# 没选中就退回荷叶上的第一件。逐件交付之后 ghost 画错东西等于骗玩家。
	var kind := ""
	if sim.target >= 0 and sim.target < sim.queue.size():
		kind = sim.next_kind_for(sim.queue[sim.target])
	if kind == "":
		if int(sim.tray["burger"]) >= 0:
			kind = "burger"
		elif str(sim.tray["drink"]) != "":
			kind = "drink"
		elif bool(sim.tray["fries"]):
			kind = "fries"
	var tex: Texture2D = null
	match kind:
		"burger":
			tex = UiKit.icon_burger(int(sim.tray["burger"]))
		"drink":
			tex = UiKit.drink_icon(str(sim.tray["drink"]))
		"fries":
			tex = UiKit.icon_food("fries")
	if tex == null:
		return
	var gh := 88.0
	UiKit.draw_sprite(self, tex, drag_pos.x, drag_pos.y + gh * 0.5, gh)

# ---------------- 输入 ----------------
func handle_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover = mm.position
		if drag_tray or tray_sticky:
			drag_pos = mm.position
			if mm.position.distance_to(drag_press) > 10.0:
				drag_moved = true
		elif shelf_drag:
			var dx := mm.position.x - shelf_drag_start
			if absf(dx) > 8.0:
				shelf_drag_moved = true
			var L := ly()
			var m := _shelf_metrics(L)
			shelf_scroll = clampf(shelf_drag_scroll0 - dx, 0.0, float(m["max_scroll"]))
			drag_ing_pos = mm.position
		# 按住左键在案板上划过 = 连续下刀
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT and str(sim.board["ing"]) != "":
			var asm_r: Rect2 = ly()["asm"]
			if asm_r.has_point(mm.position):
				slice_travel += absf(mm.relative.x) + absf(mm.relative.y)
				if slice_travel >= 70.0:
					slice_travel = 0.0
					_do_slice(mm.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_release(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var L2 := ly()
			var m2 := _shelf_metrics(L2)
			if (L2["shelf"] as Rect2).has_point(mb.position) and float(m2["max_scroll"]) > 0.0:
				shelf_scroll = clampf(shelf_scroll + 40.0, 0.0, float(m2["max_scroll"]))
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			var L3 := ly()
			var m3 := _shelf_metrics(L3)
			if (L3["shelf"] as Rect2).has_point(mb.position) and float(m3["max_scroll"]) > 0.0:
				shelf_scroll = clampf(shelf_scroll - 40.0, 0.0, float(m3["max_scroll"]))
	elif event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and ek.keycode == KEY_ESCAPE:
			paused = true
			var ov = load("res://scripts/components/ov_pause.gd").new()
			main.open_overlay(ov, func(): pass)

func _carrying() -> bool:
	return drag_tray or tray_sticky

## 手上那份放到 pos：灶膛＝丢掉，客人＝送出，别处＝什么都没发生（托盘还在台上）。
## 返回是否真的处理掉了。
func _drop_tray(pos: Vector2) -> bool:
	var L := ly()
	if (L["fire"] as Rect2).has_point(pos):
		sim.dump_tray()
		return true
	var slots: Array = L["slots"]
	for c in sim.queue:
		if c.state != "waiting":
			continue
		var sx: float = slots[clampi(c.slot, 0, 3)].x
		var rx := Rect2(sx - slots[0].w / 2.0, float(L["head_y"]) - 24, slots[0].w,
			(float(L["counter_y"]) + 10) - (float(L["head_y"]) - 24))
		if rx.has_point(pos):
			# 逐件交付：这一击递过去的是"这位还缺、荷叶上又有"的那一件
			var k := sim.next_kind_for(c)
			if k == "":
				_on_snark(Config.misc("nothing_to_give"))
			else:
				sim.deliver(c, k)
			return true
	return false

func _press(pos: Vector2) -> void:
	if sim == null:
		return
	# 提着托盘时的这一击就是落点，不再去扫别的热区
	if tray_sticky:
		tray_sticky = false
		drag_tray = false
		_drop_tray(pos)
		return
	# 托盘拖拽
	var L := ly()
	if (L["tray"] as Rect2).has_point(pos) and sim.tray_has():
		drag_tray = true
		drag_moved = false
		drag_press = pos
		drag_pos = pos
		return
	# 食材架拖拽/点按
	for h in _hits:
		if str(h["id"]) == "shelf" and (h["rect"] as Rect2).has_point(pos):
			shelf_drag = true
			shelf_drag_moved = false
			shelf_drag_start = pos.x
			shelf_drag_scroll0 = shelf_scroll
			shelf_drag_idx = int(h["idx"])
			var ks: Array = Config.shelf_order()
			if shelf_drag_idx < ks.size():
				drag_ing = str(ks[shelf_drag_idx])
			drag_ing_pos = pos
			return
	# 其他点击
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if (h["rect"] as Rect2).has_point(pos):
			_activate(h, pos)
			return

func _release(pos: Vector2) -> void:
	if drag_tray:
		drag_tray = false
		if drag_moved:
			_drop_tray(pos)
			return
		for c in sim.queue:
			var k := sim.next_kind_for(c)
			if c.state == "waiting" and k != "":
				sim.deliver(c, k)
				return
		# 点了一下但没有正好匹配的客人：别只回一句提示，直接把它提起来，
		# 下一次点击就是落点。原来要按住拖过 10px 才算"拿起来"，等于点了没反应。
		tray_sticky = true
		drag_pos = pos
		Sfx.play("lift")
		_on_snark(Config.misc("tray_lifted"))
		return
	if shelf_drag:
		shelf_drag = false
		var dropped := (ly()["asm"] as Rect2).has_point(pos)
		drag_ing = ""
		if not shelf_drag_moved and shelf_drag_idx >= 0:
			var keys: Array = Config.shelf_order()
			if shelf_drag_idx < keys.size():
				sim.tap_shelf(str(keys[shelf_drag_idx]))
		elif dropped and shelf_drag_idx >= 0:
			var keys2: Array = Config.shelf_order()
			if shelf_drag_idx < keys2.size():
				sim.tap_shelf(str(keys2[shelf_drag_idx]))
		shelf_drag_idx = -1
		return

func _activate(h: Dictionary, pos: Vector2) -> void:
	var id := str(h["id"])
	match id:
		"truck":
			var ov = load("res://scripts/components/ov_truck.gd").new()
			ov.setup({"emergency": true})
			main.open_overlay(ov)
		"menu":
			main.open_overlay(load("res://scripts/components/ov_menu.gd").new())
		"pause":
			paused = true
			main.open_overlay(load("res://scripts/components/ov_pause.gd").new())
		"records":
			# HUD 上这枚圆钮的图标和悬停说明都写着"营业台账"，但 match 里一直没有这一支，
			# 点下去不出声也不换屏。台账在暂停菜单里也有一份，从这儿走是不必先暂停的。
			main.goto("records", {"from": "play"})
		"sweeper":
			# 点收币人：打断他，并把他已经装进兜里的钱抢回来（沙威玛那一下）
			sim.swat_sweeper()
		"sound":
			GameState.toggle_muted()
			SaveManager.save_all()
		"grill":
			sim.tap_grill(int(h["i"]))
		"sauce":
			if sim.apply_sauce(int(h["i"])):
				var defs: Array = Config.sauces()
				var col := "e8452c"
				if int(h["i"]) == 1:
					col = "f2dfa0"
				elif int(h["i"]) == 2:
					col = "e8b23c"
				elif int(h["i"]) == 3:
					col = "c9412f"
				sauce_fx.append({"x": pos.x, "y": pos.y + 18.0, "t": 0.5, "color": col})
			else:
				Sfx.play("tap")
		"fryer":
			sim.tap_fryer()
		"drink":
			sim.tap_drink(int(h.get("jar", -1)))
		"asm":
			if str(sim.board["ing"]) != "":
				_do_slice(pos)
			elif sim.target < 0:
				var fi := sim.first_waiting()
				if fi >= 0:
					sim.target = fi
					Sfx.play("tap")
				else:
					sim._snark("noorder")
		"tray":
			if pos != Vector2.ZERO and not sim.tray_has():
				_on_snark(Config.misc("tray_empty"))
		"bin":
			sim.dump_tray()
		"fire_add":
			sim.add_wood()
		"fire_chop":
			var ov = load("res://scripts/components/ov_chop.gd").new()
			ov.setup({"on_done": Callable(self, "_on_chop_done")})
			main.open_overlay(ov)
		"shelf":
			sim.tap_shelf(str(h["key"]))
		"cust":
			sim.tap_customer(h["c"])

	