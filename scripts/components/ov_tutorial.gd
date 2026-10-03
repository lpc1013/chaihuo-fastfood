extends OvBase
## 开场教学动画：八幕自动播放的演示，点一下跳到下一幕，随时可跳过。
## 只做表现，不碰模拟层数据。

var on_done: Callable = Callable()
var stage := 0
var pt := 0.0
var _hits: Array = []
var t := 0.0
var _done := false

## target 一律给工位名，画的时候现问 play.ly() 要矩形：
## 以前这里写死 7 组分数坐标，换一张底图就得手工重量一遍，还容易量歪。
const STAGES := [
	{"text": "① 炉膛里没柴就烧不旺：点斧头劈柴，再点柴块添进炉口", "cell": "fire", "prop": "stoke", "hand": [0.86, 0.80]},
	{"text": "② 点烤架的空位，放一块生肉饼", "cell": "grill", "prop": "patty_raw"},
	{"text": "③ 盯住进度条的金色窗口，再点一次翻面", "cell": "grill", "prop": "patty_cooked"},
	{"text": "④ 从下面木格里把食材拖上案板", "cell": "asm", "prop": "drag_lettuce"},
	{"text": "⑤ 要切的食材：点击或按住划过案板", "cell": "asm", "prop": "chop"},
	{"text": "⑥ 最后再点一次汉堡胚封顶，变成一个汉堡", "cell": "asm", "prop": "assemble"},
	{"text": "⑦ 把荷叶上的汉堡拖给客人，金币到手", "cell": "tray", "prop": "serve"},
	{"text": "⑧ 做坏了没人要？点一下托盘提起来，再点灶膛口丢掉", "cell": "fire", "prop": "dump"},
]

func _ready() -> void:
	z_index = 40

func panel_rect() -> Rect2:
	var v := vp()
	return Rect2(0, 0, v.x, v.y)

func _on_tick(delta: float) -> void:
	if _done:
		return
	t += delta
	pt += delta
	if pt >= 3.0:
		_next()

func _next() -> void:
	if _done:
		return
	pt = 0.0
	stage += 1
	if stage >= STAGES.size():
		_finish()
		return
	# 八幕教学以前是彻底无声的：点一下画面整幕换掉却没有任何回应，
	# 玩家会以为没点到。用对话推进那一声，和剧情页同一套。
	Sfx.play("story")

func _finish() -> void:
	if _done:
		return
	_done = true
	if on_done.is_valid():
		on_done.call()
	close()

func _on_click(_pos: Vector2) -> void:
	_next()

func _on_outside_click() -> void:
	_next()

func _on_escape() -> void:
	_finish()

## 教学只在 play 上打开，所以工位矩形直接问它要，不再自己存一份坐标。
## 认 screens["play"] 而不是 main.current：换场那一帧 current 可能还不是 play，
## 拿不到版面时这一帧干脆不画（border 里就是这样炸过一次）。
func _layout() -> Dictionary:
	var scr = main.screens.get("play") if main != null else null
	return scr.call("ly") if scr != null and scr.has_method("ly") else {}

func _draw() -> void:
	if _done or stage >= STAGES.size():
		return
	_hits = []
	var v := vp()
	var st: Dictionary = STAGES[stage]
	var L := _layout()
	if L.is_empty():
		return
	var tr: Rect2 = L[str(st["cell"])]
	draw_rect(Rect2(0, 0, v.x, v.y), Color(0.05, 0.04, 0.09, 0.72))
	var gp := 0.5 + 0.5 * sin(t * 5.0)
	UiKit.draw_focus(self, Rect2(tr.position.x - 12, tr.position.y - 12, tr.size.x + 24, tr.size.y + 24),
		Color(1, 0.92, 0.66, 0.6 + 0.4 * gp))
	_draw_prop(str(st["prop"]), tr, L)
	_draw_hand(tr, st)
	_draw_caption(str(st["text"]), v)
	var sk := Rect2(v.x - 104, 14, 86, 36)
	UiKit.draw_nine(self, UiKit.art("ui/chip"), sk)
	UiKit.draw_text_centered(self, sk.position.x + sk.size.x / 2, sk.position.y + 24, "跳过", 14, Color("#7a3c12"), true)
	_hits.append({"rect": sk, "id": "skip"})

