class_name LimbRelic
extends Interactable
## 「肢解即工具」（序章提案 A）：某些敵人被砍下的部位可以撿起來當道具。
## 掛在 SeveredPart（殘肢）底下，跟著殘肢移動；撿起後殘肢消失，物品進入背包。
##   多手人的手臂 → relic_hand（按在聖器室的掌紋鎖上；也可以丟出去引開敵人）
##   無面觀察者的眼柄 → relic_eye（拿在身上時看得見藏書室的隱藏經文）
##   反足者的腿 → relic_leg（丟出去製造聲響，引開敵人）

const HAND := "relic_hand"
const EYE := "relic_eye"
const LEG := "relic_leg"
## 可以丟出去的殘肢，依丟出優先順序。
const THROWABLE := [LEG, HAND]
## [身體模板 id, 部位 id 前綴] -> 物品 id
const RULES := [
	[&"multi_armed", "arm_", HAND],
	[&"faceless", "stalk_", EYE],
	[&"reverse_legged", "leg_", LEG],
]
## 第一次撿到時的提示
const FIRST_HINTS := {
	HAND: "六根手指的掌紋……也許能打開什麼",
	EYE: "眼柄還在轉動。握著它，牆上浮現出原本看不見的字",
	LEG: "G：把殘肢丟出去，製造聲響引開敵人",
}

@export var item_id: String = ""

## 依來源身體與部位決定這塊殘肢能不能撿（空字串 = 不能）。
static func item_for(profile_id: StringName, part_id: StringName) -> String:
	for r in RULES:
		if profile_id == r[0] and String(part_id).begins_with(r[1]):
			return r[2]
	return ""

## 若這塊殘肢是可用的部位，掛上撿取互動，並讓殘肢不會自動消失。
static func attach_if_relic(gib: SeveredPart, profile_id: StringName, part_id: StringName) -> LimbRelic:
	var id := item_for(profile_id, part_id)
	if id == "" or gib == null:
		return null
	return attach(gib, id)

static func attach(gib: Node3D, id: String) -> LimbRelic:
	var r := LimbRelic.new()
	r.name = "LimbRelic"
	r.item_id = id
	r.interact_radius = 1.6
	if gib is SeveredPart:
		(gib as SeveredPart).keep = true
	gib.add_child(r)
	return r

func prompt() -> String:
	return "E：撿起%s" % Inventory.display_name(item_id)

func _do(player: Node3D) -> bool:
	var data: PlayerData = player.get_node_or_null("PlayerData")
	if data == null:
		return false
	var first := data.inventory.count(item_id) == 0 and not GameState.has_flag(StringName("relic_seen_" + item_id))
	data.inventory.add(item_id)
	GameState.set_flag(StringName("relic_seen_" + item_id))
	var msg := "撿起了%s" % Inventory.display_name(item_id)
	if first and FIRST_HINTS.has(item_id):
		msg += "　—　" + String(FIRST_HINTS[item_id])
	data.message.emit(msg)
	var gib := get_parent()
	if gib != null:
		gib.queue_free()
	return true
