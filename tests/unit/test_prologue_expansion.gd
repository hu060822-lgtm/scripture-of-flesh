extends TestCase
## 序章 50 分鐘擴充：冷藏室、伊格納支線、恐怖橋段（驚嚇、裝死、靜默區）、聖典殘頁、
## 器官完好度與新器官、異化外觀、異化幻覺。

const H := preload("res://tests/helpers.gd")
const T := DamageTypes.Type

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	return p

func _data(p: Node) -> PlayerData: return p.get_node("PlayerData")
func _combat(p: Node) -> CombatComponent: return p.get_node("CombatComponent")
func _mut(p: Node) -> MutationComponent: return p.get_node("MutationComponent")

func _enemy(path: String, pos: Vector3, id: StringName = &"e") -> CharacterBody3D:
	var e := EnemyFactory.create(load(path), id)
	e.position = pos
	tree.root.add_child(e)
	return e

# ---------- 關卡內容 ----------

func test_level_has_cold_storage_and_expansion_content() -> void:
	var lvl: Node3D = (load(PrologueGame.LEVEL) as PackedScene).instantiate()
	for area in ["ColdStorage", "IleneVault"]:
		assert_true(lvl.get_node_or_null("Geometry/" + area) != null, area)
	var pages := []
	var scares := 0
	var silence := 0
	for n in lvl.get_node("Interactables").get_children():
		if n is ScripturePage:
			pages.append(n.page)
	for n in lvl.get_node("Triggers").get_children():
		if n is ScareTrigger:
			scares += 1
		if n is SilenceZone:
			silence += 1
	pages.sort()
	assert_eq(pages, [1, 2, 3, 4, 5, 6], "six scripture pages")
	assert_true(scares >= 8, "scares %d" % scares)
	assert_eq(silence, 1)
	assert_true(lvl.get_node_or_null("Interactables/Item_item_first_suture") != null)
	assert_true(lvl.get_node_or_null("Altars/Altar_altar_cold_storage") != null)
	var modes := {"alive": 0, "dormant": 0, "corpse": 0}
	var frozen := false
	for s in lvl.get_node("Spawns").get_children():
		modes[s.mode] += 1
		frozen = frozen or s.enemy_path.ends_with("frozen_stitcher.tres")
	assert_true(frozen, "frozen stitcher guards the vault")
	assert_true(modes.dormant >= 4, "playing-dead enemies %s" % modes)
	assert_true(modes.corpse >= 3, "real corpses %s" % modes)
	var priest: DialogueInteractable = lvl.get_node("Interactables/NPC_Ignatius")
	assert_eq(priest.repeat_dialogue_id, "ignatius_return")
	lvl.free()

func test_new_dialogues_are_valid() -> void:
	for id in ["ignatius_return", "note_ilene", "inscription_cold_storage", "cold_storage_thought", "ending", "ignatius_talk",
			"scripture_page_1", "scripture_page_2", "scripture_page_3", "scripture_page_4", "scripture_page_5", "scripture_page_6"]:
		var d := DialogueRunner.load_dialogue(id)
		assert_eq(DialogueRunner.validate(d), [] as Array[String], id)

# ---------- 伊格納支線 ----------

func _run(r: DialogueRunner) -> void:
	var guard := 0
	while r.active and guard < 64:
		if not r.choices().is_empty():
			r.choose(r.choices().size() - 1)
		else:
			r.advance()
		guard += 1

func test_ignatius_quest_turn_in_grants_skill_and_he_dies() -> void:
	var g := PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://test_expansion.json"
	tree.root.add_child(g)
	g.start_game("new")
	var p := g.player
	var r := DialogueRunner.new()
	r.action_requested.connect(g._on_dialogue_action)
	r.start("ignatius_talk", p)
	_run(r)  # 最後一個選項：「……安息吧。」
	assert_true(GameState.has_flag(&"ignatius_quest"), "he asks for the thread")
	r.start("ignatius_return", p)
	assert_eq(r.node_id, "wait", "reminds you where to go")
	_data(p).inventory.add("first_suture")
	r.start("ignatius_return", p)
	assert_eq(r.node_id, "t1")
	_run(r)
	var prog: ProgressionComponent = p.get_node("ProgressionComponent")
	assert_true(&"first_suture" in prog.unlocked, "skill granted")
	assert_eq(_data(p).inventory.count("first_suture"), 0, "thread handed over")
	assert_true(GameState.has_flag(&"ignatius_absolved"))
	r.start("ignatius_return", p)
	assert_eq(r.node_id, "dead")
	g.queue_free()

