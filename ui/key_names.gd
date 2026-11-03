class_name KeyNames
extends RefCounted
## 從目前的 InputMap 讀出動作綁定的按鍵名稱，讓操作說明與提示永遠和實際鍵位一致（之後改鍵也不會寫錯）。

const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "滑鼠左鍵",
	MOUSE_BUTTON_RIGHT: "滑鼠右鍵",
	MOUSE_BUTTON_MIDDLE: "滑鼠中鍵",
}
const KEY_NAMES := {
	KEY_SPACE: "空白鍵", KEY_SHIFT: "Shift", KEY_TAB: "Tab", KEY_ESCAPE: "Esc",
}

## 動作的按鍵名稱（多個以「／」連接）。沒有綁定時回傳「未設定」。
static func of(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "未設定"
	var names := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		var n := event_name(ev)
		if n != "" and not n in names:
			names.append(n)
	return "／".join(names) if not names.is_empty() else "未設定"

static func event_name(ev: InputEvent) -> String:
	if ev is InputEventMouseButton:
		return MOUSE_NAMES.get(ev.button_index, "滑鼠按鍵 %d" % ev.button_index)
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		if KEY_NAMES.has(code):
			return KEY_NAMES[code]
		return OS.get_keycode_string(code)
	return ""

## 把文字中的 {action} 換成按鍵名稱，例如 "{dodge} 閃避" → "空白鍵 閃避"。
static func format(text: String) -> String:
	var out := text
	var re := RegEx.new()
	re.compile("\\{([a-z_0-9]+)\\}")
	for m in re.search_all(text):
		out = out.replace(m.get_string(), of(StringName(m.get_string(1))))
	return out
