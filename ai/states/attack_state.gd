extends AiState
## 攻擊：依目前身體能力挑選攻擊並執行，收招後回到追擊。

func enter(ai: EnemyAI) -> void:
	ai.stop()
	var t := ai.runtime.target
	if t == null:
		return
	ai.face(t.body().global_position)
	var a := AttackSelector.select(ai.combat, ai.distance_to(t), ai.rng)
	if a != null:
		ai.combat.try_attack(a)

func update(ai: EnemyAI, _delta: float) -> StringName:
	ai.stop()
	if ai.combat.action == CombatComponent.Action.IDLE:
		return &"chase"
	return &""
