class_name DaySim
extends RefCounted
## 单日营业模拟核心（DaySim）：顾客、排队、点单、烤架/炸锅/可乐机、组装、出餐、
## 柴火炉（劈柴生火）、金币经济、连击与声望。全部逻辑与渲染解耦，可在无窗口环境测试。
## 视图层（Play 界面）调用本类方法并读取公开状态。

signal snark_requested(text: String)
signal popup_requested(text: String, color: Color, slot: int)
signal sfx_requested(name: String)
signal shake_requested()
signal served_event(c: Customer, total: int)
signal customer_spawned(c: Customer)
signal customer_left_event(c: Customer)
signal fire_changed()
signal day_finished()
## 解锁类好消息（今天新菜上菜单 / 声望升到 N★）。以前这些事件全是静默的：
## 玩家只有等客人把新菜点出来，才知道菜单变了。
signal menu_notice_requested(text: String)

const POPUP_GOLD := Color("#ffd23c")
const POPUP_MENU := Color("#9ce88f")
## 被收币人扫走的那笔钱用的飘字色：和 +钱 的金色必须一眼分得开
const POPUP_LOST := Color("#ff8f7a")
## 一份堡最多挤几瓶酱。文案里那个数也从这里取，别在提示语里再写一遍"三"。
const SAUCE_MAX := 3

var day := 1
var _notice_done := false
var _stars_seen := 0
var rng := RandomNumberGenerator.new()

var plan: Array = []
var plan_idx := 0
var spawn_t := 1.2

var queue: Array = []
var leaving: Array = []

var grill: Array = []
var fryer: Array = []
var drink: Dictionary = {"p": -1.0}
var cooked := 0
var assembly: Array = []
var board: Dictionary = {"ing": "", "cuts": 0, "need": 0}
var sauces_used := {}
var sauce_tip := 0
var target := -1
var tray: Dictionary = {}
var drink_jar := 0

var fire := 80.0
var wood := 2
var fire_time := 0.0
var low_warned := false

var today_coins := 0
## 结算后抛在台面上的硬币：{"v":面值,"x":0..1,"y":0..1,"t":抛出后的秒数,"rest":bool}。
## 位置用整屏分数存，视图层再乘成像素——sim 不认分辨率。
var coins: Array = []
## 实收：只有被鼠标划过拾起来的那枚才算钱（拾到才算钱是用户定的规则）。
var coins_collected := 0
## 被收币人扫走的那部分，单独记账，结算页要拿它跟实收并排显示。
var coins_swept := 0
## 收币人（沙威玛式）：sweeper_t < 0 = 没来；0~walk_in 走进来；之后开始一枚一枚往兜里装，
## 每 steal_gap 秒装一枚。装完/走人时兜里的钱才真的算"被收走"。
## 期间玩家点他一下（swat_sweeper）就能把他已经拿走的抢回来，剩下的钱继续留在台面上。
var sweeper_t := -1.0
var sweeper_taken := 0
var sweeper_step := 0.0
var sweeper_done_t := -1.0
var served := 0
var missed := 0
var perfects := 0
var tips_total := 0
var combo := 0
var best_combo_day := 0
var day_time := 0.0
var today_orders: Array = []
var finished := false
var order_seq := 0

# ---------------- 初始化 ----------------
func start(p_day: int, seed_value: int = -1) -> void:
	day = p_day
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	plan = build_day_plan(day)
	plan_idx = 0
	var sp: Dictionary = Config.economy.get("spawn", {})
	spawn_t = float(sp.get("first_delay", 1.2))
	queue = []
	leaving = []
	_setup_grill()
	fryer = _new_fryer()
	drink = {"p": -1.0}
	cooked = 0
	assembly = []
	target = -1
	tray = _empty_tray()
	fire = float(Config.fire.get("fire_start", 80.0))
	wood = int(Config.fire.get("wood_start", 2))
	fire_time = 0.0
	low_warned = false
	today_coins = 0
	coins = []
	coins_collected = 0
	coins_swept = 0
	sweeper_t = -1.0
	served = 0
	missed = 0
	perfects = 0
	tips_total = 0
	combo = 0
	best_combo_day = 0
	day_time = 0.0
	today_orders = []
	finished = false
	order_seq = 0

func _setup_grill() -> void:
	grill = []
	for i in GameState.grill_slots():
		grill.append({"p": -1.0, "flipped": false, "warned": false})

func build_day_plan(p_day: int) -> Array:
	var list: Array = []
	var explicit: Array = Config.day_plan(p_day)
	if not explicit.is_empty():
		for item in explicit:
			list.append((item as Dictionary).duplicate())
	else:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 20260914 + p_day
		var e: Dictionary = Config.economy.get("endless", {})
		var count := int(e.get("base_count", 8)) + int(e.get("per_day_add", 2)) * (p_day - Config.total_days())
		count = mini(count, int(e.get("max_count", 16)))
		for i in count:
			list.append({
				"sp": rng2.randi_range(0, Config.species_count() - 1),
				"burger": _roll_burger(rng2),
				"fries": rng2.randf() < 0.6,
				"drink": rng2.randf() < 0.6
			})
	var bonus := int(GameState.effect_sum("customers_per_day_add"))
	var pool: Array = Config.bonus_pool()
	for i in bonus:
		if pool.is_empty():
			break
		list.append((pool[i % pool.size()] as Dictionary).duplicate())
	return list

func day_patience_scale(p_day: int) -> float:
	var cfg: Dictionary = Config.economy.get("day_patience_scale", {})
	var base := float(cfg.get("base", 0.98))
	var mn := float(cfg.get("min", 0.7))
	if p_day > Config.total_days():
		var e: Dictionary = Config.economy.get("endless", {})
		base = float(e.get("patience_scale", 0.97))
		mn = float(e.get("patience_scale_min", 0.7))
	return maxf(mn, pow(base, maxi(0, p_day - 1)))

func total_plan() -> int:
	return plan.size()

