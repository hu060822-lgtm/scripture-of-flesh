class_name MeshKit
extends RefCounted
## 【程序生成模型】低多邊形網格組合工具（SurfaceTool）。
## 把多個車床體（lathe：沿 Y 軸的輪廓旋轉體）、盒子、楔形合併成一個 ArrayMesh，
## 產生圓柱 UV（貼圖可以包住肢體）與 Gouraud 法線（PS1 的平滑著色）。
## 用法：var k := MeshKit.new(); k.lathe(...); k.box(...); var mesh := k.commit()

var _st := SurfaceTool.new()
var _count := 0

func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)

## rings：Array of Vector2(半徑, 高度)，由上往下或由下往上皆可。
## sides：邊數（PS1 風格 5–8）。scale：x／z 方向的扁平比例（軀幹前後較薄）。
## cap：頭尾半徑大於 0 時是否封口。
func lathe(rings: Array, sides: int = 6, xf: Transform3D = Transform3D.IDENTITY, scale: Vector2 = Vector2.ONE, cap: bool = true) -> MeshKit:
	var n := rings.size()
	var ys := []
	for r in rings:
		ys.append((r as Vector2).y)
	var y_min: float = ys.min()
	var y_span: float = maxf(0.001, float(ys.max()) - y_min)
	for i in n - 1:
		var a: Vector2 = rings[i]
		var b: Vector2 = rings[i + 1]
		for j in sides:
			var t0 := float(j) / sides
			var t1 := float(j + 1) / sides
			var p00 := _ring_point(a, t0, scale)
			var p01 := _ring_point(a, t1, scale)
			var p10 := _ring_point(b, t0, scale)
			var p11 := _ring_point(b, t1, scale)
			var v0 := 1.0 - (a.y - y_min) / y_span
			var v1 := 1.0 - (b.y - y_min) / y_span
			_tri(xf, [p00, p10, p11], [Vector2(t0, v0), Vector2(t0, v1), Vector2(t1, v1)], a.y > b.y)
			_tri(xf, [p00, p11, p01], [Vector2(t0, v0), Vector2(t1, v1), Vector2(t1, v0)], a.y > b.y)
	if cap:
		_cap(rings[0], sides, xf, scale, rings[0].y > rings[n - 1].y)
		_cap(rings[n - 1], sides, xf, scale, rings[n - 1].y > rings[0].y)
	return self

func _ring_point(r: Vector2, t: float, scale: Vector2) -> Vector3:
	var ang := t * TAU
	return Vector3(cos(ang) * r.x * scale.x, r.y, sin(ang) * r.x * scale.y)

func _cap(r: Vector2, sides: int, xf: Transform3D, scale: Vector2, top: bool) -> void:
	if r.x <= 0.0005:
		return
	var c := Vector3(0, r.y, 0)
	for j in sides:
		var p0 := _ring_point(r, float(j) / sides, scale)
		var p1 := _ring_point(r, float(j + 1) / sides, scale)
		_tri(xf, [c, p1, p0] if top else [c, p0, p1], [Vector2(0.5, 0.5), Vector2(0.5, 0), Vector2(0.5, 1)], false)

## 加入三角形（順時針為正面）。flip：反轉繞序，讓法線朝外。
func _tri(xf: Transform3D, ps: Array, uvs: Array, flip: bool) -> void:
	var order := [0, 1, 2] if flip else [0, 2, 1]
	for k in order:
		_st.set_uv(uvs[k])
		_st.add_vertex(xf * (ps[k] as Vector3))
	_count += 1

## 盒子（中心在 xf 原點）。
func box(size: Vector3, xf: Transform3D = Transform3D.IDENTITY) -> MeshKit:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f in faces:
		_quad(xf, c[f[0]], c[f[1]], c[f[2]], c[f[3]])
	return self

## 楔形／四角錐：底面 size.x × size.z、高 size.y、頂點往 tip_offset 偏移（鼻子、骨刺、牙齒）。
func spike(base: Vector2, height: float, xf: Transform3D = Transform3D.IDENTITY, tip_offset: Vector2 = Vector2.ZERO) -> MeshKit:
	var hx := base.x * 0.5
	var hz := base.y * 0.5
	var b := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var tip := Vector3(tip_offset.x, height, tip_offset.y)
	for i in 4:
		_tri(xf, [b[i], tip, b[(i + 1) % 4]], [Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1)], false)
	_quad(xf, b[0], b[1], b[2], b[3])
	return self

func _quad(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(xf, [a, b, c], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)], false)
	_tri(xf, [a, c, d], [Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)], false)

func triangle_count() -> int:
	return _count

func commit() -> ArrayMesh:
	_st.generate_normals()
	return _st.commit()

## 便利函式：位置＋歐拉角（度）的變換。
static func at(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))).scaled(scale)
	return Transform3D(b, pos)
