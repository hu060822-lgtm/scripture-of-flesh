class_name EnemyAI
extends Node
## 敵人 AI：可擴充狀態機。每個狀態是 ai/states/ 下的獨立腳本，可依敵人資料增減。
## AI 不直接計算傷害，只對 CombatComponent 下指令；可用攻擊由身體能力決定，
## 斷肢時觸發「斷肢反應」並重新評估。

signal state_changed(old_state: StringName, new_state: StringName)
# ---- 給動畫／音效執行緒的掛鉤（AI 只發訊號，不播放任何東西）----
## 第一次確認敵人並開始追擊。
signal alerted(target: CombatComponent)
## 開始搜索（失去目標或聽到聲響）。point 為要調查的位置。
signal search_started(point: Vector3)
## 出招前搖開始：動畫可依 windup 秒數播放預備動作。
signal telegraph(attack: AttackDefinition, windup_seconds: float)
## 移動方式改變：&"idle"、&"walk"、&"run"、&"limp"（缺一腿）、&"crawl"（無腿）。
signal locomotion_changed(mode: StringName)
## 叫聲：&"alert"（發現）、&"search"（搜尋低語）、&"pain"（斷肢）。音效執行緒接這個訊號。
signal bark(kind: StringName)
## 戰術意圖改變（見 Tactics）：&"approach"、&"attack"、&"circle"、&"flank"、&"back_off"、&"lurk"。
## 動畫可依此切換（例如 circle/flank 用側步、back_off 用後退步）。
signal intent_changed(intent: StringName)

const STATE_SCRIPTS := {
	&"patrol": preload("res://ai/states/patrol_state.gd"),
	&"detect": preload("res://ai/states/detect_state.gd"),
	&"chase": preload("res://ai/states/chase_state.gd"),
	&"attack": preload("res://ai/states/attack_state.gd"),
	&"defend": preload("res://ai/states/defend_state.gd"),
	&"dodge": preload("res://ai/states/dodge_state.gd"),
	&"retreat": preload("res://ai/states/retreat_state.gd"),
	&"dismember_react": preload("res://ai/states/dismember_react_state.gd"),
	&"search": preload("res://ai/states/search_state.gd"),
	&"special": preload("res://ai/states/restitch_state.gd"),
	&"dead": preload("res://ai/states/dead_state.gd"),
}
const LUNGE_SPEED := 9.0
## 分離轉向：與其他敵人小於此距離時互相推開，避免疊在同一點。
const SEPARATION_RADIUS := 1.1
const SEPARATION_WEIGHT := 0.8
## 視線檢查：眼睛高度佔碰撞高度的比例、瞄準目標的高度。
const EYE_HEIGHT_RATIO := 0.85
const TARGET_AIM_HEIGHT := 1.0
## 隔牆聽到的聲響半徑倍率。
const OCCLUDED_HEARING := 0.5
## freeze_when_watched：目標視線與「目標→我」夾角在這個角度內、距離在這之內就算被看著。
const WATCHED_HALF_ANGLE := 55.0
const WATCHED_RANGE := 14.0

@export var definition: EnemyDefinition
@export var gravity: float = 18.0

var runtime := EnemyRuntimeState.new()
var combat: CombatComponent
var anatomy: AnatomyComponent
var rng := RandomNumberGenerator.new()
var desired_velocity := Vector3.ZERO
var interrupted := false
var _states := {}
var navigator := AiNavigator.new()
var habits := TargetHabits.new()
var locomotion_mode: StringName = &"idle"
var _initial_vision := 0
var _initial_locomotion := 0
var _home_set := false
## 正被目標看著而定住（freeze_when_watched）。給動畫、除錯與測試讀取。
var frozen_by_gaze := false
## 裝死（序章恐怖橋段 C2）：躺在地上一動也不動，玩家靠近或打到它時才爬起來。
var dormant := false
const DORMANT_WAKE_RADIUS := 2.2
const DORMANT_RISE_SECONDS := 0.7
signal woke