# ---------------- 主循环 ----------------
func tick(dt: float) -> void:
	if finished:
		return
	day_time += dt
	_tick_notices()
	_tick_fire(dt)
	_tick_spawn(dt)
	_tick_customers(dt)
	_tick_stations(dt)
	_tick_coins(dt)
	_tick_leaving(dt)
	_fix_target()
	_check_day_end()

## 解锁播报。不能在 start() 里发——play.on_enter 是先 sim.start() 再 _connect_sim()，
## 那时还没人接信号，所以整段推迟到第一帧。
func _tick_notices() -> void:
	if not _notice_done:
		_notice_done = true
		_stars_seen = GameState.rep_stars()
		var fresh: Array = []
		for b in Config.burgers():
			var bd: Dictionary = b
			# 第 1 天不算"新菜"：那天上的就是开店的那道，播报它只会让人以为漏了什么
			if day > 1 and int(bd.get("unlock_day", 1)) == day:
				fresh.append(str(bd.get("name", "")))
		if not fresh.is_empty():
			menu_notice_requested.emit(Config.misc("menu_added") % "、".join(PackedStringArray(fresh)))
		return
	var stars := GameState.rep_stars()
	if stars <= _stars_seen:
		return
	_stars_seen = stars
	var names: Array = []
	for b in Config.burgers():
		var bd2: Dictionary = b
		if int(bd2.get("unlock_rep", 0)) == stars and int(bd2.get("unlock_day", 1)) <= day:
			names.append(str(bd2.get("name", "")))
	if names.is_empty():
		menu_notice_requested.emit(Config.misc("star_up") % stars)
	else:
		menu_notice_requested.emit(Config.misc("star_unlocked") % [stars, "、".join(PackedStringArray(names))])

func _tick_fire(dt: float) -> void:
	var grace := float(Config.fire.get("grace_seconds", 20.0))
	if day_time < grace:
		return
	var decay := float(Config.fire.get("decay_per_sec", 0.75)) * GameState.effect_mult("fire_decay_mult")
	fire = maxf(0.0, fire - decay * dt)
	var low := float(Config.fire.get("low_threshold", 35.0))
	if fire < low and not low_warned:
		low_warned = true
		_snark_text(str(Config.fire.get("hints", {}).get("low_text", "")))

func _tick_spawn(dt: float) -> void:
	if plan_idx >= plan.size():
		return
	var sp: Dictionary = Config.economy.get("spawn", {})
	if queue.size() >= int(sp.get("max_concurrent", 3)):
		return
	spawn_t -= dt
	if spawn_t <= 0.0:
		_spawn_customer()
		var gap := float(sp.get("gap_base", 6.0))
		spawn_t = gap * rng.randf_range(float(sp.get("gap_jitter_min", 0.8)), float(sp.get("gap_jitter_max", 1.2)))

func _spawn_customer() -> void:
	var spec: Dictionary = plan[plan_idx]
	plan_idx += 1
	var c := Customer.new()
	c.sp = int(spec.get("sp", 0))
	# 计划表按解锁日编排，但声望门槛是运行时才知道的：玩家这周失误多的话，第 5 天可能还只有 3★。
	# 未达标的单必须就地换成一道能做的，否则顾客点出一份拼不出来的堡，变成必走单。
	# 槽位按 Config.tray_slots() 的顺序逐个填——顺序和泛化前那三行赋值一致，
	# 而"点饮料"那次 rng 调用只在真的要饮料时才发生，随机数消耗序列没变。
	for id in Config.tray_slot_ids():
		c.set_want(str(id), _want_from_spec(str(id), spec))
	var base := float(Config.economy.get("patience_base_seconds", 46.0))
	var pm := float(Config.species(c.sp).get("patience_mult", 1.0))
	c.max_patience = base * pm * day_patience_scale(day)
	c.patience = c.max_patience
	c.bob = rng.randf() * TAU
	c.state = "walking"
	c.walk_t = 0.0
	queue.append(c)
	_assign_slots()
	customer_spawned.emit(c)
	sfx_requested.emit("spawn")

## 客流表里那一列 → 这一槽位客人要什么。三种 kind 各自的读法：
##   burger 走 burger_resolved（声望不够就换成做得出的那道）
##   flag   直接收 bool
##   pick   表里写字符串就照它、写 true 就随机挑一杯、写 false 就是不点
## ⚠ 随机数只在 pick 真要点的时候才消耗，所以顺序和泛化前那三行赋值完全一致。
## 槽位 id 和客流表的列名本来就同名（burger / fries / drink），加新菜时保持这个同名约定。
func _want_from_spec(id: String, spec: Dictionary) -> Variant:
	match Config.tray_slot_kind(id):
		"burger":
			return Config.burger_resolved(int(spec.get(id, 0)))
		"pick":
			var v = spec.get(id, false)
			if v is String:
				return str(v)
			if bool(v):
				return str(Config.drink_def(rng.randi_range(0, maxi(Config.drinks().size() - 1, 0))).get("id", "cola"))
			return ""
		_:
			return bool(spec.get(id, false))

func _roll_burger(r: RandomNumberGenerator) -> int:
	var open: Array = Config.open_burger_indices()
	if open.is_empty():
		return 0
	return int(open[r.randi_range(0, open.size() - 1)])

func _assign_slots() -> void:
	var used := {}
	for c in queue:
		if c.slot >= 0:
			used[c.slot] = true
	for c in queue:
		if c.slot < 0:
			for s in 4:
				if not used.has(s):
					c.slot = s
					used[s] = true
					break

