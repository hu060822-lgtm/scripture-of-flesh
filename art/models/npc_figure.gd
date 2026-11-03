class_name NpcFigure
extends Node3D
## 【程序生成模型】非戰鬥 NPC 的全身模型（阿格妮絲、伊格納…）。
## 用和敵人相同的人形身體模板與 CreatureModels 造型（所以看起來是同一個世界的人），
## 但不需要戰鬥元件：每個部位是一個掛在關節上的樞軸節點，擺出固定姿勢，再加上低幀率（12fps）的呼吸動作。
##
## 姿勢：
##   pray   — 站著、雙手在胸前交握、頭微低（阿格妮絲）
##   slumped — 靠坐在地上、雙腿伸直、頭垂下、一隻手按著腹部的傷口（垂死的伊格納）

const CM := preload("res://art/models/creature_models.gd")
const S := preload("res://art/ps1/ps1_style.gd")
const PROFILE_PATH := "res://content/anatomy/humanoid.tres"
const ANIM_FPS := 12.0

@export var look: StringName = &"agnes"
@export_enum("pray", "slumped") var pose: String = "pray"

## part id -> 樞軸節點
var pivots := {}
var _rest := {}
var _t := 0.0
var _step := 0.0

static func create(look_id: StringName, pose_id: String) -> NpcFigure:
	var f := NpcFigure.new()
	f.name = "Figure"
	f.look = look_id
	f.pose = pose_id
	f.build()
	return f

func build() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	pivots.clear()
	var profile: AnatomyProfile = load(PROFILE_PATH)
	var lk: Dictionary = CM.LOOKS.get(look, CM.LOOKS[&"humanoid"])
	set_meta(&"model_look", look)
	var frames := PlaceholderBodyBuilder.part_frames(profile)
	var parts := []
	for d in profile.parts:
		if not d.is_internal:
			parts.append(d)
	# 父部位先建立
	parts.sort_custom(func(a, b): return PlaceholderBodyBuilder._depth(profile, a) < PlaceholderBodyBuilder._depth(profile, b))
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	for d in parts:
		var pivot := Node3D.new()
		pivot.name = "pivot_%s" % d.id
		var p: Vector3 = frames[d.id]["pivot"]
		var parent: Node3D = body
		if d.parent_id != &"" and pivots.has(d.parent_id):
			parent = pivots[d.parent_id]
			p -= frames[d.parent_id]["pivot"]
		pivot.position = p
		parent.add_child(pivot)
		pivots[d.id] = pivot
		var lay := PlaceholderBodyBuilder._layout_for(d, profile)
		if not lay.get("mesh", true):
			continue
		var seg := MeshInstance3D.new()
		seg.name = String(d.mesh_segment)
		seg.position = frames[d.id]["center"] - frames[d.id]["pivot"]
		pivot.add_child(seg)
		CM.build_segment(seg, d, profile, look, lk, &"")
	_apply_pose()
	_add_props(lk)
	for id in pivots:
		_rest[id] = (pivots[id] as Node3D).transform

func _rot(part: StringName, deg: Vector3) -> void:
	var p: Node3D = pivots.get(part)
	if p != null:
		p.rotation_degrees = deg

func _apply_pose() -> void:
	var body := get_node("Body") as Node3D
	match pose:
		"pray":
			# 前方是 -Z：繞 X 軸正轉 = 手往前抬
			_rot(&"arm_l", Vector3(50, 0, -27))
			_rot(&"arm_r", Vector3(50, 0, 27))
			_rot(&"neck", Vector3(-14, 0, 0))
			_rot(&"head", Vector3(-8, 0, 4))
		"slumped":
			# 坐在地上：髖部（腿的樞軸，高 0.9）落到地面，腿往前伸，上半身往後靠
			body.position = Vector3(0, -0.8, 0)
			_rot(&"chest", Vector3(18, 0, 6))
			_rot(&"leg_l", Vector3(72, 0, -10))
			_rot(&"leg_r", Vector3(70, 0, 14))
			# 一隻手按住腹部的傷口，另一隻手垂在地上
			_rot(&"arm_r", Vector3(50, 0, 42))
			_rot(&"arm_l", Vector3(-8, 0, 22))
			_rot(&"neck", Vector3(-30, 0, -10))
			_rot(&"head", Vector3(-18, 0, -14))

