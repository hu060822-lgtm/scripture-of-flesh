extends SceneTree
## 美術測試截圖（需要真的渲染器）：
## xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s tests/sim/art_shots.gd -- <輸出資料夾>
var f := 0
var scene: Node
var out := "user://art_shots"

func _process(_d):
	f += 1
	if f == 1:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			out = args[0]
		DirAccess.make_dir_recursive_absolute(out)
		scene = load("res://scenes/art_test/art_test.tscn").instantiate()
		root.add_child(scene)
	elif f == 5:
		scene._ai_enabled = false
		for e in scene.enemies:
			scene._set_ai(e, false)
	elif f == 40:
		_shot("01_overview")
		var st = scene.enemies[0].get_node("CombatComponent").anatomy.state
		st.sever_part(&"arm_l")
		scene.enemies[1].get_node("CombatComponent").anatomy.state.sever_part(&"stalk_2")
		scene.player.get_node("CombatComponent").anatomy.state.sever_part(&"arm_l")
	elif f == 90:
		_shot("02_after_sever")
		var cam: Camera3D = scene.camera
		cam.max_track_degrees = 0.0
		cam.position = Vector3(-1.0, 2.2, 3.6)
		cam.look_at(Vector3(-2.0, 1.1, 1.5))
	elif f == 110:
		_shot("03_closeup_stitcher_stump")
		var cam: Camera3D = scene.camera
		cam.position = Vector3(2.0, 2.2, -1.2)
		cam.look_at(Vector3(2.8, 1.4, -3.5))
	elif f == 130:
		_shot("04_closeup_watcher")
		var cam: Camera3D = scene.camera
		cam.position = Vector3(0, 6.2, 9.0)
		cam.look_at(Vector3(0, 1.0, -2.5))
		scene.screen.toggle_effects()
	elif f == 150:
		_shot("05_effects_off_comparison")
		scene.screen.toggle_effects()
		scene.screen.cycle_resolution()
	elif f == 170:
		_shot("06_%dp" % scene.screen.target_height())
		quit()
	return false

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
