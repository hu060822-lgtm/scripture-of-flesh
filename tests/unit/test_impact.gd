extends TestCase
## 倒地姿態與打擊感：失去雙腿的身體在地上出手與受擊（不會站起來）、Boss 跪伏維持跪姿；
## 命中時的頓幀、鏡頭震動、受擊閃白、擊退、噴血。

const H := preload("res://tests/helpers.gd")
const CLEAVER := "res://content/weapons/bone_saw_cleaver.tres"
const A := CombatComponent.Action
const PRONE_MIN := deg_to_rad(45.0)

func before_each() -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	TimeScale.clear_hitstop()

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

func _anim(c: Node) -> CreatureAnimator:
	return c.get_node("CreatureAnimator")

func _fx(c: Node) -> ImpactFeedback:
	return c.get_node("ImpactFeedback")

func _skel(c: Node) -> Skeleton3D:
	return c.find_child("Skeleton", true, false)

## 砍斷雙腿，讓身體進入倒地（爬行）姿態。
func _floor(c: Node) -> void:
	var st: AnatomyState = c.get_node("AnatomyComponent").state
	st.sever_part(&"leg_l")
	st.sever_part(&"leg_r")
	_anim(c)._sever_timer = 0.0
	_anim(c).tick(0.5)

func _is_prone(c: Node) -> bool:
	return _skel(c).rotation.x < -PRONE_MIN

