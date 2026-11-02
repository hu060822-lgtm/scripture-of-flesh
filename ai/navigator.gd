class_name AiNavigator
extends RefCounted
## 敵人尋路：向 NavigationServer3D 查詢路徑並沿轉角前進。
## 場景沒有導航網格（沙盒、單元測試）時自動退回直線移動，行為與 M4 相同。
## 不使用 NavigationAgent3D 的非同步迴避，改由 EnemyAI 自己做分離轉向，以便 headless 測試可重現。

const REPATH_INTERVAL := 0.5
const REPATH_DISTANCE := 0.6
const CORNER_REACHED := 0.3

var path := PackedVector3Array()
var index := 0
var goal := Vector3.INF
var _timer := 0.0

func tick(delta: float) -> void:
	_timer -= delta

static func map_of(body: Node3D) -> RID:
	if body == null or not body.is_inside_tree():
		return RID()
	return body.get_world_3d().navigation_map

## 這個世界有可用的導航網格嗎？
static func has_navigation(body: Node3D) -> bool:
	var map := map_of(body)
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 \
		and not NavigationServer3D.map_get_regions(map).is_empty()

## 回傳朝 target 前進時下一個要走向的點。沒有導航網格時直接回傳 target。
func next_point(body: Node3D, target: Vector3) -> Vector3:
	if not has_navigation(body):
		path = PackedVector3Array()
		return target
	var from := body.global_position
	if _timer <= 0.0 or path.is_empty() or _flat(goal - target).length() > REPATH_DISTANCE:
		_timer = REPATH_INTERVAL
		goal = target
		path = NavigationServer3D.map_get_path(map_of(body), from, target, true)
		index = 0
	while index < path.size() and _flat(path[index] - from).length() < CORNER_REACHED:
		index += 1
	if index >= path.size():
		return target
	var p := path[index]
	return Vector3(p.x, from.y, p.z)

## 導航網格上離 point 最近的點（沒有導航網格時原樣回傳）。
static func closest_point(body: Node3D, point: Vector3) -> Vector3:
	if not has_navigation(body):
		return point
	return NavigationServer3D.map_get_closest_point(map_of(body), point)

## 沿導航網格從 from 到 to 的路徑長度；沒有導航網格時回傳直線距離。
static func path_length(body: Node3D, from: Vector3, to: Vector3) -> float:
	if not has_navigation(body):
		return _flat(to - from).length()
	var p := NavigationServer3D.map_get_path(map_of(body), from, to, true)
	if p.is_empty():
		return INF
	var total := 0.0
	for i in range(1, p.size()):
		total += _flat(p[i] - p[i - 1]).length()
	return total

func reset() -> void:
	path = PackedVector3Array()
	goal = Vector3.INF
	_timer = 0.0

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
