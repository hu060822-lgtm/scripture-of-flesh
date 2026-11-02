class_name PS1Style
extends RefCounted
## PS1 低多邊形風格工具：色盤、程序生成的低解析度貼圖（32–64px、點取樣）、PS1 材質、基本形狀與斷面。
## 生物的具象外觀見 CreatureModels（M10，取代原本的 stylize()）。
##
## 【美術測試】所有貼圖都是程式產生的測試貼圖，用來確認方向；確認後才製作正式資產。

const SHADER := preload("res://art/ps1/ps1_spatial.gdshader")

## 色盤（美術指導）
const BONE_WHITE := Color("e8e2d6")
const DRIED_RED := Color("6e1f19")
const SOOT_BLACK := Color("2a2725")
const OLD_GOLD := Color("a8863f")
const CREAM_YELLOW := Color("efe2b0")
const GREY_PINK := Color("b9a3a0")

## 全域設定（美術測試的 F 鍵切換）。
static var jitter_enabled := true
static var snap_resolution := Vector2(320, 240)

static var _textures := {}
static var _materials := {}

# ---------- 貼圖 ----------

## kind：plain、skin、cloth、stitched、tile、stone、wood、metal、glass、flesh、bone
static func texture(kind: String, size: int = 32) -> ImageTexture:
	var key := "%s_%d" % [kind, size]
	if _textures.has(key):
		return _textures[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in size:
		for x in size:
			img.set_pixel(x, y, _texel(kind, x, y, size, rng))
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex

static func _texel(kind: String, x: int, y: int, size: int, rng: RandomNumberGenerator) -> Color:
	var n := rng.randf()
	match kind:
		"skin":
			return Color.WHITE.darkened(0.04 + n * 0.08)
		"cloth":
			return Color.WHITE.darkened(0.1 + (0.12 if (x + y) % 4 == 0 else 0.0) + n * 0.06)
		"stitched":
			# 皮膚上有乾涸紅的縫線（水平縫線＋短交叉線）
			var line := y % 12 == 6 and true
			var cross := y % 12 >= 5 and y % 12 <= 7 and x % 4 == 0
			if line or cross:
				return DRIED_RED.lightened(0.15)
			return Color.WHITE.darkened(0.05 + n * 0.1)
		"tile":
			# 奶油黃與灰粉色的棋盤磁磚，有細縫
			var tile := 8
			if x % tile == 0 or y % tile == 0:
				return Color("8a8070")
			var odd := ((x / tile) + (y / tile)) % 2 == 1
			return (GREY_PINK.lightened(0.25) if odd else CREAM_YELLOW.darkened(0.05)).darkened(n * 0.06)
		"stone":
			var row := y / 8
			var off := 8 if row % 2 == 1 else 0
			if y % 8 == 0 or (x + off) % 16 == 0:
				return Color("9a9284")
			return BONE_WHITE.darkened(0.05 + n * 0.08)
		"wood":
			return Color("5a3a2a").lightened(0.05 * sin(float(y) * 0.9) + n * 0.05)
		"metal":
			return Color("8a8a88").lightened(n * 0.12 - (0.1 if x % 8 == 0 else 0.0))
		"glass":
			# 彩繪玻璃：菱形格，陳舊金鉛條
			var d := (x + y) % 16
			var e := (x - y + size) % 16
			if d == 0 or e == 0:
				return OLD_GOLD.darkened(0.3)
			var cell := ((x + y) / 16 + (x - y + size) / 16) % 3
			return [CREAM_YELLOW, GREY_PINK, Color("c9a27a")][cell].darkened(n * 0.08)
		"flesh":
			return DRIED_RED.lightened(0.1 + n * 0.25)
		"bone":
			return BONE_WHITE.darkened(n * 0.1)
	return Color.WHITE.darkened(n * 0.05)

# ---------- 材質 ----------

static func material(color: Color, kind: String = "plain", emission: Color = Color.BLACK, energy: float = 0.0, uv_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s" % [color.to_html(), kind, emission.to_html(), energy, uv_scale]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", texture(kind, 64 if kind in ["tile", "stone", "glass"] else 32))
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("emission", emission)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("snap_resolution", snap_resolution)
	m.set_shader_parameter("jitter_enabled", jitter_enabled)
	_materials[key] = m
	return m

## 套用目前的全域設定到所有已建立的材質（切換抖動、改解析度）。
static func refresh_all() -> void:
	for m in _materials.values():
		(m as ShaderMaterial).set_shader_parameter("snap_resolution", snap_resolution)
		(m as ShaderMaterial).set_shader_parameter("jitter_enabled", jitter_enabled)

# ---------- 低多邊形網格 ----------

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func cylinder(top: float, bottom: float, height: float, sides: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	c.rings = 0
	return c

static func sphere(r: float, sides: int = 6, rings: int = 3) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = sides
	s.rings = rings
	return s

static func mesh_node(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if name != "":
		mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

## 斷面：外圈皮膚、乾涸紅的肉、突出的骨瓷白骨頭（DismembermentController.cap_builder 使用）。
## 以 +Y 為「朝外」方向建立；DismembermentController 會把 +Y 對齊關節朝外的方向。
## 肉面帶一點自發光：美術指導第 9 點，斷肢位置必須有辨識度。
static func build_stump_cap(part_id: StringName) -> Node3D:
	var cap := Node3D.new()
	var r := 0.075
	var pid := String(part_id)
	if pid.begins_with("head") or pid.begins_with("neck"):
		r = 0.085
	elif pid.begins_with("leg") or pid.begins_with("stilt"):
		r = 0.09
	mesh_node(cap, cylinder(r * 1.1, r * 1.15, 0.03, 6), material(GREY_PINK, "skin"), Vector3(0, 0.0, 0), Vector3.ZERO, "SkinRing")
	mesh_node(cap, cylinder(r, r, 0.04, 6), material(DRIED_RED, "flesh", DRIED_RED, 0.5), Vector3(0, 0.02, 0), Vector3.ZERO, "Flesh")
	mesh_node(cap, cylinder(r * 0.32, r * 0.38, 0.09, 5), material(BONE_WHITE, "bone", BONE_WHITE, 0.25), Vector3(0, 0.07, 0), Vector3.ZERO, "Bone")
	mesh_node(cap, sphere(r * 0.35, 5, 2), material(DRIED_RED.darkened(0.2), "flesh"), Vector3(r * 0.5, 0.0, r * 0.3), Vector3.ZERO, "Clot")
	return cap
