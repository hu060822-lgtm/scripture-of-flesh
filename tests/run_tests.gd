extends SceneTree
## Headless 測試執行器。
## 執行：godot --headless --path . -s tests/run_tests.gd
## 結束代碼：0 = 全部通過，1 = 有失敗。

const TEST_DIR := "res://tests/unit"

func _init() -> void:
	var total := 0
	var failed := 0
	var files := DirAccess.get_files_at(TEST_DIR)
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load(TEST_DIR.path_join(f))
		if script == null or not script.can_instantiate():
			print("ERROR  could not load %s" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			var inst: TestCase = script.new()
			inst._current = name
			inst.before_each()
			inst.call(name)
			if inst.failures.is_empty():
				print("PASS   %s::%s" % [f, name])
			else:
				failed += 1
				print("FAIL   %s::%s" % [f, name])
				for msg in inst.failures:
					print("         - %s" % msg)
	print("\n%d tests, %d passed, %d failed" % [total, total - failed, failed])
	quit(1 if failed > 0 else 0)
