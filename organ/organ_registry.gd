class_name OrganRegistry
extends RefCounted
## 以 ID 查詢器官資料（存檔還原用）。

const DIR := "res://content/organs"
static var _cache := {}

static func get_organ(id: StringName) -> OrganDefinition:
	if _cache.is_empty():
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".tres"):
				var o: OrganDefinition = load(DIR.path_join(f))
				_cache[o.id] = o
	return _cache.get(id)

## 給 AnatomyState.from_save 使用：器官 ID → 部位定義（需要知道部位，因此回傳 Callable）。
static func lookup_for(profile: AnatomyProfile) -> Callable:
	return func(organ_id: StringName) -> BodyPartDef:
		var o := get_organ(organ_id)
		if o == null:
			return null
		for slot in o.slots:
			var cur := profile.get_part(StringName(slot))
			if cur != null:
				return TransplantService.build_definition(o, cur)
		return null
