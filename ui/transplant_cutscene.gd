class_name TransplantCutscene
extends CanvasLayer
## 器官移植過場（取代原本的紅色閃光）。在縫合祭壇確認移植後播放，約 4 秒，E／Esc 可跳過。
## 以獨立的 3D 世界渲染（低解析度、點取樣）：手術燈下的祭壇石台，舊部位被抬離，
## 新器官（CreatureModels 的移植外觀，例如鐵臂、反關節腿）從上方降下、接上關節，
## 乾涸紅的縫線一針一針出現，最後一下脈動。被排斥時新部位轉為壞死的暗色。
## 播放期間戰鬥維持暫停（由 TransplantScreen 控制），本身以真實時間推進。

signal finished

const RES := Vector2i(320, 180)
const DURATION := 4.2
const S := preload("res://art/ps1/ps1_style.gd")

var viewport: SubViewport
var container: SubViewportContainer
var caption: Label
var time := 0.0
var playing := false
var rejected := false
var stitches: Array[Node3D] = []
var new_part: Node3D
var old_part: Node3D
var _flash: ColorRect
var _lamp: SpotLight3D

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	container = SubViewportContainer.new()
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = RES
	viewport.own_world_3d = true
	container.add_child(viewport)
	_flash = ColorRect.new()
	_flash.color = Color(0.35, 0.03, 0.02, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size = Vector2(800, 40)
	caption.position = Vector2(-400, -90)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color("e8e2d6"))
	add_child(caption)
	visible = false

## 播放。part_def：移植後的部位定義；variant：CreatureModels 的外觀變體（空字串 = 一般外觀）。
func play(part_def: BodyPartDef, profile: AnatomyProfile, look: StringName, variant: StringName, was_rejected: bool, organ_name: String) -> void:
	for c in viewport.get_children():
		viewport.remove_child(c)
		c.queue_free()
	stitches.clear()
	rejected = was_rejected
	_build_stage()
	var lk: Dictionary = CreatureModels.LOOKS.get(look, CreatureModels.LOOKS[&"humanoid"])
	old_part = _part_node(part_def, profile, look, lk, &"")
	old_part.name = "OldPart"
	new_part = _part_node(part_def, profile, look, lk, variant)
	new_part.name = "NewPart"
	viewport.add_child(old_part)
	viewport.add_child(new_part)
	# 縫線：沿著接合處（部位頂端）一圈
	var r := float(PlaceholderBodyBuilder._layout_for(part_def, profile).get("r", 0.08))
	for i in 7:
		var a := float(i) / 7.0 * TAU
		var st := MeshInstance3D.new()
		st.mesh = S.box(Vector3(0.02, 0.05, 0.012))
		st.material_override = S.material(S.DRIED_RED, "flesh", S.DRIED_RED, 0.6)
		st.position = Vector3(cos(a) * r * 1.2, 0.0, sin(a) * r * 1.2) + _joint_point(part_def, profile)
		st.rotation.y = -a
		st.visible = false
		viewport.add_child(st)
		stitches.append(st)
	caption.text = "移植：%s" % organ_name
	time = 0.0
	playing = true
	visible = true
	_apply()

func _build_stage() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("120e0d")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("3a302c")
	e.fog_enabled = true
	e.fog_light_color = Color("1a1412")
	e.fog_density = 0.08
	env.environment = e
	viewport.add_child(env)
	# 祭壇石台與白布
	S.mesh_node(stage, S.box(Vector3(1.6, 0.5, 0.9)), S.material(S.BONE_WHITE.darkened(0.25), "stone"), Vector3(0, -0.45, 0), Vector3.ZERO, "Slab")
	S.mesh_node(stage, S.box(Vector3(1.3, 0.02, 0.7)), S.material(S.CREAM_YELLOW.darkened(0.1), "cloth"), Vector3(0, -0.19, 0), Vector3.ZERO, "Sheet")
	S.mesh_node(stage, S.box(Vector3(0.5, 0.021, 0.3)), S.material(S.DRIED_RED, "flesh"), Vector3(0.25, -0.18, 0.1), Vector3.ZERO, "Blood")
	# 器械盤
	for i in 4:
		S.mesh_node(stage, S.box(Vector3(0.015, 0.01, 0.18)), S.material(Color("b8b4aa"), "metal"), Vector3(-0.55 + i * 0.05, -0.17, 0.25), Vector3(0, 10.0 * i, 0), "Tool%d" % i)
	_lamp = SpotLight3D.new()
	_lamp.light_color = S.CREAM_YELLOW
	_lamp.light_energy = 6.0
	_lamp.spot_range = 5.0
	_lamp.spot_angle = 28.0
	_lamp.position = Vector3(0, 2.2, 0.2)
	_lamp.rotation_degrees = Vector3(-90, 0, 0)
	viewport.add_child(_lamp)
	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.position = Vector3(0.15, 0.55, 0.95)
	viewport.add_child(cam)
	cam.look_at(Vector3(-0.05, -0.05, 0))

