extends TestCase
## 身體成長：屬性與職業、技能、熟練度、經驗、異化階段、器官移植、緊急縫合、祭壇、摘取。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _player(cls: String = "stitcher") -> CharacterBody3D:
	var p := PlayerFactory.create([], "res://content/classes/%s.tres" % cls)
	tree.root.add_child(p)
	return p

func _prog(p: Node) -> ProgressionComponent: return p.get_node("ProgressionComponent")
func _mut(p: Node) -> MutationComponent: return p.get_node("MutationComponent")
func _data(p: Node) -> PlayerData: return p.get_node("PlayerData")
func _combat(p: Node) -> CombatComponent: return p.get_node("CombatComponent")

func test_five_classes_set_starting_point_only() -> void:
	var ids := []
	for f in DirAccess.get_files_at("res://content/classes"):
		var c: ClassDefinition = load("res://content/classes/" + f)
		ids.append(String(c.id))
		assert_true(c.starting_weapon != null, f)
	ids.sort()
	assert_eq(ids, ["anatomist", "flesh_witch", "mutilator", "prosthetic_knight", "stitcher"])
	var p := _player("anatomist")
	assert_eq(_combat(p).weapon().id, &"anatomist_rapier")
	assert_eq(_prog(p).stats.PER, 14)
	# 不鎖成長路線：解剖師也能把點數加到力量並學聖錘技能
	_prog(p).add_xp(100)
	assert_true(_prog(p).allocate_stat("STR"))
	assert_true(_prog(p).unlock_skill(&"hammer_devotion"))

func test_vit_raises_max_hp_and_level_up_grants_points() -> void:
	var p := _player()
	var prog := _prog(p)
	var hp_before := _combat(p).pools.max_hp
	prog.add_xp(100)
	assert_eq(prog.level, 2)
	assert_eq(prog.stat_points, 1)
	prog.allocate_stat("VIT")
	assert_near(_combat(p).pools.max_hp, hp_before + 8.0)

func test_skill_prerequisites_and_cost() -> void:
	var p := _player()
	var prog := _prog(p)
	assert_false(prog.can_unlock(&"deep_insight"), "needs anatomical_insight")
	assert_true(prog.unlock_skill(&"anatomical_insight"))
	assert_eq(prog.skill_points, 0)
	assert_false(prog.unlock_skill(&"deep_insight"), "no points left")
	assert_eq(_combat(p).ap_gain_bonus, 2.0)

func test_damage_scales_with_stats_skill_and_proficiency() -> void:
	var p := _player("mutilator")  # STR 13 DEX 12, butchers_eye
	var c := _combat(p)
	var w := c.weapon()
	var base := float(w.damage["CUT"])
	var pkt := c.build_packet(w.light_attack, &"chest")
	var expected := base * (1.0 + 3 * 0.025 + 2 * 0.015) * 1.1
	assert_near(float(pkt.amounts[T.CUT]), expected, 0.01)
	_prog(p).proficiency[&"cleaver"] = 80  # sqrt(16) = 4 級
	pkt = c.build_packet(w.light_attack, &"chest")
	assert_near(float(pkt.amounts[T.CUT]), expected * 1.16, 0.01)

func test_killing_enemy_gives_xp() -> void:
	var p := _player()
	var e := EnemyFactory.create(load("res://content/enemies/many_hands.tres"), &"mh")
	tree.root.add_child(e)
	var ec: CombatComponent = e.get_node("CombatComponent")
	ec.receive_hit(H.no_sever(&"chest", {T.CUT: 1.0}), _combat(p))
	ec.anatomy.state.sever_part(&"head")
	assert_eq(_prog(p).xp, 80)

func test_mutation_is_not_good_or_evil_each_stage_has_gain_and_cost() -> void:
	var p := _player()
	var m := _mut(p)
	var c := _combat(p)
	m.add(30)
	assert_eq(m.current_stage().id, &"stage_1_uncanny_sense")
	assert_true(m.has_effect("anatomical_sight"))
	var st_before := c.pools.max_st
	m.add(25)
	assert_eq(m.current_stage().id, &"stage_2_bone_spurs")
	assert_true("bone_spur" in c.available_attacks().map(func(a): return String(a.id)), "body: new attack")
	assert_near(c.pools.max_st, st_before + 10.0)
	assert_true(m.has_effect("heal_penalty"), "cost: altar healing mutates")

