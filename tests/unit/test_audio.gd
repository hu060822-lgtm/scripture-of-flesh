extends TestCase
## 聲音系統 A1：匯流排、cue 目錄、播放規則（冷卻、變體、發聲上限）、事件掛勾、音樂狀態、音量設定。
## 音檔還沒放入（【暫代】靜音），所以大多數測試檢查 AudioManager.history 而不是實際聲音。

const T := DamageTypes.Type
const SETTINGS := "user://test_audio_settings.cfg"

var am: Node
var dir: AudioDirector

func before_each() -> void:
	am = tree.root.get_node("AudioManager")
	dir = am.director
	am.clear_history()
	dir.reset()
	am.set_music_state(&"silence")

func _enemy(id: String = "stitcher", pos: Vector3 = Vector3(0, 0, -2)) -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % id), StringName(id))
	tree.root.add_child(e)
	e.global_position = pos
	return e

func _player() -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	return p

func _combat(n: Node) -> CombatComponent:
	return n.get_node("CombatComponent")

func _tone(seconds: float = 0.1) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = 8000
	var d := PackedByteArray()
	d.resize(int(8000 * seconds))
	w.data = d
	return w

func test_buses_exist_and_route_to_master() -> void:
	for b in am.BUSES:
		var i := AudioServer.get_bus_index(b)
		assert_true(i > 0, "bus %s" % b)
		assert_eq(AudioServer.get_bus_send(i), &"Master", "%s sends to Master" % b)
	var sfx := AudioServer.get_bus_index(&"SFX")
	assert_true(AudioServer.get_bus_effect(sfx, 0) is AudioEffectLowPassFilter)
	assert_false(AudioServer.is_bus_effect_enabled(sfx, 0), "muffle is off by default")
	am.ensure_buses()
	assert_eq(AudioServer.bus_count, 1 + am.BUSES.size(), "ensure_buses is idempotent")

func test_catalog_cues_are_valid() -> void:
	var cues := SoundCatalog.build()
	assert_eq(cues.size(), SoundCatalog.TABLE.size())
	for id in cues:
		var c: SoundCue = cues[id]
		assert_true(AudioServer.get_bus_index(c.bus) != -1, "%s bus %s" % [id, c.bus])
		assert_true(c.pitch_min <= c.pitch_max and c.pitch_min > 0.0, "%s pitch" % id)
		assert_true(c.max_voices >= 1, "%s voices" % id)
	for id in AudioDirector.ATTACK_CUES.values():
		assert_true(cues.has(id), "attack cue %s" % id)
	# 導演會用到的每一個 cue 都要在目錄裡（掃描原始碼裡的 _cue(&"...")）
	var src := FileAccess.get_file_as_string("res://audio/audio_director.gd")
	var re := RegEx.create_from_string("&\"([a-z_]+)\"")
	for m in re.search_all(src):
		var name := StringName(m.get_string(1))
		if src.find("_cue(&\"%s\"" % name) != -1 or src.find("&\"%s\" if" % name) != -1 or src.find("else &\"%s\"" % name) != -1:
			assert_true(cues.has(name), "director uses unknown cue %s" % name)

func test_placeholder_cue_is_recorded_silently_with_cooldown() -> void:
	assert_true(am.cues[&"sever"].is_placeholder(), "no audio files yet")
	assert_eq(am.play(&"sever"), null)
	assert_eq(am.last_played(), [&"sever"])
	assert_true(am.history[-1].silent)
	am.play(&"sever")
	assert_eq(am.history.size(), 1, "cooldown blocks the immediate repeat")
	am.advance(1.0)
	am.play(&"sever")
	assert_eq(am.history.size(), 2)

func test_variants_do_not_repeat_and_voices_are_limited() -> void:
	var cue := SoundCue.new(&"test", &"SFX")
	cue.cooldown = 0.0
	cue.max_voices = 2
	cue.positional = false
	cue.streams = [_tone(), _tone(), _tone()]
	am.cues[&"test"] = cue
	var last := -1
	for i in 30:
		var idx := cue.pick(am.rng, last)
		assert_true(idx != last, "no immediate repeat")
		last = idx
	var p := am.play(&"test") as AudioStreamPlayer
	assert_true(p != null and p.playing, "plays a real stream")
	assert_eq(p.bus, &"SFX")
	assert_true(p.pitch_scale >= cue.pitch_min and p.pitch_scale <= cue.pitch_max)
	am.play(&"test")
	am.play(&"test")
	var playing := 0
	for v in am._voices[&"test"]:
		if v.playing:
			playing += 1
	assert_true(playing <= 2, "max_voices respected: %d" % playing)
	am.cues.erase(&"test")

func test_positional_cue_uses_3d_player_at_body() -> void:
	var cue := SoundCue.new(&"test3d", &"SFX")
	cue.streams = [_tone()]
	am.cues[&"test3d"] = cue
	var e := _enemy("stitcher", Vector3(3, 0, -4))
	var p := am.play(&"test3d", e) as AudioStreamPlayer3D
	assert_true(p != null, "3D player")
	assert_near(p.global_position.distance_to(Vector3(3, 0, -4)), 0.0, 0.01)
	am.cues.erase(&"test3d")