func _tick_customers(dt: float) -> void:
	var urge_frac := float(Config.economy.get("urge_patience_frac", 0.35))
	var pat_mult := GameState.effect_mult("patience_decay_mult")
	for c in queue.duplicate():
		var cust: Customer = c
		cust.bob += dt * 3.0
		if cust.say_t > 0.0:
			cust.say_t -= dt
		if cust.greet_t > 0.0:
			cust.greet_t -= dt
		if cust.state == "walking":
			cust.walk_t += dt
			if cust.walk_t >= Customer.WALK_SECONDS:
				cust.state = "waiting"
				if cust.say == "" or cust.say_t <= 0.0:
					cust.say = _pick(Config.species_lines(cust.sp, "greet"))
					cust.say_t = 3.4
		elif cust.state == "waiting":
			cust.patience -= dt * pat_mult
			if not cust.urged and cust.patience < cust.max_patience * urge_frac:
				cust.urged = true
				cust.say = _pick(Config.species_lines(cust.sp, "urge"))
				cust.say_t = 2.6
				sfx_requested.emit("angry")
			if cust.patience <= 0.0:
				_walkout(cust)

func _walkout(c: Customer) -> void:
	c.is_walkout = true
	c.mood = "angry"
	c.say = _pick(Config.species_lines(c.sp, "angry"))
	c.say_t = 2.0
	missed += 1
	GameState.add_rep(-float(Config.economy.get("rep_loss_per_miss", 0.5)))
	combo = 0
	_snark("walkout")
	sfx_requested.emit("walkout")
	_remove_customer(c)

func _remove_customer(c: Customer) -> void:
	var i := queue.find(c)
	if i >= 0:
		queue.remove_at(i)
		if target == i:
			target = -1
			if not assembly.is_empty():
				refund_assembly()
		elif target > i:
			target -= 1
	c.state = "leaving"
	c.out_t = 0.0
	c.out_dir = -1 if (c.is_walkout and c.slot <= 0) else 1
	leaving.append(c)
	_assign_slots()
	customer_left_event.emit(c)

func refund_assembly() -> void:
	for k in assembly:
		if str(k) == "patty":
			cooked += 1
		else:
			GameState.inv_add(str(k), 1)
	assembly = []
	sauces_used = {}
	sauce_tip = 0
	if str(board["ing"]) != "":
		GameState.inv_add(str(board["ing"]), 1)
		board = {"ing": "", "cuts": 0, "need": 0}

func _tick_stations(dt: float) -> void:
	var gcfg := Config.cook("grill")
	var full_g := float(gcfg.get("full_seconds", 6.2))
	var burn_g := float(gcfg.get("burn_auto", 1.3))
	var speed_g := _speed_hot() * GameState.effect_mult("cook_speed_mult")
	# 自动翻面夹：到点自己翻，玩家只需要在金黄窗口起锅那一下
	var auto_turn := int(GameState.effect_sum("auto_turn")) > 0
	var flip_g := float(gcfg.get("flip_min", 0.4))
	for g in grill:
		if float(g["p"]) >= 0.0:
			g["p"] = float(g["p"]) + dt / full_g * speed_g
			if auto_turn and not bool(g["flipped"]) and float(g["p"]) >= flip_g:
				g["flipped"] = true
				sfx_requested.emit("flip")
			if float(g["p"]) >= burn_g:
				g["p"] = burn_g
				if not bool(g["warned"]):
					g["warned"] = true
					_snark("burnt")
					sfx_requested.emit("burnt")
	var fcfg := Config.cook("fryer")
	var full_f := float(fcfg.get("full_seconds", 5.0))
	var burn_f := float(fcfg.get("burn_auto", 1.35))
	for b in fryer:
		var bd: Dictionary = b
		if float(bd["p"]) < 0.0:
			continue
		bd["p"] = float(bd["p"]) + dt / full_f * _speed_hot() * GameState.effect_mult("cook_speed_mult")
		if float(bd["p"]) >= burn_f:
			bd["p"] = burn_f
			if not bool(bd["warned"]):
				bd["warned"] = true
				_snark("fryburnt")
				sfx_requested.emit("burnt")
	var dcfg := Config.cook("drink")
	var full_d := float(dcfg.get("full_seconds", 2.4))
	var over_d := float(dcfg.get("overflow_auto", 1.12))
	if float(drink["p"]) >= 0.0:
		drink["p"] = float(drink["p"]) + dt / full_d * GameState.effect_mult("cook_speed_mult")
		if float(drink["p"]) >= over_d:
			drink["p"] = -1.0
			_snark("spill")
			sfx_requested.emit("spill")

func _tick_leaving(dt: float) -> void:
	for c in leaving.duplicate():
		var cust: Customer = c
		cust.out_t += dt
		if cust.out_t > 1.6:
			leaving.erase(cust)

## 换目标一律走这里：手里叠了一半的东西是**上一道配方**的层，换人之后很可能再也凑不成
## 任何一只堡（新配方更短就直接卡死在 stack_full），所以换人的同时把料退回货架。
## 用户报的"同时做两个汉堡，两个汉堡的食材只出一个汉堡"就是这个死局。
func _set_target(i: int) -> void:
	if i == target:
		return
	if not assembly.is_empty():
		refund_assembly()
		_snark_text(str(Config.misc("swap_refund")))
	target = i

func _fix_target() -> void:
	if target >= queue.size():
		_set_target(-1)
	if target >= 0 and target < queue.size():
		var c: Customer = queue[target]
		if c.state != "waiting":
			_set_target(-1)

func _check_day_end() -> void:
	if finished:
		return
	if plan_idx >= plan.size() and queue.is_empty() and leaving.is_empty():
		finished = true
		# 打烊时台面上还没捡的钱**归玩家**（用户定的规则）：最后一个客人之后不再有收币人。
		bank_leftover_at_day_end()
		day_finished.emit()

func _speed_hot() -> float:
	var s := GameState.effect_mult("cook_speed_mult")
	if fire < float(Config.fire.get("low_threshold", 35.0)):
		s *= float(Config.fire.get("low_speed_mult", 0.6))
	return s

# ---------------- 查询 ----------------
func can_cook() -> bool:
	return fire >= float(Config.fire.get("min_to_cook", 8.0))

func fire_low() -> bool:
	return fire < float(Config.fire.get("low_threshold", 35.0))

