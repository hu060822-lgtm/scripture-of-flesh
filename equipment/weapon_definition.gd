@tool
class_name WeaponDefinition
extends Resource
## 武器資料。武器類型決定損傷類型比重、出血、骨骼破壞與斷肢能力。

@export var id: StringName
@export var display_name: String
@export var weapon_type: StringName = &"blade"
## key 為損傷類型名稱，例如 {"CUT": 16, "LACERATION": 4}
@export var damage: Dictionary = {}
@export var sever_power: float = 1.0
@export var armor_penetration: float = 0.0
@export var bleed_multiplier: float = 1.0
## 需要幾隻可用的手（grip）。雙手武器在失去一隻手後無法使用。
@export var required_grip: int = 1
@export var light_attack: AttackDefinition
## 特殊技能，消耗 AP。
@export var heavy_attack: AttackDefinition

func attacks() -> Array[AttackDefinition]:
	var out: Array[AttackDefinition] = []
	if light_attack != null:
		out.append(light_attack)
	if heavy_attack != null:
		out.append(heavy_attack)
	return out
