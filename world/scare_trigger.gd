class_name ScareTrigger
extends AreaTrigger
## 一次性驚嚇（序章恐怖橋段 C1）。玩家走進半徑時觸發一次，記錄在 GameState.taken（讀檔後不再重演）。
## 設計原則：同一條路線上大約每 5 分鐘最多一次；只嚇人，不造成傷害。
##
## kind：
##   girl_glimpse   遠處出現小女孩的剪影，玩家靠近到 4m 或 3.5 秒後消失，伴隨哼聲
##   blackout       附近的燈熄滅 1.6 秒，再亮起時高大的人影就站在 target，0.4 秒後消失
##   hanging_turn   target 的吊屍（ScareFigure）慢慢轉過來面向玩家，之後一直盯著
##   footsteps      小孩的腳步聲從 target 往玩家走來，在 2m 外停下
##   body_drop      一具屍體從天花板掉在 target，悶響
##   distant_cry    遠處（target）傳來嬰兒的哭聲

const CHILD_HUM := "res://audio/music/stingers/child_hum.ogg"

@export_enum("girl_glimpse", "blackout", "hanging_turn", "footsteps", "body_drop", "distant_cry") var kind: String = "girl_glimpse"
## 事件發生的位置（相對於觸發點）。
@export var target_offset: Vector3 = Vector3(0, 0, -6)
## 觸發後經過的秒數（測試用）。
var elapsed := -1.0
var figure: ScareFigure
var _player: Node3D
var _lights: Array = []
var _steps_left := 0
var _step_timer := 0.0

func _ready() -> void:
	super._ready()
	if kind == "hanging_turn":
		figure = _make_figure("hanging", target_offset)
		figure.visible = true
	elif kind in ["girl_glimpse", "blackout", "body_drop"]:
		figure = _make_figure({"girl_glimpse": "girl", "blackout": "tall", "body_drop": "corpse"}[kind], target_offset)
		figure.visible = done() and kind == "body_drop"

func _make_figure(k: String, offset: Vector3) -> ScareFigure:
	var f := ScareFigure.new()
	f.name = "Figure"
	f.kind = k
	f.position = offset
	add_child(f)
	return f

func target() -> Vector3:
	return global_position + global_transform.basis * target_offset

func fire(player: Node3D) -> void:
	super.fire(player)
	_player = player
	elapsed = 0.0
	match kind:
		"girl_glimpse":
			figure.visible = true
			_play_stream(CHILD_HUM, target())
		"blackout":
			for l in _nearby_lights(14.0):
				_lights.append([l, l.light_energy])
				l.light_energy = 0.0
			_cue(&"bone_snap", target())
		"hanging_turn":
			figure.player = player
			figure.face_player = true
			_cue(&"suture_break", target())
		"footsteps":
			_steps_left = 7
			_step_timer = 0.0
		"body_drop":
			figure.visible = true
			figure.position = target_offset + Vector3(0, 3.0, 0)
			var tw := create_tween()
			tw.tween_property(figure, "position", target_offset, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(func(): _cue(&"hit_blunt", target()))
		"distant_cry":
			_cue(&"boss_birth_cry", target())

func _process(delta: float) -> void:
	if elapsed < 0.0:
		return
	elapsed += delta
	match kind:
		"girl_glimpse":
			if figure.visible and (elapsed > 3.5 or _dist_to_player(target()) < 4.0):
				figure.vanish()
				elapsed = -1.0
		"blackout":
			if elapsed > 1.6 and not _lights.is_empty():
				for pair in _lights:
					if is_instance_valid(pair[0]):
						pair[0].light_energy = pair[1]
				_lights.clear()
				figure.visible = true
			elif elapsed > 2.0 and figure.visible:
				figure.vanish()
				elapsed = -1.0
		"footsteps":
			_step_timer -= delta
			if _steps_left > 0 and _step_timer <= 0.0:
				var t := 1.0 - float(_steps_left) / 7.0
				var from := target()
				var to := _player.global_position if is_instance_valid(_player) else from
				var p := from.lerp(to, t * 0.8)
				if _dist_to_player(p) > 2.0:
					_cue(&"footstep", p)
				_steps_left -= 1
				_step_timer = 0.42
			elif _steps_left <= 0:
				elapsed = -1.0

func _dist_to_player(p: Vector3) -> float:
	return _player.global_position.distance_to(p) if is_instance_valid(_player) else INF

func _nearby_lights(r: float) -> Array:
	var out := []
	for l in get_tree().root.find_children("*", "OmniLight3D", true, false):
		if (l as Node3D).global_position.distance_to(global_position) <= r:
			out.append(l)
	return out

func _cue(id: StringName, at: Vector3) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play(id, at)

func _play_stream(path: String, at: Vector3) -> void:
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.bus = &"Voice"
	p.unit_size = 4.0
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)
