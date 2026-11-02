extends TestCase
## 玩家控制器：換武器、普通攻擊的退回順序、撿武器、場景冒煙測試。

const H := preload("res://tests/helpers.gd")

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	return p

func _ctrl(p: Node) -> PlayerController:
	return p.get_node("PlayerController")

func test_player_starts_with_first_weapon_and_switches() -> void:
	var p := _player()
	var c := _ctrl(p)
	assert_eq(c.combat.weapon().id, &"bone_saw_cleaver")
	assert_eq(c.combat.faction, &"player")
	assert_true(c.switch_weapon(2))
	assert_eq(c.combat.weapon().id, &"anatomist_rapier")
	assert_eq(c.equipment.held.size(), 1, "only one weapon held at a time")

func test_player_sever_scale_is_half() -> void:
	var p := _player()
	assert_eq((p.get_node("AnatomyComponent") as AnatomyComponent).sever_chance_scale, 0.5)

func test_light_attack_falls_back_when_disarmed() -> void:
	var p := _player()
	var c := _ctrl(p)
	assert_eq(c.light_attack().id, &"cleaver_light")
	c.combat.anatomy.state.sever_part(&"arm_r")
	assert_eq(c.light_attack().id, &"punch", "left hand punches")
	assert_eq(c.heavy_attack(), null)
	c.combat.anatomy.state.sever_part(&"arm_l")
	assert_eq(c.light_attack().id, &"kick")

func test_pickup_dropped_weapon_with_other_hand() -> void:
	var p := _player()
	var c := _ctrl(p)
	c.combat.anatomy.state.sever_part(&"arm_r")  # 斧頭掉在地上
	var drops := tree.root.get_children().filter(func(n): return n is RigidBody3D and n.get_meta(&"pickup", false))
	assert_eq(drops.size(), 1)
	drops[0].global_position = p.global_position + Vector3(0.5, 0, 0)
	assert_true(c.try_pickup())
	assert_eq(c.combat.weapon().id, &"bone_saw_cleaver")
	assert_eq(c.equipment.weapon_part(), &"arm_l")
	assert_true(drops[0].is_queued_for_deletion())

func test_cannot_switch_to_two_handed_weapon_usefully_with_one_hand() -> void:
	var p := _player()
	var c := _ctrl(p)
	c.combat.anatomy.state.sever_part(&"arm_l")
	assert_true(c.switch_weapon(1), "can hold the hammer")
	assert_false("hammer_light" in c.combat.available_attacks().map(func(a): return String(a.id)), "but cannot swing it one-handed")

func test_sandbox_scenes_run_without_errors() -> void:
	for path in ["res://scenes/sandbox/combat_sandbox.tscn", "res://scenes/sandbox/dismemberment_sandbox.tscn"]:
		var s: Node = load(path).instantiate()
		tree.root.add_child(s)
		assert_true(s.is_inside_tree(), path)
