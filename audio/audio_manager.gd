extends Node
## 聲音總管（autoload: AudioManager）。
## - 建立匯流排：Master ← Music／Ambience／SFX／UI／Voice。
## - play(cue_id, at) 播放音效：隨機變體與音高、冷卻、同 cue 發聲上限、3D 定位。
## - 音樂狀態（探索／緊張／戰鬥／Boss…）由 AudioDirector 決定，這裡記錄並發出訊號；
##   實際的分層音樂在 A3 加入。
## - 音量設定存在 user://settings.cfg 的 [audio] 區段。
## 沒有音檔的 cue 是【暫代】靜音：照常記錄在 history，不發聲。

signal cue_played(cue_id: StringName, silent: bool)
signal music_state_changed(old_state: StringName, new_state: StringName)

const BUSES := [&"Music", &"Ambience", &"SFX", &"UI", &"Voice"]
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUMES := {
	&"Master": 0.8, &"Music": 0.7, &"Ambience": 0.8, &"SFX": 0.9, &"UI": 0.6, &"Voice": 0.9,
}
const POOL_2D := 16
const POOL_3D := 24
const HISTORY_SIZE := 64

var cues: Dictionary = {}
## 最近播放的 cue（新的在後）：{id, silent, time}。給測試與除錯用。
var history: Array[Dictionary] = []
var music_state: StringName = &"silence"
var settings_path := SETTINGS_PATH
var rng := RandomNumberGenerator.new()
var director: AudioDirector

var _now := 0.0
var _last_time := {}     # cue id -> 上次播放時間
var _last_variant := {}  # cue id -> 上次的變體索引
var _voices := {}        # cue id -> Array[Node]（播放中的 player）
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	cues = SoundCatalog.build()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 4.0
		add_child(p)
		_pool_3d.append(p)
	load_settings()
	director = AudioDirector.new()
	director.manager = self
	add_child(director)

func _process(delta: float) -> void:
	_now += delta

## 建立匯流排（已存在就跳過），全部送往 Master。SFX／Ambience 的低通濾波預設關閉（A4 低血量悶聲用）。
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, &"Master")
			if b == &"SFX" or b == &"Ambience":
				var lp := AudioEffectLowPassFilter.new()
				lp.cutoff_hz = 900.0
				AudioServer.add_bus_effect(i, lp)
				AudioServer.set_bus_effect_enabled(i, 0, false)
	var m := AudioServer.get_bus_index(&"Master")
	if AudioServer.get_bus_effect_count(m) == 0:
		AudioServer.add_bus_effect(m, AudioEffectLimiter.new())

# ---------- 音效 ----------

## 播放一個 cue。at：Node3D 或 Vector3 代表 3D 位置；null 代表不定位。
## 回傳播放的 player；被冷卻擋下、未知 cue、或靜音暫代時回傳 null。
func play(cue_id: StringName, at: Variant = null) -> Node:
	var cue: SoundCue = cues.get(cue_id)
	if cue == null:
		push_warning("未知的音效 cue：%s" % cue_id)
		return null
	if _now - float(_last_time.get(cue_id, -INF)) < cue.cooldown:
		return null
	_last_time[cue_id] = _now
	_record(cue_id, cue.is_placeholder())
	if cue.is_placeholder():
		return null
	var idx := cue.pick(rng, int(_last_variant.get(cue_id, -1)))
	_last_variant[cue_id] = idx
	var pos: Variant = null
	if cue.positional:
		if at is Node3D and (at as Node3D).is_inside_tree():
			pos = (at as Node3D).global_position
		elif at is Vector3:
			pos = at
	var p: Node = _take_player(pos != null)
	_limit_voices(cue)
	if pos != null:
		var p3 := p as AudioStreamPlayer3D
		p3.global_position = pos
		p3.max_distance = cue.max_distance
		p3.volume_db = cue.volume_db
		p3.pitch_scale = rng.randf_range(cue.pitch_min, cue.pitch_max)
	else:
		p.set(&"volume_db", cue.volume_db)
		p.set(&"pitch_scale", rng.randf_range(cue.pitch_min, cue.pitch_max))
	p.set(&"stream", cue.streams[idx])
	p.set(&"bus", cue.bus)
	p.call(&"play")
	if not _voices.has(cue_id):
		_voices[cue_id] = []
	(_voices[cue_id] as Array).append(p)
	return p

func last_played(n: int = 1) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in range(maxi(0, history.size() - n), history.size()):
		out.append(history[i].id)
	return out

func played_ids() -> Array[StringName]:
	return last_played(history.size())

func clear_history() -> void:
	history.clear()
	_last_time.clear()

## 測試用：推進內部時鐘（冷卻）。
func advance(delta: float) -> void:
	_now += delta

func _record(cue_id: StringName, silent: bool) -> void:
	history.append({"id": cue_id, "silent": silent, "time": _now})
	if history.size() > HISTORY_SIZE:
		history.pop_front()
	cue_played.emit(cue_id, silent)

func _take_player(positional: bool) -> Node:
	var pool: Array = _pool_3d if positional else _pool_2d
	for p in pool:
		if not p.playing:
			return p
	# 全部都在播：搶最舊的（池子的第一個），並移到最後。
	var oldest: Node = pool.pop_front()
	pool.append(oldest)
	oldest.call(&"stop")
	return oldest

func _limit_voices(cue: SoundCue) -> void:
	var list: Array = _voices.get(cue.id, [])
	list = list.filter(func(p): return p.playing and p.stream in cue.streams)
	while list.size() >= cue.max_voices:
		(list.pop_front() as Node).call(&"stop")
	_voices[cue.id] = list

# ---------- 音樂狀態 ----------

func set_music_state(state: StringName) -> void:
	if state == music_state:
		return
	var old := music_state
	music_state = state
	music_state_changed.emit(old, state)

# ---------- 音量設定 ----------

func set_volume(bus: StringName, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(linear) if linear > 0.0 else -80.0)
	AudioServer.set_bus_mute(i, linear <= 0.0)

func get_volume(bus: StringName) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i == -1 or AudioServer.is_bus_mute(i):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(i)), 0.0, 1.0)

func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # 保留檔案裡其他區段
	for b in DEFAULT_VOLUMES:
		cfg.set_value("audio", String(b), get_volume(b))
	return cfg.save(settings_path)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(settings_path) == OK
	for b in DEFAULT_VOLUMES:
		var v: float = DEFAULT_VOLUMES[b]
		if ok:
			v = float(cfg.get_value("audio", String(b), v))
		set_volume(b, v)
