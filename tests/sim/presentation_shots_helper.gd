extends RefCounted
var tree: SceneTree
var out := "user://presentation_shots"
var scene: Node
var box: DialogueBox
var cs: TransplantCutscene
var rig: CameraRig
var intro: BossIntro
var mother: CharacterBody3D
var gate: BossGate

func setup(t: SceneTree, args: PackedStringArray) -> void:
	tree = t
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	scene = load("res://scenes/art_test/art_test.tscn").instantiate()
	tree.root.add_child(scene)

func step(f: int) -> bool:
	match f:
		5:
			for e in scene.enemies:
				e.queue_free()
			scene.enemies.clear()
			scene.hud.visible = false
			box = DialogueBox.new()
			tree.root.add_child(box)
			box.open("agnes_intro", scene.player)
			box.type_step(0.9)
		20:
			_shot("p01_dialogue_typewriter_portrait")
			box.close_box()
			cs = TransplantCutscene.new()
			tree.root.add_child(cs)
			var profile: AnatomyProfile = load("res://content/anatomy/humanoid.tres")
			cs.play(profile.get_part(&"arm_l"), profile, &"player", &"iron_arm", false, "鐵臂")
			cs.advance(1.4)
		30:
			_shot("p02_transplant_lowering")
			cs.advance(1.2)
		36:
			_shot("p03_transplant_stitching")
			cs.stop()
			mother = BossFactory.create_mother()
			mother.position = Vector3(0, 0, -3.0)
			scene.screen.world.add_child(mother)
			mother.get_node("EnemyAI").process_mode = Node.PROCESS_MODE_DISABLED
			scene.player.position = Vector3(0, 0, 3.0)
			rig = CameraRig.new()
			rig.target = scene.player
			scene.screen.world.add_child(rig)
			rig.camera.current = true
			intro = BossIntro.new()
			tree.root.add_child(intro)
			intro.start(mother, rig)
			intro.advance(0.6)
		44:
			_shot("p04_boss_intro_low")
			intro.advance(1.7)
		50:
			_shot("p05_boss_intro_scream")
			intro.stop()
			TimeScale.set_mode(TimeScale.Mode.NORMAL)
			var st: AnatomyState = (mother.get_node("AnatomyComponent") as AnatomyComponent).state
			var bp: BossPhaseComponent = mother.get_node("BossPhase")
			st.sever_part(&"stilt_1")
			st.sever_part(&"stilt_2")
			bp.advance(BossPhaseComponent.KNEEL_TIME + 0.05)
			(mother.get_node("CreatureAnimator") as CreatureAnimator).tick(0.05)
			var w := bp.spawn_scream_wave()
			w.advance(0.35)
			TimeScale.set_mode(TimeScale.Mode.PAUSE)
			rig.process_mode = Node.PROCESS_MODE_DISABLED
			rig.camera.global_position = Vector3(3.5, 3.0, 3.5)
			rig.camera.look_at(Vector3(0, 1.4, -3.0))
		58:
			_shot("p06_kneel_scream_wave")
			mother.queue_free()
			gate = BossGate.new()
			gate.position = Vector3(0, 0, -4.0)
			scene.screen.world.add_child(gate)
			gate.object_id = &"shot_gate"
			GameState.taken[&"shot_gate"] = true
			gate._on_used()
			gate.advance_open(BossGate.OPEN_TIME * 0.45)
			rig.camera.global_position = Vector3(0, 2.6, 4.0)
			rig.camera.look_at(Vector3(0, 2.0, -4.0))
		66:
			_shot("p07_gate_opening")
			return true
	return false

func _shot(name: String) -> void:
	tree.root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
