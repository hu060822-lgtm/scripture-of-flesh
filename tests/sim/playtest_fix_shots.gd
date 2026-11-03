extends SceneTree
## 試玩修正（對話框、牆後透視）的截圖。牆後透視要用 Forward+（Vulkan）渲染：
## xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --path . -s tests/sim/playtest_fix_shots.gd -- <輸出資料夾>
var f := 0
var h
func _process(_d):
	f += 1
	if f == 1:
		h = load("res://tests/sim/playtest_fix_shots_helper.gd").new()
		h.setup(self, OS.get_cmdline_user_args())
	if h.step(f):
		quit()
	return false
