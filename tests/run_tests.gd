extends SceneTree
## Headless 測試執行器。
## 執行：godot --headless --path . -s tests/run_tests.gd
## 結束代碼：0 = 全部通過，1 = 有失敗。

const TEST_DIR := "res://tests/unit"

var _started := false

## 等到第一個 frame 才執行，確保加入場景樹的節點會正常收到 _ready。
func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run_all()
	return false

func _run_all() -> void:
	var total := 0
	var failed := 0
	var files := DirAccess.get_files_at(TEST_DIR)
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		# 只跑部分檔案：TEST_FILTER=conjoined godot ... -s tests/run_tests.gd
		var filt := OS.get_environment("TEST_FILTER")
		if filt != "" and not f.contains(filt):
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
			inst.tree = self
			var existing := root.get_children()
			inst.before_each()
			inst.call(name)
			# 重設全域狀態，避免失敗的測試影響後續測試
			root.get_node("TimeScale").set_mode(0)
			root.get_node("GameState").reset()
			load("res://ai/squad/attack_tokens.gd").reset()  # 不直接引用 class_name（-s 模式下 autoload 尚未就緒）
			# 清除測試加入場景樹的節點（autoload 不受影響）
			for c in root.get_children():
				if not c in existing:
					root.remove_child(c)
					c.free()
			# 被清掉的導航網格要立刻從導航地圖移除，避免影響下一個測試
			NavigationServer3D.map_force_update(root.get_world_3d().navigation_map)
			if inst.failures.is_empty():
				print("PASS   %s::%s" % [f, name])
			else:
				failed += 1
				print("FAIL   %s::%s" % [f, name])
				for msg in inst.failures:
					print("         - %s" % msg)
	print("\n%d tests, %d passed, %d failed" % [total, total - failed, failed])
	quit(1 if failed > 0 else 0)