func test_mutation_resistance_from_will() -> void:
	var p := _player("flesh_witch")  # WIL 14 → 12%
	assert_near(_mut(p).add(10.0), 10.0 * (1.0 - 0.12), 0.001)

func test_gaze_wounds_raise_mutation() -> void:
	var p := _player()
	_combat(p).anatomy.receive(H.no_sever(&"chest", {T.MUTATION: 8.0}))
	assert_near(_mut(p).value, 8.0 * MutationComponent.WOUND_TO_MUTATION, 0.001)

func test_stage_three_regenerates_parts() -> void:
	var p := _player()
	_mut(p).set_value(80)
	var st := _combat(p).anatomy.state
	st.receive(H.no_sever(&"arm_l", {T.CRUSH: 10.0}), H.rng())
	var hp := st.get_part(&"arm_l").hp
	_mut(p).advance(5.0)
	assert_near(st.get_part(&"arm_l").hp, hp + 2.0, 0.01)

func test_transplant_reverse_leg_grants_leap_kick() -> void:
	var p := _player()
	var data := _data(p)
	data.inventory.add("organ:reverse_leg")
	var c := _combat(p)
	assert_false("leap_kick" in c.available_attacks().map(func(a): return String(a.id)))
	var rng := H.rng(1)
	var organ := OrganRegistry.get_organ(&"reverse_leg")
	var pred := TransplantService.predict(organ, &"leg_l", c.anatomy.state, _prog(p), _mut(p))
	assert_true(pred.allowed)
	assert_near(pred.compatibility, 0.45 + 4 * 0.025, 0.001, "TEC 14 bonus")
	var o := TransplantScreen.perform(p, organ, &"leg_l", rng)
	assert_true(o.success)
	assert_eq(data.inventory.count("organ:reverse_leg"), 0, "organ consumed")
	assert_eq(c.anatomy.state.organs[&"leg_l"], &"reverse_leg")
	assert_eq(c.anatomy.state.get_part(&"leg_l").def.max_hp, 55.0)
	assert_true("leap_kick" in c.available_attacks().map(func(a): return String(a.id)), "new ability")
	assert_true(_mut(p).value > 0.0)

func test_transplant_rejection_causes_necrosis() -> void:
	var p := _player()
	var c := _combat(p)
	var organ := OrganRegistry.get_organ(&"watcher_eye")
	var rejected := false
	var rng := H.rng(3)
	for i in 20:  # 相容性 65%，多試幾次一定會遇到排斥
		_data(p).inventory.add("organ:watcher_eye")
		var o := TransplantScreen.perform(p, organ, &"eye_l", rng)
		if o.rejected:
			rejected = true
			assert_true(c.anatomy.state.get_part(&"eye_l").injury(T.NECROSIS) > 0.0)
			break
	assert_true(rejected)

func test_prosthetic_needs_tec_and_never_rejects() -> void:
	var low := _player("mutilator")  # TEC 9
	var organ := OrganRegistry.get_organ(&"iron_arm")
	var pred := TransplantService.predict(organ, &"arm_r", _combat(low).anatomy.state, _prog(low), _mut(low))
	assert_false(pred.allowed)
	var knight := _player("prosthetic_knight")  # TEC 13
	_combat(knight).anatomy.state.sever_part(&"arm_r")
	_data(knight).inventory.add("organ:iron_arm")
	var o := TransplantScreen.perform(knight, organ, &"arm_r", H.rng())
	assert_true(o.success and not o.rejected)
	assert_eq(o.mutation_added, 0.0)
	var arm := _combat(knight).anatomy.state.get_part(&"arm_r")
	assert_false(arm.severed, "prosthetic replaces a lost arm")
	assert_true(arm.def.functions.has("grip_r"), "keeps side tag")
	assert_eq(arm.def.armor, 6.0)
	assert_true(knight.is_ancestor_of((knight.get_node("DismembermentController") as DismembermentController).segment_for(&"arm_r")))

