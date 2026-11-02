extends SceneTree
## 一次性產生初始身體模板 .tres（之後以 Godot 編輯器直接編輯 .tres 為準）。
## 執行：godot --headless --path . -s tools/generate_anatomy_content.gd
## 注意：重新執行會覆蓋 content/anatomy/ 下的同名檔案。

const V := BodyPartDef.VitalRule

func _init() -> void:
	_save(_humanoid(), "res://content/anatomy/humanoid.tres")
	_save(_multi_armed(), "res://content/anatomy/multi_armed.tres")
	_save(_stitcher(), "res://content/anatomy/stitcher.tres")
	_save(_reverse_legged(), "res://content/anatomy/reverse_legged.tres")
	_save(_faceless(), "res://content/anatomy/faceless.tres")
	quit()

func _save(p: AnatomyProfile, path: String) -> void:
	var errors := p.validate()
	if not errors.is_empty():
		push_error("%s invalid: %s" % [p.id, errors])
		return
	var err := ResourceSaver.save(p, path)
	print("saved %s (%d parts) -> %s [%s]" % [p.id, p.parts.size(), path, error_string(err)])

func _part(id: StringName, name: String, hp: float, opts: Dictionary = {}) -> BodyPartDef:
	var d := BodyPartDef.new()
	d.id = id
	d.display_name = name
	d.max_hp = hp
	d.armor = opts.get("armor", 0.0)
	d.resistances = opts.get("res", {})
	d.functions = PackedStringArray(opts.get("fn", []))
	d.detachable = opts.get("detach", false)
	d.parent_id = opts.get("parent", &"")
	d.dependencies = PackedStringArray(opts.get("deps", []))
	d.internal_parts = PackedStringArray(opts.get("internal", []))
	d.is_internal = opts.get("is_internal", false)
	d.vital = opts.get("vital", V.NONE)
	d.sever_multiplier = opts.get("sever", 1.0)
	d.bone_name = opts.get("bone", StringName(id))
	d.mesh_segment = StringName("seg_" + String(id))
	return d

## 人形基本模板：指令要求的 14 個部位。
func _humanoid_parts() -> Array[BodyPartDef]:
	var bone_res := {"CUT": 0.8, "PIERCE": 0.7}  # 有骨骼保護的部位
	return [
		_part(&"chest", "胸腔", 60, {"res": bone_res, "fn": ["torso"], "internal": ["heart", "lungs"]}),
		_part(&"heart", "心臟", 15, {"parent": &"chest", "is_internal": true, "fn": ["circulation"], "vital": V.INSTANT_DEATH}),
		_part(&"lungs", "肺臟", 25, {"parent": &"chest", "is_internal": true, "fn": ["respiration"], "vital": V.COUNTDOWN}),
		_part(&"spine", "脊椎", 40, {"parent": &"chest", "fn": ["posture"], "res": {"CUT": 0.5, "FRACTURE": 1.2}}),
		_part(&"abdomen", "腹部", 45, {"parent": &"chest", "fn": ["core"], "res": {"PIERCE": 1.3}}),
		_part(&"neck", "頸部", 20, {"parent": &"chest", "fn": ["head_support"], "vital": V.INSTANT_DEATH}),
		_part(&"head", "頭部", 30, {"parent": &"neck", "detach": true, "sever": 0.5, "res": bone_res, "fn": ["cognition"], "vital": V.INSTANT_DEATH}),
		_part(&"eye_l", "左眼", 5, {"parent": &"head", "detach": true, "sever": 2.0, "fn": ["vision"], "deps": ["head"]}),
		_part(&"eye_r", "右眼", 5, {"parent": &"head", "detach": true, "sever": 2.0, "fn": ["vision"], "deps": ["head"]}),
		_part(&"jaw", "下顎", 12, {"parent": &"head", "detach": true, "fn": ["bite", "speech"], "deps": ["head"]}),
		_part(&"arm_l", "左臂", 30, {"parent": &"chest", "detach": true, "fn": ["arm", "grip", "grip_l"]}),
		_part(&"arm_r", "右臂", 30, {"parent": &"chest", "detach": true, "fn": ["arm", "grip", "grip_r"]}),
		_part(&"leg_l", "左腿", 40, {"parent": &"abdomen", "detach": true, "sever": 0.8, "fn": ["leg", "locomotion"], "deps": ["spine"]}),
		_part(&"leg_r", "右腿", 40, {"parent": &"abdomen", "detach": true, "sever": 0.8, "fn": ["leg", "locomotion"], "deps": ["spine"]}),
	]

func _humanoid() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"humanoid"
	p.display_name = "人形（基本）"
	p.parts = _humanoid_parts()
	return p

## 多手人：人形去掉雙臂，改為左右各三條手臂。每條手臂獨立提供 grip。
func _multi_armed() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"multi_armed"
	p.display_name = "多手人"
	var parts: Array[BodyPartDef] = []
	for d in _humanoid_parts():
		if d.id != &"arm_l" and d.id != &"arm_r":
			parts.append(d)
	for i in range(1, 4):
		parts.append(_part(StringName("arm_l%d" % i), "左臂%d" % i, 22, {"parent": &"chest", "detach": true, "sever": 1.2, "fn": ["arm", "grip"]}))
		parts.append(_part(StringName("arm_r%d" % i), "右臂%d" % i, 22, {"parent": &"chest", "detach": true, "sever": 1.2, "fn": ["arm", "grip"]}))
	p.parts = parts
	return p

## 縫屍者：人形，但全身是縫合線拼成的。四肢縫線處容易斷（斷肢倍率高），胸腔有縫合皮甲。
func _stitcher() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"stitcher"
	p.display_name = "縫屍者"
	var parts: Array[BodyPartDef] = []
	for d in _humanoid_parts():
		if d.id in [&"arm_l", &"arm_r", &"leg_l", &"leg_r", &"jaw"]:
			d.sever_multiplier *= 1.6
			d.max_hp *= 0.85
		if d.id == &"chest":
			d.armor = 2.0
		parts.append(d)
	p.parts = parts
	return p

## 反足者：膝蓋反折的雙腿是牠的武器（leap 能力：飛撲），腿很硬但被破壞後只能爬行。
func _reverse_legged() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"reverse_legged"
	p.display_name = "反足者"
	var parts: Array[BodyPartDef] = []
	for d in _humanoid_parts():
		if d.id in [&"leg_l", &"leg_r"]:
			d.max_hp = 55.0
			d.armor = 3.0
			d.sever_multiplier = 0.7
			d.functions = PackedStringArray(["leg", "locomotion", "leap"])
		elif d.id in [&"arm_l", &"arm_r"]:
			d.max_hp = 18.0  # 萎縮的手臂
		parts.append(d)
	p.parts = parts
	return p

## 無面觀察者：沒有頭、眼、下顎。胸口長出四根眼柄提供視覺，失去全部眼柄後只能靠聽覺。
func _faceless() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"faceless"
	p.display_name = "無面觀察者"
	var parts: Array[BodyPartDef] = []
	for d in _humanoid_parts():
		if d.id in [&"head", &"eye_l", &"eye_r", &"jaw"]:
			continue
		if d.id == &"neck":
			d.vital = V.NONE  # 沒有頭可以支撐
			d.functions = PackedStringArray()
		if d.id in [&"arm_l", &"arm_r"]:
			d.max_hp = 26.0
		parts.append(d)
	for i in range(1, 5):
		parts.append(_part(StringName("stalk_%d" % i), "眼柄%d" % i, 8, {"parent": &"chest", "detach": true, "sever": 1.8, "fn": ["vision"]}))
	p.parts = parts
	return p
