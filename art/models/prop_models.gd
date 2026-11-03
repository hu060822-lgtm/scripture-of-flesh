class_name PropModels
extends RefCounted
## 【程序生成模型】地上道具與可互動物件的低多邊形造型（PS1 風格，取代灰盒的球、方塊）。
## 每個 build 函式回傳一個 Node3D（名稱固定為 "Model"），原點在地面、物件立在 +Y 上。
## 道具本身只負責外觀；互動、拾取、旗標都在 world/ 的腳本裡，不受影響。
##
## 道具要能從固定斜俯視鏡頭、360p 畫面辨認，所以比例比真實稍大，關鍵部位（鑰匙、針、眼球）帶微弱的陳舊金光。

const S := preload("res://art/ps1/ps1_style.gd")
const CM := preload("res://art/models/creature_models.gd")

## 會微弱發光、提示「可以撿」的部位名稱（ItemPickup 會讓它們緩慢明滅）。
const GLINT_META := &"prop_glint"

# ---------- 共用 ----------

static func _node(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, name: String = "", scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := S.mesh_node(parent, mesh, mat, pos, rot, name)
	mi.scale = scale
	return mi

static func _root(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	root.set_meta(&"prop_kind", kind)
	return root

static func _glint(mi: MeshInstance3D) -> MeshInstance3D:
	mi.set_meta(GLINT_META, true)
	return mi

## 墊在道具底下的一小塊布（讓道具從地板上跳出來，也是 PS1 遊戲常見的「這裡有東西」）。
static func _cloth_patch(root: Node3D, size: Vector2, color: Color, blood: bool = false) -> void:
	_node(root, S.box(Vector3(size.x, 0.012, size.y)), S.material(color, "cloth"), Vector3(0, 0.006, 0), Vector3(0, 8, 0), "Cloth")
	if blood:
		_node(root, S.cylinder(size.x * 0.28, size.x * 0.32, 0.004, 7), S.material(S.DRIED_RED, "flesh"), Vector3(size.x * 0.15, 0.014, -size.y * 0.1), Vector3.ZERO, "BloodStain", Vector3(1, 1, 0.7))

## 把 CreatureModels 的部位造型（[mesh, material, dets]）放成一個節點。
static func _from_part(parent: Node3D, model: Array, pos: Vector3, rot: Vector3, name: String) -> MeshInstance3D:
	var mi := _node(parent, model[0], model[1], pos, rot, name)
	for det in model[2]:
		var d := MeshInstance3D.new()
		d.name = det[3]
		d.mesh = det[0]
		d.material_override = det[1]
		d.transform = det[2]
		mi.add_child(d)
	return mi

## 一個造型的總三角形數（測試用）。
static func triangle_count(node: Node) -> int:
	return WeaponModels.triangle_count(node)

# ---------- 地上的物品 ----------

## 依物品 id 建立外觀。count > 1 時，可堆疊的物品（血瓶）會多放幾個。
static func item(item_id: String, count: int = 1) -> Node3D:
	if item_id.begins_with("organ:"):
		return organ(item_id.substr(6))
	match item_id:
		"suture_kit": return suture_kit(count)
		"blood_vial": return blood_vials(count)
		"umbilical_key": return umbilical_key()
		"first_suture": return first_suture()
	return bundle()

## 緊急縫合包：攤開的皮革卷，上面有彎針、乾涸紅的線軸、捲好的繃帶。
static func suture_kit(count: int = 1) -> Node3D:
	var root := _root("suture_kit")
	var leather := S.material(Color("5a3a2a"), "cloth")
	_node(root, S.box(Vector3(0.46, 0.02, 0.3)), leather, Vector3(0, 0.01, 0), Vector3(0, 12, 0), "Roll")
	# 捲起的那一端
	_node(root, S.cylinder(0.05, 0.05, 0.32, 6), leather, Vector3(-0.24, 0.05, -0.05), Vector3(90, 12, 0), "RolledEnd")
	_node(root, S.box(Vector3(0.03, 0.022, 0.34)), S.material(S.OLD_GOLD.darkened(0.3), "metal"), Vector3(0.05, 0.024, 0.01), Vector3(0, 12, 0), "Strap")
	# 白色繃帶卷
	for i in mini(count, 2):
		_node(root, S.cylinder(0.055, 0.055, 0.07, 7), S.material(S.BONE_WHITE, "cloth"), Vector3(0.12 - i * 0.1, 0.06, 0.07), Vector3(0, 0, 90), "Bandage%d" % i)
	# 乾涸紅的線軸
	_node(root, S.cylinder(0.03, 0.03, 0.06, 6), S.material(S.DRIED_RED, "cloth"), Vector3(0.12, 0.04, -0.08), Vector3.ZERO, "Thread")
	_node(root, S.cylinder(0.042, 0.042, 0.012, 6), S.material(Color("6a4a36"), "wood"), Vector3(0.12, 0.076, -0.08), Vector3.ZERO, "SpoolTop")
	# 彎針（三段小方塊組成的弧）
	var steel := S.material(Color("c8c4ba"), "metal", S.OLD_GOLD, 0.6)
	for i in 3:
		var a := deg_to_rad(-40.0 + i * 40.0)
		_glint(_node(root, S.box(Vector3(0.05, 0.008, 0.008)), steel, Vector3(-0.04 + sin(a) * 0.05, 0.03, -0.02 + cos(a) * 0.03), Vector3(0, -40.0 + i * 40.0, 0), "Needle%d" % i))
	return root

## 濁血瓶：小木架上的玻璃瓶，混濁的暗紅血、軟木塞。
static func blood_vials(count: int = 1) -> Node3D:
	var root := _root("blood_vial")
	var n := clampi(count, 1, 3)
	var wood := S.material(Color("6a4a36"), "wood")
	_node(root, S.box(Vector3(0.1 + n * 0.1, 0.04, 0.12)), wood, Vector3(0, 0.02, 0), Vector3.ZERO, "Rack")
	var glass := S.material(Color("c8d0c8"), "glass")
	var blood := S.material(S.DRIED_RED.lightened(0.1), "flesh", S.DRIED_RED, 0.5)
	var cork := S.material(Color("8a6a4a"), "wood")
	for i in n:
		var x := (float(i) - (n - 1) * 0.5) * 0.1
		_node(root, S.cylinder(0.035, 0.04, 0.2, 6), glass, Vector3(x, 0.14, 0), Vector3.ZERO, "Vial%d" % i)
		_glint(_node(root, S.cylinder(0.031, 0.036, 0.13, 6), blood, Vector3(x, 0.11, 0), Vector3.ZERO, "Blood%d" % i))
		_node(root, S.cylinder(0.022, 0.026, 0.05, 5), cork, Vector3(x, 0.265, 0), Vector3.ZERO, "Cork%d" % i)
	return root

## 臍帶鑰匙：陳舊金的大鑰匙，握柄纏著一段乾涸紅、有結節的臍帶。
static func umbilical_key() -> Node3D:
	var root := _root("umbilical_key")
	_cloth_patch(root, Vector2(0.5, 0.36), S.CREAM_YELLOW.darkened(0.25), true)
	var gold := S.material(S.OLD_GOLD, "metal", S.OLD_GOLD, 0.7)
	var key := Node3D.new()
	key.name = "Key"
	key.position = Vector3(0, 0.035, 0)
	key.rotation_degrees = Vector3(0, 25, 0)
	root.add_child(key)
	var bow := TorusMesh.new()
	bow.inner_radius = 0.045
	bow.outer_radius = 0.075
	bow.rings = 8
	bow.ring_segments = 4
	_glint(_node(key, bow, gold, Vector3(-0.17, 0, 0), Vector3.ZERO, "Bow"))
	_glint(_node(key, S.cylinder(0.016, 0.016, 0.3, 5), gold, Vector3(0.03, 0, 0), Vector3(0, 0, 90), "Shaft"))
	for i in 2:
		_node(key, S.box(Vector3(0.03, 0.02, 0.07 - i * 0.02)), gold, Vector3(0.14 + i * 0.04, 0, 0.04 - i * 0.008), Vector3.ZERO, "Bit%d" % i)
	# 纏在握柄上、拖出去的臍帶
	var cord := S.material(S.DRIED_RED.lightened(0.2), "flesh", S.DRIED_RED, 0.35)
	for i in 6:
		var t := float(i) / 5.0
		var p := Vector3(-0.17 - t * 0.12 + sin(t * 6.0) * 0.04, 0.0, 0.08 + t * 0.12)
		_node(key, S.sphere(0.028 - t * 0.008, 5, 2), cord, p, Vector3.ZERO, "Cord%d" % i, Vector3(1.4, 0.8, 1))
	return root

## 最初的縫線：小小的骨瓷白聖物盒，裡面一根骨針，穿著發著陳舊金光的線。
static func first_suture() -> Node3D:
	var root := _root("first_suture")
	var bone := S.material(S.BONE_WHITE.darkened(0.05), "bone")
	_node(root, S.box(Vector3(0.3, 0.06, 0.2)), bone, Vector3(0, 0.03, 0), Vector3(0, -10, 0), "Reliquary")
	_node(root, S.box(Vector3(0.26, 0.012, 0.16)), S.material(S.DRIED_RED.darkened(0.2), "cloth"), Vector3(0, 0.062, 0), Vector3(0, -10, 0), "Velvet")
	# 打開的蓋子靠在後面
	_node(root, S.box(Vector3(0.3, 0.2, 0.02)), bone, Vector3(0.0, 0.14, 0.11), Vector3(-20, -10, 0), "Lid")
	_node(root, S.box(Vector3(0.05, 0.05, 0.005)), S.material(S.OLD_GOLD, "metal"), Vector3(0.0, 0.17, 0.095), Vector3(-20, -10, 0), "Cross")
	_glint(_node(root, S.cylinder(0.006, 0.01, 0.2, 4), S.material(S.BONE_WHITE, "bone", S.BONE_WHITE, 0.3), Vector3(0, 0.08, 0), Vector3(0, -10, 90), "BoneNeedle"))
	var thread := S.material(S.OLD_GOLD.lightened(0.2), "plain", S.OLD_GOLD, 1.4)
	for i in 5:
		var t := float(i) / 4.0
		_glint(_node(root, S.box(Vector3(0.05, 0.006, 0.006)), thread, Vector3(0.1 - t * 0.02, 0.075, -0.02 - t * 0.04 + sin(t * 5.0) * 0.015), Vector3(0, 60.0 + sin(t * 4.0) * 40.0, 0), "Thread%d" % i))
	return root

## 未登記的物品：用布包起來、綁著線的小包裹。
static func bundle() -> Node3D:
	var root := _root("bundle")
	_node(root, S.sphere(0.13, 6, 3), S.material(S.CREAM_YELLOW.darkened(0.2), "cloth"), Vector3(0, 0.1, 0), Vector3.ZERO, "Bundle", Vector3(1.2, 0.8, 1))
	_node(root, S.cylinder(0.04, 0.06, 0.06, 5), S.material(S.CREAM_YELLOW.darkened(0.3), "cloth"), Vector3(0, 0.2, 0), Vector3.ZERO, "Knot")
	_node(root, S.cylinder(0.157, 0.157, 0.015, 6), S.material(S.DRIED_RED, "cloth"), Vector3(0, 0.12, 0), Vector3.ZERO, "Twine", Vector3(1.2, 1, 1))
	return root

# ---------- 器官（可移植） ----------

## 器官：手臂類放在沾血的布上，其他放進玻璃罐（混濁的液體、陳舊金封蓋）。
static func organ(organ_id: String) -> Node3D:
	match organ_id:
		"agnes_arm": return severed_arm(CM.LOOKS[&"agnes"], "organ_agnes_arm", true)
		"stitched_arm": return severed_arm({"skin": [S.GREY_PINK.darkened(0.25), "stitched"], "trim": S.DRIED_RED, "sutures": true}, "organ_stitched_arm", false)
		"iron_arm": return iron_arm()
		"reverse_leg": return severed_leg()
	return organ_jar(organ_id)

## 斷臂：橫躺在布上，肩口有縫合的斷面。
static func severed_arm(lk: Dictionary, kind: String, sleeve: bool) -> Node3D:
	var root := _root(kind)
	_cloth_patch(root, Vector2(0.9, 0.42), S.BONE_WHITE.darkened(0.15), true)
	var h := 0.7
	var r := 0.06
	var arm := _from_part(root, CM._arm(h, r, lk), Vector3(0, r * 1.1, 0), Vector3(0, 15, 90), "Arm")
	arm.name = "Arm"
	# 肩口的斷面（肉、骨）＋一圈粗縫線
	var cap := Node3D.new()
	cap.name = "Stump"
	cap.position = Vector3(0, h * 0.5 + r * 0.3, 0)
	arm.add_child(cap)
	_node(cap, S.cylinder(r * 1.1, r * 1.1, 0.02, 6), S.material(S.DRIED_RED.lightened(0.15), "flesh", S.DRIED_RED, 0.3), Vector3.ZERO, Vector3.ZERO, "Flesh")
	_node(cap, S.cylinder(r * 0.35, r * 0.35, 0.04, 5), S.material(S.BONE_WHITE, "bone"), Vector3(0, 0.01, 0), Vector3.ZERO, "Bone")
	if sleeve:
		# 阿格妮絲：手腕上纏著一串陳舊金念珠
		for i in 6:
			var a := TAU * i / 6.0
			_glint(_node(arm, S.sphere(0.014, 4, 2), S.material(S.OLD_GOLD, "metal", S.OLD_GOLD, 0.6), Vector3(cos(a) * r * 0.8, -h * 0.28, sin(a) * r * 0.8), Vector3.ZERO, "Bead%d" % i))
	return root

static func iron_arm() -> Node3D:
	var root := _root("organ_iron_arm")
	_cloth_patch(root, Vector2(0.9, 0.42), Color("4a4644"), false)
	var arm := _from_part(root, CM._iron_arm(0.7, 0.06, {}), Vector3(0, 0.07, 0), Vector3(0, -20, 90), "Arm")
	# 肩部的固定環與露出的螺栓（陳舊金，表示可以裝上）
	_glint(_node(arm, S.cylinder(0.08, 0.08, 0.04, 6), S.material(S.OLD_GOLD, "metal", S.OLD_GOLD, 0.5), Vector3(0, 0.36, 0), Vector3.ZERO, "Socket"))
	for i in 3:
		_node(arm, S.cylinder(0.01, 0.01, 0.06, 4), S.material(Color("8a8886"), "metal"), Vector3(cos(TAU * i / 3.0) * 0.04, 0.4, sin(TAU * i / 3.0) * 0.04), Vector3.ZERO, "Bolt%d" % i)
	return root

static func severed_leg() -> Node3D:
	var root := _root("organ_reverse_leg")
	_cloth_patch(root, Vector2(1.0, 0.4), S.BONE_WHITE.darkened(0.15), true)
	_from_part(root, CM._reverse_leg(0.9, 0.08, {"skin": [S.GREY_PINK.darkened(0.35), "skin"], "trim": S.DRIED_RED}), Vector3(0, 0.1, 0), Vector3(0, 10, 90), "Leg")
	return root

## 玻璃罐：罐裡浮著器官。眼睛會發光（觀察者之眼也是弱點色）。
static func organ_jar(organ_id: String) -> Node3D:
	var root := _root("organ_" + organ_id)
	var glass := S.material(Color("b8c4b0"), "glass")
	var fluid := S.material(Color("8a8a5a"), "glass", Color("6a6a3a"), 0.25)
	var gold := S.material(S.OLD_GOLD, "metal")
	_node(root, S.cylinder(0.13, 0.12, 0.3, 7), glass, Vector3(0, 0.16, 0), Vector3.ZERO, "Jar")
	_node(root, S.cylinder(0.115, 0.11, 0.22, 7), fluid, Vector3(0, 0.12, 0), Vector3.ZERO, "Fluid")
	_node(root, S.cylinder(0.14, 0.14, 0.04, 7), gold, Vector3(0, 0.33, 0), Vector3.ZERO, "Lid")
	_node(root, S.cylinder(0.14, 0.14, 0.03, 7), gold, Vector3(0, 0.015, 0), Vector3.ZERO, "Base")
	# 封條（奶油黃紙、乾涸紅字）
	_node(root, S.box(Vector3(0.08, 0.12, 0.01)), S.material(S.CREAM_YELLOW, "cloth"), Vector3(0, 0.18, -0.13), Vector3.ZERO, "Label")
	_node(root, S.box(Vector3(0.05, 0.015, 0.005)), S.material(S.DRIED_RED, "plain"), Vector3(0, 0.2, -0.137), Vector3.ZERO, "LabelInk")
	var inside := Node3D.new()
	inside.name = "Specimen"
	inside.position = Vector3(0, 0.15, 0)
	root.add_child(inside)
	if organ_id.contains("eye"):
		var eye := _from_part(inside, CM._eye(0.07, true), Vector3.ZERO, Vector3(10, 30, 0), "Eye")
		_glint(eye)
		# 拖在眼球後面的視神經
		_node(inside, S.cylinder(0.012, 0.02, 0.1, 4), S.material(S.GREY_PINK, "flesh"), Vector3(0.02, -0.06, 0.04), Vector3(30, 0, 20), "Nerve")
	elif organ_id.contains("heart"):
		var flesh := S.material(S.DRIED_RED.lightened(0.2), "flesh", S.DRIED_RED, 0.3)
		_glint(_node(inside, S.sphere(0.065, 6, 3), flesh, Vector3.ZERO, Vector3(0, 0, 20), "Heart", Vector3(1, 1.25, 0.9)))
		for i in 3:
			_node(inside, S.cylinder(0.012, 0.018, 0.07, 4), flesh, Vector3(-0.02 + i * 0.02, 0.08, 0.0), Vector3(0, 0, -20.0 + i * 20.0), "Vessel%d" % i)
	elif organ_id.contains("lung"):
		var lung := S.material(Color("a8b4bc"), "flesh", Color("8aa0b0"), 0.4)
		for side in [-1.0, 1.0]:
			_glint(_node(inside, S.sphere(0.05, 6, 3), lung, Vector3(side * 0.045, 0, 0), Vector3.ZERO, "Lobe", Vector3(0.8, 1.5, 0.7)))
		_node(inside, S.cylinder(0.012, 0.012, 0.08, 4), lung, Vector3(0, 0.08, 0), Vector3.ZERO, "Trachea")
	else:
		_glint(_node(inside, S.sphere(0.07, 6, 3), S.material(S.GREY_PINK, "flesh", S.DRIED_RED, 0.2), Vector3.ZERO, Vector3.ZERO, "Lump", Vector3(1.1, 0.8, 1)))
	return root

# ---------- 武器台 ----------

## 武器台：哥德式的石座、鋪著乾涸紅的布，武器（WeaponModels 的實際模型）斜立在上面。
## 武器節點名稱固定為 "Weapon"（WeaponPedestal 拿走後隱藏它）。
static func pedestal(def: WeaponDefinition) -> Node3D:
	var root := _root("pedestal")
	var stone := S.material(Color("cfc8b8"), "stone")
	var k := MeshKit.new()
	k.lathe([Vector2(0.42, 0.0), Vector2(0.42, 0.12), Vector2(0.3, 0.18), Vector2(0.22, 0.25), Vector2(0.2, 0.72), Vector2(0.3, 0.8), Vector2(0.36, 0.9)], 6)
	_node(root, k.commit(), stone, Vector3.ZERO, Vector3(0, 30, 0), "Base")
	_node(root, S.box(Vector3(0.62, 0.02, 0.5)), S.material(S.DRIED_RED, "cloth"), Vector3(0, 0.91, 0), Vector3(0, 5, 0), "Altarcloth")
	_node(root, S.box(Vector3(0.12, 0.3, 0.02)), S.material(S.DRIED_RED.darkened(0.15), "cloth"), Vector3(0, 0.78, -0.26), Vector3(0, 5, 0), "ClothDrape")
	# 正面陳舊金的小十字
	_node(root, S.box(Vector3(0.04, 0.18, 0.02)), S.material(S.OLD_GOLD, "metal"), Vector3(0, 0.48, -0.21), Vector3.ZERO, "CrossV")
	_node(root, S.box(Vector3(0.12, 0.04, 0.02)), S.material(S.OLD_GOLD, "metal"), Vector3(0, 0.52, -0.21), Vector3.ZERO, "CrossH")
	# 燒剩的兩根蠟燭
	for side in [-1.0, 1.0]:
		_node(root, S.cylinder(0.03, 0.035, 0.12 + side * 0.03, 5), S.material(S.CREAM_YELLOW, "plain"), Vector3(side * 0.22, 0.98 + side * 0.015, 0.15), Vector3.ZERO, "Candle")
	var holder := Node3D.new()
	holder.name = "Weapon"
	holder.position = Vector3(0, 0.94, 0)
	root.add_child(holder)
	if def != null:
		var w := WeaponModels.build(def)
		# 武器沿 -Z 伸出；轉成刃朝上、握柄插在台上，像展示的聖物
		w.rotation_degrees = Vector3(80, 30, 0)
		w.position = Vector3(0, 0.04, 0)
		holder.add_child(w)
	return root

# ---------- 筆記、經文、銘文 ----------

## 散落的筆記：兩三張捲邊的紙、乾掉的墨水瓶與羽毛筆。
static func note() -> Node3D:
	var root := _root("note")
	var paper := S.material(Color("e9dcb8"), "cloth")
	var ink := S.material(S.SOOT_BLACK.lightened(0.15), "plain")
	for i in 3:
		var p := _node(root, S.box(Vector3(0.28, 0.006, 0.36)), paper, Vector3(-0.06 + i * 0.07, 0.006 + i * 0.006, 0.03 - i * 0.04), Vector3(0, -25.0 + i * 22.0, 3.0 * i), "Page%d" % i)
		# 頁面上的字行（細長的深色方塊）
		for j in 4:
			_node(p, S.box(Vector3(0.18 - (j % 2) * 0.05, 0.002, 0.012)), ink, Vector3(-0.01, 0.004, -0.12 + j * 0.05), Vector3.ZERO, "Line%d" % j)
	_node(root, S.cylinder(0.03, 0.035, 0.06, 6), S.material(S.SOOT_BLACK, "glass"), Vector3(0.2, 0.03, -0.12), Vector3.ZERO, "Inkwell")
	_node(root, S.box(Vector3(0.012, 0.012, 0.3)), S.material(S.BONE_WHITE, "plain"), Vector3(0.12, 0.03, 0.05), Vector3(0, 35, 8), "Quill")
	# 一抹乾涸的血手印
	_node(root, S.box(Vector3(0.08, 0.003, 0.1)), S.material(S.DRIED_RED, "flesh"), Vector3(0.0, 0.026, -0.04), Vector3(0, 30, 0), "Bloodprint")
	return root

## 《肉身聖典》殘頁：發著陳舊金光的羊皮紙，被一根骨針釘著，旁邊滴著蠟。
static func scripture_leaf() -> Node3D:
	var root := _root("scripture_page")
	var vellum := S.material(Color("d9c27a"), "cloth", S.OLD_GOLD, 0.6)
	var leaf := _glint(_node(root, S.box(Vector3(0.34, 0.008, 0.44)), vellum, Vector3(0, 0.02, 0), Vector3(4, 18, -3), "Leaf"))
	var glyph := S.material(S.DRIED_RED.darkened(0.1), "plain")
	for j in 5:
		_node(leaf, S.box(Vector3(0.22 - (j % 3) * 0.04, 0.003, 0.016)), glyph, Vector3(0, 0.005, -0.15 + j * 0.06), Vector3.ZERO, "Glyph%d" % j)
	# 中央的解剖圖（紅色圓＋十字）
	_node(leaf, S.cylinder(0.05, 0.05, 0.003, 6), S.material(S.DRIED_RED, "plain"), Vector3(0.06, 0.006, 0.02), Vector3.ZERO, "Diagram")
	_node(root, S.cylinder(0.008, 0.012, 0.16, 4), S.material(S.BONE_WHITE, "bone"), Vector3(-0.1, 0.07, -0.14), Vector3(20, 0, -10), "BonePin")
	_node(root, S.sphere(0.03, 5, 2), S.material(S.DRIED_RED, "plain"), Vector3(0.12, 0.028, 0.16), Vector3.ZERO, "WaxSeal", Vector3(1, 0.35, 1))
	return root

## 銘文：一塊立著的哥德式石碑（尖拱頂），刻著幾行字，碑腳有燒完的蠟燭。
static func inscription_tablet() -> Node3D:
	var root := _root("inscription")
	var stone := S.material(Color("6b625a"), "stone")
	_node(root, S.box(Vector3(1.0, 0.16, 0.36)), stone, Vector3(0, 0.08, 0), Vector3.ZERO, "Plinth")
	_node(root, S.box(Vector3(0.84, 1.0, 0.16)), stone, Vector3(0, 0.66, 0), Vector3.ZERO, "Slab")
	# 尖拱頂：兩個斜放的方塊
	for side in [-1.0, 1.0]:
		_node(root, S.box(Vector3(0.6, 0.16, 0.16)), stone, Vector3(side * 0.2, 1.22, 0), Vector3(0, 0, side * -32.0), "Arch")
	var carve := S.material(S.SOOT_BLACK, "plain")
	for j in 5:
		_node(root, S.box(Vector3(0.56 - (j % 2) * 0.14, 0.035, 0.02)), carve, Vector3(0, 0.95 - j * 0.12, -0.085), Vector3.ZERO, "Carving%d" % j)
	_node(root, S.box(Vector3(0.05, 0.22, 0.02)), S.material(S.OLD_GOLD, "metal"), Vector3(0, 1.22, -0.085), Vector3.ZERO, "CrossV")
	_node(root, S.box(Vector3(0.14, 0.05, 0.02)), S.material(S.OLD_GOLD, "metal"), Vector3(0, 1.26, -0.085), Vector3.ZERO, "CrossH")
	# 碑腳乾涸的血跡與兩截蠟燭
	_node(root, S.box(Vector3(0.3, 0.004, 0.2)), S.material(S.DRIED_RED, "flesh"), Vector3(0.18, 0.162, -0.06), Vector3(0, 20, 0), "Blood")
	for side in [-1.0, 1.0]:
		_node(root, S.cylinder(0.035, 0.04, 0.1 - side * 0.03, 5), S.material(S.CREAM_YELLOW, "plain"), Vector3(side * 0.38, 0.21, -0.1), Vector3.ZERO, "Candle")
	return root

## 牆上的隱藏經文：一片刻著發光字的石板（只有「看得見」的人才看得到）。
static func hidden_glyphs() -> Node3D:
	var root := _root("hidden_scripture")
	var glow := S.material(Color("c9a27a"), "stone", Color("c9a27a"), 1.2)
	for j in 6:
		var w := 1.2 - (j % 3) * 0.25
		_node(root, S.box(Vector3(w, 0.06, 0.03)), glow, Vector3(0, 1.8 - j * 0.15, 0), Vector3.ZERO, "Glyphs%d" % j)
	# 中央的眼睛符號
	var eye := TorusMesh.new()
	eye.inner_radius = 0.12
	eye.outer_radius = 0.16
	eye.rings = 8
	eye.ring_segments = 3
	_node(root, eye, glow, Vector3(0, 1.4, 0), Vector3(90, 0, 0), "GlyphsEye", Vector3(1.6, 1, 1))
	_node(root, S.sphere(0.06, 5, 2), glow, Vector3(0, 1.4, 0), Vector3.ZERO, "GlyphsPupil")
	return root
