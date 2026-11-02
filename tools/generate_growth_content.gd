extends SceneTree
## 一次性產生：器官、職業、技能、異化階段 .tres。
## 執行順序：anatomy → combat → growth → enemy。

func _init() -> void:
	_organs()
	_skills()
	_mutation()
	_classes()
	quit()

func _save(r: Resource, path: String) -> void:
	print("saved %s -> %s [%s]" % [r.get("id"), path, error_string(ResourceSaver.save(r, path))])

func _part(hp: float, fns: Array, opts: Dictionary = {}) -> BodyPartDef:
	var d := BodyPartDef.new()
	d.max_hp = hp
	d.functions = PackedStringArray(fns)
	d.armor = opts.get("armor", 0.0)
	d.resistances = opts.get("res", {})
	d.detachable = opts.get("detach", true)
	d.sever_multiplier = opts.get("sever", 1.0)
	return d

func _organ(id: StringName, name: String, desc: String, slots: Array, tpl: BodyPartDef, origin: StringName, compat: float, mut: float, harvest: StringName = &"", min_tec: int = 0) -> void:
	var o := OrganDefinition.new()
	o.id = id
	o.display_name = name
	o.description = desc
	o.slots = PackedStringArray(slots)
	o.template = tpl
	o.origin = origin
	o.base_compatibility = compat
	o.mutation_cost = mut
	o.harvest_part = harvest
	o.min_tec = min_tec
	_save(o, "res://content/organs/%s.tres" % id)

func _organs() -> void:
	_organ(&"stitched_arm", "縫屍者的手臂", "縫線密布的手臂，比人類的更耐斬，但不完全聽使喚。", ["arm_l", "arm_r"],
		_part(38, ["arm", "grip"], {"armor": 1.0, "res": {"CUT": 0.8}, "sever": 1.3}), &"abomination", 0.7, 6.0, &"arm_r")
	_organ(&"reverse_leg", "反足", "膝蓋反折的腿。能讓你飛踢，走路時卻總像在逃跑。", ["leg_l", "leg_r"],
		_part(55, ["leg", "locomotion", "leap"], {"armor": 3.0, "sever": 0.7}), &"abomination", 0.45, 14.0, &"leg_l")
	_organ(&"watcher_eye", "觀察者之眼", "從眼柄上摘下的眼球。看得更遠，也看見不該看的東西。", ["eye_l", "eye_r"],
		_part(8, ["vision", "dark_sight"], {"sever": 1.5}), &"abomination", 0.55, 10.0, &"stalk_1")
	_organ(&"many_hands_heart", "多手人的心臟", "能同時供血給六條手臂的心臟。你的血流得更慢了。", ["heart"],
		_part(30, ["circulation", "strong_heart"], {"detach": false}), &"abomination", 0.5, 12.0, &"heart")
	_organ(&"iron_arm", "鐵製義肢", "教會工坊的機械手臂。不會被排斥，也不會異化，但需要技術才能接上。", ["arm_l", "arm_r"],
		_part(45, ["arm", "grip"], {"armor": 6.0, "res": {"CUT": 0.5, "BURN": 1.3, "MUTATION": 0.0}, "sever": 0.6}), &"mechanical", 1.0, 0.0, &"", 12)

func _skill(id: StringName, name: String, desc: String, effects: Dictionary, prereq: Array = [], cost: int = 1) -> void:
	var s := SkillDefinition.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.effects = effects
	var pre: Array[StringName] = []
	for p in prereq:
		pre.append(StringName(p))
	s.prerequisites = pre
	s.cost = cost
	_save(s, "res://content/skills/%s.tres" % id)

