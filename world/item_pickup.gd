class_name ItemPickup
extends Interactable
## 地上的物品（縫合包、臍帶鑰匙等）。

@export var item_id: String = ""
@export var count: int = 1
## 拾取後附在訊息後面的提示（例如「在祭壇按 T 移植」）。
@export var hint_text: String = ""

func _init() -> void:
	once = true

func prompt() -> String:
	return "E：拾取%s" % Inventory.display_name(item_id)

func _do(player: Node3D) -> bool:
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data == null or item_id == "":
		return false
	data.inventory.add(item_id, count)
	var msg := "獲得 %s ×%d" % [Inventory.display_name(item_id), count]
	if hint_text != "":
		msg += "　—　" + hint_text
	data.message.emit(msg)
	return true

func _on_used() -> void:
	set_process(false)
	for c in get_children():
		if c is Node3D:
			c.visible = false

func _build_placeholder() -> void:
	add_child(PropModels.item(item_id, count))
	_glints.clear()
	for n in find_children("*", "MeshInstance3D", true, false):
		if n.has_meta(PropModels.GLINT_META):
			_glints.append([n, (n as Node3D).scale])

## 「可以撿」的提示：關鍵部位（針、鑰匙、眼球…）每 1.6 秒微微脹一下（PS1 式的低幀率脈動）。
const GLINT_PERIOD := 1.6
var _glints: Array = []  # [MeshInstance3D, 原本的 scale]
var _t := 0.0

func _process(delta: float) -> void:
	if _glints.is_empty():
		return
	_t += delta
	var on := fmod(_t, GLINT_PERIOD) < 0.25
	for g in _glints:
		(g[0] as Node3D).scale = (g[1] as Vector3) * (1.15 if on else 1.0)
