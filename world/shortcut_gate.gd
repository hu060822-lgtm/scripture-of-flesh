class_name ShortcutGate
extends BossGate
## 捷徑門（序章提案 D）：只能從正面（本地 -Z 那一側）拉開門閂；從背面只會看到「從另一邊閂住了」。
## 打開後永久開啟（GameState.taken），讓祭壇與遠處的區域連成一圈。

@export var locked_text: String = "門從另一邊閂住了。"

func _init() -> void:
	super._init()
	prompt_text = "E：拉開門閂"

func condition_met(player: Node3D) -> bool:
	return to_local(player.global_position).z < 0.0

func _do(player: Node3D) -> bool:
	if not condition_met(player):
		var data: PlayerData = player.get_node_or_null("PlayerData")
		if data != null:
			data.message.emit(locked_text)
		return false
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data != null:
		data.message.emit("門閂拉開了。回祭壇的捷徑。")
	return true
