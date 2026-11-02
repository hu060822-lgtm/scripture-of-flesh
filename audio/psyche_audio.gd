class_name PsycheAudio
extends Node
## A4 心理效果（只作用在玩家身上）：
## - 低血量：SFX 與環境音逐漸變悶（低通），HP 30% 開始，5% 時最悶。
## - 自己的肢體被斷：耳鳴（Voice 匯流排，不會被悶住），世界額外變悶 3 秒。
## - 異化 ≥ 25：周圍出現聽不清楚的低語（一半倒放）；異化越高越頻繁、越大聲，位置在玩家身邊隨機方向。
## 音檔由 tools/music_synth/generate_music.py 產生：stingers/tinnitus.ogg、whispers/*.ogg。

const TINNITUS := "res://audio/music/stingers/tinnitus.ogg"
const WHISPER_DIR := "res://audio/music/whispers"
const MUFFLE_START_HP := 0.30
const MUFFLE_FULL_HP := 0.05
const SEVER_MUFFLE := 0.8
const SEVER_MUFFLE_SECONDS := 3.0
const WHISPER_MUTATION := 25.0
## 異化 25 → 100 時，低語間隔（秒）與音量（dB）。
const WHISPER_INTERVAL := Vector2(36.0, 8.0)
const WHISPER_DB := Vector2(-20.0, -6.0)
const WHISPER_DISTANCE := 2.5

var manager: Node
var rng := RandomNumberGenerator.new()
var tinnitus_player: AudioStreamPlayer
var whisper_player: AudioStreamPlayer3D
var whispers: Array[AudioStream] = []
var muffle := 0.0
var whisper_count := 0
var _sever_left := 0.0
var _whisper_left := -1.0

func _ready() -> void:
	tinnitus_player = AudioStreamPlayer.new()
	tinnitus_player.bus = &"Voice"
	tinnitus_player.volume_db = -6.0
	if ResourceLoader.exists(TINNITUS):
		tinnitus_player.stream = load(TINNITUS)
	add_child(tinnitus_player)
	whisper_player = AudioStreamPlayer3D.new()
	whisper_player.bus = &"Voice"
	whisper_player.unit_size = 3.0
	add_child(whisper_player)
	whispers = SoundCatalog.load_streams(WHISPER_DIR)

func reset() -> void:
	_sever_left = 0.0
	_whisper_left = -1.0
	_set_muffle(0.0)

## 玩家自己的部位被斷。
func on_player_severed() -> void:
	_sever_left = SEVER_MUFFLE_SECONDS
	if tinnitus_player.stream != null:
		tinnitus_player.play()

## hp_ratio：0–1；mutation：0–100；body：玩家（低語定位用，可為 null）。
func update(delta: float, hp_ratio: float, mutation: float, body: Node3D) -> void:
	_sever_left = maxf(0.0, _sever_left - delta)
	var m := low_hp_muffle(hp_ratio)
	if _sever_left > 0.0:
		m = maxf(m, SEVER_MUFFLE * _sever_left / SEVER_MUFFLE_SECONDS)
	_set_muffle(m)
	_update_whispers(delta, mutation, body)

static func low_hp_muffle(hp_ratio: float) -> float:
	return clampf((MUFFLE_START_HP - hp_ratio) / (MUFFLE_START_HP - MUFFLE_FULL_HP), 0.0, 1.0)

static func whisper_t(mutation: float) -> float:
	return clampf((mutation - WHISPER_MUTATION) / (100.0 - WHISPER_MUTATION), 0.0, 1.0)

static func whisper_interval(mutation: float) -> float:
	return lerpf(WHISPER_INTERVAL.x, WHISPER_INTERVAL.y, whisper_t(mutation))

func _update_whispers(delta: float, mutation: float, body: Node3D) -> void:
	if mutation < WHISPER_MUTATION:
		_whisper_left = -1.0
		return
	if _whisper_left < 0.0:
		_whisper_left = whisper_interval(mutation) * rng.randf_range(0.5, 1.0)
	_whisper_left -= delta
	if _whisper_left > 0.0:
		return
	_whisper_left = whisper_interval(mutation) * rng.randf_range(0.7, 1.3)
	whisper_count += 1
	if whispers.is_empty() or body == null or not body.is_inside_tree():
		return
	var ang := rng.randf_range(0.0, TAU)
	whisper_player.global_position = body.global_position + Vector3(cos(ang), 1.5, sin(ang)) * WHISPER_DISTANCE
	whisper_player.stream = whispers[rng.randi_range(0, whispers.size() - 1)]
	whisper_player.volume_db = lerpf(WHISPER_DB.x, WHISPER_DB.y, whisper_t(mutation))
	whisper_player.pitch_scale = rng.randf_range(0.85, 1.05)
	whisper_player.play()

## 0 = 不悶；1 = 最悶（低通 600 Hz）。作用在 SFX 與 Ambience 匯流排。
func _set_muffle(amount: float) -> void:
	muffle = amount
	for bus in [&"SFX", &"Ambience"]:
		var i := AudioServer.get_bus_index(bus)
		if i == -1 or AudioServer.get_bus_effect_count(i) == 0:
			continue
		var lp := AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter
		if lp == null:
			continue
		AudioServer.set_bus_effect_enabled(i, 0, amount > 0.001)
		lp.cutoff_hz = cutoff_for(amount)

static func cutoff_for(amount: float) -> float:
	return 6000.0 * pow(600.0 / 6000.0, clampf(amount, 0.0, 1.0))
