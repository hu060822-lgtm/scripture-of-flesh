extends TestCase
## 對話系統：資料驗證、條件分支、動作、旗標。

func test_all_dialogue_files_are_valid() -> void:
	var ids := DialogueRunner.all_ids()
	assert_true(ids.size() >= 10, "dialogue files found: %d" % ids.size())
	for id in ids:
		var d := DialogueRunner.load_dialogue(id)
		assert_false(d.is_empty(), "%s parses" % id)
		assert_eq(String(d.get("id", "")), id, "id matches filename")
		var errs := DialogueRunner.validate(d)
		assert_true(errs.is_empty(), "%s: %s" % [id, errs])

func test_validate_catches_broken_links() -> void:
	var d := {"id": "x", "start": "a", "nodes": {"a": {"text": "hi", "next": "missing"},
		"b": {"branches": [{"if": {"flag": "f"}, "next": "a"}]}}}
	var errs := DialogueRunner.validate(d)
	assert_eq(errs.size(), 2, str(errs))

func test_intro_class_choice_emits_action_and_sets_flag() -> void:
	var r := DialogueRunner.new()
	var actions := []
	r.action_requested.connect(func(a, arg): actions.append([a, arg]))
	assert_true(r.start("agnes_intro"))
	assert_eq(r.speaker(), "阿格妮絲")
	var guard := 0
	while r.choices().is_empty() and r.active and guard < 10:
		r.advance(); guard += 1
	assert_eq(r.choices().size(), 5, "five classes")
	assert_false(r.advance(), "cannot skip a choice")
	assert_true(r.choose(1))  # 解剖師
	assert_eq(actions[0], [&"choose_class", "anatomist"])
	assert_true(GameState.has_flag(&"met_agnes"))
	while r.active and guard < 30:
		r.advance(); guard += 1
	assert_false(r.active, "dialogue ends")
	assert_true(actions.has([&"give_item", "suture_kit:2"]))

func test_branches_follow_mutation_and_flags() -> void:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	var r := DialogueRunner.new()
	r.start("agnes_return", p)
	assert_eq(r.node_id, "default")
	(p.get_node("MutationComponent") as MutationComponent).set_value(80.0)
	r.start("agnes_return", p)
	assert_eq(r.node_id, "afraid")
	GameState.set_flag(&"boss_defeated")
	r.start("agnes_return", p)
	assert_eq(r.node_id, "after_boss")

func test_has_item_condition_and_promise() -> void:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	(p.get_node("PlayerData") as PlayerData).inventory.add("umbilical_key")
	var r := DialogueRunner.new()
	r.start("agnes_return", p)
	assert_eq(r.node_id, "key")
	r.advance()
	r.choose(0)
	assert_true(GameState.has_flag(&"agnes_promise"))

func test_ending_choices_depend_on_mutation_and_promise() -> void:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	var mut: MutationComponent = p.get_node("MutationComponent")
	var r := DialogueRunner.new()
	r.start("ending", p)
	assert_eq(r.choices().size(), 1, "only burn by default")
	GameState.set_flag(&"agnes_promise")
	assert_eq(r.choices().size(), 2, "escape with promise")
	mut.set_value(60.0)
	assert_eq(r.choices().size(), 3, "mother at >=50")
	mut.set_value(80.0)
	assert_eq(r.choices().size(), 2, "agnes refuses at >=75")
	var actions := []
	r.action_requested.connect(func(a, arg): actions.append([a, arg]))
	r.choose(1)  # mother
	_finish(r)
	assert_eq(actions, [[&"ending", "mother"]])

## 推進到對話結束（遇到選項就選第一個）。回傳經過的節點 id。
func _finish(r: DialogueRunner) -> Array:
	var seen := []
	var guard := 0
	while r.active and guard < 64:
		seen.append(r.node_id)
		if not r.choices().is_empty():
			r.choose(0)
		else:
			r.advance()
		guard += 1
	return seen

