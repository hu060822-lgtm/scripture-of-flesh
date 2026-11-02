extends TestCase
## 聲音 A2：程序合成的音效檔（tools/audio_synth/generate_sfx.py 產生）。
## 檢查每個 cue 都有音檔、格式符合 PS1 低保真規格、長度合理，而且來源都記錄在 SOURCES.md。

## 各 cue 允許的最長秒數（含殘響）。短促的打擊聲不該拖太長，否則連打時會糊成一片。
const MAX_LEN := {
	&"footstep": 0.6, &"ui_hover": 0.2, &"miss": 0.5, &"attack_swing": 0.5,
	&"hit_cut": 0.6, &"hit_blunt": 0.6, &"hit_pierce": 0.6, &"bone_snap": 0.6,
}
const DEFAULT_MAX_LEN := 6.0

func test_every_cue_has_audio_variants() -> void:
	var cues := SoundCatalog.build()
	for id in cues:
		var c: SoundCue = cues[id]
		assert_false(c.is_placeholder(), "%s has no audio files" % id)
		assert_true(c.streams.size() >= 1, "%s variants" % id)
		if id not in [&"altar_rest", &"gate_open", &"boss_kneel", &"boss_defeated"]:
			assert_true(c.streams.size() >= 2, "%s should have 2+ variants" % id)

func test_files_are_lofi_mono_wav_with_sane_length() -> void:
	var cues := SoundCatalog.build()
	for id in cues:
		for s in (cues[id] as SoundCue).streams:
			assert_true(s is AudioStreamWAV, "%s is WAV" % id)
			var w := s as AudioStreamWAV
			assert_eq(w.mix_rate, 22050, "%s mix rate" % id)
			assert_false(w.stereo, "%s mono" % id)
			assert_eq(w.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s one-shot" % id)
			var length := w.get_length()
			assert_true(length > 0.02, "%s too short (%.3f s)" % [id, length])
			assert_true(length <= MAX_LEN.get(id, DEFAULT_MAX_LEN), "%s too long (%.2f s)" % [id, length])

func test_sources_document_every_cue() -> void:
	var src := FileAccess.get_file_as_string("res://audio/SOURCES.md")
	for id in SoundCatalog.TABLE:
		assert_true(src.find("`%s`" % id) != -1, "SOURCES.md lists %s" % id)
	assert_true(src.find("tools/audio_synth/generate_sfx.py") != -1, "SOURCES.md names the generator")
