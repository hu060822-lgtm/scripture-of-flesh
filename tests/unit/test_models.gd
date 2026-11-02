extends TestCase
## 具象模型（M10）：每種生物都有專屬造型、維持低多邊形、外觀與受擊區域一致、移植器官改變外觀。

const H := preload("res://tests/helpers.gd")

func _enemy(id: String) -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % id), StringName("m_" + id))
	tree.root.add_child(e)
	return e

func _seg(c: Node, part: StringName) -> MeshInstance3D:
	return (c.get_node("DismembermentController") as DismembermentController).segment_for(part) as MeshInstance3D

func test_every_enemy_and_player_get_their_own_look_within_budget() -> void:
	var budgets := {"stitcher": 2500, "many_hands": 3500, "reverse_legged": 2500, "faceless_watcher": 2500, "unborn": 2000, "walking_mother": 5000}
	for id in budgets:
		var e := _enemy(id)
		assert_eq(e.get_meta(&"model_look"), StringName(id))
		var tris := CreatureModels.triangle_count(e)
		assert_true(tris > 300 and tris < int(budgets[id]), "%s: %d tris (detailed but low-poly)" % [id, tris])
		for d in (e.get_node("AnatomyComponent") as AnatomyComponent).profile.parts:
			if d.is_internal or not d.mesh_segment:
				continue
			var seg := _seg(e, d.id)
			if seg != null:
				assert_true(seg.mesh != null and not (seg.mesh is CapsuleMesh), "%s/%s replaced" % [id, d.id])
				assert_true(seg.material_override is ShaderMaterial, "%s/%s uses PS1 material" % [id, d.id])
		e.free()
	var p := PlayerFactory.create([], PlayerFactory.DEFAULT_CLASS)
	tree.root.add_child(p)
	assert_eq(p.get_meta(&"model_look"), &"player")
	assert_true(_seg(p, &"head").get_node_or_null("Hood") != null, "player hood")
	assert_true(_seg(p, &"chest").get_node_or_null("Coat") != null, "player coat")

func test_model_stays_aligned_with_hurtboxes() -> void:
	var e := _enemy("stitcher")
	for part in [&"head", &"arm_l", &"leg_r", &"chest"]:
		var seg := _seg(e, part)
		var hb := (e.get_node("DismembermentController") as DismembermentController).hurtbox_for(part)
		var aabb := seg.get_aabb()
		var center := seg.global_transform * aabb.get_center()
		assert_true(center.distance_to(hb.global_position) < 0.25, "%s mesh centered on its hurtbox (%s vs %s)" % [part, center, hb.global_position])

func test_weak_points_glow() -> void:
	var w := _enemy("faceless_watcher")
	var stalk := _seg(w, &"stalk_1")
	var mat := stalk.material_override as ShaderMaterial
	assert_true(float(mat.get_shader_parameter("emission_energy")) > 0.5, "eye stalk is a glowing weak point")
	var m := _enemy("walking_mother")
	var cord := _seg(m, &"cord_1").material_override as ShaderMaterial
	assert_true(float(cord.get_shader_parameter("emission_energy")) > 0.1, "umbilical cords glow")

func test_transplant_changes_the_arm_and_survives_sever_and_restore() -> void:
	var p := PlayerFactory.create([], PlayerFactory.DEFAULT_CLASS)
	tree.root.add_child(p)
	var st: AnatomyState = (p.get_node("AnatomyComponent") as AnatomyComponent).state
	var organ: OrganDefinition = load("res://content/organs/iron_arm.tres")
	var def := TransplantService.build_definition(organ, st.get_part(&"arm_l").def)
	assert_true(st.replace_part_definition(&"arm_l", def, organ.id))
	var seg := _seg(p, &"arm_l")
	assert_eq(seg.get_meta(&"model_variant"), &"iron_arm")
	assert_true(seg.get_node_or_null("Band0") != null, "iron bands")
	assert_true(seg.get_node_or_null("Sleeve") == null, "old sleeve removed")
	st.sever_part(&"arm_l")
	st.restore_part(&"arm_l")
	seg = _seg(p, &"arm_l")
	assert_true(seg != null and p.is_ancestor_of(seg))
	assert_eq(seg.get_meta(&"model_variant"), &"iron_arm", "restored arm keeps the transplant look")

func test_boss_womb_opens_in_phase_two() -> void:
	var m := _enemy("walking_mother")
	var st: AnatomyState = (m.get_node("AnatomyComponent") as AnatomyComponent).state
	assert_true(_seg(m, &"womb").get_node_or_null("Seam") != null, "closed womb with golden seam")
	assert_true(st.replace_part_definition(&"womb", load("res://content/boss/womb_exposed.tres")))
	assert_true(_seg(m, &"womb").get_node_or_null("Core") != null, "opened womb shows the glowing core")

func test_unborn_is_small_and_fetal() -> void:
	var u := _enemy("unborn")
	var head := _seg(u, &"head")
	var chest := _seg(u, &"chest")
	assert_true(head.get_aabb().size.y > chest.get_aabb().size.y * 0.7, "oversized head")
	assert_true(head.global_position.y < 1.0, "small creature")
