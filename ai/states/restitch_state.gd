extends AiState
## 特殊行為（縫屍者）：走到殘肢旁，花時間把它縫回去。期間被打中就中斷。

func enter(ai: EnemyAI) -> void:
	ai.runtime.special_target = RestitchLogic.find_limb(ai)
	ai.runtime.special_progress = 0.0
	ai.interrupted = false

func update(ai: EnemyAI, delta: float) -> StringName:
	var g := ai.runtime.special_target as SeveredPart
	if g == null or not is_instance_valid(g) or g.is_queued_for_deletion():
		return &"chase"
	if ai.interrupted:
		ai.interrupted = false
		if ai.runtime.special_progress > 0.0:
			return &"chase"  # 縫到一半被打斷
	var d := g.global_position.distance_to(ai.body().global_position)
	if d > RestitchLogic.REACH:
		ai.move_towards(g.global_position)
		return &""
	ai.stop()
	ai.runtime.special_progress += delta
	if ai.runtime.special_progress >= RestitchLogic.CHANNEL_SECONDS:
		ai.anatomy.state.restore_part(g.part_id)
		g.queue_free()
		return &"chase"
	return &""
