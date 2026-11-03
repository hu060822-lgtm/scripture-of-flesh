extends SceneTree
## 手動模擬（真實物理）：沿序章的線性路線走一遍，確認坡道、高台、跳下缺口、水室坡道、捷徑門都走得通，
## 冷藏室的蛇行走道與冰櫃室也走一遍，
## 再拿鑰匙觸發母親追逐：玩家穿過通道、繞過被肉封住的東梯、從西梯逃上高台。不屬於自動測試。
## 執行：godot --headless --path . -s tests/sim/sim_route.gd [-- nododge]
##   預設：看到她預備撲擊就翻滾；nododge：從不翻滾（被抓時會狂按 E）。
var g: Node
var started := false
var t := 0.0
var leg := 0
var wp_i := 0
var stuck := 0.0
var last_pos := Vector3.ZERO
var phase := "route"
var chase_t := 0.0
var min_gap := INF
var dodge := true
var lunges := 0
var near_s := 0.0
const ESCAPE := [Vector3(18, 0, -40), Vector3(9.5, 0, -40), Vector3(-1.5, 0, -39.6), Vector3(-4.5, 0, -37.5), Vector3(-4.5, 2, -29.0)]
var esc_i := 0

const ROUTE := [
	["corridor", [Vector3(0, 0, -8), Vector3(0, 0, -15.7), Vector3(7.75, 0, -15.7), Vector3(7.75, 0, -17.8)]],
	["ramp_up", [Vector3(7.75, 2, -24.5), Vector3(6.0, 2, -28.2)]],
	["terrace", [Vector3(2.0, 2, -28.6)]],
	["drop_gap", [Vector3(2.0, 0, -32.0)]],
	["courtyard_to_west_stairs", [Vector3(-4.5, 0, -37.5), Vector3(-4.5, 2, -29.0)]],
	["terrace_back_down", [Vector3(-4.5, 2, -29.0), Vector3(-4.5, 0, -37.5)]],
	["archive", [Vector3(-11, 0, -36), Vector3(-22, 0, -36), Vector3(-22, 0, -41), Vector3(-13, 0, -41)]],
	["cold_storage", [Vector3(-22, 0, -41), Vector3(-22, 0, -36), Vector3(-11.5, 0, -36), Vector3(-12, 0, -31.4), Vector3(-20, 0, -31.4), Vector3(-20, 0, -28.5), Vector3(-20, -2.5, -21), Vector3(-14.5, -2.5, -20.5), Vector3(-14.5, -2.5, -16), Vector3(-25.5, -2.5, -16), Vector3(-25.5, -2.5, -11), Vector3(-14, -2.5, -10.3), Vector3(-10.5, -2.5, -10.3)]],
	["cold_storage_back", [Vector3(-14, -2.5, -10.3), Vector3(-25.5, -2.5, -11), Vector3(-25.5, -2.5, -16), Vector3(-14.5, -2.5, -16), Vector3(-14.5, -2.5, -20.5), Vector3(-20, -2.5, -21), Vector3(-20, 0, -28.5), Vector3(-20, 0, -31.4), Vector3(-12, 0, -31.4), Vector3(-11.5, 0, -36), Vector3(-22, 0, -36), Vector3(-22, 0, -41), Vector3(-13, 0, -41)]],
	["cistern", [Vector3(-13, 0, -42.5), Vector3(-13, -2, -50.5), Vector3(-18, -2, -51)]],
	["cistern_back", [Vector3(-13, -2, -50.5), Vector3(-13, 0, -42), Vector3(-22, 0, -41), Vector3(-22, 0, -36), Vector3(-11, 0, -36)]],
	["to_shortcut", [Vector3(0, 0, -36.5), Vector3(8.5, 0, -37.5)]],
	["sacristy", [Vector3(10.5, 0, -40), Vector3(18, 0, -40), Vector3(28.0, 0, -44.0)]],
]

func _initialize() -> void:
	dodge = not "nododge" in OS.get_cmdline_user_args()

func _physics_process(delta: float) -> bool:
	if not started:
		started = true
		g = load("res://game/prologue_game.gd").new()
		g.autostart = false
		g.play_opening = false
		g.save_path = "user://sim_route.json"
		root.add_child(g)
		g.start_game("new")
		for e in root.find_children("*", "CharacterBody3D", true, false):
			if e.has_node("EnemyAI"):
				e.queue_free()
		g.player.get_node("PlayerController").input_enabled = false
		return false
	t += delta
	if g.boss != null and is_instance_valid(g.boss):
		g.boss.process_mode = Node.PROCESS_MODE_DISABLED
	if g.dialogue.is_open():
		g.dialogue.close_box()
	var p: CharacterBody3D = g.player
	if phase == "route":
		_route(p, delta)
	elif phase == "chase":
		_chase(p, delta)
	if t > 200.0:
		print("TIMEOUT")
		quit(1)
	return false

