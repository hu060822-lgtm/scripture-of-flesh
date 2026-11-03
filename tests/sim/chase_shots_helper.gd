extends RefCounted
## 追逐戰截圖：玩家沿逃跑路線跑（不翻滾），讓母親真的追上來：破牆、通道、撲擊預備、被抓、庭院（燈熄、肉塊、臍帶）、被肉封住的東梯。
var tree: SceneTree
var out := "user://chase_shots"
var g: PrologueGame
var t := 0.0
var wp := 0
var shots := {}
const PATH := [Vector3(18, 0, -40), Vector3(9.5, 0, -40), Vector3(-1.5, 0, -39.6), Vector3(-4.5, 0, -37.5), Vector3(-4.5, 2, -29.0)]

func setup(tr: SceneTree, args: PackedStringArray) -> void:
	tree = tr
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	# 軟體渲染很慢：每個畫格只跑一次物理，讓時間跟畫格同步（遊戲變慢但截圖時機正確）
	Engine.max_physics_steps_per_frame = 1
	g = PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = "user://chase_shots_save.json"
	tree.root.add_child(g)
	g.start_game("new")
	(g.player.get_node("PlayerController") as PlayerController).input_enabled = false
	g.hud.visible = false
	for e in g.level.find_children("*", "CharacterBody3D", true, false):
		if e.has_node("EnemyAI") and e.global_position.x > 12.0:
			e.queue_free()  # 聖器室的多手人（假設已經打倒）

func _shot(name: String) -> void:
	if shots.has(name):
		return
	shots[name] = true
	var img := tree.root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name, " t=%.2f" % t)

func _run(dt: float) -> void:
	var p := g.player
	var mc := g.mother_chase
	if mc == null or mc.phase == MotherChase.Phase.HOLD or not (p.get_node("PlayerController") as PlayerController).input_enabled and mc.phase == MotherChase.Phase.HOLD:
		return
	var to: Vector3 = PATH[wp] - p.global_position
	to.y = 0
	if to.length() < 0.35 and wp < PATH.size() - 1:
		wp += 1
		return
	var v := to.normalized() * 4.2
	p.velocity = Vector3(v.x, p.velocity.y - 18.0 * dt if not p.is_on_floor() else 0.0, v.z)
	p.rotation.y = atan2(-v.x, -v.z)
	p.move_and_slide()

func step(fr: int) -> bool:
	if g.dialogue.is_open():
		g.dialogue.close_box()
	var dt := 1.0 / 60.0
	var mc := g.mother_chase
	if fr == 3:
		g.player.global_position = Vector3(26.5, 0, -43.0)
		g.rig.global_position = g.player.global_position
		g.rig._apply(1.0)
		(g.player.get_node("PlayerData") as PlayerData).inventory.add("umbilical_key")
		return false
	if fr < 4 or mc == null:
		return false
	if not mc.active and mc.phase != MotherChase.Phase.RETREAT and fr > 10:
		print("chase over t=%.1f reason=%s catches=%d dead=%s" % [t, mc.end_reason, mc.catches, (g.player.get_node("CombatComponent") as CombatComponent).is_dead()])
		return true
	t += dt
	if t > 0.9:
		_run(dt)
	if t > 0.55:
		_shot("c01_wall_burst")
	if mc.phase == MotherChase.Phase.WINDUP and mc._phase_t > 0.35:
		_shot("c03_lunge_windup")
	if mc.phase == MotherChase.Phase.HOLD and mc._phase_t > 0.4:
		_shot("c04_caught_mash_e")
		if mc._phase_t > 0.5:
			for i in 2:
				mc.struggle()
	if t > 2.6:
		_shot("c02_passage_running")
	if g.player.global_position.x < 5.0:
		_shot("c05_courtyard_lights_out_cord_flesh")
	if mc.active and mc.gap() < 3.6 and g.player.global_position.x < 3.0:
		_shot("c06_courtyard_she_is_right_behind")
	if (g.player.get_node("CombatComponent") as CombatComponent).is_dead():
		if g.injury.sew_progress() > 0.55:
			_shot("c07_second_catch_sewn_shut")
			return true
	if t > 30.0:
		return true
	return false
