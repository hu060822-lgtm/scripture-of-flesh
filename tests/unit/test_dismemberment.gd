extends TestCase
## 斷肢表現層：分段網格、殘肢、斷面、骨架、碰撞、武器掉落、動畫組。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _spawn(profile_path: String, id: StringName = &"test_creature") -> Node3D:
	var c := PlaceholderBodyBuilder.build_creature(load(profile_path), id)
	tree.root.add_child(c)
	return c

func _anatomy(c: Node3D) -> AnatomyComponent:
	return c.get_node("AnatomyComponent")

func _ctrl(c: Node3D) -> DismembermentController:
	return c.get_node("DismembermentController")

func _gibs() -> Array:
	return tree.root.get_children().filter(func(n): return n is SeveredPart)

func _bone_scale(c: Node3D, bone: String) -> Vector3:
	var skel: Skeleton3D = c.find_child("Skeleton", true, false)
	return skel.get_bone_pose_scale(skel.find_bone(bone))

func test_placeholder_body_follows_naming_contract() -> void:
	var c := _spawn(H.HUMANOID)
	var skel: Skeleton3D = c.find_child("Skeleton", true, false)
	assert_eq(skel.get_bone_count(), 14)
	var hurt := c.find_children("hurt_*", "", true, false)
	assert_eq(hurt.size(), 12, "all parts except heart & lungs are hittable")
	assert_eq(c.find_children("seg_*", "MeshInstance3D", true, false).size(), 11, "spine has hurtbox but no mesh")
	assert_eq(c.find_children("stump_*", "", true, false).size(), 8, "head, 2 eyes, jaw, 2 arms, 2 legs")
	assert_true(c.get_meta(&"placeholder"), "placeholder is explicitly marked")

func test_sever_arm_updates_model_skeleton_collision_equipment_animation() -> void:
	var c := _spawn(H.HUMANOID)
	var ctrl := _ctrl(c)
	var equip: EquipmentComponent = c.get_node("EquipmentComponent")
	var sword := Node3D.new(); sword.name = "Sword"
	assert_true(equip.equip(&"arm_r", sword))
	var seg := ctrl.segment_for(&"arm_r")
	var r := _anatomy(c).receive(DamagePacket.make(&"arm_r", {T.CUT: 30.0}))
	assert_true(r.hits[0].severed, "sever chance 1.0 hit")
	# 模型：分段網格離開角色，成為殘肢的一部分
	assert_false(c.is_ancestor_of(seg), "segment removed from creature")
	var gibs := _gibs()
	assert_eq(gibs.size(), 1)
	assert_eq(gibs[0].part_id, &"arm_r")
	assert_true(gibs[0].is_ancestor_of(seg), "segment lives on the severed part")
	# 斷面
	assert_true(c.find_child("stump_arm_r", true, false).get_node_or_null("cap") != null, "stump cap added")
	# 骨架
	assert_true(_bone_scale(c, "arm_r").length() < 0.01, "bone collapsed")
	assert_eq(_bone_scale(c, "arm_l"), Vector3.ONE)
	# 碰撞
	assert_false(ctrl.hurtbox_for(&"arm_r").active)
	assert_true(ctrl.hurtbox_for(&"arm_l").active)
	# 裝備
	assert_eq(equip.weapon_in(&"arm_r"), null)
	assert_true(sword.get_parent() is RigidBody3D and sword.get_parent().get_meta(&"pickup", false), "weapon became a pickup")
	assert_false(c.is_ancestor_of(sword))
	# 動畫組
	assert_eq(ctrl.animation_set["arms"], AnimationSet.ARMS_ONE)

func test_disabled_part_stays_attached_and_hittable() -> void:
	var c := _spawn(H.HUMANOID)
	var equip: EquipmentComponent = c.get_node("EquipmentComponent")
	var sword := Node3D.new()
	equip.equip(&"arm_r", sword)
	var seg := _ctrl(c).segment_for(&"arm_r")
	_anatomy(c).receive(H.no_sever(&"arm_r", {T.CRUSH: 30.0}))
	assert_eq(_anatomy(c).state.status_of(&"arm_r"), AnatomyTypes.PartStatus.DISABLED)
	assert_true(c.is_ancestor_of(seg), "disabled arm still on body")
	assert_true(_ctrl(c).hurtbox_for(&"arm_r").active)
	assert_eq(_gibs().size(), 0)
	assert_eq(equip.weapon_in(&"arm_r"), sword, "weapon not dropped by disabling (grip loss handled by combat in M3)")

