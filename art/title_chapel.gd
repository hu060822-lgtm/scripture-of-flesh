class_name TitleChapel
extends Node3D
## 主畫面背景：一座低多邊形的哥德式禮拜堂，在 360p 的 RetroScreen 裡渲染。
## 構圖：奶油黃與灰粉色的棋盤地磚、骨瓷白的柱廊、透進暖光的玫瑰窗（美麗、寧靜、神聖），
## 祭壇上卻是白布蓋著的屍體，垂下一隻縫過的灰粉色手臂；祭壇上方以金鏈吊著一顆放在聖骨匣裡、
## 仍在跳動的心臟；血從祭壇邊緣流下台階（只有這裡是紅色）。兩側是沒有臉的聖人像，手捧一隻眼睛。
## 以美醜、寧靜與殘酷的反差製造恐怖（美術指導）。
##
## 動畫刻意以 12fps 逐格更新（心跳、燭光閃爍、鏡頭緩慢漂移、白布下的呼吸），保留復古的有限幀數感。

const S := preload("res://art/ps1/ps1_style.gd")
## 逐格動畫的更新率。
const FPS := 12.0
## 心跳週期（秒）：「撲通—撲通」兩次收縮，然後停頓。
const BEAT_PERIOD := 1.4
const CAMERA_FROM := Vector3(-2.3, 2.4, 2.2)
const LOOK_AT := Vector3(-2.3, 2.1, -7.5)

var camera: Camera3D
var heart: Node3D
var shroud: MeshInstance3D
var candles: Array[OmniLight3D] = []
## 已經過的「格」數（測試用）。
var frames := 0
var _t := 0.0
var _acc := 0.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "TitleChapel"
	_rng.seed = 732
	_build()

func _process(delta: float) -> void:
	advance(delta)

## 推進時間；只在累積滿一格（1/12 秒）時才更新畫面。
func advance(delta: float) -> void:
	_acc += delta
	var step := 1.0 / FPS
	while _acc >= step:
		_acc -= step
		_t += step
		frames += 1
		_frame()

## 心跳的縮放倍率（0 秒起算）。兩次收縮：第一次較強。
static func beat_scale(t: float) -> float:
	var p := fmod(t, BEAT_PERIOD)
	var s := 0.0
	if p < 0.16:
		s = sin(p / 0.16 * PI) * 0.16
	elif p >= 0.26 and p < 0.4:
		s = sin((p - 0.26) / 0.14 * PI) * 0.09
	return 1.0 + s

func _frame() -> void:
	var b := beat_scale(_t)
	heart.scale = Vector3(b, b * 1.02, b)
	heart.rotation.y = _t * 0.35
	shroud.scale.y = 1.0 + 0.06 * sin(_t * 1.3)
	for c in candles:
		c.light_energy = c.get_meta(&"base") * _rng.randf_range(0.78, 1.12)
	# 鏡頭：極慢的推近與左右漂移，像有人在長椅之間緩步走向祭壇。
	var drift := Vector3(sin(_t * 0.11) * 0.35, sin(_t * 0.17) * 0.08, -0.5 + cos(_t * 0.07) * 0.5)
	camera.position = CAMERA_FROM + drift
	camera.look_at(LOOK_AT + Vector3(sin(_t * 0.09) * 0.25, 0, 0))

# ---------- 建構 ----------

