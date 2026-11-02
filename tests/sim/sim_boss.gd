extends SceneTree
## 手動模擬：在禮拜堂喚醒 Boss，讓 AI 跑 20 秒（玩家不動），印出結果。不屬於自動測試。
## 執行：godot --headless --path . -s tests/sim/sim_boss.gd
var g: Node
var t := 0.0
var started := false
func _process(delta: float) -> bool:
	if not started:
		started = true
		g = load("res://game/prologue_game.gd").new()
		g.autostart = false
		g.save_path = "user://sim_save.json"
		root.add_child(g)
		g.start_game("new")
		load("res://player/player_factory.gd").apply_class(g.player, "res://content/classes/mutilator.tres")
		g.player.global_position = Vector3(0, 0.1, -68)
		g.set_boss_active(true)
		return false
	t += delta
	if int(t * 60) % 120 == 0:
		var bc = g.boss.get_node("CombatComponent")
		var pc = g.player.get_node("CombatComponent")
		print("t=%.1f boss_state=%s action=%s player_hp=%.0f dead=%s adds=%d" % [t, g.boss.get_node("EnemyAI").state(), bc.action, pc.pools.hp, pc.is_dead(), g.boss.get_node("BossPhase").adds.size()])
	if t > 20.0:
		quit()
	return false
