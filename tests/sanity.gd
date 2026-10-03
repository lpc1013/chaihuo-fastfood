extends Node2D
# 首次冒烟测试：窗口能否打开、截图能否落盘、SystemFont 中文能否渲染

var frames := 0

func _ready() -> void:
	DisplayServer.window_set_title("柴火快餐 Sanity")
	var cr := ColorRect.new()
	cr.size = Vector2(1280, 720)
	cr.color = Color(0.13, 0.10, 0.18)
	add_child(cr)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	var l := Label.new()
	l.text = "柴火快餐 · 毒舌厨神重出江湖\n中文渲染检测 OK"
	l.position = Vector2(120, 160)
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", 56)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.43))
	add_child(l)
	print("SANITY ready, display=", DisplayServer.get_name())

func _process(_delta: float) -> void:
	frames += 1
	if frames == 30:
		_screenshot("window")
	if frames >= 45:
		print("SANITY OK")
		get_tree().quit(0)

func _screenshot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SHOT skipped (headless)")
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://screenshots/sanity/sanity_%s.png" % tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/sanity"))
	var err := img.save_png(path)
	print("SHOT ", tag, " err=", err, " path=", path)