func _skills() -> void:
	_skill(&"anatomical_insight", "解剖學洞察", "命中時多獲得 2 AP。", {"ap_gain": 2.0})
	_skill(&"deep_insight", "深層洞察", "命中時再多獲得 3 AP。", {"ap_gain": 3.0}, ["anatomical_insight"])
	_skill(&"iron_discipline", "鐵之紀律", "異化抗性 +10%。", {"mutation_resist": 0.1})
	_skill(&"flesh_communion", "肉之交感", "器官相容性 +15%。", {"compatibility": 0.15})
	_skill(&"butchers_eye", "屠夫之眼", "骨鋸斧傷害 +10%。", {"damage_scale:cleaver": 0.1})
	_skill(&"hammer_devotion", "聖錘奉獻", "聖骸錘傷害 +12%。", {"damage_scale:hammer": 0.12})
	_skill(&"quick_suture", "快速縫合", "緊急縫合時間縮短 30%。", {"suture_speed": 0.3})
	_skill(&"bleed_control", "止血術", "出血造成的 HP 損失降低 30%。", {"bleed_resist": 0.3}, ["quick_suture"])

func _stage(id: StringName, name: String, threshold: float, desc: String, effects: Dictionary, flag: StringName) -> void:
	var s := MutationStage.new()
	s.id = id
	s.display_name = name
	s.threshold = threshold
	s.description = desc
	s.effects = effects
	s.story_flag = flag
	_save(s, "res://content/mutation/%s.tres" % id)

func _mutation() -> void:
	_stage(&"stage_1_uncanny_sense", "異樣感知", 25.0, "你開始「看見」別人體內的器官在跳動。戰術介面會顯示敵人內臟的狀態與剩餘的攻擊手段。有些人開始迴避你的視線。",
		{"anatomical_sight": 1.0}, &"mutation_25")
	_stage(&"stage_2_bone_spurs", "骨刺增生", 50.0, "骨頭從皮膚下頂出。獲得「骨刺穿出」攻擊，體力上限 +10。祭壇的修復會讓骨刺長得更快（每次休息異化 +2）。",
		{"grant_attack:bone_spur": 1.0, "max_st": 10.0, "heal_penalty": 2.0}, &"mutation_50")
	_stage(&"stage_3_autonomous_flesh", "肉身自律", 75.0, "你的肉體不再等你下令。受傷部位每秒自行再生 0.4 HP。你偶爾會發現手在你沒注意時動過。",
		{"part_regen": 0.4}, &"mutation_75")

func _class(id: StringName, name: String, desc: String, stats: Dictionary, weapon: String, skills: Array, items: Dictionary = {}) -> void:
	var c := ClassDefinition.new()
	c.id = id
	c.display_name = name
	c.description = desc
	var cs := CharacterStats.new()
	cs.load_dict(stats)
	c.stats = cs
	c.starting_weapon = load("res://content/weapons/%s.tres" % weapon)
	var sk: Array[StringName] = []
	for s in skills:
		sk.append(StringName(s))
	c.starting_skills = sk
	c.starting_items = items
	_save(c, "res://content/classes/%s.tres" % id)

func _classes() -> void:
	_class(&"anatomist", "解剖師", "熟知人體每一條縫隙。擅長指定部位與穿刺。", {"STR": 9, "DEX": 11, "VIT": 9, "PER": 14, "WIL": 10, "TEC": 12}, "anatomist_rapier", ["anatomical_insight"], {"suture_kit": 1})
	_class(&"prosthetic_knight", "義體騎士", "以機械取代血肉的騎士。耐打，技術足以接上義肢。", {"STR": 12, "DEX": 8, "VIT": 13, "PER": 9, "WIL": 11, "TEC": 13}, "reliquary_hammer", ["iron_discipline"], {"suture_kit": 1})
	_class(&"flesh_witch", "肉巫", "與異化共處的人。器官相容性高，意志堅定。", {"STR": 8, "DEX": 10, "VIT": 9, "PER": 11, "WIL": 14, "TEC": 12}, "anatomist_rapier", ["flesh_communion"], {"suture_kit": 1})
	_class(&"mutilator", "刑體師", "以斬斷為業。斷肢就是他的語言。", {"STR": 13, "DEX": 12, "VIT": 11, "PER": 10, "WIL": 8, "TEC": 9}, "bone_saw_cleaver", ["butchers_eye"], {"suture_kit": 1})
	_class(&"stitcher", "縫合者", "把破碎的身體縫回去的人，包括自己的。", {"STR": 10, "DEX": 10, "VIT": 11, "PER": 10, "WIL": 10, "TEC": 14}, "bone_saw_cleaver", ["quick_suture"], {"suture_kit": 3})
