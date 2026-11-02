@tool
class_name AttackDefinition
extends Resource
## 一種攻擊的資料。玩家與敵人共用。攻擊以能力需求宣告「需要什麼身體」，
## 斷肢後不符合需求的攻擊會自動不可用（AI 與玩家同理）。

@export var id: StringName
@export var display_name: String
## 能力需求，例如 {"grip": 1}、{"bite": 1}、{"grip": 4}。
@export var required_capabilities: Dictionary = {}
## true：傷害來自手上武器（WeaponDefinition），並需要持有武器。
@export var requires_weapon: bool = false
@export var st_cost: float = 15.0
## 大於 0 代表這是特殊技能，消耗 AP。
@export var ap_cost: float = 0.0
@export_group("Timing (seconds)")
@export var windup: float = 0.4
@export var active: float = 0.1
@export var recovery: float = 0.4
@export_group("Reach")
@export var reach: float = 1.6
## 攻擊扇形角度（度）。
@export var arc_degrees: float = 90.0
## 預設瞄準高度（公尺）。未指定部位時，命中最接近此高度攻擊點的部位。
@export var aim_height: float = 1.3
@export_group("Damage")
## 徒手／天生攻擊的傷害；武器攻擊時為「額外」傷害。key 為損傷類型名稱。
@export var damage: Dictionary = {}
## 武器攻擊時，武器傷害的倍率。
@export var damage_scale: float = 1.0
## 徒手攻擊的斷肢能力；武器攻擊時為武器斷肢能力的倍率。
@export var sever_power: float = 1.0
@export var armor_penetration_bonus: float = 0.0
## 單次命中造成的部位 HP 損失超過此值時，目標硬直。
@export var stagger_threshold_bonus: float = 0.0
@export_group("AI")
@export var ai_weight: float = 1.0
@export var cooldown: float = 0.0
## 偏好攻擊的部位（例如縫屍者偏好抓手臂）。空字串代表依瞄準高度決定。
@export var preferred_target_part: StringName = &""
@export var tags: PackedStringArray = PackedStringArray()

func total_duration() -> float:
	return windup + active + recovery
