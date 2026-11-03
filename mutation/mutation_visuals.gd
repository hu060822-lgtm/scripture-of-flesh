class_name MutationVisuals
extends Node
## 異化的外觀變化（補上「異化沒有外觀」的缺口）。每個異化階段在玩家身上長出東西：
##   25 不安的感官：左前臂與脖子側面長出眼睛
##   50 骨刺：兩隻前臂外側與背後脊椎冒出骨刺
##   75 自主的肉：背後長出一隻小手、胸口撕開衣服裂出一張直立的嘴
## 長出的東西是部位分段的子網格（meta mutation_growth），斷肢時跟著殘肢飛出；
## 縫回或修復後（分段被重建）會重新長出來。
## 只依 MutationComponent.reached 決定，讀檔後也會正確顯示。

const META := &"mutation_growth"
const S := preload("res://art/ps1/ps1_style.gd")

var creature: Node3D
var anatomy: AnatomyComponent
var mutation: MutationComponent

func _ready() -> void:
	creature = get_parent() as Node3D
	anatomy = creature.get_node("AnatomyComponent")
	mutation = creature.get_node("MutationComponent")
	mutation.stage_reached.connect(func(_st): refresh())
	# 讀檔時 reached 直接被還原（不發 stage_reached），用數值變化補上
	mutation.mutation_changed.connect(func(_v): _queue())
	if anatomy.state == null:
		anatomy.setup()
	# 修復後 DismembermentController 會重建分段，晚一格再長回來
	anatomy.state.part_restored.connect(func(_id): refresh.call_deferred())
	anatomy.state.part_replaced.connect(func(_id, _o): refresh.call_deferred())
	refresh.call_deferred()

var _queued := false

func _queue() -> void:
	if _queued:
		return
	_queued = true
	(func():
		_queued = false
		refresh()).call_deferred()

## 各階段要長的東西：[部位, 名稱, 建構函式]
func _specs() -> Dictionary:
	return {
		&"stage_1_uncanny_sense": [[&"arm_l", "ForearmEye", _forearm_eye], [&"neck", "NeckEye", _neck_eye]],
		&"stage_2_bone_spurs": [[&"arm_l", "ArmSpurs", _arm_spurs.bind(1.0)], [&"arm_r", "ArmSpurs", _arm_spurs.bind(-1.0)], [&"chest", "BackSpurs", _back_spurs]],
		&"stage_3_autonomous_flesh": [[&"chest", "BackHand", _back_hand], [&"chest", "ChestMouth", _chest_mouth]],
	}

## 依目前已達到的階段補上缺少的生長物。回傳目前身上的生長物數量。
func refresh() -> int:
	if not is_instance_valid(creature):
		return 0
	var specs := _specs()
	for stage_id in specs:
		if not stage_id in mutation.reached:
			continue
		for spec in specs[stage_id]:
			var seg := _segment(spec[0])
			if seg == null:
				continue  # 部位已斷離
			var name := "Growth_%s" % spec[1]
			if seg.get_node_or_null(name) != null:
				continue
			var lay := PlaceholderBodyBuilder._layout_for(anatomy.state.get_part(spec[0]).def, anatomy.profile)
			var node: Node3D = (spec[2] as Callable).call(float(lay.get("h", 0.3)), float(lay.get("r", 0.1)))
			node.name = name
			node.set_meta(META, true)
			seg.add_child(node)
	return growths().size()

func growths() -> Array:
	var out := []
	for n in creature.find_children("Growth_*", "", true, false):
		if n.has_meta(META):
			out.append(n)
	return out

func _segment(part_id: StringName) -> MeshInstance3D:
	var st := anatomy.state.get_part(part_id)
	if st == null or st.severed:
		return null
	var seg := creature.find_child(String(st.def.mesh_segment), true, false) as MeshInstance3D
	return seg if seg != null and creature.is_ancestor_of(seg) else null

# ---------- 造型 ----------

func _mesh_node(mesh: Mesh, mat: Material, xf: Transform3D = Transform3D.IDENTITY, name: String = "Part") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	return mi