func test_first_suture_halves_suture_mutation() -> void:
	var p := _player()
	var prog: ProgressionComponent = p.get_node("ProgressionComponent")
	assert_false(prog.can_unlock(&"first_suture"), "cannot be bought with skill points")
	assert_true(prog.grant_skill(&"first_suture"))
	_combat(p).anatomy.state.sever_part(&"arm_l")
	_data(p).inventory.add("suture_kit")
	var before := _mut(p).value
	assert_true(_data(p).start_suture())
	_data(p).advance(10.0)
	assert_near(_mut(p).value - before, PlayerData.SUTURE_MUTATION * 0.5 * (1.0 - _mut(p).resistance()), 0.01)

# ---------- 聖典殘頁 ----------

func test_six_pages_complete_the_scripture_and_add_an_ending_line() -> void:
	var p := _player()
	var msgs := []
	_data(p).message.connect(func(m): msgs.append(m))
	for i in range(1, 7):
		var page := ScripturePage.new()
		page.page = i
		page.dialogue_id = "scripture_page_%d" % i
		tree.root.add_child(page)
		page.global_position = p.global_position
		assert_true(page.interact(p))
		page.queue_free()
	assert_eq(ScripturePage.collected(), 6)
	assert_true(GameState.has_flag(ScripturePage.COMPLETE_FLAG))
	assert_true(msgs[-1].contains("6／6"), msgs[-1])
	var r := DialogueRunner.new()
	r.start("ending", p)
	assert_eq(r.node_id, "scripture", "extra line before the choice")
	r.advance()
	assert_eq(r.node_id, "b")
	GameState.reset()
	r.start("ending", p)
	assert_eq(r.node_id, "b", "no extra line without the pages")

# ---------- 器官完好度、新器官 ----------

func test_harvest_quality_depends_on_how_precisely_you_killed() -> void:
	var p := _player()
	var a := _enemy("res://content/enemies/stitcher.tres", Vector3(1, 0, 0), &"a")
	var ac := _combat(a)
	ac.receive_hit(H.no_sever(&"head", {T.CUT: 300.0}), _combat(p))
	assert_true(ac.is_dead())
	assert_eq(PlayerData.harvest_quality(ac.anatomy.state, OrganRegistry.get_organ(&"stitched_arm")), &"fresh")
	assert_true(_data(p).try_harvest())
	assert_eq(_data(p).inventory.count("organ:stitched_arm"), 1)
	assert_eq(_data(p).inventory.count("fresh:stitched_arm"), 1, "intact donor = fresh organ")
	var opts := TransplantScreen.options_for(p)
	var pred: TransplantService.Prediction = opts[0][2]
	var base := TransplantService.compatibility(OrganRegistry.get_organ(&"stitched_arm"), p.get_node("ProgressionComponent"))
	assert_near(pred.compatibility, minf(1.0, base + TransplantService.FRESH_BONUS), 0.001, "fresh organs take better")
	TransplantScreen.perform(p, OrganRegistry.get_organ(&"stitched_arm"), &"arm_l", H.rng(1))
	assert_eq(_data(p).inventory.count("fresh:stitched_arm"), 0, "fresh marker consumed")
	var b := _enemy("res://content/enemies/stitcher.tres", Vector3(-1, 0, 0), &"b")
	var bs := _combat(b).anatomy.state
	bs.get_part(&"arm_r").hp = bs.get_part(&"arm_r").def.max_hp * 0.3
	assert_eq(PlayerData.harvest_quality(bs, OrganRegistry.get_organ(&"stitched_arm")), &"damaged")
	a.queue_free()
	b.queue_free()

