class_name RetroAnimator
extends Node
## 【美術測試】有限幀數的程序動畫：以 12 fps 更新骨骼姿勢（走路擺動四肢、待機呼吸），
## 保留 PS1 時代低幀動畫的頓挫感。正式動畫完成後由 AnimationTree 取代。
## 只轉動骨骼旋轉（繞關節），斷肢後骨骼縮放為零的狀態不受影響。

@export var fps: float = 12.0
@export var swing_degrees: float = 28.0
@export var stride_speed: float = 7.0

var skeleton: Skeleton3D
var body: CharacterBody3D
var _acc := 0.0
var _phase := 0.0
## bone index -> [rest Transform3D, 關節偏移（骨骼原點到關節）, 擺動方向 1/-1, 種類]
var _bones := {}

func _ready() -> void:
	body = get_parent() as CharacterBody3D
	skeleton = body.find_child("Skeleton", true, false) as Skeleton3D
	var anatomy: AnatomyComponent = body.get_node("AnatomyComponent")
	for d in anatomy.profile.parts:
		var idx := skeleton.find_bone(String(d.bone_name))
		if idx < 0:
			continue
		var s := String(d.id)
		var lay := PlaceholderBodyBuilder._layout_for(d, anatomy.profile)
		var half := float(lay.get("h", 0.2)) * 0.5
		var kind := ""
		var sign := 1.0
		if d.functions.has("leg") or s.begins_with("stilt"):
			kind = "leg"
			sign = 1.0 if s.ends_with("l") or s.ends_with("1") or s.ends_with("3") else -1.0
		elif d.functions.has("arm"):
			kind = "arm"
			sign = -1.0 if s.contains("_l") else 1.0
		elif s == "chest" or s == "torso":
			kind = "chest"
		if kind != "":
			_bones[idx] = [skeleton.get_bone_rest(idx), Vector3(0, half, 0), sign, kind]

func _process(delta: float) -> void:
	_acc += delta
	var step := 1.0 / fps
	if _acc < step:
		return
	var dt := _acc
	_acc = 0.0
	var v := body.velocity
	v.y = 0
	var speed := v.length()
	_phase += dt * (stride_speed * clampf(speed / 3.0, 0.0, 1.5) + 1.2)
	for idx in _bones:
		var info: Array = _bones[idx]
		var rest: Transform3D = info[0]
		var joint: Vector3 = info[1]
		var amount := 0.0
		match info[3]:
			"leg":
				amount = sin(_phase) * deg_to_rad(swing_degrees) * clampf(speed / 2.0, 0.0, 1.0) * info[2]
			"arm":
				amount = sin(_phase) * deg_to_rad(swing_degrees * 0.7) * clampf(speed / 2.0, 0.0, 1.0) * info[2] \
					+ sin(_phase * 0.5) * deg_to_rad(3.0)
			"chest":
				skeleton.set_bone_pose_position(idx, rest.origin + Vector3(0, sin(_phase * 0.8) * 0.01, 0))
				continue
		var r := Quaternion(Vector3.RIGHT, amount)
		skeleton.set_bone_pose_rotation(idx, rest.basis.get_rotation_quaternion() * r)
		skeleton.set_bone_pose_position(idx, rest.origin + joint - (r * joint))