func _eye_node(r: float, xf: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.transform = xf
	var e: Array = CreatureModels._eye(r, false)
	root.add_child(_mesh_node(e[0], e[1], Transform3D.IDENTITY, "Eye"))
	for d in e[2]:
		root.add_child(_mesh_node(d[0], d[1], d[2], d[3]))
	# 眼瞼：一圈濕紅的肉
	root.add_child(_mesh_node(S.cylinder(r * 1.35, r * 1.35, r * 0.6, 7), S.material(S.DRIED_RED.lightened(0.15), "skin"),
		MeshKit.at(Vector3(0, 0, r * 0.2), Vector3(90, 0, 0)), "Lid"))
	return root

## 左前臂外側（+X）的眼睛，往前看。
func _forearm_eye(h: float, r: float) -> Node3D:
	return _eye_node(r * 0.45, MeshKit.at(Vector3(r * 0.95, -h * 0.18, r * 0.2), Vector3(0, 70, 0)))

func _neck_eye(h: float, r: float) -> Node3D:
	return _eye_node(r * 0.32, MeshKit.at(Vector3(-r * 0.9, 0.0, -r * 0.35), Vector3(0, 60, 0)))

func _bone() -> Material:
	return S.material(S.BONE_WHITE.darkened(0.08), "plain")

## 前臂外側一排骨刺。side：+1 = 左臂（+X 側）。
func _arm_spurs(h: float, r: float, side: float) -> Node3D:
	var k := MeshKit.new()
	for i in 3:
		var y := -h * (0.05 + 0.13 * i)
		k.spike(Vector2(r * 0.5, r * 0.5), r * (1.5 - 0.2 * i), MeshKit.at(Vector3(side * r * 0.8, y, -r * 0.2), Vector3(0, 0, -side * 75)))
	return _mesh_node(k.commit(), _bone(), Transform3D.IDENTITY, "Spurs")

## 背後（+Z；模型正面朝 -Z）沿脊椎的骨刺。
func _back_spurs(h: float, r: float) -> Node3D:
	var k := MeshKit.new()
	for i in 4:
		var y := h * (0.3 - 0.18 * i)
		k.spike(Vector2(0.04, 0.05), 0.09 + 0.02 * (i % 2), MeshKit.at(Vector3(0, y, r * 0.85), Vector3(80, 0, 0)))
	return _mesh_node(k.commit(), _bone(), Transform3D.IDENTITY, "Spurs")

## 背後長出的小手：細瘦的上臂＋前臂＋張開的手指，往上往後伸。
func _back_hand(h: float, r: float) -> Node3D:
	var k := MeshKit.new()
	var base := MeshKit.at(Vector3(r * 0.35, h * 0.15, r * 0.8), Vector3(35, 0, -20))
	k.lathe([Vector2(0.03, 0.0), Vector2(0.025, 0.2), Vector2(0.02, 0.36)], 5, base)
	for f in 4:
		var ang := -30.0 + 20.0 * f
		k.spike(Vector2(0.012, 0.012), 0.08, base * MeshKit.at(Vector3(0, 0.36, 0), Vector3(0, 0, ang)))
	return _mesh_node(k.commit(), S.material(S.GREY_PINK.darkened(0.1), "skin"), Transform3D.IDENTITY, "Hand")

## 胸口正面（-Z）撕開衣服、直立裂開的嘴，兩排牙。
func _chest_mouth(h: float, r: float) -> Node3D:
	var root := Node3D.new()
	var z := -r * 1.32  # 在衣服外面
	# 杏仁形：用壓扁的球做嘴唇與裂口
	root.add_child(_mesh_node(S.sphere(1.0, 8, 4), S.material(S.DRIED_RED, "skin"),
		MeshKit.at(Vector3(0, -h * 0.12, z + 0.02), Vector3.ZERO, Vector3(0.075, h * 0.33, 0.025)), "Lips"))
	root.add_child(_mesh_node(S.sphere(1.0, 8, 4), S.material(Color("1a0505"), "plain"),
		MeshKit.at(Vector3(0, -h * 0.12, z), Vector3.ZERO, Vector3(0.042, h * 0.28, 0.025)), "Slit"))
	var k := MeshKit.new()
	for i in 5:
		var y := -h * 0.12 + h * (-0.2 + 0.1 * i)
		k.spike(Vector2(0.016, 0.016), 0.032, MeshKit.at(Vector3(-0.034, y, z - 0.005), Vector3(0, 0, -90)))
		k.spike(Vector2(0.016, 0.016), 0.032, MeshKit.at(Vector3(0.034, y + 0.025, z - 0.005), Vector3(0, 0, 90)))
	root.add_child(_mesh_node(k.commit(), _bone(), Transform3D.IDENTITY, "Teeth"))
	return root