func _ready() -> void:
	combat = body().get_node("CombatComponent")
	anatomy = body().get_node("AnatomyComponent")
	for k in STATE_SCRIPTS:
		_states[k] = STATE_SCRIPTS[k].new()
	_initial_vision = anatomy.state.capabilities().count("vision")
	_initial_locomotion = anatomy.state.capabilities().count("locomotion")
	anatomy.state.part_severed.connect(_on_part_severed)
	combat.hit_received.connect(_on_hit_received)
	combat.died.connect(func(_c): force_state(&"dead"))
	combat.hit_received.connect(func(_r, _a): if dormant: wake())
	combat.attack_started.connect(func(a: AttackDefinition): telegraph.emit(a, a.windup))
	EventBus.noise_emitted.connect(_on_noise)
	_states[runtime.state_name].enter(self)

func body() -> CharacterBody3D:
	return get_parent() as CharacterBody3D

func state() -> StringName:
	return runtime.state_name

func _physics_process(delta: float) -> void:
	if dormant:
		if _player_within(DORMANT_WAKE_RADIUS):
			wake()
		else:
			return
	var sd := TimeScale.scaled(delta)
	var yaw_before := body().rotation.y
	advance(sd)
	var b := body()
	var v := desired_velocity
	if frozen_by_gaze:
		v = Vector3.ZERO
		b.rotation.y = yaw_before
	elif definition.freeze_when_watched:
		v *= definition.unwatched_speed_factor
	if combat.current_attack != null and combat.current_attack.tags.has("lunge") and combat.action == CombatComponent.Action.ACTIVE:
		v = -b.global_transform.basis.z * LUNGE_SPEED
	elif combat.action == CombatComponent.Action.DODGE:
		v = combat.dodge_direction * combat.dodge_speed
	var vy := b.velocity.y - gravity * sd if not b.is_on_floor() else 0.0
	b.velocity = Vector3(v.x, vy, v.z) * TimeScale.combat_scale()
	b.move_and_slide()
	_update_locomotion(Vector2(v.x, v.z).length())

func _update_locomotion(speed: float) -> void:
	var mode: StringName = &"idle"
	if speed > 0.05:
		var legs := combat.caps().count("locomotion")
		if _initial_locomotion > 0 and legs <= 0:
			mode = &"crawl"
		elif legs < _initial_locomotion:
			mode = &"limp"
		elif speed > definition.move_speed * 0.7:
			mode = &"run"
		else:
			mode = &"walk"
	if mode != locomotion_mode:
		locomotion_mode = mode
		locomotion_changed.emit(mode)

## 裝死：把外觀放倒在地上（碰撞體不變）。
func set_dormant(on: bool) -> void:
	dormant = on
	var vis := body().get_node_or_null("Body") as Node3D
	if vis != null:
		vis.rotation.x = -PI * 0.5 if on else 0.0
		vis.position.y = 0.18 if on else 0.0

