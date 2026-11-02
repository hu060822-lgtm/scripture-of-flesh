extends TestCase
## 聲音系統 A3：分層音樂（stem 同步、狀態混音、淡入淡出、死亡 stinger）、房間環境音。

var am: Node
var mixer: MusicMixer

func before_each() -> void:
	am = tree.root.get_node("AudioManager")
	mixer = am.music
	am.director.reset()
	am.set_music_state(&"silence")
	mixer.advance(10.0)
	am.set_ambience(&"")
	am.ambience.advance(10.0)

func test_all_stems_exist_loop_and_share_one_length() -> void:
	assert_true(mixer.has_stems(), "stems imported")
	var used := {}
	for st in MusicMixer.MIXES:
		for stem in MusicMixer.MIXES[st]:
			used[stem] = true
	for stem in used:
		assert_true(mixer.players.has(stem), "stem file for %s" % stem)
	var length := -1.0
	for stem in mixer.players:
		var s: AudioStream = mixer.players[stem].stream
		assert_true(s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop, "%s loops" % stem)
		if length < 0.0:
			length = s.get_length()
		assert_near(s.get_length(), length, 0.01, "%s same length (sync)" % stem)
	assert_near(length, 40.0, 0.05, "16 bars of 3/4 at 72 BPM")

func test_every_music_state_from_the_director_has_a_mix() -> void:
	for st in [&"silence", &"menu", &"explore", &"tension", &"combat", &"boss_1", &"boss_2", &"death",
			&"ending_burn", &"ending_mother", &"ending_escape"]:
		assert_true(MusicMixer.MIXES.has(st), "mix for %s" % st)
	for id in PrologueGame.ENDINGS:
		assert_true(MusicMixer.MIXES.has(StringName("ending_" + id)), "ending %s" % id)

func test_state_change_fades_layers() -> void:
	am.set_music_state(&"explore")
	assert_true(mixer.running, "stems started")
	assert_true(mixer.players[&"lullaby"].playing)
	mixer.advance(MusicMixer.FADE * 0.5)
	assert_near(mixer.levels[&"lullaby"], 0.275, 0.01, "halfway through the fade")
	mixer.advance(MusicMixer.FADE)
	assert_near(mixer.levels[&"lullaby"], 0.55, 0.001)
	assert_eq(mixer.levels[&"heartbeat"], 0.0)
	am.set_music_state(&"combat")
	assert_eq(mixer.fade_time, MusicMixer.FADE_FAST, "combat comes in fast")
	mixer.advance(MusicMixer.FADE_FAST + 0.01)
	assert_eq(mixer.levels[&"lullaby"], 0.0, "lullaby gone in combat")
	assert_near(mixer.levels[&"heartbeat"], 0.9, 0.001)
	am.set_music_state(&"silence")
	mixer.advance(MusicMixer.FADE + 0.1)
	assert_false(mixer.running, "stopped after fading out")
	assert_false(mixer.players[&"lullaby"].playing)

func test_death_pulls_the_music_and_plays_a_stinger() -> void:
	am.set_music_state(&"combat")
	mixer.advance(5.0)
	am.set_music_state(&"death")
	assert_true(mixer.stinger_player.playing, "death stinger")
	mixer.advance(MusicMixer.FADE_FAST + 0.1)
	for stem in mixer.levels:
		assert_eq(mixer.levels[stem], 0.0, "%s silent on death" % stem)

func test_boss_phase_two_swaps_hum_for_broken_hum() -> void:
	am.set_music_state(&"boss_1")
	mixer.advance(5.0)
	assert_true(mixer.levels[&"hum"] > 0.5)
	am.set_music_state(&"boss_2")
	mixer.advance(5.0)
	assert_eq(mixer.levels[&"hum"], 0.0)
	assert_true(mixer.levels[&"hum_broken"] > 0.5)

func test_ambience_crossfades() -> void:
	var amb: AmbiencePlayer = am.ambience
	for id in AudioDirector.AREA_AMBIENCE.values():
		assert_true(amb.streams.has(id), "ambience file %s" % id)
	am.set_ambience(&"ward")
	amb.advance(AmbiencePlayer.FADE + 0.1)
	assert_near(amb.level_of_active(), 1.0, 0.01)
	var first := amb._active
	am.set_ambience(&"chapel")
	amb.advance(AmbiencePlayer.FADE + 0.1)
	assert_true(amb._active != first, "switched player")
	assert_near(amb.level_of_active(), 1.0, 0.01)
	assert_false(first.playing, "old room faded out")
	am.set_ambience(&"")
	amb.advance(AmbiencePlayer.FADE + 0.1)
	assert_false(amb._a.playing or amb._b.playing, "silent")

func test_ambience_follows_the_nearest_area() -> void:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	var a := AreaTrigger.new()
	a.trigger_id = &"enter_corridor"
	tree.root.add_child(a)
	a.global_position = Vector3(0, 0, -8)
	var b := AreaTrigger.new()
	b.trigger_id = &"enter_antechamber"
	tree.root.add_child(b)
	b.global_position = Vector3(0, 0, -49)
	p.global_position = Vector3(0, 0, -10)
	assert_eq(am.director.area_ambience(), &"corridor")
	p.global_position = Vector3(0, 0, -45)
	assert_eq(am.director.area_ambience(), &"chapel")
	am.director._physics_process(0.0)
	assert_eq(am.ambience_id, &"chapel")
	p.global_position = Vector3(0, 0, -9)
	am.director._physics_process(0.0)
	assert_eq(am.ambience_id, &"corridor", "walking back switches back")
