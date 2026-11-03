class_name MusicMixer
extends Node
## 分層音樂：所有 stem（res://audio/music/stems/*.ogg）同長、同速度，同時開始播放並循環，
## 依音樂狀態淡入淡出各層的音量。stem 由 tools/music_synth/generate_music.py 程序合成。
## 沒有 stem 檔案時（例如尚未匯入）整個混音器是靜音，不會出錯。

const STEM_DIR := "res://audio/music/stems"
const STINGER_DIR := "res://audio/music/stingers"
## 狀態 → {stem: 線性音量}。沒列出的 stem 淡出到 0。
## 【暫代】數值皆為初值，需實際聽過後調整。
const MIXES := {
	&"silence": {},
	&"menu": {&"lullaby": 0.8, &"pad": 0.35},
	# 探索：美麗但走音的搖籃曲，底下隱約的低鳴
	&"explore": {&"lullaby": 0.55, &"pad": 0.3, &"drone": 0.12},
	# 緊張：搖籃曲退到遠處，低鳴與倒放人聲浮上來
	&"tension": {&"lullaby": 0.15, &"pad": 0.1, &"drone": 0.6, &"breath": 0.6},
	# 戰鬥：搖籃曲消失，只剩心跳、悶擊與低鳴
	&"combat": {&"drone": 0.7, &"heartbeat": 0.9, &"perc": 0.75, &"breath": 0.2},
	# 追逐（母親破牆）：搖籃曲被加速、變調、走音，底下是急促的悶擊與心跳
	&"chase": {&"chase_lullaby": 0.75, &"chase_pulse": 0.7, &"drone": 0.45, &"heartbeat": 0.5},
	# 她越來越近：搖籃曲退後，悶擊、心跳與崩壞的哼唱湧上來
	&"chase_near": {&"chase_lullaby": 0.35, &"chase_pulse": 1.0, &"heartbeat": 1.0, &"drone": 0.7, &"hum_broken": 0.35},
	# 她就在背後：音樂全斷，只剩她的呼吸與哼唱（3D 定位，由 MotherChase 播放）
	&"chase_hush": {},
	# Boss 第一階段：母親哼唱同一首搖籃曲
	&"boss_1": {&"hum": 0.8, &"drone": 0.45, &"boss_low": 0.6, &"heartbeat": 0.5, &"perc": 0.55},
	# 第二階段（跪伏）：哼唱崩壞
	&"boss_2": {&"hum_broken": 0.9, &"boss_low": 0.9, &"heartbeat": 0.9, &"perc": 0.8, &"breath": 0.4},
	# 死亡：音樂全部抽走，只留一聲低鳴（stinger）
	&"death": {},
	&"ending_burn": {&"lullaby": 0.5},
	&"ending_mother": {&"hum": 0.7, &"pad": 0.3},
	# 離院：同一首搖籃曲的大調、無顫音版本
	&"ending_escape": {&"lullaby_major": 0.7, &"pad": 0.3},
}
## 進入狀態時播放的一次性音效。
const STINGERS := {&"death": &"death"}
## 淡入淡出秒數（進入戰鬥較快）。
const FADE := 2.5
const FADE_FAST := 0.8
const FAST_STATES := [&"combat", &"boss_1", &"boss_2", &"death", &"chase", &"chase_near", &"chase_hush"]

var players := {}  # stem -> AudioStreamPlayer
var levels := {}   # stem -> 目前線性音量
var targets := {}  # stem -> 目標線性音量
var rates := {}    # stem -> 每秒變化量（讓每一層都在 fade_time 內到達目標）
var stingers := {}  # id -> AudioStream
var state: StringName = &"silence"
var stinger_player: AudioStreamPlayer
var fade_time := FADE
var running := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in _load_dir(STEM_DIR):
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.stream = _looping(s.stream)
		p.volume_db = -80.0
		add_child(p)
		players[s.name] = p
		levels[s.name] = 0.0
		targets[s.name] = 0.0
	for s in _load_dir(STINGER_DIR):
		stingers[s.name] = s.stream
	stinger_player = AudioStreamPlayer.new()
	stinger_player.bus = &"Music"
	add_child(stinger_player)

func has_stems() -> bool:
	return not players.is_empty()

func apply_state(new_state: StringName) -> void:
	if not MIXES.has(new_state):
		push_warning("MusicMixer: 沒有混音設定的狀態 %s，視為靜音" % new_state)
	var old := state
	state = new_state
	var mix: Dictionary = MIXES.get(new_state, {})
	fade_time = FADE_FAST if new_state in FAST_STATES else FADE
	for stem in players:
		targets[stem] = float(mix.get(stem, 0.0))
		rates[stem] = absf(targets[stem] - levels[stem]) / maxf(0.01, fade_time)
	if not mix.is_empty() and not running:
		_start_all()
	if STINGERS.has(new_state) and old != new_state:
		var st: AudioStream = stingers.get(STINGERS[new_state])
		if st != null:
			stinger_player.stream = st
			stinger_player.play()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not running:
		return
	var any := false
	for stem in players:
		var cur: float = levels[stem]
		cur = move_toward(cur, targets[stem], float(rates.get(stem, 1.0)) * delta)
		levels[stem] = cur
		(players[stem] as AudioStreamPlayer).volume_db = linear_to_db(cur) if cur > 0.0005 else -80.0
		any = any or cur > 0.0 or targets[stem] > 0.0
	if not any:
		_stop_all()

## 所有 stem 從頭同時開始，保持同步。
func _start_all() -> void:
	for stem in players:
		(players[stem] as AudioStreamPlayer).play(0.0)
	running = true

func _stop_all() -> void:
	for stem in players:
		(players[stem] as AudioStreamPlayer).stop()
	running = false

static func _looping(s: AudioStream) -> AudioStream:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s

## 回傳 [{name, stream}]，依檔名排序。
static func _load_dir(dir_path: String) -> Array:
	var out := []
	for s in SoundCatalog.load_streams(dir_path):
		out.append({"name": StringName(s.resource_path.get_file().get_basename()), "stream": s})
	return out
