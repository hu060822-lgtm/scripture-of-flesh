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

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	_apply(1.0)

func _process(delta: float) -> void:
	_apply(clampf(follow_speed * delta, 0.0, 1.0))

func _apply(t: float) -> void:
	if target != null and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, t)
	var d := combat_distance if in_combat else distance
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0))
	camera.transform = Transform3D(basis, basis * Vector3(0, 0, d) + Vector3.UP * 1.0)
