extends RefCounted
## 傷殘外觀、滴血、垂臂、繃帶、縫線疤、HUD 狀態圖標與人體剪影的截圖。
const T := DamageTypes.Type
var tree: SceneTree
var out := "user://injury_shots"
var scene: Node
var enemy: CharacterBody3D

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

func _hit(st: AnatomyState, part: StringName, dmg: Dictionary) -> void:
	var p := DamagePacket.make(part, dmg)
	p.sever_power = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	st.receive(p, rng)

func _st(c: Node) -> AnatomyState:
	return (c.get_node("AnatomyComponent") as AnatomyComponent).state

func step(f: int) -> bool:
	match f:
		5:
			for e in scene.enemies:
				e.queue_free()
			scene.enemies.clear()
			var p: CharacterBody3D = scene.player
			p.position = Vector3(0, 0, 1.5)
			p.rotation.y = PI
			p.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
			var st := _st(p)
			_hit(st, &"arm_l", {T.CUT: 14.0})          # 切口＋出血
			_hit(st, &"arm_r", {T.FRACTURE: 40.0})     # 骨折失效 → 垂臂、斷骨
			_hit(st, &"leg_l", {T.LACERATION: 12.0})   # 腿撕裂出血
			_hit(st, &"chest", {T.BURN: 6.0, T.CUT: 30.0})  # 灼傷＋重傷
			_cam(Vector3(0, 1.4, 4.4), Vector3(0, 1.0, 1.5))
		70: _shot("j01_wounds_bleeding_dangling_arm_hud")
		72: _cam(Vector3(0.9, 1.55, 2.6), Vector3(0.1, 1.2, 1.5))
		80: _shot("j02_closeup_wounds_bone_shard")
		82:
			var p: CharacterBody3D = scene.player
			var st := _st(p)
			# 包紮、縫回斷掉的左臂（留下縫線疤）
			st.sever_part(&"arm_l")
			st.restore_part(&"arm_l")
			st.stanch(0.8)
			(p.get_node("CombatComponent") as CombatComponent).vital_timer = 6.0
			_cam(Vector3(-0.5, 1.5, 3.0), Vector3(0, 1.1, 1.5))
		100: _shot("j03_bandage_and_suture_scar_hud")
		102:
			enemy = EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"shot_stitcher")
			enemy.position = Vector3(1.2, 0, 1.5)
			enemy.rotation.y = PI
			scene.screen.world.add_child(enemy)
			enemy.get_node("EnemyAI").process_mode = Node.PROCESS_MODE_DISABLED
			var st := _st(enemy)
			_hit(st, &"chest", {T.CUT: 40.0})
			_hit(st, &"arm_l", {T.CRUSH: 25.0, T.FRACTURE: 20.0})
			st.sever_part(&"arm_r")
			_cam(Vector3(1.2, 1.5, 3.8), Vector3(1.2, 1.0, 1.5))
		140:
			_shot("j04_enemy_wounds_and_blood_trail")
			return true
	return false

func _shot(name: String) -> void:
	tree.root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
