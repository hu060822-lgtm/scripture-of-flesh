class_name DialogueBox
extends CanvasLayer
## 對話框 UI。開啟時暫停戰鬥並停用玩家輸入。
## E／Enter／左鍵：下一句；1–4 或點選按鈕：選擇選項。
## 【暫代】外觀：純色面板，無立繪、無打字機效果、無語音。

signal closed
signal action_requested(action: StringName, arg: String)

var runner := DialogueRunner.new()
var player: Node3D
var _panel: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _hint: Label

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.custom_minimum_size = Vector2(860, 210)
	_panel.position = Vector2(-430, -240)
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 18)
	_speaker.add_theme_color_override("font_color", Color("c9a27a"))
	v.add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(840, 80)
	v.add_child(_text)
	_choices = VBoxContainer.new()
	v.add_child(_choices)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(1, 1, 1, 0.5)
	v.add_child(_hint)
	runner.node_entered.connect(func(_n): refresh())
	runner.finished.connect(func(_id): close_box())
	runner.action_requested.connect(func(a, arg): action_requested.emit(a, arg))
	visible = false

func is_open() -> bool:
	return visible

## dialogue：對話 id（content/dialogue/<id>.json）或已載入的 Dictionary。
func open(dialogue, p: Node3D) -> bool:
	player = p
	visible = true
	TimeScale.set_mode(TimeScale.Mode.PAUSE)
	_set_player_input(false)
	if not runner.start(dialogue, p):
		close_box()
		return false
	return true

func close_box() -> void:
	if not visible:
		return
	visible = false
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	_set_player_input(true)
	closed.emit()

func refresh() -> void:
	_speaker.text = runner.speaker()
	_text.text = runner.text()
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	var cs := runner.choices()
	for i in cs.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, cs[i]["text"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		b.pressed.connect(func(): runner.choose(idx))
		_choices.add_child(b)
	_hint.text = "1–%d：選擇" % cs.size() if not cs.is_empty() else "E：繼續"

func _set_player_input(on: bool) -> void:
	if player != null and player.has_node("PlayerController"):
		(player.get_node("PlayerController") as PlayerController).input_enabled = on

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_4:
			runner.choose(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("attack_light"):
		runner.advance()
		get_viewport().set_input_as_handled()
