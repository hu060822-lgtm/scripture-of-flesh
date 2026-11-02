extends SceneTree
## 手動模擬（真實物理）：玩家站在庭院中央不動，三隻庭院敵人圍攻 15 秒。
## 印出同時出手的最大數量與各自意圖。不屬於自動測試。
## 執行：godot --headless --path . -s tests/sim/sim_squad.gd
var g: Node
var t := 0.0
var started := false
var max_attacking := 0
var names := ["courtyard_reverse_1", "courtyard_reverse_2", "courtyard_stitcher"]
func _process(delta: float) -> bool:
	if not started:
		started = true
		g = load("res://game/prologue_game.gd").new()
		g.autostart = false
		g.play_opening = false
		g.save_path = "user://sim_save.json"
		root.add_child(g)
		g.start_game("new")
		g.player.global_position = Vector3(0, 0.1, -38)
		var pc = g.player.get_node("CombatComponent")
		pc.max_hp = 99999.0
		pc.pools.hp = 99999.0
		var ai = g.level.get_node(names[0]).get_node("EnemyAI")
		ai.runtime.target = pc
		ai.runtime.alert = 1.0
		ai.runtime.time_since_seen = 0.0
		ai.runtime.last_known_position = g.player.global_position
		ai.force_state(&"chase")  # 第一隻發現 → 呼叫同伴
		return false
	t += delta
	var now := 0
	var line := ""
	for n in names:
		var e = g.level.get_node(n)
		var ai = e.get_node("EnemyAI")
		var c = e.get_node("CombatComponent")
		if c.action in [1, 2]:
			now += 1
		line += " %s:%s/%s(%.1f)" % [n.right(8), ai.state(), ai.runtime.intent, ai.distance_to(g.player.get_node("CombatComponent"))]
	max_attacking = maxi(max_attacking, now)
	if int(t * 60) % 90 == 0:
		print("t=%.1f%s" % [t, line])
	if t > 15.0:
		print("RESULT max_simultaneous_attackers=%d player_hp_lost=%.0f" % [max_attacking, 99999.0 - g.player.get_node("CombatComponent").pools.hp])
		quit()
	return false
