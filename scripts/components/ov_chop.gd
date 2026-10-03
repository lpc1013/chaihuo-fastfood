extends OvBase
## 劈柴小游戏：斧头在柴面上方左右扫，落进绿色窗口时点「劈！」。命中 +2 柴，未命中 +1 柴。
## 挥斧／劈开／木屑／震屏都只活在这一层，模拟层只在结束时收到 apply_chop(gained)。

var on_done: Callable = Callable()
var rounds := 3
var round_seconds := 1.5
var hit_zone := Vector2(0.32, 0.68)
var hit_wood := 2
var miss_wood := 1
var swing_seconds := 0.13
var bite_seconds := 0.10
var lift_seconds := 0.30

var marker := 0.0
var marker_dir := 1.0
var round_idx := 0
var gained := 0
var all_hit := true
var finished := false
var finish_t := 0.0
var flash := ""
var flash_t := 0.0
var applied := false

var phase := ""
var phase_t := 0.0
var aim := 0.5
var aim_hit := false
var log_gone := false
var spawn_t := 9.0
var wobble := 0.0
var shake := 0.0
var pieces: Array = []
var chips: Array = []
var puffs: Array = []
var hold := false
var _hits: Array = []

# fx/axe.png 上的两个锚点：刃口中点（落点）与握把（旋转中心）
const AXE_SZ := Vector2(345, 232)
const AXE_TIP := Vector2(22, 126)
const AXE_HAND := Vector2(318, 195)
const AXE_UP := -1.28
const AXE_HIT := -1.95
# fx/log.png：年轮圆面在 x≈150 之后，劈开线压在它左边才不会把年轮切成月牙
const LOG_SZ := Vector2(303, 121)
const LOG_SPLIT := 143.0
const CHIP_ANG := [-152.0, -124.0, -96.0, -68.0, -40.0, -16.0, -170.0, -110.0, -80.0, -54.0, -30.0]
const CHIP_SPD := [300.0, 380.0, 430.0, 392.0, 322.0, 252.0, 248.0, 334.0, 402.0, 300.0, 358.0]
const CHIP_COL := [Color("#8a5326"), Color("#c2762f"), Color("#f0c88a")]

func setup(params: Dictionary) -> void:
	on_done = params.get("on_done", Callable())
	var cfg: Dictionary = Config.fire.get("chop", {})
	rounds = int(cfg.get("rounds", 3))
	round_seconds = float(cfg.get("round_seconds", 1.5))
	var zone: Array = cfg.get("hit_zone", [0.32, 0.68])
	hit_zone = Vector2(float(zone[0]), float(zone[1]))
	hit_wood = int(cfg.get("hit_wood", 2))
	miss_wood = int(cfg.get("miss_wood", 1))
	swing_seconds = float(cfg.get("swing_seconds", 0.13))
	bite_seconds = float(cfg.get("bite_seconds", 0.10))
	lift_seconds = float(cfg.get("lift_seconds", 0.30))

func panel_rect() -> Rect2:
	var W := vp().x
	var H := vp().y
	var pw := 620.0
	var ph := 548.0
	return Rect2(W / 2 - pw / 2, H / 2 - ph / 2, pw, ph)

## 舞台几何：全部由面板内框推出来，跟着分辨率走。
func _stage() -> Dictionary:
	var c := UiKit.panel_frame(panel_rect())
	var ccx := c.position.x + c.size.x / 2.0
	var s := c.size.x * 0.42 / LOG_SZ.x
	var lw := LOG_SZ.x * s
	var lh := LOG_SZ.y * s
	return {
		"c": c, "ccx": ccx, "s": s, "lw": lw, "lh": lh,
		"log_cy": c.end.y - 132.0, "asc": s * 0.62, "travel": lw * 0.66,
	}

func _blade_x(st: Dictionary, m: float) -> float:
	return float(st["ccx"]) + (m - 0.5) * float(st["travel"])

func _log_top(st: Dictionary) -> float:
	return float(st["log_cy"]) - float(st["lh"]) * 0.5

func _impact_pt(st: Dictionary) -> Vector2:
	return Vector2(_blade_x(st, aim), _log_top(st) + 8.0)

