class_name EnemyFactory
extends RefCounted
## 依 EnemyDefinition 組裝敵人（【暫代】膠囊體外觀）。

static func create(def: EnemyDefinition, creature_id: StringName) -> CharacterBody3D:
	var body := PlaceholderBodyBuilder.build_creature(def.anatomy_profile, creature_id, def.attacks, &"enemy")
	body.set_meta(&"enemy_id", def.id)
	body.set_meta(&"xp_reward", def.xp_reward)
	body.set_meta(&"harvestable", def.harvestable)
	var anatomy: AnatomyComponent = body.get_node("AnatomyComponent")
	anatomy.sever_chance_scale = def.sever_chance_scale
	var combat: CombatComponent = body.get_node("CombatComponent")
	combat.max_hp = def.max_hp
	combat.max_st = def.max_st
	combat.stagger_threshold = def.stagger_threshold
	var ai := EnemyAI.new()
	ai.name = "EnemyAI"
	ai.definition = def
	body.add_child(ai)
	if def.weapon != null:
		body.ready.connect(func():
			var eq: EquipmentComponent = body.get_node("EquipmentComponent")
			var arm := eq.free_arm(anatomy.state)
			if arm != &"":
				eq.equip_definition(def.weapon, arm), CONNECT_ONE_SHOT)
	return body