## 部位平放在石台上（關節朝左），中心在原點附近。
func _part_node(d: BodyPartDef, profile: AnatomyProfile, look: StringName, lk: Dictionary, variant: StringName) -> Node3D:
	var holder := Node3D.new()
	var seg := MeshInstance3D.new()
	seg.name = String(d.mesh_segment)
	holder.add_child(seg)
	CreatureModels.build_segment(seg, d, profile, look, lk, variant)
	holder.rotation_degrees = Vector3(0, 0, 90)  # 直立的肢體轉成水平
	return holder

func _joint_point(d: BodyPartDef, profile: AnatomyProfile) -> Vector3:
	var h := float(PlaceholderBodyBuilder._layout_for(d, profile).get("h", 0.3))
	return Vector3(-h * 0.5, 0, 0)  # 水平擺放後，頂端（關節）在 -X

func _process(delta: float) -> void:
	if playing:
		advance(delta)

func advance(dt: float) -> void:
	time += dt
	_apply()
	if time >= DURATION:
		stop()

func stop() -> void:
	if not playing:
		return
	playing = false
	visible = false
	finished.emit()

## 時間軸：0–0.8 舊部位被抬起移開；0.8–1.8 新部位降下；1.8–3.2 一針一針縫合；3.2–4.2 脈動（排斥：轉暗）。
func _apply() -> void:
	var t := time
	if old_part != null:
		var k := clampf(t / 0.8, 0.0, 1.0)
		old_part.position = Vector3(-k * 0.3, k * 1.4, -k * 0.4)
		old_part.visible = k < 1.0
	if new_part != null:
		var k := clampf((t - 0.8) / 1.0, 0.0, 1.0)
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		new_part.position = Vector3(0, (1.0 - ease_k) * 1.2, 0)
		new_part.visible = t >= 0.8
		var pulse := 0.0
		if t > 3.2:
			pulse = sin((t - 3.2) * TAU * 1.5) * 0.04 * (1.0 - clampf((t - 3.2) / 1.0, 0.0, 1.0))
		new_part.scale = Vector3.ONE * (1.0 + pulse)
		if rejected and t > 3.2:
			if not new_part.has_meta(&"necrotic"):
				# 壞死：所有材質轉為暗沉的灰綠
				new_part.set_meta(&"necrotic", true)
				for mi in new_part.find_children("*", "MeshInstance3D", true, false):
					var m := (mi as MeshInstance3D).material_override as ShaderMaterial
					if m != null:
						var dark := m.duplicate() as ShaderMaterial
						var c: Color = dark.get_shader_parameter("albedo")
						dark.set_shader_parameter("albedo", c.lerp(Color("4a5238"), 0.6).darkened(0.3))
						(mi as MeshInstance3D).material_override = dark
			_lamp.light_color = S.CREAM_YELLOW.lerp(Color("5a6a40"), clampf((t - 3.2) / 0.8, 0.0, 1.0))
	var shown := int(clampf((t - 1.8) / 1.4, 0.0, 1.0) * stitches.size())
	for i in stitches.size():
		stitches[i].visible = i < shown
	var fl := 0.0
	if t > 3.2 and t < 3.6:
		fl = (1.0 - absf((t - 3.4) / 0.2)) * 0.6
	_flash.color.a = fl
	if rejected and t > 3.4:
		caption.text = "身體正在排斥新的器官……"

func stitches_shown() -> int:
	var n := 0
	for s in stitches:
		if s.visible:
			n += 1
	return n

func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		stop()
		get_viewport().set_input_as_handled()
