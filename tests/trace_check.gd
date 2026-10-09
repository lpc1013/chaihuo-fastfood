extends Node
## 行为指纹（重构等式闸）：固定种子 + 固定步长把 SimBot 跑过几天，每一步把
## 托盘 / 点单 / 队列 / 账目 / 这一帧发出去的信号拼成一行规范文本，最后打印整条
## 轨迹的行数与 md5，并把全文落到 `user://trace.txt`。
##
## **它是"等式闸"不是"回归闸"**：只在*不打算改变任何行为*的那类改动里有用
## （例如把托盘从写死三格泛化成 N 槽）。真改玩法——加菜、调小费、动配方、改经济——
## 这里必然变，那是预期的，重新生成基线即可，别把它当 bug 修。
##
## 为什么不用 autotest 的截图当"画面没变"的证据：**它不可复现**。
## 同一份代码连跑两趟，75 张里实测有 57 张字节不同（动画帧、客人位置、打字进度都在动）。
## 拿它当等式闸会得到一条永远红的闸；本文件连跑三趟 md5 完全一致，才配当这个证据。
##
## 用法：改之前跑一次存下 md5，改之后再跑一次，然后按行 diff。
## 要允许"表示层变了但行为没变"的那种差异（比如某个键从缺席变成 0），
## 就把那一处规范化掉再比，并确认**规范化之后差异为 0**——别只看"差了几行"就放行。
##
## 轨迹里一律走**语义取值**（`order_items()` / `got` / `missing_kinds()`），
## 不写 `c.order_burger` 这种字段名——否则重构改了字段名就会假报"行为变了"。
##
##   godot --headless --path <项目> -- --test=trace
##   ... -- --test=trace days=1,3,8 steps=2400

const SEED := 20260930
const DT := 0.05

var days: Array = [1, 3, 8]
var steps_per_day := 2400
var lines: PackedStringArray = []
var emits: PackedStringArray = []


