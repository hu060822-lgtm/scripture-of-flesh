extends RefCounted
var tree: SceneTree
var out := "user://expansion_shots"
var g: PrologueGame
var cam: Camera3D

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://expansion_shots_save.json"
	tree.root.add_child(g)
	g.start_game("new")
	(g.player.get_node("PlayerController") as PlayerController).input_enabled = false
	g.hud.visible = false
	# 擺拍：敵人不動（裝死的仍然躺著）
	for e in g.level.get_children():
		if e.has_node("EnemyAI"):
			e.get_node("EnemyAI").process_mode = Node.PROCESS_MODE_DISABLED
	g.hallucinations.process_mode = Node.PROCESS_MODE_DISABLED

func _place(pos: Vector3, yaw_deg: float = 0.0) -> void:
	if g.dialogue.is_open():
		g.dialogue.close_box()
	g.player.global_position = pos
	g.player.velocity = Vector3.ZERO
	g.player.rotation.y = deg_to_rad(yaw_deg)
	g.rig.global_position = pos
	g.rig._apply(1.0)

func _close_cam(target: Vector3, from: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 40
		g.add_child(cam)
	cam.global_position = from
	cam.look_at(target)
	cam.make_current()

func _scare(id: String) -> ScareTrigger:
	var t: ScareTrigger = g.level.get_node("Triggers/Scare_%s" % id)
	t.fire(g.player)
	return t

func step(f: int) -> bool:
	if g.dialogue.is_open():
		g.dialogue.close_box()
	match f:
		3:
			var top := Camera3D.new()
			top.name = "Top"
			top.projection = Camera3D.PROJECTION_ORTHOGONAL
			top.size = 100.0
			g.add_child(top)
			top.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90), 0, 0)), Vector3(0, 60, -34))
			top.make_current()
		6:
			_shot("x00_overview_with_cold_storage")
			g.get_node("Top").queue_free()
			g.rig.camera.make_current()
			_place(Vector3(-20.0, -2.5, -21.6), 90.0)
			_scare("scare_cold_girl")
		12:
			_shot("x01_cold_storage_aisle_girl_and_corpses")
			_place(Vector3(-15.0, -2.5, -16.2), 90.0)
			var t := _scare("scare_cold_hanging")
			t.figure.rotation.y = deg_to_rad(-90)
		18:
			_shot("x02_hanging_body_turns")
			_place(Vector3(-23.5, -2.5, -10.8), -90.0)
		24:
			_shot("x03_frozen_stitcher_at_vault_door")
			_place(Vector3(-11.5, -2.5, -10.4), 0.0)
		30:
			_shot("x04_ilene_vault")
			_place(Vector3(-3, 0, -33), 0.0)
			var mut: MutationComponent = g.player.get_node("MutationComponent")
			mut.set_value(30)
			g.player.rotation.y = 0.0
		33:
			_close_cam(g.player.global_position + Vector3(0.2, 1.1, 0), g.player.global_position + Vector3(1.8, 1.5, -1.2))
		36:
			_shot("x05_mutation_25_eyes")
			(g.player.get_node("MutationComponent") as MutationComponent).set_value(55)
		39:
			_close_cam(g.player.global_position + Vector3(0, 1.2, 0), g.player.global_position + Vector3(-1.0, 1.8, 2.4))
		42:
			_shot("x06_mutation_50_bone_spurs_back")
			(g.player.get_node("MutationComponent") as MutationComponent).set_value(80)
		45:
			_close_cam(g.player.global_position + Vector3(0, 1.3, 0), g.player.global_position + Vector3(1.6, 1.7, 2.2))
		48:
			_shot("x07_mutation_75_back_hand")
			_close_cam(g.player.global_position + Vector3(0, 1.1, 0), g.player.global_position + Vector3(-0.6, 1.3, -2.2))
		51:
			_shot("x08_mutation_75_chest_mouth")
			g.rig.camera.make_current()
			_place(Vector3(0, 0, -32), 180.0)
			g.hallucinations.use_navmesh = false
			g.hallucinations.rng.seed = 2
			g.hallucinations.spawn()
			if g.hallucinations.current != null:
				g.hallucinations.current.global_position = Vector3(1.5, 0, -40)
		56:
			_shot("x09_hallucination_tall_figure")
			_place(Vector3(19.5, 0, -36.5), 0.0)
		60:
			_shot("x10_scripture_page_glow")
			return true
	return false

func _shot(name: String) -> void:
	var img := tree.root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
