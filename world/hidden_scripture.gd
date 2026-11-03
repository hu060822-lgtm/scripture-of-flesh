class_name HiddenScripture
extends DialogueInteractable
## 只有「看得見」的人才讀得到的經文（序章提案 A）：
## 身上帶著觀察者的眼柄（relic_eye），或移植了觀察者之眼時才會顯現並可以閱讀。

const SIGHT_ORGAN := &"watcher_eye"
const CHECK_INTERVAL := 0.25

var _check_left := 0.0
var _visible_now := false

static func can_see(player: Node3D) -> bool:
	if player == null:
		return false
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data != null and data.inventory.count(LimbRelic.EYE) > 0:
		return true
	var anatomy: AnatomyComponent = player.get_node_or_null("AnatomyComponent")
	return anatomy != null and anatomy.state != null and SIGHT_ORGAN in anatomy.state.organs.values()

func in_range(player: Node3D) -> bool:
	return super.in_range(player) and can_see(player)

func _ready() -> void:
	super._ready()
	_set_revealed(false)

func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	_set_revealed(can_see(_player()))

func _player() -> Node3D:
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		if n.get_node_or_null("PlayerData") != null:
			return n
	return null

func _set_revealed(on: bool) -> void:
	_visible_now = on
	for c in get_children():
		if c is Node3D:
			c.visible = on

func is_revealed() -> bool:
	return _visible_now

func _build_placeholder() -> void:
	# 牆上發著陳舊金光的經文（PropModels.hidden_glyphs）
	add_child(PropModels.hidden_glyphs())
