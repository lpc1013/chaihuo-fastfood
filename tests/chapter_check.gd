extends Node
## 经济跑通检查：一个**会失误的人类玩家**能不能把整章打完。
##
## 每天早上按当天点单量补货（走 GameState 的真实买价、商店的 +5 批量），
## 白天用带失误率的 SimBot 打完整一天。判据三条：
##   1) 当天打得完（不会卡到天荒地老）；
##   2) 早上补货买得起——钱不够就是"第二天开不了张"，本章在此断链；
##   3) 失误 25% 的情况下出餐量不掉到一半以下（难度没失控）。
## 完美通关的 bot 撑不起这个结论：它每天 100% 出餐、金币只涨不跌，
## 而玩家会做错、会倒掉、会流失客人，声望还会往下掉把菜锁回去。
##
## 按章锚定之后一章 7 天、三章 21 天，整趟跑下来二十来分钟。`ch=2` 只跑第二章，
## `day=8` 只跑某一天（那种跑法会给一笔启动资金，只看 throughput 不看经济）。

const MISS_FRAC := 0.25
const SEED := 20260930
const DAY_CAP := 900.0
const BATCH := 5

var fails: Array = []
var miss_frac := 0.25
var aps := 3.0
var only_day := 0
var only_ch := 0
var bank := 2000
var trace := false

