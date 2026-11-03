class_name ChaseGuide
extends CanvasLayer
## 追逐戰的帶路提示（luz 試玩回饋：不知道要逃到哪裡、哪裡結束）。
## - 目標在畫面內：目標上方畫一個往下指的脈動箭頭＋文字。
## - 目標在畫面外：箭頭貼著畫面邊緣，指向目標的方向。
## - 逃脫時：畫面中央出現大字「逃脫」，幾秒後淡出。
## 位置由 PrologueGame 每格設定（target_screen / on_screen / label），這裡只負責畫。

const COLOR := Color("efe3c0")  # 奶油黃：與暗紅的壓迫感區分開
const SHADOW := Color(0, 0, 0, 0.7)
const EDGE_MARGIN := 46.0
const BANNER_SECONDS := 3.0

var active := false
var target_screen := Vector2.ZERO
var on_screen := true
var label := ""
var canvas: Control
var banner: Label
var banner_sub: Label
var _t := 0.0
var _banner_left := 0.0

func _ready() -> void:
	layer = 2  # HUD 之上
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_guide)
	add_child(canvas)
	banner = _label(64, -40.0)
	banner_sub = _label(22, 30.0)

func _label(size: int, offset_y: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", COLOR)
	l.add_theme_color_override(&"font_shadow_color", SHADOW)
	l.add_theme_constant_override(&"shadow_offset_x", 2)
	l.add_theme_constant_override(&"shadow_offset_y", 2)
	l.size = Vector2(900, 90)
	l.position = Vector2(-450, -45 + offset_y)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

## 逃脫等大字（標題＋副標），BANNER_SECONDS 秒後淡出。
func show_banner(title: String, sub: String = "") -> void:
	banner.text = title
	banner_sub.text = sub
	_banner_left = BANNER_SECONDS

func banner_visible() -> bool:
	return _banner_left > 0.0

func _process(delta: float) -> void:
	_t += delta
	if _banner_left > 0.0:
		_banner_left = maxf(0.0, _banner_left - delta)
	var a := clampf(_banner_left / 0.8, 0.0, 1.0)
	banner.modulate.a = a
	banner_sub.modulate.a = a
	canvas.queue_redraw()

## 箭頭實際畫的位置與方向（測試用）：回傳 [位置, 指向]。
func arrow_pose(view: Vector2) -> Array:
	var center := view * 0.5
	if on_screen:
		return [target_screen + Vector2(0, -36.0 - 6.0 * sin(_t * 6.0)), Vector2.DOWN]
	var dir := target_screen - center
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	dir = dir.normalized()
	# 從中心沿 dir 射到內縮 EDGE_MARGIN 的矩形邊上
	var half := center - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var tx := half.x / absf(dir.x) if absf(dir.x) > 0.001 else INF
	var ty := half.y / absf(dir.y) if absf(dir.y) > 0.001 else INF
	return [center + dir * minf(tx, ty), dir]

func _draw_guide() -> void:
	if not active:
		return
	var view := canvas.size
	var pose := arrow_pose(view)
	var pos: Vector2 = pose[0]
	var dir: Vector2 = pose[1]
	var pulse := 0.65 + 0.35 * sin(_t * 6.0)
	var col := Color(COLOR, pulse)
	var side := dir.orthogonal()
	var tip := pos + dir * 18.0
	var pts := PackedVector2Array([tip, pos - dir * 10.0 + side * 16.0, pos - dir * 2.0, pos - dir * 10.0 - side * 16.0])
	var shadow_pts := PackedVector2Array()
	for p in pts:
		shadow_pts.append(p + Vector2(2, 2))
	canvas.draw_colored_polygon(shadow_pts, SHADOW)
	canvas.draw_colored_polygon(pts, col)
	if label != "":
		var font := ThemeDB.fallback_font
		var fs := 18
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := pos - dir * 34.0 + Vector2(-w * 0.5, 6.0)
		at.x = clampf(at.x, 8.0, view.x - w - 8.0)
		at.y = clampf(at.y, 24.0, view.y - 8.0)
		canvas.draw_string(font, at + Vector2(2, 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SHADOW)
		canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
