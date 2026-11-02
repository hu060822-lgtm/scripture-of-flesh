extends SceneTree
## 主畫面截圖（需要真的渲染器）：
## xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s tests/sim/title_shots.gd -- <輸出資料夾>
var f := 0
var s
var out := "user://title_shots"

func _process(_d):
	f += 1
	if f == 2:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			out = args[0]
		DirAccess.make_dir_recursive_absolute(out)
		s = load("res://scenes/main_menu.tscn").instantiate()
		root.add_child(s)
	elif f == 90:
		_shot("t01_title_360p")
		s.buttons[3].grab_focus()
	elif f == 110:
		_shot("t02_focus_art_test")
		s.open_audio_settings()
	elif f == 130:
		_shot("t03_audio_settings")
		s.audio_panel.close()
		var cam: Camera3D = s.chapel.camera
		s.chapel.set_process(false)
		cam.position = Vector3(1.3, 3.3, -4.6)
		cam.look_at(Vector3(0.1, 2.6, -7.5))
		s.get_node("Column").visible = false
		s.get_node("Vignette").visible = false
		s.get_node("Hint").visible = false
	elif f == 150:
		_shot("t04_closeup_reliquary_heart")
		s.chapel.set_process(true)
		s.get_node("Column").visible = true
		s.get_node("Vignette").visible = true
		s.get_node("Hint").visible = true
		s.screen.height_index = 0
		s.screen.apply_settings()
	elif f == 190:
		_shot("t05_compare_old_240p")
		quit()
	return false

func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)