## 爬起來：外觀在 0.7 秒內站起，並立刻注意到玩家。
func wake() -> void:
	if not dormant:
		return
	dormant = false
	var vis := body().get_node_or_null("Body") as Node3D
	if vis != null and vis.is_inside_tree():
		var tw := vis.create_tween()
		tw.tween_property(vis, "rotation:x", 0.0, DORMANT_RISE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(vis, "position:y", 0.0, DORMANT_RISE_SECONDS)
	elif vis != null:
		vis.rotation.x = 0.0
		vis.position.y = 0.0
	runtime.decision_timer = 0.0
	woke.emit()

func _player_within(r: float) -> bool:
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var c: CombatComponent = n.get_node_or_null("CombatComponent")
		if c != null and c.faction == &"player" and not c.is_dead():
			if (n as Node3D).global_position.distance_to(body().global_position) <= r:
				return true
	return false

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
	navigator.tick(delta)
	runtime.since_attack += delta
	runtime.special_cooldown = maxf(0.0, runtime.special_cooldown - delta)
	perceive(delta)
	_update_gaze_freeze()
	habits.observe(combat, runtime.target)
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
	if name == &"dead":
		AttackTokens.release(self)
	runtime.state_name = name
	runtime.time_in_state = 0.0
	_states[name].enter(self)
	state_changed.emit(old, name)
	if name == &"chase" and old in [&"patrol", &"detect", &"search"] and runtime.target != null:
		alerted.emit(runtime.target)
		bark.emit(&"alert")
		# AI-3：呼叫附近的同伴（同陣營只會回應 alarm）
		if definition.alarm_radius > 0.0 and body().is_inside_tree():
			EventBus.emit_noise(body().global_position, definition.alarm_radius, body(), &"alarm")

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

## 序章提案 C：無面觀察者被目標看著時定住。
func _update_gaze_freeze() -> void:
	var was := frozen_by_gaze
	frozen_by_gaze = definition.freeze_when_watched and not combat.is_dead() and vision_count() > 0 \
		and runtime.target != null and is_watched_by(runtime.target)
	if frozen_by_gaze != was:
		bark.emit(&"frozen" if frozen_by_gaze else &"unfrozen")

## other 是否正面對著我（視線夾角內、距離內、沒有被牆擋住）。
func is_watched_by(other: CombatComponent) -> bool:
	if other == null or other.is_dead():
		return false
	var ob := other.body()
	var to_me := body().global_position - ob.global_position
	to_me.y = 0
	if to_me.length() > WATCHED_RANGE or to_me.length() < 0.01:
		return false
	var fwd := -ob.global_transform.basis.z
	fwd.y = 0
	if fwd.length() < 0.01:
		return false
	if fwd.normalized().dot(to_me.normalized()) < cos(deg_to_rad(WATCHED_HALF_ANGLE)):
		return false
	return has_line_of_sight(ob.global_position + Vector3.UP * TARGET_AIM_HEIGHT)

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
	if rad_to_deg(fwd.normalized().angle_to(to / d)) > definition.sight_fov_degrees * 0.5:
		return false
	return has_line_of_sight(other.body().global_position + Vector3.UP * TARGET_AIM_HEIGHT)

## 從眼睛到 point 之間沒有牆（只檢查世界碰撞層，生物不擋視線）。
func has_line_of_sight(point: Vector3) -> bool:
	var b := body()
	if not b.is_inside_tree():
		return true
	var eye := b.global_position + Vector3.UP * definition.collision_height * EYE_HEIGHT_RATIO
	var q := PhysicsRayQueryParameters3D.create(eye, point, PlaceholderBodyBuilder.WORLD_LAYER)
	return b.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## 聽覺：距離內就察覺；目標正在攻擊（發出聲響）時範圍加大。
func can_hear(other: CombatComponent) -> bool:
	var r := definition.hearing_range
	if other.action in [CombatComponent.Action.WINDUP, CombatComponent.Action.ACTIVE]:
		r += 2.0
	var d := distance_to(other)
	if d > r:
		return false
	# 隔牆時聽覺範圍減半
	return d <= r * OCCLUDED_HEARING or has_line_of_sight(other.body().global_position + Vector3.UP * TARGET_AIM_HEIGHT)

## 聲響：沒有目標時前往調查（隔牆減半）。同陣營的聲響只有 &"alarm" 會引起注意。
func _on_noise(position: Vector3, radius: float, source: Node, kind: StringName) -> void:
	if combat == null or combat.is_dead() or source == body():
		return
	if not is_inside_tree() or not body().is_inside_tree():
		return
	if source != null and kind != &"alarm":
		var sc := source.get_node_or_null("CombatComponent") as CombatComponent
		if sc != null and sc.faction == combat.faction:
			return
	var to := position - body().global_position
	to.y = 0
	var d := to.length()
	if d > radius:
		return
	if d > radius * OCCLUDED_HEARING and not has_line_of_sight(position + Vector3.UP * TARGET_AIM_HEIGHT):
		return
	hear_noise(position, kind)

## 聽到聲響後的反應（測試可以直接呼叫）。
func hear_noise(position: Vector3, _kind: StringName = &"generic") -> void:
	if runtime.target != null and runtime.time_since_seen <= 0.0:
		return  # 正在看著目標，不分心
	runtime.investigate_point = position
	runtime.alert = maxf(runtime.alert, 0.5)
	if runtime.state_name in [&"patrol", &"detect", &"search"]:
		if runtime.state_name == &"search":
			_states[&"search"].retarget(self, position)
		else:
			force_state(&"search")

# ---------- 行動輔助 ----------

func distance_to(other: CombatComponent) -> float:
	var to := other.body().global_position - body().global_position
	to.y = 0
	return to.length()

## 沿導航路徑走向 point（沒有導航網格時直線前進），並與其他敵人保持間距。
func move_towards(point: Vector3, speed_factor: float = 1.0) -> void:
	var flat := point - body().global_position
	flat.y = 0
	if flat.length() < 0.05:
		stop()
		return
	var waypoint := navigator.next_point(body(), point)
	var to := waypoint - body().global_position
	to.y = 0
	if to.length() < 0.05:
		to = flat
	var dir := to.normalized() + separation() * SEPARATION_WEIGHT
	dir.y = 0
	if dir.length() < 0.01:
		dir = to.normalized()
	desired_velocity = dir.normalized() * definition.move_speed * combat.movement_multiplier() * speed_factor
	face(body().global_position + to)

## 遠離 point：在導航網格上找一個背向 point 的點走過去（不會一路倒退撞牆）。
func flee_from(point: Vector3, speed_factor: float = 1.0) -> void:
	if not AiNavigator.has_navigation(body()):
		move_away_from(point, speed_factor)
		return
	var away := body().global_position - point
	away.y = 0
	if away.length() < 0.01:
		away = body().global_transform.basis.z
	var best := body().global_position
	var best_score := -INF
	for i in range(-2, 3):
		var dir := away.normalized().rotated(Vector3.UP, i * PI / 5.0)
		var cand := AiNavigator.closest_point(body(), body().global_position + dir * 4.0)
		var score := (cand - point).length() - absf(i) * 0.3
		if score > best_score:
			best_score = score
			best = cand
	move_towards(best, speed_factor)

## 周圍其他敵人的推開向量（越近越強）。
func separation() -> Vector3:
	var push := Vector3.ZERO
	var me := body().global_position
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		if n == body() or not (n is Node3D):
			continue
		var c := n.get_node_or_null("CombatComponent") as CombatComponent
		if c == null or c.is_dead() or c.faction != combat.faction:
			continue
		var away: Vector3 = me - (n as Node3D).global_position
		away.y = 0
		var d := away.length()
		if d < SEPARATION_RADIUS and d > 0.001:
			push += away / d * (1.0 - d / SEPARATION_RADIUS)
	return push

func move_away_from(point: Vector3, speed_factor: float = 1.0) -> void:
	var to := body().global_position - point
	to.y = 0
	if to.length() < 0.01:
		to = body().global_transform.basis.z
	desired_velocity = to.normalized() * definition.move_speed * combat.movement_multiplier() * speed_factor
	face(point)  # 後退時仍面向目標

## 走向 point 但臉朝 look_at（側步、繞圈、後退）。沿導航路徑並保持間距。
func strafe_to(point: Vector3, look_at: Vector3, speed_factor: float = 0.6) -> void:
	move_towards(point, speed_factor)
	face(look_at)

func set_intent(intent: StringName) -> void:
	if intent != runtime.intent:
		runtime.intent = intent
		intent_changed.emit(intent)

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
	bark.emit(&"pain")
	if not combat.is_dead():
		force_state(&"dismember_react")

func _on_hit_received(_result: DamageResult, attacker: CombatComponent) -> void:
	interrupted = true
	if attacker != null and runtime.target == null and not combat.is_dead():
		runtime.target = attacker
		runtime.last_known_position = attacker.body().global_position
		runtime.time_since_seen = 0.0
		runtime.alert = 1.0
