class_name AttackTokens
extends RefCounted
## AI-3 攻擊令牌：同一個目標同時最多 MAX_ATTACKERS 隻敵人出手（luz 決定：2 隻），
## 其他敵人在外圈繞行、補位，等令牌空出來。Boss 不佔令牌（EnemyDefinition.uses_attack_token = false）。
## 以目標的 instance id 分組；持有者死亡、離開場景或放棄目標時自動回收。

static var max_attackers := 2
## 目標 instance_id -> Array[EnemyAI]
static var _holders := {}

static func holders(target: CombatComponent) -> Array:
	if target == null:
		return []
	var key := target.get_instance_id()
	var list: Array = _holders.get(key, [])
	list = list.filter(func(ai): return is_instance_valid(ai) and ai.is_inside_tree() \
		and not ai.combat.is_dead() and ai.runtime.target == target)
	_holders[key] = list
	return list

static func has(ai: EnemyAI, target: CombatComponent) -> bool:
	return ai in holders(target)

## 嘗試取得令牌；已持有或不需要令牌時回傳 true。
static func request(ai: EnemyAI, target: CombatComponent) -> bool:
	if target == null:
		return false
	if not ai.definition.uses_attack_token:
		return true
	var list := holders(target)
	if ai in list:
		return true
	if list.size() >= max_attackers:
		return false
	list.append(ai)
	_holders[target.get_instance_id()] = list
	return true

static func release(ai: EnemyAI) -> void:
	for key in _holders.keys():
		var list: Array = _holders[key]
		list.erase(ai)

static func reset() -> void:
	_holders.clear()
	max_attackers = 2
