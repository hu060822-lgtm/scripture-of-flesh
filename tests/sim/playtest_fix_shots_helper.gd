extends RefCounted
var tree: SceneTree
var out := "user://playtest_fix_shots"
var g: PrologueGame
var wall: Node3D

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://playtest_fix_shots_save.json"
	tree.root.add_child(g)
	g.start_game("new")
	(g.player.get_node("PlayerController") as PlayerController).input_enabled = false
	g.hud.visible = false

func step(f: int) -> bool:
	match f:
		3:
			if g.dialogue.is_open():
				g.dialogue.close_box()
			# 在玩家與鏡頭之間立一道牆（鏡頭在玩家的 +Z 方向）
			var p := g.player.global_position
			wall = Greybox.box(g, p + Vector3(0, 1.6, 1.3), Vector3(4.0, 3.2, 0.5), LevelKit.WALL_COLOR)
			g.rig.global_position = p
			g.rig._apply(1.0)
		12:
			_shot("x01_behind_wall_xray")
			(g.player.get_node("PlayerXray") as PlayerXray).set_enabled(false)
		16:
			_shot("x02_behind_wall_xray_off")
			(g.player.get_node("PlayerXray") as PlayerXray).set_enabled(true)
			wall.queue_free()
		20:
			_shot("x03_no_wall_no_xray")
			g.dialogue.open("agnes_intro", g.player)
			var guard := 0
			while g.dialogue.runner.choices().is_empty() and g.dialogue.runner.active and guard < 10:
				g.dialogue.runner.advance(); guard += 1
			g.dialogue.finish_typing()
		26:
			_shot("d01_dialogue_five_choices")
			return true
	return false

func _shot(name: String) -> void:
	tree.root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)