func _build() -> void:
	_environment()
	var w := 12.0
	var d := 22.0
	var h := 9.0
	var zc := -4.0  # 中殿中心
	var tile := S.material(Color.WHITE, "tile", Color.BLACK, 0.0, Vector2(w / 2.0, d / 2.0))
	var stone := S.material(Color.WHITE, "stone", Color.BLACK, 0.0, Vector2(4, 3))
	var dark_stone := S.material(S.GREY_PINK.darkened(0.25), "stone", Color.BLACK, 0.0, Vector2(1, 3))
	var marble := S.material(S.BONE_WHITE, "stone")
	var gold := S.material(S.OLD_GOLD, "metal")
	var red_cloth := S.material(S.DRIED_RED, "cloth")
	S.mesh_node(self, S.box(Vector3(w, 0.2, d)), tile, Vector3(0, -0.1, zc), Vector3.ZERO, "Floor")
	S.mesh_node(self, S.box(Vector3(0.4, h, d)), stone, Vector3(-w * 0.5, h * 0.5, zc), Vector3.ZERO, "WallW")
	S.mesh_node(self, S.box(Vector3(0.4, h, d)), stone, Vector3(w * 0.5, h * 0.5, zc), Vector3.ZERO, "WallE")
	S.mesh_node(self, S.box(Vector3(w, h, 0.4)), stone, Vector3(0, h * 0.5, zc - d * 0.5), Vector3.ZERO, "Apse")
	# 柱廊與尖肋拱
	for i in 5:
		var z := 4.0 - i * 3.6
		for x in [-3.6, 3.6]:
			S.mesh_node(self, S.cylinder(0.3, 0.36, h, 6), dark_stone, Vector3(x, h * 0.5, z), Vector3.ZERO, "Column")
			S.mesh_node(self, S.box(Vector3(0.85, 0.3, 0.85)), dark_stone, Vector3(x, 0.15, z))
			S.mesh_node(self, S.box(Vector3(0.7, 0.2, 0.7)), gold, Vector3(x, h - 2.2, z))
		for side in [-1.0, 1.0]:
			S.mesh_node(self, S.box(Vector3(4.4, 0.25, 0.25)), dark_stone, Vector3(side * 1.75, h - 1.4, z), Vector3(0, 0, side * -22.0))
	_rose_window(zc - d * 0.5 + 0.22)
	_light_shafts()
	_altar(marble, gold, red_cloth)
	_reliquary_heart(gold)
	_saints(marble, gold)
	_pews()
	_candles(gold)

func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("120f0e")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b9a3a0")
	e.ambient_light_energy = 0.32
	e.fog_enabled = true
	e.fog_light_color = Color("2e2624")
	e.fog_density = 0.055
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 55.0
	camera.position = CAMERA_FROM
	add_child(camera)
	camera.current = true
	camera.look_at_from_position(CAMERA_FROM, LOOK_AT)

## 玫瑰窗：十二邊形彩繪玻璃＋陳舊金鉛條輪輻，兩側尖拱窗。
func _rose_window(z: float) -> void:
	var glass := S.material(Color.WHITE, "glass", S.CREAM_YELLOW, 1.1, Vector2(2, 2))
	var lead := S.material(S.OLD_GOLD.darkened(0.35), "metal")
	var c := Vector3(0, 6.0, z)
	S.mesh_node(self, S.cylinder(1.7, 1.7, 0.08, 12), glass, c, Vector3(90, 0, 0), "RoseWindow")
	var ring := TorusMesh.new()
	ring.inner_radius = 1.62
	ring.outer_radius = 1.9
	ring.rings = 12
	ring.ring_segments = 4
	S.mesh_node(self, ring, lead, c + Vector3(0, 0, 0.05), Vector3(90, 0, 0))
	for i in 6:
		S.mesh_node(self, S.box(Vector3(3.3, 0.08, 0.1)), lead, c + Vector3(0, 0, 0.06), Vector3(0, 0, i * 30.0))
	S.mesh_node(self, S.cylinder(0.35, 0.35, 0.1, 8), S.material(S.DRIED_RED, "glass", S.DRIED_RED, 0.8), c + Vector3(0, 0, 0.07), Vector3(90, 0, 0), "RoseEye")
	for x in [-3.0, 3.0]:
		S.mesh_node(self, S.box(Vector3(1.0, 3.2, 0.08)), glass, Vector3(x, 3.6, z))
		for side in [-1.0, 1.0]:
			S.mesh_node(self, S.box(Vector3(0.62, 0.75, 0.08)), glass, Vector3(x + side * 0.18, 5.45, z), Vector3(0, 0, side * -38.0))
	var l := OmniLight3D.new()
	l.position = c + Vector3(0, -1.0, 2.0)
	l.light_color = Color("f4d8a8")
	l.light_energy = 2.2
	l.omni_range = 12.0
	add_child(l)

