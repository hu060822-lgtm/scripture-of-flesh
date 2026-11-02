@tool
class_name BodyPartDef
extends Resource
## 部位的靜態定義。屬於 AnatomyProfile，戰鬥中不會被修改。

enum VitalRule {
	NONE,           ## 失效不致命
	INSTANT_DEATH,  ## 失效或斷離立即死亡（頭、頸、心臟）
	COUNTDOWN,      ## 失效後倒數死亡（肺）
}

## 穩定 ID，存檔與資料參照都用它。例如 &"arm_l"。
@export var id: StringName
@export var display_name: String
@export var max_hp: float = 30.0
## 平減護甲：每次命中先扣除的傷害量。
@export var armor: float = 0.0
## 損傷抗性倍率。key 為損傷類型名稱（"CUT"、"PIERCE"…，見 DamageTypes.Type），value 為倍率，未列出視為 1.0。
## 用名稱而不是數字當 key，讓 .tres 可讀，且日後調整 enum 順序不會讓資料錯位。
@export var resistances: Dictionary = {}
## 此部位提供的能力標籤，例如 grip、locomotion、vision、bite。可重複計數。
@export var functions: PackedStringArray = PackedStringArray()
## 能否被斷離。心臟、脊椎等為 false（仍可功能失效）。
@export var detachable: bool = false
## 物理連接的父部位。父部位斷離時，此部位一併斷離。空字串代表根部位。
@export var parent_id: StringName = &""
## 功能依賴：任一依賴部位不可運作時，此部位功能失效。
@export var dependencies: PackedStringArray = PackedStringArray()
## 位於此部位內部、可被穿刺貫穿到的部位，例如胸腔內的心臟與肺。
@export var internal_parts: PackedStringArray = PackedStringArray()
## 是否為內部器官（無法被直接瞄準，只能經由貫穿命中）。
@export var is_internal: bool = false
@export var vital: VitalRule = VitalRule.NONE
## 斷肢難度倍率。越大越容易斷。
@export var sever_multiplier: float = 1.0
## 部位異化值達到此門檻後，狀態變為 MUTATED。
@export var mutation_threshold: float = 60.0

@export_group("Presentation binding")
## 對應 Skeleton3D 的骨骼名稱（M2 斷肢表現使用）。
@export var bone_name: StringName = &""
## 對應的分段網格節點名稱（M2 斷肢表現使用）。
@export var mesh_segment: StringName = &""

func get_resistance(damage_type: int) -> float:
	return float(resistances.get(DamageTypes.name_of(damage_type), 1.0))
