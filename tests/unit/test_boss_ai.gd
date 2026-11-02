extends TestCase
## AI-4：行走的母親依位置選招、連段、防逃課（提早召喚／狂暴）、臍帶全斷狂暴。

func _boss(pos: Vector3 = Vector3(0, 0, -2)) -> CharacterBody3D:
	var b := BossFactory.create_mother()
	b.position = pos
	b.rotation.y = PI
	tree.root.add_child(b)
	(b.get_node("EnemyAI") as EnemyAI).rng.seed = 21
	return b

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	var pc: CombatComponent = p.get_node("CombatComponent")
	pc.max_hp = 99999.0
	pc.pools.hp = 99999.0
	return p

func _bp(b: Node) -> BossPhaseComponent: return b.get_node("BossPhase")
func _ai(b: Node) -> EnemyAI: return b.get_node("EnemyAI")

func _count(bp: BossPhaseComponent, d: float, n: int = 400) -> Dictionary:
	var out := {}
	for i in n:
		var a := bp.choose_attack(d)
		if a != null:
			out[a.id] = int(out.get(a.id, 0)) + 1
		bp.combo_queue.clear()
	return out

func test_stomps_when_under_her_and_lashes_from_afar() -> void:
	_player()
	var b := _boss()
	var bp := _bp(b)
	var under := _count(bp, 1.0)
	assert_true(int(under.get(&"stilt_stomp", 0)) > int(under.get(&"cradle_crush", 0)), "under the body: stomp (%s)" % [under])
	var far := _count(bp, 3.0)
	assert_true(int(far.get(&"mother_lash", 0)) > int(far.get(&"stilt_stomp", 0)) + int(far.get(&"cradle_crush", 0)), "far: lash (%s)" % [far])

func test_combo_chains_without_returning_to_chase() -> void:
	var p := _player()
	var b := _boss(Vector3(0, 0, -1.0))
	var bp := _bp(b)
	var ai := _ai(b)
	var combos := []
	bp.combo_started.connect(func(ids): combos.append(ids))
	var started := []
	ai.combat.attack_started.connect(func(a): started.append(a.id))
	ai.runtime.target = p.get_node("CombatComponent")
	ai.runtime.time_since_seen = 0.0
	ai.runtime.alert = 1.0
	# 強制起手招為踐踏並排好連段
	ai.combat.force_attack(bp._attack(&"stilt_stomp"))
	ai.force_state(&"attack")  # 已在出招中：攻擊狀態不會再起手
	bp.combo_queue = [&"mother_lash"]
	var states := {}
	for i in 60:
		ai.advance(0.05)
		ai.combat.advance(0.05)
		states[ai.state()] = true
		if started.size() >= 2:
			break
	assert_true(started.size() >= 2 and started[1] == &"mother_lash", "lash follows stomp: %s" % [started])
	assert_false(states.has(&"chase"), "no pause in between: %s" % [states.keys()])
	# 連段規劃本身
	var planned := 0
	for i in 200:
		bp._plan_combo(&"stilt_stomp")
		if bp.combo_queue == [&"mother_lash"]:
			planned += 1
	assert_true(planned > 80 and planned < 160, "combo about 60%% of the time (%d/200)" % planned)
	assert_true(combos.size() > 0, "combo_started signal")

func test_kiting_player_triggers_an_early_summon() -> void:
	var p := _player()
	var b := _boss(Vector3(0, 0, -12))
	var bp := _bp(b)
	var ai := _ai(b)
	bp.engage()
	ai.runtime.target = p.get_node("CombatComponent")
	bp.summon_timer = 999.0  # 排除一般召喚
	var log := []
	bp.anti_cheese.connect(func(k): log.append(k))
	for i in int((BossPhaseComponent.OUT_OF_REACH_SECONDS + 0.5) / 0.1):
		bp.advance(0.1)
	assert_eq(log, [&"summon"])
	assert_eq(bp.adds.size(), 1, "summoned an unborn early")

func test_cutting_all_cords_enrages_her_briefly() -> void:
	_player()
	var b := _boss()
	var bp := _bp(b)
	var c: CombatComponent = b.get_node("CombatComponent")
	bp.engage()
	var speed := bp.ai.definition.move_speed
	var stagger := c.stagger_threshold
	var log := []
	bp.enraged.connect(func(on): log.append(on))
	for id in [&"cord_1", &"cord_2", &"cord_3"]:
		c.anatomy.state.sever_part(id)
	assert_true(bp.is_enraged())
	assert_near(bp.ai.definition.move_speed, speed * BossPhaseComponent.ENRAGE_SPEED)
	assert_near(c.stagger_threshold, stagger * BossPhaseComponent.ENRAGE_STAGGER, 0.001, "easier to stagger while enraged")
	for i in int(BossPhaseComponent.ENRAGE_SECONDS / 0.1) + 2:
		bp.advance(0.1)
	assert_false(bp.is_enraged())
	assert_near(bp.ai.definition.move_speed, speed, 0.001, "speed restored")
	assert_near(c.stagger_threshold, stagger, 0.001)
	assert_eq(log, [true, false])

func test_kneeling_during_enrage_keeps_the_kneel_slowdown() -> void:
	_player()
	var b := _boss()
	var bp := _bp(b)
	var c: CombatComponent = b.get_node("CombatComponent")
	bp.engage()
	var speed := bp.ai.definition.move_speed
	bp.enrage()
	c.anatomy.state.sever_part(&"stilt_1")
	c.anatomy.state.sever_part(&"stilt_2")
	assert_eq(bp.phase, 2)
	for i in int(BossPhaseComponent.ENRAGE_SECONDS / 0.1) + 2:
		bp.advance(0.1)
	assert_near(bp.ai.definition.move_speed, speed * BossPhaseComponent.KNEEL_SPEED_FACTOR, 0.001)

func test_phase_two_uses_crawl_combos() -> void:
	_player()
	var b := _boss()
	var bp := _bp(b)
	var c: CombatComponent = b.get_node("CombatComponent")
	c.anatomy.state.sever_part(&"stilt_1")
	c.anatomy.state.sever_part(&"stilt_2")
	var ok := false
	for i in 50:
		bp._plan_combo(&"crawl_grasp")
		if bp.combo_queue == [&"cradle_crush"]:
			ok = true
	assert_true(ok, "crawl grasp -> cradle crush in phase 2")

func test_ai_debug_overlay_describes_enemies() -> void:
	var p := _player()
	var b := _boss()
	var ai := _ai(b)
	ai.runtime.target = p.get_node("CombatComponent")
	var o := AiDebugOverlay.new()
	tree.root.add_child(o)
	o.toggle()
	o.refresh()
	var text := AiDebugOverlay.describe(ai)
	assert_true(text.contains("patrol") and text.contains("P1"), text)
	assert_eq(o._labels.size(), 1)
	o.toggle()
	assert_eq(o._labels.size(), 0)
