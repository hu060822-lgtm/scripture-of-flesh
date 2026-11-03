extends TestCase
## 失血修正（自然凝血、保底、壓迫止血）、異常狀態圖標、人體剪影、傷殘部位外觀。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create([])
	tree.root.add_child(p)
	return p

func _data(p: Node) -> PlayerData: return p.get_node("PlayerData")
func _combat(p: Node) -> CombatComponent: return p.get_node("CombatComponent")
func _state(p: Node) -> AnatomyState: return _combat(p).anatomy.state
func _iv(p: Node) -> InjuryVisuals: return p.get_node("InjuryVisuals")

func _run(c: CombatComponent, seconds: float, step: float = 0.1) -> void:
	var t := 0.0
	while t < seconds:
		c.advance(step)
		t += step

# ---------- 失血 ----------

func test_bleeding_decays_with_exact_integral() -> void:
	var s := H.humanoid()
	s.bleed_half_life = 8.0
	s.receive(H.no_sever(&"arm_l", {T.CUT: 10.0}), H.rng())  # 1.0/s
	var blood := s.tick(8.0)
	assert_near(s.get_part(&"arm_l").bleed_rate, 0.5, 0.001, "halved after one half-life")
	assert_near(blood, 0.5 * 8.0 / log(2.0), 0.001, "exact integral of the decaying rate")
	for i in 100:
		s.tick(1.0)
	assert_eq(s.total_bleed_rate(), 0.0, "clots completely on its own")

func test_no_half_life_keeps_old_behaviour_for_pure_data() -> void:
	var s := H.humanoid()
	s.receive(H.no_sever(&"arm_l", {T.CUT: 10.0}), H.rng())
	assert_near(s.tick(2.0), 2.0)
	assert_near(s.total_bleed_rate(), 1.0)

func test_player_bleeding_alone_never_goes_below_ten_percent() -> void:
	var p := _player()
	var c := _combat(p)
	assert_near(c.bleed_half_life, 8.0)
	# 兩條腿都被切開、手臂斷了：舊版會一路流到死
	_state(p).receive(H.no_sever(&"leg_l", {T.CUT: 40.0}), H.rng())
	_state(p).receive(H.no_sever(&"leg_r", {T.CUT: 40.0}), H.rng())
	_state(p).sever_part(&"arm_l")
	c.pools.hp = 30.0
	_run(c, 30.0)
	assert_false(c.is_dead(), "bleeding alone does not kill the player")
	assert_near(c.pools.hp, c.pools.max_hp * 0.1, 0.01, "stops at the 10% floor")
	assert_true(&"bleed_floor" in StatusEffects.ids(StatusEffects.collect(c)), "HUD tells the player why")
	p.queue_free()

func test_floor_does_not_block_other_damage() -> void:
	var p := _player()
	var c := _combat(p)
	c.pools.hp = c.pools.max_hp * 0.1
	c.pools.damage_hp(5.0, "hit")
	assert_true(c.pools.hp < c.pools.max_hp * 0.1, "hits still go below the floor")
	p.queue_free()

func test_enemies_clot_slower_and_can_still_bleed_out() -> void:
	var e := EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"e")
	tree.root.add_child(e)
	var c := _combat(e)
	assert_near(c.bleed_half_life, 16.0)
	assert_eq(c.bleed_floor_ratio, 0.0)
	c.anatomy.state.receive(H.no_sever(&"leg_l", {T.CUT: 200.0}), H.rng())
	c.pools.hp = 5.0
	_run(c, 10.0)
	assert_true(c.is_dead(), "bleed weapons still finish enemies")
	e.queue_free()

func test_bandage_without_kit_stanches_bleeding() -> void:
	var p := _player()
	var d := _data(p)
	d.inventory.remove("suture_kit", d.inventory.count("suture_kit"))
	_state(p).receive(H.no_sever(&"leg_l", {T.LACERATION: 10.0}), H.rng())
	var before := _state(p).total_bleed_rate()
	assert_true(d.start_suture(), "F with no kit bandages instead")
	assert_true(d.is_bandaging())
	assert_false(d.is_suturing())
	d.advance(PlayerData.BANDAGE_SECONDS + 0.1)
	assert_false(d.is_bandaging())
	assert_near(_state(p).total_bleed_rate(), before * (1.0 - PlayerData.BANDAGE_REDUCTION), 0.001)
	assert_true(_state(p).get_part(&"leg_l").bandaged)
	assert_eq(d.inventory.count("suture_kit"), 0, "costs nothing")
	p.queue_free()

