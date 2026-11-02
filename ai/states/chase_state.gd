extends AiState
## 追擊：接近到偏好距離，時機到了就攻擊；受威脅時防禦或閃避；血量過低或沒有攻擊手段時撤退。

## 走到最後已知位置這麼近還看不到目標，就改成搜索。
const SEARCH_HANDOFF := 0.8

func _lost(ai: EnemyAI) -> StringName:
	ai.runtime.investigate_point = ai.runtime.last_known_position
	return &"search"

func update(ai: EnemyAI, _delta: float) -> StringName:
	var t := ai.runtime.target
	if t == null:
		return _lost(ai)
	# 看不到（也聽不到）目標時不偷看真實位置：走到最後看到的地方，到了還沒發現就開始搜索。
	if ai.runtime.time_since_seen > 0.0:
		var lkp := ai.runtime.last_known_position
		var to := lkp - ai.body().global_position
		to.y = 0
		if to.length() <= SEARCH_HANDOFF:
			return _lost(ai)
		ai.move_towards(lkp)
		return &""
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
