class_name InjuryVisuals
extends Node
## 傷殘部位的模型外觀（玩家與敵人共用，由 CreatureModels.apply 加入）。全部依解剖資料決定：
##   受損（HP < 75%）一道切口；重傷（< 35%）三道；HP 歸零四道
##   出血：從部位滴下血珠，落地變成血點（數量有上限）
##   骨折到失效：斷骨刺出皮膚；失效的手臂由 LimbDangle 讓它垂著不擺動（腿失效 → 既有的跛行動作）
##   灼傷：焦黑的斑塊；壞死：青灰的腐斑
##   包紮過：米黃布條纏在部位上，帶一塊滲出的血
##   縫回的斷肢：關節處一圈黑色縫線疤（永久，存檔保留）
## 生成物都是部位分段的子網格（meta injury_visual），斷肢時跟著殘肢飛走；修復後依新狀態重建。

const META := &"injury_visual"
const S := preload("res://art/ps1/ps1_style.gd")
const BLOOD := Color("7a1810")
const BLOOD_GROUP := &"blood_decal"
## 場上血點上限（超過就移除最舊的）。
const MAX_DECALS := 80
## 每個生物同時在空中的血珠上限。
const MAX_DROPS := 24
## 每單位出血速率每秒滴幾滴（上限 6 滴／秒／部位）。
const DROPS_PER_BLEED := 2.5
const DECAL_LIFETIME := 40.0

var creature: Node3D
var anatomy: AnatomyComponent
var _drop_accum := {}       # part_id -> float
var _drops: Array = []      # [MeshInstance3D, velocity: float, floor_y: float]
var _queued := false
## 累計滴出的血珠數（測試用）。
var drops_emitted := 0

func _ready() -> void:
	creature = get_parent() as Node3D
	anatomy = creature.get_node("AnatomyComponent")
	if anatomy.state == null:
		anatomy.setup()
	var st := anatomy.state
	# 用方法而不是 lambda：節點釋放時 signal 會自動斷開
	st.part_damaged.connect(_on_change.unbind(2))
	st.part_status_changed.connect(_on_change.unbind(3))
	st.part_restored.connect(_on_change.unbind(1))
	st.part_replaced.connect(_on_change.unbind(2))
	var skel := creature.find_child("Skeleton", true, false) as Skeleton3D
	if skel != null and skel.get_node_or_null("LimbDangle") == null:
		var dangle := LimbDangle.new()
		dangle.name = "LimbDangle"
		dangle.anatomy = anatomy
		skel.add_child(dangle)
	_queue()

func _on_change() -> void:
	_queue()

func _queue() -> void:
	if _queued:
		return
	_queued = true
	_deferred_refresh.call_deferred()

func _deferred_refresh() -> void:
	_queued = false
	refresh()

# ---------- 依狀態補上／移除外觀 ----------

## 依目前的解剖狀態同步所有部位的傷口外觀。回傳目前身上的傷口外觀節點數。
func refresh() -> int:
	if not is_instance_valid(creature) or anatomy.state == null:
		return 0
	for pid in anatomy.state.part_ids():
		var p := anatomy.state.get_part(pid)
		if p.def.is_internal or p.severed:
			continue
		var seg := _segment(pid)
		if seg == null:
			continue
		var lay := PlaceholderBodyBuilder._layout_for(p.def, anatomy.profile)
		var r := float(lay.get("r", 0.1))
		var h := float(lay.get("h", r * 2.0)) if lay.get("shape", "capsule") == "capsule" else r * 1.6
		# 細節模型（衣服、大衣）可能比版面半徑寬：傷口要貼在看得到的表面上
		if seg.mesh != null:
			var box := seg.mesh.get_aabb()
			r = maxf(r, maxf(box.size.x, box.size.z) * 0.5 / 1.12)
		var want := wanted(p)
		# 切口：數量隨 HP 增減
		for i in 4:
			var n := "Injury_Wound%d" % i
			_ensure(seg, n, i < int(want["wounds"]), func(): return _wound(pid, i, r, h))
		_ensure(seg, "Injury_Char", want["char"], func(): return _patch(pid, 11, r, h, S.SOOT_BLACK.darkened(0.3), "Injury_Char"))
		_ensure(seg, "Injury_Rot", want["rot"], func(): return _patch(pid, 23, r, h, Color("56603f"), "Injury_Rot"))
		_ensure(seg, "Injury_BoneShard", want["bone_shard"], func(): return _bone_shard(pid, r, h))
		_ensure(seg, "Injury_Bandage", want["bandage"], func(): return _bandage(r, h))
		_ensure(seg, "Injury_SutureScar", want["scar"], func(): return _scar(seg, r))
	return nodes().size()