func _walk(p: CharacterBody3D, target: Vector3, delta: float) -> bool:
	var to := target - p.global_position
	to.y = 0
	if to.length() < 0.35:
		return true
	var v := to.normalized() * 4.2
	var vy := p.velocity.y - 18.0 * delta if not p.is_on_floor() else 0.0
	p.velocity = Vector3(v.x, vy, v.z)
	p.move_and_slide()
	return false

func _route(p: CharacterBody3D, delta: float) -> void:
	if leg >= ROUTE.size():
		print("ROUTE OK t=%.1f" % t)
		# 捷徑門：從庭院這一側打開
		phase = "chase"
		var key: Node3D = g.level.get_node("Interactables/Item_item_umbilical_key")
		print("player near key: %s (key %s)" % [p.global_position, key.global_position])
		print("pickup=%s keys=%d" % [key.interact(p), p.get_node("PlayerData").inventory.count("umbilical_key")])
		return
	var name: String = ROUTE[leg][0]
	var pts: Array = ROUTE[leg][1]
	if _walk(p, pts[wp_i], delta):
		wp_i += 1
		stuck = 0.0
		if wp_i >= pts.size():
			print("leg %-26s ok  pos=(%.1f, %.2f, %.1f)  t=%.1f" % [name, p.global_position.x, p.global_position.y, p.global_position.z, t])
			if name == "to_shortcut":
				var gate = g.level.get_node("Interactables/ShortcutGate_Courtyard")
				print("  shortcut gate opened from courtyard side: %s" % gate.interact(p))
			leg += 1
			wp_i = 0
		return
	if p.global_position.distance_to(last_pos) < 0.01:
		stuck += delta
		if stuck > 2.0:
			print("STUCK in leg %s at %s heading %s" % [name, p.global_position, pts[wp_i]])
			quit(1)
	else:
		stuck = 0.0
	last_pos = p.global_position

func _chase(p: CharacterBody3D, delta: float) -> void:
	chase_t += delta
	var mc = g.mother_chase
	var pc = p.get_node("CombatComponent")
	if mc.mother != null and is_instance_valid(mc.mother) and mc.active:
		var gap: float = mc.gap()
		min_gap = minf(min_gap, gap)
		if gap < 4.0:
			near_s += delta
		if int(chase_t * 60) % 30 == 0:
			print("chase t=%.1f player=(%.1f,%.1f,%.1f) mother=(%.1f,%.1f) gap=%.1f phase=%d music=%s dread=%.2f dark=%d flesh=%d" % [chase_t, p.global_position.x, p.global_position.y, p.global_position.z,
				mc.mother.global_position.x, mc.mother.global_position.z, gap, mc.phase, mc.music_state(), mc.dread(), mc.dark_lights(), mc.flesh.size()])
		if mc.phase == 3 and mc._phase_t < delta * 1.5:
			lunges += 1
			print("  LUNGE windup #%d at t=%.1f gap=%.1f" % [lunges, chase_t, gap])
		# 會翻滾的玩家：預備快結束時往逃跑方向翻滾
		if dodge and mc.phase == 3 and mc._phase_t > 0.3 and pc.action == 0:
			var d: Vector3 = (ESCAPE[esc_i] - p.global_position)
			d.y = 0
			pc.dodge(d.normalized())
		if mc.phase == 6:
			if int(chase_t * 60) % 9 == 0:
				mc.struggle()  # 狂按 E：約每 0.15 秒一下
	if pc.is_dead():
		print("PLAYER DIED t=%.1f catches=%d lunges=%d" % [chase_t, mc.catches, lunges])
		quit(0)
		return
	# 等她出來 1 秒再逃
	if chase_t > 1.0 and mc.active and mc.phase != 6 and pc.action != 4:
		if _walk(p, ESCAPE[esc_i], delta) and esc_i < ESCAPE.size() - 1:
			esc_i += 1
	if not mc.active and chase_t > 0.5:
		print("CHASE ENDED t=%.1f reason=%s done=%s min_gap=%.2f near(<4m)=%.1fs lunges=%d catches=%d arms=%s/%s" % [chase_t, mc.end_reason, root.get_node("GameState").has_flag(&"mother_chase_done"), min_gap, near_s, lunges, mc.catches,
			not pc.anatomy.state.get_part(&"arm_l").severed,
			not pc.anatomy.state.get_part(&"arm_r").severed])
		quit(0)
