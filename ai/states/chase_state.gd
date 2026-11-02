extends AiState
## 追擊：看不到目標時走到最後已知位置再搜索；看得到時由 Tactics 決定意圖
## （接近／出手／繞圈／側翼／後退／伏擊），在決策之間持續執行該意圖的移動。
## 受威脅時依閃避／防禦機率反應（謹慎與傷勢會提高機率）；血量過低或沒有攻擊手段時撤退。

## 走到最後已知位置這麼近還看不到目標，就改成搜索。
const SEARCH_HANDOFF := 0.8
## 繞圈每步旋轉的角度（弧度）與換邊機率。
const CIRCLE_STEP := 0.6
const SIDE_SWAP_CHANCE := 0.2
## 側翼：目標位置到側翼點的角度（從目標正面量起）。
const FLANK_ANGLE := 1.9
## 縫屍者：目標至少這麼遠才會先回去縫殘肢。
const RESTITCH_SAFE_DISTANCE := 2.5

func _lost(ai: EnemyAI) -> StringName:
	ai.runtime.investigate_point = ai.runtime.last_known_position
	return &"search"

func enter(ai: EnemyAI) -> void:
	ai.runtime.decision_timer = minf(ai.runtime.decision_timer, 0.0)

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
		ai.set_intent(&"approach")
		ai.move_towards(lkp)
		return &""
	if not AttackSelector.has_any_attack(ai.combat):
		return &"retreat"
	if ai.hp_ratio() <= ai.definition.retreat_hp_ratio and ai.runtime.alert < 2.0:
		ai.runtime.alert = 2.0  # 只撤退一次，之後拚死作戰
		return &"retreat"
	var d := ai.distance_to(t)
	var pref := ai.definition.preferred_range
	var reach := AttackSelector.max_reach(ai.combat)
	var engage := minf(pref, reach) if reach > 0.0 else pref
	if ai.runtime.decision_timer <= 0.0:
		ai.runtime.decision_timer = ai.definition.decision_interval
		var react := _react_to_threat(ai)
		if react != &"":
			return react
		if ai.definition.special_behavior == &"restitch" and ai.runtime.special_cooldown <= 0.0 and d > RESTITCH_SAFE_DISTANCE and RestitchLogic.find_limb(ai) != null:
			return &"special"
		var can_attack := ai.combat.action == CombatComponent.Action.IDLE \
			and not AttackSelector.usable_in_range(ai.combat, d).is_empty() \
			and ai.has_line_of_sight(t.body().global_position + Vector3.UP * EnemyAI.TARGET_AIM_HEIGHT)
		var intent := Tactics.decide(ai, d, engage, can_attack)
		if intent != ai.runtime.intent and intent in [&"circle", &"flank"] and ai.rng.randf() < SIDE_SWAP_CHANCE:
			ai.runtime.strafe_side *= -1.0
		ai.set_intent(intent)
		if intent == &"attack":
			return &"attack"
	_execute(ai, t, d, engage)
	return &""

## 目標正在前搖且我在範圍內：依機率閃避或防禦。謹慎與傷勢提高機率。
func _react_to_threat(ai: EnemyAI) -> StringName:
	if not ai.threatened():
		return &""
	var def := ai.definition
	var boost := def.caution * Tactics.injury(ai) * 0.3
	var roll := ai.rng.randf()
	var dodge := def.dodge_chance + (boost if def.dodge_chance > 0.0 else 0.0)
	if roll < dodge and ai.combat.caps().count("locomotion") > 0:
		return &"dodge"
	if roll < dodge + def.defend_chance + boost and ai.combat.caps().count("grip") > 0:
		return &"defend"
	return &""

func _execute(ai: EnemyAI, t: CombatComponent, d: float, engage: float) -> void:
	var me := ai.body().global_position
	var tp := t.body().global_position
	match ai.runtime.intent:
		&"circle":
			var from_t := me - tp
			from_t.y = 0
			if from_t.length() < 0.01:
				from_t = Vector3.FORWARD
			var p := tp + from_t.normalized().rotated(Vector3.UP, CIRCLE_STEP * ai.runtime.strafe_side) * engage
			ai.strafe_to(p, tp, 0.55)
		&"flank":
			var fwd := -t.body().global_transform.basis.z
			fwd.y = 0
			var p := tp + fwd.normalized().rotated(Vector3.UP, FLANK_ANGLE * ai.runtime.strafe_side) * maxf(engage, 1.0)
			ai.strafe_to(p, tp, 0.85)
		&"back_off":
			var away := me - tp
			away.y = 0
			if away.length() < 0.01:
				away = ai.body().global_transform.basis.z
			var p := AiNavigator.closest_point(ai.body(), me + away.normalized() * 2.0)
			ai.strafe_to(p, tp, 0.7)
		&"lurk":
			ai.stop()
			ai.face(tp)
		_:
			if d > engage:
				ai.move_towards(tp)
			else:
				ai.stop()
				ai.face(tp)
