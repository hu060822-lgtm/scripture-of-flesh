class_name PortraitView
extends SubViewportContainer
## 對話立繪：以獨立的 3D 世界即時渲染說話者的半身像（CreatureModels.bust），
## 低解析度（64×64）放大顯示、點取樣，與遊戲畫面同樣是 PS1 風格。
## 說話時頭部輕微晃動（12fps 逐格），非說話者時停住。

const RES := 64
const DISPLAY := 128

var viewport: SubViewport
var camera: Camera3D
var bust: Node3D
var look: StringName = &""
var talking := false
var _t := 0.0
var _acc := 0.0

func _ready() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(DISPLAY, DISPLAY)
	viewport = SubViewport.new()
	viewport.size = Vector2i(RES, RES)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1a1614")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("6a5a50")
	env.environment = e
	viewport.add_child(env)
	var key := OmniLight3D.new()
	key.light_color = Color("efe2b0")
	key.light_energy = 2.0
	key.omni_range = 4.0
	key.position = Vector3(0.6, 2.2, -0.9)
	viewport.add_child(key)
	camera = Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)

## look 為空字串時隱藏立繪（旁白）。
func show_speaker(new_look: StringName) -> void:
	visible = new_look != &""
	if new_look == look:
		return
	look = new_look
	if bust != null:
		bust.queue_free()
		bust = null
	if look == &"":
		return
	bust = CreatureModels.bust(look)
	viewport.add_child(bust)
	# 鏡頭對準頭部，從正前方略偏
	var head := bust.find_child("seg_head", true, false) as Node3D
	var target := head.position if head != null else Vector3(0, 1.7, 0)
	var dist := 0.75 if look != &"walking_mother" else 1.2
	camera.position = target + Vector3(0.18, 0.02, -dist)
	camera.look_at(target - Vector3(0, 0.08, 0), Vector3.UP)

func _process(delta: float) -> void:
	if bust == null or not visible:
		return
	_acc += delta
	if _acc < 1.0 / 12.0:
		return
	_t += _acc
	_acc = 0.0
	var head := bust.find_child("seg_head", true, false) as Node3D
	var jaw := bust.find_child("seg_jaw", true, false) as Node3D
	var amount := 1.0 if talking else 0.25
	bust.rotation.y = sin(_t * 0.7) * 0.06
	if head != null:
		head.rotation.x = sin(_t * 3.1) * 0.05 * amount
	if jaw != null:
		jaw.rotation.x = (absf(sin(_t * 11.0)) * 0.25) if talking else 0.0
