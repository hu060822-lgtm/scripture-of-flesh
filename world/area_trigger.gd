class_name AreaTrigger
extends Node3D
## 區域觸發：玩家進入半徑內時觸發一次（可選：設定旗標、播放對話）。
## 以距離判定（不依賴物理），所以在戰術減速與測試中都可靠。

signal triggered(trigger_id: StringName, player: Node3D)
signal dialogue_requested(dialogue_id: String, player: Node3D)

const GROUP := &"area_triggers"

@export var trigger_id: StringName = &""
@export var radius: float = 2.5
@export var set_flag: StringName = &""
## 進入時顯示的區域名稱（空 = 不顯示）。
@export var area_name: String = ""
@export var dialogue_id: String = ""
## 只有此旗標成立時才會觸發（空 = 無條件）。
@export var require_flag: StringName = &""

func _ready() -> void:
	add_to_group(GROUP)

func done() -> bool:
	return trigger_id != &"" and GameState.taken.has(trigger_id)

func _physics_process(_delta: float) -> void:
	check()

func check() -> bool:
	if done() or (require_flag != &"" and not GameState.has_flag(require_flag)):
		return false
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var c: CombatComponent = n.get_node_or_null("CombatComponent")
		if c == null or c.faction != &"player" or c.is_dead():
			continue
		var b := n as Node3D
		var d := b.global_position - global_position
		d.y = 0
		if d.length() <= radius:
			fire(b)
			return true
	return false

func fire(player: Node3D) -> void:
	if trigger_id != &"":
		GameState.taken[trigger_id] = true
	if set_flag != &"":
		GameState.set_flag(set_flag)
	triggered.emit(trigger_id, player)
	if dialogue_id != "":
		dialogue_requested.emit(dialogue_id, player)
