class_name EquipmentComponent
extends Node
## 武器持握。依 D4 決策，手部屬於手臂：武器掛在手臂部位上。
## 手臂斷離時武器掉落成場景中的物件。（武器資料 WeaponDefinition 於 M3 加入。）

signal weapon_dropped(part_id: StringName, weapon: Node3D)

## 由 DismembermentController 或建構者設定：part_id -> 掛點 Node3D
var anchors := {}
var held := {}  # part_id -> Node3D

func equip(part_id: StringName, weapon: Node3D) -> bool:
	var anchor: Node3D = anchors.get(part_id)
	if anchor == null or held.has(part_id):
		return false
	if weapon.get_parent() != null:
		weapon.get_parent().remove_child(weapon)
	anchor.add_child(weapon)
	held[part_id] = weapon
	return true

func weapon_in(part_id: StringName) -> Node3D:
	return held.get(part_id)

## 部位斷離時呼叫。回傳掉落的武器（沒有則為 null）。
func drop_from(part_id: StringName, world_parent: Node) -> Node3D:
	var weapon: Node3D = held.get(part_id)
	if weapon == null:
		return null
	held.erase(part_id)
	var xf := weapon.global_transform
	var body := RigidBody3D.new()
	body.name = "Dropped_%s" % weapon.name
	body.set_meta(&"pickup", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.08, 0.8)
	shape.shape = box
	body.add_child(shape)
	world_parent.add_child(body)
	body.global_transform = xf
	weapon.get_parent().remove_child(weapon)
	body.add_child(weapon)
	weapon.transform = Transform3D.IDENTITY
	weapon_dropped.emit(part_id, weapon)
	return weapon
