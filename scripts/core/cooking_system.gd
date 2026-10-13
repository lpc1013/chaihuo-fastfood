class_name CookingSystem
extends RefCounted
## 烹饪系统（CookingSystem）：烤架 / 炸篮 / 饮料机的推进与点击判定。
##
## 审计点名的"DaySim 职责过载"：以前 `_tick_stations`、`tap_grill`、`tap_fryer`、`tap_drink`
## 把"数值推进"和"业务编排（扣料、往荷叶落成品、报错文案、音效信号）"揉在一起。
## 这里把**可纯计算**的那部分抽成静态方法，DaySim 只负责调用 + 发信号：
##   - 推进速度（含火力不足降速、升级倍率）：speed_hot()，且**只应用一次**倍率；
##   - 炸篮选哪只：fryer_focus()（只有一只篮时四个分支必然都指到 0 号，行为与泛化前一致）；
##   - 新炸篮状态：new_basket()。
## 这些方法不吃浮点时间、不吃全局态参数以外的东西，可在无场景环境单独测试。

## 单点火焰下的烹饪推进倍率。⚠ 只在这里乘 `cook_speed_mult`——所有工位都走它，
## 绝不再叠乘一次（审计点名的"猛火灶台 1.1× 被算成 1.21×"就是这么来的）。
static func speed_hot(fire: float, low_threshold: float, low_speed_mult: float, cook_speed_mult: float) -> float:
	var s := cook_speed_mult
	if fire < low_threshold:
		s *= low_speed_mult
	return s


## 新炸篮的初值。`item` 是这篮炸的是什么（`sides` 里的 id），空篮为 ""。
static func new_basket() -> Dictionary:
	return {"p": -1.0, "warned": false, "item": ""}


## 这一次点击该落在哪只篮子：
##   ① 先起锅窗口内的 → ② 糊掉的 → ③ 空篮 → ④ 任何还在炸的。
## **只有一只篮子时这四个分支必然都指到 0 号**，所以判路和泛化前那条完全一致。
static func fryer_focus(baskets: Array, win_a: float, win_b: float, burn_tap: float) -> int:
	for i in baskets.size():
		var p := float((baskets[i] as Dictionary)["p"])
		if p >= win_a and p <= win_b:
			return i
	for i in baskets.size():
		if float((baskets[i] as Dictionary)["p"]) >= burn_tap:
			return i
	for i in baskets.size():
		if float((baskets[i] as Dictionary)["p"]) < 0.0:
			return i
	for i in baskets.size():
		if float((baskets[i] as Dictionary)["p"]) >= 0.0:
			return i
	return -1


## 有没有哪只篮子正在炸（HUD 那枚脉冲用的就是这个，不是"0 号篮"）。
static func any_busy(baskets: Array) -> bool:
	for b in baskets:
		if float((b as Dictionary)["p"]) >= 0.0:
			return true
	return false


## 进度是否落在起锅窗口内（含端点）。烤架/炸锅/饮料机共用这条判据。
static func in_window(p: float, win_a: float, win_b: float) -> bool:
	return p >= win_a and p <= win_b
