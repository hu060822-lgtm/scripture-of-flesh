class_name PlaceholderBodyBuilder
extends RefCounted
## 【暫代】依 AnatomyProfile 用膠囊體／球體程序生成「分段人形」，用來驗證斷肢系統。
## 正式美術完成後，會以預先切段的骨架模型取代；DismembermentController 只依賴以下命名慣例，
## 因此換模型不需要改程式：
##   Skeleton3D 內每個部位一根骨骼（BodyPartDef.bone_name）
##   分段網格節點名稱 = BodyPartDef.mesh_segment
##   受擊區域 Hurtbox 名稱 = "hurt_<part_id>"
##   斷面標記 Marker3D 名稱 = "stump_<part_id>"（位於父部位上，標示關節位置）
##   持握點 Marker3D 名稱 = "grip_<part_id>"

const BONE_WHITE := Color("e8e2d6")   # 骨瓷白
const SOOT_BLACK := Color("2a2725")   # 煤灰黑

## 人形部位的暫代配置：位置（腳底為原點，公尺）、形狀、尺寸。
const LAYOUT := {
	&"chest":   {"pos": Vector3(0, 1.35, 0), "shape": "capsule", "r": 0.20, "h": 0.50},
	&"abdomen": {"pos": Vector3(0, 1.00, 0), "shape": "capsule", "r": 0.18, "h": 0.36},
	&"spine":   {"pos": Vector3(0, 1.20, -0.16), "shape": "box", "size": Vector3(0.08, 0.6, 0.06), "mesh": false},
	&"neck":    {"pos": Vector3(0, 1.62, 0), "shape": "capsule", "r": 0.07, "h": 0.16},
	&"head":    {"pos": Vector3(0, 1.80, 0), "shape": "sphere", "r": 0.13},
	&"eye_l":   {"pos": Vector3(0.05, 1.83, 0.11), "shape": "sphere", "r": 0.025, "color": SOOT_BLACK},
	&"eye_r":   {"pos": Vector3(-0.05, 1.83, 0.11), "shape": "sphere", "r": 0.025, "color": SOOT_BLACK},
	&"jaw":     {"pos": Vector3(0, 1.71, 0.06), "shape": "capsule", "r": 0.05, "h": 0.14},
	&"arm_l":   {"pos": Vector3(0.32, 1.22, 0), "shape": "capsule", "r": 0.06, "h": 0.70},
	&"arm_r":   {"pos": Vector3(-0.32, 1.22, 0), "shape": "capsule", "r": 0.06, "h": 0.70},
	&"leg_l":   {"pos": Vector3(0.10, 0.45, 0), "shape": "capsule", "r": 0.08, "h": 0.90},
	&"leg_r":   {"pos": Vector3(-0.10, 0.45, 0), "shape": "capsule", "r": 0.08, "h": 0.90},
}

## 非人形生物的專屬暫代配置（以 AnatomyProfile.id 為鍵），優先於 LAYOUT。
const PROFILE_LAYOUTS := {
	# 行走的母親（Boss）：四根高蹺腿撐起的巨大身軀，臍帶從子宮垂到地面。
	&"walking_mother": {
		&"torso":    {"pos": Vector3(0, 2.90, 0), "shape": "capsule", "r": 0.36, "h": 0.95},
		&"heart":    {"pos": Vector3(0, 2.95, 0), "shape": "sphere", "r": 0.12},
		&"neck":     {"pos": Vector3(0, 3.48, 0), "shape": "capsule", "r": 0.10, "h": 0.24},
		&"head":     {"pos": Vector3(0, 3.75, 0), "shape": "sphere", "r": 0.22, "color": Color("d8d0c0")},
		&"womb":     {"pos": Vector3(0, 2.20, 0.08), "shape": "sphere", "r": 0.45, "color": Color("8a3a30")},
		&"cradle_l": {"pos": Vector3(0.30, 2.45, 0.40), "shape": "capsule", "r": 0.08, "h": 0.70},
		&"cradle_r": {"pos": Vector3(-0.30, 2.45, 0.40), "shape": "capsule", "r": 0.08, "h": 0.70},
		&"long_arm_l": {"pos": Vector3(0.58, 2.50, 0), "shape": "capsule", "r": 0.07, "h": 1.50},
		&"long_arm_r": {"pos": Vector3(-0.58, 2.50, 0), "shape": "capsule", "r": 0.07, "h": 1.50},
		&"stilt_1":  {"pos": Vector3(0.38, 0.95, 0.28), "shape": "capsule", "r": 0.08, "h": 1.90, "color": SOOT_BLACK},
		&"stilt_2":  {"pos": Vector3(-0.38, 0.95, 0.28), "shape": "capsule", "r": 0.08, "h": 1.90, "color": SOOT_BLACK},
		&"stilt_3":  {"pos": Vector3(0.38, 0.95, -0.28), "shape": "capsule", "r": 0.08, "h": 1.90, "color": SOOT_BLACK},
		&"stilt_4":  {"pos": Vector3(-0.38, 0.95, -0.28), "shape": "capsule", "r": 0.08, "h": 1.90, "color": SOOT_BLACK},
		&"cord_1":   {"pos": Vector3(0.16, 1.30, 0.34), "shape": "capsule", "r": 0.05, "h": 1.10, "color": Color("a04a3e")},
		&"cord_2":   {"pos": Vector3(-0.16, 1.25, 0.34), "shape": "capsule", "r": 0.05, "h": 1.10, "color": Color("a04a3e")},
		&"cord_3":   {"pos": Vector3(0.0, 1.40, 0.44), "shape": "capsule", "r": 0.05, "h": 1.10, "color": Color("a04a3e")},
	},
}

