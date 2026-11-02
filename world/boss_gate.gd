class_name BossGate
extends Interactable
## 需要條件才能開啟的門（條件格式同對話條件，例如 {"has_item": "umbilical_key"}）。
## 未達成：播放 locked_dialogue_id；達成：播放 open_dialogue_id 並移除阻擋。
## 外觀：程序生成的哥德式雙開門（石框尖拱、木門板、陳舊金鉚釘與鐵箍）。開啟時兩扇門板
## 以真實時間在 OPEN_TIME 秒內向內推開（對話進行中戰鬥暫停，門照樣打開）。阻擋碰撞在開啟當下就移除。

signal opened

const S := preload("res://art/ps1/ps1_style.gd")
const OPEN_TIME := 1.6
const OPEN_DEGREES := 100.0

@export var condition: Dictionary = {}
@export var locked_dialogue_id: String = ""
@export var open_dialogue_id: String = ""
@export var gate_size: Vector3 = Vector3(4, 4, 0.5)

func _init() -> void:
	once = true
	prompt_text = "E：推門"

func condition_met(player: Node3D) -> bool:
	var r := DialogueRunner.new()
	r.player = player
	return r.check(condition)

func is_open() -> bool:
	return is_used()

func _do(player: Node3D) -> bool:
	if not condition_met(player):
		if locked_dialogue_id != "":
			dialogue_requested.emit(locked_dialogue_id, player)
		return false
	if open_dialogue_id != "":
		dialogue_requested.emit(open_dialogue_id, player)
	return true

var _open_t := -1.0

func _on_used() -> void:
	var blocker := get_node_or_null("Blocker")
	if blocker != null:
		blocker.queue_free()
		remove_child(blocker)
	if not is_node_ready():
		# 讀檔時門已經開過：直接全開，不播動畫
		_open_t = OPEN_TIME
		_set_leaves(1.0)
	elif _open_t < 0.0:
		_open_t = 0.0
	opened.emit()

func _process(delta: float) -> void:
	if _open_t < 0.0 or _open_t >= OPEN_TIME:
		return
	advance_open(delta)

## 推進開門動畫（測試直接呼叫）。
func advance_open(delta: float) -> void:
	_open_t = minf(OPEN_TIME, maxf(_open_t, 0.0) + delta)
	var k := _open_t / OPEN_TIME
	# 先卡住一下（沉重的門），再推開並在最後減速
	var e: float = 0.0 if k < 0.12 else Tween.interpolate_value(0.0, 1.0, (k - 0.12) / 0.88, 1.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_set_leaves(e)

func _set_leaves(k: float) -> void:
	var l := get_node_or_null("DoorVisual/HingeL") as Node3D
	var r := get_node_or_null("DoorVisual/HingeR") as Node3D
	if l != null:
		l.rotation.y = deg_to_rad(OPEN_DEGREES) * k
	if r != null:
		r.rotation.y = -deg_to_rad(OPEN_DEGREES) * k

func open_amount() -> float:
	var l := get_node_or_null("DoorVisual/HingeL") as Node3D
	return 0.0 if l == null else l.rotation.y / deg_to_rad(OPEN_DEGREES)

func _build_placeholder() -> void:
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = PlaceholderBodyBuilder.WORLD_LAYER | PlaceholderBodyBuilder.CREATURE_LAYER
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = gate_size
	cs.shape = shape
	cs.position = Vector3(0, gate_size.y * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	add_child(_build_door())

## 哥德式雙開門。門板掛在左右的鉸鏈節點上（HingeL／HingeR），門朝 -Z 推開。
func _build_door() -> Node3D:
	var root := Node3D.new()
	root.name = "DoorVisual"
	var w := gate_size.x
	var h := gate_size.y
	var stone := S.material(S.BONE_WHITE.darkened(0.15), "stone")
	var wood := S.material(Color("4a3020"), "wood")
	var gold := S.material(S.OLD_GOLD, "metal")
	var iron := S.material(Color("3a3836"), "metal")
	# 石框：兩根柱子＋尖拱（兩塊斜放的石塊）
	for side in [-1.0, 1.0]:
		S.mesh_node(root, S.box(Vector3(0.45, h + 0.4, gate_size.z + 0.3)), stone, Vector3(side * (w * 0.5 + 0.22), (h + 0.4) * 0.5, 0), Vector3.ZERO, "Pillar")
		S.mesh_node(root, S.box(Vector3(w * 0.62, 0.45, gate_size.z + 0.3)), stone, Vector3(side * w * 0.24, h + 0.55, 0), Vector3(0, 0, side * -24.0), "Arch")
	S.mesh_node(root, S.box(Vector3(0.3, 0.5, gate_size.z + 0.35)), gold, Vector3(0, h + 1.0, 0), Vector3.ZERO, "Keystone")
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "HingeL" if side < 0 else "HingeR"
		hinge.position = Vector3(side * w * 0.5, 0, 0)
		root.add_child(hinge)
		var lw := w * 0.5 - 0.02
		var cx: float = -side * lw * 0.5  # 門板中心在鉸鏈內側
		S.mesh_node(hinge, S.box(Vector3(lw, h, gate_size.z * 0.6)), wood, Vector3(cx, h * 0.5, 0), Vector3.ZERO, "Leaf")
		for i in 3:
			S.mesh_node(hinge, S.box(Vector3(lw, 0.12, gate_size.z * 0.7)), iron, Vector3(cx, 0.5 + i * (h - 1.0) * 0.5, 0), Vector3.ZERO, "Band%d" % i)
			for j in 4:
				S.mesh_node(hinge, S.sphere(0.05, 4, 2), gold, Vector3(cx - lw * 0.4 + j * lw * 0.27, 0.5 + i * (h - 1.0) * 0.5, gate_size.z * 0.36), Vector3.ZERO, "Stud")
		S.mesh_node(hinge, S.cylinder(0.12, 0.12, 0.04, 8), gold, Vector3(cx + side * lw * 0.38, h * 0.48, gate_size.z * 0.36), Vector3(90, 0, 0), "Ring")
	return root
