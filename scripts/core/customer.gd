class_name Customer
extends RefCounted
## 顾客数据（纯数据 + 轻量状态机字段），由 DaySim 驱动、由视图渲染。

const WALK_SECONDS := 0.9

var sp := 0
var order_burger := 0
var order_fries := false
var order_drink := ""
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
## 逐件交付：客人收齐他点的全部几件才结算。键是 "burger" / "fries" / "drink"。
var got: Dictionary = {}
## 那份堡上挤的酱值多少小费，在堡递过来这一刻转进来（见 DaySim.deliver）。
var tip_bonus := 0

func wants(kind: String) -> bool:
	match kind:
		"burger":
			return true
		"fries":
			return order_fries
		"drink":
			return order_drink != ""
	return false

func got_all() -> bool:
	for k in ["burger", "fries", "drink"]:
		if wants(k) and not bool(got.get(k, false)):
			return false
	return true

## 还差几件没收。视图层用它决定"点一下客人该递哪件"。
func missing_kinds() -> Array:
	var out: Array = []
	for k in ["burger", "fries", "drink"]:
		if wants(k) and not bool(got.get(k, false)):
			out.append(k)
	return out

func patience_frac() -> float:
	if max_patience <= 0.0:
		return 0.0
	return clampf(patience / max_patience, 0.0, 1.0)

func order_items() -> Array:
	var items: Array = []
	var b := Config.burger(order_burger)
	items.append(str(b.get("name", "汉堡")))
	if order_fries:
		items.append("炸薯条")
	if order_drink != "":
		items.append(str(Config.drink_def(_drink_index()).get("name", "饮料")))
	return items

func order_summary() -> String:
	return " / ".join(order_items())

func _drink_index() -> int:
	var list: Array = Config.drinks()
	for i in list.size():
		if str(list[i].get("id", "")) == order_drink:
			return i
	return 0
