class_name Tactics
extends RefCounted
## AI-2 戰術大腦：追擊中每次決策時，對幾種意圖打分，取最高分（加少量隨機）。
## 分數由敵人個性（EnemyDefinition 的 Tactics 群組）、目標目前的破綻、目標習慣（TargetHabits）
## 與自己的傷勢共同決定。這裡只做決策，移動與出招由 chase／attack 狀態執行。
##
## 意圖：
##   &"approach"  接近到交戰距離
##   &"attack"    出手（交給 attack 狀態）
##   &"circle"    在交戰距離繞圈、等待破綻
##   &"flank"     繞到目標側面／背後（防禦只擋正面）
##   &"back_off"  拉開距離（打帶跑、受傷、遠程型保持距離）
##   &"lurk"      失去雙腿後伏地不動，等目標靠近

## 全域難度倍率（影響趁隙與讀習慣的敏銳度、瞄準傷口的機率）。【暫代】1.0 = 目前預設。
static var difficulty := 1.0

const NOISE := 0.15
## 出手後多少秒內算「剛出手」（打帶跑用）。
const RECENT_ATTACK := 1.2
## 目標正面的判定（與 CombatComponent._is_facing 相同門檻）。
const FACING_DOT := 0.3

## 自己的傷勢 0..1：整體 HP 損失與斷肢比例取大者。
static func injury(ai: EnemyAI) -> float:
	var st := ai.anatomy.state
	var ids := st.part_ids()
	var lost := 0
	for pid in ids:
		if st.get_part(pid).severed:
			lost += 1
	var lost_ratio := float(lost) / maxf(1.0, float(ids.size()))
	return clampf(maxf(1.0 - ai.hp_ratio(), lost_ratio * 2.0), 0.0, 1.0)

## 目標目前的破綻 0..1：收招、僵直最大；耐力見底次之；剛翻滾完（對常閃避的玩家）也算。
static func opening(ai: EnemyAI, t: CombatComponent) -> float:
	match t.action:
		CombatComponent.Action.STAGGER: return 1.0
		CombatComponent.Action.RECOVERY: return 0.9
		CombatComponent.Action.DODGE:
			return 0.8 * ai.habits.dodge_rate * ai.definition.adaptivity
	if t.pools.st < t.pools.max_st * 0.2:
		return 0.6
	return 0.0

## 目標正面朝著我嗎？（防禦只擋正面）
static func target_faces_me(ai: EnemyAI, t: CombatComponent) -> bool:
	var tb := t.body()
	var to := ai.body().global_position - tb.global_position
	to.y = 0
	if to.length() < 0.01:
		return true
	var fwd := -tb.global_transform.basis.z
	fwd.y = 0
	return fwd.normalized().dot(to.normalized()) > FACING_DOT

static func is_crawling(ai: EnemyAI) -> bool:
	return ai._initial_locomotion > 0 and ai.combat.caps().count("locomotion") <= 0

## 回傳 {intent: 分數}，方便測試檢查各項考量。
static func score(ai: EnemyAI, d: float, engage: float, can_attack: bool) -> Dictionary:
	var def := ai.definition
	var t := ai.runtime.target
	var hab := ai.habits
	var inj := injury(ai)
	var open := opening(ai, t)
	var guarded := t.blocking and target_faces_me(ai, t)
	var guard_habit := hab.block_rate * def.adaptivity
	var recent := ai.runtime.since_attack < RECENT_ATTACK
	var s := {}
	if can_attack:
		var a := 0.35 + def.aggression * 0.6
		a += open * def.punish_skill * difficulty * 0.9
		if guarded:
			a -= 0.45 + def.adaptivity * 0.35  # 正面硬打防禦沒有意義
		# 對愛反擊的玩家：沒有破綻就先不出手
		a -= hab.counter_rate * def.adaptivity * difficulty * 0.35 * (1.0 - open)
		if recent:
			a -= def.hit_and_run * 0.5
		s[&"attack"] = a
	if d > engage + 0.2:
		s[&"approach"] = 0.55 + def.aggression * 0.35
	else:
		s[&"circle"] = 0.2 + def.patience * 0.45
		if target_faces_me(ai, t):
			s[&"flank"] = def.flank_tendency * (0.25 + maxf(1.0 if t.blocking else 0.0, guard_habit) * 0.9)
		var back := def.caution * 0.25 + inj * def.caution * 0.8
		if recent:
			back += def.hit_and_run * 0.9
		s[&"back_off"] = back
	# 遠程型：太近就拉開
	if def.preferred_range > 2.0 and d < def.preferred_range * 0.6:
		s[&"back_off"] = float(s.get(&"back_off", 0.0)) + 1.0
	if is_crawling(ai) and d > AttackSelector.max_reach(ai.combat) + 1.5 and ai.runtime.time_in_state < 6.0:
		s[&"lurk"] = 1.3  # 沒腿時爬過去太慢：伏地等待（超過 6 秒仍會爬過去）
	return s

static func decide(ai: EnemyAI, d: float, engage: float, can_attack: bool) -> StringName:
	var s := score(ai, d, engage, can_attack)
	var best: StringName = &"approach" if d > engage else &"circle"
	var best_v := -INF
	for k in s:
		var v: float = s[k] + ai.rng.randf() * NOISE
		if v > best_v:
			best_v = v
			best = k
	return best
