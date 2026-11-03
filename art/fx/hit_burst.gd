class_name HitBurst
extends Node3D
## 命中時噴出的低多邊形碎屑：血（乾涸紅）或格擋的火花（舊金色、自發光）。
## 幾個點取樣的小方塊，受重力落下，碰到地面就停住（血）或消失（火花），符合 PS1 的粗糙感。
## 以戰鬥時間推進：頓幀與戰術暫停時血滴停在半空，恢復後才落下。播完自動移除。
## （不用 CPUParticles3D：在低解析度 SubViewport 中不會被繪製。）

const S := preload("res://art/ps1/ps1_style.gd")
const LIFETIME := 0.6
const GRAVITY := 12.0

enum Kind { BLOOD, SPARK }

static var _mesh_cache := {}

## 在 parent 底下的 at 位置噴出。dir：噴出方向（通常是擊退方向）。amount：碎屑數。
static func spawn(parent: Node, at: Vector3, dir: Vector3, amount: int, kind: int = Kind.BLOOD) -> HitBurst:
	if parent == null or not parent.is_inside_tree():
		return null
	var b := HitBurst.new()
	b.name = "HitBurst"
	b.kind = kind
	b.amount = clampi(amount, 2, 40)
	b.burst_dir = dir
	parent.add_child(b, true)
	b.global_position = at
	b._emit()
	return b

var kind := Kind.BLOOD
var amount := 8
var burst_dir := Vector3.UP
var age := 0.0
var chips: Array[MeshInstance3D] = []
var _vel: Array[Vector3] = []
var _floor_y := 0.0

func _emit() -> void:
	_floor_y = global_position.y - 1.25 if kind == Kind.BLOOD else -INF
	var p := get_parent() as Node3D
	if p != null:
		_floor_y = p.global_position.y + 0.02 if kind == Kind.BLOOD else -INF
	var d := burst_dir
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var speed := Vector2(3.0, 6.0) if kind == Kind.SPARK else Vector2(1.6, 4.2)
	for i in amount:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_for(kind)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(0.6, 1.5)
		mi.scale = Vector3.ONE * s
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		add_child(mi)
		chips.append(mi)
		var spread := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)) * 0.75
		var v := (d + Vector3.UP * 0.8 + spread).normalized() * rng.randf_range(speed.x, speed.y)
		_vel.append(v)

static func _mesh_for(k: int) -> Mesh:
	if _mesh_cache.has(k):
		return _mesh_cache[k]
	var m := BoxMesh.new()
	if k == Kind.SPARK:
		m.size = Vector3(0.025, 0.025, 0.08)
		m.material = S.material(S.OLD_GOLD, "plain", S.CREAM_YELLOW, 2.5)
	else:
		m.size = Vector3(0.06, 0.06, 0.06)
		m.material = S.material(S.DRIED_RED.lightened(0.08), "flesh", S.DRIED_RED, 0.35)
	_mesh_cache[k] = m
	return m

func _process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	age += dt
	for i in chips.size():
		var mi := chips[i]
		var v := _vel[i]
		if v == Vector3.ZERO:
			continue
		v.y -= GRAVITY * dt
		v *= maxf(0.0, 1.0 - 1.5 * dt)
		var gp := mi.global_position + v * dt
		if gp.y <= _floor_y:
			gp.y = _floor_y
			v = Vector3.ZERO  # 血滴落地後停住（之後隨整個碎屑一起消失）
			mi.scale.y *= 0.3
		mi.global_position = gp
		_vel[i] = v
	if kind == Kind.SPARK:
		for mi in chips:
			mi.visible = age < LIFETIME * 0.6
	if age > LIFETIME:
		queue_free()