func test_unborn_heart_and_frost_lung() -> void:
	var unborn: EnemyDefinition = load("res://content/enemies/unborn.tres")
	assert_eq(unborn.harvestable[0].id, &"unborn_heart")
	var fz: EnemyDefinition = load("res://content/enemies/frozen_stitcher.tres")
	assert_true(fz.harvestable.any(func(o): return o.id == &"frost_lung"))
	assert_true(fz.max_hp > (load("res://content/enemies/stitcher.tres") as EnemyDefinition).max_hp)
	var p := _player()
	var c := _combat(p)
	var st := c.anatomy.state
	st.replace_part_definition(&"heart", TransplantService.build_definition(OrganRegistry.get_organ(&"unborn_heart"), st.get_part(&"heart").def), &"unborn_heart")
	c.advance(0.1)
	assert_near(c.pools.st_regen_scale, 1.35, 0.001, "restless heart: faster stamina")
	assert_true(OrganRegistry.get_organ(&"frost_lung").template.functions.has("cold_blood"))

# ---------- 裝死、真屍體 ----------

func test_dormant_enemy_waits_until_you_come_close() -> void:
	var p := _player()
	var e := _enemy("res://content/enemies/stitcher.tres", Vector3(6, 0, 0), &"d")
	var ai: EnemyAI = e.get_node("EnemyAI")
	ai.set_dormant(true)
	assert_near((e.get_node("Body") as Node3D).rotation.x, -PI * 0.5, 0.001, "lying down")
	ai._physics_process(0.1)
	assert_true(ai.dormant, "still playing dead")
	p.global_position = Vector3(4.5, 0, 0)
	ai._physics_process(0.1)
	assert_false(ai.dormant, "gets up when you come close")
	var e2 := _enemy("res://content/enemies/stitcher.tres", Vector3(-8, 0, 0), &"d2")
	var ai2: EnemyAI = e2.get_node("EnemyAI")
	ai2.set_dormant(true)
	_combat(e2).receive_hit(H.no_sever(&"chest", {T.CUT: 3.0}), _combat(p))
	assert_false(ai2.dormant, "hitting a corpse wakes it")
	e.queue_free()
	e2.queue_free()

func test_corpse_spawn_is_dead_decor() -> void:
	var s := EnemySpawn.new()
	s.spawn_id = &"decor"
	s.enemy_path = "res://content/enemies/stitcher.tres"
	s.mode = "corpse"
	tree.root.add_child(s)
	var e := s.spawn(tree.root)
	assert_true(_combat(e).is_dead())
	assert_true(e.has_meta(EnemySpawn.CORPSE_META))
	assert_false(GameState.killed.has(&"decor"), "not recorded as a kill")
	assert_eq(e.get_meta(&"harvestable"), [], "no free organs")
	e.queue_free()
	s.queue_free()

# ---------- 靜默區 ----------

func test_silence_zone_mutes_music_until_an_enemy_notices() -> void:
	var am := tree.root.get_node("AudioManager")
	am.director.reset()
	var p := _player()
	var z := SilenceZone.new()
	z.half_extents = Vector2(3, 3)
	tree.root.add_child(z)
	z.global_position = Vector3(20, 0, 0)
	assert_eq(am.director.compute_music_state(), &"explore")
	p.global_position = Vector3(21, 0, 1)
	assert_true(am.director.player_silenced())
	assert_eq(am.director.compute_music_state(), &"silence")
	am.director._combat_hold = 2.0
	assert_eq(am.director.compute_music_state(), &"combat", "an ambush breaks the silence")
	am.director._combat_hold = 0.0
	z.queue_free()

# ---------- 驚嚇事件 ----------

