extends SceneTree
## 一次性產生：序章 50 分鐘擴充用的內容 .tres（在 growth 與 enemy 之後執行）。
##   器官：未生者的心臟、冰封之肺（都要從屍體上「完好地」摘下來）
##   技能：最初的縫線（伊格納支線的獎勵，不能用技能點學）
##   敵人：冰封的縫屍者（冷藏室的守衛，縫屍者的強化版）
##   未生者 → 可摘取未生者的心臟
## 執行：godot --headless --path . -s tools/generate_expansion_content.gd

func _init() -> void:
	var unborn_heart := _organ(&"unborn_heart", "未生者的心臟",
		"從沒出生過的心臟，一刻也停不下來。體力回復得更快，胸口也總是在發燙。", ["heart"],
		_part(18, ["circulation", "restless_heart"], {"detach": false}), 0.55, 10.0, &"heart")
	var frost_lung := _organ(&"frost_lung", "冰封之肺",
		"在冰櫃旁凍了七年的肺。吸進去的空氣很冷，血也流得很慢。", ["lungs"],
		_part(32, ["respiration", "cold_blood"], {"detach": false}), 0.5, 12.0, &"lungs")
	var s := SkillDefinition.new()
	s.id = &"first_suture"
	s.display_name = "最初的縫線"
	s.description = "伊格納解開的那卷線。緊急縫合增加的異化減半。（劇情獎勵，不能用技能點學）"
	s.cost = 0
	s.prerequisites = [&"granted_by_story"] as Array[StringName]
	s.effects = {"suture_mutation": 0.5}
	_save(s, "res://content/skills/first_suture.tres")
	var base: EnemyDefinition = load("res://content/enemies/stitcher.tres")
	var fz: EnemyDefinition = base.duplicate()
	fz.id = &"frozen_stitcher"
	fz.display_name = "冰封的縫屍者"
	fz.max_hp = 130.0
	fz.move_speed = 1.9
	fz.stagger_threshold = 18.0
	fz.xp_reward = 90
	fz.visual_scale = 1.2
	fz.sight_range = 7.0
	fz.aggression = 0.7
	fz.harvestable = [frost_lung, load("res://content/organs/stitched_arm.tres")] as Array[OrganDefinition]
	_save(fz, "res://content/enemies/frozen_stitcher.tres")
	var unborn: EnemyDefinition = load("res://content/enemies/unborn.tres")
	unborn.harvestable = [unborn_heart] as Array[OrganDefinition]
	_save(unborn, "res://content/enemies/unborn.tres")
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

func _organ(id: StringName, name: String, desc: String, slots: Array, tpl: BodyPartDef, compat: float, mut: float, harvest: StringName) -> OrganDefinition:
	var o := OrganDefinition.new()
	o.id = id
	o.display_name = name
	o.description = desc
	o.slots = PackedStringArray(slots)
	o.template = tpl
	o.origin = &"abomination"
	o.base_compatibility = compat
	o.mutation_cost = mut
	o.harvest_part = harvest
	var path := "res://content/organs/%s.tres" % id
	_save(o, path)
	return load(path)