func _hover_pt(st: Dictionary) -> Vector2:
	return Vector2(_blade_x(st, marker), _log_top(st) - 40.0)

## 刃口相对握把的向量：先取精灵坐标，再按角度旋到屏幕朝向（y 轴向下）。
func _axe_d(ang: float, sc: float) -> Vector2:
	var v := (AXE_TIP - AXE_HAND) * sc
	var ca := cos(ang)
	var sa := sin(ang)
	return Vector2(v.x * ca - v.y * sa, v.x * sa + v.y * ca)

func _axe_ang() -> float:
	if phase == "swing":
		var k := clampf(phase_t / swing_seconds, 0.0, 1.0)
		return lerpf(AXE_UP, AXE_HIT, k * k)
	if phase == "bite":
		return AXE_HIT
	if phase == "lift":
		var u := clampf(phase_t / lift_seconds, 0.0, 1.0)
		var e := 1.0 - (1.0 - u) * (1.0 - u)
		return lerpf(AXE_HIT, AXE_UP, e)
	return AXE_UP

## 刃口当前位置。出斧后它从抬起处直线砸向落点，握把再由 _axe_d 反推出来。
func _blade_pt(st: Dictionary) -> Vector2:
	var top := _log_top(st)
	if phase == "swing":
		var k := clampf(phase_t / swing_seconds, 0.0, 1.0)
		return Vector2(_blade_x(st, aim), lerpf(top - 40.0, top + 8.0, k * k))
	if phase == "bite":
		return _impact_pt(st)
	if phase == "lift":
		var u := clampf(phase_t / lift_seconds, 0.0, 1.0)
		return Vector2(_blade_x(st, aim), lerpf(top + 8.0, top - 40.0, 1.0 - (1.0 - u) * (1.0 - u)))
	return _hover_pt(st)

func _on_tick(delta: float) -> void:
	if hold:
		return
	if flash_t > 0.0:
		flash_t -= delta
	shake = maxf(0.0, shake - delta)
	wobble = maxf(0.0, wobble - delta)
	if spawn_t < 1.0:
		spawn_t += delta
	for p in pieces:
		p["vel"] = (p["vel"] as Vector2) + Vector2(0, 1180) * delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["rot"] = float(p["rot"]) + float(p["vrot"]) * delta
		p["life"] = float(p["life"]) + delta
	pieces = pieces.filter(func(p): return float(p["life"]) < 0.95)
	for ch in chips:
		ch["vel"] = (ch["vel"] as Vector2) + Vector2(0, 1450) * delta
		ch["pos"] = (ch["pos"] as Vector2) + (ch["vel"] as Vector2) * delta
		ch["life"] = float(ch["life"]) + delta
	chips = chips.filter(func(ch): return float(ch["life"]) < float(ch["max"]))
	for pu in puffs:
		pu["life"] = float(pu["life"]) + delta
	puffs = puffs.filter(func(pu): return float(pu["life"]) < 0.44)
	if finished:
		finish_t += delta
		if finish_t > 1.4:
			_finish_now()
		return
	if phase == "":
		marker += delta / round_seconds * marker_dir
		if marker >= 1.0:
			marker = 1.0
			_strike(false)
		elif marker <= 0.0:
			marker = 0.0
			marker_dir = 1.0
	elif phase == "swing":
		phase_t += delta
		if phase_t >= swing_seconds:
			_impact()
	elif phase == "bite":
		phase_t += delta
		if phase_t >= bite_seconds:
			phase = "lift"
			phase_t = 0.0
	elif phase == "lift":
		phase_t += delta
		if phase_t >= lift_seconds:
			phase = ""
			phase_t = 0.0
			marker = 0.0
			marker_dir = 1.0
			_next_round()

func _press() -> void:
	if finished:
		_finish_now()
		return
	if phase != "":
		return
	_strike(marker >= hit_zone.x and marker <= hit_zone.y)

func _strike(hit: bool) -> void:
	aim = marker
	aim_hit = hit
	phase = "swing"
	phase_t = 0.0
	Sfx.play("whoosh")

