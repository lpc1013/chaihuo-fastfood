extends Node
## 配置中心（Config）：所有数值/文案配置文件统一从这里读取。
## 默认配置位于 res://data/config/*.json；用户覆盖可放 user://config/*.json（同名优先）。改数值无需改代码。

const CONFIG_DIR := "res://data/config/"
const USER_CONFIG_DIR := "user://config/"  # 用户覆盖目录：同名 JSON 放这里即可覆盖随包默认（导出后调数值不必重新打包）

var dishes: Dictionary = {}
var customers: Dictionary = {}
var economy: Dictionary = {}
var fire: Dictionary = {}
var upgrades: Dictionary = {}
var difficulty: Dictionary = {}
var story: Dictionary = {}
var map: Dictionary = {}
var load_errors: PackedStringArray = []

## 升级效果键白名单：只有这些 key 会被经济/营业逻辑读取。出现未登记 key 说明配置或代码
## 有一边漏了，validate_config 会报出来，避免"改了升级却没生效"或"乱填键被静默忽略"。
const KNOWN_EFFECT_KEYS := [
	"grill_slots_add", "fire_decay_mult", "cook_speed_mult", "patience_decay_mult",
	"tip_flat_bonus", "customers_per_day_add", "auto_turn", "cut_need_mult"
]

func _ready() -> void:
	reload_all()

func reload_all() -> void:
	load_errors.clear()
	dishes = _load_json("dishes.json")
	customers = _load_json("customers.json")
	economy = _load_json("economy.json")
	fire = _load_json("fire.json")
	upgrades = _load_json("upgrades.json")
	difficulty = _load_json("difficulty.json")
	story = _load_json("story.json")
	map = _load_json("map.json")
	# 配置落盘前先过一遍结构校验：把"魔法数字搬进 JSON"变成"可靠的数据驱动"。
	validate_config()
	for e in load_errors:
		push_warning("[Config] " + e)

## 配置结构校验（不校验美术资源，资源引用由 smoke_test._test_art_refs 负责）。
## 只报告明确的非法情况，正常配置应当零报错；任何一条都应该是一个能直接定位的文案。
func validate_config() -> void:
	var ids := {}
	for b in burgers():
		var bd: Dictionary = b
		var id := str(bd.get("id", ""))
		if id == "":
			load_errors.append("菜品缺少 id")
			continue
		if ids.has(id):
			load_errors.append("菜品 id 重复: " + id)
		ids[id] = true
		var stack: Array = bd.get("stack", [])
		if stack.is_empty():
			load_errors.append("菜品配方为空: " + id)
			continue
		for k in stack:
			if ingredient(str(k)).is_empty():
				load_errors.append("菜品 %s 引用了不存在的食材: %s" % [id, str(k)])
	for key in dishes.get("ingredients", {}).keys():
		var ing := ingredient(str(key))
		var cost = ing.get("cost", 0)
		if (typeof(cost) != TYPE_INT and typeof(cost) != TYPE_FLOAT) or float(cost) < 0:
			load_errors.append("食材成本非法（非数字或为负）: " + str(key))
	for st in ["grill", "fryer", "drink"]:
		var c := cook(st)
		var fs = c.get("full_seconds", 0)
		if (typeof(fs) != TYPE_INT and typeof(fs) != TYPE_FLOAT) or float(fs) <= 0:
			load_errors.append("烹饪时间必须为正数字: " + st)
	var uids := {}
	for u in upgrade_defs():
		var ud: Dictionary = u
		var uid := str(ud.get("id", ""))
		if uid == "":
			load_errors.append("升级缺少 id")
			continue
		if uids.has(uid):
			load_errors.append("升级 id 重复: " + uid)
		uids[uid] = true
		if float(ud.get("cost", 0)) < 0:
			load_errors.append("升级成本为负: " + uid)
		var eff: Dictionary = ud.get("effects", {})
		for ek in eff.keys():
			if not KNOWN_EFFECT_KEYS.has(str(ek)):
				load_errors.append("升级 %s 使用了未支持的效果键: %s" % [uid, str(ek)])
	if float(economy.get("start_coins", 0)) < 0:
		load_errors.append("起始金币为负")
	for m in economy.get("rep_tip_mult", []):
		if typeof(m) != TYPE_INT and typeof(m) != TYPE_FLOAT:
			load_errors.append("rep_tip_mult 含非数字")
	var expect := 1
	for c in chapters():
		var cc: Dictionary = c
		if int(cc.get("id", 0)) != expect:
			load_errors.append("章节 id 不连续，期望 %d 实得 %d" % [expect, int(cc.get("id", 0))])
		expect += 1
		if int(cc.get("days", 0)) < 1:
			load_errors.append("章节天数必须 >= 1: " + str(cc.get("id", 0)))

