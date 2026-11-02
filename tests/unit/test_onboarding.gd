extends TestCase
## 新手引導與難度曲線：按鍵名稱、操作說明、一次性情境提示、依序章進度縮放的敵人強度。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func before_each() -> void:
	InputSetup.ensure_actions()
	DifficultyCurve.mode = DifficultyCurve.Mode.EXPONENTIAL

func _player(pos: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var p := PlayerFactory.create()
	p.position = pos
	tree.root.add_child(p)
	return p

func _hints(p: Node3D) -> TutorialHints:
	var h := TutorialHints.new()
	tree.root.add_child(h)
	h.bind(p)
	return h

func _run(h: TutorialHints, seconds: float, dt: float = 0.1) -> Array:
	var shown := []
	h.hint_shown.connect(func(id, _t): shown.append(id))
	var t := 0.0
	while t < seconds:
		h.advance(dt)
		t += dt
	return shown

# ---------- 操作說明 ----------

func test_key_names_follow_the_input_map() -> void:
	assert_eq(KeyNames.of(&"dodge"), "空白鍵")
	assert_eq(KeyNames.of(&"attack_light"), "滑鼠左鍵")
	assert_eq(KeyNames.of(&"help"), "H")
	assert_eq(KeyNames.format("{block} 防禦"), "Shift 防禦")
	assert_eq(KeyNames.of(&"no_such_action"), "未設定")

func test_controls_screen_lists_every_bound_action() -> void:
	var text := ControlsScreen.build_text()
	assert_false(text.contains("未設定"), "every listed action is bound")
	for action in [&"dodge", &"block", &"attack_light", &"attack_heavy", &"tactical", &"use_item", &"menu_body", &"interact", &"surgery"]:
		assert_true(text.contains(KeyNames.of(action)), "lists %s" % action)
	# 每個實際的玩家動作都出現在說明裡
	var listed := {}
	for sec in ControlsScreen.SECTIONS:
		for row in sec[1]:
			for a in (row[0] if row[0] is Array else [row[0]]):
				listed[a] = true
	for action in InputSetup.KEYS.keys() + InputSetup.MOUSE.keys():
		assert_true(listed.has(action), "controls screen covers %s" % action)

func test_controls_screen_pauses_and_restores_time() -> void:
	var c := ControlsScreen.new()
	tree.root.add_child(c)
	c.open()
	assert_true(c.is_open())
	assert_eq(TimeScale.mode, TimeScale.Mode.PAUSE)
	c.close()
	assert_false(c.is_open())
	assert_eq(TimeScale.mode, TimeScale.Mode.NORMAL)
	# 已在其他畫面暫停時，不會擅自恢復
	TimeScale.set_mode(TimeScale.Mode.SLOW)
	c.open()
	c.close()
	assert_eq(TimeScale.mode, TimeScale.Mode.SLOW)

# ---------- 情境提示 ----------

func test_intro_hints_show_once_with_real_key_names() -> void:
	var p := _player()
	var h := _hints(p)
	var texts := []
	h.hint_shown.connect(func(_id, t): texts.append(t))
	var shown := _run(h, TutorialHints.INTRO_DELAY + TutorialHints.SHOW_SECONDS * 2 + 2.0)
	assert_eq(shown, [&"intro", &"interact"])
	assert_true(texts[0].contains("W") and texts[0].contains("H"), texts[0])
	assert_true(GameState.has_flag(&"hint_intro"), "remembered in the save flags")
	var h2 := _hints(p)
	assert_eq(_run(h2, 15.0), [], "not shown again")

func test_combat_hint_when_an_enemy_comes_for_you() -> void:
	var p := _player()
	var h := _hints(p)
	GameState.set_flag(&"hint_intro")
	GameState.set_flag(&"hint_interact")
	var e := EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"s")
	e.position = Vector3(0, 0, -4)
	tree.root.add_child(e)
	var ai: EnemyAI = e.get_node("EnemyAI")
	assert_eq(_run(h, 1.0), [], "idle enemy: no hint")
	ai.runtime.target = p.get_node("CombatComponent")
	ai.runtime.time_since_seen = 0.0
	ai.force_state(&"chase")
	assert_eq(_run(h, 1.0), [&"combat"])

func test_injury_tactical_and_sever_hints_follow_events() -> void:
	var p := _player()
	var h := _hints(p)
	for id in [&"intro", &"interact"]:
		GameState.set_flag(StringName("hint_%s" % id))
	var pc: CombatComponent = p.get_node("CombatComponent")
	pc.anatomy.state.sever_part(&"arm_l")
	assert_true(&"injury" in h.queue, "own part lost")
	var e := EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"s")
	e.position = Vector3(0, 0, -1.0)
	tree.root.add_child(e)
	var r := DamageResult.new()
	var hit := DamageResult.PartHit.new()
	hit.severed = true
	r.hits.append(hit)
	pc.attack_landed.emit(e.get_node("CombatComponent"), r)
	assert_true(&"tactical" in h.queue and &"sever" in h.queue, str(h.queue))
	var shown := _run(h, 30.0)
	assert_eq(shown, [&"injury", &"tactical", &"sever"], "one at a time, in order")

