class_name TacticalController
extends Node
## 戰術介面（D3）：Tab 開關，預設將戰鬥減速到 10%，P 切換完全暫停。
## 開啟時可選擇目標敵人與部位（滑鼠點擊部位，或 Q／R 循環），
## 之後的攻擊會瞄準該部位，每次消耗 AP（PlayerController.TARGETED_AP_COST）。
## 指定在關閉介面後仍保留，直到目標死亡、部位斷離或手動取消。

signal toggled(active: bool)
signal selection_changed(target: CombatComponent, part: StringName)

const SELECT_RANGE := 12.0

var active := false
var controller: PlayerController
var camera: Camera3D

func _ready() -> void:
	controller = get_parent().get_node("PlayerController")
	InputSetup.ensure_actions()

func toggle() -> void:
	set_active(not active)

func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	TimeScale.set_mode(TimeScale.Mode.SLOW if on else TimeScale.Mode.NORMAL)
	if on and (controller.tactical_target == null or controller.tactical_target.is_dead()):
		select_target(nearest_enemy())
	toggled.emit(on)

func toggle_pause() -> void:
	if not active:
		return
	TimeScale.set_mode(TimeScale.Mode.SLOW if TimeScale.mode == TimeScale.Mode.PAUSE else TimeScale.Mode.PAUSE)

func nearest_enemy() -> CombatComponent:
	var me: Node3D = controller.body()
	var best: CombatComponent = null
	var best_d := SELECT_RANGE
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var c: CombatComponent = n.get_node_or_null("CombatComponent")
		if c == null or c == controller.combat or c.is_dead() or c.faction == controller.combat.faction:
			continue
		var d := (n as Node3D).global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best

func select_target(target: CombatComponent, part: StringName = &"") -> void:
	if target == null:
		controller.set_tactical_target(null, &"")
	else:
		var parts := target.anatomy.state.targetable_part_ids()
		var p := part if part in parts else (&"chest" if &"chest" in parts else (parts[0] if not parts.is_empty() else &""))
		controller.set_tactical_target(target, p)
	selection_changed.emit(controller.tactical_target, controller.tactical_part)

func clear() -> void:
	select_target(null)

## 在目標的可命中部位中循環。
func cycle_part(step: int) -> void:
	var t := controller.tactical_target
	if t == null or t.is_dead():
		return
	var parts := t.anatomy.state.targetable_part_ids()
	if parts.is_empty():
		return
	var i := parts.find(controller.tactical_part)
	i = (i + step + parts.size()) % parts.size() if i >= 0 else 0
	select_target(t, parts[i])

## 預估目前普通攻擊打在指定部位的結果。
func preview_light() -> DamageResult:
	var t := controller.tactical_target
	var part := controller.targeted_part()
	var a := controller.light_attack()
	if t == null or part == &"" or a == null:
		return null
	return t.anatomy.preview(controller.combat.build_packet(a, part))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tactical"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event.is_action_pressed(&"tactical_pause"):
		toggle_pause()
	elif event.is_action_pressed(&"target_next"):
		cycle_part(1)
	elif event.is_action_pressed(&"target_prev"):
		cycle_part(-1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pick_part_at(event.position):
			get_viewport().set_input_as_handled()  # 戰術介面中點部位不會順便攻擊

func _pick_part_at(screen_pos: Vector2) -> bool:
	if camera == null:
		return false
	var from := camera.project_ray_origin(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen_pos) * 60.0, Hurtbox.LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit["collider"] is Hurtbox:
		return false
	var hb: Hurtbox = hit["collider"]
	var node: Node = hb
	while node != null and not node.has_node("CombatComponent"):
		node = node.get_parent()
	if node == null:
		return false
	var c: CombatComponent = node.get_node("CombatComponent")
	if c == controller.combat or c.faction == controller.combat.faction:
		return false
	select_target(c, hb.part_id)
	return true