## 托盘的一份空格子。`burger_tip` 跟着**这一份堡**走：酱是挤在组装过程中的，
## 以前在堡做完那一刻就把 sauce_tip 清零，结算时读到的永远是 0（等于酱料加小费这条
##  advertised 机制根本没生效）；而先做下一个堡再上菜的话，上一单还会拿到下一单的酱钱。
func _empty_tray() -> Dictionary:
	return Config.empty_tray()

## 托盘上这件是不是这位要的。"对上"按 kind 各有三种判法：
##   burger 要下标相等、pick 要选项 id 相等、flag 只要有就算。
## 以前这里是三条 match 分支各写一遍字段名，加一道菜就得再补一条。
func _tray_has(c: Customer, kind: String) -> bool:
	match Config.tray_slot_kind(kind):
		"burger":
			return int(tray[kind]) >= 0 and int(tray[kind]) == int(c.want(kind)) \
				and not bool(c.got.get(kind, false))
		"pick":
			return str(tray[kind]) != "" and str(tray[kind]) == str(c.want(kind))
		_:
			return bool(tray[kind])

func _take_tray(kind: String) -> void:
	tray[kind] = Config.tray_blank(kind)
	# 背小费的那一件（现在是堡）收走时，把挂在这一份上的酱钱一起清掉
	if Config.tip_slot() == kind:
		tray[kind + "_tip"] = 0

## 这位还缺、而荷叶上正好有的那一件（按 堡→饮料→薯条 之外的"客人点单顺序"给）。
## 视图层拿它决定手里提的是哪件、点一下客人递的是哪件。
func next_kind_for(c: Customer) -> String:
	for k in c.missing_kinds():
		if _tray_has(c, str(k)):
			return str(k)
	return ""

func tray_has_for(c: Customer) -> bool:
	for k in c.missing_kinds():
		if _tray_has(c, str(k)):
			return true
	return false

func first_waiting() -> int:
	for i in queue.size():
		var c: Customer = queue[i]
		if c.state == "waiting":
			return i
	return -1

func next_need_ing() -> String:
	if target < 0 or target >= queue.size():
		return ""
	var c: Customer = queue[target]
	if c.state != "waiting":
		return ""
	var stack: Array = Config.burger(c.burger_idx()).get("stack", [])
	if assembly.size() >= stack.size():
		return ""
	return str(stack[assembly.size()])

# ---------------- 柴火 ----------------
func add_wood() -> bool:
	if wood <= 0:
		_snark("nowood")
		return false
	wood -= 1
	fire = minf(float(Config.fire.get("fire_max", 100.0)), fire + float(Config.fire.get("add_wood_fire", 22.0)))
	fire_changed.emit()
	sfx_requested.emit("wood_add")
	return true

func apply_chop(gained: int, all_hit: bool) -> void:
	wood = mini(int(Config.fire.get("wood_max", 10)), wood + gained)
	_snark("chophit" if all_hit else "chopmiss")
	fire_changed.emit()

# ---------------- 工位交互 ----------------
func tap_grill(i: int) -> void:
	if i < 0 or i >= grill.size():
		return
	var cfg := Config.cook("grill")
	var g: Dictionary = grill[i]
	var p := float(g["p"])
	if p < 0.0:
		if not can_cook():
			_snark_text(str(Config.fire.get("hints", {}).get("min_text", "")))
			shake_requested.emit()
			return
		if not GameState.inv_use("patty"):
			_snark("nostock")
			shake_requested.emit()
			return
		g["p"] = 0.0
		g["flipped"] = false
		g["warned"] = false
		sfx_requested.emit("place")
		return
	if p >= float(cfg.get("burn_tap", 1.18)):
		g["p"] = -1.0
		_snark("burnt")
		sfx_requested.emit("burnt")
		return
	if not bool(g["flipped"]):
		if p >= float(cfg.get("flip_min", 0.4)):
			g["flipped"] = true
			sfx_requested.emit("flip")
		else:
			_snark("earlyflip")
			shake_requested.emit()
		return
	var win: Array = cfg.get("window", [0.78, 1.02])
	if p >= float(win[0]) and p <= float(win[1]):
		g["p"] = -1.0
		cooked += 1
		sfx_requested.emit("ding")
		if cooked == 1 and rng.randf() < 0.6:
			_snark("perfect")
	elif p < float(win[0]):
		_snark("earlyflip")
		shake_requested.emit()

## 每只炸篮一份状态。篮子数来自 `economy.cooking.fryer.baskets`（现在是 1）。
## 泛化到多篮之前这里是单个 Dictionary，读它的人到处写 `fryer["p"]`。
## `item` 是这只篮现在炸的是哪样（`sides` 里的 id），空篮为 ""。
## 以前"炸炉出来的就是薯条"是写死在函数里的，加第二样菜就得整段翻。
func _new_fryer(count: int = -1) -> Array:
	var n := Config.fryer_baskets() if count < 0 else count
	var out: Array = []
	for i in maxi(1, n):
		out.append({"p": -1.0, "warned": false, "item": ""})
	return out

## 这只篮现在炸的是什么（空篮返回 ""）。视图和 bot 都从这儿取，别再猜"就是薯条"。
func fryer_item(i: int = 0) -> String:
	if i < 0 or i >= fryer.size():
		return ""
	return str((fryer[i] as Dictionary)["item"])

func fryer_p(i: int = 0) -> float:
	if i < 0 or i >= fryer.size():
		return -1.0
	return float((fryer[i] as Dictionary)["p"])

## 有没有哪只篮子正在炸（HUD 那枚脉冲用的就是这个，不是"0 号篮"）
func fryer_busy() -> bool:
	for b in fryer:
		if float((b as Dictionary)["p"]) >= 0.0:
			return true
	return false

