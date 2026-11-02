class_name CreatureModels
extends RefCounted
## 【程序生成模型】把生物的每個分段換成具象的低多邊形造型（PS1 風格）。
## 不改節點名稱與階層：分段網格仍叫 BodyPartDef.mesh_segment、位置不變，細節（手指、牙齒、縫線、衣物…）
## 是分段底下的子網格，斷肢時跟著分段一起飛出，修復時由 DismembermentController 的複本重建。
## 受擊區域（hurt_<id>）的形狀不變，模型只負責外觀；戰鬥數值不受影響。
## 必須在生物加入場景樹之前呼叫（修復用複本在 _ready 時建立）。
##
## look：外觀主題（player、stitcher、many_hands、reverse_legged、faceless_watcher、unborn、walking_mother，
##       其他 id 使用通用人形）。variant：移植器官或 Boss 階段造成的部位外觀（iron_arm、stitched_arm、
##       reverse_leg、watcher_eye、womb_exposed），由 ModelSkinner 在部位被替換時套用。

const S := preload("res://art/ps1/ps1_style.gd")
const DETAIL_META := &"model_detail"

## 外觀主題：skin = [顏色, 貼圖], cloth = [顏色, 貼圖], trim = 顏色
const LOOKS := {
	&"player": {"skin": [Color("c9aea6"), "skin"], "cloth": [Color("2a2725"), "cloth"], "trim": Color("a8863f"), "clothed": true, "hood": true},
	&"humanoid": {"skin": [Color("cdbfb0"), "skin"], "cloth": [Color("5a524c"), "cloth"], "trim": Color("8a7a5a"), "clothed": true},
	&"stitcher": {"skin": [Color("a99390"), "stitched"], "cloth": [Color("4a3328"), "cloth"], "trim": Color("6e1f19"), "apron": true, "sutures": true},
	&"many_hands": {"skin": [Color("ddd3c4"), "skin"], "cloth": [Color("efe2b0"), "cloth"], "trim": Color("a8863f"), "long_fingers": true},
	&"reverse_legged": {"skin": [Color("8f7a74"), "skin"], "cloth": [Color("2a2725"), "cloth"], "trim": Color("6e1f19"), "gaunt": true},
	&"faceless_watcher": {"skin": [Color("e8e2d6"), "skin"], "cloth": [Color("e8e2d6"), "cloth"], "trim": Color("a8863f"), "clothed": true, "robe": true},
	&"unborn": {"skin": [Color("c8a09a"), "flesh"], "cloth": [Color("efe2b0"), "cloth"], "trim": Color("6e1f19"), "fetal": true},
	# 序章提案 G：水室的「長子」——長大了卻沒有出生的孩子，膚色更灰、布更髒。
	&"unborn_elite": {"skin": [Color("a88a86"), "flesh"], "cloth": [Color("b8a888"), "cloth"], "trim": Color("4e1612"), "fetal": true},
	# 阿格妮絲：產房的修女兼接生者。奶油黃頭巾、煤灰黑修女服、陳舊金念珠。
	&"agnes": {"skin": [Color("d6bfb6"), "skin"], "cloth": [Color("2a2725"), "cloth"], "hood_cloth": [Color("e2d4a4"), "cloth"], "trim": Color("a8863f"), "clothed": true, "hood": true},
	&"walking_mother": {"skin": [Color("e8e2d6"), "skin"], "cloth": [Color("efe2b0"), "cloth"], "trim": Color("a8863f"), "veil": true},
}

## 套用外觀。回傳替換了幾個分段（測試用）。
static func apply(creature: Node3D, look: StringName) -> int:
	var anatomy: AnatomyComponent = creature.get_node_or_null("AnatomyComponent")
	if anatomy == null or anatomy.profile == null:
		return 0
	var lk: Dictionary = LOOKS.get(look, LOOKS[&"humanoid"])
	creature.set_meta(&"model_look", look)
	var n := 0
	for d in anatomy.profile.parts:
		if d.is_internal:
			continue
		var seg := creature.find_child(String(d.mesh_segment), true, false) as MeshInstance3D
		if seg == null:
			continue
		build_segment(seg, d, anatomy.profile, look, lk, &"")
		n += 1
	var ctrl: DismembermentController = creature.get_node_or_null("DismembermentController")
	if ctrl != null:
		ctrl.cap_builder = S.build_stump_cap
	if creature.get_node_or_null("ModelSkinner") == null:
		var skinner := ModelSkinner.new()
		skinner.name = "ModelSkinner"
		creature.add_child(skinner)
	return n

