class_name SoundCatalog
extends RefCounted
## 所有音效 cue 的定義表。新增或替換音檔不用改程式：把檔案放進 res://audio/sfx/<cue_id>/ 即可。
## 每個 cue 的來源與授權記錄在 res://audio/SOURCES.md。

const SFX_DIR := "res://audio/sfx"
const EXTENSIONS := ["wav", "ogg", "mp3"]

## id: [bus, volume_db, pitch_min, pitch_max, max_voices, cooldown, positional]
## 【暫代】數值皆為初值，有音檔後依實際聽感調整。
const TABLE := {
	# ---- 戰鬥 ----
	&"attack_swing":      [&"SFX", -6.0, 0.90, 1.10, 6, 0.02, true],
	&"hit_cut":           [&"SFX", -2.0, 0.92, 1.08, 6, 0.03, true],
	&"hit_blunt":         [&"SFX", -2.0, 0.90, 1.05, 6, 0.03, true],
	&"hit_pierce":        [&"SFX", -3.0, 0.95, 1.10, 6, 0.03, true],
	&"hit_burn":          [&"SFX", -4.0, 0.95, 1.05, 4, 0.05, true],
	&"hit_armor":         [&"SFX", -4.0, 0.90, 1.10, 4, 0.03, true],
	&"block":             [&"SFX", -3.0, 0.92, 1.08, 4, 0.03, true],
	&"guard_break":       [&"SFX", 0.0, 0.95, 1.00, 2, 0.10, true],
	&"dodge":             [&"SFX", -8.0, 0.90, 1.10, 4, 0.05, true],
	&"stagger":           [&"SFX", -6.0, 0.90, 1.05, 4, 0.10, true],
	&"miss":              [&"SFX", -10.0, 0.90, 1.10, 4, 0.05, true],
	# ---- 解剖 ----
	&"sever":             [&"SFX", 0.0, 0.92, 1.04, 4, 0.05, true],
	&"bone_snap":         [&"SFX", -2.0, 0.90, 1.10, 4, 0.05, true],
	&"part_disabled":     [&"SFX", -4.0, 0.90, 1.05, 4, 0.08, true],
	&"vital_fail":        [&"SFX", -2.0, 0.95, 1.00, 2, 0.20, true],
	&"death_enemy":       [&"SFX", -2.0, 0.90, 1.05, 3, 0.10, true],
	&"death_player":      [&"SFX", 0.0, 1.00, 1.00, 1, 1.00, false],
	&"footstep":          [&"SFX", -14.0, 0.85, 1.15, 8, 0.08, true],
	# ---- 身體成長 ----
	&"suture_start":      [&"SFX", -6.0, 0.95, 1.05, 2, 0.20, true],
	&"suture_break":      [&"SFX", -4.0, 0.95, 1.05, 2, 0.20, true],
	&"stitch_done":       [&"SFX", -4.0, 0.95, 1.05, 2, 0.20, true],
	&"transplant":        [&"SFX", -2.0, 0.95, 1.00, 2, 0.20, false],
	&"transplant_reject": [&"SFX", -2.0, 0.90, 0.95, 2, 0.20, false],
	&"altar_rest":        [&"SFX", -4.0, 1.00, 1.00, 1, 0.50, false],
	&"pickup":            [&"SFX", -6.0, 0.97, 1.03, 2, 0.10, false],
	&"gate_open":         [&"SFX", -2.0, 1.00, 1.00, 1, 1.00, true],
	# ---- Boss：行走的母親 ----
	&"boss_birth_cry":    [&"Voice", 0.0, 0.98, 1.02, 1, 1.00, false],
	&"boss_kneel":        [&"SFX", 0.0, 1.00, 1.00, 1, 1.00, true],
	&"boss_summon":       [&"Voice", -3.0, 0.95, 1.05, 2, 0.50, true],
	&"cord_snap":         [&"SFX", -2.0, 0.95, 1.05, 3, 0.10, true],
	&"boss_defeated":     [&"Voice", 0.0, 1.00, 1.00, 1, 2.00, false],
	# ---- UI ----
	&"ui_hover":          [&"UI", -14.0, 0.97, 1.03, 2, 0.05, false],
	&"ui_confirm":        [&"UI", -8.0, 1.00, 1.00, 2, 0.05, false],
	&"ui_open":           [&"UI", -10.0, 1.00, 1.00, 1, 0.10, false],
	&"ui_close":          [&"UI", -10.0, 1.00, 1.00, 1, 0.10, false],
}

## 建立全部 cue，並載入各自資料夾裡的音檔。
static func build(sfx_dir: String = SFX_DIR) -> Dictionary:
	var cues := {}
	for id in TABLE:
		var row: Array = TABLE[id]
		var c := SoundCue.new(id, row[0])
		c.volume_db = row[1]
		c.pitch_min = row[2]
		c.pitch_max = row[3]
		c.max_voices = row[4]
		c.cooldown = row[5]
		c.positional = row[6]
		c.streams = load_streams(sfx_dir.path_join(String(id)))
		cues[id] = c
	return cues

## 讀取資料夾裡所有音檔。匯出後的遊戲裡原始檔會變成 .import／.remap，這裡一併處理。
static func load_streams(dir_path: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var names := {}
	for f in DirAccess.get_files_at(dir_path):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.get_extension().to_lower() in EXTENSIONS:
			names[n] = true
	var sorted := names.keys()
	sorted.sort()
	for n in sorted:
		var s := load(dir_path.path_join(n)) as AudioStream
		if s != null:
			out.append(s)
	return out
