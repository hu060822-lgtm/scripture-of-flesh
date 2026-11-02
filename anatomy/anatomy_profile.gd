@tool
class_name AnatomyProfile
extends Resource
## 一個生物的身體結構模板：任意數量的部位定義。
## 人形、多手人、反足者都只是不同的 AnatomyProfile。

@export var id: StringName
@export var display_name: String
@export var parts: Array[BodyPartDef] = []

func get_part(part_id: StringName) -> BodyPartDef:
	for p in parts:
		if p.id == part_id:
			return p
	return null

func has_part(part_id: StringName) -> bool:
	return get_part(part_id) != null

## 驗證資料是否一致。回傳錯誤訊息清單，空陣列代表通過。
## 檢查：重複 ID、缺少的父部位／依賴／內部部位、父子循環、依賴循環。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	for p in parts:
		if p == null:
			errors.append("null part entry")
			continue
		if p.id == &"":
			errors.append("part with empty id")
		if ids.has(p.id):
			errors.append("duplicate part id: %s" % p.id)
		ids[p.id] = p
		if p.max_hp <= 0.0:
			errors.append("%s: max_hp must be > 0" % p.id)
		for k in p.resistances:
			if not DamageTypes.Type.has(String(k)):
				errors.append("%s: unknown resistance key %s" % [p.id, k])
	for p in parts:
		if p == null:
			continue
		if p.parent_id != &"" and not ids.has(p.parent_id):
			errors.append("%s: missing parent %s" % [p.id, p.parent_id])
		for d in p.dependencies:
			if not ids.has(StringName(d)):
				errors.append("%s: missing dependency %s" % [p.id, d])
		for i in p.internal_parts:
			if not ids.has(StringName(i)):
				errors.append("%s: missing internal part %s" % [p.id, i])
	# 父子循環
	for p in parts:
		if p == null:
			continue
		var seen := {}
		var cur: BodyPartDef = p
		while cur != null and cur.parent_id != &"":
			if seen.has(cur.id):
				errors.append("%s: parent cycle" % p.id)
				break
			seen[cur.id] = true
			cur = ids.get(cur.parent_id)
	# 依賴循環（DFS）
	var state := {}  # 0 = 未訪, 1 = 訪問中, 2 = 完成
	for p in parts:
		if p != null and _dep_cycle(p.id, ids, state):
			errors.append("dependency cycle involving %s" % p.id)
			break
	return errors

func _dep_cycle(pid: StringName, ids: Dictionary, state: Dictionary) -> bool:
	var s: int = state.get(pid, 0)
	if s == 1:
		return true
	if s == 2 or not ids.has(pid):
		return false
	state[pid] = 1
	for d in (ids[pid] as BodyPartDef).dependencies:
		if _dep_cycle(StringName(d), ids, state):
			return true
	state[pid] = 2
	return false
