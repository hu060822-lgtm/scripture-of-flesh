class_name WeaponModels
extends RefCounted
## 【程序生成模型】武器的低多邊形模型（PS1 風格：6 邊圓柱、點取樣低解析度貼圖）。
## 原點 = 持握點（手掌），武器沿 -Z 往前伸。EquipmentComponent 掛在 grip_<arm> 上。
## 依 WeaponDefinition.id 建立專屬造型；未登記的武器依 weapon_type 使用通用造型。

const S := preload("res://art/ps1/ps1_style.gd")

## 沿 Z 軸放置的圓柱（CylinderMesh 預設沿 Y）。
static func _rod(parent: Node3D, top: float, bottom: float, length: float, mat: Material, z_from: float, sides: int = 6, name: String = "") -> MeshInstance3D:
	return S.mesh_node(parent, S.cylinder(top, bottom, length, sides), mat, Vector3(0, 0, z_from - length * 0.5), Vector3(-90, 0, 0), name)

static func build(def: WeaponDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_%s" % def.id
	root.set_meta(&"weapon_def", def)
	match def.id:
		&"bone_saw_cleaver": _cleaver(root)
		&"anatomist_rapier": _rapier(root)
		&"reliquary_hammer": _hammer(root)
		_:
			match def.weapon_type:
				&"hammer": _hammer(root)
				&"rapier": _rapier(root)
				_: _cleaver(root)
	return root

## 骨鋸砍刀：纏布木柄、陳舊金鉚釘、厚背鋸齒刀身，刀刃帶乾涸的血。
static func _cleaver(root: Node3D) -> void:
	var wood := S.material(Color("6a4a36"), "wood")
	var wrap := S.material(S.CREAM_YELLOW.darkened(0.25), "cloth")
	var steel := S.material(Color("b8b4aa"), "metal")
	var blood := S.material(S.DRIED_RED, "flesh")
	var gold := S.material(S.OLD_GOLD, "metal")
	_rod(root, 0.022, 0.026, 0.24, wood, 0.12, 6, "Handle")
	_rod(root, 0.028, 0.028, 0.08, wrap, 0.02, 6, "Wrap")
	S.mesh_node(root, S.sphere(0.03, 5, 2), gold, Vector3(0, 0, 0.13), Vector3.ZERO, "Pommel")
	S.mesh_node(root, S.box(Vector3(0.05, 0.07, 0.04)), gold, Vector3(0, 0.01, -0.13), Vector3.ZERO, "Bolster")
	# 刀身：刃朝下（-Y），刀背朝上
	S.mesh_node(root, S.box(Vector3(0.018, 0.13, 0.52)), steel, Vector3(0, -0.02, -0.41), Vector3.ZERO, "Blade")
	S.mesh_node(root, S.box(Vector3(0.02, 0.03, 0.30)), blood, Vector3(0, -0.075, -0.48), Vector3.ZERO, "BloodEdge")
	S.mesh_node(root, S.box(Vector3(0.024, 0.06, 0.08)), steel, Vector3(0, -0.01, -0.69), Vector3(25, 0, 0), "Tip")
	for i in 6:
		S.mesh_node(root, S.cylinder(0.0, 0.014, 0.03, 3), steel, Vector3(0, 0.06, -0.20 - i * 0.075), Vector3.ZERO, "Tooth%d" % i)
	for i in 2:
		S.mesh_node(root, S.sphere(0.012, 4, 2), gold, Vector3(0.011, 0.02, -0.18 - i * 0.04), Vector3.ZERO, "Rivet%d" % i)

## 解剖學者的細劍：陳舊金的杯狀護手與護環、細長稜形劍身。
static func _rapier(root: Node3D) -> void:
	var steel := S.material(Color("cfcac0"), "metal")
	var gold := S.material(S.OLD_GOLD, "metal")
	var grip := S.material(S.SOOT_BLACK.lightened(0.1), "cloth")
	_rod(root, 0.016, 0.02, 0.16, grip, 0.08, 6, "Grip")
	S.mesh_node(root, S.sphere(0.028, 6, 3), gold, Vector3(0, 0, 0.1), Vector3.ZERO, "Pommel")
	# 杯狀護手：開口朝後包住手
	S.mesh_node(root, S.cylinder(0.075, 0.03, 0.06, 8), gold, Vector3(0, 0, -0.03), Vector3(-90, 0, 0), "CupGuard")
	S.mesh_node(root, S.box(Vector3(0.22, 0.016, 0.016)), gold, Vector3(0, 0, -0.07), Vector3.ZERO, "Quillons")
	var ring := S.mesh_node(root, TorusMesh.new(), gold, Vector3(0, 0.0, -0.08), Vector3(0, 0, 90), "Ring")
	(ring.mesh as TorusMesh).inner_radius = 0.035
	(ring.mesh as TorusMesh).outer_radius = 0.045
	(ring.mesh as TorusMesh).rings = 6
	(ring.mesh as TorusMesh).ring_segments = 3
	_rod(root, 0.003, 0.011, 0.95, steel, -0.08, 4, "Blade")

## 聖髑錘：長木柄、陳舊金鑲邊的聖髑盒錘頭，盒上小窗透出奶油黃的光（裡面是一截指骨），背面有尖刺。
static func _hammer(root: Node3D) -> void:
	var wood := S.material(Color("5a3a2a"), "wood")
	var gold := S.material(S.OLD_GOLD, "metal")
	var bone := S.material(S.BONE_WHITE, "bone", S.CREAM_YELLOW, 0.6)
	var iron := S.material(Color("5c5a58"), "metal")
	_rod(root, 0.024, 0.028, 0.95, wood, 0.25, 6, "Haft")
	S.mesh_node(root, S.box(Vector3(0.06, 0.06, 0.05)), iron, Vector3(0, 0, 0.27), Vector3.ZERO, "Butt")
	for i in 3:
		_rod(root, 0.03, 0.03, 0.03, gold, -0.05 - i * 0.18, 6, "Band%d" % i)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0, -0.72)
	root.add_child(head)
	S.mesh_node(head, S.box(Vector3(0.30, 0.17, 0.17)), gold, Vector3.ZERO, Vector3.ZERO, "Reliquary")
	S.mesh_node(head, S.box(Vector3(0.32, 0.04, 0.19)), iron, Vector3(0, 0.09, 0), Vector3.ZERO, "Lid")
	S.mesh_node(head, S.box(Vector3(0.12, 0.09, 0.02)), bone, Vector3(0, 0, -0.09), Vector3.ZERO, "Window")
	S.mesh_node(head, S.box(Vector3(0.10, 0.10, 0.10)), iron, Vector3(0.20, 0, 0), Vector3.ZERO, "Face")
	S.mesh_node(head, S.cylinder(0.0, 0.04, 0.16, 4), iron, Vector3(-0.22, 0, 0), Vector3(0, 0, 90), "Spike")
	S.mesh_node(head, S.cylinder(0.0, 0.03, 0.08, 4), gold, Vector3(0, 0.15, 0), Vector3.ZERO, "Finial")

## 三角形數（測試用：確認維持低多邊形）。
static func triangle_count(node: Node) -> int:
	var n := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