const CREATURE_LAYER := 1 << 1  # 物理層 2：生物本體（移動碰撞）
const WORLD_LAYER := 1 << 0      # 物理層 1：場景

## 建立完整的暫代生物：CharacterBody3D 本體 + 身體 + AnatomyComponent + EquipmentComponent
## + DismembermentController + CombatComponent。
static func build_creature(profile: AnatomyProfile, creature_id: StringName,
		natural_attacks: Array[AttackDefinition] = [], faction: StringName = &"enemy") -> CharacterBody3D:
	var root := CharacterBody3D.new()
	root.name = String(creature_id)
	root.set_meta(&"placeholder", true)
	root.collision_layer = CREATURE_LAYER
	root.collision_mask = WORLD_LAYER | CREATURE_LAYER
	var col := CollisionShape3D.new()
	col.name = "BodyCollision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	root.add_child(col)
	var body := build_body(profile)
	root.add_child(body)

	var anatomy := AnatomyComponent.new()
	anatomy.name = "AnatomyComponent"
	anatomy.profile = profile
	anatomy.creature_id = creature_id
	root.add_child(anatomy)

	var equip := EquipmentComponent.new()
	equip.name = "EquipmentComponent"
	root.add_child(equip)

	var ctrl := DismembermentController.new()
	ctrl.name = "DismembermentController"
	root.add_child(ctrl)

	var combat := CombatComponent.new()
	combat.name = "CombatComponent"
	combat.natural_attacks = natural_attacks
	combat.faction = faction
	root.add_child(combat)
	return root

