extends Node
## 配置探针：打印关键数值后退出（用于验证“只改 JSON 即生效”）。
##   godot --headless --path <项目> -- --test=probe

func run(_m: Node) -> void:
	print("PROBE burger0_price=", Config.burger(0).get("price", -1))
	print("PROBE burger2_price=", Config.burger(2).get("price", -1))
	print("PROBE species0_patience_mult=", Config.species(0).get("patience_mult", -1))
	print("PROBE day1_plan_size=", Config.day_plan(1).size())
	print("PROBE day4_plan_size=", Config.day_plan(4).size())
	print("PROBE fire_decay_per_sec=", Config.fire.get("decay_per_sec", -1))
	print("PROBE upgrade_count=", Config.upgrade_defs().size())
	print("PROBE total_days=", Config.total_days())
	print("PROBE spawn_gap_base=", Config.economy.get("spawn", {}).get("gap_base", -1))
	get_tree().quit(0)