## 重建一個分段的外觀（清掉舊的細節子網格）。
static func build_segment(seg: MeshInstance3D, d: BodyPartDef, profile: AnatomyProfile, look: StringName, lk: Dictionary, variant: StringName) -> void:
	for c in seg.get_children():
		if c.has_meta(DETAIL_META):
			seg.remove_child(c)
			c.free()
	var lay := PlaceholderBodyBuilder._layout_for(d, profile)
	var model := _model_for(d, lay, look, lk, variant)
	seg.mesh = model[0]
	seg.material_override = model[1]
	seg.set_meta(&"model_variant", variant)
	for det in model[2]:
		var mi := MeshInstance3D.new()
		mi.name = det[3]
		mi.mesh = det[0]
		mi.material_override = det[1]
		mi.transform = det[2]
		mi.set_meta(DETAIL_META, true)
		seg.add_child(mi)

# ---------- 部位分派 ----------

## 回傳 [主網格, 主材質, 細節陣列 [[mesh, material, Transform3D, name], ...]]
static func _model_for(d: BodyPartDef, lay: Dictionary, look: StringName, lk: Dictionary, variant: StringName) -> Array:
	var id := String(d.id)
	var h := float(lay.get("h", 0.3))
	var r := float(lay.get("r", 0.1))
	match variant:
		&"iron_arm": return _iron_arm(h, r, lk)
		&"stitched_arm": return _arm(h, r, {"skin": [S.GREY_PINK.darkened(0.25), "stitched"], "trim": S.DRIED_RED, "sutures": true}, d)
		&"reverse_leg": return _reverse_leg(h, r, {"skin": [S.GREY_PINK.darkened(0.35), "skin"], "trim": S.DRIED_RED})
		&"watcher_eye": return _eye(r, true)
		&"womb_exposed": return _womb(r, true)
	if d.functions.has("cradle"):
		return _cradle_arm(h, r, lk)
	if d.functions.has("stilt"):
		return _stilt(h, r, lk)
	if d.functions.has("tether"):
		return _cord(h, r)
	if d.functions.has("arm"):
		if id.begins_with("long_arm"):
			return _long_arm(h, r, lk)
		return _arm(h, r, lk, d)
	if d.functions.has("leg"):
		if look == &"reverse_legged" or d.functions.has("leap"):
			return _reverse_leg(h, r, lk)
		return _leg(h, r, lk)
	if id.begins_with("stalk"):
		return _eye(r, true, true)
	if id.begins_with("eye"):
		return _eye(r, false)
	match id:
		"chest", "torso": return _torso(h, r, lk, look)
		"abdomen": return _abdomen(h, r, lk)
		"neck": return _neck(h, r, lk, look)
		"head": return _head(r, lk, look)
		"jaw": return _jaw(h, r, lk)
		"womb": return _womb(r, false)
	# 未知部位（之後新增的身體模板）：保留原本的形狀但套用低多邊形材質
	return [S.sphere(r, 6, 3) if lay.get("shape") == "sphere" else S.cylinder(r, r, h), _skin(lk), []]

static func _skin(lk: Dictionary) -> Material:
	return S.material(lk["skin"][0], lk["skin"][1])

static func _cloth(lk: Dictionary) -> Material:
	return S.material(lk["cloth"][0], lk["cloth"][1])

static func _det(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, name: String = "Detail", scale: Vector3 = Vector3.ONE) -> Array:
	return [mesh, mat, MeshKit.at(pos, rot, scale), name]

# ---------- 手臂 ----------

## 手臂（含手，D4）：肩、上臂、手肘、前臂、手腕，手掌與四指一拇指。分段原點在手臂中心，關節在 +h/2。
static func _arm(h: float, r: float, lk: Dictionary, d: BodyPartDef = null) -> Array:
	var top := h * 0.5
	var k := MeshKit.new()
	var hand_len := h * 0.17
	var arm_bottom := -top + hand_len
	var span := top - arm_bottom
	k.lathe([
		Vector2(r * 0.6, top + r * 0.3), Vector2(r * 1.15, top - r * 0.2), Vector2(r * 1.0, top - span * 0.25),
		Vector2(r * 0.85, top - span * 0.48), Vector2(r * 0.95, top - span * 0.53), Vector2(r * 0.85, top - span * 0.62),
		Vector2(r * 0.62, arm_bottom + r * 0.2), Vector2(r * 0.5, arm_bottom)], 6)
	var dets := []
	var hand_mat := S.material(lk["skin"][0].darkened(0.05), "skin")
	dets.append(_det(_hand_mesh(r, hand_len, lk.get("long_fingers", false)), hand_mat, Vector3(0, arm_bottom, 0), Vector3.ZERO, "Hand"))
	if lk.get("clothed", false):
		# 袖子：比手臂略粗的布料套在上臂到手肘，袖口有陳舊金滾邊
		var sk := MeshKit.new()
		sk.lathe([Vector2(r * 1.25, top), Vector2(r * 1.3, top - span * 0.3), Vector2(r * 1.4, top - span * 0.66)], 6, Transform3D.IDENTITY, Vector2.ONE, false)
		dets.append(_det(sk.commit(), _cloth(lk), Vector3.ZERO, Vector3.ZERO, "Sleeve"))
		dets.append(_det(S.cylinder(r * 1.45, r * 1.45, r * 0.25, 6), S.material(lk["trim"], "metal"), Vector3(0, top - span * 0.66, 0), Vector3.ZERO, "Cuff"))
	if lk.get("sutures", false):
		# 縫屍者：肩膀與手肘的粗縫線（乾涸紅）
		for y in [top - r * 0.6, top - span * 0.53]:
			dets.append(_det(S.cylinder(r * 1.12, r * 1.12, r * 0.18, 6), S.material(S.DRIED_RED, "flesh"), Vector3(0, y, 0), Vector3.ZERO, "Suture"))
	return [k.commit(), _skin(lk), dets]

