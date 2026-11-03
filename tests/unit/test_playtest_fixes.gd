extends TestCase
## 2026-11-03 試玩回饋：對話框位置、屍體卡門、牆後透視。

const H := preload("res://tests/helpers.gd")

# ---------- 對話框：選項不被畫面切掉 ----------

func test_dialogue_box_grows_upward_and_choices_fit_on_screen() -> void:
	var box := DialogueBox.new()
	tree.root.add_child(box)
	assert_true(box.open("agnes_intro", null))
	var guard := 0
	while box.runner.choices().is_empty() and box.runner.active and guard < 10:
		box.runner.advance(); guard += 1
	box.finish_typing()
	assert_eq(box.runner.choices().size(), 5, "the class choice has five options (the longest choice list)")
	assert_true(box._choices.visible, "choices shown")
	var p: PanelContainer = box._panel
	assert_eq(p.grow_vertical, Control.GROW_DIRECTION_BEGIN, "panel grows upward when content gets taller")
	assert_near(p.anchor_top, 1.0)
	assert_near(p.anchor_bottom, 1.0)
	assert_near(p.offset_bottom, -DialogueBox.BOTTOM_MARGIN, 0.01, "bottom edge stays off the screen edge")
	assert_true(DialogueBox.BOTTOM_MARGIN >= 80.0, "box lifted well above the bottom (was 30px with no room for choices)")
	var h := p.get_combined_minimum_size().y
	var screen_h := 720.0
	assert_true(DialogueBox.BOTTOM_MARGIN + h <= screen_h, "whole box with 5 choices fits in 720p (height %.0f)" % h)
	box.close_box()
	box.queue_free()

# ---------- 屍體不擋路 ----------

func test_corpse_stops_blocking_living_bodies() -> void:
	var e := PlaceholderBodyBuilder.build_creature(load(H.HUMANOID), &"corpse_test", [], &"enemy")
	tree.root.add_child(e)
	var L := PlaceholderBodyBuilder.CREATURE_LAYER
	assert_true(e.collision_layer & L != 0, "alive: blocks other creatures")
	var c: CombatComponent = e.get_node("CombatComponent")
	c._die("test")
	assert_true(c.is_dead())
	assert_eq(e.collision_layer & L, 0, "dead: no longer on the creature layer, the player walks over it")
	assert_eq(e.collision_mask & L, 0, "dead: does not collide with creatures either")
	assert_true(e.collision_mask & PlaceholderBodyBuilder.WORLD_LAYER != 0, "still rests on the floor")
	e.queue_free()

func test_decor_corpse_spawn_is_passable() -> void:
	var s := EnemySpawn.new()
	s.enemy_path = "res://content/enemies/stitcher.tres"
	s.mode = "corpse"
	s.spawn_id = &"decor_corpse_test"
	tree.root.add_child(s)
	var e := s.spawn(tree.root)
	assert_true(e != null and e.has_meta(EnemySpawn.CORPSE_META), "corpse spawned")
	assert_eq(e.collision_layer & PlaceholderBodyBuilder.CREATURE_LAYER, 0, "set-dressing corpses don't block doors")
	e.queue_free()
	s.queue_free()

# ---------- 牆後透視 ----------

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create([], PlayerFactory.DEFAULT_CLASS)
	tree.root.add_child(p)
	return p

func test_player_meshes_get_xray_pass_without_touching_shared_materials() -> void:
	var p := _player()
	var x: PlayerXray = p.get_node("PlayerXray")
	x.refresh()
	assert_true(x.applied_count() > 5, "every body segment gets the see-through pass (%d)" % x.applied_count())
	var xm := PlayerXray.xray_material()
	for gi in p.find_children("*", "GeometryInstance3D", true, false):
		var m := (gi as GeometryInstance3D).material_override as ShaderMaterial
		if m != null and m.shader == PS1Style.SHADER:
			assert_true(m.next_pass == xm, "%s has the x-ray pass" % gi.name)
	# 共用快取的材質沒被改到（敵人不會跟著透視）
	var e := PlaceholderBodyBuilder.build_creature(load(H.HUMANOID), &"xray_enemy", [], &"enemy")
	CreatureModels.apply(e, &"stitcher")
	tree.root.add_child(e)
	for gi in e.find_children("*", "GeometryInstance3D", true, false):
		var m := (gi as GeometryInstance3D).material_override as ShaderMaterial
		if m != null:
			assert_true(m.next_pass == null, "enemy %s has no x-ray" % gi.name)
	e.queue_free()
	p.queue_free()

func test_xray_follows_body_changes() -> void:
	var p := _player()
	var x: PlayerXray = p.get_node("PlayerXray")
	x.refresh()
	# 砍下手臂：掉在地上的肢段還原成原本材質（不會在牆後發光）
	var dc: DismembermentController = p.get_node("DismembermentController")
	var arm := dc.segment_for(&"arm_l")
	var arm_meshes := [arm] if arm is GeometryInstance3D else arm.find_children("*", "GeometryInstance3D", true, false)
	assert_true(not arm_meshes.is_empty())
	for gi in arm_meshes:
		assert_true(x.is_applied(gi), "arm mesh has x-ray before the cut")
	var st: AnatomyState = p.get_node("AnatomyComponent").state
	st.sever_part(&"arm_l")
	x.refresh()
	for gi in arm_meshes:
		assert_false(x.is_applied(gi), "severed arm mesh dropped from x-ray")
		var am := (gi as GeometryInstance3D).material_override as ShaderMaterial
		assert_true(am == null or am.next_pass == null, "severed arm material restored")
	for n in tree.root.find_children("Severed_*", "", true, false):
		for gi in n.find_children("*", "GeometryInstance3D", true, false):
			var m := (gi as GeometryInstance3D).material_override as ShaderMaterial
			if m != null:
				assert_true(m.next_pass == null, "severed piece %s restored" % gi.name)
	# 新長出來的網格（移植、突變）也會套上
	var mi := MeshInstance3D.new()
	mi.mesh = PS1Style.box(Vector3.ONE * 0.1)
	mi.material_override = PS1Style.material(PS1Style.GREY_PINK)
	p.add_child(mi)
	x.refresh()
	assert_true(x.is_applied(mi), "new mesh picked up")
	assert_true(PS1Style.material(PS1Style.GREY_PINK).next_pass == null, "shared cache untouched")
	# 關閉
	x.set_enabled(false)
	assert_eq(x.applied_count(), 0)
	assert_true((mi.material_override as ShaderMaterial).next_pass == null, "restored when disabled")
	for n in tree.root.find_children("Severed_*", "", true, false):
		n.queue_free()
	p.queue_free()

func test_xray_shader_compiles_with_depth_compare() -> void:
	var code := PlayerXray.SHADER.code
	assert_true(code.contains("hint_depth_texture"), "compares against the scene depth")
	assert_true(code.contains("depth_test_disabled"), "draws through walls")
	assert_true(code.contains("discard"), "only where something is in front")
