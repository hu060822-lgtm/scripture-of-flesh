extends TestCase
## 敵人 AI：攻擊選擇依身體、感知（視覺／聽覺）、狀態轉移、斷肢反應、撤退、縫屍者縫回肢體。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _enemy(id: String, pos: Vector3 = Vector3(0, 0, -2), facing_player: bool = true) -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % id), StringName(id))
	tree.root.add_child(e)
	e.global_position = pos
	if facing_player:
		e.rotation.y = PI  # 面向 +Z（玩家在原點）
	return e

func _player(pos: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	p.global_position = pos
	return p

func _ai(e: Node) -> EnemyAI:
	return e.get_node("EnemyAI")

func _ids(list: Array) -> Array:
	return list.map(func(a): return String(a.id))

func _step(ai: EnemyAI, seconds: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		ai.advance(dt)
		ai.combat.advance(dt)
		t += dt

func test_all_enemy_definitions_are_valid_and_distinct() -> void:
	var profiles := {}
	for id in ["stitcher", "reverse_legged", "faceless_watcher", "many_hands"]:
		var d: EnemyDefinition = load("res://content/enemies/%s.tres" % id)
		assert_eq(d.anatomy_profile.validate().size(), 0, id)
		assert_true(d.attacks.size() >= 2, id)
		profiles[d.anatomy_profile.id] = true
	assert_eq(profiles.size(), 4, "each enemy has its own anatomy")

func test_many_hands_reselects_attacks_as_arms_are_lost() -> void:
	var e := _enemy("many_hands")
	var c: CombatComponent = e.get_node("CombatComponent")
	var st := c.anatomy.state
	assert_eq(_ids(c.available_attacks()), ["flurry", "double_grab", "swipe", "bite"])
	assert_true(AttackSelector.weight_of(load("res://content/attacks/flurry.tres")) > AttackSelector.weight_of(load("res://content/attacks/swipe.tres")), "prefers strongest")
	st.sever_part(&"arm_l1"); st.sever_part(&"arm_r1")
	assert_eq(_ids(c.available_attacks()), ["flurry", "double_grab", "swipe", "bite"], "4 arms still flurry")
	st.sever_part(&"arm_l2")
	assert_eq(_ids(c.available_attacks()), ["double_grab", "swipe", "bite"], "3 arms: no flurry")
	st.sever_part(&"arm_r2"); st.sever_part(&"arm_l3")
	assert_eq(_ids(c.available_attacks()), ["swipe", "bite"], "uses the last arm")
	st.sever_part(&"arm_r3")
	assert_eq(_ids(c.available_attacks()), ["bite"])

func test_reverse_legged_loses_lunge_with_a_leg() -> void:
	var e := _enemy("reverse_legged")
	var c: CombatComponent = e.get_node("CombatComponent")
	assert_true("lunge" in _ids(c.available_attacks()))
	c.anatomy.state.sever_part(&"leg_l")
	assert_false("lunge" in _ids(c.available_attacks()))
	assert_true("spur_kick" in _ids(c.available_attacks()))
	c.anatomy.state.sever_part(&"leg_r")
	assert_eq(_ids(c.available_attacks()), ["claw", "pounce_bite"], "crawls and bites")
	assert_eq(c.movement_multiplier(), 0.15)

func test_faceless_watcher_sees_with_stalks_and_hears_without() -> void:
	var p := _player()
	var e := _enemy("faceless_watcher", Vector3(0, 0, -5))
	var ai := _ai(e)
	var pc: CombatComponent = p.get_node("CombatComponent")
	assert_true(ai.can_see(pc), "sees at 5m with 4 stalks")
	assert_true("gaze" in _ids(ai.combat.available_attacks()))
	for i in range(1, 5):
		ai.anatomy.state.sever_part(StringName("stalk_%d" % i))
	assert_false(ai.can_see(pc), "blind")
	assert_false(ai.can_hear(pc), "too far to hear")
	assert_false("gaze" in _ids(ai.combat.available_attacks()), "cannot gaze without eyes")
	e.global_position = Vector3(0, 0, -3)
	assert_true(ai.can_hear(pc), "hears within 3.5m")

func test_fewer_eyes_shorter_sight() -> void:
	var p := _player()
	var e := _enemy("faceless_watcher", Vector3(0, 0, -11))
	var ai := _ai(e)
	var pc: CombatComponent = p.get_node("CombatComponent")
	assert_true(ai.can_see(pc))
	ai.anatomy.state.sever_part(&"stalk_1"); ai.anatomy.state.sever_part(&"stalk_2")
	assert_false(ai.can_see(pc), "range shrinks to 80% with half the stalks")

func test_patrol_detect_chase_attack_flow() -> void:
	var p := _player()
	var e := _enemy("stitcher", Vector3(0, 0, -1.1))
	var ai := _ai(e)
	var seen := [ai.state()]
	ai.state_changed.connect(func(_o, n): seen.append(n))
	_step(ai, 1.5)
	assert_true(&"detect" in seen, "detected: %s" % [seen])
	assert_true(&"chase" in seen, "chased: %s" % [seen])
	assert_true(&"attack" in seen, "attacked: %s" % [seen])
	var pc: CombatComponent = p.get_node("CombatComponent")
	_step(ai, 2.0)
	assert_true(pc.pools.hp < pc.pools.max_hp, "player took damage")

func test_target_behind_out_of_sight_is_not_detected() -> void:
	var p := _player(Vector3(0, 0, 6))
	var e := _enemy("stitcher", Vector3.ZERO, false)  # 面向 -Z，玩家在背後 6m
	var ai := _ai(e)
	# 只測感知本身（巡邏會轉身，轉向玩家時會看見是正常行為）
	ai.perceive(0.1)
	assert_false(ai.can_see(p.get_node("CombatComponent")))
	assert_eq(ai.runtime.target, null)
	assert_eq(ai.state(), &"patrol")

func test_being_hit_from_behind_alerts_and_targets_attacker() -> void:
	var p := _player(Vector3(0, 0, 6))
	var e := _enemy("stitcher", Vector3.ZERO, false)
	var ai := _ai(e)
	ai.combat.receive_hit(H.no_sever(&"chest", {T.CUT: 3.0}), p.get_node("CombatComponent"))
	_step(ai, 0.1)
	assert_eq(ai.state(), &"chase")

func test_dismember_reaction_then_reevaluate() -> void:
	_player()
	var e := _enemy("many_hands", Vector3(0, 0, -1.2))
	var ai := _ai(e)
	_step(ai, 0.5)
	ai.anatomy.state.sever_part(&"arm_l1")
	assert_eq(ai.state(), &"dismember_react")
	assert_eq(ai.runtime.last_severed_part, &"arm_l1")
	_step(ai, ai.definition.dismember_react_seconds + 0.1)
	assert_true(ai.state() in [&"chase", &"attack", &"defend"], "back to fighting: %s" % ai.state())

func test_retreats_when_no_attack_remains() -> void:
	_player()
	var e := _enemy("faceless_watcher", Vector3(0, 0, -2))
	var ai := _ai(e)
	for id in [&"stalk_1", &"stalk_2", &"stalk_3", &"stalk_4", &"arm_l", &"arm_r"]:
		ai.anatomy.state.sever_part(id)
	_step(ai, 1.5)
	assert_eq(ai.state(), &"retreat")
	assert_false(AttackSelector.has_any_attack(ai.combat))

func test_stitcher_sews_its_arm_back_unless_interrupted() -> void:
	var p := _player(Vector3(0, 0, 8))
	var e := _enemy("stitcher", Vector3.ZERO)
	var ai := _ai(e)
	var ctrl: DismembermentController = e.get_node("DismembermentController")
	ai.anatomy.state.sever_part(&"arm_r")
	var gibs := tree.root.get_children().filter(func(n): return n is SeveredPart)
	assert_eq(gibs.size(), 1)
	gibs[0].global_position = e.global_position + Vector3(0.5, 0, 0)
	gibs[0].freeze = true
	_step(ai, ai.definition.dismember_react_seconds + 0.1)
	assert_eq(ai.state(), &"special")
	# 縫到一半被打斷
	_step(ai, 1.0)
	ai.combat.receive_hit(H.no_sever(&"chest", {T.CUT: 2.0}), p.get_node("CombatComponent"))
	_step(ai, 0.1)
	assert_eq(ai.state(), &"chase", "interrupted")
	assert_true(ai.anatomy.state.get_part(&"arm_r").severed)
	# 再試一次，這次不打擾
	ai.force_state(&"special")
	_step(ai, RestitchLogic.CHANNEL_SECONDS + 0.2)
	assert_false(ai.anatomy.state.get_part(&"arm_r").severed, "arm sewn back")
	assert_true(gibs[0].is_queued_for_deletion(), "limb consumed")
	assert_true(e.is_ancestor_of(ctrl.segment_for(&"arm_r")), "mesh segment rebuilt on body")
	assert_true(ctrl.hurtbox_for(&"arm_r").active)
	assert_eq(e.find_child("stump_arm_r", true, false).get_node_or_null("cap"), null, "stump cap removed")
	assert_true("claw" in _ids(ai.combat.available_attacks()))

func test_dead_enemy_stops() -> void:
	_player()
	var e := _enemy("stitcher", Vector3(0, 0, -1.1))
	var ai := _ai(e)
	ai.anatomy.state.sever_part(&"head")
	_step(ai, 0.2)
	assert_eq(ai.state(), &"dead")
	assert_eq(ai.desired_velocity, Vector3.ZERO)
	ai.force_state(&"chase")
	assert_eq(ai.state(), &"dead", "cannot leave dead")
