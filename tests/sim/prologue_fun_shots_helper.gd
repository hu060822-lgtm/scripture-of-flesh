extends RefCounted
var tree: SceneTree
var out := "user://prologue_fun_shots"
var g: PrologueGame
var top: Camera3D

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://fun_shots_save.json"
	tree.root.add_child(g)
	g.start_game("new")
	(g.player.get_node("PlayerController") as PlayerController).input_enabled = false
	g.hud.visible = false

func _place(pos: Vector3, yaw_deg: float = 0.0) -> void:
	if g.dialogue.is_open():
		g.dialogue.close_box()
	g.player.global_position = pos
	g.player.velocity = Vector3.ZERO
	g.player.rotation.y = deg_to_rad(yaw_deg)
	g.rig.global_position = pos
	g.rig._apply(1.0)

func _enemy(spawn_id: String) -> Node3D:
	return g.level.get_node_or_null(spawn_id)

func step(f: int) -> bool:
	if g.dialogue.is_open():
		g.dialogue.close_box()
	match f:
		3:
			# 俯視全圖
			top = Camera3D.new()
			top.projection = Camera3D.PROJECTION_ORTHOGONAL
			top.size = 96.0
			g.add_child(top)
			top.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90), 0, 0)), Vector3(2, 60, -39))
			top.make_current()
			for l in g.level.get_node("Lights").get_children():
				(l as OmniLight3D).light_energy *= 1.6
		6:
			_shot("f00_overview_map")
			for l in g.level.get_node("Lights").get_children():
				(l as OmniLight3D).light_energy /= 1.6
			top.queue_free()
			g.rig.camera.make_current()
			_place(Vector3(7.75, 1.0, -21.0), 0.0)
		12:
			_shot("f01_corridor_ramp_up")
			_place(Vector3(3.5, 2.0, -28.6), 0.0)
		18:
			_shot("f02_terrace_altar_agnes_arm")
			var w := _enemy("archive_watcher_1")
			_place(Vector3(-19.0, 0, -37.6), 90.0)
			(g.player.get_node("PlayerData") as PlayerData).inventory.add(LimbRelic.EYE)
		24:
			_shot("f03_archive_watcher_and_glowing_scripture")
			GameState.set_flag(&"secret_archive")
		26:
			_place(Vector3(-22.5, 0, -41.5), 90.0)
		32:
			_shot("f04_secret_library_opened")
			_place(Vector3(-14.5, -2.0, -52.0), 90.0)
		38:
			_shot("f05_cistern_firstborn")
			_place(Vector3(8.5, 0, -39.0), 0.0)
		44:
			_shot("f06_shortcut_gate_from_courtyard")
			var mh := _enemy("sacristy_many_hands")
			if mh != null:
				mh.queue_free()
			_place(Vector3(26.5, 0, -43.5), -90.0)
			(g.player.get_node("PlayerData") as PlayerData).inventory.add("umbilical_key")
			g.mother_chase.advance(0.05)
			g.mother_chase.advance(MotherChase.STARTUP_SECONDS + 0.4)
		52:
			_shot("f07_mother_bursts_from_the_wall")
			return true
	return false

func _shot(name: String) -> void:
	var img := tree.root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
