extends SceneTree
## Minimal headless test runner: godot --headless --script res://tests/run_tests.gd


func _init() -> void:
	var passed := 0
	var failed := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not f.begins_with("test_") or not f.ends_with(".gd") or f == "test_case.gd":
			continue
		var inst = load("res://tests/" + f).new()
		for m in inst.get_method_list():
			var test_name: String = m.name
			if not test_name.begins_with("test_"):
				continue
			inst.failures.clear()
			inst.call(test_name)
			if inst.failures.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL %s::%s" % [f, test_name])
				for line in inst.failures:
					print("    " + line)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
