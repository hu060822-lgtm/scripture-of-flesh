class_name SeveredPart
extends RigidBody3D
## 斷離後掉落的殘肢。帶有原本的網格，受物理影響，數量有上限並會自動清除。

const GROUP := &"severed_parts"
## 場景中同時存在的殘肢上限，超過時清除最舊的。
const MAX_ACTIVE := 24
## 存活秒數（0 = 不自動清除）。
@export var lifetime: float = 60.0

var part_id: StringName
var source_creature_id: StringName
## 可以撿起來當道具的殘肢（LimbRelic）不會自動清除，也不計入數量上限。
var keep := false

func _ready() -> void:
	add_to_group(GROUP)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_expire)

func _expire() -> void:
	if not keep:
		queue_free()

## 生成殘肢。visual 會被重新設為此 RigidBody 的子節點，並保留世界座標。
static func spawn(parent: Node, visual: Node3D, at: Transform3D, id: StringName,
		creature_id: StringName, impulse: Vector3) -> SeveredPart:
	var gib := SeveredPart.new()
	gib.name = "Severed_%s" % id
	gib.part_id = id
	gib.source_creature_id = creature_id
	gib.mass = 2.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var aabb := _visual_aabb(visual)
	box.size = aabb.size.max(Vector3.ONE * 0.05)
	shape.shape = box
	shape.position = aabb.get_center()
	gib.add_child(shape)
	parent.add_child(gib)
	gib.global_transform = at
	if visual.get_parent() != null:
		visual.get_parent().remove_child(visual)
	gib.add_child(visual)
	visual.transform = Transform3D.IDENTITY
	gib.apply_central_impulse(impulse)
	_enforce_limit(parent.get_tree())
	return gib

static func _visual_aabb(n: Node3D) -> AABB:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).mesh.get_aabb()
	return AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))

static func _enforce_limit(tree: SceneTree) -> void:
	if tree == null:
		return
	var gibs := tree.get_nodes_in_group(GROUP).filter(func(g): return not (g is SeveredPart and g.keep))
	var excess := gibs.size() - MAX_ACTIVE
	for i in excess:
		gibs[i].queue_free()