func test_every_story_node_is_reachable() -> void:
	# 每個節點都應該能從 start 走到（分支、選項、next 都算），避免寫了卻永遠看不到的台詞。
	for id in DialogueRunner.all_ids():
		var d := DialogueRunner.load_dialogue(id)
		var nodes: Dictionary = d["nodes"]
		var seen := {}
		var stack := [String(d["start"])]
		while not stack.is_empty():
			var nid: String = stack.pop_back()
			if nid == "" or seen.has(nid) or not nodes.has(nid):
				continue
			seen[nid] = true
			var n: Dictionary = nodes[nid]
			stack.append(String(n.get("next", "")))
			for b in n.get("branches", []):
				stack.append(String(b.get("next", "")))
			for c in n.get("choices", []):
				stack.append(String(c.get("next", "")))
		for nid in nodes:
			assert_true(seen.has(nid), "%s: node %s unreachable" % [id, nid])

func test_opening_narration_sets_flag() -> void:
	var r := DialogueRunner.new()
	assert_true(r.start("prologue_opening"))
	assert_eq(r.speaker(), "", "narrator")
	assert_true(GameState.has_flag(&"opening_seen"))
	assert_eq(_finish(r).size(), 5)

func test_notes_set_lore_flags() -> void:
	var expect := {"note_register": &"read_register", "note_stitcher": &"read_stitcher",
		"note_stripping": &"read_stripping", "note_magdalene": &"knows_mother"}
	for id in expect:
		var r := DialogueRunner.new()
		r.start(id)
		_finish(r)
		assert_true(GameState.has_flag(expect[id]), "%s sets %s" % [id, expect[id]])

func test_agnes_confesses_after_register_once() -> void:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	GameState.set_flag(&"read_register")
	var r := DialogueRunner.new()
	r.start("agnes_return", p)
	assert_eq(r.node_id, "confess")
	assert_true(GameState.has_flag(&"agnes_confessed"))
	_finish(r)
	r.start("agnes_return", p)
	assert_eq(r.node_id, "default", "confession only once")
	GameState.set_flag(&"boss_defeated")
	r.start("agnes_return", p)
	assert_eq(r.node_id, "after_boss_known")

func test_ignatius_reacts_to_mutation_and_gives_kit() -> void:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	var actions := []
	var r := DialogueRunner.new()
	r.action_requested.connect(func(a, arg): actions.append([a, arg]))
	r.start("ignatius_talk", p)
	assert_eq(r.node_id, "i1")
	r.advance(); r.advance()
	assert_eq(r.choices().size(), 4)
	r.choose(1)  # 母親是誰？
	assert_eq(r.node_id, "m1")
	r.advance(); r.advance()
	assert_eq(r.node_id, "ask", "loops back to questions")
	r.choose(3)
	_finish(r)
	assert_true(GameState.has_flag(&"met_ignatius"))
	assert_eq(actions, [[&"give_item", "suture_kit:1"]])
	(p.get_node("MutationComponent") as MutationComponent).set_value(60.0)
	r.start("ignatius_talk", p)
	assert_eq(r.node_id, "worship", "worships a heavily mutated player")

func test_class_specific_corridor_thought() -> void:
	var r := DialogueRunner.new()
	r.start("corridor_thought")
	assert_eq(r.node_id, "df")
	for cls in ["stitcher", "anatomist", "mutilator", "prosthetic_knight", "flesh_witch"]:
		GameState.class_id = StringName(cls)
		r.start("corridor_thought")
		assert_true(r.node_id != "df", "%s has its own line" % cls)

func test_mother_intro_names_and_endings_vary_with_lore() -> void:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	var actions := []
	var r := DialogueRunner.new()
	r.action_requested.connect(func(a, arg): actions.append([a, arg]))
	r.start("mother_intro", p)
	var plain := _finish(r)
	assert_false("named" in plain)
	assert_eq(actions, [[&"start_boss", ""]])
	GameState.set_flag(&"knows_mother")
	GameState.set_flag(&"read_register")
	actions.clear()
	r.start("mother_intro", p)
	var named := _finish(r)
	assert_true("nm1" in named, "can call her by name")
	assert_eq(actions, [[&"start_boss", ""]])
	actions.clear()
	r.start("ending", p)
	var burn := _finish(r)  # 第一個選項：燒掉胎房
	assert_true("burn_heart" in burn)
	assert_eq(actions, [[&"ending", "burn"]], "ending action fires once, at the end")
