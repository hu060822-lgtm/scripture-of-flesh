extends TestCase
## 受傷／瀕死畫面效果：HP 曲線、部位效果、心跳、心臟剪影、死亡縫合、閃爍設定。

const SETTINGS := "user://test_injury_settings.cfg"

func _anat() -> AnatomyState:
	return AnatomyState.from_profile(load("res://content/anatomy/humanoid.tres"))

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	return p

func _overlay(p: Node) -> InjuryOverlay:
	var o := InjuryOverlay.new()
	o.player = p.get_node("CombatComponent")
	tree.root.add_child(o)
	return o

func _run(o: InjuryOverlay, seconds: float, step: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		o._process(step)
		t += step

func test_intensity_curve_matches_audio_muffle() -> void:
	assert_eq(InjuryOverlay.intensity_for(1.0), 0.0)
	assert_eq(InjuryOverlay.intensity_for(0.30), 0.0)
	assert_near(InjuryOverlay.intensity_for(0.175), 0.5, 0.001)
	assert_eq(InjuryOverlay.intensity_for(0.0), 1.0)
	for hp in [0.0, 0.1, 0.2, 0.3, 0.6]:
		assert_near(InjuryOverlay.intensity_for(hp), PsycheAudio.low_hp_muffle(hp), 0.001, "same curve at %s" % hp)

func test_healthy_body_has_no_effect() -> void:
	var fx := InjuryOverlay.compute(_anat(), 1.0)
	for k in ["intensity", "desat", "eye_l", "eye_r", "wobble", "double_vision"]:
		assert_eq(fx[k], 0.0, k)
	assert_false(fx.heart_ghost)
	assert_eq(fx.bpm, InjuryOverlay.BPM.x)

func test_low_hp_raises_heart_rate_and_double_vision() -> void:
	var fx := InjuryOverlay.compute(_anat(), 0.05)
	assert_eq(fx.intensity, 1.0)
	assert_eq(fx.bpm, InjuryOverlay.BPM.y)
	assert_eq(fx.double_vision, 1.0)
	assert_true(InjuryOverlay.compute(_anat(), 0.2).double_vision == 0.0, "double vision only near death")

func test_lost_eye_darkens_that_side_only() -> void:
	var a := _anat()
	a.sever_part(&"eye_l")
	var fx := InjuryOverlay.compute(a, 1.0)
	assert_eq(fx.eye_l, 1.0)
	assert_eq(fx.eye_r, 0.0)

func test_damaged_head_wobbles_proportionally() -> void:
	var a := _anat()
	var head := a.get_part(&"head")
	head.hp = head.def.max_hp * 0.8
	assert_eq(InjuryOverlay.compute(a, 1.0).wobble, 0.0, "light damage: nothing")
	head.hp = head.def.max_hp * 0.35
	assert_near(InjuryOverlay.compute(a, 1.0).wobble, 0.5, 0.001)

func test_bleeding_drains_colour() -> void:
	var a := _anat()
	a.sever_part(&"arm_l")
	assert_true(a.total_bleed_rate() > 0.0, "stump bleeds")
	assert_true(InjuryOverlay.compute(a, 1.0).desat > 0.2, "colour drains while bleeding")

func test_failing_heart_enables_ghost() -> void:
	var a := _anat()
	var heart := a.get_part(&"heart")
	heart.hp = heart.def.max_hp * 0.2
	assert_true(InjuryOverlay.compute(a, 1.0).heart_ghost)

func test_overlay_hidden_at_full_hp_and_beats_when_low() -> void:
	var p := _player()
	var o := _overlay(p)
	var c: CombatComponent = p.get_node("CombatComponent")
	_run(o, 0.5)
	assert_false(o.rect.visible, "no full-screen pass when healthy")
	assert_eq(o.beats, 0)
	c.pools.hp = c.pools.max_hp * 0.1
	_run(o, 3.0)
	assert_true(o.rect.visible)
	# 10% HP → 約 116 BPM：3 秒內應有 5–6 拍
	assert_true(o.beats >= 5 and o.beats <= 7, "beats %d" % o.beats)
	assert_true(o.heart_player.stream != null, "heartbeat sound exists")
	assert_eq(o.heart_player.bus, &"Voice")
	o.queue_free()
	p.queue_free()

func test_ghost_respects_flash_setting() -> void:
	var p := _player()
	var o := _overlay(p)
	var heart := (p.get_node("CombatComponent") as CombatComponent).anatomy.state.get_part(&"heart")
	heart.hp = heart.def.max_hp * 0.1
	o.flashes_enabled = false
	o.rng.seed = 1
	_run(o, 40.0)
	assert_true(o.ghosts >= 1, "the hum still plays")
	assert_true(o.hum_player.stream != null, "child hum exists")
	assert_eq(o._ghost_left, 0.0, "no silhouette when flashes are off")
	o.queue_free()
	p.queue_free()

func test_death_sews_the_screen_shut() -> void:
	var p := _player()
	var o := _overlay(p)
	var c: CombatComponent = p.get_node("CombatComponent")
	_run(o, 0.1)
	assert_eq(o.sew_progress(), -1.0)
	c.pools.hp = 0.0
	c._die("test")
	_run(o, 0.8)
	assert_true(c.is_dead(), "dead")
	assert_true(o.sew_progress() > 0.3 and o.sew_progress() < 1.0, "sewing %s" % o.sew_progress())
	_run(o, 1.2)
	assert_eq(o.sew_progress(), 1.0)
	assert_true(o.rect.visible)
	o.reset()
	assert_eq(o.sew_progress(), -1.0)
	o.queue_free()
	p.queue_free()

func test_flash_setting_round_trips() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)
	assert_true(InjuryOverlay.load_flashes_setting(SETTINGS), "default on")
	InjuryOverlay.save_flashes_setting(SETTINGS, false)
	assert_false(InjuryOverlay.load_flashes_setting(SETTINGS))
	DirAccess.remove_absolute(SETTINGS)

func test_prologue_builds_overlay() -> void:
	var g := PrologueGame.new()
	g.autostart = false
	g.save_path = "user://test_injury_prologue.json"
	tree.root.add_child(g)
	g.start_game("new")
	assert_true(g.injury != null and g.injury.player == g.player.get_node("CombatComponent"))
	g.queue_free()
