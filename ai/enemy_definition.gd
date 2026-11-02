@tool
class_name EnemyDefinition
extends Resource
## 敵人的靜態資料（三層資料之一：EnemyDefinition／AnatomyProfile／EnemyRuntimeState）。

@export var id: StringName
@export var display_name: String
@export var anatomy_profile: AnatomyProfile
@export var attacks: Array[AttackDefinition] = []
## 可選：手持武器，裝在第一隻可用的手上。
@export var weapon: WeaponDefinition
@export var max_hp: float = 80.0
@export var max_st: float = 80.0
@export var move_speed: float = 2.6
@export var sever_chance_scale: float = 1.0
@export var stagger_threshold: float = 12.0
@export var xp_reward: int = 40
## 死後可摘取的器官（捐贈部位必須完好）。
@export var harvestable: Array[OrganDefinition] = []

## 暫代外觀：移動碰撞膠囊與整體縮放（Boss 較大、未生者較小）。
@export var collision_radius: float = 0.32
@export var collision_height: float = 1.8
@export var visual_scale: float = 1.0

@export_group("Perception")
@export var sight_range: float = 9.0
@export var sight_fov_degrees: float = 140.0
## 偵測時需要 vision 能力。失去眼睛後只能靠聽覺。
@export var needs_vision: bool = true
@export var hearing_range: float = 3.0
## 失去目標後追蹤上次位置的秒數。
@export var memory_seconds: float = 4.0

@export_group("Behavior")
## 偏好與目標保持的距離（遠程型敵人較大）。
@export var preferred_range: float = 1.4
@export_range(0.0, 1.0) var retreat_hp_ratio: float = 0.15
@export_range(0.0, 1.0) var defend_chance: float = 0.15
@export_range(0.0, 1.0) var dodge_chance: float = 0.1
@export var decision_interval: float = 0.35
@export var patrol_radius: float = 3.0
## 特殊行為：&"restitch"（縫屍者）、&"boss"（由 BossPhaseComponent 控制階段）、&"" 無。
@export var special_behavior: StringName = &""
## 斷肢反應持續秒數。
@export var dismember_react_seconds: float = 0.8

@export_group("Tactics")
## 以下為 AI-2 戰術個性（0..1）。【暫代】初值，未經遊玩測試；全域難度見 Tactics.difficulty。
## 進攻慾：越高越常直接出手、越少繞圈等待。
@export_range(0.0, 1.0) var aggression: float = 0.5
## 謹慎：越高越常後退、防禦；受傷時再加成。
@export_range(0.0, 1.0) var caution: float = 0.3
## 耐心：在攻擊距離外繞圈等待時機的傾向。
@export_range(0.0, 1.0) var patience: float = 0.5
## 側翼：繞到目標側面／背後的傾向（玩家防禦只擋正面）。
@export_range(0.0, 1.0) var flank_tendency: float = 0.3
## 打帶跑：出手後立刻拉開距離。
@export_range(0.0, 1.0) var hit_and_run: float = 0.0
## 趁隙：玩家收招、僵直、耐力見底時進攻的敏銳度。
@export_range(0.0, 1.0) var punish_skill: float = 0.5
## 適應：依玩家習慣（常防禦／常閃避）調整打法的程度。
@export_range(0.0, 1.0) var adaptivity: float = 0.5
## 優先攻擊玩家受傷部位的機率（luz 決定：中等，約 40%）。
@export_range(0.0, 1.0) var injured_target_bias: float = 0.4
