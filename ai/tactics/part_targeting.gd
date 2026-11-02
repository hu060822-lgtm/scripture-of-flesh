class_name PartTargeting
extends RefCounted
## 解剖感知：決定要瞄準目標的哪個部位。
## 以 injured_target_bias 的機率挑「已受傷但未斷」的部位（受傷越重越優先），
## 但只挑高度與這招的攻擊高度相近的部位（踢擊不會打到頭）。其餘情況交給 CombatComponent 依方向自動決定。

## 部位 HP 比例低於此值才算「受傷」。
const INJURED_RATIO := 0.75
## 部位高度與攻擊高度的容許差。
const HEIGHT_TOLERANCE := 0.5

static func pick(target: CombatComponent, attack: AttackDefinition, bias: float, rng: RandomNumberGenerator) -> StringName:
	if target == null or attack == null or bias <= 0.0 or attack.preferred_target_part != &"":
		return &""
	if rng.randf() >= bias * Tactics.difficulty:
		return &""
	var best: StringName = &""
	var best_ratio := INJURED_RATIO
	var ctrl: DismembermentController = target.body().get_node_or_null("DismembermentController")
	for pid in target.anatomy.state.targetable_part_ids():
		var p := target.anatomy.state.get_part(pid)
		if p == null or p.severed:
			continue
		var ratio := p.hp / p.def.max_hp
		if ratio >= best_ratio:
			continue
		if ctrl != null:
			var hb: Hurtbox = ctrl.hurtbox_for(pid)
			if hb == null or not hb.active:
				continue
			if absf(hb.global_position.y - target.body().global_position.y - attack.aim_height) > HEIGHT_TOLERANCE:
				continue
		best_ratio = ratio
		best = pid
	return best