func test_decapitation_flies_off_as_one_piece_with_eyes_and_jaw() -> void:
	var c := _spawn(H.HUMANOID)
	var ctrl := _ctrl(c)
	var segs := [&"head", &"eye_l", &"eye_r", &"jaw"].map(func(id): return ctrl.segment_for(id))
	_anatomy(c).state.sever_part(&"head")
	var gibs := _gibs()
	assert_eq(gibs.size(), 1)
	for s in segs:
		assert_true(gibs[0].is_ancestor_of(s), "%s in head gib" % s.name)
	for id in [&"head", &"eye_l", &"eye_r", &"jaw"]:
		assert_false(ctrl.hurtbox_for(id).active, String(id))
	assert_true(c.find_child("stump_head", true, false).get_node_or_null("cap") != null)

func test_multi_armed_animation_set_follows_remaining_arms() -> void:
	var c := _spawn(H.MULTI_ARMED)
	var ctrl := _ctrl(c)
	var st := _anatomy(c).state
	for id in [&"arm_l1", &"arm_r1", &"arm_l2"]:
		st.sever_part(id)
	assert_eq(_gibs().size(), 3)
	assert_eq(ctrl.animation_set["arms"], AnimationSet.ARMS_TWO, "three arms left")
	for id in [&"arm_r2", &"arm_l3"]:
		st.sever_part(id)
	assert_eq(ctrl.animation_set["arms"], AnimationSet.ARMS_ONE)
	st.sever_part(&"arm_r3")
	assert_eq(ctrl.animation_set["arms"], AnimationSet.ARMS_NONE)

func test_leg_loss_and_spine_failure_switch_to_crawl() -> void:
	var c := _spawn(H.HUMANOID)
	var ctrl := _ctrl(c)
	_anatomy(c).state.sever_part(&"leg_l")
	assert_eq(ctrl.animation_set["legs"], AnimationSet.LEGS_ONE)
	var c2 := _spawn(H.HUMANOID, &"other")
	_anatomy(c2).receive(H.no_sever(&"spine", {T.CRUSH: 40.0}))
	assert_eq(_ctrl(c2).animation_set["legs"], AnimationSet.LEGS_CRAWL, "spine failure -> crawl without severing")

func test_player_sever_chance_scale_halves_chance() -> void:
	var c := _spawn(H.HUMANOID)
	var a := _anatomy(c)
	a.sever_chance_scale = 0.5
	var r := a.receive(DamagePacket.make(&"arm_l", {T.CUT: 10.0}))
	assert_near(r.hits[0].sever_chance, 1.0 / 18.0)

func test_event_bus_receives_sever_event() -> void:
	var c := _spawn(H.HUMANOID, &"stitcher_01")
	var got := []
	var cb := func(cid, ids): got.append([cid, ids])
	EventBus.creature_part_severed.connect(cb)
	_anatomy(c).state.sever_part(&"arm_l")
	EventBus.creature_part_severed.disconnect(cb)
	assert_eq(got, [[&"stitcher_01", PackedStringArray(["arm_l"])]])

func test_severed_part_count_is_capped() -> void:
	for i in 13:
		var c := _spawn(H.HUMANOID, StringName("c%d" % i))
		_anatomy(c).state.sever_part(&"arm_l")
		_anatomy(c).state.sever_part(&"arm_r")
	var alive := _gibs().filter(func(g): return not g.is_queued_for_deletion())
	assert_eq(alive.size(), SeveredPart.MAX_ACTIVE)

func test_animation_set_mapping() -> void:
	var caps := CapabilitySet.new()
	assert_eq(AnimationSet.from_capabilities(caps), {"arms": AnimationSet.ARMS_NONE, "legs": AnimationSet.LEGS_CRAWL})
	caps.add("grip", 2); caps.add("locomotion", 1)
	assert_eq(AnimationSet.from_capabilities(caps), {"arms": AnimationSet.ARMS_TWO, "legs": AnimationSet.LEGS_ONE})