func _impact() -> void:
	var st := _stage()
	var ip := _impact_pt(st)
	phase = "bite"
	phase_t = 0.0
	shake = 0.26 if aim_hit else 0.13
	flash_t = 0.9
	Sfx.play("chop")
	Sfx.play("thud")
	if aim_hit:
		gained += hit_wood
		log_gone = true
		_spawn_split(st)
		_burst(11, ip)
		flash = "利落！+%d" % hit_wood
		Sfx.play("ding")
	else:
		gained += miss_wood
		all_hit = false
		wobble = 0.34
		_burst(3, ip)
		flash = "差一点，+%d" % miss_wood
	for i in 3:
		puffs.append({"pos": ip + Vector2((i - 1) * 16.0, 2.0), "life": 0.0, "r": 12.0 + i * 5.0})

func _spawn_split(st: Dictionary) -> void:
	var s := float(st["s"])
	var rx := float(st["ccx"]) - float(st["lw"]) * 0.5
	var ry := float(st["log_cy"]) - float(st["lh"]) * 0.5
	var cut := LOG_SPLIT * s
	pieces.append({
		"src": Rect2(0, 0, LOG_SPLIT, LOG_SZ.y), "side": -1.0,
		"pos": Vector2(rx + cut * 0.5, ry + float(st["lh"]) * 0.5),
		"w": cut, "h": float(st["lh"]),
		"vel": Vector2(-138.0, -222.0), "rot": 0.0, "vrot": -2.5, "life": 0.0,
	})
	pieces.append({
		"src": Rect2(LOG_SPLIT, 0, LOG_SZ.x - LOG_SPLIT, LOG_SZ.y), "side": 1.0,
		"pos": Vector2(rx + cut + (float(st["lw"]) - cut) * 0.5, ry + float(st["lh"]) * 0.5),
		"w": float(st["lw"]) - cut, "h": float(st["lh"]),
		"vel": Vector2(152.0, -182.0), "rot": 0.0, "vrot": 2.2, "life": 0.0,
	})

func _burst(n: int, ip: Vector2) -> void:
	for i in n:
		var a := deg_to_rad(CHIP_ANG[i % CHIP_ANG.size()])
		var spd := float(CHIP_SPD[i % CHIP_SPD.size()])
		chips.append({
			"pos": ip + Vector2(cos(a) * 6.0, -4.0 + float(i % 3)),
			"vel": Vector2(cos(a) * spd, sin(a) * spd),
			"rot": a, "vrot": -5.0 + float(i % 4) * 3.0,
			"sz": 11.0 + float((i * 7) % 9),
			"col": CHIP_COL[i % CHIP_COL.size()],
			"life": 0.0, "max": 0.5 + float(i % 4) * 0.12,
		})

func _next_round() -> void:
	if log_gone:
		spawn_t = 0.0
	log_gone = false
	round_idx += 1
	flash_t = 0.9
	if round_idx >= rounds:
		finished = true
		finish_t = 0.0
		flash = "共劈得 %d 根柴" % gained
		flash_t = 1.6

## 供自动化测试使用：把指针放到指定位置再判定；会先把上一斧的动画结算掉
func press_at(frac: float) -> void:
	hold = false
	if finished:
		return
	_settle()
	marker = clampf(frac, 0.0, 1.0)
	_press()

## 供自动化测试抓帧：摆出某一阶段的姿势。走的是真实判定路径，但不消耗轮次。
func debug_pose(p: String) -> void:
	var keep := [round_idx, gained, all_hit, finished, finish_t]
	_settle()
	round_idx = int(keep[0])
	gained = int(keep[1])
	all_hit = bool(keep[2])
	finished = bool(keep[3])
	finish_t = float(keep[4])
	pieces.clear()
	chips.clear()
	puffs.clear()
	shake = 0.0
	wobble = 0.0
	log_gone = false
	spawn_t = 9.0
	flash_t = 0.0
	var hit := p != "miss" and p != "miss2"
	marker = 0.5 if hit else 0.12
	marker_dir = 1.0
	_strike(hit)
	hold = true
	if p == "swing" or p == "miss2":
		phase_t = swing_seconds * 0.62
		return
	_impact()
	if p == "miss":
		phase_t = bite_seconds * 0.4
		return
	_nudge(0.16)
	shake = 0.20
	phase = "lift"
	phase_t = lift_seconds * 0.5

