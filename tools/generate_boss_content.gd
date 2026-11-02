extends SceneTree
## 一次性產生 Boss「行走的母親」與召喚物「未生者」的身體、攻擊、敵人資料。
## 先執行 generate_anatomy_content、generate_combat_content、generate_growth_content。
## 執行：godot --headless --path . -s tools/generate_boss_content.gd

const V := BodyPartDef.VitalRule

func _init() -> void:
	_save_profile(_mother(), "res://content/anatomy/walking_mother.tres")
	_save_profile(_unborn(), "res://content/anatomy/unborn.tres")
	var exposed := _womb(true)
	print("saved womb_exposed [%s]" % error_string(ResourceSaver.save(exposed, "res://content/boss/womb_exposed.tres")))

	_save(_attack(&"stilt_stomp", "高蹺踐踏", {"stilt": 2}, {"CRUSH": 16.0, "FRACTURE": 8.0}, {"st": 20, "windup": 0.8, "active": 0.15, "recovery": 0.7, "reach": 2.6, "arc": 110, "aim": 0.4, "sever": 0.3, "weight": 1.0}), "res://content/attacks/stilt_stomp.tres")
	_save(_attack(&"cradle_crush", "懷抱擠壓", {"cradle": 2}, {"CRUSH": 14.0, "LACERATION": 6.0}, {"st": 24, "windup": 0.9, "active": 0.2, "recovery": 0.8, "reach": 1.9, "arc": 70, "aim": 1.3, "sever": 0.8, "weight": 1.2}), "res://content/attacks/cradle_crush.tres")
	_save(_attack(&"mother_lash", "長臂鞭笞", {"grip": 1}, {"LACERATION": 9.0, "CRUSH": 4.0}, {"st": 14, "windup": 0.6, "active": 0.12, "recovery": 0.6, "reach": 3.2, "arc": 120, "aim": 1.2, "sever": 0.4}), "res://content/attacks/mother_lash.tres")
	_save(_attack(&"birth_scream", "產聲", {"scream": 1}, {"CRUSH": 4.0, "MUTATION": 8.0}, {"st": 10, "windup": 1.0, "active": 0.3, "recovery": 1.0, "reach": 4.5, "arc": 360, "aim": 1.3, "sever": 0.0, "cooldown": 10.0, "weight": 0.6, "stagger": 6.0}), "res://content/attacks/birth_scream.tres")
	_save(_attack(&"crawl_grasp", "爬行抓握", {"arm": 1}, {"LACERATION": 10.0, "CRUSH": 3.0}, {"st": 14, "windup": 0.55, "active": 0.1, "recovery": 0.55, "reach": 2.2, "arc": 90, "aim": 0.8, "sever": 0.6}), "res://content/attacks/crawl_grasp.tres")

	var mother := _enemy(&"walking_mother", "行走的母親", "walking_mother",
		["stilt_stomp", "cradle_crush", "mother_lash", "birth_scream", "crawl_grasp"],
		{"hp": 620, "st": 300, "speed": 1.9, "range": 2.4, "defend": 0.0, "dodge": 0.0, "special": &"boss",
		 "sight": 14.0, "fov": 220.0, "hearing": 6.0, "stagger": 45.0, "xp": 500, "retreat": 0.0,
		 "react": 1.2, "radius": 0.85, "height": 3.9, "sever_scale": 0.8, "memory": 30.0})
	_save(mother, "res://content/enemies/walking_mother.tres")
	var unborn := _enemy(&"unborn", "未生者", "unborn", ["bite", "claw"],
		{"hp": 28, "st": 60, "speed": 5.5, "range": 0.9, "defend": 0.0, "dodge": 0.0, "sight": 9.0, "fov": 360.0,
		 "hearing": 5.0, "stagger": 6.0, "xp": 5, "radius": 0.2, "height": 0.8, "scale": 0.45, "sever_scale": 1.4, "memory": 20.0})
	_save(unborn, "res://content/enemies/unborn.tres")
	quit()

func _save_profile(p: AnatomyProfile, path: String) -> void:
	var errors := p.validate()
	if not errors.is_empty():
		push_error("%s invalid: %s" % [p.id, errors])
		return
	print("saved %s (%d parts) -> %s [%s]" % [p.id, p.parts.size(), path, error_string(ResourceSaver.save(p, path))])

func _save(r: Resource, path: String) -> void:
	print("saved %s -> %s [%s]" % [r.id, path, error_string(ResourceSaver.save(r, path))])

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
	d.bone_name = StringName(id)
	d.mesh_segment = StringName("seg_" + String(id))
	return d

## 子宮：第一階段被骨盆甲包覆（高護甲、抗切割穿刺）；跪下後護甲剝落，弱點暴露。
func _womb(exposed: bool) -> BodyPartDef:
	if exposed:
		return _part(&"womb", "子宮（暴露）", 200, {"parent": &"torso", "armor": 0.0, "res": {"PIERCE": 1.5, "CUT": 1.3},
			"fn": ["birth"], "vital": V.INSTANT_DEATH})
	return _part(&"womb", "子宮（骨盆甲）", 200, {"parent": &"torso", "armor": 10.0, "res": {"PIERCE": 0.5, "CUT": 0.5, "CRUSH": 0.7},
		"fn": ["birth"], "vital": V.INSTANT_DEATH})

