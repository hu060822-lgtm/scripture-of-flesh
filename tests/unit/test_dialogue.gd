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
	r.advance()
	assert_eq(actions, [[&"ending", "mother"]])
