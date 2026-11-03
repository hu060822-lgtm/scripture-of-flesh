extends SceneTree
## 手動模擬（真實物理）：玩家站著不動，讓各區的敵人（依難度曲線生成）攻擊 15 秒，比較受到的傷害。
## 執行：godot --headless --path . -s tests/sim/sim_difficulty.gd [-- off|linear]
const CASES := [
	["corridor_stitcher_1", Vector3(0.8, 0.1, -12.5)],
	["courtyard_reverse_1", Vector3(-4, 0.1, -36)],
	["sacristy_many_hands", Vector3(15.5, 0.1, -37)],
]
var g: Node
var t := 0.0
var idx := -1
var pc
func _process(delta: float) -> bool:
	if idx < 0 or t > 15.0:
		if idx >= 0:
			print("RESULT %s hp_lost=%.0f" % [CASES[idx][0], 99999.0 - pc.pools.hp])
			g.queue_free()
		idx += 1
		t = 0.0
		if idx >= CASES.size():
			quit()
			return false
		var args := OS.get_cmdline_user_args()
		var DC = load("res://ai/difficulty_curve.gd")
		if "off" in args: DC.mode = 2
		elif "linear" in args: DC.mode = 1
		g = load("res://game/prologue_game.gd").new()
		g.autostart = false
		g.save_path = "user://sim_diff.json"
		root.add_child(g)
		g.start_game("new")
		g.player.global_position = CASES[idx][1]
		pc = g.player.get_node("CombatComponent")
		pc.max_hp = 99999.0
		pc.pools.hp = 99999.0
		pc.pools.max_hp = 99999.0
		var e = g.level.get_node(CASES[idx][0])
		var ai = e.get_node("EnemyAI")
		ai.runtime.target = pc
		ai.runtime.alert = 1.0
		ai.runtime.time_since_seen = 0.0
		ai.runtime.last_known_position = g.player.global_position
		ai.force_state(&"chase")
		return false
	t += delta
	return false
