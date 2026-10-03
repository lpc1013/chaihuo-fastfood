extends RefCounted
## 测试环境辅助（TestEnv）：探测目录可写性、解析证据目录。
## res:// 优先仅适用于编辑器/源码运行；导出运行时 res:// 只读（写会形成 exe 旁影子文件且读回不一致），
## 一律回退到 user:// 同名子目录。

static func probe_writable_dir(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var probe := FileAccess.open(path + "/.probe", FileAccess.WRITE)
	if probe == null:
		return false
	probe.store_string("ok")
	probe.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/.probe"))
	return true

static func res_dir_writable(path: String) -> bool:
	# 以编辑器特征为准 + 实际探测；导出运行中不认为 res:// 可写。
	return OS.has_feature("editor") and probe_writable_dir(path)

static func evidence_dir(preferred: String, fallback_sub: String) -> String:
	if res_dir_writable(preferred):
		return preferred
	var fb := "user://" + fallback_sub
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fb))
	return fb
