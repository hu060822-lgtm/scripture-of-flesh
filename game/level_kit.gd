class_name LevelKit
extends RefCounted
## 線性探索式關卡的灰盒工具（序章提案 D；第一章可以共用）。
## 以「區段」組合關卡：任意高度的地板（高台是實心的，不會看到下面）、沿 X／Z 的牆（可開多個口）、
## 坡道（連接不同高度）、矮欄杆（擋住但看得過去）。全部是 WORLD_LAYER 靜態碰撞體，
## 放在 Geometry 底下就會被 LevelNavigation 烘焙進導航網格（坡度 < 40°）。
## 【暫代】外觀是單色方塊，美術替換時保留碰撞即可。

const FLOOR_T := 0.2
const WALL_T := 0.5
const RAIL_H := 1.1
const FLOOR_COLOR := Color("3a3532")
const WALL_COLOR := Color("cfc8b8")
const RAMP_COLOR := Color("4a4440")

static func group(parent: Node, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g

## 地板：上表面在高度 y。y > 0 時是從地面墊高的實心平台（底部 -FLOOR_T）。
static func floor_rect(parent: Node, name: String, x0: float, x1: float, z0: float, z1: float, y: float = 0.0, color: Color = FLOOR_COLOR) -> StaticBody3D:
	var bottom := minf(y - FLOOR_T, -FLOOR_T) if y >= 0.0 else y - FLOOR_T
	var h := y - bottom
	var c := Vector3((x0 + x1) * 0.5, bottom + h * 0.5, (z0 + z1) * 0.5)
	var b := Greybox.box(parent, c, Vector3(absf(x1 - x0), h, absf(z1 - z0)), color)
	b.name = name
	return b

## 沿 X 或 Z 的牆，從 a 到 b（Vector2 = x, z），高度 y0..y1。
## gaps：[[距 a 的開口中心, 開口寬度], ...]。
static func wall(parent: Node, name: String, a: Vector2, b: Vector2, y0: float, y1: float, gaps: Array = [], color: Color = WALL_COLOR, thickness: float = WALL_T) -> Array:
	var along_x := absf(a.y - b.y) < 0.001
	var length := absf(b.x - a.x) if along_x else absf(b.y - a.y)
	var sgn := signf(b.x - a.x) if along_x else signf(b.y - a.y)
	var cuts := []
	for g in gaps:
		cuts.append([float(g[0]) - float(g[1]) * 0.5, float(g[0]) + float(g[1]) * 0.5])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var segs := []
	var cur := 0.0
	for c in cuts:
		if c[0] > cur:
			segs.append([cur, c[0]])
		cur = maxf(cur, c[1])
	if cur < length:
		segs.append([cur, length])
	var out := []
	var i := 0
	for s in segs:
		var s0: float = s[0]
		var s1: float = s[1]
		if s1 - s0 < 0.05:
			continue
		var mid := (s0 + s1) * 0.5 * sgn
		var pos := Vector3(a.x + mid, (y0 + y1) * 0.5, a.y) if along_x else Vector3(a.x, (y0 + y1) * 0.5, a.y + mid)
		var size := Vector3(s1 - s0, y1 - y0, thickness) if along_x else Vector3(thickness, y1 - y0, s1 - s0)
		var w := Greybox.box(parent, pos, size, color)
		w.name = "%s_%d" % [name, i]
		out.append(w)
		i += 1
	return out

## 矮欄杆：站在高度 y 的地板上，擋住人但看得過去。
static func railing(parent: Node, name: String, a: Vector2, b: Vector2, y: float, gaps: Array = [], color: Color = Color("8a8070")) -> Array:
	return wall(parent, name, a, b, y - 0.05, y + RAIL_H, gaps, color, 0.3)

## 坡道：從 bottom 到 top（兩者的 x 或 z 其中一個相同），寬 width。斜板厚 FLOOR_T，上表面連接兩端。
static func ramp(parent: Node, name: String, bottom: Vector3, top: Vector3, width: float, color: Color = RAMP_COLOR) -> StaticBody3D:
	var flat := Vector3(top.x - bottom.x, 0, top.z - bottom.z)
	var run := flat.length()
	var rise := top.y - bottom.y
	var length := sqrt(run * run + rise * rise)
	var slope := atan2(rise, run)
	var yaw := atan2(flat.x, flat.z)  # 朝 +Z 時為 0
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = PlaceholderBodyBuilder.WORLD_LAYER
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -slope)
	var up := basis * Vector3.UP
	body.transform = Transform3D(basis, (bottom + top) * 0.5 - up * FLOOR_T * 0.5)
	var size := Vector3(width, FLOOR_T, length)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body