func run(_m: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("miss="):
			miss_frac = float(str(a).substr(5))
		elif str(a).begins_with("aps="):
			aps = float(str(a).substr(4))
		elif str(a).begins_with("day="):
			only_day = int(str(a).substr(4))
		elif str(a).begins_with("ch="):
			only_ch = int(str(a).substr(3))
		elif str(a).begins_with("bank="):
			bank = int(str(a).substr(5))
		elif str(a) == "trace":
			trace = true
	var lo := 1
	var hi := Config.total_days()
	var label := "全程 %d 天" % hi
	if only_ch > 0:
		lo = Config.chapter_start_day(only_ch)
		hi = Config.chapter_end_day(only_ch)
		label = "第 %d 章「%s」第 %d~%d 天" % [only_ch, Config.chapter_name(only_ch), lo, hi]
	# 孤立跑（只跑某一章 / 只跑一天）是从零开始的，上一章攒的存款不在这里。
	# 那种跑法第一天的"买得起吗"根本无从判起——硬判就会假报"买不齐货"（第 8 天就这么红过一次），
	# 所以给它一笔启动资金、并把跳过的那一天说出来。
	var isolated := only_day > 0 or lo > 1
	print("============ CHAPTER CHECK START ============  %s  失误率 %.2f 手速 %.1f 次/秒" % [label, miss_frac, aps])
	if isolated:
		print("[isolated] 孤立跑：启动资金垫到 %d 金币，第一天跳过「买得起吗」那条判据" % bank)
	GameState.reset_for_new_game()
	Sfx.set_muted(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var total_served := 0
	var total_missed := 0
	var afford_checked := 0
	var chap := {}
	for d in range(lo, hi + 1):
		if only_day > 0 and d != only_day:
			continue
		GameState.day = d
		var skip_afford := isolated and d == lo
		if skip_afford:
			GameState.coins = bank
		var need := _day_need(d)
		var bought := _restock(need)
		var sim := DaySim.new()
		sim.start(d, 4000 + d)
		var bot := SimBot.new()
		bot.sim = sim
		bot.miss_frac = miss_frac
		bot.aps = aps
		bot.rng = rng
		var t := 0.0
		var next_trace := 20.0
		while not sim.finished and t < DAY_CAP:
			bot.step(0.05)
			sim.tick(0.05)
			t += 0.05
			if trace and t >= next_trace:
				next_trace += 20.0
				print("   t=%3.0fs 队%d 托盘%s 出%2d 失%2d 熟饼%d 火%3.0f" % [
					t, sim.queue.size(), str(sim.tray), sim.served, sim.missed, sim.cooked, sim.fire])
		total_served += sim.served
		total_missed += sim.missed
		var ch := Config.chapter_of(d)
		if not chap.has(ch):
			chap[ch] = {"plan": 0, "served": 0, "missed": 0}
		chap[ch]["plan"] += sim.plan.size()
		chap[ch]["served"] += sim.served
		chap[ch]["missed"] += sim.missed
		print("day %d  计划%2d 出餐%2d 流失%2d  用时%4.0fs  补货%3d份/¥%4d  金币%5d  声望%.1f/%d★" % [
			d, sim.plan.size(), sim.served, sim.missed, t,
			int(bought[0]), int(bought[1]), GameState.coins, GameState.rep, GameState.rep_stars()])
		if not sim.finished:
			fails.append("第 %d 天 %.0f 模拟秒内没打完（出餐 %d/%d）" % [d, DAY_CAP, sim.served, sim.plan.size()])
		if skip_afford:
			if int(bought[2]) > 0:
				print("   (跳过) 第 %d 天垫 %d 金币仍缺 %d 份——孤立跑没带上一章的存款，这条不判" % [d, bank, int(bought[2])])
		else:
			afford_checked += 1
			if int(bought[2]) > 0:
				fails.append("第 %d 天早上买不齐货，缺 %d 份食材 = 当天有单做不出来" % [d, int(bought[2])])
		if sim.plan.size() > 0 and sim.served * 2 < sim.plan.size():
			fails.append("第 %d 天失误后只剩 %d/%d 出餐，难度失控" % [d, sim.served, sim.plan.size()])
	# 每章的实测流失率只打印、不判：手速放到 3 次/秒时两章都是零流失，
	# 拿它当硬闸就是一条会随机变红的闸。真正判"难度有没有上升"的是 smoke 里
	# 那条按编排层数算的负载闸。
	var keys: Array = chap.keys()
	keys.sort()
	for ch in keys:
		var b: Dictionary = chap[ch]
		var p := int(b["plan"])
		var m := int(b["missed"])
		print("  第%s章：出餐 %d/%d，流失率 %.1f%%" % [UiKit.cn_num(int(ch)), int(b["served"]), p, 100.0 * m / maxi(p, 1)])
	print("%s 合计：出餐 %d、流失 %d、收尾金币 %d、声望 %.1f  「买得起吗」实判 %d 天" % [
		label, total_served, total_missed, GameState.coins, GameState.rep, afford_checked])
	if GameState.coins < 0:
		fails.append("%s 结束时金币是负数：%d" % [label, GameState.coins])
	_finish()

## 当天点单要消耗多少份食材：按 burger_resolved 还原真实会点出来的那道菜（声望门槛会改单）
func _day_need(d: int) -> Dictionary:
	var out := {}
	for spec in Config.day_plan(d):
		var b := Config.burger(Config.burger_resolved(int((spec as Dictionary).get("burger", 0))))
		for k in b.get("stack", []):
			out[str(k)] = int(out.get(str(k), 0)) + 1
		if bool((spec as Dictionary).get("fries", false)):
			out["potato"] = int(out.get("potato", 0)) + 1
		var wd = (spec as Dictionary).get("drink", false)
		var wants_drink := (str(wd) != "" and wd is String) if wd is String else bool(wd)
		if wants_drink:
			out["drink"] = int(out.get("drink", 0)) + 1
	return out

## 按商店真实批量 +5 补到当天需求量；返回 [买入份数, 花掉金币, 没买到的份数]
func _restock(need: Dictionary) -> Array:
	var got := 0
	var spent := 0
	var short := 0
	for key in need.keys():
		var want := int(need[key])
		while GameState.inv_count(str(key)) < want:
			var before := GameState.coins
			if not GameState.buy_ingredient(str(key), BATCH, 1.0):
				short += maxi(0, want - GameState.inv_count(str(key)))
				break
			got += BATCH
			spent += before - GameState.coins
	return [got, spent, short]

func _finish() -> void:
	print("============ CHAPTER RESULT ============")
	if fails.is_empty():
		print("CHAPTER: ALL PASS")
		get_tree().quit(0)
		return
	print("CHAPTER: FAIL")
	for f in fails:
		print("  FAIL: ", f)
	get_tree().quit(1)
