class_name Hurtbox
extends Area3D
## 單一部位的受擊區域。攻擊的 Hitbox（M3）偵測到它後，以 part_id 決定命中部位。

const LAYER := 1 << 2  # 物理層 3：hurtbox

@export var part_id: StringName
## 邏輯上是否可被命中。斷離時立即設為 false；物理屬性以 deferred 方式停用，
## 避免在物理查詢中修改狀態。
var active := true

func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false

func deactivate() -> void:
	active = false
	set_deferred("monitorable", false)
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)

func activate() -> void:
	active = true
	set_deferred("monitorable", true)
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", false)
