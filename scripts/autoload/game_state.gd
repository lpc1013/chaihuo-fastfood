extends Node
## 玩家全局状态（GameState）：金币、声望、库存、天数、升级与统计。由 SaveManager 持久化。

signal coins_changed()
signal rep_changed()
signal inventory_changed()
signal upgrades_changed()

var coins: int = 0
var rep: float = 3.0
var day: int = 1
var best_combo: int = 0
var total_served: int = 0
var total_coins: int = 0
var intro_seen := false
var mystery_seen := false
## 已经看过章末页的最大章号。以前是个 ending_seen 布尔——那时全程只有一个结局，
## 按章锚定之后每一章末尾都有一页，得记住走到过哪一章，否则无尽模式每天弹一次结局页。
var ending_chapter := 0
var tut_done := false
var upgrades: Dictionary = {}
var inventory: Dictionary = {}
var muted := false
var shop_spent_pending := 0
## 每道菜**成功出过餐**没有：键是 dishes.json 里 burgers[].id，值是做过多少次。
## 用 id 不用下标——将来在中间插一道菜，下标会把勾打到别的堡上。
## 图鉴靠它给做过的菜盖一枚绿勾（见 ov_menu._draw_done_stamp）。
var dishes_done: Dictionary = {}

## 记一次"这道菜做出来了"。返回 true 表示是**第一次**做出来（调用方据此弹一条获得型反馈）。
func mark_dish_done(burger_idx: int) -> bool:
	var id := str(Config.burger(burger_idx).get("id", ""))
	if id == "":
		return false
	var n := int(dishes_done.get(id, 0))
	dishes_done[id] = n + 1
	return n == 0

func dish_done(id: String) -> bool:
	return int(dishes_done.get(id, 0)) > 0

func dishes_done_count() -> int:
	var n := 0
	for k in dishes_done.keys():
		if int(dishes_done[k]) > 0:
			n += 1
	return n


func initialize_new() -> void:
	coins = int(Config.economy.get("start_coins", 0))
	rep = float(Config.economy.get("start_rep", 3))
	day = 1
	best_combo = 0
	total_served = 0
	total_coins = 0
	intro_seen = false
	mystery_seen = false
	ending_chapter = 0
	tut_done = false
	upgrades = {}
	inventory = Config.start_inventory()
	muted = false
	shop_spent_pending = 0
	dishes_done = {}

func reset_for_new_game() -> void:
	initialize_new()
	SaveManager.wipe()
	set_muted(muted)

## 静音的唯一入口：音效和音乐必须一起哑，否则切了开关还有 BGM 在响
func set_muted(v: bool) -> void:
	muted = v
	Sfx.set_muted(muted)
	Music.set_muted(muted)

func toggle_muted() -> bool:
	set_muted(not muted)
	return muted

func add_coins(n: int) -> void:
	# 资金只进不出这条通道：负数会凭空扣钱，属非法入参，直接丢弃。
	if n < 0:
		push_warning("[GameState] add_coins 收到负数 %d，已忽略" % n)
		return
	coins += n
	if n > 0:
		total_coins += n
	coins_changed.emit()

func spend_coins(n: int) -> bool:
	# 规则在 Economics.can_spend（纯函数）：负金额等于反向充值，必须拒绝，
	# 否则 `spend_coins(-100)` 会凭空加钱。
	if not Economics.can_spend(coins, n):
		if n < 0:
			push_warning("[GameState] spend_coins 收到负数 %d，已拒绝" % n)
		return false
	coins -= n
	coins_changed.emit()
	return true

func add_rep(d: float) -> void:
	rep = clampf(rep + d, float(Config.economy.get("rep_min", 0)), float(Config.economy.get("rep_max", 5)))
	rep_changed.emit()

func rep_stars() -> int:
	return int(round(rep))

# ---------- 升级 ----------
func has_upgrade(id: String) -> bool:
	return upgrades.get(id, false) == true

func buy_upgrade(id: String) -> bool:
	var u := Config.upgrade_def(id)
	if u.is_empty() or has_upgrade(id):
		return false
	var cost := int(u.get("cost", 0))
	if not spend_coins(cost):
		return false
	upgrades[id] = true
	upgrades_changed.emit()
	return true

func effect_sum(key: String) -> float:
	var total := 0.0
	for id in upgrades.keys():
		if not has_upgrade(str(id)):
			continue
		var eff: Dictionary = Config.upgrade_def(str(id)).get("effects", {})
		if eff.has(key):
			total += float(eff[key])
	return total

func effect_mult(key: String) -> float:
	var total := 1.0
	for id in upgrades.keys():
		if not has_upgrade(str(id)):
			continue
		var eff: Dictionary = Config.upgrade_def(str(id)).get("effects", {})
		if eff.has(key):
			total *= float(eff[key])
	return total

func grill_slots() -> int:
	return 2 + int(effect_sum("grill_slots_add"))