## 这一次点击该落在哪只篮子：先起锅窗口内的、再糊掉的、再空篮、最后退回任何还在炸的。
## **只有一只篮子时这四个分支必然都指到 0 号**，所以判路和泛化前那条完全一致——
## 这是这一步能宣称"行为零变化"的依据，不是靠读代码看出来的是靠 trace 比出来的。
func _fryer_focus() -> int:
	var cfg := Config.cook("fryer")
	var win: Array = cfg.get("window", [0.72, 1.0])
	var burn_tap := float(cfg.get("burn_tap", 1.22))
	for i in fryer.size():
		var p := float((fryer[i] as Dictionary)["p"])
		if p >= float(win[0]) and p <= float(win[1]):
			return i
	for i in fryer.size():
		if float((fryer[i] as Dictionary)["p"]) >= burn_tap:
			return i
	for i in fryer.size():
		if float((fryer[i] as Dictionary)["p"]) < 0.0:
			return i
	for i in fryer.size():
		if float((fryer[i] as Dictionary)["p"]) >= 0.0:
			return i
	return -1

## 点炸炉。`item` 是要下的料在 `sides` 里的 id（现在是 "fries"，将来还有 "drumstick"）。
## 不传就是泛化前那唯一的产品：薯条。烧哪种原料由 `sides[<item>].ingredient` 说，
## 起锅往荷叶哪一格也按 `<item>` 放——这两处以前都写死成土豆和薯条。
func tap_fryer(item: String = "fries") -> void:
	var cfg := Config.cook("fryer")
	var bi := _fryer_focus()
	if bi < 0:
		return
	var b: Dictionary = fryer[bi]
	var p := float(b["p"])
	if p < 0.0:
		if not can_cook():
			_snark_text(str(Config.fire.get("hints", {}).get("min_text", "")))
			shake_requested.emit()
			return
		# 没登记原料的小菜不该"白炸"：宁可报没货，也别把空字符串喂给 inv_use
		var ing := str(Config.side(item).get("ingredient", ""))
		if ing == "" or not GameState.inv_use(ing):
			_snark("nostock")
			shake_requested.emit()
			return
		b["p"] = 0.0
		b["warned"] = false
		b["item"] = item
		sfx_requested.emit("place")
		return
	if p >= float(cfg.get("burn_tap", 1.22)):
		b["p"] = -1.0
		b["item"] = ""
		_snark("fryburnt")
		sfx_requested.emit("burnt")
		return
	var win: Array = cfg.get("window", [0.72, 1.0])
	if p >= float(win[0]) and p <= float(win[1]):
		var it := str(b["item"])
		if it == "":
			# 有进度却没登记炸的是什么（手摆状态的测试、或将来漏了赋值都会到这儿）。
			# 不拦的话下一句会往荷叶写 tray[""] = true，凭空多出一格谁也画不出来的东西。
			b["p"] = -1.0
			return
		if bool(tray.get(it, false)):
			_snark("trayfull")
			return
		b["p"] = -1.0
		b["item"] = ""
		tray[it] = true
		sfx_requested.emit("ding")
	elif p < float(win[0]):
		shake_requested.emit()
		_snark_text(Config.misc("fry_notyet"))
	else:
		shake_requested.emit()
		_snark_text(Config.misc("fry_soon"))

func tap_drink(jar: int = -1) -> void:
	var cfg := Config.cook("drink")
	var p := float(drink["p"])
	if jar >= 0:
		if p < 0.0:
			drink_jar = jar
		elif jar != drink_jar:
			_snark_text(str(Config.misc("drink_pouring")))
			return
	var did := str(Config.drink_def(drink_jar).get("id", "cola"))
	if p < 0.0:
		if not GameState.inv_use("drink"):
			_snark("nostock")
			shake_requested.emit()
			return
		drink["p"] = 0.0
		sfx_requested.emit("pour")
		return
	if p >= float(cfg.get("overflow_tap", 1.06)):
		drink["p"] = -1.0
		_snark("spill")
		sfx_requested.emit("angry")
		return
	var win: Array = cfg.get("window", [0.62, 0.95])
	if p >= float(win[0]) and p <= float(win[1]):
		if str(tray["drink"]) != "":
			_snark("trayfull")
			return
		drink["p"] = -1.0
		tray["drink"] = did
		sfx_requested.emit("ding")
	elif p < float(win[0]):
		drink["p"] = -1.0
		_snark_text(Config.misc("drink_too_low"))
		shake_requested.emit()
	else:
		shake_requested.emit()
		_snark_text(Config.misc("drink_soon"))

func tap_shelf(ing: String) -> void:
	# 案板上还压着食材时，再点同一种就是下刀，不会重复扣库存
	if str(board["ing"]) != "":
		if str(board["ing"]) == ing:
			slice_board()
		else:
			# 这条 return 以前一声不出：点别的食材像"点了没反应"，其实是要先切完
			_snark_text(Config.misc("board_busy") % Config.ingredient_name(str(board["ing"])))
		return
	if target < 0:
		var t := first_waiting()
		if t >= 0:
			_set_target(t)
		else:
			_snark("noorder")
			return
	if target >= queue.size():
		_set_target(-1)
		_snark("noorder")
		return
	var c: Customer = queue[target]
	var rec := Config.burger(c.burger_idx())
	var stack: Array = rec.get("stack", [])
	if assembly.size() >= stack.size():
		_snark_text(Config.misc("stack_full") % str(rec.get("name", "")))
		return
	var need := str(stack[assembly.size()])
	if need != ing:
		_snark("wrong")
		shake_requested.emit()
		sfx_requested.emit("angry")
		return
	if ing == "patty":
		if cooked <= 0:
			_snark("rawpatty")
			shake_requested.emit()
			return
		cooked -= 1
	else:
		if not GameState.inv_use(ing):
			_snark("nostock")
			shake_requested.emit()
			return
	var cuts := Config.ingredient_cuts(ing)
	if cuts > 0:
		var need_cuts := maxi(1, int(round(float(cuts) * GameState.effect_mult("cut_need_mult"))))
		board = {"ing": ing, "cuts": 0, "need": need_cuts}
		sfx_requested.emit("place")
		return
	_finish_assembly(ing)