## 一個部位應該有哪些傷口外觀（測試與 refresh 共用）。
static func wanted(p: BodyPartState) -> Dictionary:
	var ratio := p.hp_ratio()
	var wounds := 0
	if ratio <= 0.0:
		wounds = 4
	elif ratio < AnatomyTypes.SEVERELY_DAMAGED_RATIO:
		wounds = 3
	elif ratio < AnatomyTypes.DAMAGED_RATIO:
		wounds = 1
	return {
		"wounds": wounds,
		"char": p.injury(DamageTypes.Type.BURN) > 0.0,
		"rot": p.injury(DamageTypes.Type.NECROSIS) > 0.0,
		"bone_shard": p.injury(DamageTypes.Type.FRACTURE) >= p.def.max_hp * DamageTypes.FRACTURE_DISABLE_RATIO,
		"bandage": p.bandaged,
		"scar": p.sutured,
	}

func nodes() -> Array:
	var out := []
	for n in creature.find_children("Injury_*", "", true, false):
		if n.has_meta(META):
			out.append(n)
	return out

func _ensure(seg: Node3D, name: String, on: bool, build: Callable) -> void:
	var existing := seg.get_node_or_null(name)
	if on and existing == null:
		var node: Node3D = build.call()
		node.name = name
		node.set_meta(META, true)
		seg.add_child(node)
	elif not on and existing != null:
		seg.remove_child(existing)
		existing.queue_free()

func _segment(part_id: StringName) -> MeshInstance3D:
	var st := anatomy.state.get_part(part_id)
	if st == null or st.severed:
		return null
	var seg := creature.find_child(String(st.def.mesh_segment), true, false) as MeshInstance3D
	return seg if seg != null and creature.is_ancestor_of(seg) else null

# ---------- 造型 ----------

## 部位表面上一個固定的點（同一個部位、同一個序號每次都在同一處）。回傳面向外側的 Transform。
static func surface_point(part_id: StringName, index: int, r: float, h: float, tilt_deg: float = 0.0) -> Transform3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(part_id)) + index * 7919
	var ang := rng.randf_range(-PI * 0.75, PI * 0.75) + PI  # 偏向正面（模型正面朝 -Z）
	var y := rng.randf_range(-h * 0.32, h * 0.32)
	var normal := Vector3(sin(ang), 0.0, cos(ang))
	var pos := normal * r * 1.12 + Vector3(0, y, 0)
	var basis := Basis.looking_at(-normal, Vector3.UP)  # 局部 +Z 朝外
	basis = basis * Basis(Vector3(0, 0, 1), deg_to_rad(tilt_deg + rng.randf_range(-35.0, 35.0)))
	return Transform3D(basis, pos)

func _wound(part_id: StringName, i: int, r: float, h: float) -> Node3D:
	var xf := surface_point(part_id, i, r, h)
	var root := Node3D.new()
	root.transform = xf
	var len := clampf(h * (0.3 + 0.06 * i), 0.07, 0.24)
	var w := clampf(r * 0.35, 0.026, 0.05)
	# 外圈翻開的肉（帶一點自發光，暗色衣服上也看得到）、裡面深色的裂口、下方往下流的血痕
	S.mesh_node(root, S.box(Vector3(w, len, 0.014)), S.material(Color("b8382a"), "flesh", Color("b8382a"), 0.55), Vector3.ZERO, Vector3.ZERO, "Lips")
	S.mesh_node(root, S.box(Vector3(w * 0.45, len * 0.85, 0.018)), S.material(Color("1a0505"), "plain"), Vector3.ZERO, Vector3.ZERO, "Gash")
	if i >= 1:
		S.mesh_node(root, S.box(Vector3(w * 0.5, len * 0.8, 0.008)), S.material(BLOOD, "flesh", BLOOD, 0.3), Vector3(w * 0.2, -len * 0.6, -0.002), Vector3.ZERO, "Streak")
	return root