func test_transplant_save_roundtrip() -> void:
	var p := _player()
	_data(p).inventory.add("organ:many_hands_heart")
	TransplantScreen.perform(p, OrganRegistry.get_organ(&"many_hands_heart"), &"heart", H.rng(5))
	var st := _combat(p).anatomy.state
	var data: Dictionary = JSON.parse_string(JSON.stringify(st.to_save()))
	var loaded := AnatomyState.from_save(st.profile, data, OrganRegistry.lookup_for(st.profile))
	assert_eq(loaded.get_part(&"heart").def.max_hp, 30.0)
	assert_true(loaded.capabilities().has("strong_heart"))
	assert_eq(loaded.organs[&"heart"], &"many_hands_heart")

func test_emergency_suture_restores_arm_with_mutation_and_can_be_interrupted() -> void:
	var p := _player()  # 縫合者：3 個縫合包，快速縫合 -30%
	var data := _data(p)
	var c := _combat(p)
	c.anatomy.state.sever_part(&"arm_r")
	c.anatomy.state.sever_part(&"leg_l")
	assert_eq(data.next_suture_target(), &"arm_r", "hands first")
	assert_true(data.start_suture())
	data.advance(0.5)
	c.receive_hit(H.no_sever(&"chest", {T.CUT: 1.0}), null)
	assert_false(data.is_suturing(), "interrupted by a hit")
	assert_eq(data.inventory.count("suture_kit"), 3, "kit not consumed")
	assert_true(data.start_suture())
	data.advance(data.suture_duration() + 0.01)
	assert_false(c.anatomy.state.get_part(&"arm_r").severed)
	assert_eq(data.inventory.count("suture_kit"), 2)
	assert_true(_mut(p).value > 0.0, "crude stitching mutates")

func test_altar_restores_everything() -> void:
	var p := _player()
	var c := _combat(p)
	var altar := StitchingAltar.new()
	tree.root.add_child(altar)
	c.anatomy.state.sever_part(&"arm_l")
	c.anatomy.state.sever_part(&"eye_r")
	c.anatomy.receive(H.no_sever(&"leg_r", {T.CUT: 10.0}))
	c.pools.damage_hp(50)
	altar.rest(p)
	for pid in c.anatomy.state.part_ids():
		assert_eq(c.anatomy.state.status_of(pid), AnatomyTypes.PartStatus.INTACT, String(pid))
	assert_eq(c.anatomy.state.total_bleed_rate(), 0.0)
	assert_eq(c.pools.hp, c.pools.max_hp)

func test_harvest_needs_intact_donor_part() -> void:
	var p := _player()
	var e := EnemyFactory.create(load("res://content/enemies/faceless_watcher.tres"), &"fw")
	e.position = Vector3(1, 0, 0)
	tree.root.add_child(e)
	var ec: CombatComponent = e.get_node("CombatComponent")
	ec.anatomy.state.sever_part(&"stalk_1")  # 捐贈部位被砍掉了
	ec.receive_hit(H.no_sever(&"chest", {T.CUT: 200.0}), _combat(p))
	assert_true(ec.is_dead())
	assert_false(_data(p).try_harvest(), "eye stalk destroyed")
	var e2 := EnemyFactory.create(load("res://content/enemies/many_hands.tres"), &"mh2")
	e2.position = Vector3(-1, 0, 0)
	tree.root.add_child(e2)
	(e2.get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"head")
	assert_true(_data(p).try_harvest())
	assert_eq(_data(p).inventory.count("organ:many_hands_heart"), 1)
	assert_false(_data(p).try_harvest(), "only once per corpse")

func test_menus_render_text() -> void:
	var p := _player()
	_mut(p).add(30)
	var txt := BodyMenu.text_for(p)
	assert_true(txt.contains("異樣感知"), txt)
	assert_true(txt.contains("緊急縫合包"), txt)
	_data(p).inventory.add("organ:stitched_arm")
	var opts := TransplantScreen.options_for(p)
	assert_eq(opts.size(), 2, "arm organ fits both arms")
