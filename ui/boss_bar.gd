class_name BossBar
extends CanvasLayer
## Boss 血條與階段提示，以及登場標題卡。
## 【暫代】標題卡為純文字淡入淡出，取代正式的 Boss 登場演出（鏡頭、動畫、音樂待製作）。

const TITLE_SECONDS := 3.5

var boss: Node3D
var _bar: ProgressBar
var _name: Label
var _phase: Label
var _title: Label
var _subtitle: Label
var _title_left := 0.0

func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.custom_minimum_size = Vector2(640, 60)
	box.position = Vector2(-320, -92)
	add_child(box)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(640, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("8a1c14")
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	_phase = Label.new()
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase.add_theme_font_size_override("font_size", 12)
	box.add_child(_phase)
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.custom_minimum_size = Vector2(800, 60)
	_title.position = Vector2(-400, -80)
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", Color("e8e2d6"))
	add_child(_title)
	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_CENTER)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.custom_minimum_size = Vector2(800, 30)
	_subtitle.position = Vector2(-400, -20)
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.add_theme_color_override("font_color", Color("a04a3e"))
	add_child(_subtitle)
	visible = false

func show_boss(b: Node3D, title: String, subtitle: String) -> void:
	boss = b
	visible = true
	_title.text = title
	_subtitle.text = subtitle
	_title_left = TITLE_SECONDS
	_name.text = title
	refresh()

func hide_boss() -> void:
	boss = null
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	if _title_left > 0.0:
		_title_left -= delta
		var a := clampf(minf(_title_left, TITLE_SECONDS - _title_left) / 0.6, 0.0, 1.0)
		_title.modulate.a = a
		_subtitle.modulate.a = a
	else:
		_title.modulate.a = 0.0
		_subtitle.modulate.a = 0.0
	refresh()

func refresh() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var c: CombatComponent = boss.get_node("CombatComponent")
	_bar.max_value = c.pools.max_hp
	_bar.value = c.pools.hp
	var bp: BossPhaseComponent = boss.get_node_or_null("BossPhase")
	if bp != null:
		var lines := ["第%s階段" % ("一" if bp.phase == 1 else "二"), "高蹺腿 %d" % bp.stilts(), "臍帶 %d" % bp.cords()]
		if bp.phase == 2:
			lines.append("子宮暴露")
		_phase.text = "　".join(lines)
