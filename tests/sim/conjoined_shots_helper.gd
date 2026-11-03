extends RefCounted
var tree: SceneTree
var out := "user://conjoined_shots"
var g: PrologueGame
var cam: Camera3D
var nun: Node3D
var sisters := []

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://conjoined_shots_save.json"
	tree.root.add_child(g)
	g.start_game("new")
	(g.player.get_node("PlayerController") as PlayerController).input_enabled = false
	g.hud.visible = false
	for e in g.level.get_children():
		if e.has_node("EnemyAI"):
			e.get_node("EnemyAI").process_mode = Node.PROCESS_MODE_DISABLED
		if e.get_meta(&"enemy_id", &"") == &"conjoined_nun":
			nun = e
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

func _shot(name: String) -> void:
	var img := tree.root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)

func step(f: int) -> bool:
	if g.dialogue.is_open():
		g.dialogue.close_box()
	match f:
		3:
			_place(Vector3(0, 0, -49.5), 0.0)
			_close_cam(nun.global_position + Vector3(0, 1.1, 0), Vector3(-2.4, 2.6, -47.6))
		8:
			_shot("c01_antechamber_nun_back_turned_at_sealed_door")
			# 轉過來面對玩家
			nun.rotation.y = PI
			_close_cam(nun.global_position + Vector3(0, 1.4, 0), nun.global_position + Vector3(0.6, 1.7, 2.6))
		12:
			_shot("c02_closeup_two_heads_embracing_arms_seam")
			var st: AnatomyState = nun.get_node("AnatomyComponent").state
			st.sever_part(&"arm_r_a")
			st.sever_part(&"arm_l_b")
		18:
			_shot("c03_inner_arms_cut_seam_exposed")
			g.rig.camera.make_current()
			_place(Vector3(0, 0, -51.0), 0.0)
			var st: AnatomyState = nun.get_node("AnatomyComponent").state
			nun.get_node("EnemyAI").runtime.target = g.player.get_node("CombatComponent")
			st.sever_part(&"seam")
			sisters = (nun.get_node("ConjoinedSplit") as ConjoinedSplit).split()
			for s in sisters:
				s.get_node("EnemyAI").process_mode = Node.PROCESS_MODE_DISABLED
				s.rotation.y = PI + (0.5 if s.get_meta(&"enemy_id") == &"nun_sister_a" else -0.5)
		22:
			_shot("c04_split_two_sisters_scream")
		40:
			_shot("c05_split_blood_pool")
			var a: Node3D = sisters[0]
			_close_cam(a.global_position + Vector3(0, 1.2, 0), a.global_position + Vector3(-1.6, 1.6, 1.4))
		44:
			_shot("c06_closeup_sister_torn_side")
			for s in sisters:
				(s.get_node("CombatComponent") as CombatComponent)._die("shot")
			GameState.set_flag(&"conjoined_defeated")
			g.rig.camera.make_current()
			_place(Vector3(0, 0, -52.0), 0.0)
		52:
			_shot("c07_seal_opened_after_defeat")
			return true
	return false
