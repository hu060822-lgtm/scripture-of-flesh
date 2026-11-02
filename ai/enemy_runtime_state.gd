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
var special_target: Node3D
var special_progress := 0.0

func to_save() -> Dictionary:
	return {"state": String(state_name), "alert": alert,
		"home": [home.x, home.y, home.z]}
