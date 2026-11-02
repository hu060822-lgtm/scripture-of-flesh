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

## 目前持有的武器資料（取第一把有 weapon_def 的武器）。
func held_weapon() -> WeaponDefinition:
	for pid in held:
		var def = held[pid].get_meta(&"weapon_def", null)
		if def is WeaponDefinition:
			return def
	return null

func weapon_part() -> StringName:
	for pid in held:
		if held[pid].get_meta(&"weapon_def", null) is WeaponDefinition:
			return pid
	return &""

## 找一隻可用且空著的手臂。
func free_arm(state: AnatomyState) -> StringName:
	for pid in anchors:
		var p := state.get_part(pid)
		if p != null and p.is_functional() and not held.has(pid):
			return pid
	return &""

## 以武器資料建立【暫代】外觀並裝備。
func equip_definition(def: WeaponDefinition, part_id: StringName) -> Node3D:
	var node := make_placeholder_visual(def)
	if not equip(part_id, node):
		node.free()
		return null
	return node

## 收起目前武器（換武器用），回傳被收起的節點（已脫離場景樹）。
func unequip(part_id: StringName) -> Node3D:
	var w: Node3D = held.get(part_id)
	if w == null:
		return null
	held.erase(part_id)
	w.get_parent().remove_child(w)
	return w

static func make_placeholder_visual(def: WeaponDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_%s" % def.id
	root.set_meta(&"weapon_def", def)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match def.weapon_type:
		&"hammer": bm.size = Vector3(0.18, 0.18, 0.9)
		&"rapier": bm.size = Vector3(0.025, 0.025, 1.0)
		_: bm.size = Vector3(0.12, 0.04, 0.7)
	mi.mesh = bm
	mi.position = Vector3(0, 0, -bm.size.z * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8c7a4b")  # 陳舊金
	mi.material_override = mat
	root.add_child(mi)
	return root

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