## 手掌＋手指（手指往下伸，掌心朝身體內側）。
static func _hand_mesh(r: float, hand_len: float, long_fingers: bool) -> ArrayMesh:
	var k := MeshKit.new()
	var palm := hand_len * 0.45
	k.box(Vector3(r * 0.55, palm, r * 1.2), MeshKit.at(Vector3(0, -palm * 0.5, 0)))
	var flen := hand_len * (0.95 if long_fingers else 0.55)
	for i in 4:
		var z := (float(i) - 1.5) * r * 0.3
		var l := flen * (1.0 - absf(float(i) - 1.3) * 0.12)
		k.box(Vector3(r * 0.22, l, r * 0.22), MeshKit.at(Vector3(0, -palm - l * 0.5, z), Vector3(0, 0, 6.0)))
	k.box(Vector3(r * 0.22, flen * 0.6, r * 0.22), MeshKit.at(Vector3(-r * 0.25, -palm * 0.6, -r * 0.65), Vector3(-35, 0, 0)))
	return k.commit()

## 鐵臂（移植器官）：分節的鐵管、陳舊金箍、鉚釘、鉤爪。
static func _iron_arm(h: float, r: float, lk: Dictionary) -> Array:
	var top := h * 0.5
	var k := MeshKit.new()
	for i in 4:
		var y0 := top - h * 0.22 * i
		k.lathe([Vector2(r * 1.05, y0), Vector2(r * 0.95, y0 - h * 0.18)], 6)
	var iron := S.material(Color("6a6866"), "metal")
	var gold := S.material(S.OLD_GOLD, "metal")
	var dets := []
	for i in 4:
		dets.append(_det(S.cylinder(r * 1.12, r * 1.12, r * 0.3, 6), gold, Vector3(0, top - h * 0.22 * i - h * 0.19, 0), Vector3.ZERO, "Band%d" % i))
	var claw := MeshKit.new()
	for i in 3:
		claw.spike(Vector2(r * 0.3, r * 0.3), h * 0.16, MeshKit.at(Vector3(0, 0, (float(i) - 1.0) * r * 0.45), Vector3(180, 0, 0)))
	dets.append(_det(claw.commit(), iron, Vector3(0, -top + h * 0.12, 0), Vector3.ZERO, "Hand"))
	return [k.commit(), iron, dets]

## 行走的母親的長臂：細長、關節突出，指尖拖地。
static func _long_arm(h: float, r: float, lk: Dictionary) -> Array:
	var top := h * 0.5
	var k := MeshKit.new()
	k.lathe([Vector2(r * 0.7, top + r * 0.4), Vector2(r * 1.2, top), Vector2(r * 0.8, top - h * 0.3),
		Vector2(r * 1.1, top - h * 0.34), Vector2(r * 0.7, top - h * 0.38), Vector2(r * 0.5, -top + h * 0.2)], 5)
	var dets := [_det(_hand_mesh(r * 1.1, h * 0.22, true), S.material(S.BONE_WHITE.darkened(0.08), "skin"), Vector3(0, -top + h * 0.2, 0), Vector3.ZERO, "Hand")]
	return [k.commit(), _skin(lk), dets]

## 搖籃臂：抱著一個裹布的「嬰兒」（奶油黃襁褓、骨瓷白小臉）。
static func _cradle_arm(h: float, r: float, lk: Dictionary) -> Array:
	var top := h * 0.5
	var k := MeshKit.new()
	k.lathe([Vector2(r * 1.1, top), Vector2(r * 0.9, top - h * 0.45), Vector2(r * 1.0, top - h * 0.5), Vector2(r * 0.7, -top + h * 0.1)], 5)
	var bundle := MeshKit.new()
	bundle.lathe([Vector2(0.0, 0.14), Vector2(0.07, 0.1), Vector2(0.09, 0.0), Vector2(0.07, -0.1), Vector2(0.0, -0.14)], 6, MeshKit.at(Vector3.ZERO, Vector3(90, 0, 0)))
	var dets := [
		_det(bundle.commit(), S.material(S.CREAM_YELLOW, "cloth"), Vector3(0, -top + 0.02, 0.07), Vector3.ZERO, "Bundle"),
		_det(S.sphere(0.045, 5, 3), S.material(S.BONE_WHITE, "skin"), Vector3(0, -top + 0.06, -0.06), Vector3.ZERO, "InfantFace"),
		_det(_hand_mesh(r, h * 0.16, false), _skin(lk), Vector3(0, -top + h * 0.1, 0), Vector3(0, 0, 40), "Hand"),
	]
	return [k.commit(), _skin(lk), dets]

