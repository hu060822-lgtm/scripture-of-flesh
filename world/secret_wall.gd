class_name SecretWall
extends StaticBody3D
## 隱藏通道（序章提案 A／G）：open_flag 成立時牆面消失、碰撞停用，露出後方的隱藏區域。
## 讀檔後若旗標已成立，一開始就是打開的。放在關卡的 Secrets 節點下（不參與導航網格烘焙）。

signal opened

@export var open_flag: StringName = &""
@export var size: Vector3 = Vector3(3.0, 3.0, 0.4)
@export var color: Color = Color("4a3a2c")

var is_open := false

func _ready() -> void:
	collision_layer = PlaceholderBodyBuilder.WORLD_LAYER
	if get_child_count() == 0:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = Vector3(0, size.y * 0.5, 0)
		add_child(shape)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = shape.position
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mi.material_override = mat
		add_child(mi)
	if open_flag != &"" and GameState.has_flag(open_flag):
		open()

func _physics_process(_delta: float) -> void:
	if not is_open and open_flag != &"" and GameState.has_flag(open_flag):
		open()

func open() -> void:
	if is_open:
		return
	is_open = true
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
		elif c is Node3D:
			c.visible = false
	opened.emit()
