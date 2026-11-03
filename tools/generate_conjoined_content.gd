extends SceneTree
## 產生「連體修女」（主線精英）的身體模板與敵人定義 .tres。
## 執行：godot --headless --path . -s tools/generate_conjoined_content.gd
## 注意：重新執行會覆蓋 content/anatomy/conjoined*.tres、content/enemies/conjoined_nun.tres、nun_sister_*.tres。
##
## 身體結構（部位 id 以 _a／_b 結尾的屬於左／右兩位修女，去掉字尾就是分裂後的部位 id）：
##   pelvis（共用的骨盆，根）─ leg_l（左修女的腿）、leg_r（右修女的腿）、seam（連接兩人的縫線）
##   pelvis ─ chest_a ─ neck_a ─ head_a ─ jaw_a；chest_a ─ arm_l_a（外側）、arm_r_a（內側，抱著對方）
##   pelvis ─ chest_b ─ neck_b ─ head_b ─ jaw_b；chest_b ─ arm_r_b（外側）、arm_l_b（內側）
## 只要還有一隻內側手臂抱著，縫線就被護在身前：受擊區域停用，正面或背後的一般攻擊都打不到（戰術模式指定部位仍可以）。
## 連體時頭部不是致命部位：一顆頭被毀，那一半的手臂與下顎跟著失效（依賴），另一半拖著她繼續打。
## 兩顆頭都失效才會死。seam 被砍斷或 HP 歸零 → ConjoinedSplit 把她們分成兩隻（nun_sister_a／b）。

const V := BodyPartDef.VitalRule
const BONE_RES := {"CUT": 0.8, "PIERCE": 0.7}

func _init() -> void:
	_save_profile(_conjoined(), "res://content/anatomy/conjoined.tres")
	_save_profile(_sister(&"a"), "res://content/anatomy/conjoined_half_a.tres")
	_save_profile(_sister(&"b"), "res://content/anatomy/conjoined_half_b.tres")
	_save_def(_nun())
	_save_def(_sister_def(&"a"))
	_save_def(_sister_def(&"b"))
	quit()

func _save_profile(p: AnatomyProfile, path: String) -> void:
	var errors := p.validate()
	if not errors.is_empty():
		push_error("%s invalid: %s" % [p.id, errors])
		return
	print("saved %s (%d parts) -> %s [%s]" % [p.id, p.parts.size(), path, error_string(ResourceSaver.save(p, path))])

func _save_def(d: EnemyDefinition) -> void:
	var path := "res://content/enemies/%s.tres" % d.id
	print("saved %s -> %s [%s]" % [d.id, path, error_string(ResourceSaver.save(d, path))])

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

## 一位修女的上半身。s = "_a"／"_b"（分裂後為 ""）。conjoined 為 true 時頭不致命、手臂依賴頭。
## outer／inner：外側與內側手臂的 id（左修女的外側是 arm_l）。
func _upper(s: String, side_name: String, conjoined: bool, root_parent: StringName) -> Array[BodyPartDef]:
	var head := StringName("head" + s)
	var arm_deps := [String(head)] if conjoined else []
	var head_vital := V.NONE if conjoined else V.INSTANT_DEATH
	var outer := "arm_l" if side_name == "左" else "arm_r"
	var inner := "arm_r" if side_name == "左" else "arm_l"
	return [
		_part(StringName("chest" + s), "%s修女的胸腔" % side_name, 55, {"parent": root_parent, "res": BONE_RES, "fn": ["torso"],
			"internal": ["heart" + s, "lungs" + s]}),
		_part(StringName("heart" + s), "%s修女的心臟" % side_name, 15, {"parent": StringName("chest" + s), "is_internal": true, "fn": ["circulation"],
			"vital": V.NONE if conjoined else V.INSTANT_DEATH}),
		_part(StringName("lungs" + s), "%s修女的肺臟" % side_name, 22, {"parent": StringName("chest" + s), "is_internal": true, "fn": ["respiration"]}),
		_part(StringName("neck" + s), "%s修女的頸部" % side_name, 30 if conjoined else 20, {"parent": StringName("chest" + s), "fn": ["head_support"], "vital": head_vital}),
		# 連體時頭比較硬（頭巾下縫了皮革、斷離倍率低），不然直接砍頭就跳過整個分裂機制
		_part(head, "%s修女的頭" % side_name, 55 if conjoined else 28, {"parent": StringName("neck" + s), "detach": true,
			"sever": 0.35 if conjoined else 0.6, "armor": 4.0 if conjoined else 0.0, "res": BONE_RES,
			"fn": ["cognition"], "vital": head_vital}),
		_part(StringName("jaw" + s), "%s修女的下顎" % side_name, 10, {"parent": head, "detach": true, "fn": ["bite", "speech"], "deps": [String(head)]}),
		_part(StringName(outer + s), "%s修女的外側手臂" % side_name, 28, {"parent": StringName("chest" + s), "detach": true, "sever": 1.2,
			"fn": ["arm", "grip"], "deps": arm_deps}),
		# 內側手臂：連體時環抱著對方、擋在縫線前面
		_part(StringName(inner + s), "%s修女的內側手臂" % side_name, 22, {"parent": StringName("chest" + s), "detach": true, "sever": 1.4,
			"fn": ["arm", "grip"], "deps": arm_deps}),
	]