# ---------- 腿 ----------

static func _leg(h: float, r: float, lk: Dictionary) -> Array:
	var top := h * 0.5
	var foot_h := h * 0.06
	var k := MeshKit.new()
	k.lathe([Vector2(r * 0.9, top + r * 0.2), Vector2(r * 1.15, top - h * 0.08), Vector2(r * 0.95, top - h * 0.42),
		Vector2(r * 0.85, top - h * 0.5), Vector2(r * 0.95, top - h * 0.6), Vector2(r * 0.6, -top + foot_h * 1.5), Vector2(r * 0.55, -top + foot_h)], 6)
	var dets := []
	var boot := S.material(S.SOOT_BLACK.lightened(0.05), "cloth") if lk.get("clothed", false) else _skin(lk)
	var fk := MeshKit.new()
	fk.box(Vector3(r * 1.1, foot_h, r * 2.6), MeshKit.at(Vector3(0, 0, -r * 0.7)))
	dets.append(_det(fk.commit(), boot, Vector3(0, -top + foot_h * 0.5, 0), Vector3.ZERO, "Foot"))
	if lk.get("clothed", false):
		var pk := MeshKit.new()
		pk.lathe([Vector2(r * 1.25, top), Vector2(r * 1.1, top - h * 0.5), Vector2(r * 1.0, -top + foot_h * 3.0)], 6, Transform3D.IDENTITY, Vector2.ONE, false)
		dets.append(_det(pk.commit(), _cloth(lk), Vector3.ZERO, Vector3.ZERO, "Trouser"))
	if lk.get("sutures", false):
		dets.append(_det(S.cylinder(r * 1.0, r * 1.0, r * 0.15, 6), S.material(S.DRIED_RED, "flesh"), Vector3(0, top - h * 0.5, 0), Vector3.ZERO, "Suture"))
	return [k.commit(), _skin(lk), dets]

## 反關節腿：大腿往前、小腿往後折、蹠骨著地，三根爪趾（逆腳者、移植的反關節腿）。
static func _reverse_leg(h: float, r: float, lk: Dictionary) -> Array:
	var top := h * 0.5
	var k := MeshKit.new()
	var knee := Vector3(0, top - h * 0.35, -h * 0.16)
	var hock := Vector3(0, -top + h * 0.28, h * 0.12)
	var ground := Vector3(0, -top + 0.03, -h * 0.02)
	_bone_between(k, Vector3(0, top, 0), knee, r * 1.2, r * 0.8)
	_bone_between(k, knee, hock, r * 0.8, r * 0.55)
	_bone_between(k, hock, ground, r * 0.55, r * 0.45)
	var dets := []
	var claw := MeshKit.new()
	for i in 3:
		claw.spike(Vector2(r * 0.35, r * 0.35), r * 2.2, MeshKit.at(Vector3((float(i) - 1.0) * r * 0.5, 0, 0), Vector3(-90 + (float(i) - 1.0) * 10.0, (float(i) - 1.0) * 20.0, 0)))
	dets.append(_det(claw.commit(), S.material(S.BONE_WHITE.darkened(0.2), "bone"), ground, Vector3.ZERO, "Foot"))
	dets.append(_det(S.sphere(r * 0.9, 5, 3), _skin(lk), knee, Vector3.ZERO, "Knee"))
	dets.append(_det(S.cylinder(0.0, r * 0.35, r * 1.4, 4), S.material(S.BONE_WHITE, "bone"), hock + Vector3(0, 0, r * 0.6), Vector3(90, 0, 0), "Spur"))
	return [k.commit(), _skin(lk), dets]

## 兩點之間的錐形肢段（車床體沿 a→b）。
static func _bone_between(k: MeshKit, a: Vector3, b: Vector3, ra: float, rb: float, sides: int = 6) -> void:
	var dir := b - a
	var len := dir.length()
	var basis := Basis(Quaternion(Vector3.DOWN, dir.normalized()))
	k.lathe([Vector2(ra, 0.0), Vector2(rb, -len)], sides, Transform3D(basis, a))

## 高蹺腿：煤灰黑的骨木、陳舊金箍、尖端像蹄。
static func _stilt(h: float, r: float, lk: Dictionary) -> Array:
	var top := h * 0.5
	var k := MeshKit.new()
	k.lathe([Vector2(r * 1.2, top), Vector2(r * 0.9, top - h * 0.3), Vector2(r * 1.05, top - h * 0.33), Vector2(r * 0.7, -top + h * 0.08), Vector2(r * 0.25, -top)], 5)
	var gold := S.material(S.OLD_GOLD, "metal")
	var dets := []
	for i in 3:
		dets.append(_det(S.cylinder(r * 1.15, r * 1.15, r * 0.4, 5), gold, Vector3(0, top - h * (0.15 + 0.25 * i), 0), Vector3.ZERO, "Ring%d" % i))
	return [k.commit(), S.material(S.SOOT_BLACK.lightened(0.08), "wood"), dets]

