extends AiState
## 追擊：接近到偏好距離，時機到了就攻擊；受威脅時防禦或閃避；血量過低或沒有攻擊手段時撤退。

func update(ai: EnemyAI, _delta: float) -> StringName:
	var t := ai.runtime.target
	if t == null:
		if ai.runtime.time_since_seen < ai.definition.memory_seconds:
			ai.move_towards(ai.runtime.last_known_position)
			return &""
		return &"patrol"
	if not AttackSelector.has_any_attack(ai.combat):
		return &"retreat"
	if ai.hp_ratio() <= ai.definition.retreat_hp_ratio and ai.runtime.alert < 2.0:
		ai.runtime.alert = 2.0  # 只撤退一次，之後拚死作戰
		return &"retreat"
	var d := ai.distance_to(t)
	if ai.runtime.decision_timer <= 0.0:
		ai.runtime.decision_timer = ai.definition.decision_interval
		if ai.threatened():
			var roll := ai.rng.randf()
			if roll < ai.definition.dodge_chance and ai.combat.caps().count("locomotion") > 0:
				return &"dodge"
			if roll < ai.definition.dodge_chance + ai.definition.defend_chance and ai.combat.caps().count("grip") > 0:
				return &"defend"
		if ai.combat.action == CombatComponent.Action.IDLE and AttackSelector.select(ai.combat, d, ai.rng) != null:
			return &"attack"
	var pref := ai.definition.preferred_range
	var reach := AttackSelector.max_reach(ai.combat)
	var engage := minf(pref, reach) if reach > 0.0 else pref
	if d > engage:
		ai.move_towards(t.body().global_position)
	elif pref > 2.0 and d < pref * 0.6:
		ai.move_away_from(t.body().global_position, 0.7)
	else:
		ai.stop()
		ai.face(t.body().global_position)
	return &""