## 透過玫瑰窗的光柱：加算混色的半透明長方體（不做體積光，維持 PS1 的作法）。
func _light_shafts() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(S.CREAM_YELLOW, 0.1)
	m.disable_receive_shadows = true
	for i in 3:
		var x := -0.9 + i * 0.9
		var shaft := S.mesh_node(self, S.box(Vector3(0.7, 9.0, 0.5)), m, Vector3(x * 1.3, 3.2, -11.0), Vector3(-38.0, 0, x * 8.0), "LightShaft")
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 祭壇：三層台階、骨瓷白石台、陳舊金邊、乾涸紅的長毯；白布蓋著的人形，垂下一隻縫過的手臂；血從台邊流下。
func _altar(marble: Material, gold: Material, red_cloth: Material) -> void:
	var az := -7.5
	for i in 3:
		var s := 6.0 - i * 1.3
		S.mesh_node(self, S.box(Vector3(s, 0.22, s * 0.6)), marble, Vector3(0, 0.11 + i * 0.22, az + 0.2), Vector3.ZERO, "Step")
	S.mesh_node(self, S.box(Vector3(1.0, 0.03, 9.0)), red_cloth, Vector3(0, 0.015, az + 5.2), Vector3.ZERO, "Runner")
	var top := 0.66
	S.mesh_node(self, S.box(Vector3(2.6, 1.0, 1.2)), marble, Vector3(0, top + 0.5, az), Vector3.ZERO, "Altar")
	S.mesh_node(self, S.box(Vector3(2.75, 0.08, 1.3)), gold, Vector3(0, top + 1.02, az))
	S.mesh_node(self, S.box(Vector3(2.62, 0.1, 0.06)), gold, Vector3(0, top + 0.2, az + 0.61))
	# 白布下的人形（頭、胸、腳的起伏）
	var cloth := S.material(S.BONE_WHITE, "cloth")
	shroud = S.mesh_node(self, S.box(Vector3(2.0, 0.24, 0.62)), cloth, Vector3(0, top + 1.18, az), Vector3.ZERO, "Shroud")
	S.mesh_node(shroud, S.sphere(0.2, 6, 3), cloth, Vector3(-0.85, 0.08, 0))
	S.mesh_node(shroud, S.box(Vector3(0.5, 0.12, 0.5)), cloth, Vector3(-0.3, 0.1, 0))
	S.mesh_node(shroud, S.box(Vector3(0.12, 0.1, 0.4)), cloth, Vector3(0.95, 0.08, 0))
	# 垂下的縫合手臂（灰粉色，乾涸紅縫線）
	var skin := S.material(S.GREY_PINK, "stitched")
	var arm := Node3D.new()
	arm.name = "StitchedArm"
	arm.position = Vector3(-0.2, top + 1.12, az + 0.68)
	arm.rotation_degrees = Vector3(8, 0, 6)
	add_child(arm)
	S.mesh_node(arm, S.cylinder(0.065, 0.075, 0.55, 6), skin, Vector3(0, -0.27, 0))
	S.mesh_node(arm, S.box(Vector3(0.13, 0.16, 0.05)), S.material(S.GREY_PINK, "skin"), Vector3(0, -0.62, 0), Vector3.ZERO, "Hand")
	for i in 4:
		S.mesh_node(arm, S.box(Vector3(0.022, 0.13, 0.03)), S.material(S.GREY_PINK, "skin"), Vector3(-0.045 + i * 0.03, -0.76, 0))
	# 血：從手指滴到台階，再沿長毯流下（只有這裡是紅色）
	var blood := S.material(S.DRIED_RED, "flesh", S.DRIED_RED, 0.25)
	S.mesh_node(self, S.box(Vector3(0.05, 0.62, 0.02)), blood, Vector3(-0.22, top + 0.3, az + 0.66), Vector3.ZERO, "Drip")
	S.mesh_node(self, S.box(Vector3(0.6, 0.012, 1.6)), blood, Vector3(-0.15, 0.665, az + 1.2), Vector3(0, 8, 0), "Blood")
	S.mesh_node(self, S.box(Vector3(0.35, 0.012, 2.2)), blood, Vector3(-0.1, 0.03, az + 2.9), Vector3(0, -4, 0))
	# 金聖杯接著血
	S.mesh_node(self, S.cylinder(0.14, 0.05, 0.16, 6), gold, Vector3(0.6, top + 1.14, az + 0.3))
	S.mesh_node(self, S.cylinder(0.02, 0.02, 0.12, 4), gold, Vector3(0.6, top + 1.08, az + 0.3))

