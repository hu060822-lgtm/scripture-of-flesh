class_name Squad
extends RefCounted
## AI-3 群體站位：追擊同一個目標的敵人依「目前所在的方位」排序，平均分配到目標周圍的扇區，
## 讓牠們從不同方向逼近、包圍，而不是全部擠在正面。

## 相鄰站位的最大夾角（人少時不會分得太開）。
const MAX_SPREAD := deg_to_rad(75.0)

## 追擊同一目標、同陣營、活著的敵人（包含自己）。
static func members(ai: EnemyAI, target: CombatComponent) -> Array:
	var out: Array = []
	if target == null:
		return out
	for n in ai.get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var other := n.get_node_or_null("EnemyAI") as EnemyAI
		if other == null or other.combat == null or other.combat.is_dead():
			continue
		if other.combat.faction != ai.combat.faction or other.runtime.target != target:
			continue
		if other.state() in [&"chase", &"attack", &"defend", &"dodge"]:
			out.append(other)
	if not ai in out:
		out.append(ai)
	return out

static func bearing(ai: EnemyAI, target: CombatComponent) -> float:
	var to := ai.body().global_position - target.body().global_position
	return atan2(to.x, to.z)

## 自己的站位方位角（弧度，以目標為中心）。只有自己一隻時回傳目前方位。
static func slot_angle(ai: EnemyAI, target: CombatComponent) -> float:
	var list := members(ai, target)
	var mine := bearing(ai, target)
	if list.size() <= 1:
		return mine
	var bearings := []
	var sx := 0.0
	var sz := 0.0
	for m in list:
		var b := bearing(m, target)
		bearings.append([wrapf(b, -PI, PI), m.get_instance_id(), m])
		sx += sin(b)
		sz += cos(b)
	var mean := atan2(sx, sz)
	# 以平均方位為中心，依相對角度排序
	bearings.sort_custom(func(a, b):
		var da := wrapf(a[0] - mean, -PI, PI)
		var db := wrapf(b[0] - mean, -PI, PI)
		return da < db if absf(da - db) > 0.0001 else a[1] < b[1])
	var n := bearings.size()
	var spread := minf(TAU / n, MAX_SPREAD)
	for i in n:
		if bearings[i][2] == ai:
			return mean + (i - (n - 1) * 0.5) * spread
	return mine

static func slot_position(ai: EnemyAI, target: CombatComponent, radius: float) -> Vector3:
	var a := slot_angle(ai, target)
	return target.body().global_position + Vector3(sin(a), 0, cos(a)) * radius
