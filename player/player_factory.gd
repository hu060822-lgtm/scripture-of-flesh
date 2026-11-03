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
## include_class_weapon = false：不帶職業武器（序章開場赤手醒來，之後由 apply_class 給予）。
static func create(weapon_paths: Array = WEAPONS, class_path: String = DEFAULT_CLASS, include_class_weapon: bool = true) -> CharacterBody3D:
	var naturals: Array[AttackDefinition] = []
	for p in NATURAL + ["res://content/attacks/leap_kick.tres"]:
		naturals.append(load(p))
	var body := PlaceholderBodyBuilder.build_creature(load(PROFILE), &"player", naturals, &"player")
	CreatureModels.apply(body, &"player")
	(body.get_node("AnatomyComponent") as AnatomyComponent).sever_chance_scale = PLAYER_SEVER_SCALE
	var combat: CombatComponent = body.get_node("CombatComponent")
	combat.max_hp = 160.0
	combat.max_st = 110.0
	var ctrl := PlayerController.new()
	ctrl.name = "PlayerController"
	var cls: ClassDefinition = load(class_path)
	var ws: Array[WeaponDefinition] = []
	if cls.starting_weapon != null and include_class_weapon:
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
	var noise := NoiseEmitter.new()
	noise.name = "NoiseEmitter"
	body.add_child(noise)
	var tac := TacticalController.new()
	tac.name = "TacticalController"
	body.add_child(tac)
	var mv := MutationVisuals.new()
	mv.name = "MutationVisuals"
	body.add_child(mv)
	return body

## 遊戲中途決定職業（序章中透過阿格妮絲的對話）。重設屬性與起始技能，給予職業武器與起始物品。
## 玩家必須已加入場景（_ready 完成）。
static func apply_class(player: Node3D, class_path: String) -> bool:
	if not ResourceLoader.exists(class_path):
		return false
	var cls: ClassDefinition = load(class_path)
	var prog: ProgressionComponent = player.get_node("ProgressionComponent")
	prog.unlocked.clear()
	prog.apply_class(cls)
	prog.apply_to_combat()
	var combat: CombatComponent = player.get_node("CombatComponent")
	combat.pools.hp = combat.pools.max_hp
	combat.pools.st = combat.pools.max_st
	var ctrl: PlayerController = player.get_node("PlayerController")
	if cls.starting_weapon != null:
		if not ctrl.weapons.has(cls.starting_weapon):
			ctrl.weapons.append(cls.starting_weapon)
		var cur := ctrl.equipment.weapon_part()
		if cur != &"":
			var old := ctrl.equipment.unequip(cur)
			if old != null:
				old.queue_free()
			ctrl.weapon_index = -1
		ctrl.switch_weapon(ctrl.weapons.find(cls.starting_weapon))
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data != null:
		for k in cls.starting_items:
			data.inventory.add(String(k), int(cls.starting_items[k]))
	GameState.class_id = cls.id
	return true
