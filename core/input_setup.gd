class_name InputSetup
extends RefCounted
## 在執行時註冊輸入動作（避免手寫 project.godot 的序列化 InputEvent）。
## 已存在的動作不會被覆蓋，玩家日後可在設定中重新綁定。

const KEYS := {
	&"move_up": [KEY_W], &"move_down": [KEY_S], &"move_left": [KEY_A], &"move_right": [KEY_D],
	&"dodge": [KEY_SPACE], &"block": [KEY_SHIFT], &"interact": [KEY_E], &"tactical": [KEY_TAB],
	&"tactical_pause": [KEY_P], &"weapon_1": [KEY_1], &"weapon_2": [KEY_2], &"weapon_3": [KEY_3],
	&"target_prev": [KEY_Q], &"target_next": [KEY_R], &"menu_body": [KEY_B], &"pause_menu": [KEY_ESCAPE],
	&"use_item": [KEY_F], &"surgery": [KEY_T], &"help": [KEY_H],
	&"throw_limb": [KEY_G],
}
const MOUSE := {
	&"attack_light": MOUSE_BUTTON_LEFT, &"attack_heavy": MOUSE_BUTTON_RIGHT,
}

static func ensure_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE[action]
		InputMap.action_add_event(action, mb)
