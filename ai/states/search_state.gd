extends AiState
## 搜索：走到調查點（聽到的聲響、最後看到目標的地方），四處張望，再到附近幾個點查看，
## 都沒有發現就回去巡邏。期間察覺目標則進入偵測／追擊。

## 抵達調查點的距離。
const ARRIVE := 0.6
## 每個點張望的秒數與轉頭角度。
const LOOK_SECONDS := 1.6
const LOOK_SWEEP := 1.4
## 抵達第一個點後再查看幾個附近的點。
const PROBES := 2
const PROBE_RADIUS := 3.0
## 整體上限，避免卡在無法抵達的點。
const MAX_SECONDS := 14.0
const SPEED := 0.65

var _points: Array[Vector3] = []
var _probed := 0
var _look_timer := 0.0
var _base_yaw := 0.0

func enter(ai: EnemyAI) -> void:
	_points.clear()
	var p := ai.runtime.investigate_point
	if p == Vector3.INF:
		p = ai.runtime.last_known_position
	_points.append(AiNavigator.closest_point(ai.body(), p))
	_look_timer = 0.0
	_probed = 0
	ai.navigator.reset()
	ai.search_started.emit(p)
	ai.bark.emit(&"search")

## 搜索中又聽到聲音：改去新的位置（重新計時）。
func retarget(ai: EnemyAI, point: Vector3) -> void:
	ai.runtime.investigate_point = point
	ai.runtime.time_in_state = 0.0
	enter(ai)

func exit(ai: EnemyAI) -> void:
	ai.runtime.investigate_point = Vector3.INF

func update(ai: EnemyAI, delta: float) -> StringName:
	if ai.runtime.target != null and ai.runtime.time_since_seen <= 0.0:
		return &"chase" if ai.runtime.alert >= 1.0 else &"detect"
	if _points.is_empty() or ai.runtime.time_in_state > MAX_SECONDS:
		ai.runtime.target = null
		return &"patrol"
	var goal: Vector3 = _points[0]
	var to := goal - ai.body().global_position
	to.y = 0
	if to.length() > ARRIVE and _look_timer <= 0.0:
		ai.move_towards(goal, SPEED)
		return &""
	# 抵達：停下來左右張望
	ai.stop()
	if _look_timer <= 0.0:
		_base_yaw = ai.body().rotation.y
	_look_timer += delta
	ai.body().rotation.y = _base_yaw + sin(_look_timer / LOOK_SECONDS * TAU) * LOOK_SWEEP * 0.5
	if _look_timer >= LOOK_SECONDS:
		_look_timer = 0.0
		var reached: Vector3 = _points.pop_front()
		if _probed < PROBES:
			_probed += 1
			_points.append(_probe(ai, reached))
	return &""

func _probe(ai: EnemyAI, around: Vector3) -> Vector3:
	var a := ai.rng.randf() * TAU
	var r := PROBE_RADIUS * (0.5 + 0.5 * ai.rng.randf())
	return AiNavigator.closest_point(ai.body(), around + Vector3(cos(a) * r, 0, sin(a) * r))
