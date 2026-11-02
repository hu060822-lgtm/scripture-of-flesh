extends TestCase
## Boss 行走的母親：身體資料、階段轉換（跪下→骨盆甲剝落→產聲）、臍帶召喚、死亡。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _boss() -> CharacterBody3D:
	var b := BossFactory.create_mother()
	b.position = Vector3(0, 0, -4)
	tree.root.add_child(b)
	return b

func _phase(b: Node) -> BossPhaseComponent: return b.get_node("BossPhase")
func _combat(b: Node) -> CombatComponent: return b.get_node("CombatComponent")

func test_profile_is_valid_and_has_breakable_parts() -> void:
	var prof: AnatomyProfile = load("res://content/anatomy/walking_mother.tres")
	assert_true(prof.validate().is_empty(), str(prof.validate()))
	var detachable := prof.parts.filter(func(d): return d.detachable)
	assert_true(detachable.size() >= 10, "many breakable parts: %d" % detachable.size())
	assert_true((load("res://content/anatomy/unborn.tres") as AnatomyProfile).validate().is_empty())

func test_womb_is_armored_in_phase_one() -> void:
	var b := _boss()
	var st := _combat(b).anatomy.state
	assert_eq(_phase(b).phase, 1)
	assert_eq(st.get_part(&"womb").def.armor, 10.0)
	var armored: float = DamageResolver.resolve(st, H.no_sever(&"womb", {T.PIERCE: 20.0}), H.rng()).hits[0].hp_loss
	assert_true(armored < 6.0, "armored womb takes little: %s" % armored)
	assert_eq(_phase(b).stilts(), 4)
	assert_eq(_phase(b).cords(), 3)

func test_losing_stilts_makes_her_kneel_exposes_womb_and_screams() -> void:
	var b := _boss()
	var bp := _phase(b)
	var c := _combat(b)
	var st := c.anatomy.state
	var events := []
	bp.phase_changed.connect(func(p): events.append(p))
	var y_before := (b.get_node("Body") as Node3D).position.y
	var speed_before := bp.ai.definition.move_speed
	st.get_part(&"womb").hp = 100.0  # 已受損 50%
	st.sever_part(&"stilt_1")
	assert_eq(bp.phase, 1, "3 stilts still standing")
	st.sever_part(&"stilt_2")
	assert_eq(bp.phase, 2)
	assert_eq(events, [2])
	var womb := st.get_part(&"womb")
	assert_eq(womb.def.armor, 0.0)
	assert_near(womb.hp, 100.0, 0.01, "damage ratio kept")
	assert_true(bp.is_kneeling(), "kneel plays over time (not an instant drop)")
	assert_eq((b.get_node("CreatureAnimator") as CreatureAnimator).current_clip, &"kneel")
	bp.advance(BossPhaseComponent.KNEEL_TIME * 0.3)
	var y_mid := (b.get_node("Body") as Node3D).position.y
	assert_true(y_mid < y_before and y_mid > y_before - BossPhaseComponent.KNEEL_DROP, "partway down")
	bp.advance(BossPhaseComponent.KNEEL_TIME)
	assert_near((b.get_node("Body") as Node3D).position.y, y_before - BossPhaseComponent.KNEEL_DROP, 0.001, "body lowered")
	assert_eq((b.get_node("CreatureAnimator") as CreatureAnimator).override_clip, &"", "animation control handed back")
	assert_near(bp.ai.definition.move_speed, speed_before * BossPhaseComponent.KNEEL_SPEED_FACTOR)
	var res: EnemyDefinition = load("res://content/enemies/walking_mother.tres")
	assert_near(res.move_speed, speed_before, 0.001, "resource not modified")
	assert_eq(c.current_attack.id if c.current_attack else &"", &"birth_scream")
	assert_true(GameState.has_flag(&"mother_kneeled"))
	var exposed: float = DamageResolver.resolve(st, H.no_sever(&"womb", {T.PIERCE: 20.0}), H.rng()).hits[0].hp_loss
	assert_true(exposed > 15.0, "exposed womb takes much more (armored ≈3): %s" % exposed)

func test_cords_summon_unborn_until_cut() -> void:
	var b := _boss()
	var bp := _phase(b)
	bp.advance(30.0)
	assert_eq(bp.adds.size(), 0, "not engaged yet")
	bp.engage()
	bp.summon_timer = 0.01
	bp.advance(0.1)
	assert_eq(bp.adds.size(), 1)
	bp.advance(BossPhaseComponent.SUMMON_INTERVAL)
	assert_eq(bp.adds.size(), 2)
	bp.advance(BossPhaseComponent.SUMMON_INTERVAL)
	assert_eq(bp.adds.size(), BossPhaseComponent.MAX_ADDS, "capped")
	var add: Node3D = bp.adds[0]
	assert_eq(add.get_meta(&"enemy_id"), &"unborn")
	assert_true(add.get_parent() == b.get_parent(), "add spawned in the world")
	# 殺掉一隻 → 可以再召喚
	(add.get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"head")
	bp.advance(BossPhaseComponent.SUMMON_INTERVAL)
	assert_eq(bp.adds.size(), 2)
	# 臍帶全斷 → 不再召喚
	var st := _combat(b).anatomy.state
	for i in range(1, 4):
		st.sever_part(StringName("cord_%d" % i))
	assert_true(GameState.has_flag(&"mother_cords_cut"))
	(bp.adds[0].get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"head")
	bp.advance(BossPhaseComponent.SUMMON_INTERVAL * 3)
	assert_eq(bp.adds.size(), 1)

func test_attacks_drop_out_with_body_parts() -> void:
	var b := _boss()
	var c := _combat(b)
	var ids := func(): return c.available_attacks().map(func(a): return String(a.id))
	assert_true("stilt_stomp" in ids.call())
	assert_true("cradle_crush" in ids.call())
	c.anatomy.state.sever_part(&"cradle_l")
	assert_false("cradle_crush" in ids.call(), "needs both cradling arms")
	for i in range(1, 4):
		c.anatomy.state.sever_part(StringName("stilt_%d" % i))
	assert_false("stilt_stomp" in ids.call())
	assert_true("crawl_grasp" in ids.call(), "she still crawls and grabs")

func test_death_sets_flag_and_kills_adds() -> void:
	var b := _boss()
	var bp := _phase(b)
	bp.engage()
	var add := bp.summon()
	_combat(b).anatomy.state.sever_part(&"head")
	assert_true(_combat(b).is_dead())
	assert_true(GameState.has_flag(&"boss_defeated"))
	assert_true((add.get_node("CombatComponent") as CombatComponent).is_dead())
