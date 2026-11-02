extends TestCase
## 戰鬥：攻擊可用性（依身體能力與武器）、資源、命中、防禦、閃避、硬直、出血、死亡。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")
const CLEAVER := "res://content/weapons/bone_saw_cleaver.tres"
const HAMMER := "res://content/weapons/reliquary_hammer.tres"
const RAPIER := "res://content/weapons/anatomist_rapier.tres"
const A := CombatComponent.Action

func _naturals() -> Array[AttackDefinition]:
	return [load("res://content/attacks/punch.tres"), load("res://content/attacks/kick.tres"), load("res://content/attacks/bite.tres")]

func _spawn(id: StringName, faction: StringName, pos: Vector3, facing_z_positive: bool = false) -> CharacterBody3D:
	var c := PlaceholderBodyBuilder.build_creature(load(H.HUMANOID), id, _naturals(), faction)
	tree.root.add_child(c)
	c.global_position = pos
	if facing_z_positive:
		c.rotation.y = PI
	return c

func _combat(c: Node) -> CombatComponent:
	return c.get_node("CombatComponent")

func _equip(c: Node, path: String, part: StringName = &"arm_r") -> void:
	(c.get_node("EquipmentComponent") as EquipmentComponent).equip_definition(load(path), part)

func _ids(attacks: Array[AttackDefinition]) -> Array:
	return attacks.map(func(a): return String(a.id))

## 玩家在原點面向 -Z，敵人在 -Z 方向 1.2 公尺面向玩家。
func _duel(weapon: String = CLEAVER) -> Array:
	var p := _spawn(&"player", &"player", Vector3.ZERO)
	var e := _spawn(&"enemy", &"enemy", Vector3(0, 0, -1.2), true)
	_equip(p, weapon)
	return [_combat(p), _combat(e)]

