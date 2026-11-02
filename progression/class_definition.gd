@tool
class_name ClassDefinition
extends Resource
## 起始職業。只決定起點（屬性、武器、技能），不限制之後的成長。

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var stats: CharacterStats
@export var starting_weapon: WeaponDefinition
@export var starting_skills: Array[StringName] = []
@export var starting_items: Dictionary = {}  ## item_id -> count
