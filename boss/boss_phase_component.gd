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

const KNEEL_STILTS := 2
const KNEEL_DROP := 1.25
const SUMMON_INTERVAL := 9.0
const MAX_ADDS := 2
const KNEEL_SPEED_FACTOR := 0.55
const EXPOSED_WOMB := "res://content/boss/womb_exposed.tres"
const UNBORN := "res://content/enemies/unborn.tres"

var phase := 1
## 戰鬥是否已開始（序章中由對話動作 start_boss 啟動；沙盒或測試可直接設定）。
var engaged := false
var adds: Array[Node3D] = []
var summon_timer := SUMMON_INTERVAL * 0.5
var combat: CombatComponent
var ai: EnemyAI
var _cords_reported := false
var _add_counter := 0

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