func _draw_prop(kind: String, tr: Rect2, L: Dictionary) -> void:
	var cx := tr.position.x + tr.size.x / 2.0
	var by := tr.end.y - 6.0
	var s := tr.size.y * 0.42
	var mouth := Vector2(cx, tr.position.y + tr.size.y * 0.52)
	match kind:
		"stoke":
			# 斧头在炉顶石板上劈柴 → 柴垛多一根 → 一根柴滑进炉口、火焰跟着变大。
			# 柴垛位置必须和 play._draw_wood_pile 对齐，不然教的是另一个地方。
			var lw := tr.size.x * 0.135
			var lh := lw * 0.40
			var px0 := tr.position.x + tr.size.x * 0.05
			var pbase := tr.position.y + tr.size.y * 0.155
			var swing := sin(minf(pt * 4.5, PI)) * s * 0.40
			# 斧子以前按 s*1.1（≈90px）画在石板线上，比一根柴高 7 倍，斧刃还没到、
			# 斧背已经顶出炉拱骑到夜空上，读作"天上一把大斧头"。收到和柴垛同量级、
			# 并且挪到柴垛右手边，才像在劈这一堆。
			UiKit.draw_sprite(self, UiKit.art("fx/axe"), tr.position.x + tr.size.x * 0.30,
				pbase - lh * 0.6 + swing, s * 0.52)
			var logs := 2 if pt < 1.0 else 3
			for i in logs:
				UiKit.draw_tex_contain(self, UiKit.art("fx/log"), Rect2(
					px0 + float(i % 2) * lw * 1.02, pbase - float(int(i / 2) + 1) * (lh + 1.0), lw, lh))
			var k4 := clampf((pt - 1.3) / 1.3, 0.0, 1.0)
			if k4 > 0.0:
				var lp := Vector2(px0 + lw * 0.6, pbase - lh).lerp(mouth, k4)
				var fl := 0.5 + 0.5 * sin(t * 7.0)
				if k4 < 0.94:
					UiKit.draw_tex_contain(self, UiKit.art("fx/log"), Rect2(lp.x - lw * 0.5, lp.y, lw, lh))
				UiKit.draw_sprite(self, UiKit.art("kitchen/flame"), mouth.x, mouth.y + s * 0.3,
					s * (0.9 + 0.55 * k4) * (0.92 + 0.1 * fl))
		"patty_raw":
			UiKit.draw_sprite(self, UiKit.art("ingredients/pt_raw"), cx, by, s)
		"patty_cooked":
			UiKit.draw_sprite(self, UiKit.art("ingredients/pt_cooked"), cx, by, s)
		"drag_lettuce":
			var k := clampf(pt / 1.1, 0.0, 1.0)
			var sh: Rect2 = L["shelf"]
			var from := Vector2(tr.position.x + tr.size.x * 0.2, sh.position.y + sh.size.y * 0.30)
			var to := Vector2(cx, by - s * 0.2)
			var lp2 := from.lerp(to, k)
			UiKit.draw_sprite(self, UiKit.icon_ingredient("lettuce"), lp2.x, lp2.y + s, s * 1.1)
		"chop":
			UiKit.draw_sprite(self, UiKit.icon_ingredient("lettuce"), cx, by, s * 1.15)
			var cycle := fmod(pt, 0.7) / 0.7
			if cycle < 0.45:
				var kx := cx + (0.5 - cycle) * tr.size.x * 0.7
				UiKit.draw_sprite(self, UiKit.art("fx/knife"), kx, by - s * 0.9 + cycle * s * 1.4, s * 1.5)
			UiKit.draw_sprite(self, UiKit.icon_ingredient("lettuce"), cx - s * 0.55, by, s * 0.5, Color(1, 1, 1, 0.9))
			UiKit.draw_sprite(self, UiKit.icon_ingredient("lettuce"), cx + s * 0.1, by, s * 0.5, Color(1, 1, 1, 0.9))
		"assemble":
			UiKit.draw_sprite(self, UiKit.art("ingredients/pt_cooked"), cx, by, s)
			UiKit.draw_sprite(self, UiKit.icon_ingredient("cheese"), cx, by - s * 0.28, s * 0.9)
			var drop := clampf(pt / 1.2, 0.0, 1.0)
			if drop < 0.98:
				UiKit.draw_sprite(self, UiKit.icon_ingredient("bun"), cx, by - s * 1.6 + drop * s * 1.3, s)
			else:
				UiKit.draw_sprite(self, UiKit.icon_burger(0), cx, by, s * 1.5)
		"serve":
			var k2 := clampf((pt - 0.5) / 1.6, 0.0, 1.0)
			var slots: Array = L["slots"]
			var to2 := Vector2(float(slots[1]["x"]), float(L["counter_y"]) - float(L["cust_h"]) * 0.34)
			var from2 := Vector2(cx, by - s * 0.4)
			var pos := from2.lerp(to2, k2)
			UiKit.draw_sprite(self, UiKit.icon_burger(0), pos.x, pos.y, s * 1.5)
			if k2 > 0.9:
				UiKit.draw_sprite(self, UiKit.art("characters/full_rabbit"), to2.x, to2.y + s * 1.2, s * 3.0)
				var bl := 0.5 + 0.5 * sin(t * 6.0)
				UiKit.draw_text_centered(self, to2.x, to2.y - s * 1.6, "+26", 26, Color(1.0, 0.84, 0.30, 0.6 + 0.4 * bl), true)
		"dump":
			# 荷叶 → 灶膛口的一段拖影，末尾糊一下火，表示这份东西没了、钱不退
			var k3 := clampf((pt - 0.5) / 1.4, 0.0, 1.0)
			var from3: Vector2 = (L["tray"] as Rect2).get_center()
			var p3 := from3.lerp(mouth, k3)
			if k3 < 0.97:
				UiKit.draw_sprite(self, UiKit.icon_burger(0), p3.x, p3.y, tr.size.y * 0.52)
			else:
				# 火苗让到炉口左半：小手默认就落在炉口正中，两个原来完全叠在一起，
				# 末尾这一下"噗"的反馈被手盖掉，看不出东西是被烧掉的
				UiKit.draw_sprite(self, UiKit.art("kitchen/flame"),
					tr.position.x + tr.size.x * 0.30, mouth.y + tr.size.y * 0.2, tr.size.y * 0.62)

