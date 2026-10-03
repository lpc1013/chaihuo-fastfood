extends SceneTree
## 一次性工具：实测关键文案在字体下的像素宽度（用于排版核对）。
##   godot --headless --path <项目> --script res://tests/measure.gd

func _init() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans SC", "SimHei", "sans-serif"])
	print("DESC_AVAILABLE(11pt): 194.2 px  (uw=339.2, 升级卡描述列宽 uw-145)")
	var strings: Array = [
		"烤架从 2 眼升级为 3 眼，可同时煎更多肉饼。",
		"烤架升级为 3 眼，可同时煎更多肉饼。",
		"烤架升级为 3 眼，同时煎更多肉饼。",
		"炉火消耗降低 35%，烹饪速度 +10%。",
		"炉火消耗降 35%，烹饪提速 10%。",
		"顾客耐心流失速度 -15%。",
		"每成功出餐一笔，小费额外 +2。",
		"每天多接待 2 位客人。",
	]
	for s in strings:
		var w11: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var w10: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		print("w11=%.1f w10=%.1f | %s" % [w11, w10, s])
	quit()
