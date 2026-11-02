class_name AmbiencePlayer
extends Node
## 房間環境音：兩個播放器交叉淡變。檔案在 res://audio/music/ambience/<id>.ogg（程序合成，30 秒循環）。

const DIR := "res://audio/music/ambience"
const FADE := 3.0

var streams := {}  # id -> AudioStream
var current: StringName = &""
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in MusicMixer._load_dir(DIR):
		streams[s.name] = MusicMixer._looping(s.stream)
	_a = _make()
	_b = _make()
	_active = _a

func _make() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Ambience"
	p.volume_db = -80.0
	add_child(p)
	return p

## id 為 &"" 時淡出到無聲。
func set_ambience(id: StringName) -> void:
	if id == current:
		return
	current = id
	var next := _b if _active == _a else _a
	var st: AudioStream = streams.get(id)
	if st != null:
		next.stream = st
		next.volume_db = -80.0
		next.play()
	_active = next

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	var step := delta / FADE
	for p in [_a, _b]:
		var cur := db_to_linear(p.volume_db) if p.volume_db > -79.0 else 0.0
		var target := 1.0 if (p == _active and current != &"" and p.playing) else 0.0
		cur = move_toward(cur, target, step)
		p.volume_db = linear_to_db(cur) if cur > 0.0005 else -80.0
		if cur <= 0.0 and target == 0.0 and p.playing:
			p.stop()

func level_of_active() -> float:
	return db_to_linear(_active.volume_db) if _active.volume_db > -79.0 else 0.0
