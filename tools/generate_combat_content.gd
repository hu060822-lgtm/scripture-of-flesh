extends SceneTree
## 一次性產生攻擊與三種武器的 .tres（之後以編輯器編輯 .tres 為準）。
## 執行：godot --headless --path . -s tools/generate_combat_content.gd

func _init() -> void:
	# 徒手／天生攻擊
	_save(_attack(&"punch", "拳擊", {"grip": 1}, {"CRUSH": 5.0}, {"st": 10, "windup": 0.25, "recovery": 0.3, "reach": 1.2, "arc": 70, "sever": 0.0}), "res://content/attacks/punch.tres")
	_save(_attack(&"kick", "踢擊", {"leg": 1}, {"CRUSH": 7.0, "FRACTURE": 2.0}, {"st": 14, "windup": 0.35, "recovery": 0.45, "reach": 1.3, "arc": 60, "aim": 0.6, "sever": 0.0}), "res://content/attacks/kick.tres")
	_save(_attack(&"bite", "啃咬", {"bite": 1}, {"LACERATION": 6.0, "PIERCE": 2.0}, {"st": 12, "windup": 0.4, "recovery": 0.5, "reach": 0.9, "arc": 50, "sever": 0.3}), "res://content/attacks/bite.tres")

	# 敵人攻擊
	_save(_attack(&"claw", "抓擊", {"grip": 1}, {"CUT": 7.0, "LACERATION": 4.0}, {"st": 12, "windup": 0.45, "recovery": 0.5, "reach": 1.3, "arc": 80, "sever": 0.4}), "res://content/attacks/claw.tres")
	_save(_attack(&"grab_tear", "撕扯", {"grip": 2}, {"LACERATION": 12.0}, {"st": 20, "windup": 0.7, "recovery": 0.7, "reach": 1.2, "arc": 60, "sever": 0.9, "prefer": &"arm_l", "weight": 0.8}), "res://content/attacks/grab_tear.tres")
	_save(_attack(&"lunge", "反足飛撲", {"leap": 2}, {"PIERCE": 12.0, "CRUSH": 4.0}, {"st": 25, "windup": 0.65, "active": 0.3, "recovery": 0.8, "reach": 4.5, "arc": 30, "sever": 0.3, "tags": ["lunge"], "cooldown": 2.5, "weight": 1.2}), "res://content/attacks/lunge.tres")
	_save(_attack(&"spur_kick", "骨刺踢", {"leg": 1}, {"PIERCE": 8.0, "CUT": 3.0}, {"st": 14, "windup": 0.4, "recovery": 0.5, "reach": 1.4, "arc": 70, "aim": 0.7, "sever": 0.4}), "res://content/attacks/spur_kick.tres")
	_save(_attack(&"pounce_bite", "爬行撲咬", {"bite": 1}, {"LACERATION": 9.0, "PIERCE": 3.0}, {"st": 15, "windup": 0.5, "active": 0.2, "recovery": 0.7, "reach": 1.6, "arc": 50, "aim": 0.5, "sever": 0.4, "tags": ["lunge"], "cooldown": 1.5}), "res://content/attacks/pounce_bite.tres")
	_save(_attack(&"gaze", "凝視", {"vision": 1}, {"BURN": 6.0, "MUTATION": 4.0}, {"st": 15, "windup": 0.9, "active": 0.15, "recovery": 0.6, "reach": 7.0, "arc": 24, "sever": 0.0, "cooldown": 1.5, "weight": 1.5}), "res://content/attacks/gaze.tres")
	_save(_attack(&"lash", "長臂鞭擊", {"grip": 1}, {"LACERATION": 7.0, "CRUSH": 3.0}, {"st": 12, "windup": 0.5, "recovery": 0.5, "reach": 2.2, "arc": 100, "sever": 0.3}), "res://content/attacks/lash.tres")
	_save(_attack(&"flurry", "千手亂擊", {"grip": 4}, {"CUT": 14.0, "LACERATION": 4.0}, {"st": 24, "windup": 0.6, "active": 0.2, "recovery": 0.7, "reach": 1.6, "arc": 120, "sever": 0.6, "weight": 1.0}), "res://content/attacks/flurry.tres")
	_save(_attack(&"double_grab", "雙手擒抓", {"grip": 2}, {"LACERATION": 10.0, "CRUSH": 3.0}, {"st": 18, "windup": 0.55, "recovery": 0.6, "reach": 1.4, "arc": 80, "sever": 0.7}), "res://content/attacks/double_grab.tres")
	_save(_attack(&"swipe", "單手揮擊", {"grip": 1}, {"CUT": 7.0}, {"st": 10, "windup": 0.4, "recovery": 0.45, "reach": 1.4, "arc": 90, "sever": 0.4}), "res://content/attacks/swipe.tres")

	# 骨鋸斧：切割為主，高出血、高斷肢
	var cleaver := _weapon(&"bone_saw_cleaver", "骨鋸斧", &"cleaver", {"CUT": 16.0, "LACERATION": 4.0}, 1.5, 0.1, 1.2, 1)
	cleaver.light_attack = _attack(&"cleaver_light", "橫劈", {}, {}, {"weapon": true, "st": 18, "windup": 0.35, "active": 0.1, "recovery": 0.4, "reach": 1.8, "arc": 100})
	cleaver.heavy_attack = _attack(&"cleaver_heavy", "斷骨下劈", {}, {}, {"weapon": true, "st": 25, "ap": 25, "windup": 0.7, "recovery": 0.6, "reach": 1.9, "arc": 50, "scale": 1.8, "sever": 1.5})
	_save(cleaver, "res://content/weapons/bone_saw_cleaver.tres")

	# 聖骸錘：粉碎與骨折，雙手武器，斷肢能力低
	var hammer := _weapon(&"reliquary_hammer", "聖骸錘", &"hammer", {"CRUSH": 14.0, "FRACTURE": 10.0}, 0.6, 0.3, 0.6, 2)
	hammer.light_attack = _attack(&"hammer_light", "重擊", {}, {}, {"weapon": true, "st": 26, "windup": 0.55, "active": 0.12, "recovery": 0.6, "reach": 2.0, "arc": 120, "stagger": -4.0})
	hammer.heavy_attack = _attack(&"hammer_heavy", "碎骨禱", {}, {"FRACTURE": 15.0}, {"weapon": true, "st": 30, "ap": 30, "windup": 0.9, "recovery": 0.7, "reach": 2.0, "arc": 80, "scale": 1.6})
	_save(hammer, "res://content/weapons/reliquary_hammer.tres")

	# 解剖刺劍：穿刺，貫穿內臟，破甲
	var rapier := _weapon(&"anatomist_rapier", "解剖刺劍", &"rapier", {"PIERCE": 12.0, "CUT": 4.0}, 0.4, 0.5, 1.0, 1)
	rapier.light_attack = _attack(&"rapier_light", "刺擊", {}, {}, {"weapon": true, "st": 12, "windup": 0.2, "active": 0.08, "recovery": 0.3, "reach": 2.2, "arc": 40})
	rapier.heavy_attack = _attack(&"rapier_heavy", "探臟刺", {}, {}, {"weapon": true, "st": 18, "ap": 20, "windup": 0.45, "recovery": 0.5, "reach": 2.4, "arc": 25, "scale": 2.0, "pen": 0.5})
	_save(rapier, "res://content/weapons/anatomist_rapier.tres")
	quit()