func _run(c: CombatComponent, seconds: float, step: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		c.advance(step)
		t += step

func test_resource_pools_spend_and_regen_after_delay() -> void:
	var r := ResourcePools.new()
	r.setup(100, 100, 100)
	assert_true(r.spend_st(40))
	assert_eq(r.st, 60.0)
	r.tick(0.5)
	assert_eq(r.st, 60.0, "no regen during delay")
	r.tick(0.2); r.tick(1.0)
	assert_true(r.st > 60.0, "regen after delay")
	assert_false(r.spend_ap(10), "AP starts at 0")
	r.add_ap(30)
	assert_true(r.spend_ap(10))
	r.damage_hp(150)
	assert_true(r.is_dead())

func test_available_attacks_follow_body_and_weapon() -> void:
	var cs := _duel()
	var p: CombatComponent = cs[0]
	assert_eq(_ids(p.available_attacks()), ["cleaver_light", "cleaver_heavy", "punch", "kick", "bite"])
	# 斷掉持武器的右臂：武器掉落，武器攻擊消失，拳擊仍可用（左手）
	p.anatomy.state.sever_part(&"arm_r")
	assert_eq(p.weapon(), null)
	assert_eq(_ids(p.available_attacks()), ["punch", "kick", "bite"])
	p.anatomy.state.sever_part(&"arm_l")
	assert_eq(_ids(p.available_attacks()), ["kick", "bite"])
	p.anatomy.state.sever_part(&"jaw")
	assert_eq(_ids(p.available_attacks()), ["kick"])

func test_two_handed_weapon_needs_two_working_hands() -> void:
	var cs := _duel(HAMMER)
	var p: CombatComponent = cs[0]
	assert_true("hammer_light" in _ids(p.available_attacks()))
	p.anatomy.receive(H.no_sever(&"arm_l", {T.CRUSH: 30.0}))  # 左臂功能失效（未斷）
	assert_true(p.weapon() != null, "hammer still held by right arm")
	assert_false("hammer_light" in _ids(p.available_attacks()), "one hand cannot swing the hammer")

func test_attack_costs_stamina_and_heavy_needs_ap() -> void:
	var cs := _duel()
	var p: CombatComponent = cs[0]
	var heavy: AttackDefinition = p.weapon().heavy_attack
	assert_false(p.try_attack(heavy), "no AP yet")
	assert_true(p.try_attack(p.weapon().light_attack))
	assert_eq(p.pools.st, 100.0 - 18.0)
	assert_eq(p.action, A.WINDUP)
	assert_false(p.try_attack(p.weapon().light_attack), "busy")

func test_swing_hits_target_part_and_flows_to_body_hp() -> void:
	var cs := _duel()
	var p: CombatComponent = cs[0]
	var e: CombatComponent = cs[1]
	var landed := []
	p.attack_landed.connect(func(t, r): landed.append(r))
	p.try_attack(p.weapon().light_attack, &"arm_l")
	_run(p, 0.4)
	assert_eq(landed.size(), 1, "hit landed")
	var hit: DamageResult.PartHit = landed[0].hits[0]
	assert_eq(hit.part_id, &"arm_l", "tactical target honored")
	assert_near(e.pools.hp, 100.0 - hit.hp_loss * CombatComponent.BODY_HP_FACTOR, 0.001)
	assert_eq(p.pools.ap, CombatComponent.AP_PER_HIT)
	_run(p, 1.0)
	assert_eq(p.action, A.IDLE)

func test_auto_part_choice_uses_aim_height() -> void:
	var cs := _duel()
	var p: CombatComponent = cs[0]
	var kick: AttackDefinition = load("res://content/attacks/kick.tres")
	var part := p.choose_part(cs[1], kick, &"")
	assert_true(String(part).begins_with("leg") or part == &"abdomen", "low kick hits low part, got %s" % part)
	var head_height := p.choose_part(cs[1], p.weapon().light_attack, &"")
	assert_true(head_height in [&"chest", &"arm_l", &"arm_r", &"spine", &"abdomen"], "torso height swing, got %s" % head_height)

func test_miss_when_out_of_range_or_behind() -> void:
	var p := _spawn(&"player", &"player", Vector3.ZERO)
	_equip(p, CLEAVER)
	var e := _spawn(&"enemy", &"enemy", Vector3(0, 0, 3.0), true)  # 在背後 3 公尺
	var pc := _combat(p)
	var missed := []
	pc.attack_missed.connect(func(a): missed.append(a))
	pc.try_attack(pc.weapon().light_attack)
	_run(pc, 0.4)
	assert_eq(missed.size(), 1)
	assert_eq(_combat(e).pools.hp, 100.0)

func test_same_faction_is_not_hit() -> void:
	var p := _spawn(&"player", &"enemy", Vector3.ZERO)
	_equip(p, CLEAVER)
	var e := _spawn(&"ally", &"enemy", Vector3(0, 0, -1.2), true)
	_combat(p).try_attack(_combat(p).weapon().light_attack)
	_run(_combat(p), 0.4)
	assert_eq(_combat(e).pools.hp, 100.0)

func test_block_reduces_damage_prevents_sever_and_guard_breaks() -> void:
	var cs := _duel()
	var p: CombatComponent = cs[0]
	var e: CombatComponent = cs[1]
	e.set_blocking(true)
	var pkt := DamagePacket.make(&"arm_l", {T.CUT: 30.0})
	pkt.sever_power = 10.0
	var r := e.receive_hit(pkt, p)
	assert_near(r.hits[0].hp_loss, 30.0 * (1.0 - e.block_reduction), 0.001)
	assert_false(r.hits[0].severed, "blocked hits never sever")
	assert_near(e.pools.st, 100.0 - 30.0 * e.block_st_per_damage, 0.001)
	# 體力耗盡 → 破防硬直，全額傷害
	e.pools.st = 5.0
	e.set_blocking(true)
	var broken := []
	e.blocked.connect(func(a, b): broken.append(b))
	r = e.receive_hit(DamagePacket.make(&"arm_r", {T.CRUSH: 10.0}), p)
	assert_eq(broken, [true])
	assert_eq(e.action, A.STAGGER)
	assert_near(r.hits[0].hp_loss, 13.0, 0.001)

func test_block_from_behind_does_not_work() -> void:
	var p := _spawn(&"player", &"player", Vector3.ZERO)
	var e := _spawn(&"enemy", &"enemy", Vector3(0, 0, -1.2))  # 背對玩家
	var ec := _combat(e)
	ec.set_blocking(true)
	var r := ec.receive_hit(H.no_sever(&"arm_l", {T.CRUSH: 5.0}), _combat(p))
	assert_near(r.hits[0].hp_loss, 6.5, 0.001)

func test_dodge_iframes_then_vulnerable_and_needs_legs() -> void:
	var cs := _duel()
	var e: CombatComponent = cs[1]
	assert_true(e.dodge(Vector3.RIGHT))
	assert_eq(e.receive_hit(DamagePacket.make(&"chest", {T.CUT: 10.0}), cs[0]), null, "i-frames")
	_run(e, 0.35)
	assert_true(e.receive_hit(H.no_sever(&"chest", {T.CUT: 1.0}), cs[0]) != null, "after i-frames")
	_run(e, 1.0)
	e.anatomy.state.sever_part(&"leg_l")
	e.anatomy.state.sever_part(&"leg_r")
	assert_false(e.dodge(Vector3.RIGHT), "cannot dodge without legs")

func test_movement_multiplier_by_legs() -> void:
	var cs := _duel()
	var e: CombatComponent = cs[1]
	assert_eq(e.movement_multiplier(), 1.0)
	e.anatomy.state.sever_part(&"leg_l")
	assert_eq(e.movement_multiplier(), 0.45)
	e.anatomy.state.sever_part(&"leg_r")
	assert_eq(e.movement_multiplier(), 0.15)

func test_big_hit_staggers_and_interrupts_windup() -> void:
	var cs := _duel()
	var p: CombatComponent = cs[0]
	var e: CombatComponent = cs[1]
	e.natural_attacks = _naturals()
	assert_true(e.try_attack(load("res://content/attacks/punch.tres")))
	e.receive_hit(H.no_sever(&"chest", {T.CRUSH: 15.0}), p)
	assert_eq(e.action, A.STAGGER)
	assert_eq(e.current_attack, null)

func test_bleeding_drains_body_hp() -> void:
	var cs := _duel()
	var e: CombatComponent = cs[1]
	e.anatomy.receive(H.no_sever(&"leg_l", {T.CUT: 10.0}))  # 出血 1.0/s
	var before := e.pools.hp
	_run(e, 2.0, 0.1)
	assert_near(e.pools.hp, before - 2.0 * CombatComponent.BLEED_HP_FACTOR, 0.01)

func test_decapitation_kills_immediately() -> void:
	var cs := _duel()
	var e: CombatComponent = cs[1]
	var causes := []
	e.died.connect(func(c): causes.append(c))
	e.anatomy.state.sever_part(&"head")
	assert_true(e.is_dead())
	assert_eq(causes, ["vital:head"])
	assert_false(e.try_attack(load("res://content/attacks/kick.tres")))

func test_lung_failure_counts_down_then_dies_unless_restored() -> void:
	var cs := _duel()
	var e: CombatComponent = cs[1]
	var lungs := e.anatomy.state.get_part(&"lungs")
	# 讓肺失效：直接設定 HP 並觸發刷新（內部器官不能直接命中）
	e.anatomy.state.apply_result(_lung_hit(lungs.def.max_hp))
	assert_true(e.vital_timer > 0.0)
	_run(e, e.vital_countdown - 1.0, 0.25)
	assert_false(e.is_dead(), "still alive before countdown ends")
	e.anatomy.state.restore_part(&"lungs")
	assert_eq(e.vital_timer, -1.0, "restoring lungs cancels countdown")
	e.anatomy.state.apply_result(_lung_hit(lungs.def.max_hp))
	_run(e, e.vital_countdown + 0.5, 0.25)
	assert_true(e.is_dead())

func _lung_hit(amount: float) -> DamageResult:
	var r := DamageResult.new()
	var h := DamageResult.PartHit.new()
	h.part_id = &"lungs"
	h.hp_loss = amount
	r.hits.append(h)
	return r

func test_time_scale_slow_and_pause() -> void:
	TimeScale.set_mode(TimeScale.Mode.SLOW)
	assert_near(TimeScale.scaled(1.0), 0.1)
	TimeScale.set_mode(TimeScale.Mode.PAUSE)
	assert_eq(TimeScale.scaled(1.0), 0.0)
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	assert_eq(TimeScale.scaled(1.0), 1.0)