# ---------- 軀幹 ----------

static func _torso(h: float, r: float, lk: Dictionary, look: StringName) -> Array:
	var top := h * 0.5 + (0.0 if lk.get("fetal", false) else r * 0.6)  # 胎兒的軀幹短小
	var k := MeshKit.new()
	var flat := Vector2(1.35, 0.72) if not lk.get("fetal", false) else Vector2(1.0, 0.9)
	var gaunt: bool = lk.get("gaunt", false) or look == &"walking_mother"
	var waist := 0.72 if gaunt else 0.85
	k.lathe([Vector2(r * 0.35, top), Vector2(r * 0.95, top - r * 0.25), Vector2(r * 1.05, top - r * 0.6),
		Vector2(r * 1.0, top - h * 0.55), Vector2(r * waist, -top + r * 0.2), Vector2(r * waist * 0.9, -top)], 7, Transform3D.IDENTITY, flat)
	var dets := []
	var bone := S.material(S.BONE_WHITE.darkened(0.05), "bone")
	if gaunt or lk.get("sutures", false):
		# 肋骨：胸前的橫向骨條，從皮膚下凸出
		for i in 4:
			var y := top - r * 0.9 - i * h * 0.12
			dets.append(_det(S.box(Vector3(r * 2.2 - i * r * 0.15, r * 0.08, r * 0.1)), bone, Vector3(0, y, -r * 0.7), Vector3(0, 0, 0), "Rib%d" % i))
	if lk.get("clothed", false):
		var ck := MeshKit.new()
		ck.lathe([Vector2(r * 0.5, top + r * 0.15), Vector2(r * 1.08, top - r * 0.6), Vector2(r * 1.1, -top + r * 0.1), Vector2(r * 1.12, -top - r * 0.2)], 7, Transform3D.IDENTITY, flat * 1.04, false)
		dets.append(_det(ck.commit(), _cloth(lk), Vector3.ZERO, Vector3.ZERO, "Coat"))
		# 高領（奶油黃）與陳舊金扣環
		dets.append(_det(S.cylinder(r * 0.48, r * 0.55, r * 0.5, 6), S.material(S.CREAM_YELLOW.darkened(0.15), "cloth"), Vector3(0, top + r * 0.1, 0), Vector3.ZERO, "Collar"))
		for i in 3:
			dets.append(_det(S.box(Vector3(r * 0.22, r * 0.12, r * 0.1)), S.material(lk["trim"], "metal"), Vector3(0, top - r * 0.8 - i * h * 0.18, -r * 0.8), Vector3.ZERO, "Clasp%d" % i))
	if lk.get("robe", false):
		# 無面觀察者：胸前垂掛的骨瓷白聖帶，繡陳舊金十字
		dets.append(_det(S.box(Vector3(r * 0.5, h * 0.9, r * 0.05)), S.material(lk["trim"], "cloth"), Vector3(0, -r * 0.1, -r * 0.8), Vector3.ZERO, "Stole"))
	if lk.get("apron", false):
		# 縫屍者：沾血的皮圍裙、腰間一排手術器械
		var ak := MeshKit.new()
		ak.box(Vector3(r * 1.9, h * 1.2, r * 0.08), MeshKit.at(Vector3(0, -h * 0.25, -r * 0.78)))
		dets.append(_det(ak.commit(), S.material(Color("4a3328"), "cloth"), Vector3.ZERO, Vector3.ZERO, "Apron"))
		dets.append(_det(S.box(Vector3(r * 0.9, h * 0.35, r * 0.09)), S.material(S.DRIED_RED, "flesh"), Vector3(r * 0.3, -h * 0.4, -r * 0.83), Vector3.ZERO, "Bloodstain"))
		for i in 4:
			dets.append(_det(S.box(Vector3(r * 0.06, r * 0.5, r * 0.06)), S.material(Color("b8b4aa"), "metal"), Vector3(-r * 0.6 + i * r * 0.25, -h * 0.05, -r * 0.85), Vector3(0, 0, 8.0 * i), "Tool%d" % i))
	if lk.get("sutures", false):
		dets.append(_det(S.box(Vector3(r * 0.08, h * 1.0, r * 0.08)), S.material(S.DRIED_RED, "flesh"), Vector3(r * 0.2, 0, -r * 0.74), Vector3(0, 0, 10), "ChestSeam"))
	if lk.get("veil", false):
		# 行走的母親：從肩上垂下的奶油黃面紗、陳舊金的胸前聖物
		var vk := MeshKit.new()
		vk.lathe([Vector2(r * 0.5, top + r * 0.3), Vector2(r * 1.15, top - r * 0.5), Vector2(r * 1.3, top - h * 0.55)], 7, Transform3D.IDENTITY, Vector2(1.3, 0.85), false)
		dets.append(_det(vk.commit(), S.material(S.CREAM_YELLOW, "cloth"), Vector3(0, 0, r * 0.08), Vector3.ZERO, "Veil"))
		dets.append(_det(S.box(Vector3(r * 0.35, r * 0.5, r * 0.08)), S.material(S.OLD_GOLD, "metal", S.OLD_GOLD, 0.4), Vector3(0, top - r * 1.2, -r * 0.78), Vector3.ZERO, "Reliquary"))
	if lk.get("long_fingers", false):
		# 多手人：胸側多出的肩窩（縫合痕）
		for side in [-1.0, 1.0]:
			for i in 2:
				dets.append(_det(S.sphere(r * 0.22, 5, 2), S.material(S.GREY_PINK.darkened(0.2), "flesh"), Vector3(side * r * 1.15, top - r * 1.0 - i * h * 0.25, 0), Vector3.ZERO, "Socket"))
	if lk.get("fetal", false):
		# 未生者：臍帶殘端與透出的血管
		dets.append(_det(S.cylinder(r * 0.12, r * 0.18, r * 1.2, 5), S.material(S.DRIED_RED.lightened(0.2), "flesh", S.DRIED_RED, 0.3), Vector3(0, -top + r * 0.4, -r * 0.7), Vector3(70, 0, 0), "Cord"))
	return [k.commit(), _skin(lk), dets]