func _load_json(file_name: String) -> Dictionary:
	# 优先级：user://config/<file>（用户覆盖） > res://data/config/<file>（随包默认）
	var override_path := USER_CONFIG_DIR + file_name
	if FileAccess.file_exists(override_path):
		var ov := _parse_json(override_path)
		if not ov.is_empty():
			return ov
		push_warning("[Config] 用户覆盖无法解析，已回退默认: " + override_path)
	var path := CONFIG_DIR + file_name
	if not FileAccess.file_exists(path):
		load_errors.append("缺少配置文件: " + path)
		return {}
	var parsed := _parse_json(path)
	if parsed.is_empty():
		load_errors.append("无法读取或 JSON 解析失败: " + path)
	return parsed

func _parse_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

# ---------- 菜品 ----------
func burgers() -> Array:
	return dishes.get("burgers", [])

func burger(idx: int) -> Dictionary:
	var list: Array = burgers()
	if idx < 0 or idx >= list.size():
		return {}
	return list[idx]

func burger_count() -> int:
	return burgers().size()

func ingredient(key: String) -> Dictionary:
	return dishes.get("ingredients", {}).get(key, {})

func ingredient_cuts(key: String) -> int:
	return int(ingredient(key).get("cuts", 0))

func ingredient_name(key: String) -> String:
	return str(ingredient(key).get("name", key))

func start_inventory() -> Dictionary:
	return dishes.get("start_inventory", {}).duplicate()

## 规则本体在 UnlockRules（纯函数，显式接收 day）。这里读当前天数后转发，
## 保持 Config.shelf_order() 这个老签名不变——调用方不必逐个改。
func shelf_order() -> Array:
	return UnlockRules.shelf_order(dishes, all_shelf_order(), GameState.day)

func all_shelf_order() -> Array:
	return dishes.get("shelf_order", [])

## 能买到的原料 = 货架上那些 + 不上架但会被工位吃掉的（可乐从饮料机出，不在木格里）。
## 商店和卡车补货都走这个表：以前两边都只读 shelf_order，可乐哪儿都买不到，
## 开局那 10 杯用完之后所有带饮料的单永远做不出来。
func shop_order() -> Array:
	var out: Array = all_shelf_order().duplicate()
	for k in dishes.get("shop_extra", []):
		if not out.has(str(k)):
			out.append(str(k))
	return out

## 已到解锁日的菜谱下标（老菜谱下标不变，只筛可选范围）
func open_burger_indices() -> Array:
	return UnlockRules.open_indices(burgers(), GameState.day, GameState.rep_stars())

## 声望既挂解锁也挂小费（设计决策：双挂钩）。星级不足时这道菜连被点单的资格都没有。
## 规则本体在 UnlockRules.burger_open（纯函数）；这里读当前天数/星级后转发。
func burger_open(idx: int) -> bool:
	return UnlockRules.burger_open(burger(idx), GameState.day, GameState.rep_stars())

## 下标 idx 当前不可点时，回退到一个可点的（默认取原序号最近的可行解）。
func burger_resolved(idx: int) -> int:
	return UnlockRules.resolved(burgers(), idx, GameState.day, GameState.rep_stars())

## 按星级查小费倍率，超出表长取末档。
func rep_tip_mult(stars: int) -> float:
	var list: Array = economy.get("rep_tip_mult", [])
	if list.is_empty():
		return 1.0
	return float(list[clampi(stars, 0, list.size() - 1)])

func drinks() -> Array:
	return dishes.get("drinks", [])

func drink_def(i: int) -> Dictionary:
	var list: Array = drinks()
	# 饮品列表为空时，`maxi(list.size() - 1, 0)` 会算出 0，进而 `list[0]` 越界崩。
	# 这曾经是"配置一少东西整个开机就挂"的来源之一，这里先挡掉。
	if list.is_empty():
		push_warning("[Config] drinks 列表为空，drink_def(%d) 退回空字典" % i)
		return {}
	return list[clampi(i, 0, maxi(list.size() - 1, 0))]

func sauces() -> Array:
	return dishes.get("sauces", [])

## 酱料瓶前几天不上台面（用户要台面先留干净，瓶瓶罐罐以后再加），到日子才出现
func sauce_unlock_day() -> int:
	return int(dishes.get("sauce_unlock_day", 1))

func sauces_open() -> bool:
	return GameState.day >= sauce_unlock_day()

# ---------- 荷叶槽位 ----------
## 荷叶上有那么几件、每件是什么类型，全在这里定义。以后加一道小菜 = 这里加一条
## + `sides` 里登记它的名字/图/价格，**不用再改 day_sim、play 和测试里的判断分支**。
## kind 三种：
##   "burger" 值 = 堡下标(int)，必须等于客人点的那道才算对上；酱料小费可以挂在它身上
##   "flag"   值 = bool，有就是有，不挑是哪一份
##   "pick"   值 = 选项 id(String)，必须等于客人点的那个才算对上
func tray_slots() -> Array:
	return dishes.get("tray_slots", [])

