extends TestCase
## 動畫（M9）：關節樞軸骨架、程序生成動作片段、AnimationTree 驅動與戰鬥時序同步、斷肢後的動畫一致性。

const H := preload("res://tests/helpers.gd")
const CLEAVER := "res://content/weapons/bone_saw_cleaver.tres"
const RAPIER := "res://content/weapons/anatomist_rapier.tres"
const HAMMER := "res://content/weapons/reliquary_hammer.tres"
const A := CombatComponent.Action

func before_each() -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)

func _naturals() -> Array[AttackDefinition]:
	return [load("res://content/attacks/punch.tres"), load("res://content/attacks/kick.tres"), load("res://content/attacks/bite.tres")]

func _spawn(id: StringName = &"p", faction: StringName = &"player", pos: Vector3 = Vector3.ZERO, profile: String = H.HUMANOID) -> CharacterBody3D:
	var c := PlaceholderBodyBuilder.build_creature(load(profile), id, _naturals(), faction)
	c.position = pos
	tree.root.add_child(c)
	return c

func _anim(c: Node) -> CreatureAnimator:
	return c.get_node("CreatureAnimator")

func _skel(c: Node) -> Skeleton3D:
	return c.find_child("Skeleton", true, false)

func _bone_rot(c: Node, bone: String) -> Quaternion:
	var s := _skel(c)
	return s.get_bone_pose_rotation(s.find_bone(bone))