static func build_body(profile: AnatomyProfile) -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	body.add_child(skel)

	var positions := {}
	for d in profile.parts:
		positions[d.id] = _layout_for(d, profile)["pos"]

	# 依深度排序，確保父骨骼先建立。
	var ordered: Array[BodyPartDef] = profile.parts.duplicate()
	ordered.sort_custom(func(a, b): return _depth(profile, a) < _depth(profile, b))
	for d in ordered:
		var idx := skel.add_bone(String(d.bone_name))
		var world_pos: Vector3 = positions[d.id]
		var parent_pos := Vector3.ZERO
		if d.parent_id != &"":
			var pdef := profile.get_part(d.parent_id)
			skel.set_bone_parent(idx, skel.find_bone(String(pdef.bone_name)))
			parent_pos = positions[d.parent_id]
		skel.set_bone_rest(idx, Transform3D(Basis(), world_pos - parent_pos))
	skel.reset_bone_poses()

	for d in ordered:
		var lay := _layout_for(d, profile)
		var att := BoneAttachment3D.new()
		att.name = "attach_%s" % d.id
		att.bone_name = String(d.bone_name)
		skel.add_child(att)
		att.position = positions[d.id]
		if d.is_internal:
			continue  # 內部器官沒有外觀也不能直接命中
		if lay.get("mesh", true):
			var mi := MeshInstance3D.new()
			mi.name = String(d.mesh_segment)
			mi.mesh = _mesh_for(lay)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = lay.get("color", BONE_WHITE)
			mi.material_override = mat
			att.add_child(mi)
		var hb := Hurtbox.new()
		hb.name = "hurt_%s" % d.id
		hb.part_id = d.id
		var cs := CollisionShape3D.new()
		cs.shape = _shape_for(lay)
		hb.add_child(cs)
		att.add_child(hb)
		if d.functions.has("grip"):
			var grip := Marker3D.new()
			grip.name = "grip_%s" % d.id
			grip.position = Vector3(0, -float(lay.get("h", 0.5)) * 0.5, 0)
			att.add_child(grip)

	# 斷面標記：放在父部位上、子部位與父部位相接的關節處。
	for d in ordered:
		if d.parent_id == &"" or not d.detachable:
			continue
		var parent_att := skel.get_node("attach_%s" % d.parent_id) as Node3D
		var child_pos: Vector3 = positions[d.id]
		var dir: Vector3 = (positions[d.parent_id] - child_pos)
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.UP
		var lay := _layout_for(d, profile)
		var joint := child_pos + dir * _half_extent(lay)
		if lay["shape"] == "capsule":
			# 直立膠囊（手臂、腿、臍帶）：關節取靠近父部位的那一端，斷面才會在肩膀／髖部而不是埋進軀幹
			var top := child_pos + Vector3.UP * float(lay["h"]) * 0.5
			var bottom := child_pos - Vector3.UP * float(lay["h"]) * 0.5
			var pp: Vector3 = positions[d.parent_id]
			joint = top if top.distance_to(pp) <= bottom.distance_to(pp) else bottom
		var marker := Marker3D.new()
		marker.name = "stump_%s" % d.id
		parent_att.add_child(marker)
		marker.position = joint - positions[d.parent_id]
	return body

static func _layout_for(d: BodyPartDef, profile: AnatomyProfile = null) -> Dictionary:
	if profile != null and PROFILE_LAYOUTS.has(profile.id) and PROFILE_LAYOUTS[profile.id].has(d.id):
		return PROFILE_LAYOUTS[profile.id][d.id]
	if LAYOUT.has(d.id):
		return LAYOUT[d.id]
	var s := String(d.id)
	# 多手人等：arm_l1..N / arm_r1..N 沿軀幹往下排列。
	if s.begins_with("arm_l") or s.begins_with("arm_r"):
		var n := maxi(1, s.substr(5).to_int())
		var side := 1.0 if s.begins_with("arm_l") else -1.0
		return {"pos": Vector3(side * (0.32 + 0.06 * (n - 1)), 1.30 - 0.16 * (n - 1), 0.04 * (n - 1)), "shape": "capsule", "r": 0.05, "h": 0.62}
	# 無面觀察者的眼柄：從胸口上方呈扇形伸出。
	if s.begins_with("stalk_"):
		var k := maxi(1, s.substr(6).to_int())
		var ang := (float(k) - 2.5) * 0.45
		return {"pos": Vector3(sin(ang) * 0.22, 1.66 + 0.04 * (k % 2), 0.08 + cos(ang) * 0.08), "shape": "sphere", "r": 0.05, "color": SOOT_BLACK}
	return {"pos": Vector3(0, 1.0, 0), "shape": "sphere", "r": 0.1}

static func _depth(profile: AnatomyProfile, d: BodyPartDef) -> int:
	var n := 0
	var cur := d
	while cur != null and cur.parent_id != &"":
		n += 1
		cur = profile.get_part(cur.parent_id)
	return n

static func _half_extent(lay: Dictionary) -> float:
	match lay["shape"]:
		"capsule": return float(lay["h"]) * 0.5
		"sphere": return float(lay["r"])
		_: return (lay["size"] as Vector3).y * 0.5

static func _mesh_for(lay: Dictionary) -> Mesh:
	match lay["shape"]:
		"capsule":
			var m := CapsuleMesh.new(); m.radius = lay["r"]; m.height = lay["h"]; return m
		"sphere":
			var m := SphereMesh.new(); m.radius = lay["r"]; m.height = float(lay["r"]) * 2.0; return m
		_:
			var m := BoxMesh.new(); m.size = lay["size"]; return m

static func _shape_for(lay: Dictionary) -> Shape3D:
	match lay["shape"]:
		"capsule":
			var s := CapsuleShape3D.new(); s.radius = lay["r"]; s.height = lay["h"]; return s
		"sphere":
			var s := SphereShape3D.new(); s.radius = lay["r"]; return s
		_:
			var s := BoxShape3D.new(); s.size = lay["size"]; return s
