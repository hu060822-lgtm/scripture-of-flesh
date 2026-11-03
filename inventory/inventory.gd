class_name Inventory
extends RefCounted
## 物品與素材（含摘取的器官）。以 ID 計數。

signal changed

const ITEM_NAMES := {
	"suture_kit": "緊急縫合包",
	"umbilical_key": "臍帶鑰匙",
	"blood_vial": "濁血瓶",
	"relic_hand": "多手人的斷手",
	"relic_eye": "觀察者的眼柄",
	"relic_leg": "反足者的斷腿",
}

var items := {}  # id(String) -> count

func add(id: String, count: int = 1) -> void:
	items[id] = int(items.get(id, 0)) + count
	changed.emit()

func remove(id: String, count: int = 1) -> bool:
	if int(items.get(id, 0)) < count:
		return false
	items[id] = int(items[id]) - count
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	return true

func count(id: String) -> int:
	return int(items.get(id, 0))

## 器官以 "organ:<id>" 存放。
func organs() -> Array[OrganDefinition]:
	var out: Array[OrganDefinition] = []
	for k in items:
		if String(k).begins_with("organ:"):
			var o := OrganRegistry.get_organ(StringName(String(k).substr(6)))
			if o != null:
				out.append(o)
	return out

static func display_name(id: String) -> String:
	if id.begins_with("organ:"):
		var o := OrganRegistry.get_organ(StringName(id.substr(6)))
		return o.display_name if o != null else id
	return ITEM_NAMES.get(id, id)

func to_save() -> Dictionary:
	return items.duplicate()

func load_save(d: Dictionary) -> void:
	items = d.duplicate()
	changed.emit()
