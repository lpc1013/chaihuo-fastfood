extends Node
## 环境探针：打印构建类型与路径映射（编辑器 与 导出包 行为对比用）。
##   godot --headless --path <项目> -- --test=envcheck
##   ChaihuoFastFood.exe --headless -- --test=envcheck

func run(_m: Node) -> void:
	print("ENV editor_feature=", OS.has_feature("editor"))
	print("ENV debug_build=", OS.is_debug_build())
	print("ENV exe_path=", OS.get_executable_path())
	print("ENV res_glob=", ProjectSettings.globalize_path("res://"))
	print("ENV res_saves_glob=", ProjectSettings.globalize_path("res://saves"))
	print("ENV user_saves_glob=", ProjectSettings.globalize_path("user://saves"))
	print("ENV project_binary_exists=", FileAccess.file_exists("res://project.binary"))
	print("ENV save_dir_current=", SaveManager.save_dir)
	print("ENV save_dir_player=", SaveManager.save_dir_player)
	print("ENV save_path=", SaveManager.save_path())
	get_tree().quit(0)
