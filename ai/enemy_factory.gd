class_name EnemyFactory
extends RefCounted
## 依 EnemyDefinition 組裝敵人（【暫代】膠囊體外觀）。

static func create(def: EnemyDefinition, creature_id: StringName) -> CharacterBody3D:
	var body := PlaceholderBodyBuilder.build_creature(def.anatomy_profile, creature_id, def.attacks, &"enemy")
	body.set_meta(&"enemy_id", def.id)
	if CreatureModels.LOOKS.has(def.id):
		CreatureModels.apply(body, def.id)
	body.set_meta(&"xp_reward", def.xp_reward)
	body.set_meta(&"harvestable", def.harvestable)
	if def.collision_radius != 0.32 or def.collision_height != 1.8:
		var cap := CapsuleShape3D.new()
		cap.radius = def.collision_radius
		cap.height = maxf(def.collision_height, def.collision_radius * 2.0)
		var col: CollisionShape3D = body.get_node("BodyCollision")
		col.shape = cap
		col.position = Vector3(0, cap.height * 0.5, 0)
	if def.visual_scale != 1.0:
		(body.get_node("Body") as Node3D).scale = Vector3.ONE * def.visual_scale
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
