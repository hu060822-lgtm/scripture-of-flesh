class_name CameraShake
extends Node
## 鏡頭震動（打擊回饋）。掛在 Camera3D 底下，只改 h_offset／v_offset：
## 鏡頭腳本（CameraRig、FixedCamera）每格重設的是位置與朝向，兩者互不干擾。
## 以 trauma（0..1）表示強度，震幅與 trauma² 成正比，以真實時間衰減（頓幀與戰術減速時照樣震）。
## 用法：CameraShake.shake(get_viewport().get_camera_3d(), 0.4)

## trauma = 1 時的最大偏移（公尺）。固定斜俯視鏡頭距離 7–9 公尺，約等於畫面的 1–2%。
const MAX_OFFSET := 0.14
## 每秒衰減的 trauma。
const DECAY := 2.6
## 震動頻率（每秒換方向的次數）。低頻一點比較像 PS1 的「頓挫」而不是電子抖動。
const FREQUENCY := 28.0

var camera: Camera3D
var trauma := 0.0
var _t := 0.0
var _seed := 0.0

## 對鏡頭加入震動。amount 0..1，可疊加（上限 1）。回傳掛上的 CameraShake（沒有鏡頭時為 null）。
static func shake(cam: Camera3D, amount: float) -> CameraShake:
	if cam == null or not is_instance_valid(cam) or amount <= 0.0:
		return null
	var s := cam.get_node_or_null("CameraShake") as CameraShake
	if s == null:
		s = CameraShake.new()
		s.name = "CameraShake"
		cam.add_child(s)
	s.add_trauma(amount)
	return s

func _ready() -> void:
	camera = get_parent() as Camera3D
	_seed = randf() * 100.0

func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)

func offset() -> Vector2:
	var k := trauma * trauma * MAX_OFFSET
	var ph := floorf(_t * FREQUENCY)  # 逐格跳動，不平滑內插
	return Vector2(sin(ph * 12.9898 + _seed), cos(ph * 78.233 + _seed * 0.5)) * k

func _process(delta: float) -> void:
	advance(delta)

func advance(dt: float) -> void:
	if camera == null:
		return
	_t += dt
	trauma = maxf(0.0, trauma - DECAY * dt)
	var o := offset()
	camera.h_offset = o.x
	camera.v_offset = o.y
