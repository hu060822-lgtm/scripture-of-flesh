class_name FixedCamera
extends Camera3D
## 固定鏡頭（日式復古恐怖的構圖）：位置固定，只在限定角度內轉向追蹤目標。
## 與 CameraRig 不同，鏡頭不會跟著玩家移動。

@export var target: Node3D
## 最大追蹤角度（度）；0 = 完全固定。
@export var max_track_degrees: float = 18.0
@export var track_speed: float = 3.0

var _base_basis: Basis

func _ready() -> void:
	_base_basis = global_transform.basis

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or max_track_degrees <= 0.0:
		return
	var to := (target.global_position + Vector3.UP * 0.9 - global_position).normalized()
	var fwd := -_base_basis.z
	var ang := fwd.angle_to(to)
	var limit := deg_to_rad(max_track_degrees)
	var dir := to if ang <= limit else fwd.slerp(to, limit / ang)
	var want := Basis.looking_at(dir, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(want, clampf(track_speed * delta, 0.0, 1.0)).orthonormalized()
