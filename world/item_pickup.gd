class_name ItemPickup
extends Interactable
## 地上的物品（縫合包、臍帶鑰匙等）。

@export var item_id: String = ""
@export var count: int = 1

func _init() -> void:
	once = true

func prompt() -> String:
	return "E：拾取%s" % Inventory.display_name(item_id)

func _do(player: Node3D) -> bool:
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data == null or item_id == "":
		return false
	data.inventory.add(item_id, count)
	data.message.emit("獲得 %s ×%d" % [Inventory.display_name(item_id), count])
	return true

func _on_used() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false

func _build_placeholder() -> void:
	var m := SphereMesh.new()
	m.radius = 0.15
	m.height = 0.3
	Interactable.placeholder_mesh(self, m, Vector3(0, 0.4, 0), Color("a04a3e"))