## 挤酱：只有正在组装的汉堡能加酱，每种酱一次、最多加三种，加得越多小费越高。
func apply_sauce(i: int) -> bool:
	var defs: Array = Config.sauces()
	if i < 0 or i >= defs.size():
		return false
	if assembly.is_empty() and str(board["ing"]) == "":
		_snark("tray_empty")
		return false
	var sid := str(defs[i].get("id", i))
	if sauces_used.has(sid):
		_snark_text(str(Config.misc("sauce_once")))
		return false
	if sauces_used.size() >= SAUCE_MAX:
		_snark_text(Config.misc("sauce_full") % SAUCE_MAX)
		return false
	sauces_used[sid] = true
	sauce_tip += int(defs[i].get("tip_bonus", 2))
	sfx_requested.emit("pour")
	return true

## 案板切割：一次点击或一次划过算一刀，够刀数才落进组装层。
func slice_board() -> bool:
	if str(board["ing"]) == "":
		return false
	board["cuts"] = int(board["cuts"]) + 1
	sfx_requested.emit("chop")
	if int(board["cuts"]) >= int(board["need"]):
		var ing := str(board["ing"])
		board = {"ing": "", "cuts": 0, "need": 0}
		_finish_assembly(ing)
	return true

func _finish_assembly(ing: String) -> void:
	var c: Customer = queue[target]
	var stack: Array = Config.burger(c.burger_idx()).get("stack", [])
	assembly.append(ing)
	sfx_requested.emit("place")
	if assembly.size() == stack.size():
		var bs := Config.burger_slot()
		if int(tray[bs]) >= 0:
			_snark("trayfull")
			refund_assembly()
			return
		tray[bs] = c.burger_idx()
		# 这一份堡的酱钱跟着堡存进荷叶，不清零成"下一个堡的"——以前在这里清掉，
		# 结算时读到的 sauce_tip 恒为 0，"挤酱加小费"等于没做。
		tray[bs + "_tip"] = sauce_tip
		assembly = []
		sauces_used = {}
		sauce_tip = 0
		sfx_requested.emit("ding")
		if target < queue.size() and queue[target] == c:
			var nx := -1
			for j in queue.size():
				var cc: Customer = queue[j]
				if cc.state == "waiting" and int(tray[bs]) != cc.burger_idx():
					nx = j
					break
			if nx >= 0:
				target = nx

func tap_customer(c: Customer) -> void:
	if c.state != "waiting":
		# 客人在走进来/走开这两段里，整副身体都是热区，点下去一声不响会被读成"点了没反应"
		_snark_text(str(Config.misc("cust_walking" if c.state == "walking" else "cust_gone")))
		return
	var k := next_kind_for(c)
	if k != "":
		deliver(c, k)
		return
	var idx := queue.find(c)
	if idx >= 0:
		if target != idx and not assembly.is_empty():
			refund_assembly()
			_snark_text(Config.misc("swap_order"))
		target = idx
		sfx_requested.emit("tap")
	elif int(tray[Config.burger_slot()]) >= 0:
		_snark("nomatch")

## 一物一交付：把荷叶上**一件**成品递给这位客人，收齐他点的全部几件才走结算。
## 以前是一整盘一次给（try_serve），三样全做完才交得出去——手慢的话薯条都糊了还在等面包。
func deliver(c: Customer, kind: String) -> bool:
	if c.state != "waiting":
		_snark_text(str(Config.misc("cust_walking" if c.state == "walking" else "cust_gone")))
		return false
	if not c.wants(kind):
		_snark("nomatch")
		shake_requested.emit()
		sfx_requested.emit("angry")
		return false
	if bool(c.got.get(kind, false)):
		_snark_text(Config.misc("already_got") % _item_label(c, kind))
		return false
	if not _tray_has(c, kind):
		_snark_text(Config.misc("tray_no_kind") % _item_label(c, kind))
		return false
	var label := _item_label(c, kind)
	if Config.tip_slot() == kind:
		# 用 get 而不是直接取键：测试里会手摆 tray 字典，少一个键就会让这一句抛错、
		# 整个 deliver 原地断掉（GDScript 的 SCRIPT ERROR 会中止当前函数）。
		c.tip_bonus += int(tray.get(kind + "_tip", 0))
	_take_tray(kind)
	c.got[kind] = true
	sfx_requested.emit("deliver")
	popup_requested.emit(label, POPUP_MENU, c.slot if c.slot >= 0 else 0)
	if c.got_all():
		_settle_order(c)
	return true

## 这一格现在是不是空的（荷叶上没这一件）。
func _slot_blank(id: String, v) -> bool:
	match Config.tray_slot_kind(id):
		"burger":
			return int(v) < 0
		"pick":
			return str(v) == ""
		_:
			return not bool(v)

## 荷叶上此刻有没有这一件（不看谁点的）。视图层画荷叶、算"盘子空不空"都问这个，
## 免得把上面那段 kind 判法在第二个文件里再抄一遍。
func tray_has_slot(id: String) -> bool:
	return not _slot_blank(id, tray.get(id, Config.tray_blank(id)))

## 递出去那件的报名：荷叶上有这一件就按荷叶上那件报（"手上这杯是橙汁"），
## 没有才按客人点的报——这个区别在 `tray_no_kind` 那句文案上看得到，别顺手统一掉。
## ⚠ kind=flag 这一支读的是 `Config.misc("kind_<id>")`，和票面上 `Customer.item_label()`
##   读的 `sides.name` **不是同一个词**（票上"炸薯条"、这里"薯条"）。那是泛化之前就
##   存在的双套叫法，本轮只动结构、没去改文案。
func _item_label(c: Customer, kind: String) -> String:
	var v = tray.get(kind, Config.tray_blank(kind))
	if _slot_blank(kind, v):
		v = c.want(kind)
	match Config.tray_slot_kind(kind):
		"burger":
			return str(Config.burger(int(v)).get("name", "汉堡"))
		"pick":
			for d in Config.drinks():
				if str((d as Dictionary).get("id", "")) == str(v):
					return str((d as Dictionary).get("name", "饮料"))
		_:
			pass
	return str(Config.misc("kind_" + kind))


