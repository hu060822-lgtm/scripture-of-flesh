class_name BodyPartState
extends RefCounted
## 單一部位的戰鬥即時狀態。只由 AnatomyState 修改。

var def: BodyPartDef
var hp: float
## 各損傷類型的累積量。key 為 DamageTypes.Type。
var injuries := {}
## 出血速率（部位 HP 換算／秒），由 AnatomyState.tick 計入失血。
var bleed_rate: float = 0.0
## 部位異化值 0–100。
var mutation: float = 0.0
var severed: bool = false
## 自身造成的失效（HP 歸零、骨折）。
var own_disabled: bool = false
## 因依賴部位不可運作而失效。由 AnatomyState 重新計算。
var dependency_disabled: bool = false

func _init(definition: BodyPartDef) -> void:
	def = definition
	hp = definition.max_hp

var id: StringName:
	get: return def.id

func injury(t: int) -> float:
	return float(injuries.get(t, 0.0))

func is_functional() -> bool:
	return not severed and not own_disabled and not dependency_disabled

func is_mutated() -> bool:
	return mutation >= def.mutation_threshold

func hp_ratio() -> float:
	return hp / def.max_hp

## 狀態優先序：斷離 > 功能失效 > 異化 > 嚴重受損 > 受損 > 完整。
func status() -> int:
	if severed:
		return AnatomyTypes.PartStatus.SEVERED
	if own_disabled or dependency_disabled:
		return AnatomyTypes.PartStatus.DISABLED
	if is_mutated():
		return AnatomyTypes.PartStatus.MUTATED
	var r := hp_ratio()
	if r < AnatomyTypes.SEVERELY_DAMAGED_RATIO:
		return AnatomyTypes.PartStatus.SEVERELY_DAMAGED
	if r < AnatomyTypes.DAMAGED_RATIO:
		return AnatomyTypes.PartStatus.DAMAGED
	return AnatomyTypes.PartStatus.INTACT
