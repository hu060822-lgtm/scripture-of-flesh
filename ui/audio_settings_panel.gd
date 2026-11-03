class_name AudioSettingsPanel
extends PanelContainer
## 聲音設定：每個匯流排一條音量滑桿，關閉時存到 user://settings.cfg。【暫代】外觀。

signal closed

const LABELS := {
	&"Master": "總音量", &"Music": "音樂", &"Ambience": "環境音",
	&"SFX": "音效", &"UI": "介面", &"Voice": "人聲",
}

var sliders := {}
var flashes: CheckButton

func _ready() -> void:
	custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var title := Label.new()
	title.text = "聲音設定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)
	for bus in LABELS:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = LABELS[bus]
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(280, 24)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value = AudioManager.get_volume(bus)
		s.value_changed.connect(func(x): AudioManager.set_volume(bus, x))
		row.add_child(s)
		sliders[bus] = s
		v.add_child(row)
	flashes = CheckButton.new()
	flashes.text = "瀕死畫面的閃爍效果（剪影、雙重影像）"
	flashes.button_pressed = InjuryOverlay.load_flashes_setting(AudioManager.settings_path)
	flashes.toggled.connect(func(on): InjuryOverlay.save_flashes_setting(AudioManager.settings_path, on))
	v.add_child(flashes)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(close)
	v.add_child(back)

func close() -> void:
	AudioManager.save_settings()
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
