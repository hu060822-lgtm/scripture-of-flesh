extends AiState
## 死亡：停止一切行動。

func enter(ai: EnemyAI) -> void:
	ai.stop()
	ai.combat.set_blocking(false)

func update(_ai: EnemyAI, _delta: float) -> StringName:
	return &""
