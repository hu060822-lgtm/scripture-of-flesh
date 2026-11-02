class_name BossGate
extends Interactable
## 需要條件才能開啟的門（條件格式同對話條件，例如 {"has_item": "umbilical_key"}）。
## 未達成：播放 locked_dialogue_id；達成：播放 open_dialogue_id 並移除阻擋。

signal opened

@export var condition: Dictionary = {}
@export var locked_dialogue_id: String = ""
@export var open_dialogue_id: String = ""
@export var gate_size: Vector3 = Vector3(4, 4, 0.5)

func _init() -> void:
	once = true
	prompt_text = "E：推門"

func condition_met(player: Node3D) -> bool:
	var r := DialogueRunner.new()
	r.player = player
	return r.check(condition)

func is_open() -> bool:
	return is_used()

func _do(player: Node3D) -> bool:
	if not condition_met(player):
		if locked_dialogue_id != "":
			dialogue_requested.emit(locked_dialogue_id, player)
		return false
	if open_dialogue_id != "":
		dialogue_requested.emit(open_dialogue_id, player)
	return true

func _on_used() -> void:
	var blocker := get_node_or_null("Blocker")
	if blocker != null:
		blocker.queue_free()
		remove_child(blocker)
	opened.emit()

func _build_placeholder() -> void:
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = PlaceholderBodyBuilder.WORLD_LAYER | PlaceholderBodyBuilder.CREATURE_LAYER
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = gate_size
	cs.shape = shape
	cs.position = Vector3(0, gate_size.y * 0.5, 0)
	body.add_child(cs)
	var m := BoxMesh.new()
	m.size = gate_size
	Interactable.placeholder_mesh(body, m, Vector3(0, gate_size.y * 0.5, 0), Color("5a1a14"), "Door")
	add_child(body)
