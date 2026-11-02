extends TestCase
## 聲音系統 A4：低血量悶聲、斷肢耳鳴、異化低語。

var am: Node
var ps: PsycheAudio

func before_each() -> void:
	am = tree.root.get_node("AudioManager")
	ps = am.psyche
	am.director.reset()

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	return p

func _lp_enabled() -> bool:
	return AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(&"SFX"), 0)

func _cutoff() -> float:
	return (AudioServer.get_bus_effect(AudioServer.get_bus_index(&"SFX"), 0) as AudioEffectLowPassFilter).cutoff_hz

func _run(seconds: float, step: float = 0.25) -> void:
	var t := 0.0
	while t < seconds:
		am.director.update_psyche(step)
		t += step

func test_assets_exist() -> void:
	assert_true(ps.tinnitus_player.stream != null, "tinnitus")
	assert_eq(ps.whispers.size(), 4)

func test_muffle_curve() -> void:
	assert_eq(PsycheAudio.low_hp_muffle(1.0), 0.0)
	assert_eq(PsycheAudio.low_hp_muffle(0.30), 0.0)
	assert_near(PsycheAudio.low_hp_muffle(0.175), 0.5, 0.001)
	assert_eq(PsycheAudio.low_hp_muffle(0.02), 1.0)
	assert_near(PsycheAudio.cutoff_for(0.0), 6000.0, 0.1)
	assert_near(PsycheAudio.cutoff_for(1.0), 600.0, 0.1)

func test_low_hp_muffles_world_sounds() -> void:
	var p := _player()
	var c: CombatComponent = p.get_node("CombatComponent")
	_run(0.25)
	assert_false(_lp_enabled(), "full HP: clear")
	c.pools.hp = c.pools.max_hp * 0.1
	_run(0.25)
	assert_true(_lp_enabled(), "low HP: muffled")
	assert_true(_cutoff() < 1500.0, "cutoff %s" % _cutoff())
	assert_false(AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(&"Voice"), 0) if AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"Voice")) > 0 else false, "voice stays clear")
	c.pools.hp = c.pools.max_hp
	_run(0.25)
	assert_false(_lp_enabled(), "healed: clear again")

func test_own_sever_rings_and_muffles_briefly() -> void:
	var p := _player()
	var c: CombatComponent = p.get_node("CombatComponent")
	c.anatomy.state.sever_part(&"arm_l")
	assert_true(ps.tinnitus_player.playing, "tinnitus")
	_run(0.25)
	assert_true(ps.muffle > 0.6, "muffled after sever: %s" % ps.muffle)
	_run(PsycheAudio.SEVER_MUFFLE_SECONDS + 0.5)
	assert_eq(ps.muffle, 0.0, "fades out")
	ps.tinnitus_player.stop()

func test_enemy_sever_does_not_ring() -> void:
	_player()
	var e := EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"stitcher")
	tree.root.add_child(e)
	(e.get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"arm_l")
	assert_false(ps.tinnitus_player.playing)

func test_whispers_grow_with_mutation() -> void:
	var p := _player()
	var mut: MutationComponent = p.get_node("MutationComponent")
	ps.rng.seed = 7
	ps.whisper_count = 0
	mut.value = 10.0
	_run(120.0, 0.5)
	assert_eq(ps.whisper_count, 0, "no whispers below 25")
	mut.value = 50.0
	_run(120.0, 0.5)
	var at_50 := ps.whisper_count
	ps.whisper_count = 0
	mut.value = 100.0
	_run(120.0, 0.5)
	var at_100 := ps.whisper_count
	assert_true(at_50 >= 2, "some whispers at 50: %d" % at_50)
	assert_true(at_100 > at_50 * 2, "much more at 100: %d vs %d" % [at_100, at_50])
	assert_true(ps.whisper_player.playing, "a whisper is playing")
	assert_true(ps.whisper_player.global_position.distance_to(p.global_position) > 2.0, "around the player")
	ps.whisper_player.stop()
