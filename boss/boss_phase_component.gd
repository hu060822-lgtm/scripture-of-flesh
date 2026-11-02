class_name BossPhaseComponent
extends Node
## 行走的母親的階段控制。掛在 Boss 本體下（與 EnemyAI 同層）。
##
## 第一階段「行走」：四根高蹺腿撐起身體，子宮被骨盆甲包覆，只能先打腿與臍帶。
## 第二階段「跪伏」：高蹺腿剩下 KNEEL_STILTS 根以下時跪下 —— 身體降低、骨盆甲剝落
##   （以 replace_part_definition 換成暴露的子宮定義，保留受損比例）、發出產聲、移動變慢。
## 臍帶（tether 能力）還連著時，每隔 SUMMON_INTERVAL 秒生出未生者（同時最多 MAX_ADDS 隻）。
## 臍帶全斷後不再召喚。Boss 死亡時設定 boss_defeated 旗標，殘存的未生者一起死亡。
##
## 【暫代】跪下演出為身體直接下移與文字提示，正式動畫待製作。

signal phase_changed(phase: int)
signal summoned(add: Node3D)
signal cords_severed
signal defeated
# ---- AI-4（給動畫／音效：只發訊號）----
## 開始一段連段，ids 為整串招式。
signal combo_started(ids: PackedStringArray)
## 狂暴開始／結束。
signal enraged(on: bool)
## 防逃課反應：&"summon"（提早召喚）、&"enrage"（沒臍帶時改為狂暴追擊）。
signal anti_cheese(kind: StringName)

const KNEEL_STILTS := 2
const KNEEL_DROP := 1.25
const SUMMON_INTERVAL := 9.0
const MAX_ADDS := 2
const KNEEL_SPEED_FACTOR := 0.55
const EXPOSED_WOMB := "res://content/boss/womb_exposed.tres"
const UNBORN := "res://content/enemies/unborn.tres"

## ---- AI-4 Boss 戰術（【暫代】數值未經遊玩測試）----
## 連段：第一招結束後若下一招可用且在範圍內，直接接著出（不回到追擊）。依階段不同。
const COMBOS := {
	1: [[&"stilt_stomp", &"mother_lash"], [&"mother_lash", &"cradle_crush"]],
	2: [[&"crawl_grasp", &"cradle_crush"], [&"cradle_crush", &"crawl_grasp"]],
}
## 選到連段起手招時，接續連段的機率。
const COMBO_CHANCE := 0.6
## 位置判斷：玩家在身下（踐踏）、在遠處（鞭笞）的距離。
const UNDER_BODY := 1.4
const FAR := 2.4
## 防逃課：玩家持續待在攻擊範圍外這麼多秒，就提早召喚／狂暴。
const OUT_OF_REACH_SECONDS := 6.0
## 狂暴：臍帶全斷或防逃課時觸發。移動更快，但更容易被打出僵直（公平的代價）。
const ENRAGE_SECONDS := 8.0
const ENRAGE_SPEED := 1.3
const ENRAGE_STAGGER := 0.7

var phase := 1
## 戰鬥是否已開始（序章中由對話動作 start_boss 啟動；沙盒或測試可直接設定）。
var engaged := false
var adds: Array[Node3D] = []
var summon_timer := SUMMON_INTERVAL * 0.5
var combat: CombatComponent
var ai: EnemyAI
var _cords_reported := false
var _add_counter := 0
## AI-4 狀態
var combo_queue: Array[StringName] = []
var out_of_reach := 0.0
var enrage_left := 0.0
var _base_speed := 0.0
var _base_stagger := 0.0
var _base_speed_phase := 1

func _ready() -> void:
	combat = get_parent().get_node("CombatComponent")
	ai = get_parent().get_node("EnemyAI")
	# 每隻 Boss 使用自己的定義副本，跪下時可以調整速度而不影響資源檔。
	ai.definition = ai.definition.duplicate()
	combat.anatomy.state.capabilities_changed.connect(func(_c): _check_phase())
	combat.died.connect(func(_c): _on_died())

func body() -> CharacterBody3D:
	return get_parent() as CharacterBody3D

func engage() -> void:
	engaged = true

func stilts() -> int:
	return combat.caps().count("stilt")

func cords() -> int:
	return combat.caps().count("tether")

func _physics_process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

## 推進召喚計時（測試直接呼叫）。
func advance(delta: float) -> void:
	if not engaged or combat.is_dead() or delta <= 0.0:
		return
	adds = adds.filter(func(a): return is_instance_valid(a) and not a.is_queued_for_deletion() \
		and not (a.get_node("CombatComponent") as CombatComponent).is_dead())
	_advance_enrage(delta)
	_advance_anti_cheese(delta)
	if cords() <= 0:
		return
	summon_timer -= delta
	if summon_timer <= 0.0:
		summon_timer = SUMMON_INTERVAL
		if adds.size() < MAX_ADDS:
			summon()

func summon() -> Node3D:
	_add_counter += 1
	var add := EnemyFactory.create(load(UNBORN), StringName("unborn_%d" % _add_counter))
	var b := body()
	var ang := float(_add_counter) * 2.4
	add.position = b.global_position + Vector3(cos(ang), 0, sin(ang)) * 1.6 if b.is_inside_tree() else Vector3(cos(ang), 0, sin(ang)) * 1.6
	var parent := b.get_parent() if b.get_parent() != null else b
	parent.add_child(add)
	adds.append(add)
	summoned.emit(add)
	return add

func _check_phase() -> void:
	if combat.is_dead():
		return
	if cords() <= 0 and not _cords_reported:
		_cords_reported = true
		GameState.set_flag(&"mother_cords_cut")
		cords_severed.emit()
		enrage()
	if phase == 1 and stilts() <= KNEEL_STILTS:
		_kneel()

