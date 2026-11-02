extends AiState
## 防禦：舉起手臂擋住一次攻擊。

const DURATION := 0.8

func enter(ai: EnemyAI) -> void:
	ai.stop()
	ai.combat.set_blocking(true)

func update(ai: EnemyAI, _delta: float) -> StringName:
	if ai.runtime.target != null:
		ai.face(ai.runtime.target.body().global_position)
	if ai.runtime.time_in_state >= DURATION or not ai.combat.blocking:
		return &"chase"
	return &""

func exit(ai: EnemyAI) -> void:
	ai.combat.set_blocking(false)
