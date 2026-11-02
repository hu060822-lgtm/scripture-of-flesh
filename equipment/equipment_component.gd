class_name EquipmentComponent
extends Node
## 武器持握。依 D4 決策，手部屬於手臂：武器掛在手臂部位上。
## 手臂斷離時武器掉落成場景中的物件。（武器資料 WeaponDefinition 於 M3 加入。）

signal weapon_dropped(part_id: StringName, weapon: Node3D)

## 由 DismembermentController 或建構者設定：part_id -> 掛點 Node3D
var anchors := {}
var held := {}  # part_id -> Node3D

## 握持角度：手臂自然下垂時武器朝前下方（-65°）。揮擊時手臂前擺，武器跟著轉到水平或高舉。
const GRIP_PITCH_DEGREES := -65.0

func equip(part_id: StringName, weapon: Node3D) -> bool:
	var anchor: Node3D = anchors.get(part_id)
	if anchor == null or held.has(part_id):
		return false
	if weapon.get_parent() != null:
		weapon.get_parent().remove_child(weapon)
	anchor.add_child(weapon)
	weapon.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(GRIP_PITCH_DEGREES)), Vector3.ZERO)
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

## 以武器資料建立外觀（程序生成的低多邊形模型）並裝備。
func equip_definition(def: WeaponDefinition, part_id: StringName) -> Node3D:
	var node := make_visual(def)
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

static func make_visual(def: WeaponDefinition) -> Node3D:
	return WeaponModels.build(def)

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
	weapon.transform = Transform3D(Basis(), Vector3(0, 0, 0.35))  # 碰撞盒置中於武器長度
	weapon_dropped.emit(part_id, weapon)
	return weapon
