extends TestCase
## 存檔：往返、版本遷移、斷肢與移植器官還原、模型同步。

const T := DamageTypes.Type
const PATH := "user://test_save_roundtrip.json"

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create(["res://content/weapons/reliquary_hammer.tres"], "res://content/classes/stitcher.tres")
	tree.root.add_child(p)
	return p

func _combat(p: Node) -> CombatComponent: return p.get_node("CombatComponent")

func test_roundtrip_restores_body_progress_flags_and_inventory() -> void:
	var p := _player()
	var c := _combat(p)
	var st := c.anatomy.state
	st.sever_part(&"arm_l")
	var organ := OrganRegistry.get_organ(&"iron_arm")
	assert_true(organ != null, "iron_arm organ exists")
	st.replace_part_definition(&"arm_r", TransplantService.build_definition(organ, st.get_part(&"arm_r").def), organ.id)
	st.get_part(&"leg_l").hp = 7.0
	(p.get_node("ProgressionComponent") as ProgressionComponent).add_xp(150)
	(p.get_node("MutationComponent") as MutationComponent).add(30)
	(p.get_node("PlayerData") as PlayerData).inventory.add("organ:watcher_eye")
	(p.get_node("PlayerController") as PlayerController).switch_weapon(1)
	GameState.set_flag(&"met_agnes")
	GameState.checkpoint_altar = &"altar_corridor"
	GameState.killed[&"spawn_1"] = true
	assert_eq(SaveSystem.save_game(p, PATH), OK)

	GameState.reset()
	p.queue_free()
	var q := _player()
	var data := SaveSystem.read(PATH)
	assert_eq(int(data["version"]), SaveSystem.VERSION)
	SaveSystem.apply(q, data)
	var qc := _combat(q)
	var qs := qc.anatomy.state
	assert_true(qs.get_part(&"arm_l").severed, "arm_l severed")
	assert_eq(qs.organs.get(&"arm_r"), &"iron_arm")
	assert_eq(qs.get_part(&"arm_r").def.max_hp, st.get_part(&"arm_r").def.max_hp)
	assert_near(qs.get_part(&"leg_l").hp, 7.0)
	assert_false(qs.capabilities().has(&"grip_l"), "no left grip after load")
	# 表現層同步：左臂模型被移除、斷面出現
	var marker := q.find_child("stump_arm_l", true, false)
	assert_true(marker != null and marker.get_node_or_null("cap") != null, "stump cap attached")
	var dm: DismembermentController = q.get_node("DismembermentController")
	var seg := dm.segment_for(&"arm_l")
	assert_true(seg == null or not q.is_ancestor_of(seg), "arm_l segment detached")
	var prog: ProgressionComponent = q.get_node("ProgressionComponent")
	assert_eq(prog.xp, (p.get_node("ProgressionComponent") as ProgressionComponent).xp)
	assert_true(prog.level >= 2, "leveled")
	assert_eq(prog.level, (p.get_node("ProgressionComponent") as ProgressionComponent).level)
	assert_near((q.get_node("MutationComponent") as MutationComponent).value, 30.0, 0.5)
	assert_true((q.get_node("PlayerData") as PlayerData).inventory.count("organ:watcher_eye") == 1)
	assert_eq((q.get_node("PlayerController") as PlayerController).weapon_index, 1)
	assert_true(GameState.has_flag(&"met_agnes"))
	assert_eq(GameState.checkpoint_altar, &"altar_corridor")
	assert_true(GameState.killed.has(&"spawn_1"))
	DirAccess.remove_absolute(PATH)

func test_missing_file_returns_empty_and_unknown_ids_are_ignored() -> void:
	assert_eq(SaveSystem.read("user://does_not_exist.json"), {})
	var q := _player()
	var data := {"version": 1, "player": {"weapons": ["no_such_weapon", "reliquary_hammer"],
		"anatomy": {"parts": {"no_such_part": {"hp": 1.0}, "head": {"hp": 3.0}}}}}
	SaveSystem.apply(q, data)
	assert_near(_combat(q).anatomy.state.get_part(&"head").hp, 3.0)
	assert_eq((q.get_node("PlayerController") as PlayerController).weapons.size(), 1)

func test_migrate_stamps_version_on_old_data() -> void:
	var d := SaveSystem.migrate({"player": {}})
	assert_eq(int(d["version"]), SaveSystem.VERSION)