static func _abdomen(h: float, r: float, lk: Dictionary) -> Array:
	var top := h * 0.5 + r * 0.5
	var k := MeshKit.new()
	k.lathe([Vector2(r * 0.85, top), Vector2(r * 0.95, 0.0), Vector2(r * 1.15, -top + r * 0.4), Vector2(r * 0.9, -top)], 7, Transform3D.IDENTITY, Vector2(1.25, 0.8))
	var dets := []
	if lk.get("clothed", false):
		# 腰帶與下擺（短，不遮住腿的斷面）
		dets.append(_det(S.cylinder(r * 1.25, r * 1.25, r * 0.3, 7), S.material(lk["trim"].darkened(0.3), "cloth"), Vector3(0, top - r * 0.3, 0), Vector3.ZERO, "Belt", Vector3(1.2, 1, 0.85)))
		var sk := MeshKit.new()
		sk.lathe([Vector2(r * 1.2, top - r * 0.4), Vector2(r * 1.45, -top - r * 0.3)], 7, Transform3D.IDENTITY, Vector2(1.2, 0.85), false)
		dets.append(_det(sk.commit(), _cloth(lk), Vector3.ZERO, Vector3.ZERO, "Skirt"))
	elif lk.has("cloth"):
		dets.append(_det(S.cylinder(r * 1.2, r * 1.3, r * 0.9, 7), _cloth(lk), Vector3(0, -top + r * 0.5, 0), Vector3.ZERO, "Loincloth", Vector3(1.2, 1, 0.85)))
	return [k.commit(), _skin(lk), dets]

static func _neck(h: float, r: float, lk: Dictionary, look: StringName) -> Array:
	var k := MeshKit.new()
	k.lathe([Vector2(r * 0.85, h * 0.5 + r * 0.2), Vector2(r * 1.0, 0.0), Vector2(r * 1.3, -h * 0.5 - r * 0.3)], 6)
	var dets := []
	if look == &"faceless_watcher":
		# 沒有頭：頸部頂端是光滑封口的皮膚，中央一道縫合的豎縫
		dets.append(_det(S.sphere(r * 1.1, 6, 3), _skin(lk), Vector3(0, h * 0.5, 0), Vector3.ZERO, "SealedTop", Vector3(1, 0.6, 1)))
		dets.append(_det(S.box(Vector3(r * 0.12, r * 0.9, r * 0.12)), S.material(S.DRIED_RED, "flesh"), Vector3(0, h * 0.55, -r * 0.95), Vector3.ZERO, "Seam"))
	return [k.commit(), _skin(lk), dets]

