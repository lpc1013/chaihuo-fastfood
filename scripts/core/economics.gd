class_name Economics
extends RefCounted
## 经济（Economics）：金钱与库存的领域不变量，收拢到一处纯逻辑。
##
## 审计点名"资金/库存操作散落、缺少受控入口"：以前 `spend_coins` 允许负数（等于反向充值）、
## `buy_ingredient` 不校验数量与单价倍率。这里把规则定义成纯静态函数，GameState 只是
## "读状态 → 交给这里判定 → 写回状态 + 发信号"的薄壳。好处：
##   - 不变量只有一份定义，改规则不会漏改某条通道；
##   - 不依赖场景节点，可以单独造参数断言（见 smoke 的 _test_economic_invariants）。
##
## 约定：所有涉及金钱/库存的变更都必须能通过这里的一组 `can_*` / `*_result` 判定或计算，
## 不要让任何模块直接改 GameState 的字典。

## 这笔钱能不能花出去。负数或超出余额都不行。
static func can_spend(coins: int, n: int) -> bool:
	return n >= 0 and coins >= n

## 采购数量/单价倍率是否合法：数量必须为正整数，单价倍率必须为正。
static func can_buy(n: int, unit_mult: float) -> bool:
	return n > 0 and unit_mult > 0.0

## 采购总价。单价倍率非法时退回 1.0，数量非法时按 0 计——但**调用方应先过 can_buy**，
## 这里只是保证即便被绕过也不会算出"倒贴/免费"的价。
static func ingredient_cost(unit_cost: int, n: int, unit_mult: float) -> int:
	var safe_mult := unit_mult if unit_mult > 0.0 else 1.0
	return int(ceil(float(unit_cost) * safe_mult)) * maxi(0, n)

## 库存增量结果（只增通道）：负数不接受，结果钳制非负。
## 返回 null 表示"这次调用非法，应忽略"；否则返回新的库存数量。
static func inv_add_result(current: int, n: int):
	if n < 0:
		return null
	return maxi(0, current + n)

## 库存减一结果（只减通道）：余额不足返回 null（调用方据此报"没货"）。
static func inv_use_result(current: int):
	if current <= 0:
		return null
	return current - 1
