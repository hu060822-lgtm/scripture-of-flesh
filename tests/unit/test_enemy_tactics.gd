extends TestCase
## AI-2：戰術評分、讀玩家習慣、趁隙、側翼、打帶跑、遠程保持距離、伏擊、解剖感知瞄準、選招、縫屍者個性。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _enemy(id: String, pos: Vector3 = Vector3(0, 0, -1.2)) -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % id), StringName(id))
	e.position = pos
	e.rotation.y = PI  # 面向 +Z（玩家在原點）
	tree.root.add_child(e)
	var ai: EnemyAI = e.get_node("EnemyAI")
	ai.rng.seed = 11
	return e

## 玩家在原點、面向 -Z（面對敵人）。
func _player(pos: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var p := PlayerFactory.create()
	p.position = pos
	tree.root.add_child(p)
	return p

func _ai(e: Node) -> EnemyAI:
	return e.get_node("EnemyAI")

func _pc(p: Node) -> CombatComponent:
	return p.get_node("CombatComponent")

func _engage(ai: EnemyAI, target: CombatComponent) -> void:
	ai.runtime.target = target
	ai.runtime.time_since_seen = 0.0
	ai.runtime.alert = 1.0

func test_habits_learn_that_the_player_blocks() -> void:
	var p := _player()
	var e := _enemy("many_hands")
	var ai := _ai(e)
	var pc := _pc(p)
	for i in 4:
		ai.combat.action = CombatComponent.Action.WINDUP
		pc.blocking = true
		ai.habits.observe(ai.combat, pc)
		ai.combat.action = CombatComponent.Action.IDLE
		ai.habits.observe(ai.combat, pc)
	assert_eq(ai.habits.samples, 4)
	assert_true(ai.habits.block_rate > 0.7, "learned blocking (%s)" % ai.habits.block_rate)
	assert_true(ai.habits.dodge_rate < 0.01)

func test_attacks_are_preferred_when_the_player_is_recovering() -> void:
	var p := _player()
	var e := _enemy("stitcher")
	var ai := _ai(e)
	var pc := _pc(p)
	_engage(ai, pc)
	var idle: float = Tactics.score(ai, 1.2, 1.1, true)[&"attack"]
	pc.action = CombatComponent.Action.RECOVERY
	var punish: float = Tactics.score(ai, 1.2, 1.1, true)[&"attack"]
	assert_true(punish > idle + 0.3, "punishes recovery (%s > %s)" % [punish, idle])

func test_guarding_player_is_flanked_not_hit_head_on() -> void:
	var p := _player()
	p.rotation.y = 0.0  # 面向 -Z，正對敵人
	var e := _enemy("reverse_legged", Vector3(0, 0, -3.0))
	var ai := _ai(e)
	var pc := _pc(p)
	_engage(ai, pc)
	var open: Dictionary = Tactics.score(ai, 3.0, 3.5, true)
	pc.blocking = true
	var guarded: Dictionary = Tactics.score(ai, 3.0, 3.5, true)
	assert_true(guarded[&"attack"] < open[&"attack"] - 0.4, "does not swing into a guard")
	assert_true(guarded[&"flank"] > guarded[&"attack"], "prefers flanking a guard")
	# 執行側翼：應該移向玩家的側面
	ai.force_state(&"chase")
	ai.set_intent(&"flank")
	var chase = ai._states[&"chase"]
	for i in 60:
		chase._execute(ai, pc, ai.distance_to(pc), 3.5)
		e.global_position += ai.desired_velocity * 0.05
	assert_true(absf(e.global_position.x) > 1.5, "moved to the player's side (x=%s)" % e.global_position.x)
	assert_false(Tactics.target_faces_me(ai, pc) and absf(e.global_position.x) < 0.5, "left the guarded front")

func test_reverse_legged_hits_and_runs() -> void:
	var p := _player()
	var e := _enemy("reverse_legged", Vector3(0, 0, -3.0))
	var ai := _ai(e)
	_engage(ai, _pc(p))
	ai.runtime.since_attack = 0.2
	var s: Dictionary = Tactics.score(ai, 3.0, 3.5, true)
	assert_true(s[&"back_off"] > s[&"attack"], "backs off right after striking")
	ai.runtime.since_attack = INF
	s = Tactics.score(ai, 3.0, 3.5, true)
	assert_true(s[&"attack"] > s[&"back_off"], "strikes again later")

func test_watcher_keeps_its_distance() -> void:
	var p := _player()
	var e := _enemy("faceless_watcher", Vector3(0, 0, -1.5))
	var ai := _ai(e)
	_engage(ai, _pc(p))
	var s: Dictionary = Tactics.score(ai, 1.5, 5.0, true)
	var best: StringName = s.keys().reduce(func(a, b): return a if s[a] >= s[b] else b)
	assert_eq(best, &"back_off", "too close for the watcher: %s" % [s])

func test_legless_enemy_lurks_instead_of_crawling_far() -> void:
	var p := _player()
	var e := _enemy("stitcher", Vector3(0, 0, -6))
	var ai := _ai(e)
	_engage(ai, _pc(p))
	ai.anatomy.state.sever_part(&"leg_l")
	ai.anatomy.state.sever_part(&"leg_r")
	assert_true(Tactics.is_crawling(ai))
	assert_eq(Tactics.decide(ai, 6.0, 1.1, false), &"lurk")

func test_injury_rises_with_lost_parts_and_hp() -> void:
	_player()
	var e := _enemy("many_hands")
	var ai := _ai(e)
	assert_eq(Tactics.injury(ai), 0.0)
	ai.anatomy.state.sever_part(&"arm_l1")
	ai.anatomy.state.sever_part(&"arm_r1")
	assert_true(Tactics.injury(ai) > 0.0)
	ai.combat.pools.hp = ai.combat.pools.max_hp * 0.3
	assert_true(Tactics.injury(ai) >= 0.7)

func test_part_targeting_prefers_injured_parts_at_the_right_height() -> void:
	var p := _player()
	var pc := _pc(p)
	var rng := H.rng(3)
	var claw: AttackDefinition = load("res://content/attacks/claw.tres")  # 攻擊高度 1.3
	var kick: AttackDefinition = load("res://content/attacks/kick.tres")  # 攻擊高度 0.6
	assert_eq(PartTargeting.pick(pc, claw, 1.0, rng), &"", "nothing injured yet")
	var arm := pc.anatomy.state.get_part(&"arm_r")
	arm.hp = arm.def.max_hp * 0.3
	assert_eq(PartTargeting.pick(pc, claw, 1.0, rng), &"arm_r", "goes for the hurt arm")
	assert_eq(PartTargeting.pick(pc, claw, 0.0, rng), &"", "bias 0: never")
	assert_eq(PartTargeting.pick(pc, kick, 1.0, rng), &"", "a kick cannot reach the arm")
	var leg := pc.anatomy.state.get_part(&"leg_l")
	leg.hp = leg.def.max_hp * 0.5
	assert_eq(PartTargeting.pick(pc, kick, 1.0, rng), &"leg_l", "the kick goes for the hurt leg")

func test_part_targeting_bias_is_about_forty_percent() -> void:
	var p := _player()
	var pc := _pc(p)
	var arm := pc.anatomy.state.get_part(&"arm_r")
	arm.hp = arm.def.max_hp * 0.3
	var rng := H.rng(5)
	var claw: AttackDefinition = load("res://content/attacks/claw.tres")
	var hits := 0
	for i in 1000:
		if PartTargeting.pick(pc, claw, 0.4, rng) == &"arm_r":
			hits += 1
	assert_true(hits > 340 and hits < 460, "about 40%% (%d/1000)" % hits)

func test_many_hands_uses_heavier_attacks_against_a_blocker() -> void:
	var p := _player()
	var pc := _pc(p)
	var e := _enemy("many_hands")
	var ai := _ai(e)
	_engage(ai, pc)
	var count := func(n: int) -> float:
		var heavy := 0
		for i in n:
			var a := AttackSelector.select_for(ai, 1.2)
			if a.id in [&"flurry", &"double_grab"]:
				heavy += 1
		return float(heavy) / float(n)
	var normal: float = count.call(600)
	pc.blocking = true
	var vs_guard: float = count.call(600)
	assert_true(vs_guard > normal + 0.05, "more guard pressure (%s -> %s)" % [normal, vs_guard])

func test_stitcher_goes_back_for_its_limb_only_when_safe() -> void:
	var p := _player(Vector3(0, 0, 1.0))
	var e := _enemy("stitcher", Vector3(0, 0, 0))
	var ai := _ai(e)
	_engage(ai, _pc(p))
	ai.anatomy.state.sever_part(&"arm_r")
	var gib = tree.root.get_children().filter(func(n): return n is SeveredPart)[0]
	gib.global_position = e.global_position + Vector3(-0.8, 0, 0)
	gib.freeze = true
	ai.force_state(&"chase")
	ai.runtime.decision_timer = 0.0
	ai.advance(0.05)
	assert_true(ai.state() != &"special", "player too close: keeps fighting")
	p.global_position = Vector3(0, 0, 4.0)
	ai.force_state(&"chase")
	ai.runtime.decision_timer = 0.0
	ai.runtime.time_since_seen = 0.0
	ai.advance(0.05)
	assert_eq(ai.state(), &"special", "player far: goes to sew")

func test_intent_signal_and_varied_behaviour_in_a_duel() -> void:
	var p := _player()
	var e := _enemy("reverse_legged", Vector3(0, 0, -3.0))
	var ai := _ai(e)
	var intents := {}
	ai.intent_changed.connect(func(i): intents[i] = true)
	var pc := _pc(p)
	pc.max_hp = 9999.0
	pc.pools.hp = 9999.0
	for i in 200:
		ai.advance(0.05)
		ai.combat.advance(0.05)
		e.global_position += ai.desired_velocity * 0.05
	assert_true(intents.has(&"attack"), "attacked: %s" % [intents.keys()])
	assert_true(intents.size() >= 3, "mixes tactics, not just stand-and-swing: %s" % [intents.keys()])
	assert_true(pc.pools.hp < 9999.0, "landed hits")