func _patch(part_id: StringName, salt: int, r: float, h: float, color: Color, _n: String) -> Node3D:
	var root := Node3D.new()
	root.transform = surface_point(part_id, salt, r, h)
	S.mesh_node(root, S.box(Vector3(r * 1.1, minf(h * 0.4, 0.16), 0.01)), S.material(color, "flesh"), Vector3.ZERO, Vector3.ZERO, "Patch")
	S.mesh_node(root, S.box(Vector3(r * 0.6, minf(h * 0.22, 0.09), 0.014)), S.material(color.darkened(0.35), "flesh"), Vector3(r * 0.2, h * 0.05, 0), Vector3.ZERO, "Core")
	return root

func _bone_shard(part_id: StringName, r: float, h: float) -> Node3D:
	var root := Node3D.new()
	root.transform = surface_point(part_id, 5, r * 0.8, h)
	var k := MeshKit.new()
	var b := maxf(r, 0.07)
	k.spike(Vector2(b * 0.35, b * 0.3), b * 1.6, MeshKit.at(Vector3.ZERO, Vector3(80, 0, 15)))
	k.spike(Vector2(b * 0.25, b * 0.25), b * 1.1, MeshKit.at(Vector3(0, -b * 0.4, 0), Vector3(100, 0, -20)))
	var mi := MeshInstance3D.new()
	mi.name = "Shard"
	mi.mesh = k.commit()
	mi.material_override = S.material(S.BONE_WHITE, "bone", S.BONE_WHITE, 0.35)
	root.add_child(mi)
	S.mesh_node(root, S.cylinder(r * 0.45, r * 0.5, 0.012, 6), S.material(BLOOD, "flesh"), Vector3.ZERO, Vector3(90, 0, 0), "Blood")
	return root

func _bandage(r: float, h: float) -> Node3D:
	var root := Node3D.new()
	var y := -h * 0.08
	S.mesh_node(root, S.cylinder(r * 1.22, r * 1.22, minf(h * 0.28, 0.12), 7), S.material(S.CREAM_YELLOW.darkened(0.08), "cloth"), Vector3(0, y, 0), Vector3.ZERO, "Wrap")
	S.mesh_node(root, S.cylinder(r * 1.26, r * 1.26, minf(h * 0.06, 0.025), 7), S.material(S.CREAM_YELLOW.darkened(0.25), "cloth"), Vector3(0, y + minf(h * 0.1, 0.04), 0), Vector3.ZERO, "Edge")
	# 滲出的血：正面一塊
	S.mesh_node(root, S.box(Vector3(r * 0.8, minf(h * 0.16, 0.07), 0.01)), S.material(BLOOD, "flesh"), Vector3(0, y, -r * 1.24), Vector3.ZERO, "Seep")
	return root

## 縫線疤：在分段靠近關節的那端（分段原點是部位中心，關節在 -seg.position）。
func _scar(seg: Node3D, r: float) -> Node3D:
	var root := Node3D.new()
	var joint := -seg.position
	var dir := joint.normalized() if joint.length() > 0.001 else Vector3.UP
	root.position = joint * 0.8
	root.basis = Basis(Quaternion(Vector3.UP, dir))
	S.mesh_node(root, S.cylinder(r * 1.12, r * 1.12, 0.016, 7), S.material(S.DRIED_RED.darkened(0.2), "skin"), Vector3.ZERO, Vector3.ZERO, "ScarRing")
	var k := MeshKit.new()
	for i in 7:
		var a := TAU * i / 7.0
		k.box(Vector3(0.008, 0.05, 0.008), MeshKit.at(Vector3(cos(a) * r * 1.16, 0, sin(a) * r * 1.16), Vector3(0, -rad_to_deg(a), 25)))
	var mi := MeshInstance3D.new()
	mi.name = "Stitches"
	mi.mesh = k.commit()
	mi.material_override = S.material(Color("120a08"), "plain")
	root.add_child(mi)
	return root