func test_hit_cue_by_dominant_damage_type() -> void:
	var r := DamageResult.new()
	var h := DamageResult.PartHit.new()
	h.hp_loss = 5.0
	h.injuries = {T.CUT: 4.0, T.CRUSH: 1.0}
	r.hits.append(h)
	assert_eq(AudioDirector.hit_cue(r), &"hit_cut")
	h.injuries = {T.FRACTURE: 6.0, T.CUT: 1.0}
	assert_eq(AudioDirector.hit_cue(r), &"hit_blunt")
	h.injuries = {T.PIERCE: 3.0}
	assert_eq(AudioDirector.hit_cue(r), &"hit_pierce")
	h.injuries = {T.BURN: 3.0}
	assert_eq(AudioDirector.hit_cue(r), &"hit_burn")
	h.hp_loss = 0.0
	assert_eq(AudioDirector.hit_cue(r), &"hit_armor", "no damage = armor")

func test_severing_a_limb_plays_sever_and_bone() -> void:
	var e := _enemy()
	_combat(e).anatomy.state.sever_part(&"arm_l")
	var ids: Array = am.played_ids()
	assert_true(&"sever" in ids and &"bone_snap" in ids, str(ids))

func test_anatomy_hooks_survive_state_replacement() -> void:
	var e := _enemy()
	var c := _combat(e)
	c.anatomy.setup()  # 讀檔會換掉 AnatomyState
	dir._physics_process(0.0)
	c.anatomy.state.sever_part(&"arm_r")
	assert_true(&"sever" in am.played_ids(), "new state hooked")

func test_combat_signals_map_to_cues() -> void:
	var e := _enemy()
	var c := _combat(e)
	c.attack_started.emit(c.natural_attacks[0] if not c.natural_attacks.is_empty() else AttackDefinition.new())
	c.dodged.emit(null)
	c.staggered.emit()
	assert_eq(am.played_ids(), [&"attack_swing", &"dodge", &"stagger"])
	am.clear_history()
	# 防禦成功的同一幀，命中聲不再疊加
	c.blocked.emit(null, false)
	var r := DamageResult.new()
	var h := DamageResult.PartHit.new()
	h.hp_loss = 2.0
	h.injuries = {T.CUT: 2.0}
	r.hits.append(h)
	c.hit_received.emit(r, null)
	assert_eq(am.played_ids(), [&"block"])
	am.clear_history()
	c.died.emit("test")
	assert_eq(am.played_ids(), [&"death_enemy"])

func test_boss_birth_scream_uses_birth_cry() -> void:
	var b := BossFactory.create_mother()
	tree.root.add_child(b)
	var bp: BossPhaseComponent = b.get_node("BossPhase")
	var st := _combat(b).anatomy.state
	st.sever_part(&"stilt_1")
	st.sever_part(&"stilt_2")
	var ids: Array = am.played_ids()
	assert_true(&"boss_kneel" in ids, str(ids))
	assert_true(&"boss_birth_cry" in ids, "kneeling scream: %s" % str(ids))
	assert_eq(bp.phase, 2)

func test_buttons_play_ui_confirm() -> void:
	var btn := Button.new()
	tree.root.add_child(btn)
	btn.pressed.emit()
	assert_eq(am.last_played(), [&"ui_confirm"])

func test_music_state_follows_the_game() -> void:
	var p := _player()
	dir.update_music(0.0)
	assert_eq(am.music_state, &"explore")
	var e := _enemy()
	var ai: EnemyAI = e.get_node("EnemyAI")
	ai.force_state(&"detect")
	dir.update_music(0.1)
	assert_eq(am.music_state, &"tension")
	ai.force_state(&"chase")
	dir.update_music(0.1)
	assert_eq(am.music_state, &"combat")
	ai.force_state(&"patrol")
	dir.update_music(0.1)
	assert_eq(am.music_state, &"combat", "combat music lingers")
	dir.update_music(AudioDirector.COMBAT_HOLD + 0.1)
	assert_eq(am.music_state, &"explore")
	var b := BossFactory.create_mother()
	tree.root.add_child(b)
	var bp: BossPhaseComponent = b.get_node("BossPhase")
	bp.engage()
	dir.update_music(0.1)
	assert_eq(am.music_state, &"boss_1")
	_combat(b).anatomy.state.sever_part(&"stilt_1")
	_combat(b).anatomy.state.sever_part(&"stilt_2")
	dir.update_music(0.1)
	assert_eq(am.music_state, &"boss_2")
	_combat(p).pools.damage_hp(9999.0, "test")
	dir.update_music(0.1)
	assert_eq(am.music_state, &"death")

func test_volume_settings_round_trip() -> void:
	am.settings_path = SETTINGS
	am.set_volume(&"Music", 0.25)
	am.set_volume(&"SFX", 0.0)
	assert_eq(am.save_settings(), OK)
	am.set_volume(&"Music", 1.0)
	am.set_volume(&"SFX", 1.0)
	am.load_settings()
	assert_near(am.get_volume(&"Music"), 0.25, 0.01)
	assert_eq(am.get_volume(&"SFX"), 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "zero mutes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	am.settings_path = am.SETTINGS_PATH
	for b in am.DEFAULT_VOLUMES:
		am.set_volume(b, am.DEFAULT_VOLUMES[b])

func test_main_menu_has_audio_settings() -> void:
	var m := MainMenu.new()
	tree.root.add_child(m)
	dir.update_music(0.0)
	assert_eq(am.music_state, &"menu")
	m.open_audio_settings()
	assert_true(m.audio_panel.visible)
	var s: HSlider = m.audio_panel.sliders[&"Music"]
	s.value = 0.5
	assert_near(am.get_volume(&"Music"), 0.5, 0.01)
	am.set_volume(&"Music", am.DEFAULT_VOLUMES[&"Music"])
