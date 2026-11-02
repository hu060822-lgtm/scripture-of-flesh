class_name Interactable
extends Node3D
## 可互動物件的基底類別（E 鍵）。銘文、NPC、武器台、物品、Boss 門等都繼承它。
## 子類別覆寫 _do()；once = true 的物件互動後記錄到 GameState.taken，讀檔後保持已使用狀態。
## 沒有子節點時會自動生成【暫代】灰盒外觀；美術可在場景中直接放入正式模型取代。

signal interacted(player: Node3D)
## 需要開啟對話時發出，由遊戲控制器接手（物件本身不依賴 UI）。
signal dialogue_requested(dialogue_id: String, player: Node3D)

const GROUP := &"world_interactables"

@export var object_id: StringName = &""
@export var interact_radius: float = 1.8
@export var prompt_text: String = "E：調查"
@export var once: bool = false
## 只有此旗標成立時才能互動（空 = 無條件），例如 Boss 死後才出現的胎房。
@export var require_flag: StringName = &""

func _ready() -> void:
	add_to_group(GROUP)
	if get_child_count() == 0:
		_build_placeholder()
	if once and is_used():
		_on_used()

func is_used() -> bool:
	return object_id != &"" and GameState.taken.has(object_id)

func in_range(player: Node3D) -> bool:
	return player.global_position.distance_to(global_position) <= interact_radius

func available() -> bool:
	if require_flag != &"" and not GameState.has_flag(require_flag):
		return false
	return not (once and is_used())

func prompt() -> String:
	return prompt_text

func interact(player: Node3D) -> bool:
	if not available():
		return false
	if not _do(player):
		return false
	if once and object_id != &"":
		GameState.taken[object_id] = true
		_on_used()
	interacted.emit(player)
	return true

## 實際效果。回傳 false 表示這次互動沒有發生（不會標記為已使用）。
func _do(_player: Node3D) -> bool:
	return true

## 已使用後的外觀變化（例如武器從台座上消失）。
func _on_used() -> void:
	pass

func _build_placeholder() -> void:
	pass

static func placeholder_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, name: String = "Placeholder") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	parent.add_child(mi)
	return mi

## 最近的可互動物件（距離內、仍可用）。
static func nearest(tree: SceneTree, player: Node3D) -> Interactable:
	var best: Interactable = null
	var best_d := INF
	for n in tree.get_nodes_in_group(GROUP):
		var it := n as Interactable
		if it == null or not it.available() or not it.in_range(player):
			continue
		var d := it.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best