func _settle_order(c: Customer) -> void:
	var rec := Config.burger(c.burger_idx())
	var price := int(rec.get("price", 0))
	var frac := c.patience_frac()
	# 声望星级挂小费：3★（开局水位）= ×1.0，5★=×1.45，掉到 2★ 以下开始扣。
	var rep_mult := Config.rep_tip_mult(GameState.rep_stars())
	var tip := int(round(float(price) * float(Config.economy.get("tip_rate", 0.5)) * frac * float(Config.species(c.sp).get("tip_mult", 1.0)) * rep_mult))
	# 酱料钱在递出那份堡时就转到 c.tip_bonus 上了（见 deliver），这里不能再读全局的
	# sauce_tip——那时它已经是"下一个正在做的堡"的累计值。
	tip += int(GameState.effect_sum("tip_flat_bonus")) + c.tip_bonus
	var perfect := frac > float(Config.economy.get("perfect_patience_frac", 0.6))
	if perfect:
		combo += 1
		perfects += 1
		best_combo_day = maxi(best_combo_day, combo)
		if combo > GameState.best_combo:
			GameState.best_combo = combo
	else:
		combo = 0
	var combo_bonus := combo if (perfect and combo >= int(Config.economy.get("combo_min", 2))) else 0
	var total := price + tip + combo_bonus
	# 钱不再直接进钱包：先抛到台面上，鼠标划过才算收到（拾到才算钱）。
	# 所以钱包的增量、台账的"实收"和订单行的 nominal total 是三个数，
	# 由 coins_collected / coins_swept 这条账对平。
	toss_coins(total)
	GameState.total_served += 1
	tips_total += tip
	served += 1
	order_seq += 1
	GameState.add_rep(float(Config.economy.get("rep_gain_per_serve", 0.15)))
	var pop_text := "+%d" % total
	if combo_bonus > 0:
		pop_text += "  连击x%d" % combo
	popup_requested.emit(pop_text, POPUP_GOLD, c.slot if c.slot >= 0 else 0)
	# 连击那一声**顶掉**结算声，不是叠在上面：两条都是三音上行琶音，
	# 同帧一起放只听得见一团糊，连击反而更没存在感。
	if combo_bonus > 0:
		sfx_requested.emit("combo")
	else:
		sfx_requested.emit("settle")
	c.mood = "happy"
	c.say = _pick(Config.species_lines(c.sp, "happy"))
	c.say_t = 2.6
	if frac > 0.55:
		_snark("serve")
	elif rng.randf() < 0.5:
		_snark("urge")
	today_orders.append({
		"seq": order_seq,
		"day": day,
		"customer": str(Config.species(c.sp).get("name", "")),
		"items": c.order_items(),
		"price": price,
		"tip": tip,
		"rep_mult": snappedf(rep_mult, 0.01),
		"combo_bonus": combo_bonus,
		"total": total,
		"patience_frac": snappedf(frac, 0.01),
		"time": Time.get_datetime_string_from_system(false, true)
	})
	# 这里**不清托盘**：逐件交付之后，荷叶上没递出去的薯条/饮料要留给下一位，
	# 一次整盘清空会把别人做好的东西凭空抹掉。
	_remove_customer(c)
	served_event.emit(c, total)
	_check_day_end()

func tray_has() -> bool:
	# 以前是三格各写一句 or；现在问注册表"有没有哪一格不空"
	for id in Config.tray_slot_ids():
		if not _slot_blank(str(id), tray.get(str(id), Config.tray_blank(str(id)))):
			return true
	return false

# ---------------- 抛硬币 / 划过拾取 / 收币客人 ----------------

## 把这一单的应付金额拆成硬币抛到台面上：银币一枚 1、金币一枚 10。
## 位置存整屏分数（视图层再乘成像素），t 是抛出后的秒数，用来算抛物线。
func toss_coins(total: int) -> void:
	var cc := Config.coins_cfg()
	var gv := maxi(1, int(cc.get("gold_value", 10)))
	var sv := maxi(1, int(cc.get("silver_value", 1)))
	var cap := maxi(4, int(cc.get("max_per_toss", 40)))
	var list: Array = []
	var rest := int(total)
	while rest >= gv:
		list.append(gv)
		rest -= gv
	while rest >= sv:
		list.append(sv)
		rest -= sv
	# 超过上限就并枚，不丢钱：多出来的面值合成一枚大币（画出来还是金币样子）
	if list.size() > cap:
		var extra := 0
		for i in range(cap - 1, list.size()):
			extra += int(list[i])
		list.resize(cap - 1)
		list.append(extra)
	var anchor := float(cc.get("anchor_x", 0.52))
	var spread := float(cc.get("spread_x", 0.19))
	var band: Array = cc.get("rest_band", [0.775, 0.815])
	var n := list.size()
	for i in n:
		var f := float(i) / float(maxi(n - 1, 1))
		coins.append({
			"v": int(list[i]),
			"x": anchor + (f - 0.5) * spread + rng.randf_range(-0.005, 0.005),
			"y": lerpf(float(band[0]), float(band[1]), rng.randf()),
			"t": -float(i) * 0.035,
			"rest": false,
			"age": 0.0,
		})
	sfx_requested.emit("coin")

## 拾起第 i 枚——这才是真的进钱包。视图层鼠标命中后调它。
func pick_coin(i: int) -> int:
	if i < 0 or i >= coins.size():
		return 0
	var c: Dictionary = coins[i]
	coins.remove_at(i)
	var v := int(c["v"])
	GameState.add_coins(v)
	today_coins += v
	coins_collected += v
	sfx_requested.emit("coin_pick")
	return v

