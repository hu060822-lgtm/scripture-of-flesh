class_name PalmLock
extends Interactable
## 掌紋鎖（序章提案 A）：把撿來的斷手按上去才會打開的櫃子。打開後給予獎勵物品。
## 沒有斷手時只顯示線索，不會被標記為已使用。

@export var required_item: String = LimbRelic.HAND
## 物品 id -> 數量
@export var rewards: Dictionary = {}
@export var locked_text: String = "鎖上刻著一隻六指的掌印。需要一隻不屬於人類的手。"
@export var open_text: String = "斷手的指節一根根卡進掌紋，櫃門無聲地滑開。"

func _init() -> void:
	once = true

func has_key(player: Node3D) -> bool:
	var data: PlayerData = player.get_node_or_null("PlayerData")
	return data != null and data.inventory.count(required_item) > 0

func prompt() -> String:
	return "E：調查掌紋鎖"

func _do(player: Node3D) -> bool:
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data == null:
		return false
	if not data.inventory.remove(required_item):
		data.message.emit(locked_text)
		return false
	var got := []
	for id in rewards:
		data.inventory.add(String(id), int(rewards[id]))
		got.append("%s ×%d" % [Inventory.display_name(String(id)), int(rewards[id])])
	data.message.emit("%s　獲得 %s" % [open_text, "、".join(got)])
	return true

func _on_used() -> void:
	var door := get_node_or_null("Door") as Node3D
	if door != null:
		door.visible = false

func _build_placeholder() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 2.0, 0.5)
	Interactable.placeholder_mesh(self, box, Vector3(0, 1.0, -0.15), Color("4a1a14"), "Cabinet")
	var door := BoxMesh.new()
	door.size = Vector3(1.3, 1.9, 0.06)
	Interactable.placeholder_mesh(self, door, Vector3(0, 1.0, 0.13), Color("6a2a20"), "Door")
	var palm := BoxMesh.new()
	palm.size = Vector3(0.3, 0.36, 0.04)
	var mi := Interactable.placeholder_mesh(get_node("Door"), palm, Vector3(0, 0.1, 0.05), Color("c9a27a"), "Palm")
	var mat := mi.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = Color("c9a27a")
	mat.emission_energy_multiplier = 0.5
