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
## 演出：跪下時身體在 KNEEL_TIME 秒內沉下並播放跪伏動作（CreatureAnimator 的 kneel 片段），
## 產聲時擴散聲波環（ScreamWave）；未生者從子宮的位置落下。

signal phase_changed(phase: int)
signal summoned(add: Node3D)
signal cords_severed
signal defeated

const KNEEL_STILTS := 2
const KNEEL_DROP := 1.25
const SUMMON_INTERVAL := 9.0
const MAX_ADDS := 2
const KNEEL_SPEED_FACTOR := 0.55
## 跪下的演出時間（秒，戰鬥時間）。
const KNEEL_TIME := 1.0
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
var _kneel_left := 0.0
var _kneel_from := 0.0

func _ready() -> void:
	combat = get_parent().get_node("CombatComponent")
	ai = get_parent().get_node("EnemyAI")
	# 每隻 Boss 使用自己的定義副本，跪下時可以調整速度而不影響資源檔。
	ai.definition = ai.definition.duplicate()
	combat.anatomy.state.capabilities_changed.connect(func(_c): _check_phase())
	combat.died.connect(func(_c): _on_died())
	combat.action_changed.connect(_on_action_changed)

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
	if delta <= 0.0:
		return
	_advance_kneel(delta)
	if not engaged or combat.is_dead():
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
	# 從子宮落下：出生點在子宮的高度，靠重力掉到地面
	var ctrl: DismembermentController = b.get_node_or_null("DismembermentController")
	var womb := ctrl.segment_for(&"womb") if ctrl != null else null
	if womb != null and b.is_inside_tree() and b.is_ancestor_of(womb):
		var wp := womb.global_position
		add.position = Vector3(wp.x + cos(ang) * 0.4, wp.y - 0.4, wp.z + sin(ang) * 0.4)
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
		_kneel_from = vis.position.y
		_kneel_left = KNEEL_TIME
	var anim: CreatureAnimator = body().get_node_or_null("CreatureAnimator")
	if anim != null:
		anim.play_override(&"kneel")
	ai.definition.move_speed *= KNEEL_SPEED_FACTOR
	GameState.set_flag(&"mother_kneeled")
	phase_changed.emit(phase)
	# 產聲：跪下的瞬間發出（打斷目前動作）
	var scream := _attack(&"birth_scream")
	if scream != null and combat.caps().count("scream") > 0:
		combat.force_attack(scream)

## 跪下：身體以「先急墜、再小幅反彈」的曲線沉下 KNEEL_DROP 公尺，結束後交還動畫控制（接著是產聲）。
func _advance_kneel(delta: float) -> void:
	if _kneel_left <= 0.0:
		return
	_kneel_left = maxf(0.0, _kneel_left - delta)
	var t := 1.0 - _kneel_left / KNEEL_TIME
	var vis := body().get_node_or_null("Body") as Node3D
	if vis != null:
		vis.position.y = _kneel_from - KNEEL_DROP * Tween.interpolate_value(0.0, 1.0, t, 1.0, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
	if _kneel_left <= 0.0:
		var anim: CreatureAnimator = body().get_node_or_null("CreatureAnimator")
		if anim != null and anim.override_clip == &"kneel":
			anim.play_override(&"")

func is_kneeling() -> bool:
	return _kneel_left > 0.0

func _on_action_changed(action: int) -> void:
	if action == CombatComponent.Action.ACTIVE and combat.current_attack != null and combat.current_attack.id == &"birth_scream":
		spawn_scream_wave()

func spawn_scream_wave() -> ScreamWave:
	var b := body()
	if b.get_parent() == null:
		return null
	var w := ScreamWave.new()
	w.name = "ScreamWave"
	b.get_parent().add_child(w)
	w.global_position = b.global_position + Vector3.UP * 2.2
	return w

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