func test_bandage_is_interrupted_by_a_hit() -> void:
	var p := _player()
	var d := _data(p)
	_state(p).receive(H.no_sever(&"leg_l", {T.CUT: 10.0}), H.rng())
	assert_true(d.start_bandage())
	_combat(p).hit_received.emit(DamageResult.new(), null)
	assert_false(d.is_bandaging())
	p.queue_free()

func test_suture_also_closes_the_stump_bleeding() -> void:
	var p := _player()
	var d := _data(p)
	d.inventory.add("suture_kit")
	_state(p).sever_part(&"arm_l")
	assert_true(_state(p).get_part(&"chest").bleed_rate > 0.0, "stump bleeds into the chest")
	assert_true(d.start_suture())
	assert_true(d.is_suturing(), "kit + severed limb → suture, not bandage")
	d.advance(10.0)
	assert_true(_state(p).get_part(&"chest").bleed_rate < 0.5, "stump stitched shut")
	assert_true(_state(p).get_part(&"arm_l").sutured)
	p.queue_free()

func test_bandaged_and_sutured_flags_survive_save() -> void:
	var s := H.humanoid()
	s.receive(H.no_sever(&"leg_l", {T.CUT: 10.0}), H.rng())
	s.stanch(0.5)
	s.sever_part(&"arm_r")
	s.restore_part(&"arm_r")
	var back := AnatomyState.from_save(s.profile, s.to_save())
	assert_true(back.get_part(&"leg_l").bandaged)
	assert_true(back.get_part(&"arm_r").sutured)
	assert_false(back.get_part(&"arm_l").sutured)

# ---------- 異常狀態圖標 ----------

func test_status_effects_reflect_real_state() -> void:
	var p := _player()
	var c := _combat(p)
	assert_eq(StatusEffects.collect(c), [] as Array[Dictionary], "healthy = no icons")
	var s := _state(p)
	s.receive(H.no_sever(&"leg_l", {T.FRACTURE: 40.0}), H.rng())
	s.receive(H.no_sever(&"arm_l", {T.CUT: 30.0}), H.rng())
	s.receive(H.no_sever(&"chest", {T.BURN: 5.0}), H.rng())
	var ids := StatusEffects.ids(StatusEffects.collect(c))
	for want in [&"bleeding", &"fracture", &"burn", &"limping"]:
		assert_true(want in ids, "%s shown (got %s)" % [want, ids])
	var bleed: Dictionary = StatusEffects.collect(c).filter(func(e): return e["id"] == &"bleeding")[0]
	assert_eq(bleed["level"], 3, "3.0/s is heavy bleeding")
	s.sever_part(&"leg_r")
	ids = StatusEffects.ids(StatusEffects.collect(c))
	assert_true(&"crawling" in ids and not &"limping" in ids)
	s.sever_part(&"eye_l"); s.sever_part(&"eye_r")
	assert_true(&"blind" in StatusEffects.ids(StatusEffects.collect(c)))
	p.queue_free()

func test_suffocation_and_mutation_icons() -> void:
	var p := _player()
	var c := _combat(p)
	c.vital_timer = 4.2
	var fx := StatusEffects.collect(c)
	assert_eq(fx[0]["id"], &"suffocating", "most dangerous first")
	assert_eq(fx[0]["text"], "5秒")
	(p.get_node("MutationComponent") as MutationComponent).add(30)
	assert_true(&"mutation" in StatusEffects.ids(StatusEffects.collect(c)))
	p.queue_free()

func test_every_status_has_an_icon() -> void:
	for id in StatusEffects.ORDER:
		assert_true(StatusIconBar.ICONS.has(id), "icon for %s" % id)
		for row in StatusIconBar.ICONS[id]:
			assert_eq(String(row).length(), StatusIconBar.CELL, "%s row width" % id)

func test_hud_builds_icon_bar_and_body_doll() -> void:
	var p := _player()
	var hud := CombatHud.new()
	hud.player = _combat(p)
	tree.root.add_child(hud)
	_state(p).receive(H.no_sever(&"arm_l", {T.CUT: 10.0}), H.rng())
	hud._process(0.016)
	assert_eq(hud.status_bar.effects.size(), 1)
	assert_true(hud.body_doll.anatomy == _state(p))
	hud.queue_free()
	p.queue_free()

