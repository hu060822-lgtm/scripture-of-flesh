class_name PlayerController
extends Node
## 玩家輸入 → 移動與 CombatComponent 指令。不包含任何傷害邏輯。
## 掛在生物本體（CharacterBody3D）底下。

signal weapon_switched(weapon: WeaponDefinition)
signal picked_up(weapon: WeaponDefinition)
signal tactical_target_changed(part_id: StringName)

@export var move_speed: float = 4.2
@export var gravity: float = 18.0
@export var turn_speed: float = 14.0
@export var pickup_radius: float = 1.6
## 玩家攜帶的武器（垂直切片：三種）。
@export var weapons: Array[WeaponDefinition] = []

var camera: Camera3D
var combat: CombatComponent
var equipment: EquipmentComponent
var weapon_index := -1
## 戰術介面指定的目標與部位（M5）。空值代表自動。
var tactical_target: CombatComponent
var tactical_part: StringName = &""
var input_enabled := true

func _ready() -> void:
	InputSetup.ensure_actions()
	combat = body().get_node("CombatComponent")
	equipment = body().get_node("EquipmentComponent")
	combat.faction = &"player"
	if not weapons.is_empty() and weapon_index < 0:
		switch_weapon(0)

func body() -> CharacterBody3D:
	return get_parent() as CharacterBody3D

## 換武器。收起目前的武器，裝到一隻可用的手上。
func switch_weapon(index: int) -> bool:
	if index < 0 or index >= weapons.size() or combat.action != CombatComponent.Action.IDLE:
		return false
	var current := equipment.weapon_part()
	if current != &"":
		var old := equipment.unequip(current)
		if old != null:
			old.queue_free()
	var arm := &"arm_r" if equipment.anchors.has(&"arm_r") and combat.anatomy.state.get_part(&"arm_r").is_functional() else equipment.free_arm(combat.anatomy.state)
	if arm == &"":
		return false
	if equipment.equip_definition(weapons[index], arm) == null:
		return false
	weapon_index = index
	weapon_switched.emit(weapons[index])
	return true

## 撿起附近掉落的武器。
func try_pickup() -> bool:
	var best: RigidBody3D = null
	var best_d := pickup_radius
	for n in body().get_parent().get_children():
		if n is RigidBody3D and n.get_meta(&"pickup", false):
			var d: float = (n as Node3D).global_position.distance_to(body().global_position)
			if d < best_d:
				best_d = d
				best = n
	if best == null:
		return false
	var arm := equipment.free_arm(combat.anatomy.state)
	if arm == &"":
		return false
	var weapon_node: Node3D = null
	for c in best.get_children():
		if c.has_meta(&"weapon_def"):
			weapon_node = c
	if weapon_node == null:
		return false
	var cur := equipment.weapon_part()
	if cur != &"":
		return false  # 已持有武器時不撿（之後可做替換）
	best.remove_child(weapon_node)
	best.queue_free()
	equipment.equip(arm, weapon_node)
	var def: WeaponDefinition = weapon_node.get_meta(&"weapon_def")
	if not weapons.has(def):
		weapons.append(def)
	weapon_index = weapons.find(def)
	picked_up.emit(def)
	return true

## 目前的普通攻擊：武器輕攻擊，沒有武器時依序退回拳、踢、咬。
func light_attack() -> AttackDefinition:
	var avail := combat.available_attacks()
	var w := combat.weapon()
	if w != null and w.light_attack in avail:
		return w.light_attack
	for a in avail:
		if not a.requires_weapon:
			return a
	return null

func heavy_attack() -> AttackDefinition:
	var w := combat.weapon()
	if w != null and w.heavy_attack in combat.available_attacks():
		return w.heavy_attack
	return null

func set_tactical_target(target: CombatComponent, part: StringName) -> void:
	tactical_target = target
	tactical_part = part
	tactical_target_changed.emit(part)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or combat.is_dead():
		return
	if event.is_action_pressed(&"attack_light"):
		_attack(light_attack())
	elif event.is_action_pressed(&"attack_heavy"):
		_attack(heavy_attack())
	elif event.is_action_pressed(&"dodge"):
		combat.dodge(_move_input_world())
	elif event.is_action_pressed(&"interact"):
		try_pickup()
	else:
		for i in 3:
			if event.is_action_pressed(StringName("weapon_%d" % (i + 1))):
				switch_weapon(i)

## 指定部位攻擊的 AP 消耗（戰術介面）。AP 不足時改為自動選擇部位。
const TARGETED_AP_COST := 10.0

func _attack(a: AttackDefinition) -> bool:
	if a == null:
		return false
	var part := targeted_part()
	if part != &"" and combat.pools.ap < TARGETED_AP_COST + a.ap_cost:
		part = &""
	if part != &"":
		_face_towards(tactical_target.body().global_position, 1000.0)
	var ok := combat.try_attack(a, part)
	if ok and part != &"":
		combat.pools.spend_ap(TARGETED_AP_COST)
	return ok

## 目前有效的指定部位（目標死亡或部位斷離時自動失效）。
func targeted_part() -> StringName:
	if tactical_target == null or not is_instance_valid(tactical_target) or tactical_target.is_dead() or tactical_part == &"":
		return &""
	if not tactical_part in tactical_target.anatomy.state.targetable_part_ids():
		return &""
	return tactical_part

## 給測試與 UI 使用：以普通攻擊／特殊技出手。
func attack_light() -> bool:
	return _attack(light_attack())

func attack_heavy() -> bool:
	return _attack(heavy_attack())

func _physics_process(delta: float) -> void:
	var b := body()
	var sd := TimeScale.scaled(delta)
	if combat.is_dead():
		b.velocity = Vector3.ZERO
		return
	if input_enabled:
		combat.set_blocking(Input.is_action_pressed(&"block"))
	var dir := _move_input_world() if input_enabled else Vector3.ZERO
	var horizontal := Vector3.ZERO
	if combat.action == CombatComponent.Action.DODGE:
		horizontal = combat.dodge_direction * combat.dodge_speed
	else:
		horizontal = dir * move_speed * combat.movement_multiplier()
	var vy := b.velocity.y - gravity * sd if not b.is_on_floor() else 0.0
	b.velocity = Vector3(horizontal.x, vy, horizontal.z) * TimeScale.combat_scale() if TimeScale.combat_scale() > 0.0 else Vector3.ZERO
	b.move_and_slide()
	if combat.action in [CombatComponent.Action.IDLE, CombatComponent.Action.RECOVERY] and input_enabled:
		var aim = _mouse_ground_point()
		if aim != null:
			_face_towards(aim, sd)

func _face_towards(point: Vector3, sd: float) -> void:
	var b := body()
	var to := point - b.global_position
	to.y = 0
	if to.length() < 0.1:
		return
	var target_yaw := atan2(-to.x, -to.z)
	b.rotation.y = lerp_angle(b.rotation.y, target_yaw, clampf(turn_speed * sd, 0.0, 1.0))

func _move_input_world() -> Vector3:
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if v.length() < 0.01:
		return Vector3.ZERO
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	if camera != null:
		fwd = -camera.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		right = fwd.cross(Vector3.UP).normalized()
	return (right * v.x - fwd * v.y).normalized()

func _mouse_ground_point():
	if camera == null or not camera.is_inside_tree():
		return null
	var vp := camera.get_viewport()
	var mp := vp.get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var normal := camera.project_ray_normal(mp)
	return Plane(Vector3.UP, body().global_position.y).intersects_ray(origin, normal)
