@tool
class_name SkillDefinition
extends Resource
## 技能樹節點。效果以資料描述，由 ProgressionComponent 套用。
## 支援的效果 key：
##   "damage_scale:<weapon_type>"：該武器類型傷害倍率加成（0.1 = +10%）
##   "bleed_resist"：出血速率降低比例
##   "suture_speed"：緊急縫合時間縮短比例
##   "compatibility"：器官相容性加成
##   "mutation_resist"：異化抗性加成
##   "ap_gain"：命中 AP 加成（點數）

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var cost: int = 1
@export var prerequisites: Array[StringName] = []
@export var effects: Dictionary = {}
