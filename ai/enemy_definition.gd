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
## 特殊行為：&"restitch"（縫屍者）、&"" 無。
@export var special_behavior: StringName = &""
## 斷肢反應持續秒數。
@export var dismember_react_seconds: float = 0.8