## 祭壇上方：以金鏈懸吊的聖骨匣，裡面是仍在跳動的心臟（美術指導第 9 點：重要器官必須清楚可辨）。
func _reliquary_heart(gold: Material) -> void:
	var root := Node3D.new()
	root.name = "Reliquary"
	root.position = Vector3(0, 3.5, -7.5)
	root.scale = Vector3.ONE * 1.35
	add_child(root)
	heart = Node3D.new()
	heart.name = "Heart"
	root.add_child(heart)
	var flesh := S.material(S.DRIED_RED.lightened(0.3), "flesh", Color("8c2a20"), 0.9)
	# 解剖心臟的輪廓：左右心房兩個球、心室主體、往下收尖的心尖
	var h := S.mesh_node(heart, S.sphere(0.3, 7, 4), flesh, Vector3(0, -0.04, 0), Vector3(0, 0, 18), "Muscle")
	h.scale = Vector3(1.0, 1.1, 0.8)
	S.mesh_node(heart, S.sphere(0.19, 6, 3), flesh, Vector3(-0.17, 0.17, 0.02), Vector3.ZERO, "AtriumR")
	S.mesh_node(heart, S.sphere(0.16, 6, 3), S.material(S.DRIED_RED, "flesh", Color("6e1f19"), 0.6), Vector3(0.2, 0.15, -0.02), Vector3.ZERO, "AtriumL")
	S.mesh_node(heart, S.cylinder(0.08, 0.1, 0.32, 5), S.material(S.GREY_PINK.lightened(0.2), "skin", S.GREY_PINK, 0.3), Vector3(0.06, 0.4, 0), Vector3(0, 0, -12), "Aorta")
	S.mesh_node(heart, S.cylinder(0.06, 0.07, 0.24, 5), S.material(S.GREY_PINK.darkened(0.15), "flesh"), Vector3(-0.12, 0.34, 0.05), Vector3(0, 0, 24))
	S.mesh_node(heart, S.cylinder(0.2, 0.0, 0.34, 6), flesh, Vector3(0.07, -0.36, 0), Vector3(0, 0, 18), "Apex")
	# 縫線
	S.mesh_node(heart, S.box(Vector3(0.04, 0.5, 0.02)), S.material(S.BONE_WHITE, "plain"), Vector3(0.05, 0.0, 0.29), Vector3(0, 0, 18))
	# 金籠：兩道直立的環（不擋住心臟正面）
	for i in 2:
		var t := TorusMesh.new()
		t.inner_radius = 0.52
		t.outer_radius = 0.57
		t.rings = 10
		t.ring_segments = 3
		S.mesh_node(root, t, gold, Vector3.ZERO, Vector3(90, 0, 0) if i == 0 else Vector3(0, 0, 90), "Cage")
	S.mesh_node(root, S.cylinder(0.0, 0.18, 0.3, 6), gold, Vector3(0, 0.72, 0), Vector3.ZERO, "Crown")
	S.mesh_node(root, S.cylinder(0.18, 0.0, 0.3, 6), gold, Vector3(0, -0.72, 0))
	for x in [-0.12, 0.12]:
		S.mesh_node(root, S.cylinder(0.015, 0.015, 4.6, 3), gold, Vector3(x, 3.1, 0), Vector3.ZERO, "Chain")
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, -0.2, 0.7)
	glow.light_color = Color("c0503c")
	glow.light_energy = 1.2
	glow.omni_range = 3.2
	root.add_child(glow)

