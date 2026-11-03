class_name HallucinationDirector
extends Node3D
## 異化幻覺（序章恐怖橋段 C3）。異化越高，越常看到不存在的東西：
##   異化 ≥ 50：前方遠處出現高大的人影，朝你慢慢走來，靠近到 3m 或 8 秒後消失，伴隨低語。
##   異化 ≥ 75：另外有機會看到地上「發光的器官」，走近時才發現什麼都沒有。
## 只在探索時出現（附近沒有敵人察覺、不在對話或戰術模式），不造成傷害，也不會騙戰術介面的重要資訊。

const START := 50.0
const FAKE_ITEM_START := 75.0
## 異化 50 → 100 時，兩次幻覺之間的秒數。
const INTERVAL := Vector2(80.0, 30.0)
const WALK_SPEED := 1.2
const VANISH_DISTANCE := 3.0
const LIFETIME := 8.0
const FAKE_ITEM_CHANCE := 0.4

var player: Node3D
var mutation: MutationComponent
var rng := RandomNumberGenerator.new()
## 生成位置是否貼齊導航網格（測試裡沒有導航網格時關掉）。
var use_navmesh := true
var spawned := 0
var fake_items := 0
var current: Node3D
var _left := -1.0
var _age := 0.0
var _is_item := false

func setup(p: Node3D) -> void:
	player = p
	mutation = p.get_node_or_null("MutationComponent")

func interval_for(m: float) -> float:
	return lerpf(INTERVAL.x, INTERVAL.y, clampf((m - START) / (100.0 - START), 0.0, 1.0))

## 現在是否適合出現幻覺（探索中）。
func calm() -> bool:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and not am.music_state in [&"explore", &"silence"]:
		return false
	return TimeScale.mode == TimeScale.Mode.NORMAL

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or mutation == null:
		return
	if current != null:
		_update_current(delta)
		return
	if mutation.value < START:
		_left = -1.0
		return
	if _left < 0.0:
		_left = interval_for(mutation.value) * rng.randf_range(0.7, 1.2)
	_left -= delta
	if _left <= 0.0:
		_left = -1.0
		if calm():
			spawn()

## 在玩家前方生成一個幻覺。回傳是否成功（前方沒有可站的地面就放棄）。
func spawn() -> bool:
	_is_item = mutation.value >= FAKE_ITEM_START and rng.randf() < FAKE_ITEM_CHANCE
	var dist := rng.randf_range(4.0, 6.0) if _is_item else rng.randf_range(7.0, 10.0)
	var fwd := player.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized().rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
	var want := player.global_position + fwd * dist
	var pos := want
	var map := get_world_3d().navigation_map
	if use_navmesh and NavigationServer3D.map_get_iteration_id(map) > 0:
		pos = NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(pos.x - want.x, pos.z - want.z).length() > 2.0:
			return false
	if _is_item:
		current = _fake_item()
		fake_items += 1
	else:
		var f := ScareFigure.new()
		f.kind = "tall"
		current = f
		_whisper(pos)
	current.name = "Hallucination"
	add_child(current)
	current.global_position = pos
	_age = 0.0
	spawned += 1
	return true

func _update_current(delta: float) -> void:
	_age += delta
	var to := player.global_position - current.global_position
	to.y = 0
	if _is_item:
		if to.length() < 1.2:
			var data: PlayerData = player.get_node_or_null("PlayerData")
			if data != null:
				data.message.emit("……那裡什麼都沒有。")
			_clear()
		elif _age > 25.0:
			_clear()
		return
	if to.length() < VANISH_DISTANCE or _age > LIFETIME:
		_clear()
		return
	current.rotation.y = atan2(to.x, to.z)
	current.global_position += to.normalized() * WALK_SPEED * delta

func _clear() -> void:
	if current != null:
		current.queue_free()
	current = null

func _fake_item() -> Node3D:
	var n := Node3D.new()
	var m := SphereMesh.new()
	m.radius = 0.15
	m.height = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = Vector3(0, 0.4, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("a04a3e")
	mat.emission_enabled = true
	mat.emission = Color("c04030")
	mat.emission_energy_multiplier = 0.8
	mi.material_override = mat
	n.add_child(mi)
	return n

func _whisper(at: Vector3) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null or am.psyche == null or am.psyche.whispers.is_empty():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = am.psyche.whispers[rng.randi_range(0, am.psyche.whispers.size() - 1)]
	p.bus = &"Voice"
	p.unit_size = 4.0
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)
