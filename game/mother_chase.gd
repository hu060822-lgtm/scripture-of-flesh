class_name MotherChase
extends Node
## 母親的中途登場（序章提案 E）：拿到臍帶鑰匙的那一刻，行走的母親撞破聖器室的北牆追出來。
## 玩家要逃回庭院；她碰到你會扯下你一條手臂（不會殺死你），之後被臍帶拉回牆後。
## 只發生一次（旗標 mother_chase_done，隨祭壇存檔）。這是演出用的分身：沒有 BossPhase，
## 不影響真正的 Boss 戰；EnemyAI 停用，由這個節點直接驅動移動。

signal started
signal ended(reason: StringName)  # &"escaped"、&"caught"、&"timeout"

const MOTHER := "res://content/enemies/walking_mother.tres"
const START_FLAG := &"mother_chase_started"
const DONE_FLAG := &"mother_chase_done"
const TRIGGER_ITEM := "umbilical_key"
## 追逐速度（玩家 4.2）：跑直線追不上，但被擋住或回頭打就會被抓。
const SPEED := 3.7
const GRAB_RANGE := 1.7
const MAX_SECONDS := 30.0
## 破牆後愣住的秒數（給玩家反應時間）。
const STARTUP_SECONDS := 1.2
## 被拉回牆後所需的秒數。
const RETREAT_SECONDS := 3.0
const GRAVITY := 18.0

@export var spawn_marker: NodePath
## 玩家的 x 小於這個值（回到庭院）就算逃掉。
@export var escape_x: float = 9.5

var level: Node3D
var player: CharacterBody3D
var mother: CharacterBody3D
var active := false
var elapsed := 0.0
var _retreat_left := -1.0
var _home := Vector3.ZERO
var _nav := AiNavigator.new()

func setup(lvl: Node3D, pl: CharacterBody3D) -> void:
	level = lvl
	player = pl

func is_done() -> bool:
	return GameState.has_flag(DONE_FLAG)

func _physics_process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

## 推進（測試直接呼叫）。
func advance(delta: float) -> void:
	if delta <= 0.0 or level == null or player == null or not is_instance_valid(player):
		return
	if _retreat_left >= 0.0:
		_advance_retreat(delta)
		return
	if not active:
		if not is_done() and _has_key():
			start()
		return
	elapsed += delta
	var pc: CombatComponent = player.get_node("CombatComponent")
	if pc.is_dead():
		return
	if player.global_position.x < escape_x:
		finish(&"escaped")
		return
	if elapsed >= MAX_SECONDS:
		finish(&"timeout")
		return
	if elapsed < STARTUP_SECONDS:
		_move(Vector3.ZERO, delta)
		return
	var to := player.global_position - mother.global_position
	to.y = 0
	if to.length() <= GRAB_RANGE:
		_grab(pc)
		finish(&"caught")
		return
	_nav.tick(delta)
	var wp := _nav.next_point(mother, player.global_position)
	var dir := wp - mother.global_position
	dir.y = 0
	if dir.length() < 0.05:
		dir = to
	_move(dir.normalized() * SPEED, delta)

func _has_key() -> bool:
	var data: PlayerData = player.get_node_or_null("PlayerData")
	return data != null and data.inventory.count(TRIGGER_ITEM) > 0

func start() -> void:
	active = true
	elapsed = 0.0
	GameState.set_flag(START_FLAG)  # SecretWall（聖器室北牆）看這個旗標打開
	var m := level.get_node_or_null(spawn_marker) as Node3D
	_home = m.global_position if m != null else player.global_position + Vector3(0, 0, 4)
	mother = EnemyFactory.create(load(MOTHER), &"walking_mother_apparition")
	mother.set_meta(&"apparition", true)
	mother.position = _home
	mother.rotation.y = m.rotation.y if m != null else PI
	level.add_child(mother)
	var ai := mother.get_node_or_null("EnemyAI")
	if ai != null:
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	started.emit()

## 扯下一條手臂（優先沒拿武器的那隻）。
func _grab(pc: CombatComponent) -> void:
	var st := pc.anatomy.state
	var eq: EquipmentComponent = player.get_node_or_null("EquipmentComponent")
	var weapon_arm := eq.weapon_part() if eq != null else &""
	var choice := &""
	for arm in [&"arm_l", &"arm_r"]:
		var p := st.get_part(arm)
		if p == null or p.severed:
			continue
		if choice == &"" or arm != weapon_arm:
			choice = arm
	if choice != &"":
		st.sever_part(choice)

func finish(reason: StringName) -> void:
	if not active:
		return
	active = false
	GameState.set_flag(DONE_FLAG)
	_retreat_left = RETREAT_SECONDS
	ended.emit(reason)

func _advance_retreat(delta: float) -> void:
	_retreat_left -= delta
	if mother == null or not is_instance_valid(mother):
		_retreat_left = -1.0
		return
	var dir := _home - mother.global_position
	dir.y = 0
	if dir.length() > 0.3:
		_move(dir.normalized() * SPEED * 1.5, delta)
	if _retreat_left <= 0.0:
		_retreat_left = -1.0
		mother.queue_free()
		mother = null

func _move(v: Vector3, delta: float) -> void:
	var vy := mother.velocity.y - GRAVITY * delta if not mother.is_on_floor() else 0.0
	mother.velocity = Vector3(v.x, vy, v.z)
	if v.length() > 0.01:
		mother.rotation.y = atan2(-v.x, -v.z)
	if mother.is_inside_tree():
		mother.move_and_slide()
