extends TestCase
## 演出（M11）：移植過場、Boss 演出、對話打字機與立繪、開門動畫、匯出設定。

func before_each() -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)

func test_transplant_cutscene_sequence() -> void:
	var cs := TransplantCutscene.new()
	tree.root.add_child(cs)
	var profile: AnatomyProfile = load("res://content/anatomy/humanoid.tres")
	var finished := []
	cs.finished.connect(func(): finished.append(true))
	cs.play(profile.get_part(&"arm_l"), profile, &"player", &"iron_arm", false, "鐵臂")
	assert_true(cs.visible and cs.playing)
	assert_true(cs.new_part.find_child("Band0", true, false) != null, "shows the transplanted organ's model")
	cs.advance(0.5)
	assert_eq(cs.stitches_shown(), 0)
	assert_true(cs.new_part.position.y > 0.5, "new part still above the slab")
	cs.advance(2.0)
	assert_true(cs.stitches_shown() > 0 and cs.stitches_shown() < 7, "stitching one by one")
	assert_true(cs.new_part.position.y < 0.01, "new part in place")
	cs.advance(2.0)
	assert_eq(finished, [true])
	assert_false(cs.visible)
	cs.queue_free()

func test_rejected_transplant_turns_necrotic() -> void:
	var cs := TransplantCutscene.new()
	tree.root.add_child(cs)
	var profile: AnatomyProfile = load("res://content/anatomy/humanoid.tres")
	cs.play(profile.get_part(&"leg_r"), profile, &"player", &"reverse_leg", true, "反關節腿")
	cs.advance(3.5)
	assert_true(cs.new_part.has_meta(&"necrotic"))
	assert_true(cs.caption.text.contains("排斥"))
	cs.queue_free()

func test_transplant_screen_plays_cutscene_and_returns() -> void:
	var p := PlayerFactory.create([], PlayerFactory.DEFAULT_CLASS)
	tree.root.add_child(p)
	var screen := TransplantScreen.new()
	tree.root.add_child(screen)
	screen.open(p)
	var organ: OrganDefinition = load("res://content/organs/iron_arm.tres")
	var outcome := TransplantScreen.perform(p, organ, &"arm_l", RandomNumberGenerator.new())
	screen.play_cutscene(organ, &"arm_l", outcome)
	assert_true(screen.cutscene.playing)
	assert_false(screen._root.visible, "panel hidden during the cutscene")
	screen.cutscene.advance(TransplantCutscene.DURATION + 0.1)
	assert_true(screen._root.visible, "panel back afterwards")
	screen.close_screen()
	screen.queue_free()

func test_dialogue_typewriter_and_portrait() -> void:
	var box := DialogueBox.new()
	tree.root.add_child(box)
	assert_true(box.open("agnes_intro", null))
	assert_eq(box.portrait.look, &"agnes", "Agnes has a rendered portrait")
	assert_true(box.portrait.bust.find_child("Hood", true, false) != null, "wimple on the bust")
	assert_true(box.is_typing(), "text types out")
	assert_eq(box._text.visible_characters, 0)
	var typed := []
	box.typed.connect(func(c): typed.append(c))
	box.type_step(0.1)
	assert_true(box._text.visible_characters > 0 and box.is_typing())
	assert_eq(typed.size(), box._text.visible_characters)
	var first_line := box.runner.text()
	box.finish_typing()
	assert_false(box.is_typing())
	assert_eq(box.runner.text(), first_line, "finishing the line does not skip it")
	box.close_box()
	box.queue_free()

func test_boss_scream_wave_and_birth_from_womb() -> void:
	var b := BossFactory.create_mother()
	b.position = Vector3(0, 0, -4)
	tree.root.add_child(b)
	var bp: BossPhaseComponent = b.get_node("BossPhase")
	var w := bp.spawn_scream_wave()
	assert_true(w != null and w.is_inside_tree())
	w.advance(0.5)
	assert_true(w.get_node("Ring0").scale.x > 2.0, "ring expands")
	w.advance(1.0)
	assert_true(w.is_queued_for_deletion(), "wave fades out")
	bp.engage()
	var add := bp.summon()
	assert_true(add.global_position.y > 1.0, "unborn drops from the womb (falls with gravity)")
	b.queue_free()
	add.queue_free()

func test_intro_clip_and_boss_intro_restores_time() -> void:
	var b := BossFactory.create_mother()
	tree.root.add_child(b)
	var intro := BossIntro.new()
	tree.root.add_child(intro)
	intro.start(b, null)
	assert_eq(TimeScale.mode, TimeScale.Mode.PAUSE)
	var anim: CreatureAnimator = b.get_node("CreatureAnimator")
	assert_eq(anim.current_clip, &"intro")
	intro.advance(BossIntro.DURATION + 0.1)
	assert_false(intro.playing)
	assert_eq(anim.override_clip, &"")
	assert_eq(TimeScale.mode, TimeScale.Mode.NORMAL)
	b.queue_free()
	intro.queue_free()

func test_gate_door_swings_open() -> void:
	var gate := BossGate.new()
	gate.object_id = &"test_gate"
	tree.root.add_child(gate)
	assert_true(gate.get_node_or_null("DoorVisual/HingeL/Leaf") != null, "gothic double door")
	assert_true(gate.get_node_or_null("Blocker") != null)
	GameState.taken[&"test_gate"] = true
	gate._on_used()
	assert_true(gate.get_node_or_null("Blocker") == null, "blocker removed immediately")
	assert_near(gate.open_amount(), 0.0, 0.01, "doors start closed")
	gate.advance_open(BossGate.OPEN_TIME * 0.5)
	assert_true(gate.open_amount() > 0.2 and gate.open_amount() < 1.0, "swinging")
	gate.advance_open(BossGate.OPEN_TIME)
	assert_near(gate.open_amount(), 1.0, 0.01)
	GameState.taken.erase(&"test_gate")
	gate.queue_free()

func test_export_preset_includes_dialogue_json() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	for sec in ["preset.0", "preset.1"]:
		assert_true(String(cfg.get_value(sec, "include_filter", "")).contains("*.json"), "%s includes *.json" % sec)
		assert_true(String(cfg.get_value(sec, "exclude_filter", "")).contains("tests/*"))