# ---------- 库存 ----------
func inv_count(key: String) -> int:
	return int(inventory.get(key, 0))

func inv_use(key: String) -> bool:
	# 只减通道：余额不足就是不成功（规则在 Economics.inv_use_result）。
	var next = Economics.inv_use_result(inv_count(key))
	if next == null:
		return false
	inventory[key] = next
	inventory_changed.emit()
	return true

func inv_add(key: String, n: int) -> void:
	# 只增通道：负数既不合理（那是 inv_use 的职责），还可能制造负库存。
	# 规则在 Economics.inv_add_result（纯函数），结果钳制非负。
	var next = Economics.inv_add_result(inv_count(key), n)
	if next == null:
		push_warning("[GameState] inv_add 收到负数 %d（key=%s），已忽略" % [n, key])
		return
	inventory[key] = next
	inventory_changed.emit()

func ingredient_cost(key: String, n: int, unit_mult: float) -> int:
	# 单价倍率必须为正，否则单价会变成 0 或负数，进而制造"免费/倒贴"采购。
	return Economics.ingredient_cost(int(Config.ingredient(key).get("cost", 1)), n, unit_mult)

func buy_ingredient(key: String, n: int, unit_mult: float) -> bool:
	# 非法入参守卫（规则在 Economics.can_buy）：数量必须是正整数、单价倍率必须为正，
	# 否则既不扣钱也不入库。
	if not Economics.can_buy(n, unit_mult):
		push_warning("[GameState] buy_ingredient 入参非法 n=%d mult=%f（key=%s），已拒绝" % [n, unit_mult, key])
		return false
	var cost := ingredient_cost(key, n, unit_mult)
	if not spend_coins(cost):
		return false
	inventory[key] = inv_count(key) + n
	inventory_changed.emit()
	return true

# ---------- 存档序列化 ----------
func to_save_dict() -> Dictionary:
	return {
		"coins": coins,
		"rep": rep,
		"day": day,
		"best_combo": best_combo,
		"total_served": total_served,
		"total_coins": total_coins,
		"intro_seen": intro_seen,
		"mystery_seen": mystery_seen,
		"ending_chapter": ending_chapter,
		"tut_done": tut_done,
		"upgrades": upgrades.duplicate(),
		"inventory": inventory.duplicate(),
		"muted": muted,
		"shop_spent_pending": shop_spent_pending,
		"dishes_done": dishes_done.duplicate()
	}

func apply_save_dict(d: Dictionary) -> void:
	initialize_new()
	if d.is_empty():
		return
	# 基础数值：先按类型取，再做范围钳制，保证从磁盘进来的任何脏数据都不会破坏不变量。
	coins = maxi(0, int(d.get("coins", coins)))
	rep = clampf(float(d.get("rep", rep)), float(Config.economy.get("rep_min", 0.0)), float(Config.economy.get("rep_max", 5.0)))
	day = maxi(1, int(d.get("day", day)))
	best_combo = maxi(0, int(d.get("best_combo", best_combo)))
	total_served = maxi(0, int(d.get("total_served", total_served)))
	total_coins = maxi(0, int(d.get("total_coins", total_coins)))
	intro_seen = bool(d.get("intro_seen", intro_seen))
	mystery_seen = bool(d.get("mystery_seen", mystery_seen))
	ending_chapter = clampi(int(d.get("ending_chapter", 0)), 0, Config.chapter_count())
	tut_done = bool(d.get("tut_done", tut_done))
	muted = bool(d.get("muted", muted))
	shop_spent_pending = maxi(0, int(d.get("shop_spent_pending", 0)))

	# 升级表：必须是字典。历史上 `upgrades` 被写成数组，导致后续 `upgrades.keys()` 直接崩。
	var ug = d.get("upgrades", {})
	if typeof(ug) != TYPE_DICTIONARY:
		push_warning("[GameState] 存档 upgrades 不是对象，已忽略")
		ug = {}
	upgrades = (ug as Dictionary).duplicate()

	# 图鉴：原本就做了类型校验（第十七轮 `player` 写成数组崩过），保留并强化。
	var dd = d.get("dishes_done", {})
	dishes_done = {}
	if typeof(dd) == TYPE_DICTIONARY:
		for k in (dd as Dictionary).keys():
			var v = (dd as Dictionary)[k]
			var n := 0
			if typeof(v) == TYPE_STRING:
				n = int(str(v))
			elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				n = int(v)
			if n > 0:
				dishes_done[str(k)] = n

	# 库存：必须是字典，且结果钳制在非负。"负库存"既不合理，也会让库存计数出现诡异的下溢。
	var inv = d.get("inventory", {})
	if typeof(inv) != TYPE_DICTIONARY:
		push_warning("[GameState] 存档 inventory 不是对象，已回退初始库存")
		inv = {}
	var base := Config.start_inventory()
	for k in base.keys():
		inventory[k] = maxi(0, int((inv as Dictionary).get(k, base[k])))