func _kneel() -> void:
	phase = 2
	var st := combat.anatomy.state
	var womb := st.get_part(&"womb")
	if womb != null and not womb.severed:
		var ratio := womb.hp / womb.def.max_hp
		var injuries := womb.injuries.duplicate()
		var exposed: BodyPartDef = load(EXPOSED_WOMB)
		if st.replace_part_definition(&"womb", exposed):
			var w := st.get_part(&"womb")
			w.hp = exposed.max_hp * ratio
			w.injuries = injuries
	var vis := body().get_node_or_null("Body") as Node3D
	if vis != null:
		vis.position.y -= KNEEL_DROP
	ai.definition.move_speed *= KNEEL_SPEED_FACTOR
	GameState.set_flag(&"mother_kneeled")
	phase_changed.emit(phase)
	# 產聲：跪下的瞬間發出（打斷目前動作）
	var scream := _attack(&"birth_scream")
	if scream != null and combat.caps().count("scream") > 0:
		combat.force_attack(scream)

# ---------- AI-4 戰術 ----------

## 依位置與階段選招（EnemyAI 的攻擊狀態會呼叫）。回傳 null 代表沒有可用的招。
func choose_attack(distance: float) -> AttackDefinition:
	var usable := AttackSelector.usable_in_range(combat, distance)
	if usable.is_empty():
		return null
	var weights: Array[float] = []
	var total := 0.0
	for a in usable:
		var w := AttackSelector.weight_of(a) * situational_weight(a.id, distance)
		weights.append(w)
		total += w
	var roll := ai.rng.randf() * total
	var pick: AttackDefinition = usable.back()
	for i in usable.size():
		roll -= weights[i]
		if roll <= 0.0:
			pick = usable[i]
			break
	_plan_combo(pick.id)
	return pick

## 位置判斷的倍率：身下踐踏、遠處鞭笞、中距離擠壓；產聲在被圍或防逃課時優先。
func situational_weight(id: StringName, distance: float) -> float:
	match id:
		&"stilt_stomp":
			return 4.0 if distance < UNDER_BODY else 0.6
		&"mother_lash":
			return 3.0 if distance > FAR else 0.7
		&"cradle_crush":
			return 2.0 if distance >= 1.0 and distance <= FAR else 0.8
		&"crawl_grasp":
			return 1.5 if phase == 2 else 1.0
		&"birth_scream":
			return 4.0 if out_of_reach > OUT_OF_REACH_SECONDS * 0.5 else 0.5
	return 1.0

func _plan_combo(first: StringName) -> void:
	combo_queue.clear()
	for c in COMBOS.get(phase, []):
		if c[0] == first and ai.rng.randf() < COMBO_CHANCE:
			for i in range(1, c.size()):
				combo_queue.append(c[i])
			var ids := PackedStringArray()
			for id in c:
				ids.append(String(id))
			combo_started.emit(ids)
			return

## 連段的下一招（可用且在範圍內才回傳；否則清空連段）。
func next_combo_attack(distance: float) -> AttackDefinition:
	while not combo_queue.is_empty():
		var a := _attack(combo_queue.pop_front())
		if a != null and a in AttackSelector.usable_in_range(combat, distance):
			return a
	return null

func enrage(seconds: float = ENRAGE_SECONDS) -> void:
	if combat.is_dead():
		return
	if enrage_left <= 0.0:
		_base_speed = ai.definition.move_speed
		_base_speed_phase = phase
		_base_stagger = combat.stagger_threshold
		ai.definition.move_speed *= ENRAGE_SPEED
		combat.stagger_threshold *= ENRAGE_STAGGER
		enraged.emit(true)
	enrage_left = maxf(enrage_left, seconds)

func is_enraged() -> bool:
	return enrage_left > 0.0

func _advance_enrage(delta: float) -> void:
	if enrage_left <= 0.0:
		return
	enrage_left -= delta
	if enrage_left <= 0.0:
		enrage_left = 0.0
		# 期間若跪下過，速度要以跪下後的值為準
		ai.definition.move_speed = _base_speed * (KNEEL_SPEED_FACTOR if phase == 2 and _base_speed_phase == 1 else 1.0)
		combat.stagger_threshold = _base_stagger
		enraged.emit(false)


## 玩家一直待在攻擊範圍外（放風箏、躲在遠處）：提早召喚；沒有臍帶時改為狂暴逼近。
func _advance_anti_cheese(delta: float) -> void:
	var t := ai.runtime.target
	if t == null or t.is_dead():
		out_of_reach = 0.0
		return
	if ai.distance_to(t) > AttackSelector.max_reach(combat) + 1.0:
		out_of_reach += delta
	else:
		out_of_reach = 0.0
	if out_of_reach < OUT_OF_REACH_SECONDS:
		return
	out_of_reach = 0.0
	if cords() > 0 and adds.size() < MAX_ADDS:
		summon_timer = SUMMON_INTERVAL
		summon()
		anti_cheese.emit(&"summon")
	else:
		enrage(ENRAGE_SECONDS * 0.5)
		anti_cheese.emit(&"enrage")

func _attack(id: StringName) -> AttackDefinition:
	for a in combat.natural_attacks:
		if a.id == id:
			return a
	return null

func _on_died() -> void:
	GameState.set_flag(&"boss_defeated")
	for a in adds:
		if is_instance_valid(a):
			var c: CombatComponent = a.get_node("CombatComponent")
			if not c.is_dead():
				c.anatomy.state.sever_part(&"head")
	adds.clear()
	defeated.emit()
