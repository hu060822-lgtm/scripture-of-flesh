extends SceneTree
## 手動模擬：在禮拜堂前廳和連體修女打一場（真實物理與 AI），印出分裂時間、擊殺時間與玩家受到的傷害。
## 玩家是簡單的機器人：面向最近的敵人、貼近、能出招就出招。不屬於自動測試。
## 執行：godot --headless --path . -s tests/sim/sim_conjoined.gd -- [auto|seam|heads] [職業]
##   auto：不指定部位（一般操作，正面先打到環抱的手臂）
##   seam：每一刀都瞄準縫線（戰術模式的打法）
##   heads：先砍頭，不分裂直接殺死
##   idle：站著不出手（量連體修女的輸出）
var g: Node
var t := 0.0
var started := false
var mode := "auto"
var cls := "mutilator"
var split_at := -1.0
var hp_start := 0.0
var log_t := 0.0
var done_at := -1.0

func _process(delta: float) -> bool:
	if not started:
		started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			mode = args[0]
		if args.size() > 1:
			cls = args[1]
		g = load("res://game/prologue_game.gd").new()
		g.autostart = false
		g.play_opening = false
		g.save_path = "user://sim_conjoined_save.json"
		root.add_child(g)
		g.start_game("new")
		load("res://player/player_factory.gd").apply_class(g.player, "res://content/classes/%s.tres" % cls)
		g.player.global_position = Vector3(0, 0.1, -50.5)
		g.player.process_mode = Node.PROCESS_MODE_INHERIT
		var pc = g.player.get_node("CombatComponent")
		hp_start = pc.pools.hp
		root.get_node("EventBus").creature_part_severed.connect(func(cid, ids): print("t=%.1f   severed %s: %s" % [t, cid, ids]))
		print("mode=%s class=%s player_hp=%.0f attacks=%s" % [mode, cls, hp_start, pc.available_attacks().map(func(a): return a.id)])
		return false
	t += delta
	if g.dialogue.is_open():
		g.dialogue.close_box()  # 前廳的旁白會暫停世界；模擬直接關掉
	var pc = g.player.get_node("CombatComponent")
	var enemies := _enemies()
	if split_at < 0.0 and enemies.any(func(e): return String(e.get_meta(&"enemy_id")).begins_with("nun_sister")):
		split_at = t
		print("t=%.1f SPLIT  player_hp=%.0f" % [t, pc.pools.hp])
	if pc.is_dead():
		print("t=%.1f PLAYER DIED  split=%s" % [t, split_at])
		quit()
		return false
	if enemies.is_empty():
		if done_at < 0.0:
			done_at = t
		if t - done_at < 0.3:
			return false  # 等生成點在下一格設定「已打倒」旗標
		print("t=%.1f ALL DEAD  split_at=%.1f  player_hp=%.0f/%.0f (lost %.0f)  defeated_flag=%s" % [t, split_at, pc.pools.hp, pc.pools.max_hp, hp_start - pc.pools.hp, root.get_node("GameState").has_flag(&"conjoined_defeated")])
		quit()
		return false
	_bot(pc, enemies)
	if t - log_t > 2.0:
		log_t = t
		var parts := []
		for e in enemies:
			parts.append("%s %s hp=%.0f st=%s grip=%d" % [e.get_meta(&"enemy_id"), e.global_position.snapped(Vector3.ONE * 0.1), e.get_node("CombatComponent").pools.hp, e.get_node("EnemyAI").state(), e.get_node("AnatomyComponent").state.capabilities().count("grip")])
		print("t=%.1f p=%s player_hp=%.0f bleed=%.2f | %s" % [t, g.player.global_position.snapped(Vector3.ONE * 0.1), pc.pools.hp, pc.anatomy.state.total_bleed_rate(), ", ".join(parts)])
	if t > 120.0:
		print("TIMEOUT")
		quit()
	return false

func _enemies() -> Array:
	return g.level.get_children().filter(func(n): return n is CharacterBody3D and n.has_meta(&"enemy_id") \
		and String(n.get_meta(&"enemy_id")) in ["conjoined_nun", "nun_sister_a", "nun_sister_b"] \
		and not n.is_queued_for_deletion() and not n.get_node("CombatComponent").is_dead())

func _bot(pc, enemies: Array) -> void:
	var p: CharacterBody3D = g.player
	var best: Node3D = null
	var bd := INF
	for e in enemies:
		var d := p.global_position.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	var to: Vector3 = best.global_position - p.global_position
	to.y = 0
	if to.length() > 0.01:
		p.rotation.y = atan2(-to.x, -to.z)
	var attacks: Array = pc.available_attacks()
	var reach: float = attacks[0].reach if not attacks.is_empty() else 1.2
	var ctrl := p.get_node_or_null("PlayerController")
	if ctrl != null:
		ctrl.set_physics_process(false)
	if bd > reach * 0.9:
		p.velocity = to.normalized() * 3.5 * pc.movement_multiplier()
	else:
		p.velocity = Vector3.ZERO
	p.move_and_slide()
	if pc.action != 0 or mode == "idle":
		return
	var part := &""
	var st = best.get_node("AnatomyComponent").state
	if mode == "seam" and st.get_part(&"seam") != null and not st.get_part(&"seam").severed:
		part = &"seam"
	elif mode == "heads":
		for h in [&"head_a", &"head_b", &"head"]:
			if st.get_part(h) != null and st.get_part(h).is_functional() and not st.get_part(h).severed:
				part = h
				break
	for a in attacks:
		if pc.can_use(a) and bd <= a.reach + 0.3:
			pc.try_attack(a, part)
			break
