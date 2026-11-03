class_name CameraRig
extends Node3D
## 固定斜俯視鏡頭。跟隨目標，戰鬥中可拉近（M5 戰術介面使用）。

@export var target: Node3D
@export var pitch_degrees: float = -52.0
@export var yaw_degrees: float = 0.0
@export var distance: float = 9.0
@export var combat_distance: float = 7.0
@export var follow_speed: float = 6.0

var camera: Camera3D
var in_combat := false
## 鏡頭震動強度（0–1，每秒衰減 SHAKE_DECAY；位移量與平方成正比，小震很輕、大震很猛）。
var trauma := 0.0
## 跟隨點的偏移（追逐戰時往追兵那一側偏，讓玩家與背後的母親都在畫面裡）。
var bias := Vector3.ZERO
var _bias_now := Vector3.ZERO

const SHAKE_DECAY := 1.8
const SHAKE_MAX := 0.35

func add_shake(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	_apply(1.0)

func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - SHAKE_DECAY * delta)
	_bias_now = _bias_now.lerp(bias, clampf(3.0 * delta, 0.0, 1.0))
	_apply(clampf(follow_speed * delta, 0.0, 1.0))

func _apply(t: float) -> void:
	if target != null and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position + _bias_now, t)
	var d := combat_distance if in_combat else distance
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0))
	var jitter := Vector3.ZERO
	if trauma > 0.0:
		var k := trauma * trauma * SHAKE_MAX
		jitter = Vector3(randf_range(-k, k), randf_range(-k, k), randf_range(-k, k) * 0.5)
	camera.transform = Transform3D(basis, basis * Vector3(0, 0, d) + Vector3.UP * 1.0 + jitter)