## 頭：蛋形頭骨、眉骨、鼻、耳、眼窩（眼睛是獨立部位，放在眼窩前）。
static func _head(r: float, lk: Dictionary, look: StringName) -> Array:
	var k := MeshKit.new()
	k.lathe([Vector2(0.0, r * 1.05), Vector2(r * 0.7, r * 0.85), Vector2(r * 0.98, r * 0.3), Vector2(r * 0.95, -r * 0.2),
		Vector2(r * 0.75, -r * 0.65), Vector2(r * 0.45, -r * 0.95)], 7, Transform3D.IDENTITY, Vector2(0.9, 1.0))
	var dets := []
	var skin := _skin(lk)
	var dark := S.material(S.SOOT_BLACK, "plain")
	if look == &"walking_mother":
		# 瓷面具：骨瓷白平面、黑色空洞眼孔、陳舊金光環
		dets.append(_det(S.box(Vector3(r * 1.3, r * 1.5, r * 0.12)), S.material(S.BONE_WHITE.lightened(0.05), "plain"), Vector3(0, 0, -r * 0.88), Vector3.ZERO, "Mask"))
		for side in [-1.0, 1.0]:
			dets.append(_det(S.box(Vector3(r * 0.32, r * 0.16, r * 0.05)), dark, Vector3(side * r * 0.3, r * 0.15, -r * 0.95), Vector3(0, 0, side * -12.0), "MaskEye"))
		dets.append(_det(S.box(Vector3(r * 0.5, r * 0.06, r * 0.05)), S.material(S.DRIED_RED, "plain"), Vector3(0, -r * 0.45, -r * 0.95), Vector3.ZERO, "MaskMouth"))
		var halo := TorusMesh.new()
		halo.inner_radius = r * 1.25
		halo.outer_radius = r * 1.4
		halo.rings = 10
		halo.ring_segments = 3
		dets.append(_det(halo, S.material(S.OLD_GOLD, "metal", S.OLD_GOLD, 0.5), Vector3(0, r * 0.55, r * 0.75), Vector3(90, 0, 0), "Halo"))
		return [k.commit(), skin, dets]
	dets.append(_det(S.box(Vector3(r * 1.3, r * 0.18, r * 0.25)), skin, Vector3(0, r * 0.35, -r * 0.78), Vector3(-10, 0, 0), "Brow"))
	var nose := MeshKit.new()
	nose.spike(Vector2(r * 0.25, r * 0.2), r * 0.35, MeshKit.at(Vector3.ZERO, Vector3(-90, 0, 0)), Vector2(0, r * 0.12))
	dets.append(_det(nose.commit(), skin, Vector3(0, r * 0.0, -r * 0.82), Vector3.ZERO, "Nose"))
	for side in [-1.0, 1.0]:
		dets.append(_det(S.box(Vector3(r * 0.12, r * 0.35, r * 0.25)), skin, Vector3(side * r * 0.9, r * 0.05, 0), Vector3.ZERO, "Ear"))
		dets.append(_det(S.box(Vector3(r * 0.38, r * 0.22, r * 0.1)), dark, Vector3(side * r * 0.38, r * 0.18, -r * 0.8), Vector3.ZERO, "Socket"))
	if lk.get("hood", false):
		# 玩家：煤灰黑兜帽，前緣奶油黃
		var hk := MeshKit.new()
		# 兜帽往後偏，臉從前緣露出來
		hk.lathe([Vector2(0.0, r * 1.25), Vector2(r * 0.9, r * 1.0), Vector2(r * 1.05, r * 0.2), Vector2(r * 1.0, -r * 0.9)], 7, MeshKit.at(Vector3(0, r * 0.05, r * 0.5)), Vector2(1.05, 0.9), false)
		var hood_mat := S.material(lk["hood_cloth"][0], lk["hood_cloth"][1]) if lk.has("hood_cloth") else _cloth(lk)
		dets.append(_det(hk.commit(), hood_mat, Vector3.ZERO, Vector3.ZERO, "Hood"))
	if lk.get("sutures", false):
		# 頭皮上一圈縫合、兩根固定針
		dets.append(_det(S.cylinder(r * 0.97, r * 0.97, r * 0.08, 7), S.material(S.DRIED_RED, "flesh"), Vector3(0, r * 0.55, 0), Vector3(12, 0, 0), "ScalpSeam"))
		for side in [-1.0, 1.0]:
			dets.append(_det(S.cylinder(r * 0.03, r * 0.03, r * 0.6, 4), S.material(Color("b8b4aa"), "metal"), Vector3(side * r * 0.6, r * 0.7, 0), Vector3(0, 0, side * 40.0), "Pin"))
	if lk.get("fetal", false):
		# 未生者：過大的頭、半透明的薄皮、額上的血管
		dets.append(_det(S.box(Vector3(r * 0.05, r * 0.6, r * 0.05)), S.material(S.DRIED_RED, "flesh"), Vector3(r * 0.2, r * 0.6, -r * 0.75), Vector3(0, 0, 20), "Vein"))
	return [k.commit(), skin, dets]

## 下顎：U 形下巴＋一排牙齒。
static func _jaw(h: float, r: float, lk: Dictionary) -> Array:
	var k := MeshKit.new()
	k.box(Vector3(r * 2.4, h * 0.5, r * 1.6), MeshKit.at(Vector3(0, -h * 0.05, -r * 0.2)))
	var teeth := MeshKit.new()
	for i in 6:
		teeth.spike(Vector2(r * 0.25, r * 0.25), r * 0.45, MeshKit.at(Vector3((float(i) - 2.5) * r * 0.38, 0, 0)))
	var dets := [_det(teeth.commit(), S.material(S.BONE_WHITE, "bone"), Vector3(0, h * 0.2, -r * 0.9), Vector3.ZERO, "Teeth")]
	return [k.commit(), _skin(lk), dets]