func _content(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tres"):
			out.append(load(dir.path_join(f)))
	return out

func test_bones_pivot_at_joints_and_hurtboxes_keep_rest_positions() -> void:
	var c := _spawn()
	var s := _skel(c)
	var shoulder := s.get_bone_global_rest(s.find_bone("arm_l")).origin
	assert_true(shoulder.distance_to(Vector3(0.32, 1.57, 0)) < 0.001, "arm pivots at shoulder: %s" % shoulder)
	var hip := s.get_bone_global_rest(s.find_bone("leg_r")).origin
	assert_true(hip.distance_to(Vector3(-0.10, 0.90, 0)) < 0.001, "leg pivots at hip: %s" % hip)
	var hb := c.find_child("hurt_arm_l", true, false) as Node3D
	assert_true(hb.global_position.distance_to(Vector3(0.32, 1.22, 0)) < 0.02, "hurtbox stays at part center: %s" % hb.global_position)

func test_every_profile_builds_base_clips_with_resolvable_tracks() -> void:
	for profile in _content("res://content/anatomy"):
		var lib := CreatureAnimationLibrary.for_profile(profile)
		var body := PlaceholderBodyBuilder.build_body(profile)
		var skel := body.get_node("Skeleton") as Skeleton3D
		for clip in [&"idle", &"walk", &"limp", &"crawl", &"crawl_idle", &"block", &"hit", &"stagger", &"sever", &"dodge", &"death"]:
			assert_true(lib.has_animation(clip), "%s has %s" % [profile.id, clip])
			var a := lib.get_animation(clip)
			for t in a.get_track_count():
				var path := a.track_get_path(t)
				if path.get_subname_count() > 0:
					assert_true(skel.find_bone(String(path.get_subname(0))) >= 0, "%s/%s: bone %s exists" % [profile.id, clip, path])
		body.free()

func test_every_content_attack_has_a_registered_style() -> void:
	var attacks: Array = _content("res://content/attacks")
	for w in _content("res://content/weapons"):
		attacks.append_array((w as WeaponDefinition).attacks())
	for a in attacks:
		var style := AttackStyles.style_for(a)
		assert_true(style in AttackStyles.ALL, "%s -> %s is known" % [a.id, style])
		assert_true(AttackStyles.BY_ID.has(a.id), "%s is mapped explicitly (not inferred)" % a.id)

func test_every_enemy_can_animate_all_its_attacks_without_fallback() -> void:
	for def in _content("res://content/enemies"):
		var e := EnemyFactory.create(def, StringName("anim_%s" % def.id))
		tree.root.add_child(e)
		var anim := _anim(e)
		for atk in (def as EnemyDefinition).attacks:
			anim._choose_attack_clips(atk)
			assert_eq(anim._attack_style, AttackStyles.style_for(atk), "%s: %s keeps its style" % [def.id, atk.id])
		e.free()

func test_attack_phases_follow_combat_timing() -> void:
	var p := _spawn()
	var combat: CombatComponent = p.get_node("CombatComponent")
	(p.get_node("EquipmentComponent") as EquipmentComponent).equip_definition(load(CLEAVER), &"arm_r")
	var light: AttackDefinition = combat.weapon().light_attack
	assert_true(combat.try_attack(light))
	var anim := _anim(p)
	assert_eq(anim.current_state, &"attack_windup")
	assert_eq(anim.current_clip, &"slash@arm_r_windup")
	assert_near(anim.playback_scale, 1.0 / light.windup, 0.001, "windup clip stretched to windup seconds")
	var before := _bone_rot(p, "arm_r")
	combat.advance(light.windup * 0.9)
	anim.tick(light.windup * 0.9)
	assert_true(_bone_rot(p, "arm_r").angle_to(before) > deg_to_rad(30.0), "arm cocks back during windup")
	combat.advance(light.windup * 0.2)
	assert_eq(combat.action, A.ACTIVE)
	assert_eq(anim.current_clip, &"slash@arm_r_active", "strike clip starts the same moment the hit resolves")
	combat.advance(light.active + 0.01)
	assert_eq(anim.current_clip, &"slash@arm_r_recovery")
	combat.advance(light.recovery + 0.01)
	anim.tick(0.1)
	assert_eq(anim.current_state, &"idle")

func test_striking_arm_follows_weapon_hand_and_remaining_arm() -> void:
	var p := _spawn()
	var combat: CombatComponent = p.get_node("CombatComponent")
	(p.get_node("EquipmentComponent") as EquipmentComponent).equip_definition(load(RAPIER), &"arm_l")
	var anim := _anim(p)
	assert_eq(anim.striking_arm(combat.weapon().light_attack), &"arm_l", "weapon hand")
	var punch: AttackDefinition = load("res://content/attacks/punch.tres")
	assert_eq(anim.striking_arm(punch), &"arm_r", "unarmed prefers right")
	combat.anatomy.state.sever_part(&"arm_r")
	assert_eq(anim.striking_arm(punch), &"arm_l", "uses the remaining arm")

func test_two_handed_heavy_uses_both_arms() -> void:
	var p := _spawn()
	var combat: CombatComponent = p.get_node("CombatComponent")
	(p.get_node("EquipmentComponent") as EquipmentComponent).equip_definition(load(HAMMER), &"arm_r")
	combat.pools.add_ap(100)
	var heavy: AttackDefinition = combat.weapon().heavy_attack
	assert_true(combat.try_attack(heavy))
	assert_eq(_anim(p).current_clip, &"overhead_two_windup")

func test_severed_bone_stays_collapsed_while_animating() -> void:
	var p := _spawn()
	var anim := _anim(p)
	p.get_node("AnatomyComponent").state.sever_part(&"arm_r")
	p.velocity = Vector3(0, 0, -2.6)
	var s := _skel(p)
	var rots := []
	for i in 12:
		anim.tick(1.0 / 12.0)
		rots.append(_bone_rot(p, "arm_l"))
		assert_true(s.get_bone_pose_scale(s.find_bone("arm_r")).length() < 0.01, "severed bone stays collapsed")
	assert_eq(anim.current_state, &"walk")
	assert_true((rots[2] as Quaternion).angle_to(rots[8]) > deg_to_rad(10.0), "remaining arm swings while walking")

func test_gait_follows_legs() -> void:
	var p := _spawn()
	var anim := _anim(p)
	var st: AnatomyState = p.get_node("AnatomyComponent").state
	p.velocity = Vector3(1.0, 0, 0)
	st.sever_part(&"leg_l")
	anim._sever_timer = 0.0
	anim.tick(0.1)
	assert_eq(anim.current_state, &"limp")
	st.sever_part(&"leg_r")
	anim._sever_timer = 0.0
	anim.tick(0.1)
	assert_eq(anim.current_state, &"crawl")
	anim.tick(0.5)
	assert_true(absf(_skel(p).rotation.x) > deg_to_rad(45.0), "body lies prone while crawling (hurtboxes go down with it)")
	var head := p.find_child("hurt_head", true, false) as Node3D
	assert_true(head.global_position.y < 1.0, "head hurtbox is near the floor: %s" % head.global_position.y)

func test_sever_reaction_then_death_fall() -> void:
	var p := _spawn()
	var anim := _anim(p)
	p.get_node("AnatomyComponent").state.sever_part(&"arm_l")
	anim.tick(0.05)
	assert_eq(anim.current_state, &"sever")
	anim.tick(1.0)
	assert_eq(anim.current_state, &"idle")
	var combat: CombatComponent = p.get_node("CombatComponent")
	combat.pools.damage_hp(9999, "test")
	assert_true(combat.is_dead())
	assert_eq(anim.current_state, &"death")
	for i in 20:
		anim.tick(0.1)
	assert_true(_skel(p).rotation.x > deg_to_rad(60.0), "falls backwards and stays down")

func test_tactical_pause_freezes_animation() -> void:
	var p := _spawn()
	var anim := _anim(p)
	p.velocity = Vector3(0, 0, -2.6)
	anim.tick(0.2)
	TimeScale.set_mode(TimeScale.Mode.PAUSE)
	var before := _bone_rot(p, "leg_l")
	anim._process(0.5)
	anim._process(0.5)
	assert_true(_bone_rot(p, "leg_l").is_equal_approx(before), "paused")
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	anim._process(0.25)
	assert_false(_bone_rot(p, "leg_l").is_equal_approx(before), "resumes")

func test_multi_armed_flurry_and_boss_styles() -> void:
	var m := _spawn(&"m", &"enemy", Vector3(4, 0, 0), H.MULTI_ARMED)
	var anim := _anim(m)
	anim._choose_attack_clips(load("res://content/attacks/flurry.tres"))
	assert_eq(anim._attack_style, &"flurry")
	var lib := CreatureAnimationLibrary.for_profile(load(H.MULTI_ARMED))
	var a := lib.get_animation(&"flurry_windup")
	var bones := []
	for t in a.get_track_count():
		if a.track_get_path(t).get_subname_count() > 0:
			bones.append(String(a.track_get_path(t).get_subname(0)))
	for i in range(1, 4):
		assert_true(("arm_l%d" % i) in bones and ("arm_r%d" % i) in bones, "flurry moves all six arms")
	var mother: AnatomyProfile = load("res://content/anatomy/walking_mother.tres")
	for style in [&"cradle", &"scream", &"stomp", &"lash"]:
		var arm := &"long_arm_r" if style == &"lash" else &""
		assert_true(CreatureAnimationLibrary.ensure_attack(mother, style, arm), "mother can %s" % style)

func test_weapon_models_are_low_poly_and_follow_the_hand() -> void:
	for w in _content("res://content/weapons"):
		var node := WeaponModels.build(w)
		var tris := WeaponModels.triangle_count(node)
		assert_true(tris > 20 and tris < 600, "%s is low-poly but not a box: %d tris" % [w.id, tris])
		assert_eq(node.get_meta(&"weapon_def"), w)
		node.free()
	var p := _spawn()
	var eq: EquipmentComponent = p.get_node("EquipmentComponent")
	var weapon := eq.equip_definition(load(CLEAVER), &"arm_r")
	assert_true(weapon.find_child("Blade", true, false) != null, "real blade mesh, not a placeholder box")
	var tip_before := (weapon.find_child("Tip", true, false) as Node3D).global_position
	var combat: CombatComponent = p.get_node("CombatComponent")
	combat.try_attack(combat.weapon().light_attack)
	_anim(p).tick(0.3)
	# 遊戲中骨骼掛點在 frame 結束時更新；測試在同一 frame 內，手動更新
	_skel(p).force_update_all_bone_transforms()
	(p.find_child("attach_arm_r", true, false) as BoneAttachment3D).on_skeleton_update()
	var tip_after := (weapon.find_child("Tip", true, false) as Node3D).global_position
	assert_true(tip_before.distance_to(tip_after) > 0.3, "weapon swings with the arm bone")
	p.get_node("AnatomyComponent").state.sever_part(&"arm_r")
	assert_true(eq.held_weapon() == null, "weapon drops with the arm")

func test_block_pose_while_guarding() -> void:
	var p := _spawn()
	var combat: CombatComponent = p.get_node("CombatComponent")
	combat.set_blocking(true)
	assert_true(combat.blocking)
	_anim(p).tick(0.2)
	assert_eq(_anim(p).current_state, &"block")
	assert_true(_bone_rot(p, "arm_r").get_angle() > deg_to_rad(45.0), "arms raised to guard")
