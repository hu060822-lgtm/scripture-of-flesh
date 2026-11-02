extends Node3D
## 【測試場景】戰鬥沙盒：玩家 vs 不會動的木樁敵人（AI 在 M4）。
## WASD 移動、滑鼠瞄準、左鍵普通攻擊、右鍵特殊技（AP）、Space 閃避、Shift 防禦、
## 1/2/3 換武器、E 撿武器、F5 重置。

var _player: CharacterBody3D
var _rig: CameraRig
var _hud: CombatHud

func _ready() -> void:
	InputSetup.ensure_actions()
	Greybox.environment(self)
	Greybox.floor_plane(self, Vector3.ZERO, Vector2(24, 24))
	_reset()

func _reset() -> void:
	for c in get_children():
		if c is CharacterBody3D or c is SeveredPart or (c is RigidBody3D and c.get_meta(&"pickup", false)) or c is CameraRig or c is CombatHud:
			c.queue_free()
	_player = PlayerFactory.create()
	add_child(_player)
	_rig = CameraRig.new()
	_rig.target = _player
	add_child(_rig)
	(_player.get_node("PlayerController") as PlayerController).camera = _rig.camera
	_hud = CombatHud.new()
	_hud.player = _player.get_node("CombatComponent")
	add_child(_hud)
	var dummies := [
		["res://content/anatomy/humanoid.tres", &"dummy_humanoid", Vector3(-1.5, 0, -3)],
		["res://content/anatomy/multi_armed.tres", &"dummy_many_hands", Vector3(1.5, 0, -3)],
	]
	for d in dummies:
		var e := PlaceholderBodyBuilder.build_creature(load(d[0]), d[1])
		add_child(e)
		e.global_position = d[2]
		e.rotation.y = PI

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_reset()