func _mother() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"walking_mother"
	p.display_name = "行走的母親"
	var parts: Array[BodyPartDef] = [
		_part(&"torso", "軀幹", 180, {"armor": 3.0, "res": {"CUT": 0.8}, "fn": ["torso"], "internal": ["heart"]}),
		_part(&"heart", "心臟", 80, {"parent": &"torso", "is_internal": true, "fn": ["circulation"], "vital": V.INSTANT_DEATH}),
		_part(&"neck", "頸部", 60, {"parent": &"torso", "fn": ["head_support"]}),
		_part(&"head", "覆面頭", 90, {"parent": &"neck", "armor": 4.0, "detach": true, "sever": 0.3, "fn": ["cognition", "vision", "scream"], "vital": V.INSTANT_DEATH}),
		_womb(false),
		_part(&"cradle_l", "左抱臂", 70, {"parent": &"torso", "detach": true, "sever": 0.8, "fn": ["arm", "cradle"]}),
		_part(&"cradle_r", "右抱臂", 70, {"parent": &"torso", "detach": true, "sever": 0.8, "fn": ["arm", "cradle"]}),
		_part(&"long_arm_l", "左長臂", 55, {"parent": &"torso", "detach": true, "fn": ["arm", "grip"]}),
		_part(&"long_arm_r", "右長臂", 55, {"parent": &"torso", "detach": true, "fn": ["arm", "grip"]}),
	]
	for i in range(1, 5):
		parts.append(_part(StringName("stilt_%d" % i), "高蹺腿%d" % i, 80, {"parent": &"womb", "armor": 2.0, "detach": true,
			"sever": 0.9, "res": {"FRACTURE": 1.3}, "fn": ["leg", "locomotion", "stilt"]}))
	for i in range(1, 4):
		parts.append(_part(StringName("cord_%d" % i), "臍帶%d" % i, 30, {"parent": &"womb", "detach": true, "sever": 1.6,
			"res": {"CUT": 1.3}, "fn": ["tether"]}))
	p.parts = parts
	return p

## 未生者：沒有腿、在地上爬的半成形胎兒。
func _unborn() -> AnatomyProfile:
	var p := AnatomyProfile.new()
	p.id = &"unborn"
	p.display_name = "未生者"
	p.parts = [
		_part(&"chest", "軀體", 30, {"fn": ["torso"], "internal": ["heart"]}),
		_part(&"heart", "心臟", 10, {"parent": &"chest", "is_internal": true, "fn": ["circulation"], "vital": V.INSTANT_DEATH}),
		_part(&"head", "頭部", 16, {"parent": &"chest", "detach": true, "sever": 1.2, "fn": ["cognition", "vision"], "vital": V.INSTANT_DEATH}),
		_part(&"jaw", "下顎", 8, {"parent": &"head", "detach": true, "fn": ["bite"], "deps": ["head"]}),
		_part(&"arm_l", "左臂", 12, {"parent": &"chest", "detach": true, "sever": 1.5, "fn": ["arm", "grip"]}),
		_part(&"arm_r", "右臂", 12, {"parent": &"chest", "detach": true, "sever": 1.5, "fn": ["arm", "grip"]}),
	]
	return p

func _attack(id: StringName, name: String, req: Dictionary, dmg: Dictionary, o: Dictionary) -> AttackDefinition:
	var a := AttackDefinition.new()
	a.id = id
	a.display_name = name
	a.required_capabilities = req
	a.damage = dmg
	a.st_cost = o.get("st", 15.0)
	a.windup = o.get("windup", 0.4)
	a.active = o.get("active", 0.1)
	a.recovery = o.get("recovery", 0.4)
	a.reach = o.get("reach", 1.6)
	a.arc_degrees = o.get("arc", 90.0)
	a.aim_height = o.get("aim", 1.3)
	a.sever_power = o.get("sever", 1.0)
	a.stagger_threshold_bonus = o.get("stagger", 0.0)
	a.cooldown = o.get("cooldown", 0.0)
	a.ai_weight = o.get("weight", 1.0)
	return a

func _enemy(id: StringName, name: String, profile: String, attacks: Array, o: Dictionary) -> EnemyDefinition:
	var d := EnemyDefinition.new()
	d.id = id
	d.display_name = name
	d.anatomy_profile = load("res://content/anatomy/%s.tres" % profile)
	var list: Array[AttackDefinition] = []
	for a in attacks:
		list.append(load("res://content/attacks/%s.tres" % a))
	d.attacks = list
	d.max_hp = o.get("hp", 80.0)
	d.max_st = o.get("st", 80.0)
	d.move_speed = o.get("speed", 2.6)
	d.preferred_range = o.get("range", 1.4)
	d.defend_chance = o.get("defend", 0.15)
	d.dodge_chance = o.get("dodge", 0.1)
	d.special_behavior = o.get("special", &"")
	d.sight_range = o.get("sight", 9.0)
	d.sight_fov_degrees = o.get("fov", 140.0)
	d.hearing_range = o.get("hearing", 3.0)
	d.memory_seconds = o.get("memory", 4.0)
	d.stagger_threshold = o.get("stagger", 12.0)
	d.xp_reward = o.get("xp", 40)
	d.retreat_hp_ratio = o.get("retreat", 0.15)
	d.dismember_react_seconds = o.get("react", 0.8)
	d.collision_radius = o.get("radius", 0.32)
	d.collision_height = o.get("height", 1.8)
	d.visual_scale = o.get("scale", 1.0)
	d.sever_chance_scale = o.get("sever_scale", 1.0)
	return d
