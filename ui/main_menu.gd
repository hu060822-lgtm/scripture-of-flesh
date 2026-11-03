class_name MainMenu
extends Control
## 主選單：新遊戲／繼續／戰鬥沙盒／美術測試／聲音設定／離開。
## 背景是 360p RetroScreen 裡的 3D 低多邊形哥德禮拜堂（TitleChapel）；
## 標題字以低解析度 SubViewport 繪製後點取樣放大，與 3D 畫面同樣是 PS1 的像素感；
## 選單文字保持清晰（可讀性優先）。可用滑鼠或方向鍵＋Enter 操作，開場由黑淡入，開始遊戲時淡出。

const PROLOGUE := "res://scenes/prologue/prologue.tscn"
const SANDBOX := "res://scenes/sandbox/combat_sandbox.tscn"
const ART_TEST := "res://scenes/art_test/art_test.tscn"
## 操作說明畫面（新手引導那邊的工作）。檔案存在時才顯示「操作說明」選項；以 load() 載入，避免檔案尚未合併時解析失敗。
const CONTROLS := "res://ui/controls_screen.gd"
const S := preload("res://art/ps1/ps1_style.gd")

const FADE_IN := 1.2
const FADE_OUT := 0.7
## 標題字的低解析度畫布大小（顯示時放大 LOGO_SCALE 倍）。
const LOGO_RES := Vector2i(300, 92)
const LOGO_SCALE := 2
const MARKER := "†  "

var continue_button: Button
var audio_button: Button
var controls_screen: Node
var audio_panel: AudioSettingsPanel
var screen: RetroScreen
var chapel: TitleChapel
var buttons: Array[Button] = []
var _menu_box: VBoxContainer
var _fade: ColorRect
var _fade_t := 0.0
var _leaving := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("120f0e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	screen = RetroScreen.new()
	screen.name = "RetroScreen"
	add_child(screen)
	chapel = TitleChapel.new()
	screen.world.add_child(chapel)
	_vignette()
	var col := VBoxContainer.new()
	col.name = "Column"
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 72
	col.offset_right = 72 + LOGO_RES.x * LOGO_SCALE
	col.offset_top = 64
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.add_child(_logo())
	var rule := ColorRect.new()
	rule.color = Color(S.OLD_GOLD, 0.7)
	rule.custom_minimum_size = Vector2(LOGO_RES.x * LOGO_SCALE * 0.62, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	col.add_child(spacer)
	var v := VBoxContainer.new()
	v.name = "Menu"
	v.add_theme_constant_override("separation", 2)
	col.add_child(v)
	_menu_box = v
	_button(v, "新遊戲", new_game)
	continue_button = _button(v, "繼續", continue_game)
	continue_button.disabled = not SaveSystem.exists()
	_button(v, "戰鬥沙盒", func(): _leave(SANDBOX))
	_button(v, "美術測試（PS1 風格）", func(): _leave(ART_TEST))
	if ResourceLoader.exists(CONTROLS):
		_button(v, "操作說明", open_controls)
	audio_button = _button(v, "聲音設定", open_audio_settings)
	_button(v, "離開", func(): get_tree().quit())
	_footer()
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	buttons[0].grab_focus()

func _process(delta: float) -> void:
	_fade_t += delta
	if _leaving == "":
		_fade.color.a = clampf(1.0 - _fade_t / FADE_IN, 0.0, 1.0)
	else:
		_fade.color.a = clampf(_fade_t / FADE_OUT, 0.0, 1.0)
		if _fade_t >= FADE_OUT:
			var target := _leaving
			_leaving = "-"
			if target != "-":
				get_tree().change_scene_to_file(target)

## 淡出後切換場景；淡出中忽略重複的選擇。
func _leave(scene: String) -> void:
	if _leaving != "":
		return
	_leaving = scene
	_fade_t = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP

func is_leaving() -> bool:
	return _leaving != ""

# ---------- 標題、選單外觀 ----------

## 標題字：畫在 300×92 的 SubViewport 裡，點取樣放大兩倍（像素化的骨瓷白字、乾涸紅的影子與陳舊金的英文副標）。
func _logo() -> Control:
	var c := SubViewportContainer.new()
	c.name = "Logo"
	c.stretch = true
	c.stretch_shrink = LOGO_SCALE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.custom_minimum_size = Vector2(LOGO_RES * LOGO_SCALE)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = LOGO_RES
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	c.add_child(vp)
	var font := _title_font()
	var shadow := _label("肉身聖典", font, 50, S.DRIED_RED)
	shadow.position = Vector2(3, 3)
	vp.add_child(shadow)
	var title := _label("肉身聖典", font, 50, S.BONE_WHITE)
	title.name = "Title"
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", S.SOOT_BLACK)
	vp.add_child(title)
	var sub := _label("T H E   S C R I P T U R E   O F   F L E S H", font, 11, S.OLD_GOLD)
	sub.name = "Subtitle"
	sub.position = Vector2(2, 68)
	vp.add_child(sub)
	return c

## 標題用襯線字型：優先使用系統的明體／宋體（Windows 的新細明體、macOS 的宋體），找不到時退回預設字型。
static func _title_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Noto Serif CJK TC", "Source Han Serif TC", "PMingLiU", "MingLiU", "Songti TC", "Noto Serif TC", "serif"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	return f

static func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## 左側漸層暗角，讓選單文字在 3D 畫面上清楚可讀。
func _vignette() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.035, 0.88))
	g.set_color(1, Color(0.05, 0.04, 0.035, 0.0))
	g.add_point(0.45, Color(0.05, 0.04, 0.035, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 4
	var r := TextureRect.new()
	r.name = "Vignette"
	r.texture = t
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	r.offset_right = 760
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)

func _footer() -> void:
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "滑鼠／↑↓ 選擇　Enter 確定"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(S.GREY_PINK, 0.75))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 76
	hint.offset_top = -44
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	var ch := Label.new()
	ch.name = "Chapter"
	ch.text = "序章　白色產房"
	ch.add_theme_font_size_override("font_size", 14)
	ch.add_theme_color_override("font_color", Color(S.OLD_GOLD, 0.8))
	ch.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ch.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ch.offset_left = -200
	ch.offset_right = -32
	ch.offset_top = -44
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ch)

