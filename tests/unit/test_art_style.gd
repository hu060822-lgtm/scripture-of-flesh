extends TestCase
## 美術測試：PS1 風格化不破壞斷肢命名慣例；組合式手臂斷臂後整隻飛出、修復後重建；自訂斷面。

const S := preload("res://art/ps1/ps1_style.gd")

func _styled_stitcher() -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"st")
	S.stylize(e, {}, [], [S.GREY_PINK, "stitched"])
	e.position = Vector3(0, 0, -3)
	tree.root.add_child(e)
	(e.get_node("DismembermentController") as DismembermentController).cap_builder = S.build_stump_cap
	return e

func test_stylize_keeps_contract_and_composes_arm() -> void:
	var e := _styled_stitcher()
	var dm: DismembermentController = e.get_node("DismembermentController")
	var seg := dm.segment_for(&"arm_l") as MeshInstance3D
	assert_true(seg != null, "segment still found by name")
	assert_true(seg.get_node_or_null("Hand") != null and seg.get_node_or_null("Forearm") != null, "composite arm")
	assert_true(dm.hurtbox_for(&"arm_l") != null)
	var chest := dm.segment_for(&"chest") as MeshInstance3D
	assert_eq((chest.mesh as CapsuleMesh).radial_segments, 6, "low poly")
	assert_true(chest.material_override is ShaderMaterial)

func test_severed_composite_arm_flies_off_and_restores() -> void:
	var e := _styled_stitcher()
	var dm: DismembermentController = e.get_node("DismembermentController")
	var st: AnatomyState = (e.get_node("CombatComponent") as CombatComponent).anatomy.state
	st.sever_part(&"arm_l")
	var gib: SeveredPart = null
	for n in tree.get_nodes_in_group(SeveredPart.GROUP):
		gib = n
	assert_true(gib != null, "gib spawned")
	assert_true(gib.find_child("Hand", true, false) != null, "hand flies with the arm (D4)")
	var marker := e.find_child("stump_arm_l", true, false)
	var cap := marker.get_node_or_null("cap")
	assert_true(cap != null and cap.get_node_or_null("Bone") != null, "PS1 stump cap with bone")
	st.restore_part(&"arm_l")
	var seg := dm.segment_for(&"arm_l")
	assert_true(seg != null and e.is_ancestor_of(seg) and seg.get_node_or_null("Hand") != null, "restored arm is the styled composite")

func test_art_test_scene_builds() -> void:
	var scene: Node = load("res://scenes/art_test/art_test.tscn").instantiate()
	tree.root.add_child(scene)
	assert_eq(scene.enemies.size(), 2)
	assert_true(scene.camera is FixedCamera)
	assert_true(scene.player.get_node_or_null("RetroAnimator") != null)
	scene.screen.toggle_effects()
	assert_false(scene.screen.effects_enabled)
	scene.screen.toggle_effects()
	scene.reset()
	assert_eq(scene.enemies.size(), 2)