## 無臉聖人像：骨瓷白石像，手捧一隻眼睛。
func _saints(marble: Material, gold: Material) -> void:
	for x in [-2.6, 2.6]:
		var s := Node3D.new()
		s.name = "FacelessSaintL" if x < 0.0 else "FacelessSaintR"
		s.position = Vector3(x, 0.66, -8.6)
		s.rotation_degrees = Vector3(0, -x * 6.0, 0)
		add_child(s)
		S.mesh_node(s, S.box(Vector3(0.9, 0.6, 0.9)), S.material(S.GREY_PINK.darkened(0.25), "stone"), Vector3(0, 0.3, 0))
		S.mesh_node(s, S.cylinder(0.24, 0.44, 1.9, 6), marble, Vector3(0, 1.55, 0), Vector3.ZERO, "Robe")
		S.mesh_node(s, S.sphere(0.2, 6, 3), marble, Vector3(0, 2.68, 0), Vector3.ZERO, "Head")
		S.mesh_node(s, S.cylinder(0.27, 0.27, 0.03, 8), gold, Vector3(0, 2.75, -0.12), Vector3(80, 0, 0), "Halo")
		S.mesh_node(s, S.box(Vector3(0.36, 0.14, 0.18)), marble, Vector3(0, 1.85, 0.22))
		S.mesh_node(s, S.sphere(0.08, 6, 3), S.material(S.BONE_WHITE, "plain", S.CREAM_YELLOW, 0.6), Vector3(0, 1.97, 0.26), Vector3.ZERO, "HeldEye")
		S.mesh_node(s, S.sphere(0.035, 4, 2), S.material(S.SOOT_BLACK, "plain"), Vector3(0, 1.98, 0.33))
		# 臉的位置只有一道縫線
		S.mesh_node(s, S.box(Vector3(0.02, 0.18, 0.02)), S.material(S.DRIED_RED, "plain"), Vector3(0, 2.68, 0.19))

## 前景的木長椅（只是剪影）。
func _pews() -> void:
	var wood := S.material(Color.WHITE, "wood")
	for i in 4:
		var z := 2.6 - i * 1.7
		for x in [-2.0, 2.0]:
			S.mesh_node(self, S.box(Vector3(2.4, 0.08, 0.5)), wood, Vector3(x, 0.5, z))
			S.mesh_node(self, S.box(Vector3(2.4, 0.6, 0.08)), wood, Vector3(x, 0.8, z + 0.26))
			for e in [-1.15, 1.15]:
				S.mesh_node(self, S.box(Vector3(0.08, 1.0, 0.6)), wood, Vector3(x + e, 0.5, z))

## 祭壇台階在 (x, z) 處的頂面高度（蠟燭放在台階上）。
static func step_top(x: float, z: float) -> float:
	var y := 0.0
	for i in 3:
		var s := 6.0 - i * 1.3
		if absf(x) <= s * 0.5 and absf(z - (-7.3)) <= s * 0.3:
			y = 0.22 * (i + 1)
	return y

## 祭壇台階上的蠟燭群＋閃爍的暖光。
func _candles(gold: Material) -> void:
	var wax := S.material(S.CREAM_YELLOW, "plain")
	var flame := S.material(S.CREAM_YELLOW, "plain", Color("ffcf8a"), 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in [-1.0, 1.0]:
		for i in 7:
			var p := Vector3(side * rng.randf_range(1.75, 2.9), 0.0, -7.3 + rng.randf_range(-1.2, 1.5))
			p.y = step_top(p.x, p.z)
			var hgt := rng.randf_range(0.15, 0.4)
			S.mesh_node(self, S.cylinder(0.04, 0.045, hgt, 5), wax, p + Vector3(0, hgt * 0.5, 0), Vector3.ZERO, "Candle")
			S.mesh_node(self, S.sphere(0.03, 4, 2), flame, p + Vector3(0, hgt + 0.04, 0))
		S.mesh_node(self, S.cylinder(0.05, 0.16, 1.8, 5), gold, Vector3(side * 1.6, 1.56, -8.2), Vector3.ZERO, "Candlestand")
		S.mesh_node(self, S.sphere(0.05, 4, 2), flame, Vector3(side * 1.6, 2.55, -8.2))
		for k in 2:
			var c := OmniLight3D.new()
			c.position = Vector3(side * (1.6 + k * 0.8), 1.0 + (1 - k) * 1.6, -7.6 + k * 0.6)
			c.light_color = Color("ffc47a")
			c.set_meta(&"base", 1.1 if k == 0 else 0.8)
			c.light_energy = c.get_meta(&"base")
			c.omni_range = 4.5
			add_child(c)
			candles.append(c)