## 只推进特效，不推进阶段——抓帧时用
func _nudge(dt: float) -> void:
	for p in pieces:
		p["vel"] = (p["vel"] as Vector2) + Vector2(0, 1180) * dt
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * dt
		p["rot"] = float(p["rot"]) + float(p["vrot"]) * dt
		p["life"] = float(p["life"]) + dt
	for ch in chips:
		ch["vel"] = (ch["vel"] as Vector2) + Vector2(0, 1450) * dt
		ch["pos"] = (ch["pos"] as Vector2) + (ch["vel"] as Vector2) * dt
		ch["life"] = float(ch["life"]) + dt
	for pu in puffs:
		pu["life"] = float(pu["life"]) + dt

func _settle() -> void:
	var guard := 0
	while phase != "" and guard < 8:
		guard += 1
		if phase == "swing":
			_impact()
		elif phase == "bite":
			phase = "lift"
			phase_t = 0.0
		else:
			phase = ""
			phase_t = 0.0
			marker = 0.0
			marker_dir = 1.0
			_next_round()

func _finish_now() -> void:
	if applied:
		close()
		return
	applied = true
	if on_done.is_valid():
		on_done.call(gained, all_hit)
	close()

func _on_escape() -> void:
	_finish_now()

func _on_outside_click() -> void:
	_finish_now()

func _shake_off() -> Vector2:
	if shake <= 0.0:
		return Vector2.ZERO
	var k := shake / 0.26
	return Vector2(sin(shake * 92.0) * 5.0 * k, cos(shake * 74.0) * 4.0 * k)

func _log_wob() -> float:
	if wobble <= 0.0:
		return 0.0
	return sin(wobble * 46.0) * 7.0 * (wobble / 0.34)

func _draw() -> void:
	_hits = []
	draw_rect(Rect2(0, 0, vp().x, vp().y), Color(0, 0, 0, 0.72))
	var sk := _shake_off()
	var st := _stage()
	var frame := (st["c"] as Rect2)
	var outer := panel_rect()
	outer.position += sk
	frame.position += sk
	UiKit.draw_nine(self, UiKit.art("ui/panel"), outer)
	var ccx := frame.position.x + frame.size.x / 2.0
	# 先画舞台再画字：斧柄扫到最上方时也会压在提示行下面，字不能被盖住
	_draw_stage(st, sk)
	UiKit.draw_text_centered(self, ccx, frame.position.y + 26, "劈柴", 24, UiKit.INK, true)
	UiKit.draw_text_centered(self, ccx, frame.position.y + 52,
		"斧头落进绿色窗口时点「劈！」 · 命中 +%d 根，未命中 +%d 根" % [hit_wood, miss_wood],
		14, UiKit.INK_SOFT)
	UiKit.draw_text_right(self, frame.end.x - 6, frame.position.y + 26, "现有柴 %d" % _wood_now(), 14, UiKit.INK_SOFT)
	var dot_y := float(st["log_cy"]) + float(st["lh"]) * 0.5 + 22.0
	for i in rounds:
		var dx := ccx - (rounds - 1) * 19.0 + i * 38.0
		var done_r := i < round_idx
		var dot := Rect2(dx - 15.0, dot_y + sk.y, 30, 18)
		UiKit.draw_tex_box(self, UiKit.art("ui/chip"), dot,
			Color.WHITE if done_r else Color(0.86, 0.82, 0.76, 0.6))
		UiKit.draw_text_centered(self, dx, dot_y + 13.5 + sk.y, str(i + 1), 12,
			UiKit.INK if done_r else UiKit.INK_FAINT, true)
	if not finished:
		_btn(Rect2(ccx - 84.0, frame.end.y - 48.0, 168, 46), "劈！", Callable(self, "_press"))
	else:
		UiKit.draw_text_centered(self, ccx, frame.end.y - 20.0, "共劈得 %d 根柴（点击关闭）" % gained, 16, UiKit.INK, true)
	if flash_t > 0.0 and not finished:
		var fu := 1.0 - clampf(flash_t / 0.9, 0.0, 1.0)
		var fy := _log_top(st) - 14.0 - fu * 34.0 + sk.y
		UiKit.draw_text_centered(self, _blade_x(st, aim) + sk.x, fy, flash, 20,
			Color(UiKit.EMBER, clampf(flash_t / 0.35, 0.0, 1.0)), true)

