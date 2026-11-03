class_name ThrownLimb
extends RigidBody3D
## 丟出去的殘肢（序章提案 A）：落地時發出聲響（AI-1 噪音事件），附近沒在追你的敵人會過去查看。
## 落地後變回可以撿起的殘肢。

const NOISE_RADIUS := 9.0
const THROW_SPEED := 7.0
## 最晚這麼多秒後一定會發出聲響（沒有碰到東西時）。
const MAX_FLIGHT := 1.2

signal landed(position: Vector3)

var item_id := ""
var _flight := 0.0
var _landed := false

static func throw_from(player: Node3D, id: String, direction: Vector3) -> ThrownLimb:
	var t := ThrownLimb.new()
	t.name = "Thrown_%s" % id
	t.item_id = id
	t.mass = 1.5
	t.contact_monitor = true
	t.max_contacts_reported = 2
	# 只和場景碰撞：不會擋住玩家或敵人
	t.collision_layer = 0
	t.collision_mask = PlaceholderBodyBuilder.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.18, 0.18, 0.5)
	shape.shape = box
	t.add_child(shape)
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.08
	cap.height = 0.5
	mi.mesh = cap
	mi.rotation_degrees.x = 90
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8a6a5a")
	mi.material_override = mat
	t.add_child(mi)
	var dir := direction
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else -player.global_transform.basis.z
	player.get_parent().add_child(t)
	t.global_position = player.global_position + Vector3.UP * 1.3 + dir * 0.6
	t.linear_velocity = dir * THROW_SPEED + Vector3.UP * 3.0
	return t

func _ready() -> void:
	body_entered.connect(func(_b): _land())

func _physics_process(delta: float) -> void:
	_flight += delta
	if not _landed and _flight >= MAX_FLIGHT:
		_land()

func _land() -> void:
	if _landed:
		return
	_landed = true
	EventBus.emit_noise(global_position, NOISE_RADIUS, null, &"thrown")
	LimbRelic.attach(self, item_id)
	landed.emit(global_position)
