class_name ScreamWave
extends Node3D
## 產聲的視覺效果：從 Boss 身上擴散的乾涸紅聲波環（低多邊形、自發光），
## 加上地面揚起的骨灰碎片。依戰鬥時間倍率推進（戰術減速時也會變慢）。
## 音效由音訊系統負責（另一個工作串），這裡只有畫面。

const S := preload("res://art/ps1/ps1_style.gd")
const LIFETIME := 1.2
const MAX_RADIUS := 7.0

var age := 0.0
var _rings: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _debris: Array[MeshInstance3D] = []

func _ready() -> void:
	for i in 3:
		var t := TorusMesh.new()
		t.inner_radius = 0.9
		t.outer_radius = 1.0
		t.rings = 12
		t.ring_segments = 3
		var mat := S.material(S.DRIED_RED, "flesh", S.DRIED_RED.lightened(0.2), 1.5).duplicate() as ShaderMaterial
		var mi := MeshInstance3D.new()
		mi.name = "Ring%d" % i
		mi.mesh = t
		mi.material_override = mat
		mi.position = Vector3(0, -0.4 * i, 0)
		add_child(mi)
		_rings.append(mi)
		_mats.append(mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = S.box(Vector3.ONE * rng.randf_range(0.05, 0.12))
		mi.material_override = S.material(S.BONE_WHITE.darkened(0.2), "bone")
		var a := float(i) / 10.0 * TAU
		mi.position = Vector3(cos(a), -global_position.y if is_inside_tree() else -2.0, sin(a)) * Vector3(0.8, 1, 0.8)
		mi.set_meta(&"dir", Vector3(cos(a), rng.randf_range(1.5, 3.0), sin(a)))
		add_child(mi)
		_debris.append(mi)
	_apply()

func _process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

func advance(dt: float) -> void:
	age += dt
	_apply()
	if age >= LIFETIME:
		queue_free()

func _apply() -> void:
	var t := clampf(age / LIFETIME, 0.0, 1.0)
	for i in _rings.size():
		var k := clampf(t * 1.3 - i * 0.15, 0.0, 1.0)
		var r := 0.5 + k * MAX_RADIUS
		_rings[i].scale = Vector3(r, 1.0 + (1.0 - k) * 2.0, r)
		_mats[i].set_shader_parameter("emission_energy", 1.5 * (1.0 - k))
		_rings[i].visible = k < 0.98
	for d in _debris:
		var dir: Vector3 = d.get_meta(&"dir")
		d.position = Vector3(dir.x * (0.8 + t * 3.0), d.position.y + dir.y * 0.02 * (1.0 - t), dir.z * (0.8 + t * 3.0))
		d.rotation = Vector3(t * 9.0, t * 7.0, 0)