## 角色專屬的小道具（掛在部位上，跟著呼吸動作）。
func _add_props(lk: Dictionary) -> void:
	match look:
		&"agnes":
			# 腰間垂下的陳舊金念珠與一卷乾涸紅的縫線、一把剪刀
			var gold := S.material(S.OLD_GOLD, "metal", S.OLD_GOLD, 0.4)
			var ab: Node3D = pivots.get(&"abdomen")
			if ab != null:
				for i in 7:
					PropModels._node(ab, S.sphere(0.02, 4, 2), gold, Vector3(0.12 + sin(i * 0.5) * 0.03, -0.1 - i * 0.06, -0.18), Vector3.ZERO, "Bead%d" % i)
				PropModels._node(ab, S.box(Vector3(0.025, 0.08, 0.01)), gold, Vector3(0.14, -0.55, -0.18), Vector3.ZERO, "RosaryCross")
				PropModels._node(ab, S.cylinder(0.035, 0.035, 0.06, 6), S.material(S.DRIED_RED, "cloth"), Vector3(-0.2, -0.12, -0.12), Vector3(0, 0, 90), "ThreadSpool")
				PropModels._node(ab, S.box(Vector3(0.02, 0.12, 0.01)), S.material(Color("b8b4aa"), "metal"), Vector3(-0.22, -0.22, -0.1), Vector3(0, 0, 12), "Scissors")
		&"ignatius":
			# 身下的一灘血、掉在手邊的縫針與線、碎掉的香爐
			var blood := S.material(S.DRIED_RED, "flesh")
			PropModels._node(self, S.cylinder(0.55, 0.6, 0.006, 8), blood, Vector3(0.0, 0.004, -0.15), Vector3.ZERO, "BloodPool", Vector3(1.2, 1, 0.8))
			PropModels._node(self, S.cylinder(0.04, 0.04, 0.06, 6), S.material(S.DRIED_RED.darkened(0.2), "cloth"), Vector3(0.5, 0.03, -0.35), Vector3(0, 0, 90), "ThreadSpool")
			PropModels._node(self, S.box(Vector3(0.12, 0.008, 0.008)), S.material(Color("c8c4ba"), "metal"), Vector3(0.42, 0.01, -0.45), Vector3(0, 30, 0), "Needle")
			var censer := S.material(S.OLD_GOLD.darkened(0.25), "metal")
			PropModels._node(self, S.sphere(0.09, 6, 3), censer, Vector3(-0.55, 0.07, -0.2), Vector3(0, 0, 70), "Censer", Vector3(1, 0.8, 1))
			for i in 4:
				PropModels._node(self, S.box(Vector3(0.012, 0.012, 0.06)), censer, Vector3(-0.45 + i * 0.05, 0.01, -0.3 - i * 0.03), Vector3(0, 40.0 * i, 0), "Chain%d" % i)
			# 腹部的傷口（布被撕開、露出縫到一半的線）
			var ab: Node3D = pivots.get(&"abdomen")
			if ab != null:
				PropModels._node(ab, S.box(Vector3(0.2, 0.14, 0.02)), S.material(S.DRIED_RED.lightened(0.1), "flesh", S.DRIED_RED, 0.3), Vector3(0.04, 0.02, -0.19), Vector3.ZERO, "Wound")
				for i in 3:
					PropModels._node(ab, S.box(Vector3(0.008, 0.08, 0.008)), S.material(S.SOOT_BLACK, "plain"), Vector3(-0.02 + i * 0.05, 0.02, -0.205), Vector3(0, 0, 30), "WoundStitch%d" % i)

func _process(delta: float) -> void:
	_t += delta
	_step += delta
	if _step < 1.0 / ANIM_FPS:
		return
	_step = 0.0
	animate(_t)

## 呼吸動作（以時間 t 計算，測試可以直接呼叫）。
func animate(t: float) -> void:
	if _rest.is_empty():
		return
	match pose:
		"pray":
			var b := sin(t * TAU / 4.0)
			_offset(&"chest", Vector3(b * 1.2, 0, sin(t * TAU / 9.0) * 1.5))
			_offset(&"head", Vector3(b * 2.0, 0, 0))
		"slumped":
			# 淺而急的喘息，偶爾抽搐一下
			var b := sin(t * TAU / 1.6)
			var twitch := 6.0 if fmod(t, 5.3) < 0.15 else 0.0
			_offset(&"chest", Vector3(b * 2.0, 0, 0))
			_offset(&"head", Vector3(b * 1.5 + twitch, twitch * 0.5, 0))
			_offset(&"arm_l", Vector3(0, 0, twitch * 0.6))

func _offset(part: StringName, deg: Vector3) -> void:
	var p: Node3D = pivots.get(part)
	if p == null or not _rest.has(part):
		return
	var rest: Transform3D = _rest[part]
	p.transform = Transform3D(rest.basis * Basis.from_euler(deg * (PI / 180.0)), rest.origin)
