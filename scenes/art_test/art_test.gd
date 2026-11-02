extends Control
## 【美術測試場景】PS1 復古恐怖／低多邊形哥德身體恐怖的方向確認用。可實際遊玩。
## 內容：低多邊形玩家、低多邊形人形敵人（縫屍者）、可斷的組合式手臂、特殊解剖怪物（無面觀察者，眼柄為發光弱點）、
## 哥德式手術室、固定鏡頭戰鬥。
## 操作同戰鬥沙盒。F1 PS1 效果開關（對照）、F2 切換解析度 240p/360p/480p、F3 抖色開關、F4 頂點抖動開關、
## F5 重置、F6 敵人 AI 開關、Esc 回主選單。

const S := preload("res://art/ps1/ps1_style.gd")

var screen: RetroScreen
var camera: FixedCamera
var player: CharacterBody3D
var enemies: Array[CharacterBody3D] = []
var hud: CombatHud
var _info: Label
var _ai_enabled := true

func _ready() -> void:
	InputSetup.ensure_actions()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	screen = RetroScreen.new()
	add_child(screen)
	_info = Label.new()
	_info.position = Vector2(16, -36)
	_info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info.add_theme_font_size_override("font_size", 13)
	_info.modulate = Color(1, 1, 1, 0.7)
	var info_layer := CanvasLayer.new()
	info_layer.layer = 5
	add_child(info_layer)
	info_layer.add_child(_info)
	reset()

func reset() -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	for c in screen.world.get_children():
		screen.world.remove_child(c)
		c.queue_free()
	if hud != null:
		hud.queue_free()
	enemies.clear()
	var w := screen.world
	GothicOperatingRoom.environment(w)
	GothicOperatingRoom.build(w)
	# 外觀由工廠套用（CreatureModels）：玩家煤灰黑兜帽外衣、縫屍者的縫線皮膚與皮圍裙、
	# 無面觀察者的骨瓷白法衣與發光眼柄（弱點）
	player = PlayerFactory.create(["res://content/weapons/bone_saw_cleaver.tres"], PlayerFactory.DEFAULT_CLASS)
	_finish_creature(player, Vector3(0.3, 0, 2.6), 0.0)
	var stitcher := EnemyFactory.create(load("res://content/enemies/stitcher.tres"), &"stitcher")
	_finish_creature(stitcher, Vector3(-2.0, 0, 1.5), PI)
	enemies.append(stitcher)
	var watcher := EnemyFactory.create(load("res://content/enemies/faceless_watcher.tres"), &"watcher")
	_finish_creature(watcher, Vector3(2.8, 0, -3.5), PI)
	enemies.append(watcher)
	for e in enemies:
		_set_ai(e, _ai_enabled)
	# 固定鏡頭：從南側高處斜俯視整個手術室，只在小角度內追蹤玩家
	camera = FixedCamera.new()
	camera.fov = 48.0
	camera.position = Vector3(0, 6.2, 9.0)
	camera.target = player
	camera.max_track_degrees = 8.0
	w.add_child(camera)
	camera.look_at(Vector3(0, 1.0, -2.5))
	camera._base_basis = camera.global_transform.basis
	camera.current = true
	var ctrl: PlayerController = player.get_node("PlayerController")
	ctrl.camera = camera
	(player.get_node("TacticalController") as TacticalController).camera = camera
	hud = CombatHud.new()
	hud.player = player.get_node("CombatComponent")
	hud.controller = ctrl
	add_child(hud)

func _finish_creature(c: CharacterBody3D, pos: Vector3, yaw: float) -> void:
	c.position = pos
	c.rotation.y = yaw
	screen.world.add_child(c)

func _set_ai(e: Node, on: bool) -> void:
	var ai := e.get_node_or_null("EnemyAI")
	if ai != null:
		ai.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _process(_delta: float) -> void:
	_info.text = "【美術測試】%s　｜　F1 效果　F2 解析度　F3 抖色　F4 頂點抖動　F5 重置　F6 AI（%s）" % [screen.describe(), "開" if _ai_enabled else "關"]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F1: screen.toggle_effects()
		KEY_F2: screen.cycle_resolution()
		KEY_F3: screen.toggle_dither()
		KEY_F4: screen.toggle_jitter()
		KEY_F5: reset()
		KEY_F6:
			_ai_enabled = not _ai_enabled
			for e in enemies:
				if is_instance_valid(e):
					_set_ai(e, _ai_enabled)
		KEY_ESCAPE:
			if ResourceLoader.exists("res://scenes/main_menu.tscn"):
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
