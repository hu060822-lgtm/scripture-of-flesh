extends TestCase
## 地上道具與 NPC 的程序生成模型：每種物品有自己的造型、不是灰盒、維持低多邊形；NPC 是完整的人形而不是膠囊。

func _tris_ok(n: Node, lo: int, hi: int, label: String) -> void:
	var t := PropModels.triangle_count(n)
	assert_true(t >= lo and t <= hi, "%s: %d tris (between %d and %d)" % [label, t, lo, hi])

func _no_greybox(n: Node, label: String) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		assert_true(mi.material_override is ShaderMaterial, "%s/%s uses PS1 material" % [label, mi.name])

func test_every_floor_item_in_the_prologue_has_its_own_model() -> void:
	var ids := ["suture_kit", "blood_vial", "umbilical_key", "first_suture", "organ:agnes_arm", "organ:iron_arm", "organ:watcher_eye"]
	for o in DirAccess.get_files_at("res://content/organs"):
		ids.append("organ:" + o.get_basename())
	var kinds := {}
	for id in ids:
		var it := ItemPickup.new()
		it.item_id = id
		tree.root.add_child(it)
		var model := it.get_node_or_null("Model")
		assert_true(model != null, "%s has a model" % id)
		if model == null:
			it.free()
			continue
		assert_true(model.get_meta(&"prop_kind") != "bundle", "%s is not the fallback bundle" % id)
		_no_greybox(model, id)
		_tris_ok(model, 40, 1500, id)
		kinds[model.get_meta(&"prop_kind")] = true
		it.free()
	assert_true(kinds.size() >= 9, "distinct looks: %s" % kinds.keys())

func test_picking_up_hides_the_model_and_glint_pulses() -> void:
	var it := ItemPickup.new()
	it.item_id = "umbilical_key"
	tree.root.add_child(it)
	assert_true(it._glints.size() > 0, "key has glinting parts")
	var g: Node3D = it._glints[0][0]
	var base: Vector3 = it._glints[0][1]
	it._t = 0.0
	it._process(0.1)
	assert_true(g.scale.x > base.x, "glint pulses")
	it._process(1.0)
	assert_true(is_equal_approx(g.scale.x, base.x), "and settles")
	it._on_used()
	assert_false((it.get_node("Model") as Node3D).visible, "model hidden after pickup")
	it.free()

func test_pedestal_shows_the_real_weapon_and_hides_it_when_taken() -> void:
	var p := WeaponPedestal.new()
	p.weapon_path = "res://content/weapons/bone_saw_cleaver.tres"
	tree.root.add_child(p)
	var w := p.find_child("Weapon", true, false) as Node3D
	assert_true(w != null and w.get_child_count() == 1, "weapon model on the pedestal")
	assert_true(w.get_child(0).has_meta(&"weapon_def"), "it is the WeaponModels model")
	p._on_used()
	assert_false(w.visible, "weapon gone after taking it")
	assert_true((p.find_child("Base", true, false) as Node3D).visible, "pedestal stays")
	p.free()

func test_notes_pages_and_inscriptions_have_models() -> void:
	var n := DialogueInteractable.new()
	n.kind = "note"
	tree.root.add_child(n)
	assert_eq(n.get_node("Model").get_meta(&"prop_kind"), "note")
	n.free()
	var i := DialogueInteractable.new()
	tree.root.add_child(i)
	assert_eq(i.get_node("Model").get_meta(&"prop_kind"), "inscription")
	_tris_ok(i.get_node("Model"), 40, 1500, "inscription")
	i.free()
	var s := ScripturePage.new()
	tree.root.add_child(s)
	assert_eq(s.get_node("Model").get_meta(&"prop_kind"), "scripture_page")
	assert_true(s.get_node_or_null("Glow") != null, "page still glows")
	s.free()

func test_hidden_scripture_model_still_toggles_with_sight() -> void:
	var h := HiddenScripture.new()
	tree.root.add_child(h)
	var m := h.get_node("Model") as Node3D
	assert_false(m.visible, "hidden without sight")
	h._set_revealed(true)
	assert_true(m.visible and h.is_revealed(), "revealed with sight")
	h.free()

func test_npcs_are_full_humanoid_figures_with_their_own_look() -> void:
	for pair in [[&"npc_agnes", &"agnes", "pray"], [&"npc_ignatius", &"ignatius", "slumped"]]:
		var npc := DialogueInteractable.new()
		npc.kind = "npc"
		npc.object_id = pair[0]
		tree.root.add_child(npc)
		var f := npc.get_node_or_null("Figure") as NpcFigure
		assert_true(f != null, "%s has a figure" % pair[0])
		assert_eq(f.get_meta(&"model_look"), pair[1])
		assert_eq(f.pose, pair[2])
		for part in [&"head", &"chest", &"arm_l", &"arm_r", &"leg_l", &"leg_r"]:
			assert_true(f.pivots.has(part), "%s has %s" % [pair[0], part])
		assert_true(npc.find_children("*", "CapsuleMesh", true, false).is_empty(), "no capsule placeholder")
		_no_greybox(f, String(pair[0]))
		_tris_ok(f, 300, 3500, String(pair[0]))
		npc.free()

func test_agnes_prays_and_breathes_ignatius_sits_on_the_floor() -> void:
	var a := NpcFigure.create(&"agnes", "pray")
	tree.root.add_child(a)
	var arm := a.pivots[&"arm_l"] as Node3D
	assert_true(arm.rotation_degrees.x > 30.0, "hands raised in prayer")
	assert_true(a.find_child("Hood", true, false) != null, "wimple")
	var chest := a.pivots[&"chest"] as Node3D
	a.animate(1.0)
	var r1 := chest.basis
	a.animate(3.0)
	assert_false(r1.is_equal_approx(chest.basis), "breathing moves the chest")
	a.free()
	var g := NpcFigure.create(&"ignatius", "slumped")
	tree.root.add_child(g)
	var head := (g.pivots[&"head"] as Node3D).global_position
	assert_true(head.y < 1.3, "sitting: head is low (%s)" % head)
	var foot := (g.pivots[&"leg_l"] as Node3D).global_transform * Vector3(0, -0.85, 0)
	assert_true(foot.y > -0.05 and foot.y < 0.45, "legs on the floor (%s)" % foot)
	assert_true(g.find_child("BloodPool", true, false) != null, "dying in a pool of blood")
	assert_true(g.find_child("Stole", true, false) != null, "priest's stole")
	g.free()

func test_prologue_level_interactables_all_get_models() -> void:
	var level: Node3D = load("res://scenes/prologue/prologue_level.tscn").instantiate()
	tree.root.add_child(level)
	var bare := []
	for n in level.get_node("Interactables").get_children():
		if n is ItemPickup or n is WeaponPedestal or n is DialogueInteractable:
			if n.get_node_or_null("Model") == null and n.get_node_or_null("Figure") == null:
				bare.append(n.name)
	assert_true(bare.is_empty(), "interactables without a model: %s" % [bare])
	assert_true(level.find_child("NPC_Agnes", true, false).get_node_or_null("Figure") != null, "Agnes has a body in the level")
	level.free()
