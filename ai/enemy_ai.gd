class_name EnemyAI
extends Node
## 敵人 AI：可擴充狀態機。每個狀態是 ai/states/ 下的獨立腳本，可依敵人資料增減。
## AI 不直接計算傷害，只對 CombatComponent 下指令；可用攻擊由身體能力決定，
## 斷肢時觸發「斷肢反應」並重新評估。

signal state_changed(old_state: StringName, new_state: StringName)

const STATE_SCRIPTS := {
	&"patrol": preload("res://ai/states/patrol_state.gd"),
	&"detect": preload("res://ai/states/detect_state.gd"),
	&"chase": preload("res://ai/states/chase_state.gd"),
	&"attack": preload("res://ai/states/attack_state.gd"),
	&"defend": preload("res://ai/states/defend_state.gd"),
	&"dodge": preload("res://ai/states/dodge_state.gd"),
	&"retreat": preload("res://ai/states/retreat_state.gd"),
	&"dismember_react": preload("res://ai/states/dismember_react_state.gd"),
	&"special": preload("res://ai/states/restitch_state.gd"),
	&"dead": preload("res://ai/states/dead_state.gd"),
}
const LUNGE_SPEED := 9.0

@export var definition: EnemyDefinition
@export var gravity: float = 18.0

var runtime := EnemyRuntimeState.new()
var combat: CombatComponent
var anatomy: AnatomyComponent
var rng := RandomNumberGenerator.new()
var desired_velocity := Vector3.ZERO
var interrupted := false
var _states := {}
var _initial_vision := 0
var _home_set := false

func _ready() -> void:
	combat = body().get_node("CombatComponent")
	anatomy = body().get_node("AnatomyComponent")
	for k in STATE_SCRIPTS:
		_states[k] = STATE_SCRIPTS[k].new()
	_initial_vision = anatomy.state.capabilities().count("vision")
	anatomy.state.part_severed.connect(_on_part_severed)
	combat.hit_received.connect(_on_hit_received)
	combat.died.connect(func(_c): force_state(&"dead"))
	_states[runtime.state_name].enter(self)

func body() -> CharacterBody3D:
	return get_parent() as CharacterBody3D

func state() -> StringName:
	return runtime.state_name

func _physics_process(delta: float) -> void:
	var sd := TimeScale.scaled(delta)
	advance(sd)
	var b := body()
	var v := desired_velocity
	if combat.current_attack != null and combat.current_attack.tags.has("lunge") and combat.action == CombatComponent.Action.ACTIVE:
		v = -b.global_transform.basis.z * LUNGE_SPEED
	elif combat.action == CombatComponent.Action.DODGE:
		v = combat.dodge_direction * combat.dodge_speed
	var vy := b.velocity.y - gravity * sd if not b.is_on_floor() else 0.0
	b.velocity = Vector3(v.x, vy, v.z) * TimeScale.combat_scale()
	b.move_and_slide()

## 推進 AI 決策（不移動身體；移動在 _physics_process）。測試直接呼叫。
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if not _home_set:
		# 出生點在第一次決策時記錄（生成後才設定位置的情況也正確）。
		_home_set = true
		runtime.home = body().global_position
		runtime.patrol_point = runtime.home
	if combat.is_dead() and runtime.state_name != &"dead":
		force_state(&"dead")
	runtime.time_in_state += delta
	runtime.decision_timer -= delta
	perceive(delta)
	var next: StringName = _states[runtime.state_name].update(self, delta)
	if next != &"" and next != runtime.state_name:
		force_state(next)

func force_state(name: StringName) -> void:
	if not _states.has(name):
		push_error("EnemyAI: unknown state %s" % name)
		return
	if runtime.state_name == &"dead" and name != &"dead":
		return
	var old := runtime.state_name
	_states[old].exit(self)
	runtime.state_name = name
	runtime.time_in_state = 0.0
	_states[name].enter(self)
	state_changed.emit(old, name)

