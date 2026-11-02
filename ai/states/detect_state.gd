extends AiState
## 偵測：停下來注視，警戒值累積滿後追擊；失去目標則回到巡邏。

const ALERT_RATE := 2.5

func enter(ai: EnemyAI) -> void:
	ai.stop()

func update(ai: EnemyAI, delta: float) -> StringName:
	ai.face(ai.runtime.last_known_position)
	if ai.runtime.target != null and ai.runtime.time_since_seen <= 0.0:
		ai.runtime.alert += ALERT_RATE * delta
	elif ai.runtime.target == null:
		return &"patrol"
	if ai.runtime.alert >= 1.0:
		return &"chase"
	return &""
