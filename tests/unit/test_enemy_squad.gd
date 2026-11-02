extends TestCase
## AI-3：攻擊令牌（同時最多 2 隻出手）、包圍站位、外圈等待、呼叫同伴、未生者咬腿、Boss 不佔令牌。

func _enemy(id: String, pos: Vector3) -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % id), StringName("%s_%d" % [id, tree.root.get_child_count()]))
	e.position = pos
	var to := -pos
	e.rotation.y = atan2(-to.x, -to.z)  # 面向原點
	tree.root.add_child(e)
	var ai: EnemyAI = e.get_node("EnemyAI")
	ai.rng.seed = 100 + tree.root.get_child_count()
	return e

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	var pc: CombatComponent = p.get_node("CombatComponent")
	pc.max_hp = 99999.0
	pc.pools.hp = 99999.0
	return p

func _ai(e: Node) -> EnemyAI:
	return e.get_node("EnemyAI")

func _engage(ai: EnemyAI, t: CombatComponent) -> void:
	ai.runtime.target = t
	ai.runtime.time_since_seen = 0.0
	ai.runtime.alert = 1.0
	ai.force_state(&"chase")

func test_tokens_cap_simultaneous_attackers_at_two() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var ais: Array[EnemyAI] = []
	for i in 4:
		var e := _enemy("stitcher", Vector3(1, 0, 0).rotated(Vector3.UP, i * TAU / 4.0))
		ais.append(_ai(e))
		_engage(ais[-1], pc)
	var granted := 0
	for ai in ais:
		if AttackTokens.request(ai, pc):
			granted += 1
	assert_eq(granted, 2, "only two tokens")
	assert_true(AttackTokens.request(ais[0], pc), "holder keeps its token")
	AttackTokens.release(ais[0])
	assert_true(AttackTokens.request(ais[2], pc), "freed token goes to the next")

func test_dead_holder_frees_its_token() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var a := _ai(_enemy("stitcher", Vector3(1, 0, 0)))
	var b := _ai(_enemy("stitcher", Vector3(-1, 0, 0)))
	var c := _ai(_enemy("stitcher", Vector3(0, 0, 1)))
	for ai in [a, b, c]:
		_engage(ai, pc)
	AttackTokens.request(a, pc)
	AttackTokens.request(b, pc)
	assert_false(AttackTokens.request(c, pc))
	a.anatomy.state.sever_part(&"head")
	a.advance(0.05)
	assert_true(AttackTokens.request(c, pc), "dead enemy's token was reclaimed")

func test_never_more_than_two_attacking_in_a_brawl() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var ais: Array[EnemyAI] = []
	for i in 4:
		var e := _enemy("stitcher", Vector3(1.0, 0, 0).rotated(Vector3.UP, i * TAU / 4.0))
		ais.append(_ai(e))
		_engage(ais[-1], pc)
	var max_seen := 0
	var attacks := 0
	for step in 160:
		var now := 0
		for ai in ais:
			ai.advance(0.05)
			ai.combat.advance(0.05)
			ai.body().global_position += ai.desired_velocity * 0.05
			if ai.combat.action in [CombatComponent.Action.WINDUP, CombatComponent.Action.ACTIVE]:
				now += 1
		max_seen = maxi(max_seen, now)
		attacks += now
	assert_true(max_seen <= 2, "at most 2 winding up / striking at once (saw %d)" % max_seen)
	assert_true(attacks > 0, "they still attack")

func test_boss_does_not_take_a_token() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var boss := BossFactory.create_mother()
	boss.position = Vector3(0, 0, -3)
	tree.root.add_child(boss)
	var a := _ai(_enemy("unborn", Vector3(1, 0, 0)))
	var b := _ai(_enemy("unborn", Vector3(-1, 0, 0)))
	assert_true(AttackTokens.request(a, pc))
	assert_true(AttackTokens.request(b, pc))
	assert_true(AttackTokens.request(_ai(boss), pc), "boss always may attack")
	assert_false(_ai(boss) in AttackTokens.holders(pc))

func test_squad_spreads_around_the_target() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	# 三隻都從北方（-Z）接近
	var ais: Array[EnemyAI] = []
	for x in [-0.3, 0.0, 0.3]:
		var ai := _ai(_enemy("stitcher", Vector3(x, 0, -5)))
		_engage(ai, pc)
		ais.append(ai)
	var angles := ais.map(func(ai): return Squad.slot_angle(ai, pc))
	angles.sort()
	assert_true(angles[1] - angles[0] > deg_to_rad(60) and angles[2] - angles[1] > deg_to_rad(60), "slots spread apart: %s" % [angles])
	# 走一段時間後，三隻分布在不同方向
	for step in 120:
		for ai in ais:
			ai.advance(0.05)
			ai.combat.set_blocking(false)
			ai.body().global_position += ai.desired_velocity * 0.05
	var xs := ais.map(func(ai): return ai.body().global_position.x)
	xs.sort()
	assert_true(xs[2] - xs[0] > 1.2, "approached from different sides: %s" % [xs])

func test_waiting_enemies_hold_an_outer_ring() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var holders: Array[EnemyAI] = []
	for i in 2:
		var h := _ai(_enemy("stitcher", Vector3(1, 0, 0).rotated(Vector3.UP, i * PI)))
		_engage(h, pc)
		AttackTokens.request(h, pc)
		holders.append(h)
	var waiter := _ai(_enemy("stitcher", Vector3(0, 0, 4)))
	_engage(waiter, pc)
	waiter.set_intent(&"circle")
	for step in 100:
		waiter.runtime.decision_timer = 1.0  # 固定意圖，只測走位
		waiter.advance(0.05)
		waiter.body().global_position += waiter.desired_velocity * 0.05
	var d := waiter.distance_to(pc)
	assert_true(d > 1.6 and d < 3.2, "waits outside the melee (%.2f m)" % d)

func test_alert_calls_nearby_allies() -> void:
	var p := _player()
	var spotter := _ai(_enemy("stitcher", Vector3(0, 0, -1.5)))
	var ally := _ai(_enemy("many_hands", Vector3(8, 0, -6)))
	ally.body().rotation.y = 0.0  # 背對
	var far := _ai(_enemy("many_hands", Vector3(30, 0, -6)))
	for i in 20:
		spotter.advance(0.05)
	assert_eq(spotter.state(), &"chase")
	assert_eq(ally.state(), &"search", "ally heard the alarm")
	assert_eq(far.state(), &"patrol", "too far to hear")

func test_unborn_go_for_the_legs() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var u := _ai(_enemy("unborn", Vector3(0, 0, -0.8)))
	var bite: AttackDefinition = load("res://content/attacks/bite.tres")
	var legs := 0
	for i in 50:
		var part := PartTargeting.pick(pc, bite, u.definition.injured_target_bias, u.rng, u.definition.preferred_target_parts, u.definition.visual_scale)
		if part in [&"leg_l", &"leg_r"]:
			legs += 1
	assert_eq(legs, 50, "small biters aim low")
