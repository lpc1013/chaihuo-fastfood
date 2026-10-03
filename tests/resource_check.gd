extends Node
## 资源完整性检查：加载全部脚本 / 场景 / 贴图，捕获解析与导入错误。

var failures: Array = []

func _ready() -> void:
	var files: Array = []
	files.append_array(_collect("res://scripts", "gd"))
	files.append_array(_collect("res://scripts", "tscn"))
	files.append_array(_collect("res://scenes", "tscn"))
	files.append_array(_collect("res://tests", "gd"))
	files.append_array(_collect("res://tests", "tscn"))
	var total := files.size()
	for f in files:
		var res = ResourceLoader.load(str(f))
		if res == null:
			failures.append("FAIL: " + str(f))
			print("LOAD FAIL: ", f)
		else:
			print("ok: ", f)
	var tex_count := 0
	for f2 in _collect("res://assets/art", "png"):
		var res2 = ResourceLoader.load(str(f2))
		if res2 == null:
			failures.append("FAIL: " + str(f2))
			print("TEX FAIL: ", f2)
		else:
			tex_count += 1
	print("CHECK DONE: %d res files, %d textures, %d failures" % [total, tex_count, failures.size()])
	for x in failures:
		print(x)
	if failures.is_empty():
		print("RESULT: OK")
		get_tree().quit(0)
	else:
		print("RESULT: FAIL")
		get_tree().quit(1)

func _collect(dir_path: String, ext: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var path := dir_path + "/" + name
		if d.current_is_dir():
			out.append_array(_collect(path, ext))
		elif ext == "" or name.get_extension().to_lower() == ext:
			out.append(path)
		name = d.get_next()
	d.list_dir_end()
	return out
