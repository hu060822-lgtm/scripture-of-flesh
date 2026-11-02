extends AiState
## 閃避：往側面閃開。

func enter(ai: EnemyAI) -> void:
	ai.stop()
	var t := ai.runtime.target
	var side := ai.body().global_transform.basis.x * (1.0 if ai.rng.randf() < 0.5 else -1.0)
	if t != null:
		var to := t.body().global_position - ai.body().global_position
		side = to.cross(Vector3.UP).normalized() * (1.0 if ai.rng.randf() < 0.5 else -1.0)
	ai.combat.dodge(side)

func update(ai: EnemyAI, _delta: float) -> StringName:
	if ai.combat.action != CombatComponent.Action.DODGE:
		return &"chase"
	return &""
