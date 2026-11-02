extends RefCounted
## 見 impact_shots.gd。截圖時以 PAUSE 凍結自動推進，手動推進戰鬥與動畫；
## 受擊閃白只持續 0.1 秒，截圖時把閃白時間拉長（只為了拍到，遊戲中不會這樣）。
var tree: SceneTree
var out := "user://impact_shots"
var scene: Node

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

func _c(n: Node) -> CombatComponent:
	return n.get_node("CombatComponent")

func _a(n: Node) -> CreatureAnimator:
	return n.get_node("CreatureAnimator")

func _attack(c: Node3D, attack: AttackDefinition, phase: int, frac: float) -> void:
	var combat := _c(c)
	combat.advance(5.0)
	combat.pools.add_ap(100)
	combat.pools.st = combat.pools.max_st
	if not combat.force_attack(attack):
		push_warning("attack failed: %s" % attack.id)
	var t := attack.windup * (frac if phase == 0 else 1.0)
	if phase >= 1:
		t += 0.001 + attack.active * (frac if phase == 1 else 1.0)
	combat.advance(t)
	_a(c).tick(t)

func step(f: int) -> bool:
	var p: CharacterBody3D = scene.player
	var st: CharacterBody3D = scene.enemies[0]
	var claw: AttackDefinition = load("res://content/attacks/claw.tres")
	if f == 5:
		scene._ai_enabled = false
		for e in scene.enemies:
			scene._set_ai(e, false)
		TimeScale.set_mode(TimeScale.Mode.PAUSE)
		TimeScale.hitstop_enabled = false
		p.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
		st.position = Vector3(-1.5, 0, 1.2)
		st.rotation.y = -PI * 0.5
		p.position = Vector3(1.5, 0, 1.2)
		p.rotation.y = PI * 0.5
		_cam(Vector3(-1.2, 1.3, 3.6), Vector3(-1.6, 0.4, 1.2))
		# 縫屍者失去雙腿 → 倒地爬行
		var s := st.get_node("AnatomyComponent").state as AnatomyState
		s.sever_part(&"leg_l")
		s.sever_part(&"leg_r")
		_a(st)._sever_timer = 0.0
		_c(st).advance(2.0)
		_a(st).tick(0.6)
	match f:
		10: _attack(st, claw, 0, 0.95)
		14: _shot("i01_prone_claw_windup")
		16: _attack(st, claw, 1, 0.9)
		20: _shot("i02_prone_claw_strike")
		22:
			_c(st).advance(5.0)
			_c(st).hit_received.emit(DamageResult.new(), _c(p))
			_a(st).tick(0.1)
		26: _shot("i03_prone_hit_flinch")
		28:
			_c(st).pools.damage_hp(9999, "shot")
			_a(st).tick(1.2)
		32: _shot("i04_prone_death_stays_down")
		34:
			# 第二隻敵人站在玩家面前，玩家骨鋸刀命中
			var e2: CharacterBody3D = scene.enemies[2] if scene.enemies.size() > 2 else scene.enemies[1]
			e2.position = Vector3(0.35, 0, 1.2)
			e2.rotation.y = -PI * 0.5
			_cam(Vector3(0.6, 1.5, 3.4), Vector3(0.4, 1.0, 1.2))
			var w: WeaponDefinition = _c(p).weapon()
			_c(p).advance(5.0)
			_c(p).force_attack(w.light_attack)
			_c(p).advance(w.light_attack.windup + 0.01)
			_a(p).tick(w.light_attack.windup + 0.05)
			var fx: ImpactFeedback = e2.get_node("ImpactFeedback")
			print("hit feedback: ", fx.last)
			fx._flash_left = 10.0  # 只為截圖：維持閃白
			fx._apply_flash()
			_a(e2).tick(1.0 / 12.0)
		36:
			for b in scene.find_children("HitBurst*", "Node3D", true, false):
				(b as HitBurst).advance(0.07)  # 截圖時戰鬥暫停：手動推進噴血
		38:
			_shot("i05_hit_flash_blood_flinch")
		39:
			var e2: CharacterBody3D = scene.enemies[2] if scene.enemies.size() > 2 else scene.enemies[1]
			var fx: ImpactFeedback = e2.get_node("ImpactFeedback")
			fx._flash_left = 0.0
			fx._apply_flash()
			_c(e2)._stagger()
			_a(e2).tick(0.5)
		42:
			_shot("i06_stagger_buckle")
			return true
	return false

func _shot(name: String) -> void:
	var img := tree.root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
