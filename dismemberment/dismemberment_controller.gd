class_name DismembermentController
extends Node
## 斷肢的「表現層」。收到 AnatomyState.part_severed 後同步更新：
##   模型（移除分段網格、生成殘肢、接上斷面）、骨架（斷離骨骼縮為零）、
##   碰撞（停用 Hurtbox）、裝備（武器掉落）、動畫組（依能力重選）。
## 資料（能力、依賴）由 AnatomyState 處理；AI 透過 capabilities_changed 自行重新評估（M4）。
## 依命名慣例尋找節點，詳見 PlaceholderBodyBuilder。

signal severed_visuals_applied(part_id: StringName, severed_ids: PackedStringArray)
signal animation_set_changed(animation_set: Dictionary)

const STUMP_COLOR := Color("5a1a14")  # 乾涸紅
const BONE_COLLAPSED_SCALE := Vector3(0.0001, 0.0001, 0.0001)

@export var anatomy: AnatomyComponent
@export var equipment: EquipmentComponent
@export var skeleton: Skeleton3D
## 殘肢與掉落武器放置的父節點；未設定時使用生物的父節點。
@export var world_parent: Node
@export var gib_impulse: float = 3.0

var animation_set := {}
var _creature: Node3D

func _ready() -> void:
	_creature = get_parent() as Node3D
	if anatomy == null:
		anatomy = _creature.get_node_or_null("AnatomyComponent")
	if equipment == null:
		equipment = _creature.get_node_or_null("EquipmentComponent")
	if skeleton == null:
		skeleton = _creature.find_child("Skeleton", true, false) as Skeleton3D
	assert(anatomy != null and skeleton != null, "DismembermentController needs AnatomyComponent and Skeleton3D")
	if anatomy.state == null:
		anatomy.setup()
	anatomy.state.part_severed.connect(_on_part_severed)
	anatomy.state.capabilities_changed.connect(_on_capabilities_changed)
	anatomy.state.part_restored.connect(_on_part_restored)
	if equipment != null:
		for d in anatomy.profile.parts:
			var grip := _find("grip_%s" % d.id)
			if grip != null:
				equipment.anchors[d.id] = grip
	_on_capabilities_changed(anatomy.state.capabilities())

func hurtbox_for(part_id: StringName) -> Hurtbox:
	return _find("hurt_%s" % part_id) as Hurtbox

func segment_for(part_id: StringName) -> Node3D:
	var def := anatomy.profile.get_part(part_id)
	return null if def == null else _find(String(def.mesh_segment))

func _find(node_name: String) -> Node3D:
	return _creature.find_child(node_name, true, false) as Node3D

func _drop_parent() -> Node:
	if world_parent != null:
		return world_parent
	return _creature.get_parent() if _creature.get_parent() != null else _creature

func _on_part_severed(top_id: StringName, ids: PackedStringArray) -> void:
	var drop_parent := _drop_parent()
	# 1. 裝備：武器掉落（D4：手部屬於手臂）
	if equipment != null:
		for id in ids:
			equipment.drop_from(StringName(id), drop_parent)
	# 2. 碰撞：停用所有斷離部位的 Hurtbox
	for id in ids:
		var hb := hurtbox_for(StringName(id))
		if hb != null:
			hb.deactivate()
	# 3. 模型：頂層部位生成一個殘肢，子部位的網格跟著它（斬首時頭帶著眼睛與下顎飛出）
	var top_seg := segment_for(top_id)
	var gib: SeveredPart = null
	if top_seg != null:
		var xf := top_seg.global_transform
		var dir := (xf.origin - _creature.global_position)
		dir.y = 0.0
		var impulse := (dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD) * gib_impulse + Vector3.UP * gib_impulse * 0.6
		var child_segments := []
		for id in ids:
			if StringName(id) == top_id:
				continue
			var seg := segment_for(StringName(id))
			if seg != null:
				child_segments.append([seg, xf.affine_inverse() * seg.global_transform])
		gib = SeveredPart.spawn(drop_parent, top_seg, xf, top_id, anatomy.creature_id, impulse)
		for pair in child_segments:
			var seg: Node3D = pair[0]
			seg.get_parent().remove_child(seg)
			gib.add_child(seg)
			seg.transform = pair[1]
	# 4. 骨架：斷離骨骼縮為零，避免殘留變形
	for id in ids:
		var def := anatomy.profile.get_part(StringName(id))
		var idx := skeleton.find_bone(String(def.bone_name))
		if idx >= 0:
			skeleton.set_bone_pose_scale(idx, BONE_COLLAPSED_SCALE)
	# 5. 斷面：在父部位的關節處接上斷面網格
	var marker := _find("stump_%s" % top_id)
	if marker != null and marker.get_node_or_null("cap") == null:
		var cap := MeshInstance3D.new()
		cap.name = "cap"
		var m := SphereMesh.new()
		m.radius = 0.06
		m.height = 0.06
		cap.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = STUMP_COLOR
		cap.material_override = mat
		marker.add_child(cap)
	severed_visuals_applied.emit(top_id, ids)

func _on_capabilities_changed(caps: CapabilitySet) -> void:
	var s := AnimationSet.from_capabilities(caps)
	if s != animation_set:
		animation_set = s
		animation_set_changed.emit(s)

func _on_part_restored(part_id: StringName) -> void:
	# 【未實作】修復後重建網格與骨架屬於 M6（肢體修復）。目前只恢復資料與受擊區域。
	for id in [part_id] + anatomy.state.descendants_of(part_id):
		var hb := hurtbox_for(id)
		if hb != null:
			hb.activate()
		var def := anatomy.profile.get_part(id)
		var idx := skeleton.find_bone(String(def.bone_name))
		if idx >= 0:
			skeleton.set_bone_pose_scale(idx, Vector3.ONE)
	push_warning("DismembermentController: visual restore of %s not implemented yet (M6)" % part_id)
