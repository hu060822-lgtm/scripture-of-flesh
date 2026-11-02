extends SceneTree
## 動畫姿勢截圖（需要真的渲染器）：
## xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s tests/sim/anim_shots.gd -- <輸出資料夾>
## 在美術測試場景中，讓玩家與縫屍者擺出各動作的關鍵格並截圖。
var f := 0
var h
func _process(_d):
	f += 1
	if f == 1:
		h = load("res://tests/sim/anim_shots_helper.gd").new()
		h.setup(self, OS.get_cmdline_user_args())
	if h.step(f):
		quit()
	return false
