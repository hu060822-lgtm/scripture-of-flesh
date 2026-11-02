class_name ControlsScreen
extends CanvasLayer
## 操作說明畫面：遊戲中按 {help}（預設 H）開關，開啟時暫停戰鬥。
## 按鍵名稱即時從 InputMap 讀取（KeyNames），不會和實際鍵位不一致。
## 主選單也可以 new() 一個加進場景、呼叫 open() 來顯示。

signal closed

## [分類, [[動作或固定文字, 說明], ...]]。動作以 & 開頭的 StringName 表示，其餘是固定按鍵文字。
const SECTIONS := [
	["移動", [
		[[&"move_up", &"move_left", &"move_down", &"move_right"], "移動"],
		["滑鼠", "瞄準方向（角色面向游標）"],
		[&"dodge", "閃避翻滾（消耗耐力，翻滾初段無敵）"],
		[&"interact", "互動：對話、拾取、祭壇"],
	]],
	["戰鬥", [
		[&"attack_light", "輕攻擊"],
		[&"attack_heavy", "重攻擊（消耗 AP，命中累積 AP）"],
		[&"block", "按住防禦（只擋正面，消耗耐力）"],
		[[&"weapon_1", &"weapon_2", &"weapon_3"], "切換武器"],
	]],
	["戰術（瞄準部位）", [
		[&"tactical", "戰術模式：時間變慢，可以選擇要砍的部位"],
		[[&"target_prev", &"target_next"], "切換目標部位"],
		[&"tactical_pause", "戰術模式中完全暫停"],
	]],
	["身體", [
		[&"use_item", "使用縫合包，修復失效的部位（會異化）"],
		[&"menu_body", "身體選單：部位狀態、屬性、技能"],
		[&"surgery", "在祭壇進行器官移植"],
		[&"help", "開關這個操作說明"],
		[&"pause_menu", "連按兩次回主選單"],
	]],
]

const TIPS := [
	"敵人出招前會有預備動作，看準時機防禦或閃避。",
	"斷掉敵人的手臂，牠就不能用那隻手攻擊；斷腿會讓牠爬行。",
	"你的部位也會受損失效。在縫合祭壇休息可以完全修復並存檔。",
	"敵人會聽聲音：打鬥聲會引來附近的怪物。",
]

var _panel: PanelContainer
var _cols: Array[RichTextLabel] = []
var _footer: RichTextLabel
var _paused_by_me := false

func _ready() -> void:
	layer = 50
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(760, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.035, 0.96)
	sb.border_color = Color("8c7a4b")
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	for i in 2:
		var col := _rich(356)
		row.add_child(col)
		_cols.append(col)
	_footer = _rich(736)
	v.add_child(_footer)
	visible = false

func _rich(width: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(width, 0)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 15)
	return r

func is_open() -> bool:
	return visible

func open() -> void:
	var half := SECTIONS.size() / 2
	_cols[0].text = "[b]操作說明[/b]\n" + section_text(SECTIONS.slice(0, half))
	_cols[1].text = "\n" + section_text(SECTIONS.slice(half))
	_footer.text = footer_text()
	visible = true
	_center()
	_center.call_deferred()  # 內容高度在下一個 frame 才確定
	if TimeScale.mode == TimeScale.Mode.NORMAL:
		TimeScale.set_mode(TimeScale.Mode.PAUSE)
		_paused_by_me = true

func _center() -> void:
	_panel.reset_size()
	_panel.position = (_panel.get_viewport_rect().size - _panel.size) * 0.5

func close() -> void:
	if not visible:
		return
	visible = false
	if _paused_by_me:
		TimeScale.set_mode(TimeScale.Mode.NORMAL)
		_paused_by_me = false
	closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"help") or event.is_action_pressed(&"pause_menu") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## 完整說明文字（BBCode），測試直接檢查。畫面上分成兩欄＋底部提示。
static func build_text() -> String:
	return "[b]操作說明[/b]\n" + section_text(SECTIONS) + "\n" + footer_text()

static func section_text(sections: Array) -> String:
	var lines := PackedStringArray()
	for sec in sections:
		lines.append("[color=#c9b27a][b]%s[/b][/color]" % sec[0])
		for row in sec[1]:
			lines.append("  [b]%s[/b]　%s" % [keys_text(row[0]), row[1]])
		lines.append("")
	return "\n".join(lines)

static func footer_text() -> String:
	var lines := PackedStringArray()
	lines.append("[color=#c9b27a][b]提示[/b][/color]")
	for t in TIPS:
		lines.append("  ・%s" % t)
	lines.append("[right][color=#8a8070]按 %s 或 Esc 關閉[/color][/right]" % KeyNames.of(&"help"))
	return "\n".join(lines)

static func keys_text(k) -> String:
	if k is StringName:
		return KeyNames.of(k)
	if k is Array:
		var parts := PackedStringArray()
		for a in k:
			parts.append(KeyNames.of(a))
		return " ".join(parts)
	return str(k)
