extends RefCounted
var tree: SceneTree
var out := "user://model_shots"
var scene: Node
var lineup := []

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	scene = load("res://scenes/art_test/art_test.tscn").instantiate()
	tree.root.add_child(scene)

func _cam(pos: Vector3, at: Vector3) -> void:
	var cam: Camera3D = scene.camera
	cam.max_track_degrees = 0.0
	cam.position = pos
	cam.look_at(at)

func _place(c: CharacterBody3D, pos: Vector3) -> void:
	c.position = pos
	c.rotation.y = PI  # 面向鏡頭（+Z）
	scene.screen.world.add_child(c)
	var ai := c.get_node_or_null("EnemyAI")
	if ai != null:
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	lineup.append(c)

func step(f: int) -> bool:
	match f:
		5:
			for e in scene.enemies:
				e.queue_free()
			scene.enemies.clear()
			scene.player.position = Vector3(-3.0, 0, 1.5)
			scene.player.rotation.y = PI
			scene.player.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
			var ids := ["stitcher", "many_hands", "reverse_legged", "faceless_watcher", "unborn"]
			for i in ids.size():
				_place(EnemyFactory.create(load("res://content/enemies/%s.tres" % ids[i]), StringName("shot_" + ids[i])), Vector3(-1.8 + i * 1.2, 0, 1.5))
			_cam(Vector3(-0.6, 1.5, 6.2), Vector3(-0.6, 1.0, 1.5))
		20: _shot("m01_lineup")
		22: _cam(Vector3(-2.4, 1.75, 3.0), Vector3(-2.4, 1.45, 1.5))
		26: _shot("m02_closeup_player_stitcher")
		28: _cam(Vector3(0.6, 1.75, 3.0), Vector3(0.6, 1.4, 1.5))
		32: _shot("m03_closeup_reverse_watcher")
		34:
			for c in lineup:
				c.queue_free()
			lineup.clear()
			var m := EnemyFactory.create(load("res://content/enemies/walking_mother.tres"), &"shot_mother")
			_place(m, Vector3(0, 0, -1.0))
			_cam(Vector3(0, 2.6, 5.5), Vector3(0, 2.1, -1.0))
		44: _shot("m04_walking_mother")
		46:
			var m: CharacterBody3D = lineup[0]
			var st: AnatomyState = (m.get_node("AnatomyComponent") as AnatomyComponent).state
			st.replace_part_definition(&"womb", load("res://content/boss/womb_exposed.tres"))
			_cam(Vector3(1.2, 2.4, 2.2), Vector3(0, 2.4, -1.0))
		50: _shot("m05_mother_womb_exposed")
		52:
			var p: CharacterBody3D = scene.player
			p.position = Vector3(0, 0, 2.5)
			var st: AnatomyState = (p.get_node("AnatomyComponent") as AnatomyComponent).state
			var organ: OrganDefinition = load("res://content/organs/iron_arm.tres")
			st.replace_part_definition(&"arm_l", TransplantService.build_definition(organ, st.get_part(&"arm_l").def), organ.id)
			var leg: OrganDefinition = load("res://content/organs/reverse_leg.tres")
			st.replace_part_definition(&"leg_r", TransplantService.build_definition(leg, st.get_part(&"leg_r").def), leg.id)
			_cam(Vector3(0, 1.3, 5.0), Vector3(0, 1.0, 2.5))
		58:
			_shot("m06_player_transplants")
			return true
	return false

func _shot(name: String) -> void:
	tree.root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
