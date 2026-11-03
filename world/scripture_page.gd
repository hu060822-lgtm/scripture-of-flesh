class_name ScripturePage
extends DialogueInteractable
## 《肉身聖典》殘頁（序章收集品，共 6 頁）。閱讀時設定 page_<n> 旗標並顯示收集進度；
## 集滿 6 頁設定 scripture_complete（結局多一段台詞）。對話 id = scripture_page_<n>。

const TOTAL := 6
const COMPLETE_FLAG := &"scripture_complete"

@export_range(1, 6) var page := 1

func _init() -> void:
	kind = "note"
	prompt_text = "E：閱讀聖典殘頁"

static func flag_for(n: int) -> StringName:
	return StringName("page_%d" % n)

static func collected() -> int:
	var n := 0
	for i in range(1, TOTAL + 1):
		if GameState.has_flag(flag_for(i)):
			n += 1
	return n

func _do(player: Node3D) -> bool:
	var first := not GameState.has_flag(flag_for(page))
	GameState.set_flag(flag_for(page))
	if first:
		var n := collected()
		if n >= TOTAL:
			GameState.set_flag(COMPLETE_FLAG)
		var data: PlayerData = player.get_node_or_null("PlayerData")
		if data != null:
			data.message.emit("聖典殘頁 %d／%d" % [n, TOTAL] + ("　—　經文完整了" if n >= TOTAL else ""))
	return super._do(player)

func _build_placeholder() -> void:
	# 發著微弱金光的羊皮紙（PropModels.scripture_leaf）＋一點點光，讓它在暗處被看見
	add_child(PropModels.scripture_leaf())
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color("c9a24a")
	glow.light_energy = 0.5
	glow.omni_range = 1.6
	glow.position = Vector3(0, 0.4, 0)
	add_child(glow)