func tray_slot_ids() -> Array:
	var out: Array = []
	for s in tray_slots():
		out.append(str((s as Dictionary).get("id", "")))
	return out

func tray_slot(id: String) -> Dictionary:
	for s in tray_slots():
		if str((s as Dictionary).get("id", "")) == id:
			return s
	return {}

func tray_slot_kind(id: String) -> String:
	return str(tray_slot(id).get("kind", "flag"))

## 那一种 kind=burger 的槽位。组装台和烤架天生只做堡这一件，取它的 id 从这儿走，
## 不在代码里写死 "burger" 这个字符串。
func burger_slot() -> String:
	for s in tray_slots():
		if str((s as Dictionary).get("kind", "")) == "burger":
			return str((s as Dictionary).get("id", ""))
	return ""

## 小菜定义（炸鸡腿/蛋炒饭都在这）。`tray_slots` 里 kind=flag 的那几件，
## 小票上显示什么名字就读这里的 name。
func side(id: String) -> Dictionary:
	return dishes.get("sides", {}).get(id, {})


## 某一槽位"没有这一件"时的取值。Customer 和 DaySim 以前各自手写一遍这个 match，
## 泛化之后只留这一份。
func tray_blank(id: String) -> Variant:
	match tray_slot_kind(id):
		"burger":
			return -1
		"pick":
			return ""
		_:
			return false

## 哪一件背着酱料小费（现在是堡）。把它做成配置而不是写死"burger"，
## 否则"能加酱的东西"永远只有堡一种，将来给小菜加酱就得再翻一遍代码。
func tip_slot() -> String:
	for s in tray_slots():
		if bool((s as Dictionary).get("carries_tip", false)):
			return str((s as Dictionary).get("id", ""))
	return ""

## 空荷叶的初值。键的插入顺序和泛化前那份字面量保持一致（burger, fries, drink, burger_tip），
## 免得有谁按 keys() 的顺序取第一件。
func empty_tray() -> Dictionary:
	var out := {}
	for id in tray_slot_ids():
		out[str(id)] = tray_blank(str(id))
	var ts := tip_slot()
	if ts != "":
		out[ts + "_tip"] = 0
	return out


# ---------- 顾客 ----------
func species(idx: int) -> Dictionary:
	var list: Array = customers.get("species", [])
	if idx < 0 or idx >= list.size():
		return {}
	return list[idx]

func species_count() -> int:
	return customers.get("species", []).size()

func species_lines(idx: int, kind: String) -> Array:
	return species(idx).get("lines", {}).get(kind, [])

# ---------- 经济/烹饪 ----------
## 抛硬币 / 划过拾取 / 收币客人这套的默认值。单列一份是因为使用说明里教用户
## 直接改 user://config/economy.json——他只写想改的那几个键时，缺的键不能变成 0。
const COIN_DEFAULTS := {
	"gold_value": 10, "silver_value": 1, "max_per_toss": 40, "toss_seconds": 0.5,
	"pickup_radius": 20, "rest_band": [0.490, 0.515], "spread_x": 0.42,
	"anchor_x": 0.44, "coin_size": 30.0, "collector_from_day": 2,
	"sweep_after": 6.0, "sweep_walk": 1.2, "steal_gap": 0.45, "leave_after": 0.9
}

func coins_cfg() -> Dictionary:
	var out: Dictionary = COIN_DEFAULTS.duplicate(true)
	var c = economy.get("coins", {})
	if typeof(c) == TYPE_DICTIONARY:
		for k in (c as Dictionary).keys():
			out[k] = (c as Dictionary)[k]
	return out

func cook(key: String) -> Dictionary:
	return economy.get("cooking", {}).get(key, {})

## 炸炉有几只篮子。第三章要接炸鸡腿、要扩到 2，但那是玩法改动；
## 现在给 1，让"多篮"这层结构先在行为中立的前提下长出来。
func fryer_baskets() -> int:
	return maxi(1, int(cook("fryer").get("baskets", 1)))


# ---------- 章 ----------
## 进度按「章」锚定，不按天。一章多少天、叫什么，全在 economy.json 的 chapters 表里。
## chapters 缺席时才退回旧的 total_days（= 单章），这样老存档和用户手写的
## user://config/economy.json 里只有 total_days 的情况不会变成零天。
func chapters() -> Array:
	return economy.get("chapters", [])

func chapter_count() -> int:
	return maxi(1, chapters().size())

func chapter_days(ch: int) -> int:
	var list: Array = chapters()
	if ch < 1 or ch > list.size():
		return int(economy.get("total_days", 7))
	return maxi(1, int((list[ch - 1] as Dictionary).get("days", economy.get("total_days", 7))))

