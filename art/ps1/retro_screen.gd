class_name RetroScreen
extends SubViewportContainer
## 低解析度畫面：3D 世界畫在小尺寸的 SubViewport 上，再以點取樣放大到視窗（stretch_shrink）。
## 後處理（色階＋抖色）只套在這一層，UI（CanvasLayer）保持清晰。
## world 是 3D 內容的父節點。

const POST := preload("res://art/ps1/ps1_post.gdshader")
## 可切換的垂直解析度（F2）。預設 360p（遊玩回饋：240p 太糊）。
const HEIGHTS := [240, 360, 480]
const DEFAULT_HEIGHT := 360

var viewport: SubViewport
var world: Node3D
var height_index := HEIGHTS.find(DEFAULT_HEIGHT)
var effects_enabled := true

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_3d = true
	add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	var m := ShaderMaterial.new()
	m.shader = POST
	material = m

func _ready() -> void:
	apply_settings()
	get_viewport().size_changed.connect(apply_settings)

func target_height() -> int:
	return HEIGHTS[height_index] if effects_enabled else int(get_viewport_rect().size.y)

func apply_settings() -> void:
	var win := get_viewport_rect().size
	if win.y <= 0:
		return
	stretch_shrink = maxi(1, int(round(win.y / float(target_height()))))
	var low := Vector2(win.x / stretch_shrink, win.y / stretch_shrink)
	PS1Style.snap_resolution = low * 0.5 if effects_enabled else Vector2.ZERO
	PS1Style.jitter_enabled = effects_enabled and PS1Style.jitter_enabled
	PS1Style.refresh_all()
	(material as ShaderMaterial).set_shader_parameter("enabled", effects_enabled and dither_enabled)

var dither_enabled := true

func toggle_effects() -> void:
	effects_enabled = not effects_enabled
	if effects_enabled:
		PS1Style.jitter_enabled = true
	apply_settings()

func cycle_resolution() -> void:
	height_index = (height_index + 1) % HEIGHTS.size()
	apply_settings()

func toggle_dither() -> void:
	dither_enabled = not dither_enabled
	apply_settings()

func toggle_jitter() -> void:
	PS1Style.jitter_enabled = not PS1Style.jitter_enabled
	apply_settings()

func describe() -> String:
	return "%s　%dp　抖色%s　頂點抖動%s" % ["PS1 效果開" if effects_enabled else "PS1 效果關", target_height(),
		"開" if dither_enabled and effects_enabled else "關", "開" if PS1Style.jitter_enabled and effects_enabled else "關"]
