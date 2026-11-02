extends Node3D
## 【測試場景】戰鬥沙盒：玩家 vs 四種敵人（縫屍者、反足者、無面觀察者、多手人）。
## WASD 移動、滑鼠瞄準、左鍵普通攻擊、右鍵特殊技（AP）、Space 閃避、Shift 防禦、
## 1/2/3 換武器、E 撿武器／祭壇休息／摘取屍體器官、F 緊急縫合、T 在祭壇移植器官、B 身體選單、
## Tab 戰術介面（減速 10%，P 暫停，點擊部位或 Q/R 指定）、F5 重置。F6 切換「敵人 AI 開／關」（關掉時敵人變成木樁）。

var _ai_enabled := true
var _body_menu: BodyMenu

var _player: CharacterBody3D
var _rig: CameraRig
var _hud: CombatHud

func _ready() -> void:
	InputSetup.ensure_actions()
	Greybox.environment(self)
	Greybox.floor_plane(self, Vector3.ZERO, Vector2(24, 24))
	_reset()

func _reset() -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	for c in get_children():
		if c is CharacterBody3D or c is SeveredPart or (c is RigidBody3D and c.get_meta(&"pickup", false)) or c is CameraRig or c is CanvasLayer or c is MeshInstance3D or c is StitchingAltar:
			c.queue_free()
	_player = PlayerFactory.create()
	add_child(_player)
	_rig = CameraRig.new()
	_rig.target = _player
	add_child(_rig)
	(_player.get_node("PlayerController") as PlayerController).camera = _rig.camera
	_hud = CombatHud.new()
	_hud.player = _player.get_node("CombatComponent")
	_hud.controller = _player.get_node("PlayerController")
	add_child(_hud)
	var tac: TacticalController = _player.get_node("TacticalController")
	tac.camera = _rig.camera
	tac.toggled.connect(func(on): _rig.in_combat = on)
	var overlay := TacticalOverlay.new()
	overlay.tactical = tac
	add_child(overlay)
	var altar := StitchingAltar.new()
	altar.position = Vector3(0, 0, 4)
	add_child(altar)
	var transplant := TransplantScreen.new()
	add_child(transplant)
	altar.surgery_requested.connect(func(pl): transplant.open(pl))
	_body_menu = BodyMenu.new()
	add_child(_body_menu)
	var enemies := [
		["stitcher", Vector3(-4, 0, -6)],
		["reverse_legged", Vector3(4, 0, -9)],
		["faceless_watcher", Vector3(0, 0, -11)],
		["many_hands", Vector3(-1, 0, -5)],
	]
	for d in enemies:
		var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % d[0]), StringName(d[0]))
		e.position = d[1]  # 先設定位置再加入場景，避免生成時與玩家重疊被物理推開
		e.rotation.y = PI
		add_child(e)
		_set_ai(e, _ai_enabled)

func _set_ai(e: Node, on: bool) -> void:
	var ai := e.get_node_or_null("EnemyAI")
	if ai != null:
		ai.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_reset()
	elif event.is_action_pressed(&"menu_body") and _body_menu != null:
		_body_menu.toggle(_player)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_ai_enabled = not _ai_enabled
		for c in get_children():
			_set_ai(c, _ai_enabled)