func _save(r: Resource, path: String) -> void:
	print("saved %s -> %s [%s]" % [r.id, path, error_string(ResourceSaver.save(r, path))])

func _attack(id: StringName, name: String, req: Dictionary, dmg: Dictionary, o: Dictionary) -> AttackDefinition:
	var a := AttackDefinition.new()
	a.id = id
	a.display_name = name
	a.required_capabilities = req
	a.damage = dmg
	a.requires_weapon = o.get("weapon", false)
	a.st_cost = o.get("st", 15.0)
	a.ap_cost = o.get("ap", 0.0)
	a.windup = o.get("windup", 0.4)
	a.active = o.get("active", 0.1)
	a.recovery = o.get("recovery", 0.4)
	a.reach = o.get("reach", 1.6)
	a.arc_degrees = o.get("arc", 90.0)
	a.aim_height = o.get("aim", 1.3)
	a.damage_scale = o.get("scale", 1.0)
	a.sever_power = o.get("sever", 1.0)
	a.armor_penetration_bonus = o.get("pen", 0.0)
	a.stagger_threshold_bonus = o.get("stagger", 0.0)
	a.preferred_target_part = o.get("prefer", &"")
	a.tags = PackedStringArray(o.get("tags", []))
	a.cooldown = o.get("cooldown", 0.0)
	a.ai_weight = o.get("weight", 1.0)
	return a

func _weapon(id: StringName, name: String, type: StringName, dmg: Dictionary, sever: float, pen: float, bleed: float, grip: int) -> WeaponDefinition:
	var w := WeaponDefinition.new()
	w.id = id
	w.display_name = name
	w.weapon_type = type
	w.damage = dmg
	w.sever_power = sever
	w.armor_penetration = pen
	w.bleed_multiplier = bleed
	w.required_grip = grip
	return w
