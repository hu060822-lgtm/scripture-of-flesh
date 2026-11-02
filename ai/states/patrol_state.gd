extends AiState
## 巡邏：在出生點附近徘徊。察覺目標後進入偵測（被攻擊時直接追擊）。

func enter(ai: EnemyAI) -> void:
	ai.runtime.alert = maxf(0.0, ai.runtime.alert - 0.5)
	_pick_point(ai)

func update(ai: EnemyAI, _delta: float) -> StringName:
	if ai.runtime.target != null:
		return &"chase" if ai.runtime.alert >= 1.0 else &"detect"
	var to: Vector3 = ai.runtime.patrol_point - ai.body().global_position
	to.y = 0
	if to.length() < 0.3 or ai.runtime.time_in_state > 6.0:
		_pick_point(ai)
		ai.runtime.time_in_state = 0.0
	ai.move_towards(ai.runtime.patrol_point, 0.4)
	return &""

func _pick_point(ai: EnemyAI) -> void:
	var a := ai.rng.randf() * TAU
	var r := ai.rng.randf() * ai.definition.patrol_radius
	ai.runtime.patrol_point = ai.runtime.home + Vector3(cos(a) * r, 0, sin(a) * r)