func test_altar_hint_near_an_altar() -> void:
	var p := _player()
	var h := _hints(p)
	GameState.set_flag(&"hint_intro")
	GameState.set_flag(&"hint_interact")
	var altar := StitchingAltar.new()
	altar.position = Vector3(2, 0, 0)
	tree.root.add_child(altar)
	assert_eq(_run(h, 1.0), [&"altar"])

# ---------- 難度曲線 ----------

func test_ramp_is_monotonic_and_exponential_starts_gentler() -> void:
	var prev := -1.0
	for i in 11:
		var v := DifficultyCurve.ramp(i / 10.0)
		assert_true(v > prev, "monotonic")
		prev = v
	assert_near(DifficultyCurve.ramp(0.0), 0.0, 0.001)
	assert_near(DifficultyCurve.ramp(1.0), 1.0, 0.001)
	var expo := DifficultyCurve.ramp(0.5)
	DifficultyCurve.mode = DifficultyCurve.Mode.LINEAR
	assert_near(DifficultyCurve.ramp(0.5), 0.5, 0.001)
	assert_true(expo < 0.3, "exponential stays gentle longer (%s)" % expo)
	DifficultyCurve.mode = DifficultyCurve.Mode.OFF
	assert_eq(DifficultyCurve.ramp(0.0), 1.0)

func test_first_enemies_are_weaker_and_the_boss_is_unchanged() -> void:
	var base: EnemyDefinition = load("res://content/enemies/stitcher.tres")
	var first := DifficultyCurve.apply(base, DifficultyCurve.progress_for(&"corridor_stitcher_1", Vector3.ZERO))
	assert_true(first != base, "a copy, the resource is not modified")
	assert_near(first.max_hp, base.max_hp * 0.65, 0.01)
	assert_near(first.damage_scale, 0.45, 0.01)
	assert_true(first.aggression < base.aggression and first.punish_skill < base.punish_skill)
	assert_eq(first.adaptivity, 0.0, "does not read your habits yet")
	assert_true(first.decision_interval > base.decision_interval, "reacts slower")
	assert_eq(first.squad_attackers, 1)
	assert_eq(first.alarm_radius, 0.0, "does not call friends")
	assert_eq(base.squad_attackers, 0, "resource untouched")
	var mid := DifficultyCurve.apply(base, DifficultyCurve.progress_for(&"sacristy_many_hands", Vector3.ZERO))
	assert_true(mid.max_hp > first.max_hp and mid.max_hp < base.max_hp)
	var boss: EnemyDefinition = load("res://content/enemies/walking_mother.tres")
	assert_eq(DifficultyCurve.apply(boss, DifficultyCurve.progress_for(&"boss", Vector3(0, 0, -74))), boss, "boss at full strength")
	# 依遊玩順序遞增
	var order := [&"corridor_stitcher_1", &"corridor_stitcher_2", &"courtyard_stitcher", &"archive_watcher_1", &"sacristy_many_hands"]
	for i in range(1, order.size()):
		assert_true(DifficultyCurve.progress_for(order[i], Vector3.ZERO) > DifficultyCurve.progress_for(order[i - 1], Vector3.ZERO))

func test_scaled_enemy_hits_softer() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var base: EnemyDefinition = load("res://content/enemies/stitcher.tres")
	var soft := EnemyFactory.create(DifficultyCurve.apply(base, 0.0), &"soft")
	var hard := EnemyFactory.create(base, &"hard")
	tree.root.add_child(soft)
	tree.root.add_child(hard)
	var claw: AttackDefinition = load("res://content/attacks/claw.tres")
	var sp := (soft.get_node("CombatComponent") as CombatComponent).build_packet(claw, &"chest")
	var hp := (hard.get_node("CombatComponent") as CombatComponent).build_packet(claw, &"chest")
	var st := 0.0
	var ht := 0.0
	for k in sp.amounts: st += float(sp.amounts[k])
	for k in hp.amounts: ht += float(hp.amounts[k])
	assert_near(st, ht * 0.45, 0.01)
	assert_near((soft.get_node("CombatComponent") as CombatComponent).max_hp, base.max_hp * 0.65, 0.01)

func test_early_enemies_attack_one_at_a_time() -> void:
	var p := _player()
	var pc: CombatComponent = p.get_node("CombatComponent")
	var easy := DifficultyCurve.apply(load("res://content/enemies/stitcher.tres"), 0.0)
	var ais: Array[EnemyAI] = []
	for i in 2:
		var e := EnemyFactory.create(easy, StringName("e%d" % i))
		e.position = Vector3(1 if i == 0 else -1, 0, 0)
		tree.root.add_child(e)
		var ai: EnemyAI = e.get_node("EnemyAI")
		ai.runtime.target = pc
		ais.append(ai)
	assert_true(AttackTokens.request(ais[0], pc))
	assert_false(AttackTokens.request(ais[1], pc), "only one early enemy attacks at a time")

func test_prologue_spawns_use_the_curve() -> void:
	var s := EnemySpawn.new()
	s.spawn_id = &"corridor_stitcher_1"
	s.enemy_path = "res://content/enemies/stitcher.tres"
	tree.root.add_child(s)
	var e := s.spawn(tree.root)
	assert_eq(e.get_meta(&"difficulty_progress"), 0.0)
	var base: EnemyDefinition = load("res://content/enemies/stitcher.tres")
	assert_near((e.get_node("CombatComponent") as CombatComponent).max_hp, base.max_hp * 0.65, 0.01)
