class_name PlayerFactory
extends RefCounted
## 組裝玩家角色（【暫代】膠囊體外觀）。

const PROFILE := "res://content/anatomy/humanoid.tres"
const NATURAL := ["res://content/attacks/punch.tres", "res://content/attacks/kick.tres", "res://content/attacks/bite.tres"]
const WEAPONS := ["res://content/weapons/bone_saw_cleaver.tres", "res://content/weapons/reliquary_hammer.tres", "res://content/weapons/anatomist_rapier.tres"]
## D2：玩家比敵人難斷肢，但不能太低。
const PLAYER_SEVER_SCALE := 0.5

static func create(weapon_paths: Array = WEAPONS) -> CharacterBody3D:
	var naturals: Array[AttackDefinition] = []
	for p in NATURAL:
		naturals.append(load(p))
	var body := PlaceholderBodyBuilder.build_creature(load(PROFILE), &"player", naturals, &"player")
	(body.get_node("AnatomyComponent") as AnatomyComponent).sever_chance_scale = PLAYER_SEVER_SCALE
	var combat: CombatComponent = body.get_node("CombatComponent")
	combat.max_hp = 160.0
	combat.max_st = 110.0
	var ctrl := PlayerController.new()
	ctrl.name = "PlayerController"
	var ws: Array[WeaponDefinition] = []
	for p in weapon_paths:
		ws.append(load(p))
	ctrl.weapons = ws
	body.add_child(ctrl)
	var tac := TacticalController.new()
	tac.name = "TacticalController"
	body.add_child(tac)
	return body