func _conjoined() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"conjoined"
	p.display_name = "連體修女"
	var parts: Array[BodyPartDef] = [
		_part(&"pelvis", "共用的骨盆", 80, {"res": {"CUT": 0.8, "FRACTURE": 1.1}, "fn": ["core", "posture"]}),
		_part(&"leg_l", "左修女的腿", 45, {"parent": &"pelvis", "detach": true, "sever": 0.8, "fn": ["leg", "locomotion"]}),
		_part(&"leg_r", "右修女的腿", 45, {"parent": &"pelvis", "detach": true, "sever": 0.8, "fn": ["leg", "locomotion"]}),
		# 縫線：怕刀（CUT ×1.5、斷離倍率 1.8），鈍器（粉碎、骨折）幾乎打不斷
		_part(&"seam", "連接兩人的縫線", 70, {"parent": &"pelvis", "detach": true, "sever": 1.0,
			"res": {"CUT": 1.5, "LACERATION": 1.3, "PIERCE": 1.1, "CRUSH": 0.4, "FRACTURE": 0.3}}),
	]
	parts.append_array(_upper("_a", "左", true, &"pelvis"))
	parts.append_array(_upper("_b", "右", true, &"pelvis"))
	p.parts = parts
	return p

## 分裂後的一位修女：普通人形的上半身＋撕開的腹部＋一條腿。左修女留著 leg_l，右修女留著 leg_r。
func _sister(which: StringName) -> AnatomyProfile:
	var p := AnatomyProfile.new()
	var left := which == &"a"
	p.id = StringName("conjoined_half_" + String(which))
	p.display_name = "%s修女（分裂）" % ("左" if left else "右")
	var parts: Array[BodyPartDef] = _upper("", "左" if left else "右", false, &"")
	parts.append(_part(&"abdomen", "撕開的腹部", 40, {"parent": &"chest", "fn": ["core"], "res": {"PIERCE": 1.4}}))
	var leg := &"leg_l" if left else &"leg_r"
	parts.append(_part(leg, "%s腿" % ("左" if left else "右"), 40, {"parent": &"abdomen", "detach": true, "sever": 0.8, "fn": ["leg", "locomotion"]}))
	p.parts = parts
	return p

func _attacks(ids: Array) -> Array[AttackDefinition]:
	var list: Array[AttackDefinition] = []
	for a in ids:
		list.append(load("res://content/attacks/%s.tres" % a))
	return list

func _base(id: StringName, name: String, profile: String) -> EnemyDefinition:
	var d := EnemyDefinition.new()
	d.id = id
	d.display_name = name
	d.anatomy_profile = load("res://content/anatomy/%s.tres" % profile)
	return d

## 連體時：四隻手（flurry 需要 4 個 grip）、兩張嘴，很硬、慢、攻擊密集。
func _nun() -> EnemyDefinition:
	var d := _base(&"conjoined_nun", "連體修女", "conjoined")
	d.attacks = _attacks(["flurry", "double_grab", "grab_tear", "claw", "bite"])
	d.max_hp = 240.0
	d.max_st = 160.0
	d.move_speed = 2.1
	d.sever_chance_scale = 1.0
	d.stagger_threshold = 60.0  # 精英：一般攻擊幾乎打不出僵直（不能靠連砍把她鎖死）
	d.xp_reward = 260
	d.collision_radius = 0.55
	d.collision_height = 2.0
	d.visual_scale = 1.08
	d.sight_range = 10.0
	d.sight_fov_degrees = 360.0  # 兩顆頭各看一邊
	d.needs_vision = false       # 縫住的眼睛：靠彼此的低語與聲音
	d.hearing_range = 9.0
	d.memory_seconds = 30.0
	d.preferred_range = 1.2
	d.retreat_hp_ratio = 0.0
	d.defend_chance = 0.2
	d.dodge_chance = 0.0
	d.decision_interval = 0.3
	d.patrol_radius = 0.5
	d.special_behavior = &"conjoined"
	d.dismember_react_seconds = 0.5
	d.aggression = 0.8
	d.caution = 0.1
	d.patience = 0.3
	d.flank_tendency = 0.0
	d.hit_and_run = 0.0
	d.punish_skill = 0.6
	d.adaptivity = 0.5
	d.injured_target_bias = 0.5
	d.alarm_radius = 0.0
	return d

## 分裂後：比較脆但快、會打帶跑，兩隻同時繞著你。
func _sister_def(which: StringName) -> EnemyDefinition:
	var left := which == &"a"
	var d := _base(StringName("nun_sister_" + String(which)), "%s修女" % ("左" if left else "右"), "conjoined_half_" + String(which))
	d.attacks = _attacks(["grab_tear", "double_grab", "claw", "bite"])
	d.max_hp = 110.0
	d.max_st = 100.0
	d.move_speed = 6.4  # 單腿 ×0.45 → 實際約 2.9（連體時 2.1）
	d.stagger_threshold = 16.0
	d.xp_reward = 80
	d.sight_range = 10.0
	d.sight_fov_degrees = 200.0
	d.needs_vision = false
	d.hearing_range = 8.0
	d.memory_seconds = 30.0
	d.preferred_range = 1.1
	d.retreat_hp_ratio = 0.0
	d.defend_chance = 0.0
	d.dodge_chance = 0.15
	d.decision_interval = 0.25
	d.patrol_radius = 0.5
	d.special_behavior = &""
	d.dismember_react_seconds = 0.4
	d.aggression = 0.9
	d.caution = 0.1
	d.patience = 0.2
	d.flank_tendency = 0.8  # 兩隻從兩側包夾
	d.hit_and_run = 0.6
	d.punish_skill = 0.6
	d.adaptivity = 0.4
	d.injured_target_bias = 0.5
	d.alarm_radius = 0.0
	return d
