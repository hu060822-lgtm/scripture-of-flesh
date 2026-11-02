class_name AttackSelector
extends RefCounted
## 依「目前身體還能做什麼」挑選攻擊。斷肢後不符合能力需求的攻擊自動被排除，
## 因此多手人失去手臂後會自然改用剩餘手臂能做的攻擊，最後退回啃咬。

## 回傳距離內可用的攻擊（加權隨機）。沒有則回傳 null。
static func select(combat: CombatComponent, distance: float, rng: RandomNumberGenerator) -> AttackDefinition:
	var candidates := usable_in_range(combat, distance)
	if candidates.is_empty():
		return null
	var total := 0.0
	for a in candidates:
		total += weight_of(a)
	var roll := rng.randf() * total
	for a in candidates:
		roll -= weight_of(a)
		if roll <= 0.0:
			return a
	return candidates.back()

static func usable_in_range(combat: CombatComponent, distance: float) -> Array[AttackDefinition]:
	var out: Array[AttackDefinition] = []
	for a in combat.available_attacks():
		if combat.can_use(a) and distance <= a.reach + CombatComponent.TARGET_RADIUS:
			out.append(a)
	return out

## 需求越多的攻擊（例如需要四隻手的連擊）權重越高：身體健全時優先用強力攻擊。
static func weight_of(a: AttackDefinition) -> float:
	var req := 0
	for k in a.required_capabilities:
		req += int(a.required_capabilities[k])
	return a.ai_weight * (1.0 + 0.5 * req)

## 這隻敵人目前「有任何攻擊手段」嗎？（不考慮距離與資源）
static func has_any_attack(combat: CombatComponent) -> bool:
	return not combat.available_attacks().is_empty()

## 所有可用攻擊中最遠的距離，用來決定接近到多近。
static func max_reach(combat: CombatComponent) -> float:
	var r := 0.0
	for a in combat.available_attacks():
		r = maxf(r, a.reach)
	return r