func run(_m: Node) -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("days="):
			days = []
			for t in s.substr(5).split(","):
				days.append(int(str(t)))
		elif s.begins_with("steps="):
			steps_per_day = maxi(1, int(s.substr(6)))
	print("============ TRACE START ============")
	GameState.reset_for_new_game()
	Sfx.set_muted(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for d in days:
		_run_day(int(d), rng)
	_sauce_probe()
	var text := "\n".join(lines) + "\n"
	var f := FileAccess.open("user://trace.txt", FileAccess.WRITE)
	var wrote := "没写成"
	if f != null:
		f.store_string(text)
		f.close()
		wrote = "user://trace.txt"
	# 出餐这条链的实弹检查：前三天是真跑出来的 sim，勾必须由 _settle_order 盖上去，
	# 不能只在 smoke 里手调 mark_dish_done。空字典＝游戏里永远不会有勾。
	print("[trace] 实跑出餐 %d 单，打勾=%s" % [GameState.total_served, JSON.stringify(GameState.dishes_done)])
	print("[trace] 行数=%d md5=%s 全文=%s" % [lines.size(), text.md5_text(), wrote])
	print("============ TRACE DONE ============")
	get_tree().quit(0)


func _run_day(d: int, rng: RandomNumberGenerator) -> void:
	GameState.day = d
	_restock(d)
	var sim := DaySim.new()
	_hook(sim)
	sim.start(d, 4000 + d)
	var bot := SimBot.new()
	bot.sim = sim
	bot.miss_frac = 0.25
	bot.aps = 3.0
	bot.rng = rng
	_mark("day=%d begin" % d, sim)
	for i in steps_per_day:
		_clear_emits()
		bot.step(DT)
		sim.tick(DT)
		_mark("day=%d step=%d" % [d, i], sim)
		if sim.finished:
			break
	# 收尾几条边路：SimBot 不会主动走这些分支，泛化托盘时最容易改坏而没人看见
	_clear_emits()
	sim.dump_tray()
	_mark("day=%d edge=dump_tray" % d, sim)
	_clear_emits()
	sim.refund_assembly()
	_mark("day=%d edge=refund_assembly" % d, sim)
	_clear_emits()
	sim.collect_all()
	_mark("day=%d edge=collect_all" % d, sim)
	_clear_emits()
	sim.swat_sweeper()
	_mark("day=%d edge=swat_sweeper" % d, sim)


## 挂上所有对外播报的信号。泛化时最容易悄悄丢掉的就是这些反馈。
func _hook(sim: DaySim) -> void:
	sim.snark_requested.connect(func(t: String) -> void: emits.append("snark:" + t))
	sim.popup_requested.connect(func(t: String, c: Color, slot: int) -> void:
		emits.append("popup:%s|%s|%d" % [t, str(c), slot]))
	sim.sfx_requested.connect(func(n: String) -> void: emits.append("sfx:" + n))
	sim.shake_requested.connect(func() -> void: emits.append("shake"))
	sim.menu_notice_requested.connect(func(t: String) -> void: emits.append("menu:" + t))
	sim.served_event.connect(func(c: Customer, total: int) -> void:
		emits.append("served:%s|%d" % [_cust(c), total]))
	sim.customer_left_event.connect(func(c: Customer) -> void:
		emits.append("left:%s" % _cust(c)))


## SimBot 从不挤酱，所以 `sauces_used` / `sauce_tip` / `tray.burger_tip` 这条链
## （第十九轮"酱料小费一直是死的"就出在这）在 bot 轨迹里一次都没被走到——
## 实测 4222 行里 `sauces=` 非空 0 行、`sauce_tip` 非零 0 行。
## 这里手摆一遍：组装到一半挤两种酱、再重复挤同一种（走 sauce_once 那条文案），
## 然后逐件递出去，覆盖 deliver → burger_tip 转进 tip_bonus → _settle_order。
func _sauce_probe() -> void:
	GameState.day = 5
	_restock(5)
	var sim := DaySim.new()
	_hook(sim)
	sim.start(5, 999)
	var g := 0
	while sim.first_waiting() < 0 and g < 4000:
		sim.tick(DT)
		g += 1
	if sim.first_waiting() < 0:
		lines.append("sauce ABORT 没等到等待中的客人（跑了 %d 步）" % g)
		return
	# 探针要测的是托盘/小费那条链，烤饼这步直接摆结果，不把探针变成第二个 SimBot
	sim.cooked = 20
	sim._set_target(sim.first_waiting())
	var c: Customer = sim.queue[sim.target]
	_mark("sauce begin sp%d" % c.sp, sim)
	var stack: Array = Config.burger(c.burger_idx()).get("stack", [])
	for li in stack.size():
		var ing := str(stack[li])
		_clear_emits()
		sim.tap_shelf(ing)
		_mark("sauce shelf[%d]=%s" % [li, ing], sim)
		var guard := 0
		while str(sim.board["ing"]) != "" and guard < 12:
			_clear_emits()
			sim.slice_board()
			_mark("sauce slice %s" % ing, sim)
			guard += 1
		if li == 1:
			for si in [0, 1, 0]:
				_clear_emits()
				sim.apply_sauce(si)
				_mark("sauce apply %d" % si, sim)
	for k in c.missing_kinds():
		_clear_emits()
		sim.deliver(c, str(k))
		_mark("sauce deliver %s" % str(k), sim)
	_clear_emits()
	sim.tick(DT)
	_mark("sauce settled", sim)


## 给足料：轨迹要测的是托盘/点单/递送那几条路，不该被"缺货"分支主导。
## 起点统一、数量写死，重构前后才拿得到同一条轨迹。
func _restock(_d: int) -> void:
	var need := {}
	for ing in Config.shelf_order():
		need[str(ing)] = 60
	need["potato"] = 60
	need["drink"] = 60
	var ks: Array = need.keys()
	ks.sort()
	for k in ks:
		GameState.inv_add(str(k), int(need[k]))


func _clear_emits() -> void:
	emits.clear()


func _mark(head: String, sim: DaySim = null) -> void:
	var parts: Array = [head]
	if sim != null:
		parts.append("tray=" + _canon(sim.tray))
		parts.append("target=%d" % sim.target)
		parts.append("asm=%s" % _arr(sim.assembly))
		parts.append("board=" + _canon(sim.board))
		parts.append("sauces=" + _canon(sim.sauces_used))
		parts.append("sauce_tip=%d" % sim.sauce_tip)
		parts.append("grill=%s" % _arr(sim.grill))
		# 炸炉从单槽 Dictionary 变成一篮一份的 Array，所以这里从 _canon 换成 _arr。
		# 这是**表示层**的变化：单篮时 `{p:..,warned:..}` 变成 `[{p:..,warned:..}]`，
		# 比对基线时把外层那对中括号规范化掉再判等，别看见这行不同就说行为变了。
		parts.append("fryer=%s" % _arr(sim.fryer))
		parts.append("drinking=" + _canon(sim.drink))
		parts.append("jar=%d cooked=%d fire=%.0f wood=%d" % [sim.drink_jar, sim.cooked, sim.fire, sim.wood])
		parts.append("q=[%s]" % " ".join(_q(sim.queue)))
		parts.append("lv=[%s]" % " ".join(_q(sim.leaving)))
		parts.append("n served=%d missed=%d perfects=%d tips=%d combo=%d today=%d col=%d swept=%d coins=%d seq=%d fin=%s" % [
			sim.served, sim.missed, sim.perfects, sim.tips_total, sim.combo,
			sim.today_coins, sim.coins_collected, sim.coins_swept, GameState.coins,
			sim.order_seq, str(sim.finished)])
		parts.append("floor=%s" % _floor(sim.coins))
		parts.append("inv=" + _canon(GameState.inventory))
	if not emits.is_empty():
		parts.append("emit=" + ";".join(emits))
	lines.append(" ".join(PackedStringArray(parts)))


func _q(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		out.append(_cust(c))
	return out


## 顾客这一行只用语义取值：换目标、泛化点单字段都不该改变它
func _cust(c) -> String:
	var cs: Customer = c
	return "sp%d|items=%s|got=%s|miss=%s|st=%s|tip=%d|pat=%d|urge=%s|out=%s" % [
		cs.sp, ",".join(PackedStringArray(cs.order_items())), _canon(cs.got),
		",".join(PackedStringArray(cs.missing_kinds())), cs.state, cs.tip_bonus,
		int(cs.patience * 10.0), str(cs.urged), ("%d/%d" % [cs.out_dir, int(cs.out_t * 10.0)])]


func _floor(arr: Array) -> String:
	var out: Array = []
	for c in arr:
		var cd: Dictionary = c
		out.append("%d@%d,%d t%d" % [int(cd.get("v", 0)), int(cd.get("x", 0)), int(cd.get("y", 0)), int(float(cd.get("t", 0.0)) * 100.0)])
	return ",".join(PackedStringArray(out))


func _arr(a: Array) -> String:
	var out: Array = []
	for v in a:
		out.append(_val(v))
	return "[" + ",".join(PackedStringArray(out)) + "]"


func _canon(d) -> String:
	var dic: Dictionary = d
	var ks: Array = dic.keys()
	ks.sort()
	var out: Array = []
	for k in ks:
		out.append("%s:%s" % [str(k), _val(dic[k])])
	return "{" + ",".join(PackedStringArray(out)) + "}"


func _val(v) -> String:
	if typeof(v) == TYPE_DICTIONARY:
		return _canon(v)
	if typeof(v) == TYPE_ARRAY:
		return _arr(v)
	if typeof(v) == TYPE_FLOAT:
		return "%.3f" % v
	return str(v)
