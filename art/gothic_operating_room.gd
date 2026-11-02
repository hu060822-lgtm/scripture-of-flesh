class_name GothicOperatingRoom
extends RefCounted
## 【美術測試】哥德式手術室：用低多邊形方塊與程序貼圖組成。
## 方向：乾淨、明亮、近乎神聖的白色空間（奶油黃磁磚、骨瓷白石牆、彩繪玻璃的暖光），
## 只在細節處放進殘酷的東西（排水溝的乾涸紅、玻璃罐裡的器官、手術台的束帶）——以反差製造恐怖。

const S := preload("res://art/ps1/ps1_style.gd")

static func build(parent: Node3D) -> Node3D:
	var room := Node3D.new()
	room.name = "GothicOperatingRoom"
	parent.add_child(room)
	var w := 14.0
	var d := 16.0
	var h := 7.0
	var tile := S.material(Color.WHITE, "tile", Color.BLACK, 0.0, Vector2(w / 2.0, d / 2.0))
	var stone := S.material(Color.WHITE, "stone", Color.BLACK, 0.0, Vector2(4, 2))
	var dark_stone := S.material(S.GREY_PINK.darkened(0.2), "stone", Color.BLACK, 0.0, Vector2(1, 2))
	# 地板（有碰撞）
	_solid(room, Vector3(0, -0.1, 0), Vector3(w, 0.2, d), tile, "Floor")
	# 牆（東、西、北；南側開放給鏡頭）
	_solid(room, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.4, h, d), stone, "WallW")
	_solid(room, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.4, h, d), stone, "WallE")
	_solid(room, Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 0.4), stone, "WallN")
	_solid(room, Vector3(-w * 0.5 + 0.3, 0.15, d * 0.5 - 0.2), Vector3(0.2, 0.3, 0.2), dark_stone, "Corner")
	# 哥德式柱與肋拱（六角柱，頂端斜樑交會成尖拱）
	for z in [-6.0, -1.5, 3.0]:
		for x in [-w * 0.5 + 0.7, w * 0.5 - 0.7]:
			S.mesh_node(room, S.cylinder(0.32, 0.38, h, 6), dark_stone, Vector3(x, h * 0.5, z))
			S.mesh_node(room, S.box(Vector3(0.9, 0.3, 0.9)), dark_stone, Vector3(x, 0.15, z))
		for side in [-1.0, 1.0]:
			S.mesh_node(room, S.box(Vector3(w * 0.56, 0.25, 0.25)), dark_stone,
				Vector3(side * w * 0.24, h - 0.3, z), Vector3(0, 0, side * -14.0))
	# 尖拱彩繪玻璃窗（北牆三扇）：細長窗身＋兩塊斜板組成尖頂，自發光模擬透進來的暖光
	var glass := S.material(Color.WHITE, "glass", S.CREAM_YELLOW, 0.9, Vector2(1, 2))
	var lead := S.material(S.OLD_GOLD.darkened(0.3), "metal")
	for x in [-4.0, 0.0, 4.0]:
		var ww := 1.6 if x == 0.0 else 1.2
		var wh := 3.4 if x == 0.0 else 2.8
		S.mesh_node(room, S.box(Vector3(ww, wh, 0.08)), glass, Vector3(x, 2.2 + wh * 0.5, -d * 0.5 + 0.22))
		for side in [-1.0, 1.0]:
			S.mesh_node(room, S.box(Vector3(ww * 0.62, 0.9, 0.08)), glass,
				Vector3(x + side * ww * 0.22, 2.2 + wh + 0.3, -d * 0.5 + 0.22), Vector3(0, 0, side * -38.0))
		S.mesh_node(room, S.box(Vector3(ww + 0.2, 0.12, 0.14)), lead, Vector3(x, 2.15, -d * 0.5 + 0.24))
	# 手術台：骨瓷白石台＋陳舊金邊＋乾涸紅的束帶
	var marble := S.material(S.BONE_WHITE, "stone")
	var gold := S.material(S.OLD_GOLD, "metal")
	_solid(room, Vector3(0, 0.5, -2.0), Vector3(1.2, 1.0, 2.6), marble, "OperatingTable")
	S.mesh_node(room, S.box(Vector3(1.3, 0.08, 2.7)), gold, Vector3(0, 1.02, -2.0))
	for z in [-2.8, -1.6]:
		S.mesh_node(room, S.box(Vector3(1.32, 0.06, 0.14)), S.material(S.DRIED_RED, "cloth"), Vector3(0, 1.07, z))
	# 白布下的人形（只露出一隻灰粉色的手）
	S.mesh_node(room, S.box(Vector3(0.7, 0.22, 1.9)), S.material(S.BONE_WHITE, "cloth"), Vector3(0, 1.16, -2.0))
	S.mesh_node(room, S.box(Vector3(0.16, 0.06, 0.28)), S.material(S.GREY_PINK, "skin"), Vector3(0.48, 1.06, -1.2), Vector3(0, 12, 0))
	# 排水溝與乾涸的血跡（只有這裡是紅色）
	S.mesh_node(room, S.box(Vector3(0.5, 0.02, 0.5)), S.material(S.SOOT_BLACK, "metal"), Vector3(0, 0.01, -0.2))
	S.mesh_node(room, S.box(Vector3(1.4, 0.015, 0.6)), S.material(S.DRIED_RED, "flesh"), Vector3(0.3, 0.008, -0.5), Vector3(0, 20, 0))
	# 手術燈：吊在肋拱下的黃銅燈罩＋聚光
	S.mesh_node(room, S.cylinder(0.05, 0.6, 0.45, 8), gold, Vector3(0, 4.2, -2.0))
	S.mesh_node(room, S.cylinder(0.02, 0.02, h - 4.4, 4), gold, Vector3(0, 4.4 + (h - 4.4) * 0.5, -2.0))
	var lamp := SpotLight3D.new()
	lamp.name = "SurgicalLamp"
	lamp.position = Vector3(0, 4.0, -2.0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.light_color = S.CREAM_YELLOW
	lamp.light_energy = 3.0
	lamp.spot_range = 6.0
	lamp.spot_angle = 32.0
	lamp.shadow_enabled = true
	room.add_child(lamp)
	# 器具推車（金屬）
	S.mesh_node(room, S.box(Vector3(0.8, 0.05, 0.5)), S.material(Color.WHITE, "metal"), Vector3(1.6, 0.95, -2.4))
	for i in 4:
		S.mesh_node(room, S.box(Vector3(0.04, 0.02, 0.32)), S.material(Color.WHITE, "metal"), Vector3(1.35 + i * 0.16, 0.98, -2.4), Vector3(0, i * 9, 0))
	S.mesh_node(room, S.box(Vector3(0.05, 0.9, 0.05)), S.material(Color.WHITE, "metal"), Vector3(1.6, 0.45, -2.4))
	# 標本櫃：木櫃＋發出奶油黃微光的玻璃罐，罐裡是器官（心臟、眼球）
	_solid(room, Vector3(-w * 0.5 + 0.8, 1.3, -4.0), Vector3(1.0, 2.6, 2.4), S.material(Color.WHITE, "wood"), "SpecimenCabinet")
	var jar := S.material(S.CREAM_YELLOW, "glass", S.CREAM_YELLOW, 0.5)
	for i in 3:
		for j in 2:
			var p := Vector3(-w * 0.5 + 1.35, 0.9 + j * 0.9, -4.8 + i * 0.8)
			S.mesh_node(room, S.cylinder(0.16, 0.16, 0.42, 6), jar, p)
			S.mesh_node(room, S.sphere(0.09, 5, 2), S.material(S.DRIED_RED, "flesh", S.DRIED_RED, 0.3), p + Vector3(0, -0.03, 0))
	# 燭台（陳舊金）＋低能量暖光
	for p in [Vector3(-5.5, 0, 3.5), Vector3(5.5, 0, 3.5), Vector3(5.5, 0, -6.0)]:
		S.mesh_node(room, S.cylinder(0.04, 0.12, 1.4, 5), gold, p + Vector3(0, 0.7, 0))
		S.mesh_node(room, S.cylinder(0.035, 0.035, 0.18, 5), S.material(S.CREAM_YELLOW, "plain", S.CREAM_YELLOW, 1.5), p + Vector3(0, 1.5, 0))
		var c := OmniLight3D.new()
		c.position = p + Vector3(0, 1.7, 0)
		c.light_color = Color("ffcf8a")
		c.light_energy = 0.9
		c.omni_range = 5.0
		room.add_child(c)
	# 透過彩繪玻璃的暖光
	var window_light := OmniLight3D.new()
	window_light.position = Vector3(0, 4.5, -d * 0.5 + 1.2)
	window_light.light_color = Color("f4d8a8")
	window_light.light_energy = 1.6
	window_light.omni_range = 11.0
	room.add_child(window_light)
	return room

static func environment(parent: Node) -> WorldEnvironment:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1a1615")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c9b8a8")
	e.ambient_light_energy = 0.45
	e.fog_enabled = true
	e.fog_light_color = Color("3a302c")
	e.fog_density = 0.035
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	parent.add_child(env)
	return env

static func _solid(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.collision_layer = PlaceholderBodyBuilder.WORLD_LAYER
	b.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	b.add_child(cs)
	S.mesh_node(b, S.box(size), mat)
	parent.add_child(b)
	return b
