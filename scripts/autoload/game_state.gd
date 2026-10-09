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
	coins += n
	if n > 0:
		total_coins += n
	coins_changed.emit()

func spend_coins(n: int) -> bool:
	if coins < n:
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
	if inv_count(key) <= 0:
		return false
	inventory[key] = inv_count(key) - 1
	inventory_changed.emit()
	return true

func inv_add(key: String, n: int) -> void:
	inventory[key] = inv_count(key) + n
	inventory_changed.emit()

func ingredient_cost(key: String, n: int, unit_mult: float) -> int:
	var unit := int(Config.ingredient(key).get("cost", 1))
	return int(ceil(float(unit) * unit_mult)) * n

func buy_ingredient(key: String, n: int, unit_mult: float) -> bool:
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
	coins = int(d.get("coins", coins))
	rep = float(d.get("rep", rep))
	day = maxi(1, int(d.get("day", day)))
	best_combo = int(d.get("best_combo", best_combo))
	total_served = int(d.get("total_served", total_served))
	total_coins = int(d.get("total_coins", total_coins))
	intro_seen = bool(d.get("intro_seen", intro_seen))
	mystery_seen = bool(d.get("mystery_seen", mystery_seen))
	ending_chapter = clampi(int(d.get("ending_chapter", 0)), 0, Config.chapter_count())
	tut_done = bool(d.get("tut_done", tut_done))
	upgrades = d.get("upgrades", {}).duplicate()
	muted = bool(d.get("muted", muted))
	shop_spent_pending = int(d.get("shop_spent_pending", 0))
	# 磁盘上的 JSON 不保证类型（第十七轮 `player` 写成数组直接把开机弄崩过一次），
	# 所以这里先验类型再取。类型不对就当没做过菜——勾会丢，但游戏还得能起来。
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
	var inv: Dictionary = d.get("inventory", {})
	var base := Config.start_inventory()
	for k in base.keys():
		inventory[k] = int(inv.get(k, base[k]))
