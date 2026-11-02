extends RefCounted
var tree: SceneTree
var out := "user://anim_shots"
var scene: Node
var shots := []  # [frame, name, Callable]

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	scene = load("res://scenes/art_test/art_test.tscn").instantiate()
	tree.root.add_child(scene)

func _cam(pos: Vector3, at: Vector3) -> void:
	var cam: Camera3D = scene.camera
	cam.max_track_degrees = 0.0
	cam.position = pos
	cam.look_at(at)

func _pose(c: Node3D, state: Callable, seconds: float) -> void:
	state.call()
	var anim: CreatureAnimator = c.get_node("CreatureAnimator")
	anim.tick(seconds)

func _attack(c: Node3D, attack: AttackDefinition, phase: int, frac: float) -> void:
	var combat: CombatComponent = c.get_node("CombatComponent")
	combat.advance(5.0)  # 結束前一個動作
	combat.pools.add_ap(100)
	combat.pools.st = combat.pools.max_st
	if not combat.force_attack(attack):
		push_warning("attack failed: %s" % attack.id)
	var t := attack.windup * (frac if phase == 0 else 1.0)
	if phase >= 1:
		t += 0.001 + attack.active * (frac if phase == 1 else 1.0)
	if phase >= 2:
		t += 0.001 + attack.recovery * frac
	combat.advance(t)
	(c.get_node("CreatureAnimator") as CreatureAnimator).tick(t)

func step(f: int) -> bool:
	var p: CharacterBody3D = scene.player
	var st: CharacterBody3D = scene.enemies[0]
	if f == 5:
		scene._ai_enabled = false
		for e in scene.enemies:
			scene._set_ai(e, false)
		TimeScale.set_mode(TimeScale.Mode.PAUSE)  # 凍結自動推進，手動擺姿勢
		st.position = Vector3(-1.5, 0, 1.2)
		st.rotation.y = -PI * 0.5
		p.position = Vector3(1.5, 0, 1.2)
		p.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
		p.rotation.y = PI * 0.5
		(p.get_node("CombatComponent") as CombatComponent).pools.add_ap(100)
		_cam(Vector3(0, 1.6, 4.6), Vector3(0, 0.9, 1.2))
	var w: WeaponDefinition = (p.get_node("CombatComponent") as CombatComponent).weapon()
	match f:
		10: _attack(p, w.light_attack, 0, 0.95)
		14: _shot("a01_cleaver_slash_windup")
		16: _attack(p, w.light_attack, 1, 0.9)
		20: _shot("a02_cleaver_slash_strike")
		22: _attack(p, w.heavy_attack, 0, 0.95); _attack(st, load("res://content/attacks/claw.tres"), 0, 0.95)
		26: _shot("a03_overhead_windup_and_claw_windup")
		28: _attack(p, w.heavy_attack, 1, 0.9); _attack(st, load("res://content/attacks/claw.tres"), 1, 0.9)
		32: _shot("a04_overhead_strike_and_claw_strike")
		34:
			(p.get_node("CombatComponent") as CombatComponent).advance(3.0)
			(st.get_node("CombatComponent") as CombatComponent).advance(3.0)
			p.velocity = Vector3(0, 0, -2.6); st.velocity = Vector3(0, 0, -2.6)
			(p.get_node("CreatureAnimator") as CreatureAnimator).tick(0.25)
			(st.get_node("CreatureAnimator") as CreatureAnimator).tick(0.25)
		38: _shot("a05_walk")
		40:
			st.get_node("AnatomyComponent").state.sever_part(&"leg_l")
			(st.get_node("CreatureAnimator") as CreatureAnimator)._sever_timer = 0.0
			(st.get_node("CombatComponent") as CombatComponent).advance(2.0)
			st.velocity = Vector3(1.0, 0, 0)
			(st.get_node("CreatureAnimator") as CreatureAnimator).tick(0.4)
			(p.get_node("CombatComponent") as CombatComponent).set_blocking(true)
			p.velocity = Vector3.ZERO
			(p.get_node("CreatureAnimator") as CreatureAnimator).tick(0.2)
		44: _shot("a06_limp_and_block")
		46:
			st.get_node("AnatomyComponent").state.sever_part(&"leg_r")
			(st.get_node("CreatureAnimator") as CreatureAnimator)._sever_timer = 0.0
			(st.get_node("CombatComponent") as CombatComponent).advance(2.0)
			(st.get_node("CreatureAnimator") as CreatureAnimator).tick(0.6)
			(p.get_node("CombatComponent") as CombatComponent).set_blocking(false)
			p.get_node("AnatomyComponent").state.sever_part(&"arm_l")
			(p.get_node("CreatureAnimator") as CreatureAnimator).tick(0.1)
		50: _shot("a07_crawl_and_sever_react")
		52:
			var watcher: CharacterBody3D = scene.enemies[1]
			_cam(watcher.global_position + Vector3(2.2, 2.0, 2.2), watcher.global_position + Vector3(0, 0.4, 0))
			(watcher.get_node("CombatComponent") as CombatComponent).pools.damage_hp(9999, "shot")
			(watcher.get_node("CreatureAnimator") as CreatureAnimator).tick(1.2)
		56: _shot("a08_death")
		58:
			_cam(Vector3(0, 6.2, 9.0), Vector3(0, 1.0, -2.5))
			var watcher: CharacterBody3D = scene.enemies[1]
			_attack(watcher, load("res://content/attacks/gaze.tres"), 1, 1.0)
		62:
			_shot("a09_watcher_gaze_overview")
			return true
	return false

func _shot(name: String) -> void:
	var img := tree.root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
