extends Node
## 脚本编译自检：递归加载 scripts/ 与 tests/ 下全部 .gd，任一脚本编译/加载失败即非零退出。
## 用法：godot --headless --path <项目> -- --test=artcheck

func run(_main) -> void:
	var fails: Array = []
	var count := _walk("res://scripts", fails)
	count += _walk("res://tests", fails)
	if fails.is_empty():
		print("ARTCHECK OK scripts=%d" % count)
		get_tree().quit(0)
	else:
		for f in fails:
			push_error("ARTCHECK FAIL " + str(f))
		print("ARTCHECK FAIL count=%d" % fails.size())
		get_tree().quit(1)

func _walk(dir: String, fails: Array) -> int:
	var n := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var path := dir + "/" + name
		if d.current_is_dir():
			n += _walk(path, fails)
		elif name.ends_with(".gd"):
			var s = load(path)
			n += 1
			if s == null:
				fails.append(path)
			# load() 对「带 class_name 且编译失败」的脚本仍会返回一个坏掉的 GDScript 对象，
			# 只判 null 会漏掉整类语法错（day_sim.gd 重名变量那次就是这么溜过去的）
			elif s is GDScript and not (s as GDScript).can_instantiate():
				fails.append(path + " —— 编译失败")
		name = d.get_next()
	return n
