extends Node
## 跨进程存档一致性检查（写、读分两次进程运行，等价于「退出游戏后重新打开」）：
##   godot --headless --path <项目> -- --test=persist_write
##   godot --headless --path <项目> -- --test=persist_read

func run(_m: Node) -> void:
	var mode := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--test="):
			mode = str(a).substr(7)
	if mode == "persist_write":
		GameState.coins = 777
		GameState.day = 3
		GameState.best_combo = 5
		GameState.inventory["patty"] = 9
		SaveManager.ledger["day_records"] = [{"day": 1, "coins": 123, "served": 8, "missed": 0}]
		SaveManager.ledger["orders"] = [{"seq": 1, "day": 1, "customer": "兔小姐", "items": ["经典芝士堡"], "total": 20}]
		var ok := SaveManager.save_all()
		print("PERSIST_WRITE saved=%s path=%s coins=%d day=%d" % [str(ok), SaveManager.save_path(), GameState.coins, GameState.day])
		get_tree().quit(0 if ok else 1)
	elif mode == "persist_read":
		print("PERSIST_READ path=%s coins=%d day=%d best_combo=%d patty=%d ledger_days=%d ledger_orders=%d" % [
			SaveManager.save_path(), GameState.coins, GameState.day, GameState.best_combo,
			GameState.inv_count("patty"), SaveManager.day_records().size(), SaveManager.orders().size()])
		var ok2 := GameState.coins == 777 and GameState.day == 3 and GameState.best_combo == 5 \
			and GameState.inv_count("patty") == 9 \
			and SaveManager.day_records().size() == 1 and SaveManager.orders().size() == 1
		print("PERSIST_READ: %s" % ("OK" if ok2 else "MISMATCH"))
		get_tree().quit(0 if ok2 else 1)
	else:
		print("PERSIST: unknown mode")
		get_tree().quit(2)
