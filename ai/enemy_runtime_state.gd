class_name EnemyRuntimeState
extends RefCounted
## 敵人戰鬥即時狀態（三層資料之三）。解剖狀態在 AnatomyState，這裡只放 AI 狀態。

var state_name: StringName = &"patrol"
var time_in_state := 0.0
var target: CombatComponent
var last_known_position := Vector3.ZERO
var time_since_seen := INF
var alert := 0.0
var home := Vector3.ZERO
var patrol_point := Vector3.ZERO
var decision_timer := 0.0
var last_severed_part: StringName = &""
## 搜索／調查的目標位置（聽到的聲響或最後看到目標的地方）。
var investigate_point := Vector3.INF
## AI-2：目前的戰術意圖、繞圈方向、距離上次出手的秒數。
var intent: StringName = &""
var strafe_side := 1.0
var since_attack := INF
var special_target: Node3D
var special_progress := 0.0
## 特殊行為被打斷後的冷卻秒數（縫屍者不會立刻再去縫）。
var special_cooldown := 0.0

func to_save() -> Dictionary:
	return {"state": String(state_name), "alert": alert,
		"home": [home.x, home.y, home.z]}
