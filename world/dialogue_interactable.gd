class_name DialogueInteractable
extends Interactable
## 銘文或 NPC：互動時開啟對話。NPC 第一次對話後改用 repeat_dialogue_id。

@export var dialogue_id: String = ""
@export var repeat_dialogue_id: String = ""
## 第一次對話完成的旗標（例如 met_agnes）；設定後改用 repeat_dialogue_id。
@export var first_done_flag: StringName = &""
@export_enum("inscription", "npc") var kind: String = "inscription"

func current_dialogue() -> String:
	if repeat_dialogue_id != "" and first_done_flag != &"" and GameState.has_flag(first_done_flag):
		return repeat_dialogue_id
	return dialogue_id

func _do(player: Node3D) -> bool:
	var id := current_dialogue()
	if id == "":
		return false
	dialogue_requested.emit(id, player)
	return true

func _build_placeholder() -> void:
	if kind == "npc":
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 1.7
		Interactable.placeholder_mesh(self, cap, Vector3(0, 0.85, 0), Color("2a2725"))
		var hood := SphereMesh.new()
		hood.radius = 0.18
		hood.height = 0.36
		Interactable.placeholder_mesh(self, hood, Vector3(0, 1.75, 0), Color("e8e2d6"), "Hood")
	else:
		var slab := BoxMesh.new()
		slab.size = Vector3(0.9, 1.2, 0.18)
		Interactable.placeholder_mesh(self, slab, Vector3(0, 0.6, 0), Color("6b625a"))
