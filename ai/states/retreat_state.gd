extends AiState
## 撤退：遠離目標。若還有攻擊手段，一段時間後回頭再戰；完全沒有攻擊手段則持續逃離。

const DURATION := 3.0

func update(ai: EnemyAI, _delta: float) -> StringName:
	var t := ai.runtime.target
	if t == null:
		return &"patrol"
	ai.flee_from(t.body().global_position)
	if ai.runtime.time_in_state >= DURATION and AttackSelector.has_any_attack(ai.combat):
		return &"chase"
	return &""