## 平面文字按鈕：平常是骨瓷白；滑過或聚焦時變成奶油黃並在前面加上 † 記號；停用時是暗灰。
func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.set_meta(&"label", text)
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 38)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", S.BONE_WHITE.darkened(0.08))
	b.add_theme_color_override("font_hover_color", S.CREAM_YELLOW)
	b.add_theme_color_override("font_focus_color", S.CREAM_YELLOW)
	b.add_theme_color_override("font_hover_pressed_color", S.GREY_PINK)
	b.add_theme_color_override("font_pressed_color", S.GREY_PINK)
	b.add_theme_color_override("font_disabled_color", Color(S.BONE_WHITE, 0.25))
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.pressed.connect(cb)
	b.focus_entered.connect(_mark.bind(b))
	b.focus_exited.connect(_mark.bind(b))
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	parent.add_child(b)
	buttons.append(b)
	return b

func _mark(b: Button) -> void:
	b.text = (MARKER if b.has_focus() else "") + String(b.get_meta(&"label"))

func open_audio_settings() -> void:
	if audio_panel == null:
		audio_panel = AudioSettingsPanel.new()
		audio_panel.position = Vector2(72, _menu_box.get_global_rect().position.y - 8)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(S.SOOT_BLACK.darkened(0.45), 0.94)
		sb.border_color = Color(S.OLD_GOLD, 0.7)
		sb.set_border_width_all(1)
		sb.set_content_margin_all(18)
		audio_panel.add_theme_stylebox_override("panel", sb)
		audio_panel.closed.connect(func():
			_menu_box.show()
			audio_button.grab_focus())
		add_child(audio_panel)
		move_child(audio_panel, _fade.get_index())
	_menu_box.hide()
	audio_panel.show()

func open_controls() -> void:
	InputSetup.ensure_actions()  # 主選單不會先載入遊戲場景；先註冊按鍵，說明才會顯示實際的鍵位
	if controls_screen == null or not is_instance_valid(controls_screen):
		controls_screen = load(CONTROLS).new()
		add_child(controls_screen)
		if controls_screen.has_signal(&"closed"):
			controls_screen.connect(&"closed", func(): buttons[0].grab_focus())
	controls_screen.open()

func new_game() -> void:
	GameState.reset()
	GameState.start_mode = "new"
	_leave(PROLOGUE)

func continue_game() -> void:
	GameState.start_mode = "continue"
	_leave(PROLOGUE)