func test_body_doll_part_looks() -> void:
	var s := H.humanoid()
	assert_eq(BodyDoll.part_look(s.get_part(&"arm_l"))["status"], AnatomyTypes.PartStatus.INTACT)
	s.receive(H.no_sever(&"arm_l", {T.CUT: 12.0}), H.rng())
	var look := BodyDoll.part_look(s.get_part(&"arm_l"))
	assert_eq(look["status"], AnatomyTypes.PartStatus.DAMAGED)
	assert_true(look["bleeding"])
	s.sever_part(&"arm_r")
	assert_true(BodyDoll.part_look(s.get_part(&"arm_r"))["outline_only"])
	s.receive(H.no_sever(&"leg_l", {T.FRACTURE: 40.0}), H.rng())
	assert_true(BodyDoll.part_look(s.get_part(&"leg_l"))["cracked"])
	for pid in BodyDoll.LAYOUT:
		assert_true(s.get_part(pid) != null, "doll part %s exists on the humanoid" % pid)

# ---------- 傷殘部位外觀 ----------

func test_wounds_appear_and_heal_with_part_hp() -> void:
	var p := _player()
	var iv := _iv(p)
	assert_eq(iv.refresh(), 0, "unhurt body has no wounds")
	var s := _state(p)
	s.receive(H.no_sever(&"arm_l", {T.CRUSH: 10.0}), H.rng())  # 30 → 17 HP (< 75%)
	iv.refresh()
	assert_true(p.find_child("Injury_Wound0", true, false) != null)
	assert_true(p.find_child("Injury_Wound1", true, false) == null)
	s.receive(H.no_sever(&"arm_l", {T.CRUSH: 6.0}), H.rng())  # < 35%
	iv.refresh()
	assert_true(p.find_child("Injury_Wound2", true, false) != null, "severe = three wounds")
	s.heal_part(&"arm_l", 100.0)
	iv.refresh()
	assert_eq(iv.nodes().size(), 0, "wounds close when healed")
	p.queue_free()

func test_fracture_burn_rot_and_bandage_visuals() -> void:
	var p := _player()
	var iv := _iv(p)
	var s := _state(p)
	s.receive(H.no_sever(&"arm_r", {T.FRACTURE: 40.0}), H.rng())
	s.receive(H.no_sever(&"chest", {T.BURN: 4.0}), H.rng())
	s.receive(H.no_sever(&"leg_l", {T.CUT: 5.0}), H.rng())
	s.stanch(0.5)
	iv.refresh()
	for n in ["Injury_BoneShard", "Injury_Char", "Injury_Rot", "Injury_Bandage"]:
		assert_true(p.find_child(n, true, false) != null, "%s visible" % n)
	p.queue_free()

func test_disabled_arm_dangles_but_severed_one_does_not() -> void:
	var p := _player()
	var s := _state(p)
	var dangle: LimbDangle = p.find_child("LimbDangle", true, false)
	assert_true(dangle != null)
	assert_eq(dangle.dangling_parts(), [] as Array[StringName])
	s.receive(H.no_sever(&"arm_r", {T.FRACTURE: 40.0}), H.rng())
	assert_eq(dangle.dangling_parts(), [&"arm_r"] as Array[StringName])
	assert_eq(dangle.apply_now(0.0), 1)
	s.sever_part(&"arm_r")
	assert_eq(dangle.dangling_parts(), [] as Array[StringName])
	p.queue_free()

func test_sutured_limb_keeps_a_stitch_scar() -> void:
	var p := _player()
	var s := _state(p)
	s.sever_part(&"arm_l")
	s.restore_part(&"arm_l")
	_iv(p).refresh()
	assert_true(p.find_child("Injury_SutureScar", true, false) != null)
	p.queue_free()

func test_bleeding_drips_and_leaves_capped_floor_decals() -> void:
	var p := _player()
	var iv := _iv(p)
	_state(p).receive(H.no_sever(&"arm_l", {T.CUT: 20.0}), H.rng())  # 2.0/s → 5 滴／秒
	iv.step(1.0)
	assert_true(iv.drops_emitted >= 4, "drops spawn with the bleed rate (%d)" % iv.drops_emitted)
	for i in 20:
		iv.step(0.1)
	assert_true(tree.get_nodes_in_group(InjuryVisuals.BLOOD_GROUP).size() > 0, "blood on the floor")
	for i in 400:
		iv.emit_drop(&"arm_l")
		iv.step(1.0)
	assert_true(tree.get_nodes_in_group(InjuryVisuals.BLOOD_GROUP).size() <= InjuryVisuals.MAX_DECALS)
	p.queue_free()
