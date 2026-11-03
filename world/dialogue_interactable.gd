class_name DialogueInteractable
extends Interactable
## 銘文、筆記或 NPC：互動時開啟對話。NPC 第一次對話後改用 repeat_dialogue_id。

@export var dialogue_id: String = ""
@export var repeat_dialogue_id: String = ""
## 第一次對話完成的旗標（例如 met_agnes）；設定後改用 repeat_dialogue_id。
@export var first_done_flag: StringName = &""
@export_enum("inscription", "npc", "note") var kind: String = "inscription"
## NPC 的外觀（CreatureModels.LOOKS 的 id）與姿勢（NpcFigure）。空 = 依 object_id 查 NPC_LOOKS。
@export var npc_look: StringName = &""
@export var npc_pose: String = ""

## object_id -> [外觀, 姿勢]
const NPC_LOOKS := {
	&"npc_agnes": [&"agnes", "pray"],
	&"npc_ignatius": [&"ignatius", "slumped"],
}

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
		var preset: Array = NPC_LOOKS.get(object_id, [&"humanoid", "pray"])
		var look: StringName = npc_look if npc_look != &"" else preset[0]
		var pose: String = npc_pose if npc_pose != "" else preset[1]
		add_child(NpcFigure.create(look, pose))
	elif kind == "note":
		add_child(PropModels.note())
	else:
		add_child(PropModels.inscription_tablet())
