class_name SimBot
extends RefCounted
## 自动玩家：驱动 DaySim 完成营业日（用于冒烟 / 自动巡演 / 耐久测试）。
## 行为对齐正常人类玩家：控火、煎肉、炸薯条、打可乐、选单、叠堡、上餐。

var sim: DaySim
var t := 0.0
## 失误率：>0 时按这个概率把手上那盘对的单倒掉重做——人类玩家就是在这里流失客人和食材的。
## 默认 0，冒烟/巡演/耐久仍按完美通关跑；只有经济类判据会调它。
var miss_frac := 0.0
var rng := RandomNumberGenerator.new()
## 手速上限（次/秒），0=不限。默认不限是因为冒烟/巡演跑的是"逻辑步长"，
## 卡的是流程通不通；但判难度时必须掐住手速，否则一个每秒点 20 下的机器人
## 会把"人类根本来不及"的日子读成完美通关。
var aps := 0.0
var _budget := 0.0

func step(dt: float) -> void:
	if sim == null or sim.finished:
		return
	t += dt
	if aps > 0.0:
		_budget = minf(_budget + dt * aps, 2.0)
		if _budget < 1.0:
			return
		_budget -= 1.0

	# 0) 台面上的硬币先捡干净：拾到才算钱，bot 不捡就等于每单都在漏钱，
	#    经济类判据会读成"这关赚不到钱"（那是 bot 缺动作，不是难度问题）。
	if not sim.coins.is_empty():
		sim.collect_all()

	# 0) 柴火管理
	if sim.fire < 50.0:
		if sim.wood > 0:
			sim.add_wood()
		else:
			sim.apply_chop(4, true)

	# 1) 能递就递一件：逐件交付之后，不再要求"整盘正好等于整单"
	for c in sim.queue:
		if c.state != "waiting":
			continue
		var k := sim.next_kind_for(c)
		if k == "":
			continue
		if miss_frac > 0.0 and rng.randf() < miss_frac:
			sim.dump_tray()
			return
		sim.deliver(c, k)
		return

	# 1b) 荷叶上没有一件是等待中的客人还要的：真人会拖到灶膛丢掉，bot 以前不会——
	#     第一章第 4 天就是这么堵死的（举着一份没人要的堡，后面整天的单全卡住）。
	#     逐件交付之后判据要跟着换：不是"这只堡没人要"，而是"整张荷叶没人要"，
	#     因为只剩薯条/可乐时它们随时可以给下一位点配菜的人。
	var wanted := false
	for c in sim.queue:
		if c.state == "waiting" and sim.next_kind_for(c) != "":
			wanted = true
			break
	if sim.tray_has() and not wanted:
		sim.dump_tray()
		return

	# 2) 确保有目标订单
	if sim.target < 0:
		var fi := sim.first_waiting()
		if fi >= 0:
			sim.tap_customer(sim.queue[fi])

	var target: Customer = null
	if sim.target >= 0 and sim.target < sim.queue.size():
		target = sim.queue[sim.target]

	# 3) 烤架：保持若干肉饼在产
	var busy := 0
	for g in sim.grill:
		if float(g["p"]) >= 0.0:
			busy += 1
	var placed := false
	for gi in sim.grill.size():
		var g: Dictionary = sim.grill[gi]
		var p := float(g["p"])
		if p >= 0.0:
			if not bool(g["flipped"]):
				var flip_min := float(Config.cook("grill").get("flip_min", 0.4))
				if p >= flip_min and p < 1.15:
					sim.tap_grill(gi)
			else:
				var win: Array = Config.cook("grill").get("window", [0.78, 1.02])
				if p >= float(win[0]) and p <= float(win[1]):
					sim.tap_grill(gi)
				elif p >= 1.18:
					sim.tap_grill(gi)
		else:
			if not placed and sim.cooked + busy < 3 and sim.can_cook():
				# 生饼是烤架唯一的原料，烧完就又成了"端着半只堡等一块饼"的死局：
				# 缺料补货那条我当初只接了货架和土豆/可乐，漏了这里
				if GameState.inv_count("patty") <= 0:
					GameState.buy_ingredient("patty", 5, 1.5)
				if GameState.inv_count("patty") > 0:
					sim.tap_grill(gi)
					placed = true

	# 4) 薯条 / 可乐：按"这位客人还缺哪件"补充。
	#    逐件交付之后，堡递出去不等于这单完了——以前这里的闸门是"荷叶上还有没有堡"，
	#    堡一递走闸门就落下，薯条和可乐永远不开工，整天的单全超时（trace 实测 served=0）。
	var owner: Customer = target if target != null else _tray_owner()
	var still_open := owner != null and not owner.got_all()
	var fp := float(sim.fryer["p"])
	if fp < 0.0:
		if still_open and owner.wants("fries") and not bool(owner.got.get("fries", false)) \
				and not sim.tray_has_slot("fries") and sim.can_cook():
			if GameState.inv_count("potato") <= 0:
				GameState.buy_ingredient("potato", 5, 1.5)
			if GameState.inv_count("potato") > 0:
				sim.tap_fryer()
	else:
		var fwin: Array = Config.cook("fryer").get("window", [0.72, 1.0])
		if fp >= float(fwin[0]) and fp <= float(fwin[1]):
			sim.tap_fryer()
		elif fp >= float(Config.cook("fryer").get("burn_tap", 1.22)):
			sim.tap_fryer()

	var dp := float(sim.drink["p"])
	if dp < 0.0:
		if still_open and owner.wants("drink") and not bool(owner.got.get("drink", false)) \
				and not sim.tray_has_slot("drink"):
			if GameState.inv_count("drink") <= 0:
				GameState.buy_ingredient("drink", 5, 1.5)
			if GameState.inv_count("drink") > 0:
				sim.tap_drink(_jar_of(str(owner.want("drink"))))
	else:
		var dwin: Array = Config.cook("drink").get("window", [0.62, 0.95])
		if dp >= float(dwin[0]) and dp <= float(dwin[1]):
			sim.tap_drink()
		elif dp >= float(Config.cook("drink").get("overflow_tap", 1.06)):
			sim.tap_drink()

	# 5) 组装：只给"还没有收到堡"的目标叠（逐件交付之后，got.burger 为真的人再叠一只就是白烧食材）
	if target != null and not sim.tray_has_slot(Config.burger_slot()) and not bool(target.got.get("burger", false)):
		var need := sim.next_need_ing()
		if need == "patty":
			if sim.cooked > 0:
				sim.tap_shelf("patty")
		elif need != "":
			if GameState.inv_count(need) <= 0:
				# 倒掉的盘子会把已经用掉的食材一起烧掉（设计如此，不退钱）。
				# 真人这时候叫卡车补货（×1.5），bot 以前只会干等——第一章第 4 天就这么
				# 端着空盘举着三个熟饼看完整天，把"bot 不会补货"误判成"这天太难"。
				GameState.buy_ingredient(need, 5, 1.5)
			if GameState.inv_count(need) > 0:
				sim.tap_shelf(need)

## 队列里还有没有人要托盘上这只堡。刚进门还在走的也算，否则会在买家到的前一瞬把堡倒掉。
## 托盘汉堡的主人：优先能立即上餐的等待者；否则找同款汉堡的等待者；无汉堡时用当前目标
func _tray_owner() -> Customer:
	var tb := int(sim.tray[Config.burger_slot()])
	if tb < 0:
		if sim.target >= 0 and sim.target < sim.queue.size():
			return sim.queue[sim.target]
		return null
	for c in sim.queue:
		if c.state == "waiting" and c.burger_idx() == tb and sim.next_kind_for(c) == "burger":
			return c
	for c in sim.queue:
		if c.state == "waiting" and c.burger_idx() == tb:
			return c
	return null

func _jar_of(did: String) -> int:
	var list: Array = Config.drinks()
	for i in list.size():
		if str(list[i].get("id", "")) == did:
			return i
	return 0