func test_girl_glimpse_shows_once_and_vanishes_when_approached() -> void:
	var p := _player()
	var t := ScareTrigger.new()
	t.trigger_id = &"scare_test_girl"
	t.kind = "girl_glimpse"
	t.radius = 2.0
	t.target_offset = Vector3(0, 0, -8)
	tree.root.add_child(t)
	t.global_position = Vector3(0, 0, 1)
	assert_false(t.figure.visible, "hidden until triggered")
	assert_true(t.check())
	assert_true(t.figure.visible)
	t._process(0.5)
	assert_true(t.elapsed > 0.0, "still there")
	p.global_position = Vector3(0, 0, -5)
	t._process(0.1)
	assert_eq(t.elapsed, -1.0, "vanishes when you get close")
	assert_false(t.check(), "only once")
	t.queue_free()

func test_blackout_restores_lights_and_shows_a_figure() -> void:
	var p := _player()
	var light := OmniLight3D.new()
	light.light_energy = 1.2
	tree.root.add_child(light)
	light.global_position = Vector3(2, 3, 0)
	var t := ScareTrigger.new()
	t.trigger_id = &"scare_test_blackout"
	t.kind = "blackout"
	t.radius = 2.0
	tree.root.add_child(t)
	assert_true(t.check())
	assert_eq(light.light_energy, 0.0, "lights out")
	t._process(1.7)
	assert_near(light.light_energy, 1.2, 0.001, "lights back")
	assert_true(t.figure.visible, "someone is standing there")
	t._process(0.4)
	assert_eq(t.elapsed, -1.0, "then gone")
	light.queue_free()
	t.queue_free()

# ---------- 異化外觀 ----------

func test_mutation_grows_visible_parts_that_fall_off_with_limbs() -> void:
	var p := _player()
	var mv: MutationVisuals = p.get_node("MutationVisuals")
	assert_eq(mv.refresh(), 0, "no growths at 0")
	_mut(p).add(30)
	assert_eq(mv.refresh(), 2, "eyes on the forearm and neck")
	assert_true(p.find_child("Growth_ForearmEye", true, false) != null)
	_mut(p).set_value(80)
	assert_eq(mv.refresh(), 7, "eyes + spurs + back hand + chest mouth")
	_combat(p).anatomy.state.sever_part(&"arm_l")
	assert_eq(mv.growths().size(), 5, "growths on the severed arm went with it")
	_combat(p).anatomy.state.restore_part(&"arm_l")
	assert_eq(mv.refresh(), 7, "grow back after the arm is restored")

# ---------- 異化幻覺 ----------

func test_hallucinations_need_high_mutation_and_vanish() -> void:
	var p := _player()
	var hd := HallucinationDirector.new()
	hd.use_navmesh = false
	tree.root.add_child(hd)
	hd.setup(p)
	hd._process(500.0)
	assert_eq(hd.spawned, 0, "nothing below 50")
	assert_true(hd.interval_for(100.0) < hd.interval_for(50.0), "more often at higher mutation")
	_mut(p).set_value(60)
	hd.rng.seed = 3
	assert_true(hd.spawn())
	assert_true(hd.current is ScareFigure, "a tall figure")
	p.global_position = hd.current.global_position + Vector3(1, 0, 0)
	hd._process(0.1)
	assert_true(hd.current == null, "vanishes when you get close")
	_mut(p).set_value(90)
	var msgs := []
	_data(p).message.connect(func(m): msgs.append(m))
	var tries := 0
	while hd.fake_items == 0 and tries < 20:
		hd._clear()
		hd.spawn()
		tries += 1
	assert_eq(hd.fake_items, 1, "fake glowing organ at high mutation")
	p.global_position = hd.current.global_position
	hd._process(0.1)
	assert_true(msgs.has("……那裡什麼都沒有。"))
	hd.queue_free()

func test_prologue_wires_hallucinations() -> void:
	var g := PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://test_expansion2.json"
	tree.root.add_child(g)
	g.start_game("new")
	assert_true(g.hallucinations != null and g.hallucinations.player == g.player)
	assert_true(g.player.has_node("MutationVisuals"))
	g.queue_free()
