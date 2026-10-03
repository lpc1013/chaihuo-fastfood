class_name Customer
extends RefCounted
## 顾客数据（纯数据 + 轻量状态机字段），由 DaySim 驱动、由视图渲染。

const WALK_SECONDS := 0.9

var sp := 0
## 客人点了哪几件。键是 `Config.tray_slots()` 里的 id，值按那一件的 kind 解释：
##   kind=burger → 堡下标(int)；kind=flag → 要不要(bool)；kind=pick → 选项 id(String)。
## 泛化之前这里是 order_burger / order_fries / order_drink 三个字段，加一道小菜
## 要把三个字段各自补齐、还要动 97 处判断；现在加一条 tray_slots 配置就够了。
var orders: Dictionary = {}
var patience := 0.0
var max_patience := 0.0
var state := "walking"          # walking / waiting / leaving
var slot := -1
var urged := false
var mood := "normal"            # normal / happy / angry
var walk_t := 0.0
var bob := 0.0
var out_t := 0.0
var out_dir := 1
var say := ""
var say_t := 0.0
var greet_t := 3.4
var is_walkout := false
## 逐件交付：客人收齐他点的全部几件才结算。键和 `orders` 同一套槽位 id。
var got: Dictionary = {}
## 那份堡上挤的酱值多少小费，在堡递过来这一刻转进来（见 DaySim.deliver）。
var tip_bonus := 0

## 这一件客人要么没点、要么点了什么。没点时返回该 kind 的空值。
func want(id: String) -> Variant:
	if not orders.has(id):
		return Config.tray_blank(id)
	return orders[id]

func set_want(id: String, v: Variant) -> void:
	orders[id] = v

## 客人点的那道堡的下标。组装台、烤架、结算都从这一个口子取，
## 不再各自写 `c.order_burger`。
func burger_idx() -> int:
	return int(want(Config.burger_slot()))

## 这一点他要不要。以前 "burger" 那一支是无条件 return true 的（人人都点堡），
## 现在改成"下标 >= 0 才算点了"——`_spawn_customer` 一定会写这个键，所以等价。
func wants(id: String) -> bool:
	if not orders.has(id):
		return false
	match Config.tray_slot_kind(id):
		"burger":
			return int(orders[id]) >= 0
		"pick":
			return str(orders[id]) != ""
		_:
			return bool(orders[id])

func got_all() -> bool:
	for id in Config.tray_slot_ids():
		if wants(str(id)) and not bool(got.get(str(id), false)):
			return false
	return true

## 还差几件没收。视图层用它决定"点一下客人该递哪件"。
func missing_kinds() -> Array:
	var out: Array = []
	for id in Config.tray_slot_ids():
		if wants(str(id)) and not bool(got.get(str(id), false)):
			out.append(str(id))
	return out

## 他点了哪几件（不管收没收），按槽位顺序。票面上画的就是这一串。
func wanted_kinds() -> Array:
	var out: Array = []
	for id in Config.tray_slot_ids():
		if wants(str(id)):
			out.append(str(id))
	return out

func patience_frac() -> float:
	if max_patience <= 0.0:
		return 0.0
	return clampf(patience / max_patience, 0.0, 1.0)

## 这一件在票上叫什么。三种 kind 各自的出处：
##   burger → 那道堡的名字；pick → 他点的那杯饮料的名字；flag → sides 里那条的名字
func item_label(id: String) -> String:
	match Config.tray_slot_kind(id):
		"burger":
			return str(Config.burger(int(orders.get(id, -1))).get("name", "汉堡"))
		"pick":
			return str(Config.drink_def(_pick_index(str(orders.get(id, "")))).get("name", "饮料"))
		_:
			return str(Config.side(id).get("name", id))

func order_items() -> Array:
	var items: Array = []
	for id in Config.tray_slot_ids():
		if wants(str(id)):
			items.append(item_label(str(id)))
	return items

func order_summary() -> String:
	return " / ".join(order_items())

func _pick_index(did: String) -> int:
	var list: Array = Config.drinks()
	for i in list.size():
		if str(list[i].get("id", "")) == did:
			return i
	return 0
