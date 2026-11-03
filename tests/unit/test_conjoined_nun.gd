extends TestCase
## 主線精英「連體修女」：身體結構、頭被毀的連帶失效、砍斷縫線分裂成兩隻（延續傷勢）、
## 存檔／重生後的重建、前廳的肉膜與祭壇鎖、模型與音效。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")
const NUN := "res://content/enemies/conjoined_nun.tres"

func _nun(pos: Vector3 = Vector3(0, 0, -3), spawn_id: StringName = &"test_conjoined") -> CharacterBody3D:
	var e := EnemyFactory.create(load(NUN), spawn_id)
	e.set_meta(&"spawn_id", spawn_id)
	e.position = pos
	tree.root.add_child(e)
	return e

func _player(pos: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	p.global_position = pos
	return p

func _st(e: Node) -> AnatomyState: return (e.get_node("AnatomyComponent") as AnatomyComponent).state
func _combat(e: Node) -> CombatComponent: return e.get_node("CombatComponent")
func _split(e: Node) -> ConjoinedSplit: return e.get_node("ConjoinedSplit")

func _sisters() -> Array:
	return tree.root.get_children().filter(func(n): return n is CharacterBody3D and String(n.get_meta(&"enemy_id", "")).begins_with("nun_sister") and not n.is_queued_for_deletion())

# ---------- 身體 ----------

func test_profiles_are_valid() -> void:
	for p in ["conjoined", "conjoined_half_a", "conjoined_half_b"]:
		var prof: AnatomyProfile = load("res://content/anatomy/%s.tres" % p)
		assert_true(prof.validate().is_empty(), "%s valid: %s" % [p, prof.validate()])
	var half_a: AnatomyProfile = load("res://content/anatomy/conjoined_half_a.tres")
	assert_true(half_a.get_part(&"leg_l") != null and half_a.get_part(&"leg_r") == null, "left sister keeps the left leg")
	var half_b: AnatomyProfile = load("res://content/anatomy/conjoined_half_b.tres")
	assert_true(half_b.get_part(&"leg_r") != null and half_b.get_part(&"leg_l") == null, "right sister keeps the right leg")

func test_conjoined_has_four_hands_and_flurry() -> void:
	var e := _nun()
	var caps := _st(e).capabilities()
	assert_eq(caps.count("grip"), 4)
	assert_eq(caps.count("bite"), 2)
	assert_eq(caps.count("locomotion"), 2)
	var ids := _combat(e).available_attacks().map(func(a): return a.id)
	assert_true(&"flurry" in ids, "four hands → flurry: %s" % [ids])
	assert_true(e.get_node_or_null("ConjoinedSplit") != null)
	assert_eq(e.get_node("ConjoinedSplit").get_index() > e.get_node("EnemyAI").get_index(), true, "split component after AI")

func test_cutting_inner_arms_removes_flurry() -> void:
	var e := _nun()
	_st(e).sever_part(&"arm_r_a")
	var ids := _combat(e).available_attacks().map(func(a): return a.id)
	assert_false(&"flurry" in ids, "three hands: no flurry")
	assert_true(&"double_grab" in ids)

func test_inner_arms_guard_the_seam() -> void:
	var e := _nun()
	var cs := _split(e)
	cs.update_guard()
	var ctrl: DismembermentController = e.get_node("DismembermentController")
	assert_false(ctrl.hurtbox_for(&"seam").active, "embraced: normal attacks cannot pick the seam")
	assert_true(&"seam" in _st(e).targetable_part_ids(), "tactical targeting still can")
	_st(e).sever_part(&"arm_r_a")
	cs.update_guard()
	assert_false(ctrl.hurtbox_for(&"seam").active, "one inner arm still holds on")
	_st(e).sever_part(&"arm_l_b")
	cs.update_guard()
	assert_true(ctrl.hurtbox_for(&"seam").active, "both inner arms gone: seam exposed")

func test_one_head_destroyed_disables_that_half_but_not_death() -> void:
	var e := _nun()
	var st := _st(e)
	assert_true(st.sever_part(&"head_a"))
	assert_false(_combat(e).is_dead(), "one head is not fatal while conjoined")
	assert_false(st.get_part(&"arm_l_a").is_functional(), "her arms go limp")
	assert_false(st.get_part(&"arm_r_a").is_functional())
	assert_true(st.get_part(&"arm_r_b").is_functional(), "the other sister still fights")
	assert_eq(st.capabilities().count("grip"), 2)

func test_both_heads_destroyed_kills_without_split() -> void:
	var e := _nun()
	var st := _st(e)
	st.sever_part(&"head_a")
	st.sever_part(&"head_b")
	assert_true(_combat(e).is_dead(), "both heads → dead")
	assert_false(_split(e).split_done, "no split")

# ---------- 分裂 ----------

func test_cutting_the_seam_splits_into_two_sisters() -> void:
	var p := _player()
	var e := _nun()
	var ai: EnemyAI = e.get_node("EnemyAI")
	ai.runtime.target = _combat(p)
	assert_true(_st(e).sever_part(&"seam"))
	assert_true(_split(e).split_done, "seam severed → split pending")
	var sisters := _split(e).split()
	assert_eq(sisters.size(), 2)
	assert_true(e.is_queued_for_deletion(), "conjoined body removed")
	var a: Node3D = sisters[0]
	var b: Node3D = sisters[1]
	assert_eq(a.get_meta(&"enemy_id"), &"nun_sister_a")
	assert_eq(b.get_meta(&"enemy_id"), &"nun_sister_b")
	assert_eq(a.get_meta(&"spawn_id"), &"test_conjoined_a")
	assert_true(a.global_position.distance_to(b.global_position) > 0.8, "they stand apart")
	for s in sisters:
		var sai: EnemyAI = s.get_node("EnemyAI")
		assert_eq(sai.state(), &"chase", "sisters go straight for the player")
		assert_eq(sai.runtime.target, _combat(p))
		assert_eq(_st(s).capabilities().count("locomotion"), 1, "one leg each")
		assert_eq(_st(s).capabilities().count("grip"), 2)
	assert_true(GameState.killed.has(&"test_conjoined"))
	assert_true(GameState.has_flag(&"test_conjoined_split"))
	assert_true(tree.root.get_node_or_null("SplitBloodPool") != null, "blood pool left on the floor")

func test_split_runs_only_once() -> void:
	var e := _nun()
	_st(e).sever_part(&"seam")
	var first := _split(e).split()
	assert_eq(first.size(), 2)
	assert_eq(_split(e).split().size(), 0, "deferred second call does nothing")
	assert_eq(_sisters().size(), 2, "no duplicate sisters")

func test_heavy_cut_on_seam_also_splits() -> void:
	var e := _nun()
	var pk := H.no_sever(&"seam", {T.CUT: 200.0})
	_st(e).receive(pk, H.rng(3))
	assert_true(_split(e).split_done, "seam HP 0 → split")

func test_wounds_carry_over_after_split() -> void:
	var e := _nun()
	var st := _st(e)
	st.sever_part(&"arm_l_a")
	st.apply_result(_hit(&"chest_b", 30.0))
	_combat(e).pools.hp = _combat(e).pools.max_hp * 0.5
	st.sever_part(&"seam")
	var sisters := _split(e).split()
	var a: Node = sisters[0]
	var b: Node = sisters[1]
	assert_true(_st(a).get_part(&"arm_l").severed, "left sister's outer arm is still gone")
	assert_true((a.get_node("DismembermentController") as DismembermentController).segment_for(&"arm_l") == null, "its mesh is gone too")
	var hb := (a.get_node("DismembermentController") as DismembermentController).hurtbox_for(&"arm_l")
	assert_true(hb == null or not hb.active, "and its hurtbox")
	assert_false(_st(b).get_part(&"arm_l").severed, "right sister's arms intact")
	assert_near(_st(b).get_part(&"chest").hp, 25.0, 0.01, "chest damage carried (55-30)")
	assert_true(_st(a).get_part(&"chest").bleed_rate >= ConjoinedSplit.TORN_BLEED, "torn side bleeds")
	assert_near(_combat(a).pools.hp, 55.0, 0.5, "HP ratio carried (110 × 0.5)")

func _hit(part: StringName, hp_loss: float) -> DamageResult:
	var r := DamageResult.new()
	var h := DamageResult.PartHit.new()
	h.part_id = part
	h.hp_loss = hp_loss
	r.hits.append(h)
	return r

func test_beheaded_half_falls_dead_on_split() -> void:
	var e := _nun()
	var st := _st(e)
	st.sever_part(&"head_b")
	st.sever_part(&"seam")
	var alive := _split(e).split()
	assert_eq(alive.size(), 1, "only the left sister gets up")
	assert_eq(alive[0].get_meta(&"enemy_id"), &"nun_sister_a")
	var all := _sisters()
	assert_eq(all.size(), 2, "the other half lies there as a corpse")
	var dead: Node = all.filter(func(n): return n.get_meta(&"enemy_id") == &"nun_sister_b")[0]
	assert_true(_combat(dead).is_dead())
	assert_true(dead.has_meta(EnemySpawn.CORPSE_META))
	assert_true(GameState.killed.has(&"test_conjoined_b"), "counts as killed")

# ---------- 生成點、肉膜、祭壇 ----------

func _spawn_node() -> ConjoinedSpawn:
	var s := ConjoinedSpawn.new()
	s.spawn_id = &"ante_test"
	s.enemy_path = NUN
	s.defeat_flag = &"test_nun_defeated"
	tree.root.add_child(s)
	return s

func test_spawn_defeat_logic() -> void:
	var s := _spawn_node()
	assert_false(s.is_defeated())
	GameState.killed[&"ante_test"] = true
	assert_true(s.is_defeated(), "killed while conjoined")
	GameState.set_flag(&"ante_test_split")
	assert_false(s.is_defeated(), "split: both sisters must die")
	GameState.killed[&"ante_test_a"] = true
	assert_false(s.is_defeated())
	GameState.killed[&"ante_test_b"] = true
	assert_true(s.is_defeated())
	s._physics_process(0.016)
	assert_true(GameState.has_flag(&"test_nun_defeated"))

func test_spawn_rebuilds_remaining_sister_after_reload() -> void:
	var s := _spawn_node()
	var e := s.spawn(tree.root)
	assert_eq(e.get_meta(&"enemy_id"), &"conjoined_nun", "fresh: conjoined")
	e.free()
	GameState.killed[&"ante_test"] = true
	GameState.set_flag(&"ante_test_split")
	GameState.killed[&"ante_test_a"] = true
	var r := s.spawn(tree.root)
	assert_true(r != null)
	assert_eq(r.get_meta(&"enemy_id"), &"nun_sister_b", "only the surviving sister comes back")
	assert_eq(r.get_meta(&"spawn_id"), &"ante_test_b")
	assert_eq(_sisters().size(), 1)

func test_seal_and_altar_wait_for_defeat() -> void:
	var lvl: Node3D = (load(PrologueGame.LEVEL) as PackedScene).instantiate()
	tree.root.add_child(lvl)
	var spawn := lvl.get_node("Spawns/Spawn_antechamber_conjoined") as ConjoinedSpawn
	assert_true(spawn != null, "conjoined nun is placed")
	assert_true(spawn.position.z < -46.0 and spawn.position.z > -58.0, "inside the antechamber (after the chapel gate)")
	var seal := lvl.get_node("Secrets/FleshSeal_Chapel") as SecretWall
	assert_eq(seal.open_flag, spawn.defeat_flag)
	assert_false(seal.is_open)
	var altar := lvl.get_node("Altars/Altar_altar_antechamber") as StitchingAltar
	var p := _player(altar.global_position)
	assert_false(altar.in_range(p), "altar locked mid-fight")
	GameState.set_flag(spawn.defeat_flag)
	seal._physics_process(0.016)
	assert_true(seal.is_open, "seal opens")
	assert_true(altar.in_range(p), "altar usable after the fight")

func test_prologue_game_spawns_the_nun_and_records_split_kills() -> void:
	var g := PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://test_conjoined_save.json"
	tree.root.add_child(g)
	g.start_game("new")
	var nuns := g.level.get_children().filter(func(n): return n.get_meta(&"enemy_id", &"") == &"conjoined_nun")
	assert_eq(nuns.size(), 1, "the elite is on the main path")
	var e: Node = nuns[0]
	_st(e).sever_part(&"seam")
	var sisters := _split(e).split()
	for s in sisters:
		_combat(s)._die("test")
	var spawn := g.level.get_node("Spawns/Spawn_antechamber_conjoined") as ConjoinedSpawn
	spawn._physics_process(0.016)
	assert_true(GameState.has_flag(&"conjoined_defeated"), "both sisters dead → defeated")
	if FileAccess.file_exists(g.save_path):
		DirAccess.remove_absolute(g.save_path)

# ---------- 外觀與聲音 ----------

func test_models_are_low_poly_and_show_the_seam() -> void:
	var e := _nun()
	var tri := CreatureModels.triangle_count(e)
	assert_true(tri > 300 and tri < 6000, "low-poly budget: %d" % tri)
	var seam := (e.get_node("DismembermentController") as DismembermentController).segment_for(&"seam")
	assert_true(seam != null and seam.find_child("Stitch0", false, false) != null, "seam has gold stitches")
	var head := (e.get_node("DismembermentController") as DismembermentController).segment_for(&"head_a")
	assert_true(head.find_child("Blindfold", false, false) != null, "sewn blindfold")
	_st(e).sever_part(&"seam")
	var a: Node = _split(e).split()[0]
	var chest := (a.get_node("DismembermentController") as DismembermentController).segment_for(&"chest")
	assert_true(chest.find_child("TornFlesh", false, false) != null, "sister shows the torn side")

func test_twin_cues_have_synth_files() -> void:
	for cue in [&"twin_hymn", &"twin_split"]:
		assert_true(SoundCatalog.TABLE.has(cue), "%s in catalog" % cue)
		assert_true(SoundCatalog.load_streams("res://audio/sfx/%s" % cue).size() >= 2, "%s has variants" % cue)
