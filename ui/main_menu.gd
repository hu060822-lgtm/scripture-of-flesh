class_name MainMenu
extends Control
## 主選單：新遊戲／繼續／戰鬥沙盒／離開。【暫代】外觀：純文字按鈕，無背景美術。

const PROLOGUE := "res://scenes/prologue/prologue.tscn"
const SANDBOX := "res://scenes/sandbox/combat_sandbox.tscn"

var continue_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("141211")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(360, 320)
	v.position = Vector2(-180, -160)
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var title := Label.new()
	title.text = "肉身聖典"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("e8e2d6"))
	v.add_child(title)
	var sub := Label.new()
	sub.text = "THE SCRIPTURE OF FLESH　—　序章"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color("a04a3e"))
	v.add_child(sub)
	_button(v, "新遊戲", new_game)
	continue_button = _button(v, "繼續", continue_game)
	continue_button.disabled = not SaveSystem.exists()
	_button(v, "戰鬥沙盒", func(): get_tree().change_scene_to_file(SANDBOX))
	_button(v, "離開", func(): get_tree().quit())

func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func new_game() -> void:
	GameState.reset()
	GameState.start_mode = "new"
	get_tree().change_scene_to_file(PROLOGUE)

func continue_game() -> void:
	GameState.start_mode = "continue"
	get_tree().change_scene_to_file(PROLOGUE)
