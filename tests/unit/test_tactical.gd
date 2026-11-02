extends TestCase
## 戰術介面：時間倍率、選擇目標與部位、AP 消耗、預覽不改變狀態、鎖定失效。

const T := DamageTypes.Type

func after() -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)

func _setup() -> Array:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	var e := EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"stitcher")
	e.position = Vector3(0, 0, -1.3)
	e.rotation.y = PI
	tree.root.add_child(e)
	e.get_node("EnemyAI").process_mode = Node.PROCESS_MODE_DISABLED
	return [p.get_node("TacticalController"), p.get_node("PlayerController"), e.get_node("CombatComponent")]

func test_toggle_slows_and_pause_and_restores() -> void:
	var s := _setup()
	var tac: TacticalController = s[0]
	tac.toggle()
	assert_true(tac.active)
	assert_eq(TimeScale.mode, TimeScale.Mode.SLOW, "D3: slow by default")
	tac.toggle_pause()
	assert_eq(TimeScale.mode, TimeScale.Mode.PAUSE)
	tac.toggle_pause()
	assert_eq(TimeScale.mode, TimeScale.Mode.SLOW)
	tac.toggle()
	assert_eq(TimeScale.mode, TimeScale.Mode.NORMAL)
	after()

func test_opening_selects_nearest_enemy_chest_and_cycles_parts() -> void:
	var s := _setup()
	var tac: TacticalController = s[0]
	var ctrl: PlayerController = s[1]
	tac.toggle()
	assert_eq(ctrl.tactical_target, s[2])
	assert_eq(ctrl.tactical_part, &"chest")
	var seen := {}
	for i in 12:
		tac.cycle_part(1)
		seen[ctrl.tactical_part] = true
	assert_false(seen.has(&"heart"), "internal organs are not selectable")
	assert_eq(seen.size(), 12, "all 12 targetable parts reachable")
	after()

func test_targeted_attack_costs_ap_and_hits_chosen_part() -> void:
	var s := _setup()
	var tac: TacticalController = s[0]
	var ctrl: PlayerController = s[1]
	var enemy: CombatComponent = s[2]
	tac.select_target(enemy, &"leg_l")
	ctrl.combat.pools.add_ap(30)
	var landed := []
	ctrl.combat.attack_landed.connect(func(_t, r): landed.append(r.hits[0].part_id))
	assert_true(ctrl.attack_light())
	assert_eq(ctrl.combat.pools.ap, 20.0, "10 AP spent for targeting")
	for i in 10:
		ctrl.combat.advance(0.05)
	assert_eq(landed, [&"leg_l"])
	after()

func test_without_ap_attack_falls_back_to_auto_part() -> void:
	var s := _setup()
	var tac: TacticalController = s[0]
	var ctrl: PlayerController = s[1]
	tac.select_target(s[2], &"leg_l")
	assert_true(ctrl.attack_light())
	assert_eq(ctrl.combat.current_target_part, &"", "no AP -> automatic part")
	assert_eq(ctrl.combat.pools.ap, 0.0)
	after()

func test_preview_matches_resolver_and_does_not_mutate() -> void:
	var s := _setup()
	var tac: TacticalController = s[0]
	var enemy: CombatComponent = s[2]
	tac.select_target(enemy, &"arm_l")
	var pv := tac.preview_light()
	assert_true(pv != null and not pv.rejected)
	assert_true(pv.hits[0].sever_chance > 0.0)
	assert_eq(enemy.anatomy.state.get_part(&"arm_l").hp, enemy.anatomy.state.get_part(&"arm_l").def.max_hp, "preview changed nothing")
	var text := TacticalOverlay.text_for(tac)
	assert_true(text.contains("斷肢機率"), text)
	after()

func test_lock_is_cleared_when_part_severed_or_target_dies() -> void:
	var s := _setup()
	var tac: TacticalController = s[0]
	var ctrl: PlayerController = s[1]
	var enemy: CombatComponent = s[2]
	tac.select_target(enemy, &"arm_r")
	assert_eq(ctrl.targeted_part(), &"arm_r")
	enemy.anatomy.state.sever_part(&"arm_r")
	assert_eq(ctrl.targeted_part(), &"", "severed part no longer targeted")
	tac.select_target(enemy, &"leg_l")
	enemy.anatomy.state.sever_part(&"head")
	assert_eq(ctrl.targeted_part(), &"", "dead target")
	after()

func test_combat_freezes_when_paused() -> void:
	var s := _setup()
	var tac: TacticalController = s[0]
	var ctrl: PlayerController = s[1]
	tac.toggle(); tac.toggle_pause()
	assert_true(ctrl.attack_light())
	var before := ctrl.combat.action
	ctrl.combat.advance(TimeScale.scaled(1.0))
	assert_eq(ctrl.combat.action, before, "no progress while paused")
	after()