# ---------- 感知 ----------

func perceive(delta: float) -> void:
	var best: CombatComponent = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var other: CombatComponent = n.get_node_or_null("CombatComponent")
		if other == null or other == combat or other.is_dead() or other.faction == combat.faction:
			continue
		if not can_detect(other):
			continue
		var d := distance_to(other)
		if d < best_d:
			best_d = d
			best = other
	if best != null:
		runtime.target = best
		runtime.last_known_position = best.body().global_position
		runtime.time_since_seen = 0.0
	else:
		runtime.time_since_seen += delta
		if runtime.target != null and (runtime.target.is_dead() or runtime.time_since_seen > definition.memory_seconds):
			runtime.target = null

func can_detect(other: CombatComponent) -> bool:
	return can_see(other) or can_hear(other)

func vision_count() -> int:
	return anatomy.state.capabilities().count("vision")

## 視覺：需要 vision 能力；眼睛越少看得越近。
func can_see(other: CombatComponent) -> bool:
	var vis := vision_count()
	if definition.needs_vision and vis <= 0:
		return false
	var range := definition.sight_range
	if _initial_vision > 0:
		range *= 0.6 + 0.4 * float(vis) / float(_initial_vision)
	var to := other.body().global_position - body().global_position
	to.y = 0
	var d := to.length()
	if d > range:
		return false
	if d < 0.05:
		return true
	var fwd := -body().global_transform.basis.z
	fwd.y = 0
	return rad_to_deg(fwd.normalized().angle_to(to / d)) <= definition.sight_fov_degrees * 0.5

## 聽覺：距離內就察覺；目標正在攻擊（發出聲響）時範圍加大。
func can_hear(other: CombatComponent) -> bool:
	var r := definition.hearing_range
	if other.action in [CombatComponent.Action.WINDUP, CombatComponent.Action.ACTIVE]:
		r += 2.0
	return distance_to(other) <= r

# ---------- 行動輔助 ----------

func distance_to(other: CombatComponent) -> float:
	var to := other.body().global_position - body().global_position
	to.y = 0
	return to.length()

func move_towards(point: Vector3, speed_factor: float = 1.0) -> void:
	var to := point - body().global_position
	to.y = 0
	if to.length() < 0.05:
		stop()
		return
	desired_velocity = to.normalized() * definition.move_speed * combat.movement_multiplier() * speed_factor
	face(point)

func move_away_from(point: Vector3, speed_factor: float = 1.0) -> void:
	var to := body().global_position - point
	to.y = 0
	if to.length() < 0.01:
		to = body().global_transform.basis.z
	desired_velocity = to.normalized() * definition.move_speed * combat.movement_multiplier() * speed_factor
	face(point)  # 後退時仍面向目標

func stop() -> void:
	desired_velocity = Vector3.ZERO

func face(point: Vector3) -> void:
	var to := point - body().global_position
	to.y = 0
	if to.length() > 0.05:
		body().rotation.y = atan2(-to.x, -to.z)

func hp_ratio() -> float:
	return combat.pools.hp / combat.pools.max_hp

## 目標正在前搖且我在其攻擊範圍內：考慮防禦或閃避。
func threatened() -> bool:
	var t := runtime.target
	return t != null and t.action == CombatComponent.Action.WINDUP and t.current_attack != null \
		and distance_to(t) <= t.current_attack.reach + CombatComponent.TARGET_RADIUS

func _on_part_severed(part_id: StringName, _ids: PackedStringArray) -> void:
	runtime.last_severed_part = part_id
	if not combat.is_dead():
		force_state(&"dismember_react")

func _on_hit_received(_result: DamageResult, attacker: CombatComponent) -> void:
	interrupted = true
	if attacker != null and runtime.target == null and not combat.is_dead():
		runtime.target = attacker
		runtime.last_known_position = attacker.body().global_position
		runtime.time_since_seen = 0.0
		runtime.alert = 1.0
