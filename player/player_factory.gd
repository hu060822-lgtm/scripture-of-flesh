class_name PlayerFactory
extends RefCounted
## 組裝玩家角色（【暫代】膠囊體外觀）。

const PROFILE := "res://content/anatomy/humanoid.tres"
const NATURAL := ["res://content/attacks/punch.tres", "res://content/attacks/kick.tres", "res://content/attacks/bite.tres"]
const WEAPONS := ["res://content/weapons/bone_saw_cleaver.tres", "res://content/weapons/reliquary_hammer.tres", "res://content/weapons/anatomist_rapier.tres"]
## D2：玩家比敵人難斷肢，但不能太低。
const PLAYER_SEVER_SCALE := 0.5

const DEFAULT_CLASS := "res://content/classes/stitcher.tres"

## class_path 為起始職業；weapon_paths 為初始攜帶武器（空陣列 = 只帶職業武器）。
static func create(weapon_paths: Array = WEAPONS, class_path: String = DEFAULT_CLASS) -> CharacterBody3D:
	var naturals: Array[AttackDefinition] = []
	for p in NATURAL + ["res://content/attacks/leap_kick.tres"]:
		naturals.append(load(p))
	var body := PlaceholderBodyBuilder.build_creature(load(PROFILE), &"player", naturals, &"player")
	(body.get_node("AnatomyComponent") as AnatomyComponent).sever_chance_scale = PLAYER_SEVER_SCALE
	var combat: CombatComponent = body.get_node("CombatComponent")
	combat.max_hp = 160.0
	combat.max_st = 110.0
	var ctrl := PlayerController.new()
	ctrl.name = "PlayerController"
	var cls: ClassDefinition = load(class_path)
	var ws: Array[WeaponDefinition] = []
	if cls.starting_weapon != null:
		ws.append(cls.starting_weapon)
	for p in weapon_paths:
		var w: WeaponDefinition = load(p)
		if not w in ws:
			ws.append(w)
	ctrl.weapons = ws
	var prog := ProgressionComponent.new()
	prog.name = "ProgressionComponent"
	prog.class_definition = cls
	body.add_child(prog)
	var mut := MutationComponent.new()
	mut.name = "MutationComponent"
	body.add_child(mut)
	var data := PlayerData.new()
	data.name = "PlayerData"
	body.add_child(data)
	body.add_child(ctrl)
	var tac := TacticalController.new()
	tac.name = "TacticalController"
	body.add_child(tac)
	return body
