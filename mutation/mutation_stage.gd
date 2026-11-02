@tool
class_name MutationStage
extends Resource
## 異化階段。異化不是善惡值：每個階段同時帶來能力、代價與感官／劇情變化。

@export var id: StringName
@export var display_name: String
@export var threshold: float = 25.0
@export_multiline var description: String
## 效果 key：
##   "anatomical_sight"：戰術介面顯示內臟 HP 與敵人剩餘攻擊手段（感官）
##   "grant_attack:<attack id>"：獲得天生攻擊（身體）
##   "max_st"：體力上限加成
##   "part_regen"：每秒部位 HP 再生（身體）
##   "heal_penalty"：祭壇治療時額外增加的異化（代價）
##   "ap_bonus"：命中 AP 加成
@export var effects: Dictionary = {}
## 進入此階段時設定的劇情旗標。
@export var story_flag: StringName = &""