## 第 ch 章最后一天在全程里的日号（累加，章可以不等长）
func chapter_end_day(ch: int) -> int:
	var acc := 0
	for i in range(1, clampi(ch, 1, chapter_count()) + 1):
		acc += chapter_days(i)
	return acc

func chapter_start_day(ch: int) -> int:
	return chapter_end_day(ch) - chapter_days(ch) + 1

## 日号落在第几章；超出表长算最后一章（endless 也归在最后那一章里）
func chapter_of(day: int) -> int:
	var acc := 0
	for i in chapters().size():
		acc += chapter_days(i + 1)
		if day <= acc:
			return i + 1
	return chapter_count()

func chapter_name(ch: int) -> String:
	var list: Array = chapters()
	if ch < 1 or ch > list.size():
		return ""
	return str((list[ch - 1] as Dictionary).get("name", ""))

func is_chapter_end(day: int) -> bool:
	return day == chapter_end_day(chapter_of(day))

func is_game_end(day: int) -> bool:
	return day >= total_days()

## 全程总天数 = 各章天数之和。以前这个数就是 economy.json 里写死的 7，
## 现在它是「最后一章的最后一天」，章末判定和无尽分支的分界都读它。
func total_days() -> int:
	var list: Array = chapters()
	if list.is_empty():
		return int(economy.get("total_days", 7))
	var acc := 0
	for c in list:
		acc += maxi(1, int((c as Dictionary).get("days", 1)))
	return acc

## 有显式客流表的最后一天。过了这天 build_day_plan 才走 endless 的随机 roll。
func last_planned_day() -> int:
	var best := 0
	for p in difficulty.get("day_plans", []):
		best = maxi(best, int(p.get("day", 0)))
	return best

func v(key: String, fallback = null):
	if economy.has(key):
		return economy[key]
	return fallback

# ---------- 难度 ----------
func day_plan(day: int) -> Array:
	for p in difficulty.get("day_plans", []):
		if int(p.get("day", -1)) == day:
			return p.get("customers", [])
	return []

func bonus_pool() -> Array:
	return difficulty.get("bonus_pool", [])

# ---------- 升级 ----------
func upgrade_defs() -> Array:
	return upgrades.get("upgrades", [])

func upgrade_def(id: String) -> Dictionary:
	for u in upgrade_defs():
		if str(u.get("id", "")) == id:
			return u
	return {}

# ---------- 剧情/文案 ----------
func intro_lines() -> Array:
	return story.get("intro", [])

## 每一章开场那一段（老柴报新菜 / 请柬落地）。键是章号的字符串形式。
func chapter_intro_lines(ch: int) -> Array:
	var table = story.get("chapter_intro", {})
	if typeof(table) != TYPE_DICTIONARY:
		return []
	return (table as Dictionary).get(str(ch), [])

func has_chapter_intro(ch: int) -> bool:
	return not chapter_intro_lines(ch).is_empty()

func mystery_lines() -> Array:
	return story.get("mystery", [])

func tutorial_steps() -> Array:
	return story.get("tutorial_steps", [])

func snark_lines(cat: String) -> Array:
	return story.get("snarks", {}).get(cat, [])

func misc(key: String) -> String:
	return str(story.get("misc", {}).get(key, ""))

## 街区地图的点位。ui/map_bg 上只有六块空白路牌，所以「一章一条路线」——
## 每章各写六个点位复用同六块牌子，而不是往一张图上硬挤十四块。
func map_nodes(day: int = 0) -> Array:
	var ch := chapter_of(day if day > 0 else GameState.day)
	for c in map.get("chapters", []):
		if int((c as Dictionary).get("id", 0)) == ch:
			return (c as Dictionary).get("nodes", [])
	return map.get("nodes", [])

func map_caption(day: int = 0) -> String:
	var ch := chapter_of(day if day > 0 else GameState.day)
	for c in map.get("chapters", []):
		if int((c as Dictionary).get("id", 0)) == ch:
			var cap := str((c as Dictionary).get("caption", ""))
			if cap != "":
				return cap
			break
	return str(map.get("caption", ""))

func map_hint(key: String) -> String:
	return str(map.get(key, ""))

func ui(key: String) -> String:
	return str(story.get("ui", {}).get(key, ""))

## 营业主界面悬停提示的文案（story.json 的 tooltips 块）
func tooltip(key: String) -> String:
	return str(story.get("tooltips", {}).get(key, ""))

## 章末页那几行结语。按章号取；缺席就返回空表，smoke 有一条闸盯着每一章都得有。
func ending_lines(ch: int) -> Array:
	var table = story.get("ending_lines", {})
	if typeof(table) != TYPE_DICTIONARY:
		return []
	return (table as Dictionary).get(str(ch), [])
