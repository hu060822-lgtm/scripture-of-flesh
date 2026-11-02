extends AiState
## 攻擊：依目前身體能力與戰況（Tactics／AttackSelector.select_for）挑選招式，
## 依解剖感知（PartTargeting）決定瞄準部位，收招後回到追擊。
## 失明時只能朝聽到的位置出手，方向有誤差。

## 失明時出手方向的最大誤差（弧度）。
const BLIND_JITTER := 0.45

func enter(ai: EnemyAI) -> void:
	ai.stop()
	var t := ai.runtime.target
	if t == null:
		return
	var aim := t.body().global_position
	if ai.definition.needs_vision and ai.vision_count() <= 0:
		var lkp := ai.runtime.last_known_position
		var off := (lkp - ai.body().global_position).rotated(Vector3.UP, ai.rng.randf_range(-BLIND_JITTER, BLIND_JITTER))
		aim = ai.body().global_position + off
	ai.face(aim)
	AttackTokens.request(ai, t)  # 通常已由 chase 取得；直接進入攻擊狀態時補拿
	var boss := _boss(ai)
	var a := boss.choose_attack(ai.distance_to(t)) if boss != null else AttackSelector.select_for(ai, ai.distance_to(t))
	if a != null:
		var part := PartTargeting.pick(t, a, ai.definition.injured_target_bias, ai.rng, ai.definition.preferred_target_parts, ai.definition.visual_scale)
		ai.combat.try_attack(a, part)

## 收招結束才開始計算「剛出手」（打帶跑在收招後拉開距離）。
func exit(ai: EnemyAI) -> void:
	ai.runtime.since_attack = 0.0
	AttackTokens.release(ai)

func update(ai: EnemyAI, _delta: float) -> StringName:
	ai.stop()
	if ai.combat.action == CombatComponent.Action.IDLE:
		# AI-4：Boss 連段，下一招可用就直接接上
		var boss := _boss(ai)
		var t := ai.runtime.target
		if boss != null and t != null and not t.is_dead():
			var nxt := boss.next_combo_attack(ai.distance_to(t))
			if nxt != null:
				ai.face(t.body().global_position)
				if ai.combat.try_attack(nxt):
					return &""
		return &"chase"
	return &""

func _boss(ai: EnemyAI) -> BossPhaseComponent:
	return ai.body().get_node_or_null("BossPhase") as BossPhaseComponent
