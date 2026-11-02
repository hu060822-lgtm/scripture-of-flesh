class_name DialogueBox
extends CanvasLayer
## 對話框 UI。開啟時暫停戰鬥並停用玩家輸入。
## E／Enter／左鍵：下一句（文字還在打字時先顯示整句）；1–4 或點選按鈕：選擇選項。
## 打字機效果（每秒 CHARS_PER_SECOND 字，標點停頓）；說話者有 3D 即時渲染的半身立繪（PortraitView）。
## 語音與音效由音訊系統負責（另一個工作串）：每顯示一個字會發出 typed 訊號，供音效掛接。

signal closed
signal action_requested(action: StringName, arg: String)
## 每顯示一個字（音效掛接用）。
signal typed(character: String)

const CHARS_PER_SECOND := 38.0
## 標點後的額外停頓（秒）。
const PUNCT_PAUSE := {"，": 0.12, "、": 0.1, "。": 0.28, "……": 0.35, "？": 0.25, "！": 0.25, "：": 0.12}
## 說話者名稱 -> 立繪外觀（CreatureModels.LOOKS）。旁白（空名稱）沒有立繪。
const PORTRAITS := {"阿格妮絲": &"agnes", "行走的母親": &"walking_mother"}

var runner := DialogueRunner.new()
var player: Node3D
var _panel: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _hint: Label
var portrait: PortraitView
var _typing_left := 0.0
var _pause := 0.0

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.custom_minimum_size = Vector2(860, 210)
	_panel.position = Vector2(-430, -240)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)
	portrait = PortraitView.new()
	portrait.name = "Portrait"
	row.add_child(portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 18)
	_speaker.add_theme_color_override("font_color", Color("c9a27a"))
	v.add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(700, 80)
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
	_text.visible_characters = 0
	_typing_left = 0.0
	_pause = 0.0
	portrait.show_speaker(PORTRAITS.get(runner.speaker(), &""))
	_choices.visible = false
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
	_update_typing_state()

func is_typing() -> bool:
	return _text.visible_characters >= 0 and _text.visible_characters < _text.get_total_character_count()

## 立刻顯示整句。
func finish_typing() -> void:
	_text.visible_characters = -1
	_update_typing_state()

## 推進打字機（真實時間；戰鬥暫停時對話照常進行）。測試可直接呼叫。
func type_step(delta: float) -> void:
	if not visible or not is_typing():
		return
	if _pause > 0.0:
		_pause -= delta
		return
	_typing_left += delta * CHARS_PER_SECOND
	while _typing_left >= 1.0 and is_typing():
		_typing_left -= 1.0
		_text.visible_characters += 1
		var plain := _text.get_parsed_text()
		var ch := plain.substr(_text.visible_characters - 1, 1)
		typed.emit(ch)
		for p in PUNCT_PAUSE:
			if plain.substr(_text.visible_characters - String(p).length(), String(p).length()) == p:
				_pause = PUNCT_PAUSE[p]
				_typing_left = 0.0
				break
		if _pause > 0.0:
			break
	_update_typing_state()

func _update_typing_state() -> void:
	var typing := is_typing()
	portrait.talking = typing
	_choices.visible = not typing
	if typing:
		_hint.text = "E：顯示全文"
	elif _choices.get_child_count() > 0:
		_hint.text = "1–%d：選擇" % _choices.get_child_count()
	else:
		_hint.text = "E：繼續"

func _process(delta: float) -> void:
	type_step(delta)

func _set_player_input(on: bool) -> void:
	if player != null and player.has_node("PlayerController"):
		(player.get_node("PlayerController") as PlayerController).input_enabled = on

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_4 and not is_typing():
			runner.choose(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("attack_light"):
		if is_typing():
			finish_typing()
		else:
			runner.advance()
		get_viewport().set_input_as_handled()