# ---------- 滴血 ----------

func _process(delta: float) -> void:
	step(TimeScale.scaled(delta))

## 推進滴血（測試可直接呼叫）。
func step(delta: float) -> void:
	if delta <= 0.0 or not is_instance_valid(creature) or anatomy.state == null:
		return
	if not anatomy.state.is_dead:
		for pid in anatomy.state.part_ids():
			var p := anatomy.state.get_part(pid)
			if p.severed or p.bleed_rate <= 0.0:
				_drop_accum.erase(pid)
				continue
			var acc := float(_drop_accum.get(pid, 0.0)) + minf(6.0, p.bleed_rate * DROPS_PER_BLEED) * delta
			while acc >= 1.0:
				acc -= 1.0
				emit_drop(pid)
			_drop_accum[pid] = acc
	_step_drops(delta)

## 從部位滴出一顆血珠。內部器官從胸口滴。回傳是否真的生成。
func emit_drop(part_id: StringName) -> bool:
	if _drops.size() >= MAX_DROPS:
		return false
	var p := anatomy.state.get_part(part_id)
	var seg: Node3D = _segment(part_id) if p != null and not p.def.is_internal else null
	var origin := seg.global_position if seg != null else creature.global_position + Vector3(0, 1.1, 0)
	var parent := creature.get_parent()
	if parent == null:
		return false
	var mi := MeshInstance3D.new()
	mi.name = "BloodDrop"
	mi.mesh = S.box(Vector3(0.022, 0.035, 0.022))
	mi.material_override = S.material(BLOOD, "plain")
	parent.add_child(mi)
	var jitter := Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(-0.06, 0.06))
	mi.global_position = origin + jitter
	_drops.append([mi, 0.0, creature.global_position.y + 0.005])
	drops_emitted += 1
	return true

func drops_in_air() -> int:
	return _drops.size()

func _step_drops(delta: float) -> void:
	for i in range(_drops.size() - 1, -1, -1):
		var d: Array = _drops[i]
		var mi: MeshInstance3D = d[0]
		if not is_instance_valid(mi):
			_drops.remove_at(i)
			continue
		d[1] = float(d[1]) + 9.8 * delta
		mi.global_position.y -= float(d[1]) * delta
		if mi.global_position.y <= float(d[2]):
			_land(mi, float(d[2]))
			_drops.remove_at(i)

func _land(drop: MeshInstance3D, floor_y: float) -> void:
	var pos := drop.global_position
	var parent := drop.get_parent()
	drop.queue_free()
	var decal := MeshInstance3D.new()
	decal.name = "BloodDecal"
	var rad := randf_range(0.03, 0.07)
	decal.mesh = S.cylinder(rad, rad, 0.004, 6)
	decal.material_override = S.material(BLOOD.darkened(randf_range(0.0, 0.3)), "plain")
	decal.add_to_group(BLOOD_GROUP)
	parent.add_child(decal)
	decal.global_position = Vector3(pos.x, floor_y, pos.z)
	decal.rotation.y = randf() * TAU
	var tw := decal.create_tween()
	tw.tween_interval(DECAL_LIFETIME)
	tw.tween_property(decal, "scale", Vector3(0.01, 1.0, 0.01), 2.0)
	tw.tween_callback(decal.queue_free)
	var all := decal.get_tree().get_nodes_in_group(BLOOD_GROUP)
	var extra := all.size() - MAX_DECALS
	for k in extra:
		(all[k] as Node).remove_from_group(BLOOD_GROUP)
		(all[k] as Node).queue_free()