## 一次收干净。自动玩家和用例走这条，真人是靠鼠标划过拾取的。
func collect_all() -> int:
	var sum := 0
	while not coins.is_empty():
		sum += pick_coin(0)
	return sum

func _tick_coins(dt: float) -> void:
	var cc := Config.coins_cfg()
	var toss := maxf(0.05, float(cc.get("toss_seconds", 0.5)))
	var after := float(cc.get("sweep_after", 6.0))
	for c in coins:
		var cd: Dictionary = c
		cd["t"] = float(cd["t"]) + dt
		if bool(cd["rest"]):
			cd["age"] = float(cd["age"]) + dt
		elif float(cd["t"]) >= toss:
			cd["rest"] = true
			cd["age"] = 0.0
	if sweeper_t >= 0.0:
		_tick_sweeper(dt, cc)
		return
	# 第 collector_from_day 天起才有收币人：第 1 天玩家还在学做堡，先不抢钱
	if day < int(cc.get("collector_from_day", 2)) or after <= 0.0:
		return
	for c in coins:
		var cd2: Dictionary = c
		if bool(cd2["rest"]) and float(cd2["age"]) >= after:
			sweeper_t = 0.0
			sweeper_taken = 0
			sweeper_step = 0.0
			sweeper_done_t = -1.0
			_snark_text(str(Config.misc("sweep_coming")))
			sfx_requested.emit("sweep_in")
			return

func _tick_sweeper(dt: float, cc: Dictionary) -> void:
	sweeper_t += dt
	if sweeper_t < maxf(0.2, float(cc.get("sweep_walk", 1.2))):
		return            # 还在走进来，手没伸出来
	if coins.is_empty():
		# 兜里的钱要等他走出画面才算真的丢了——这期间点他还能抢回来
		sweeper_done_t = maxf(0.0, sweeper_done_t) + dt
		if sweeper_done_t >= maxf(0.2, float(cc.get("leave_after", 0.9))):
			_finish_sweep()
		return
	sweeper_step += dt
	var gap := maxf(0.08, float(cc.get("steal_gap", 0.45)))
	while sweeper_step >= gap and not coins.is_empty():
		sweeper_step -= gap
		var cd: Dictionary = coins[0]
		sweeper_taken += int(cd["v"])
		coins.remove_at(0)
		sfx_requested.emit("steal")

## 收币人走远了：他兜里那些才算"被收走"
func _finish_sweep() -> void:
	sweeper_t = -1.0
	sweeper_done_t = -1.0
	sweeper_step = 0.0
	if sweeper_taken > 0:
		coins_swept += sweeper_taken
		popup_requested.emit("-%d" % sweeper_taken, POPUP_LOST, 0)
		_snark_text(Config.misc("coins_swept") % sweeper_taken)
		sfx_requested.emit("sweep")
		sweeper_taken = 0

## 玩家点收币人：他把已经拿走的钱全吐出来，台面上剩下的继续归玩家捡。
func swat_sweeper() -> int:
	if sweeper_t < 0.0:
		return 0
	var back := sweeper_taken
	sweeper_taken = 0
	sweeper_t = -1.0
	sweeper_done_t = -1.0
	sweeper_step = 0.0
	if back > 0:
		GameState.add_coins(back)
		today_coins += back
		coins_collected += back
		_snark_text(Config.misc("sweeper_swat") % back)
		popup_requested.emit("+%d" % back, POPUP_GOLD, 0)
	sfx_requested.emit("thud")
	return back

## 打烊：最后一个客人之后，台面上没捡的钱（连同收币人手里还没来得及算走的）全归玩家。
func bank_leftover_at_day_end() -> void:
	if sweeper_taken > 0:
		GameState.add_coins(sweeper_taken)
		today_coins += sweeper_taken
		coins_collected += sweeper_taken
		sweeper_taken = 0
	sweeper_t = -1.0
	sweeper_done_t = -1.0
	sweeper_step = 0.0
	collect_all()

## 倒掉：托盘上那份是已经把食材成本烧掉的成品，没有顾客要就只能丢回灶膛重做。
## 不退款——沉没成本就是这一动作的代价。
func dump_tray() -> bool:
	if not tray_has():
		_snark_text(Config.misc("tray_empty"))
		return false
	# 这里原来手抄了一份 {"burger":-1,"fries":false,"drink":""}，**少了 burger_tip**。
	# 今天看不出差别（读它的人一律带默认值），但等荷叶上有第四件时，这一行会把
	# 新那件留在盘上——倒一次盘子等于白得一份小菜。所以走注册表，不再手抄。
	tray = _empty_tray()
	_snark("dumped")
	sfx_requested.emit("burnt")
	shake_requested.emit()
	return true

# ---------------- 结算数据 ----------------
func day_stats() -> Dictionary:
	return {
		"day": day,
		"coins": today_coins,
		"served": served,
		"missed": missed,
		"perfects": perfects,
		"tips": tips_total,
		## 实收与被收走分开记：coins 这一列从此是"拾到手里的钱"，
		## 各单 nominal 之和在 today_orders 里，对账式是 sum(total) == collected + swept。
		"collected": coins_collected,
		"swept": coins_swept,
		"combo_peak": best_combo_day,
		"planned": plan.size(),
		"rep_after": snappedf(GameState.rep, 0.01)
	}

func settlement_record() -> Dictionary:
	var rec := day_stats()
	rec["orders_count"] = today_orders.size()
	rec["saved_at"] = Time.get_datetime_string_from_system(false, true)
	return rec

# ---------------- 内部工具 ----------------
func _pick(arr: Array) -> String:
	if arr.is_empty():
		return ""
	return str(arr[rng.randi() % arr.size()])

func _snark(cat: String) -> void:
	var lines := Config.snark_lines(cat)
	if lines.is_empty():
		return
	snark_requested.emit(_pick(lines))

func _snark_text(t: String) -> void:
	if t != "":
		snark_requested.emit(t)