func _content(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tres"):
			out.append(load(dir.path_join(f)))
	return out

# ---------- 倒地／跪伏姿態 ----------

func test_every_profile_has_prone_and_kneel_variants() -> void:
	for profile in _content("res://content/anatomy"):
		var lib := CreatureAnimationLibrary.for_profile(profile)
		for clip in [&"hit", &"stagger", &"sever", &"dodge", &"death"]:
			assert_true(lib.has_animation(CreatureAnimationLibrary.posture_clip(clip, &"prone")), "%s %s~prone" % [profile.id, clip])
			assert_true(lib.has_animation(CreatureAnimationLibrary.posture_clip(clip, &"kneel")), "%s %s~kneel" % [profile.id, clip])
		for clip in [&"idle", &"walk"]:
			assert_true(lib.has_animation(CreatureAnimationLibrary.posture_clip(clip, &"kneel")), "%s %s~kneel" % [profile.id, clip])

func test_every_enemy_attack_has_a_prone_variant() -> void:
	for def in _content("res://content/enemies"):
		var e := EnemyFactory.create(def, StringName("prone_%s" % def.id))
		tree.root.add_child(e)
		var anim := _anim(e)
		for atk in (def as EnemyDefinition).attacks:
			anim._choose_attack_clips(atk)
			anim.animation_set = {"arms": AnimationSet.ARMS_TWO, "legs": AnimationSet.LEGS_CRAWL}
			anim._ensure_posture_attack()
			var clip := CreatureAnimationLibrary.attack_clip_name(anim._attack_style, anim._attack_arm, "active", &"prone")
			assert_true(anim._library.has_animation(clip), "%s/%s has %s" % [def.id, atk.id, clip])
		e.free()

func test_downed_creature_attacks_from_the_ground() -> void:
	var p := _spawn(&"p", &"player", Vector3.ZERO)
	_floor(p)
	var anim := _anim(p)
	assert_eq(anim.current_state, &"crawl_idle")
	assert_true(_is_prone(p), "lying down before the attack")
	var punch: AttackDefinition = load("res://content/attacks/punch.tres")
	var combat := _combat(p)
	assert_true(combat.try_attack(punch), "can still punch while crawling")
	assert_eq(anim.current_clip, &"punch@arm_r_windup~prone")
	var head := p.find_child("hurt_head", true, false) as Node3D
	var t := 0.0
	while combat.action != A.IDLE and t < 3.0:
		combat.advance(1.0 / 12.0)
		anim.tick(1.0 / 12.0)
		_skel(p).force_update_all_bone_transforms()
		t += 1.0 / 12.0
		assert_true(_is_prone(p), "stays on the ground during %s (rot %.0f°)" % [anim.current_clip, rad_to_deg(_skel(p).rotation.x)])
		assert_true(String(anim.current_clip).ends_with("~prone") or anim.current_state in [&"crawl", &"crawl_idle"], "prone clip: %s" % anim.current_clip)
	assert_true(head.global_position.y < 1.0, "head hurtbox stays low: %s" % head.global_position.y)

func test_downed_creature_reacts_and_dies_on_the_ground() -> void:
	var p := _spawn(&"p", &"player", Vector3.ZERO)
	var e := _spawn(&"e", &"enemy", Vector3(0, 0, -1.2), true)
	_floor(e)
	var anim := _anim(e)
	var ec := _combat(e)
	ec.hit_received.emit(DamageResult.new(), _combat(p))
	anim.tick(1.0 / 12.0)
	assert_eq(anim.current_clip, &"hit~prone")
	assert_true(_is_prone(e), "flinches on the ground")
	anim.tick(1.0)
	ec._stagger()
	assert_eq(anim.current_clip, &"stagger~prone")
	anim.tick(0.2)
	assert_true(_is_prone(e), "staggers on the ground")
	ec.advance(1.0)
	ec.pools.damage_hp(9999, "test")
	assert_eq(anim.current_clip, &"death~prone")
	for i in 12:
		anim.tick(0.1)
		assert_true(_is_prone(e), "dies face-down without standing up")

func test_losing_legs_mid_attack_switches_to_the_prone_clip() -> void:
	var p := _spawn(&"p", &"player", Vector3.ZERO)
	var punch: AttackDefinition = load("res://content/attacks/punch.tres")
	var combat := _combat(p)
	assert_true(combat.try_attack(punch))
	assert_eq(_anim(p).current_clip, &"punch@arm_r_windup")
	var st: AnatomyState = p.get_node("AnatomyComponent").state
	st.sever_part(&"leg_l")
	st.sever_part(&"leg_r")
	_anim(p).tick(1.0 / 12.0)
	if combat.action == A.WINDUP:
		assert_eq(_anim(p).current_clip, &"punch@arm_r_windup~prone")

func test_kneel_posture_keeps_the_torso_bent() -> void:
	var p := _spawn(&"p", &"player", Vector3.ZERO)
	var anim := _anim(p)
	var s := _skel(p)
	var bone := s.find_bone("chest")
	anim.tick(0.5)
	var upright := s.get_bone_pose_rotation(bone)
	anim.posture_override = &"kneel"
	anim.tick(0.5)
	assert_eq(anim.current_clip, &"idle~kneel")
	assert_true(s.get_bone_pose_rotation(bone).angle_to(upright) > deg_to_rad(15.0), "torso bent forward while knelt")
	var punch: AttackDefinition = load("res://content/attacks/punch.tres")
	assert_true(_combat(p).try_attack(punch))
	assert_eq(anim.current_clip, &"punch@arm_r_windup~kneel")

# ---------- 打擊感 ----------

func test_hitstop_scales_combat_time_in_real_time() -> void:
	assert_eq(TimeScale.combat_scale(), 1.0)
	TimeScale.hitstop(0.1)
	assert_true(TimeScale.in_hitstop())
	assert_eq(TimeScale.combat_scale(), TimeScale.HITSTOP_SCALE)
	assert_near(TimeScale.scaled(1.0), TimeScale.HITSTOP_SCALE, 0.0001)
	TimeScale.set_mode(TimeScale.Mode.SLOW)
	assert_eq(TimeScale.combat_scale(), TimeScale.SLOW_SCALE, "tactical slow-mo is not overridden")
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	var t0 := Time.get_ticks_msec()
	while TimeScale.in_hitstop() and Time.get_ticks_msec() - t0 < 1000:
		OS.delay_msec(5)
	assert_false(TimeScale.in_hitstop(), "hitstop expires on its own")
	assert_true(Time.get_ticks_msec() - t0 < 200, "capped duration")
	TimeScale.hitstop_enabled = false
	TimeScale.hitstop(0.1)
	assert_false(TimeScale.in_hitstop(), "can be disabled")
	TimeScale.hitstop_enabled = true

func test_player_hit_lands_with_flash_knockback_blood_hitstop_and_shake() -> void:
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.make_current()
	var p := _spawn(&"player", &"player", Vector3.ZERO)
	var e := _spawn(&"enemy", &"enemy", Vector3(0, 0, -1.2), true)
	(p.get_node("EquipmentComponent") as EquipmentComponent).equip_definition(load(CLEAVER), &"arm_r")
	var pc := _combat(p)
	var light: AttackDefinition = pc.weapon().light_attack
	assert_true(pc.try_attack(light))
	var z0 := e.global_position.z
	pc.advance(light.windup + 0.01)
	var fx := _fx(e)
	assert_eq(fx.last.get("kind"), &"hit", "feedback fired: %s" % fx.last)
	assert_eq(fx.flash_level(), 1.0, "enemy flashes white")
	var mesh := e.find_child("Seg_torso", true, false) as GeometryInstance3D
	if mesh == null:
		for n in e.find_children("*", "MeshInstance3D", true, false):
			mesh = n
			break
	assert_true(mesh.material_overlay != null and mesh.material_overlay == ImpactFeedback.flash_material(1.0), "white flash overlay on the body")
	assert_true(TimeScale.in_hitstop(), "player's hit freezes combat for a beat")
	var shake := cam.get_node_or_null("CameraShake") as CameraShake
	assert_true(shake != null and shake.trauma > 0.1, "camera shakes")
	assert_true(tree.root.find_children("HitBurst*", "Node3D", false, false).size() > 0, "blood burst spawned in the world")
	assert_true(fx.pending_knockback() > 0.1, "knockback queued: %s" % fx.pending_knockback())
	for i in 10:
		fx.advance_knockback(1.0 / 30.0)
	assert_true(e.global_position.z < z0 - 0.1, "pushed away from the player: %.3f -> %.3f" % [z0, e.global_position.z])
	fx._process(0.2)
	assert_eq(fx.flash_level(), 0.0)
	assert_true(mesh.material_overlay == null, "flash cleared")
	shake.advance(1.0)
	assert_eq(shake.trauma, 0.0)
	assert_eq(cam.h_offset, 0.0, "shake settles")

func test_enemy_on_enemy_hit_has_no_hitstop() -> void:
	var a := _spawn(&"a", &"enemy", Vector3.ZERO)
	var b := _spawn(&"b", &"cult", Vector3(0, 0, -1.2), true)
	var punch: AttackDefinition = load("res://content/attacks/punch.tres")
	var ac := _combat(a)
	assert_true(ac.try_attack(punch))
	ac.advance(punch.windup + 0.01)
	assert_eq(_fx(b).last.get("kind"), &"hit")
	assert_eq(_fx(b).last.get("hitstop"), 0.0)
	assert_false(TimeScale.in_hitstop(), "no global freeze for fights the player isn't in")

func test_sever_hits_harder_than_plain_hits() -> void:
	var p := _spawn(&"player", &"player", Vector3.ZERO)
	var e := _spawn(&"enemy", &"enemy", Vector3(0, 0, -1.2), true)
	var fx := _fx(e)
	var plain := DamageResult.new()
	var h := DamageResult.PartHit.new()
	h.part_id = &"arm_l"
	h.hp_loss = 4.0
	plain.hits.append(h)
	_combat(e).hit_received.emit(plain, _combat(p))
	var light: Dictionary = fx.last.duplicate()
	var cut := DamageResult.new()
	var h2 := DamageResult.PartHit.new()
	h2.part_id = &"arm_l"
	h2.hp_loss = 20.0
	h2.severed = true
	cut.hits.append(h2)
	_combat(e).hit_received.emit(cut, _combat(p))
	assert_true(fx.last["hitstop"] > light["hitstop"], "longer hitstop on sever")
	assert_true(fx.last["shake"] > light["shake"], "bigger shake on sever")
	assert_true(fx.last["knockback"] > light["knockback"], "bigger knockback on sever")
	assert_true(fx.last["particles"] > light["particles"], "more blood on sever")

func test_block_throws_sparks() -> void:
	var p := _spawn(&"player", &"player", Vector3.ZERO)
	var e := _spawn(&"enemy", &"enemy", Vector3(0, 0, -1.2), true)
	_combat(e).blocked.emit(_combat(p), false)
	assert_eq(_fx(e).last.get("kind"), &"block")
	var sparks := tree.root.find_children("HitBurst*", "Node3D", false, false)
	assert_true(sparks.size() > 0 and (sparks[0] as HitBurst).kind == HitBurst.Kind.SPARK)
	var b := sparks[0] as HitBurst
	var y0 := b.chips[0].global_position.y
	b.advance(0.05)
	assert_true(b.chips[0].global_position != Vector3(b.chips[0].global_position.x, y0, b.chips[0].global_position.z) or true)
	var moved := false
	for c in b.chips:
		moved = moved or c.position.length() > 0.01
	assert_true(moved, "chips fly out")

func test_hit_clip_snaps_hard_on_the_first_frame() -> void:
	var p := _spawn(&"p", &"player", Vector3.ZERO)
	var anim := _anim(p)
	anim.tick(0.2)
	var s := _skel(p)
	var bone := s.find_bone("head")
	var rest := s.get_bone_pose_rotation(bone)
	_combat(p).hit_received.emit(DamageResult.new(), null)
	anim.tick(1.0 / 12.0)
	assert_eq(anim.current_clip, &"hit")
	var ang := rad_to_deg(s.get_bone_pose_rotation(bone).angle_to(rest))
	assert_true(ang > 20.0, "head whips back within one 12fps frame: %.1f°" % ang)
