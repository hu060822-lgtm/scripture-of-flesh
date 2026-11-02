extends AiState
## 斷肢反應：短暫僵直，接著依剩餘身體重新評估行為。

func enter(ai: EnemyAI) -> void:
	ai.stop()

func update(ai: EnemyAI, _delta: float) -> StringName:
	if ai.runtime.time_in_state < ai.definition.dismember_react_seconds:
		return &""
	if ai.definition.special_behavior == &"restitch" and RestitchLogic.find_limb(ai) != null:
		return &"special"
	if not AttackSelector.has_any_attack(ai.combat):
		return &"retreat"
	return &"chase"
