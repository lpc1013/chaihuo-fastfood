extends Node
## 存档与台账（SaveManager）：
## - save_slot1.json：玩家进度（金币/声望/天数/库存/升级/剧情标记）
## - ledger.json：营业台账（每日结算记录 + 逐笔订单明细，可读 JSON）
## 编辑器/源码运行时写入项目内 res://saves/；导出运行时写入用户数据目录 user://saves/（本机用户数据）。

const SAVE_FILE := "save_slot1.json"
const LEDGER_FILE := "ledger.json"
const SAVE_VERSION := 1
const MAX_ORDERS := 500
## 自检模式专用目录。导出包跑自检时 user://saves/ 就是玩家正在玩的那一份，
## 而测试收尾会把"开测前那一刻"的内容写回去——玩家在这期间打完一天，进度就没了。
const TEST_SAVE_DIR := "user://_test_saves/"

var save_dir := "res://saves/"
var save_dir_abs := ""
## 玩家那份存档的目录（use_isolated_saves 之后仍要能报告真实落点）
var save_dir_player := ""
var has_save := false
## 存档文件在、但读不出内容时的原因与备份位置。
## 以前这两种情况都走 `d.is_empty()` 同一个分支：has_save 变 false、标题页把「继续」
## 换成「开始营业」，玩家接着打一局就把那份文件原地覆盖了——进度彻底没了，且没人说过一句。
var load_error := ""
var corrupt_backup_path := ""
var last_saved_at := ""
var ledger: Dictionary = {"version": SAVE_VERSION, "day_records": [], "orders": []}

func _ready() -> void:
	_setup_dir()
	save_dir_player = save_dir
	load_all()

## 只给测试模式调：把存档/台账整体挪到隔离目录，玩家那份一个字节都碰不到。
func use_isolated_saves() -> void:
	save_dir = TEST_SAVE_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	save_dir_abs = ProjectSettings.globalize_path(save_dir)
	has_save = false
	load_all()

func _setup_dir() -> void:
	# 仅编辑器/源码运行优先写 res://saves/；导出运行一律写用户数据目录 user://saves/。
	# 注：导出运行中写 res:// 会形成 exe 旁“影子文件”且读回不一致，因此不能靠探测判定，须以编辑器特征为准。
	var can_res := false
	if OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://saves"))
		var probe := FileAccess.open("res://saves/.probe", FileAccess.WRITE)
		if probe != null:
			probe.store_string("ok")
			probe.close()
			can_res = true
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://saves/.probe"))
	if can_res:
		save_dir = "res://saves/"
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
		save_dir = "user://saves/"
	save_dir_abs = ProjectSettings.globalize_path(save_dir)

func save_path() -> String:
	return save_dir + SAVE_FILE

func ledger_path() -> String:
	return save_dir + LEDGER_FILE

func load_all() -> void:
	load_error = ""
	corrupt_backup_path = ""
	var exists := FileAccess.file_exists(save_path())
	var d := _read_json(save_path())
	if d.is_empty():
		# 文件在、却读不出字典：这是损坏，不是"没玩过"。先把原字节挪走保住，
		# 再当新档处理，否则下一局 save_all() 会直接盖掉它。
		if exists:
			_quarantine_corrupt(save_path())
		GameState.initialize_new()
		ledger = {"version": SAVE_VERSION, "day_records": [], "orders": []}
		has_save = false
		return
	has_save = true
	# apply_save_dict 的形参是 Dictionary，而 JSON 里 player 是什么都有可能（手改过、
	# 半截写入）——直接喂进去会在 _ready 里抛 "Cannot convert argument 1 from Array to
	# Dictionary"，load_all 后半段（读台账、恢复静音）就静默不执行了。
	var player = d.get("player", {})
	if typeof(player) != TYPE_DICTIONARY:
		load_error = "存档内容不像本游戏的存档（player 字段不是对象），已原样留底"
		has_save = false
		_quarantine_corrupt(save_path())
		GameState.initialize_new()
		ledger = {"version": SAVE_VERSION, "day_records": [], "orders": []}
		return
	GameState.apply_save_dict(player)
	var l := _read_json(ledger_path())
	if FileAccess.file_exists(ledger_path()) and l.is_empty():
		_quarantine_corrupt(ledger_path())
	if l.is_empty():
		ledger = {"version": SAVE_VERSION, "day_records": [], "orders": []}
	else:
		ledger = l
		if not ledger.has("day_records"):
			ledger["day_records"] = []
		if not ledger.has("orders"):
			ledger["orders"] = []
	# 一致性校验：玩家存档与台账必须属于同一次提交。若某次 save_all 里台账写盘失败、
	# 玩家存档写成功，两者 commit_id 就会对不上——这正是审计点名的"钱和天数更新了、
	# 营业记录却没更新"的脏状态。这里必须告警，但玩家进度以存档为准，绝不能丢。
	var player_cid = d.get("commit_id", "")
	if l.has("commit_id") and str(player_cid) != "" and str(l["commit_id"]) != str(player_cid):
		load_error = "玩家存档与营业台账不是同一次提交（台账可能没存上），已按玩家存档为准"
		push_warning("[SaveManager] " + load_error)
	GameState.set_muted(GameState.muted)