## 眼睛：眼白＋虹膜。弱點（眼柄、移植的觀察者之眼）以陳舊金自發光標示（美術指導第 9 點）。
static func _eye(r: float, glowing: bool, stalk: bool = false) -> Array:
	var white := S.material(S.BONE_WHITE.lightened(0.05), "plain", S.OLD_GOLD if glowing else Color.BLACK, 1.4 if glowing else 0.0)
	var iris := S.material(S.SOOT_BLACK if not glowing else S.DRIED_RED, "plain")
	var dets := [_det(S.sphere(r * 0.5, 5, 2), iris, Vector3(0, 0, -r * 0.62), Vector3.ZERO, "Iris", Vector3(1, 1, 0.5))]
	if stalk:
		# 眼柄：從胸口伸出的肉質柄
		dets.append(_det(S.cylinder(r * 0.35, r * 0.5, r * 3.0, 5), S.material(S.GREY_PINK, "flesh"), Vector3(0, -r * 1.2, r * 0.6), Vector3(-30, 0, 0), "Stalk"))
	return [S.sphere(r, 6, 4), white, dets]

## 臍帶：扭曲、有結節的乾涸紅管，自發光標示為弱點。
static func _cord(h: float, r: float) -> Array:
	var top := h * 0.5
	var rings := []
	for i in 9:
		var t := float(i) / 8.0
		rings.append(Vector2(r * (1.0 + 0.35 * sin(t * PI * 5.0)), top - h * t))
	var k := MeshKit.new()
	k.lathe(rings, 5)
	var dets := [_det(S.sphere(r * 1.6, 5, 3), S.material(S.DRIED_RED.lightened(0.15), "flesh", S.DRIED_RED, 0.6), Vector3(0, -top, 0), Vector3.ZERO, "Knot")]
	return [k.commit(), S.material(S.DRIED_RED.lightened(0.25), "flesh", S.DRIED_RED, 0.5), dets]

## 子宮：巨大的肉囊，表面有血管與一道陳舊金縫線；暴露後（第二階段）裂開，內部發光。
static func _womb(r: float, exposed: bool) -> Array:
	var k := MeshKit.new()
	k.lathe([Vector2(0.0, r), Vector2(r * 0.7, r * 0.75), Vector2(r * 1.0, r * 0.1), Vector2(r * 0.9, -r * 0.5), Vector2(r * 0.4, -r * 0.92), Vector2(0.0, -r)], 8)
	var flesh := S.material(Color("8a3a30"), "flesh", S.DRIED_RED, 0.25 if not exposed else 0.0)
	var dets := []
	for i in 5:
		var a := float(i) / 5.0 * TAU
		dets.append(_det(S.box(Vector3(r * 0.05, r * 1.4, r * 0.05)), S.material(S.DRIED_RED.darkened(0.3), "flesh"), Vector3(cos(a) * r * 0.97, 0, sin(a) * r * 0.97), Vector3(0, -rad_to_deg(a), 15), "Vein%d" % i))
	if exposed:
		# 裂開的肉瓣與裡面發光的胎
		for i in 4:
			var a := float(i) / 4.0 * TAU + 0.4
			dets.append(_det(S.box(Vector3(r * 0.5, r * 0.9, r * 0.08)), flesh, Vector3(cos(a) * r * 0.8, r * 0.1, sin(a) * r * 0.8 - r * 0.3), Vector3(-40, -rad_to_deg(a), 0), "Petal%d" % i))
		dets.append(_det(S.sphere(r * 0.55, 6, 3), S.material(S.CREAM_YELLOW, "flesh", S.CREAM_YELLOW, 1.6), Vector3(0, 0, -r * 0.65), Vector3.ZERO, "Core"))
	else:
		dets.append(_det(S.box(Vector3(r * 0.1, r * 1.6, r * 0.1)), S.material(S.OLD_GOLD, "metal"), Vector3(0, 0, -r * 0.98), Vector3.ZERO, "Seam"))
	return [k.commit(), flesh, dets]

## 半身像（對話立繪用）：胸、頸、頭、眼、下顎，位置與遊戲中的模型相同。
static func bust(look: StringName) -> Node3D:
	var profile: AnatomyProfile = load("res://content/anatomy/walking_mother.tres" if look == &"walking_mother" else "res://content/anatomy/humanoid.tres")
	var lk: Dictionary = LOOKS.get(look, LOOKS[&"humanoid"])
	var root := Node3D.new()
	root.name = "Bust_%s" % look
	var frames := PlaceholderBodyBuilder.part_frames(profile)
	for d in profile.parts:
		var id := String(d.id)
		if d.is_internal or not (id in ["chest", "torso", "neck", "head", "eye_l", "eye_r", "jaw"]):
			continue
		var seg := MeshInstance3D.new()
		seg.name = String(d.mesh_segment)
		root.add_child(seg)
		seg.position = frames[d.id]["center"]
		build_segment(seg, d, profile, look, lk, &"")
	return root

## 一個生物外觀的總三角形數（測試用：確認仍是低多邊形）。
static func triangle_count(creature: Node) -> int:
	return WeaponModels.triangle_count(creature.find_child("Body", true, false))