func _draw_stage(st: Dictionary, sk: Vector2) -> void:
	var frame := st["c"] as Rect2
	var ccx := float(st["ccx"])
	var log_cy := float(st["log_cy"])
	var lw := float(st["lw"])
	var lh := float(st["lh"])
	var top := _log_top(st)
	# 柴垛退到后面当布景，底边和柴落在同一条地线上。
	# 原图里插着的那把斧头已经被拆出去了，不会和手里这把打架。
	UiKit.draw_sprite(self, UiKit.art("kitchen/wood_stack"), frame.position.x + 78.0 + sk.x,
		log_cy + lh * 0.36 + sk.y, 104.0, Color(1, 1, 1, 0.92))
	UiKit.draw_sprite(self, UiKit.art("kitchen/wood_stack"), frame.end.x - 82.0 + sk.x,
		log_cy + lh * 0.40 + sk.y, 82.0, Color(1, 1, 1, 0.72))
	# 柴底下的地线阴影：压扁的圆。收得比柴窄一点，否则读成一块摆在那儿的铁板
	draw_set_transform(Vector2(ccx + sk.x, log_cy + lh * 0.46 + 3.0 + sk.y), 0.0, Vector2(1.0, 0.14))
	draw_circle(Vector2.ZERO, lw * 0.40, Color(0.34, 0.20, 0.10, 0.26))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 命中窗口：越靠近柴面越实的绿色光柱 + 两道亮边 + 顶上一对向下的箭头
	var zx0 := _blade_x(st, hit_zone.x) + sk.x
	var zw := _blade_x(st, hit_zone.y) - _blade_x(st, hit_zone.x)
	var shaft_top := top - 54.0
	var shaft_h := 54.0 + lh * 0.46
	UiKit.draw_rect_gradient(self, Rect2(zx0, shaft_top + sk.y, zw, shaft_h),
		Color(0.36, 0.88, 0.50, 0.10), Color(0.26, 0.76, 0.40, 0.40))
	draw_rect(Rect2(zx0 - 1.5, shaft_top + sk.y, 3.0, shaft_h), Color(0.28, 0.80, 0.42, 0.80))
	draw_rect(Rect2(zx0 + zw - 1.5, shaft_top + sk.y, 3.0, shaft_h), Color(0.28, 0.80, 0.42, 0.80))
	for ex in [zx0, zx0 + zw]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(ex - 5.0, shaft_top - 9.0 + sk.y), Vector2(ex + 5.0, shaft_top - 9.0 + sk.y),
			Vector2(ex, shaft_top + 1.0 + sk.y),
		]), Color(0.28, 0.80, 0.42, 0.9))
	var asc := float(st["asc"])
	var ang := _axe_ang()
	var bp := _blade_pt(st) + sk
	var hand := bp - _axe_d(ang, asc)
	if phase == "swing":
		for g in 2:
			var ka := float(g + 1) / 3.0
			var ga := lerpf(ang, AXE_UP, ka)
			_draw_axe(bp - _axe_d(ga, asc) - Vector2(0, ka * 26.0), ga, asc, Color(1, 1, 1, 0.15))
	# 咬进柴里的那一瞬把斧头画在柴后面，才像真的「进去」了
	var behind := phase == "bite" and not aim_hit
	if behind:
		_draw_axe(hand, ang, asc, Color.WHITE)
	if not log_gone:
		var vis := clampf(spawn_t / 0.24, 0.0, 1.0)
		var drop := (1.0 - vis) * -22.0
		_draw_log(Rect2(ccx - lw * 0.5 + _log_wob() + sk.x, log_cy - lh * 0.5 + drop + sk.y, lw, lh), vis)
	for p in pieces:
		_draw_piece(p, sk)
	if not behind:
		_draw_axe(hand, ang, asc, Color.WHITE)
	if phase == "" and not finished:
		var mx := _blade_x(st, marker) + sk.x
		for i in 4:
			draw_rect(Rect2(mx - 1.0, top - 40.0 + i * 9.0 + sk.y, 2.0, 5.0),
				Color(1, 0.94, 0.80, 0.55 - i * 0.1))
	for pu in puffs:
		var u := float(pu["life"]) / 0.44
		draw_circle((pu["pos"] as Vector2) + sk, float(pu["r"]) * (0.5 + u * 1.6),
			Color(0.96, 0.90, 0.80, 0.40 * (1.0 - u)))
	for ch in chips:
		_draw_chip_quad(ch, sk, 1.0 - clampf(float(ch["life"]) / float(ch["max"]), 0.0, 1.0))
	if phase == "bite" and aim_hit:
		var k := 1.0 - clampf(phase_t / bite_seconds, 0.0, 1.0)
		draw_arc(_impact_pt(st) + sk, 26.0 + (1.0 - k) * 30.0, 0.0, TAU, 26,
			Color(1, 1, 0.94, 0.75 * k), 4.0)

