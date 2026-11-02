extends SceneTree
## 手動模擬（真實物理）：玩家躲進藏書室，庭院的縫屍者被激怒後沿導航網格穿過門追進來。不屬於自動測試。
## 執行：godot --headless --path . -s tests/sim/sim_navigation.gd
var g: Node
var s: Node3D
var t := 0.0
var started := false
var entered_at := -1.0
func _process(delta: float) -> bool:
	if not started:
		started = true
		g = load("res://game/prologue_game.gd").new()
		g.autostart = false
		g.save_path = "user://sim_save.json"
		root.add_child(g)
		g.start_game("new")
		g.player.global_position = Vector3(-15, 0.1, -40)
		var pc = g.player.get_node("CombatComponent")
		pc.max_hp = 99999.0
		pc.pools.hp = 99999.0
		s = g.level.get_node("courtyard_stitcher")
		var ai = s.get_node("EnemyAI")
		ai.runtime.target = pc
		ai.runtime.alert = 1.0
		ai.runtime.last_known_position = g.player.global_position
		ai.runtime.time_since_seen = 0.1
		ai.force_state(&"chase")
		return false
	t += delta
	var ai = s.get_node("EnemyAI")
	if int(t * 60) % 60 == 0:
		print("t=%.1f stitcher=(%.1f, %.1f) state=%s loco=%s" % [t, s.global_position.x, s.global_position.z, ai.state(), ai.locomotion_mode])
	if entered_at < 0.0 and s.global_position.x < -10.6:
		entered_at = t
		print("ENTERED ARCHIVE at t=%.1f" % t)
	if t > 12.0:
		print("RESULT entered=%s" % (entered_at >= 0.0))
		quit()
	return false
