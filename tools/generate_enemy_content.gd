extends SceneTree
## 一次性產生 EnemyDefinition .tres。先執行 generate_anatomy_content 與 generate_combat_content。
## 執行：godot --headless --path . -s tools/generate_enemy_content.gd

func _init() -> void:
	_save(_def(&"stitcher", "縫屍者", "stitcher", ["claw", "grab_tear", "bite"],
		{"hp": 85, "speed": 2.4, "range": 1.1, "defend": 0.1, "dodge": 0.0, "special": &"restitch", "sight": 8.0}))
	_save(_def(&"reverse_legged", "反足者", "reverse_legged", ["lunge", "spur_kick", "claw", "pounce_bite"],
		{"hp": 70, "speed": 4.2, "range": 3.5, "defend": 0.0, "dodge": 0.3, "sight": 11.0, "stagger": 10.0}))
	_save(_def(&"faceless_watcher", "無面觀察者", "faceless", ["gaze", "lash"],
		{"hp": 65, "speed": 2.0, "range": 5.0, "defend": 0.05, "dodge": 0.15, "sight": 12.0, "fov": 220.0, "hearing": 3.5}))
	_save(_def(&"many_hands", "多手人", "multi_armed", ["flurry", "double_grab", "swipe", "bite"],
		{"hp": 110, "st": 120, "speed": 2.2, "range": 1.3, "defend": 0.3, "dodge": 0.0, "sight": 8.0, "stagger": 16.0}))
	quit()

func _save(d: EnemyDefinition) -> void:
	var path := "res://content/enemies/%s.tres" % d.id
	print("saved %s -> %s [%s]" % [d.id, path, error_string(ResourceSaver.save(d, path))])

func _def(id: StringName, name: String, profile: String, attacks: Array, o: Dictionary) -> EnemyDefinition:
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
	d.stagger_threshold = o.get("stagger", 12.0)
	return d
