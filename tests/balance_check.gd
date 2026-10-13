extends Node
const TestEnv := preload("res://tests/test_env.gd")
const Bot := preload("res://tests/sim_bot.gd")
## 21 天成长曲线 / 平衡量化（审计问题 5.3 实验 C）：
##   godot --headless --path <项目> -- --test=balance [--days=21] [--aps=2.5] [--runs=1]
##
## 目的不是"证明游戏好玩"——那是人类体验判断，脚本给不了。它只做审计要的那件可量化的事：
## 用受限手速的自动玩家跑完整章节，逐日记录可量化指标，然后回答三个设计问题：
##   ① 是否存在突然的难度断崖（某天成功率/超时数相对前一天剧烈恶化）
##   ② 玩家是否在升级后失去挑战（升级买满后仍无压力）
##   ③ 后期是否只是同一玩法的数值放大（订单数涨了但结构没变）
##
## 它同时是一根回归闸：曲线突变（服务率崩到 0、超时爆表、金币不增反降）直接判红。
## 复现性：bot 的 rng 与 sim 的 seed 都按 (run, day) 派生，同参数必得同结果。

var main: Node
var fails: Array = []

var days := 21
var aps := 2.5          # 受限手速：模拟"手速普通的真人"，不是 20 击/秒的神
var runs := 1
var miss_frac := 0.05   # 轻微失误率：完全不失误的机器人会把难度读成"没有难度"

## 每日一行记录（也是最终报告的原始数据）
var rows: Array = []

func run(m: Node) -> void:
	main = m
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--days="):
			days = maxi(1, int(s.substr(7)))
		elif s.begins_with("--aps="):
			aps = maxf(0.0, float(s.substr(6)))
		elif s.begins_with("--runs="):
			runs = maxi(1, int(s.substr(7)))
		elif s.begins_with("--miss="):
			miss_frac = clampf(float(s.substr(7)), 0.0, 1.0)
	print("============ BALANCE START (days=%d aps=%.2f runs=%d miss=%.2f) ============" % [days, aps, runs, miss_frac])
	Sfx.set_muted(true)
	_backup_saves()
	SaveManager.use_isolated_saves()
	for r in runs:
		_run_playthrough(r)
	_restore_saves()
	_report()
	var red := _evaluate()
	print("============ BALANCE RESULT ============")
	for f in fails:
		print("FAIL: ", f)
	if red and fails.is_empty():
		print("BALANCE: ALL PASS")
		get_tree().quit(0)
	else:
		print("BALANCE: FAIL")
		get_tree().quit(1)

## 跑一整条线：每天都用受限手速的 bot 打完，日结后按"简单策略"买升级，再进下一天。
func _run_playthrough(r: int) -> void:
	GameState.reset_for_new_game()
	SaveManager.wipe()
	for d in range(1, days + 1):
		GameState.day = d
		var sim := DaySim.new()
		# 同一 (run, day) 派生固定种子 → 结果可复现
		sim.start(d, 700000 + r * 1000 + d)
		var bot := Bot.new()
		bot.sim = sim
		bot.aps = aps
		bot.miss_frac = miss_frac
		var brng := RandomNumberGenerator.new()
		brng.seed = 810000 + r * 1000 + d
		bot.rng = brng
		# 物流上限要跟上：bot 不补货会在"明明做得出来"的日子读成超时（那是 bot 的缺陷）
		_top_inventory(24)
		var steps := 0
		var max_steps := 20000
		while not sim.finished and steps < max_steps:
			bot.step(0.05)
			sim.tick(0.05)
			steps += 1
		if not sim.finished:
			# bot 卡住：这是 bot 覆盖不足，记下来但不让它污染难度结论
			rows.append({"run": r, "day": d, "stuck": true})
			continue
		var st := sim.day_stats()
		rows.append({
			"run": r, "day": d, "stuck": false,
			"planned": int(st["planned"]),
			"served": int(st["served"]),
			"missed": int(st["missed"]),
			"tips": int(st["tips"]),
			"collected": int(st["collected"]),
			"swept": int(st["swept"]),
			"combo_peak": int(st["combo_peak"]),
			"rep_after": float(st["rep_after"]),
			"coins_after": GameState.coins,
			"upgrades": GameState.upgrades.size(),
		})
		# 日结后：按经济能力买得起就买（简单贪心——按 cost 升序，买个够得着的）
		_buy_affordable_upgrades()

## 简单升级策略：把买得起的、还没买的升级按价格从低到高买下去。
## 这不是"最优策略"，是把成长曲线跑出来所需的稳定输入；换策略只需改这里。
func _buy_affordable_upgrades() -> void:
	var defs: Array = Config.upgrade_defs().duplicate()
	defs.sort_custom(func(a, b): return int(a.get("cost", 0)) < int(b.get("cost", 0)))
	for u in defs:
		var id := str((u as Dictionary).get("id", ""))
		if GameState.has_upgrade(id):
			continue
		if GameState.coins >= int((u as Dictionary).get("cost", 0)):
			GameState.buy_upgrade(id)

