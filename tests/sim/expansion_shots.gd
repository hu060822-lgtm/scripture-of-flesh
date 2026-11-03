extends SceneTree
## 序章 50 分鐘擴充的截圖（需要真的渲染器）：
## xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s tests/sim/expansion_shots.gd -- <輸出資料夾>
var f := 0
var h
func _process(_d):
	f += 1
	if f == 1:
		h = load("res://tests/sim/expansion_shots_helper.gd").new()
		h.setup(self, OS.get_cmdline_user_args())
	if h.step(f):
		quit()
	return false
