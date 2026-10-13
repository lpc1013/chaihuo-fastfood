class_name UnlockRules
extends RefCounted
## 解锁规则（UnlockRules）：纯计算，不读取任何全局运行时状态。
##
## 审计点名的双向依赖：以前 `Config.shelf_order()` / `Config.burger_open()` 直接读
## `GameState.day` / `GameState.rep_stars()`，于是"规则"隐式绑死在"当前全局状态"上——
## 想验证"第 5 天 3 星能点哪些菜"就得先改全局变量，回放/关卡预览/模拟器都做不了。
## 现在这些规则全部改成显式接收 (day, stars)：
##   - 不依赖场景节点，不进 autoload，可以单独造数据测试；
##   - Config 里保留同名包装（读 GameState 后转发），调用方一行都不用改；
##   - 需要"假设第 N 天"时，直接调这里的静态方法即可，不再有全局副作用。

## 货架上此刻能看到的原料：按 all_order 的次序筛出已到解锁日的那些。
static func shelf_order(dishes: Dictionary, all_order: Array, day: int) -> Array:
	var out: Array = []
	var ings: Dictionary = dishes.get("ingredients", {})
	for k in all_order:
		var ing: Dictionary = ings.get(str(k), {})
		if int(ing.get("unlock_day", 1)) <= day:
			out.append(k)
	return out

## 这道菜在给定天数/星级下是否可点。`unlock_rep=0` 的菜不受声望限制。
static func burger_open(b: Dictionary, day: int, stars: int) -> bool:
	if b.is_empty():
		return false
	if int(b.get("unlock_day", 1)) > day:
		return false
	return int(b.get("unlock_rep", 0)) <= stars

## 已解锁的菜谱下标。
static func open_indices(burgers: Array, day: int, stars: int) -> Array:
	var out: Array = []
	for i in burgers.size():
		if burger_open(burgers[i], day, stars):
			out.append(i)
	return out

## 下标 idx 当前不可点时，回退到一个可点的（取原序号最近的可行解）。
static func resolved(burgers: Array, idx: int, day: int, stars: int) -> int:
	if idx >= 0 and idx < burgers.size() and burger_open(burgers[idx], day, stars):
		return idx
	var open := open_indices(burgers, day, stars)
	if open.is_empty():
		return idx
	var best := int(open[0])
	for i in open:
		if absi(int(i) - idx) < absi(best - idx):
			best = int(i)
	return best