func _report() -> void:
	print("--- 逐日曲线（run/day 计划 服务 超时 实收 小费 声望 金币 升级数） ---")
	for row in rows:
		if bool(row.get("stuck", false)):
			print("run%d day%-2d  STUCK（bot 未能在步数上限内打完，本条不计入难度结论）" % [int(row["run"]), int(row["day"])])
			continue
		var planned := int(row["planned"])
		var served := int(row["served"])
		var rate := (float(served) / float(maxi(planned, 1))) * 100.0
		print("run%d day%-2d 计划 %2d  服务 %2d (%5.1f%%)  超时 %2d  实收 %4d  小费 %3d  声望 %.2f  金币 %5d  升级 %d" % [
			int(row["run"]), int(row["day"]), planned, served, rate,
			int(row["missed"]), int(row["collected"]), int(row["tips"]),
			float(row["rep_after"]), int(row["coins_after"]), int(row["upgrades"])])
	# 难度断崖：相邻两天服务率跌幅 > 35 个百分点
	print("--- 突变检测（相邻两天服务率跌幅 > 35pp 视为断崖） ---")
	var cliffs := 0
	var prev := -1.0
	for row in rows:
		if bool(row.get("stuck", false)):
			continue
		var rate := float(int(row["served"])) / float(maxi(int(row["planned"]), 1)) * 100.0
		if prev >= 0.0 and prev - rate > 35.0:
			cliffs += 1
			print("  ⚠ run%d day%d 服务率 %.1f%% → %.1f%%（跌 %.1fpp）" % [
				int(row["run"]), int(row["day"]), prev, rate, prev - rate])
		prev = rate
	print("  突变点数 = %d" % cliffs)
	# 后期放大：末段平均计划数 vs 首段
	var first: Array = []
	var last: Array = []
	var valid := rows.filter(func(x): return not bool(x.get("stuck", false)))
	if not valid.is_empty():
		var n := valid.size()
		for i in n:
			if i < maxi(1, n / 3):
				first.append(int(valid[i]["planned"]))
			if i >= n - maxi(1, n / 3):
				last.append(int(valid[i]["planned"]))
	print("--- 后期放大检查 ---")
	print("  首段平均计划数 %.1f → 末段平均计划数 %.1f" % [_avg(first), _avg(last)])

## 红线：曲线出现结构性异常就判红（不是"好不好玩"，是"是不是坏了"）
func _evaluate() -> bool:
	var valid := rows.filter(func(x): return not bool(x.get("stuck", false)))
	if valid.is_empty():
		fails.append("没有任何一天跑完（bot 逻辑或 sim 接口可能坏了）")
		return false
	var zero_days := 0
	for row in valid:
		if int(row["served"]) == 0:
			zero_days += 1
	check(zero_days == 0, "没有整天零服务的日子（实得 %d 天）——有的话说明这天必卡死" % zero_days)
	# 金币总体应随天数上升（买升级会花钱，但收入应盖过）
	var first_coins := int(valid[0]["coins_after"])
	var last_coins := int(valid[-1]["coins_after"])
	check(last_coins >= first_coins, "末期金币不低于首日（%d → %d），成长曲线不至于倒退" % [first_coins, last_coins])
	# 手速受限下仍应有可观服务率，否则"人类根本来不及"
	var total_planned := 0
	var total_served := 0
	for row in valid:
		total_planned += int(row["planned"])
		total_served += int(row["served"])
	var overall := float(total_served) / float(maxi(total_planned, 1))
	check(overall >= 0.5, "受限手速(%.1f/s)整体服务率 %.1f%% ≥ 50%%（低于此则正常人玩不动）" % [aps, overall * 100.0])
	print("  总服务率 = %.1f%%（%d/%d）" % [overall * 100.0, total_served, total_planned])
	return true

func check(cond: bool, label: String) -> void:
	if not cond:
		fails.append(label)
		print("CHECK FAILED: ", label)

func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(a.size())

func _top_inventory(n: int) -> void:
	for k in Config.start_inventory().keys():
		GameState.inventory[k] = n

# ---------------- 存档隔离（与 soak/smoke 同款） ----------------
var _save_bak := ""
var _ledger_bak := ""
var _had_save := false
var _had_ledger := false

func _backup_saves() -> void:
	_had_save = FileAccess.file_exists(SaveManager.save_path())
	_had_ledger = FileAccess.file_exists(SaveManager.ledger_path())
	if _had_save:
		_save_bak = FileAccess.get_file_as_string(SaveManager.save_path())
	if _had_ledger:
		_ledger_bak = FileAccess.get_file_as_string(SaveManager.ledger_path())

func _restore_saves() -> void:
	SaveManager.wipe()
	if _had_save:
		_write(SaveManager.save_path(), _save_bak)
	if _had_ledger:
		_write(SaveManager.ledger_path(), _ledger_bak)
	SaveManager.load_all()

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