func _draw_log(rect: Rect2, vis: float) -> void:
	var tex := UiKit.art("fx/log")
	if tex == null:
		return
	draw_texture_rect(tex, rect, false, Color(1, 1, 1, clampf(vis, 0.0, 1.0)))

func _draw_piece(p: Dictionary, sk: Vector2) -> void:
	var tex := UiKit.art("fx/log")
	if tex == null:
		return
	var a := 1.0 - clampf((float(p["life"]) - 0.55) / 0.4, 0.0, 1.0)
	var w := float(p["w"])
	var h := float(p["h"])
	var side := float(p["side"])
	draw_set_transform((p["pos"] as Vector2) + sk, float(p["rot"]), Vector2.ONE)
	draw_texture_rect_region(tex, Rect2(-w * 0.5, -h * 0.5, w, h), p["src"] as Rect2, Color(1, 1, 1, a))
	# 断口：贴着内侧的一道新木色，两块分开时才看得出是「劈」断而不是缩小
	var fx := (w * 0.5 - 4.0) if side < 0.0 else (-w * 0.5 - 3.0)
	draw_rect(Rect2(fx, -h * 0.5 + 5.0, 7.0, h - 10.0), Color(0.97, 0.89, 0.72, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_chip_quad(ch: Dictionary, sk: Vector2, alpha: float) -> void:
	var sz := float(ch["sz"])
	var pos := (ch["pos"] as Vector2) + sk
	var rot := float(ch["rot"]) + float(ch["life"]) * float(ch["vrot"])
	var ca := cos(rot)
	var sa := sin(rot)
	var col: Color = ch["col"]
	col.a = alpha * 0.95
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for q in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var lx := float(q[0]) * sz * 0.5
		var ly := float(q[1]) * sz * 0.42
		pts.append(pos + Vector2(lx * ca - ly * sa, lx * sa + ly * ca))
		cols.append(col)
	draw_polygon(pts, cols)

func _draw_axe(hand: Vector2, ang: float, sc: float, mod: Color) -> void:
	var tex := UiKit.art("fx/axe")
	if tex == null:
		return
	draw_set_transform(hand, ang, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-AXE_HAND.x * sc, -AXE_HAND.y * sc, AXE_SZ.x * sc, AXE_SZ.y * sc), false, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _wood_now() -> int:
	if main.current != null and main.current.has_method("wood_count"):
		return int(main.current.call("wood_count"))
	return 0

func _btn(rect: Rect2, label: String, cb: Callable) -> void:
	var hovered := rect.has_point(_hover)
	UiKit.draw_tex_box(self, UiKit.art("ui/tag"), rect, Color(1.14, 1.06, 0.96) if hovered else Color.WHITE)
	UiKit.draw_text_centered(self, rect.position.x + rect.size.x / 2.0,
		rect.position.y + rect.size.y / 2.0 + 7, label, 20, Color("#8a3d12"), true)
	_hits.append({"rect": rect, "cb": cb})

func _on_click(pos: Vector2) -> void:
	for h in _hits:
		if (h["rect"] as Rect2).has_point(pos):
			var cb: Callable = h["cb"]
			cb.call()
			return
	# 面板内除按钮外的空白也算出斧——时机游戏不该逼玩家去瞄按钮
	_press()
