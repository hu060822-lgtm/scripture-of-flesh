@tool
class_name OrganDefinition
extends Resource
## 可移植的器官或義肢。template 是新的部位定義樣板：移植時複製一份，
## 保留受體部位的 ID、父部位、依賴與骨骼綁定，再換上樣板的 HP、護甲、抗性與功能。

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## 可以移植到哪些部位，例如 ["arm_l", "arm_r"]。
@export var slots: PackedStringArray = PackedStringArray()
@export var template: BodyPartDef
## 來源：&"human"、&"abomination"（怪物）、&"mechanical"（義肢）。
@export var origin: StringName = &"abomination"
## 基礎相容性 0–1。最終相容性另加技術（TEC）與技能加成。
@export_range(0.0, 1.0) var base_compatibility: float = 0.6
## 移植後增加的異化。
@export var mutation_cost: float = 10.0
## 需要的最低技術（義肢）。
@export var min_tec: int = 0
## 必定相容（劇情給予的器官，例如阿格妮絲縫的手臂：序章第一次移植不會被排斥）。
@export var guaranteed: bool = false
## 從屍體摘取時，捐贈者身上必須仍然完好的部位。
@export var harvest_part: StringName = &""