func save_all() -> bool:
	# 每次保存生成一个 commit_id，同时写进玩家存档与台账，作为"两份文件属于同一次提交"的凭据。
	var cid := _next_commit_id()
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"commit_id": cid,
		"player": GameState.to_save_dict()
	}
	ledger["commit_id"] = cid
	var ok := _write_json(save_path(), payload)
	var ok2 := _write_json(ledger_path(), ledger)
	last_saved_at = str(payload["saved_at"])
	# 玩家进度是权威状态：只要它落盘成功，就认为"有存档"。台账若写入失败，
	# 会在下次 load 时通过 commit_id 不一致被捕获并告警，而不是被静默吞掉。
	has_save = ok
	return ok and ok2

func wipe() -> void:
	for f in [save_path(), ledger_path(), save_path() + ".bak", ledger_path() + ".bak", save_path() + ".tmp", ledger_path() + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	ledger = {"version": SAVE_VERSION, "day_records": [], "orders": []}
	has_save = false

## 同一次 save_all 内的玩家存档与台账共享同一个 id，用于加载时检测"只写了一半"的不一致。
func _next_commit_id() -> String:
	return "%d" % Time.get_ticks_usec()

## 日结算提交：写台账 → 返回是否两文件都落盘成功。
## 返回值让上层（after_day_settled）能在写盘失败时重试，而不是闷头继续推进流程。
func commit_day(record: Dictionary, orders: Array) -> bool:
	ledger["day_records"].append(record)
	for o in orders:
		ledger["orders"].append(o)
	if ledger["orders"].size() > MAX_ORDERS:
		ledger["orders"] = ledger["orders"].slice(ledger["orders"].size() - MAX_ORDERS)
	return save_all()

func day_records() -> Array:
	return ledger.get("day_records", [])

func orders() -> Array:
	return ledger.get("orders", [])

## 把读不出来的存档改名留底（不删），并记下路径给标题页提示用。
## 用 .corrupt-<时间戳>.json 而不是覆盖同名，是为了连续两次损坏也各留一份。
func _quarantine_corrupt(path: String) -> void:
	var raw := FileAccess.get_file_as_string(path)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var dest := path.replace(".json", ".corrupt-%s.json" % stamp)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		load_error = "存档损坏且无法留底（磁盘或权限问题）"
		return
	f.store_string(raw)
	f.close()
	corrupt_backup_path = dest
	load_error = "存档文件读不出来，已原样留到 %s" % dest.get_file()
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("[SaveManager] 损坏存档未能移除: %s err=%d" % [path, err])

## 原子写入：先写临时文件，再把上一版留作 .bak，最后改名覆盖真实文件。
## 进程在写盘途中被掐断，最多留下一个 .tmp（没被改名），而真实文件要么是旧版、要么是完整新版，
## 绝不会是半截内容——这正是"开机读到半截 JSON 直接崩"的根因。改名失败时回滚到 .bak。
func _write_json(path: String, data: Dictionary) -> bool:
	var text := JSON.stringify(data, "  ")
	var tmp := path + ".tmp"
	var tf := FileAccess.open(tmp, FileAccess.WRITE)
	if tf == null:
		push_warning("[SaveManager] 无法写入临时文件: " + tmp)
		return false
	tf.store_string(text)
	tf.close()
	# 把上一版留底，便于改名失败回滚
	if FileAccess.file_exists(path):
		var prev := FileAccess.get_file_as_string(path)
		var bf := FileAccess.open(path + ".bak", FileAccess.WRITE)
		if bf != null:
			bf.store_string(prev)
			bf.close()
		var rem := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if rem != OK:
			push_warning("[SaveManager] 旧文件删除失败: %s err=%d" % [path, rem])
	var dir := ProjectSettings.globalize_path(save_dir).trim_suffix("/")
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("[SaveManager] 无法打开目录做原子替换: " + dir)
		# 退化方案：直接覆盖写（和旧实现等价），保证尽量落盘
		var ff := FileAccess.open(path, FileAccess.WRITE)
		if ff == null:
			return false
		ff.store_string(text)
		ff.close()
		return true
	var err := d.rename(tmp.get_file(), path.get_file())
	if err != OK:
		push_warning("[SaveManager] 原子替换失败，尝试从 .bak 回滚: " + path)
		if FileAccess.file_exists(path + ".bak"):
			var bd := DirAccess.open(dir)
			if bd != null:
				bd.rename((path + ".bak").get_file(), path.get_file())
		return false
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t := f.get_as_text()
	f.close()
	var p = JSON.parse_string(t)
	if typeof(p) != TYPE_DICTIONARY:
		push_warning("[SaveManager] 存档解析失败: " + path)
		return {}
	return p