## 小手默认落在目标格中部偏下——第 1 幕那里正好是炉口，火焰道具也画在那儿，
## 两只叠在一起把炉膛糊住。所以每幕可以用 "hand" 给一个格内比例落点。
func _draw_hand(tr: Rect2, st: Dictionary) -> void:
	var hand := UiKit.art("fx/hand")
	if hand == null:
		return
	var at: Array = st.get("hand", [0.62, 0.65])
	var k := clampf(pt / 0.8, 0.0, 1.0)
	var tap := sin(minf(pt * 4.0, PI)) * 10.0
	var pos := Vector2(tr.position.x + tr.size.x * float(at[0]), tr.position.y + tr.size.y * float(at[1]) + tap - (1.0 - k) * 30.0)
	UiKit.draw_sprite(self, hand, pos.x, pos.y, tr.size.y * 0.42)

func _draw_caption(text: String, v: Vector2) -> void:
	# ui/plaque 是整块带花朵装饰的木牌，九宫格拉它会变形，按原始比例 contain 居中画
	var pw := minf(v.x * 0.52, 540.0)
	var ph := pw * 232.0 / 803.0
	var pr := Rect2(v.x / 2.0 - pw / 2.0, 22.0, pw, ph)
	UiKit.draw_tex_contain(self, UiKit.art("ui/plaque"), pr)
	# 牌面实际只有 ~525px 宽，原来按 ph*0.20（31px）排一行 19 个字，
	# 首尾各有一个字挂到牌外的街景上；改成 22px 并允许折行
	var size := 22
	var lines := UiKit.wrap_text(text, pw - 70.0, size, true)
	var mid := pr.position.y + ph / 2.0
	var top := mid - float(lines.size() - 1) * size * 0.75 + size * 0.36
	for i in lines.size():
		UiKit.draw_text_centered(self, pr.position.x + pr.size.x / 2.0, top + float(i) * size * 1.5,
			str(lines[i]), size, Color("#fff2dc"), true)
	UiKit.draw_text_centered(self, pr.position.x + pr.size.x / 2.0, pr.end.y + 20.0,
		"%d / %d" % [stage + 1, STAGES.size()], 14, Color(1, 0.93, 0.78, 0.85), true)

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h["rect"] as Rect2).has_point(event.position):
				_finish()
				return
		_next()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_finish()
