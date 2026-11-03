class_name PrologueGame
extends Node3D
## 序章遊戲控制器：載入關卡、生成玩家與敵人、串接對話／祭壇存檔／Boss／死亡重生／結局。
## 由 scenes/prologue/prologue.tscn 使用。開始方式由 GameState.start_mode 決定（主選單設定）。

signal ending_reached(ending_id: String)
signal player_respawned

const LEVEL := "res://scenes/prologue/prologue_level.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const CLASS_PATH := "res://content/classes/%s.tres"
const DEATH_SECONDS := 3.0
const ENDINGS := {
	"burn": ["灰燼結局", "最後的孩子"],
	"mother": ["母親結局", "第七百三十二次分娩"],
	"escape": ["離院結局", "灰色的天空"],
}

@export var save_path: String = SaveSystem.DEFAULT_PATH
## 新遊戲開始時播放開場旁白（測試與模擬可關閉，以免對話框擋住流程）。
@export var play_opening: bool = true
## 測試用：不建立 UI 以外的視覺效果也能運作；false 時不自動在 _ready 開始（由測試呼叫 start_game）。
@export var autostart: bool = true

var level: Node3D
var player: CharacterBody3D
var boss: CharacterBody3D
var rig: CameraRig
var boss_intro: BossIntro
var mother_chase: MotherChase
var hud: CombatHud
var injury: InjuryOverlay
var hallucinations: HallucinationDirector
var dialogue: DialogueBox
var boss_bar: BossBar
var transplant: TransplantScreen
var body_menu: BodyMenu
var controls: ControlsScreen
var hints: TutorialHints
var toast: Label
var overlay_label: Label
var ending_id := ""
var _death_left := -1.0
var _toast_left := 0.0
var _ui: CanvasLayer
var _esc_armed := 0.0

func _ready() -> void:
	InputSetup.ensure_actions()
	if autostart:
		start_game(GameState.start_mode)

## mode："new" 新遊戲；"continue" 從存檔（沒有存檔時視為新遊戲）。
func start_game(mode: String) -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	var data := {}
	if mode == "continue":
		data = SaveSystem.read(save_path)
	if data.is_empty():
		GameState.reset()
	else:
		GameState.load_save(data.get("game", {}))
	_build_world()
	_spawn_player(data)
	_build_ui()
	_setup_mother_chase()
	if data.is_empty():
		# 新遊戲：赤手醒來，等阿格妮絲的對話決定職業。立即存一次，死在第一個祭壇前也能重生。
		(player.get_node("PlayerData") as PlayerData).inventory.items.clear()
		save_now()
		show_toast("白色產房")
		if play_opening:
			open_dialogue("prologue_opening")

# ---------- 世界 ----------

func _build_world() -> void:
	level = (load(LEVEL) as PackedScene).instantiate()
	add_child(level)
	# 敵人跨房間尋路用的導航網格（只從灰盒幾何烘焙，不含 Boss 大門）。
	LevelNavigation.bake(level, level.get_node("Geometry"))
	for s in get_tree().get_nodes_in_group(EnemySpawn.GROUP):
		if level.is_ancestor_of(s):
			(s as EnemySpawn).spawn(level)
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		if level.is_ancestor_of(n):
			(n as Interactable).dialogue_requested.connect(open_dialogue)
	for n in get_tree().get_nodes_in_group(AreaTrigger.GROUP):
		if level.is_ancestor_of(n):
			var t := n as AreaTrigger
			t.dialogue_requested.connect(open_dialogue)
			t.triggered.connect(func(_id, _p): if t.area_name != "": show_toast(t.area_name))
	for a in level.get_node("Altars").get_children():
		var altar := a as StitchingAltar
		altar.rested.connect(_on_altar_rested.bind(altar))
	if not GameState.has_flag(&"boss_defeated"):
		_spawn_boss()
	if not EventBus.creature_killed.is_connected(_on_creature_killed):
		EventBus.creature_killed.connect(_on_creature_killed)

func _spawn_boss() -> void:
	boss = BossFactory.create_mother()
	var m := level.get_node("Markers/BossSpawn") as Node3D
	boss.position = m.position
	boss.rotation.y = PI
	level.add_child(boss)
	set_boss_active(false)
	var bp: BossPhaseComponent = boss.get_node("BossPhase")
	bp.defeated.connect(_on_boss_defeated)
	# Boss 戰中的台詞只用字幕顯示，不暫停戰鬥。
	bp.phase_changed.connect(func(ph): if ph == 2: show_toast(boss_line(&"kneel")))
	bp.cords_severed.connect(func(): show_toast(boss_line(&"cords")))

func set_boss_active(on: bool) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var ai := boss.get_node("EnemyAI")
	ai.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	var bp: BossPhaseComponent = boss.get_node("BossPhase")
	if on:
		bp.engage()

func _on_creature_killed(victim: Node, _killer: Node) -> void:
	var b := (victim as CombatComponent).body() if victim is CombatComponent else null
	if b != null and b.has_meta(&"spawn_id"):
		GameState.killed[StringName(b.get_meta(&"spawn_id"))] = true

## Boss 戰中的字幕台詞（依劇情旗標變化）。
func boss_line(moment: StringName) -> String:
	var knows := GameState.has_flag(&"knows_mother")
	match moment:
		&"kneel":
			return "母親：「為什麼……要讓媽媽跪下……」"
		&"cords":
			return "母親：「孩子們……我聽不見孩子們了……」"
		&"defeated":
			return "母親：「……伊蓮……妳好溫暖……」" if knows else "母親：「……好冷……我的孩子們……」"
	return ""

func _on_cord_cut(left: int) -> void:
	if left > 0:
		show_toast("臍帶斷了　母親踉蹌了一下（剩 %d 條，生產變慢）" % left)
	else:
		show_toast("最後一條臍帶斷了　她再也生不出孩子")

func _on_boss_defeated() -> void:
	boss_bar.hide_boss()
	show_toast(boss_line(&"defeated"))
	save_now()

## 序章提案 E：拿到臍帶鑰匙時母親破牆追出來（只發生一次）。
func _setup_mother_chase() -> void:
	if GameState.has_flag(MotherChase.DONE_FLAG) or level.get_node_or_null("Markers/MotherChaseSpawn") == null:
		return
	mother_chase = MotherChase.new()
	mother_chase.name = "MotherChase"
	mother_chase.spawn_marker = NodePath("Markers/MotherChaseSpawn")
	add_child(mother_chase)
	mother_chase.setup(level, player)
	mother_chase.started.connect(_on_mother_chase_started)
	mother_chase.ended.connect(_on_mother_chase_ended)

func _on_mother_chase_started() -> void:
	show_toast("牆後傳來搖籃曲……她來了。逃回庭院！")

func _on_mother_chase_ended(reason: StringName) -> void:
	if reason == &"caught":
		show_toast("母親扯走了你的一條手臂，然後被臍帶拉回了牆後")
	else:
		show_toast("臍帶繃緊，把母親拉回了黑暗裡")

# ---------- 玩家 ----------

func spawn_point() -> Transform3D:
	if GameState.checkpoint_altar != &"":
		var a := level.get_node_or_null("Altars/Altar_%s" % GameState.checkpoint_altar) as Node3D
		if a != null:
			return Transform3D(Basis(), a.position + Vector3(0, 0, -1.2))
	var m := level.get_node("Markers/PlayerStart") as Node3D
	return m.transform

func _spawn_player(data: Dictionary) -> void:
	var cls := String(GameState.class_id)
	var class_path := CLASS_PATH % cls if cls != "" else PlayerFactory.DEFAULT_CLASS
	player = PlayerFactory.create([], class_path, false)
	player.transform = spawn_point()
	level.add_child(player)
	if not data.is_empty():
		SaveSystem.apply(player, data)
	(player.get_node("CombatComponent") as CombatComponent).died.connect(func(_c): _on_player_died())

func _on_player_died() -> void:
	_death_left = DEATH_SECONDS
	_show_overlay("你被收回了", "……將在最後觸碰的祭壇醒來")

## 死亡後重生：重新載入整個序章並讀取最後的存檔（未擊殺的敵人與 Boss 都會復原）。
func respawn() -> void:
	_death_left = -1.0
	for c in get_children():
		remove_child(c)
		c.queue_free()
	boss = null
	start_game("continue")
	player_respawned.emit()

func _on_altar_rested(_p: Node3D, altar: StitchingAltar) -> void:
	GameState.checkpoint_altar = altar.altar_id
	save_now()
	show_toast("身體已修復　—　已存檔")

func save_now() -> Error:
	return SaveSystem.save_game(player, save_path)

# ---------- 對話與動作 ----------

func open_dialogue(id: String, p: Node3D = null) -> void:
	if dialogue.is_open():
		return
	dialogue.open(id, p if p != null else player)

func _on_dialogue_action(action: StringName, arg: String) -> void:
	match String(action):
		"choose_class":
			if PlayerFactory.apply_class(player, CLASS_PATH % arg):
				show_toast("職業：%s" % (load(CLASS_PATH % arg) as ClassDefinition).display_name)
		"give_item":
			var parts := arg.split(":")
			var data: PlayerData = player.get_node("PlayerData")
			data.inventory.add(parts[0], int(parts[1]) if parts.size() > 1 else 1)
		"learn_skill":
			var prog: ProgressionComponent = player.get_node("ProgressionComponent")
			if prog.grant_skill(StringName(arg)):
				show_toast("習得技能：%s" % prog.skill(StringName(arg)).display_name)
		"take_item":
			var parts := arg.split(":")
			var data: PlayerData = player.get_node("PlayerData")
			data.inventory.remove(parts[0], int(parts[1]) if parts.size() > 1 else 1)
		"start_boss":
			# 對話結束後才播放登場演出（對話關閉時會恢復戰鬥時間，避免互相覆蓋）
			if dialogue.is_open():
				dialogue.closed.connect(start_boss_intro, CONNECT_ONE_SHOT)
			else:
				start_boss_intro()
		"ending":
			reach_ending(arg)
		_:
			push_warning("未處理的對話動作：%s" % action)

## Boss 登場：鏡頭演出結束後才啟動 AI。
func start_boss_intro() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	boss_bar.show_boss(boss, "行走的母親", "THE WALKING MOTHER")
	boss_intro = BossIntro.new()
	boss_intro.name = "BossIntro"
	add_child(boss_intro)
	boss_intro.finished.connect(func():
		set_boss_active(true)
		boss_intro.queue_free(), CONNECT_ONE_SHOT)
	boss_intro.start(boss, rig)

func reach_ending(id: String) -> void:
	ending_id = id
	GameState.set_flag(StringName("ending_" + id))
	var t: Array = ENDINGS.get(id, ["結局", id])
	_show_overlay("%s：%s" % [t[0], t[1]], "序章　完\n\n按 Esc 回到主選單")
	ending_reached.emit(id)

# ---------- UI ----------

func _build_ui() -> void:
	rig = CameraRig.new()
	rig.target = player
	add_child(rig)
	var ctrl: PlayerController = player.get_node("PlayerController")
	ctrl.camera = rig.camera
	hud = CombatHud.new()
	hud.player = player.get_node("CombatComponent")
	hud.controller = ctrl
	add_child(hud)
	injury = InjuryOverlay.new()
	injury.name = "InjuryOverlay"
	injury.player = player.get_node("CombatComponent")
	add_child(injury)
	hallucinations = HallucinationDirector.new()
	hallucinations.name = "Hallucinations"
	add_child(hallucinations)
	hallucinations.setup(player)
	var tac: TacticalController = player.get_node("TacticalController")
	tac.camera = rig.camera
	tac.toggled.connect(func(on): rig.in_combat = on)
	var overlay := TacticalOverlay.new()
	overlay.tactical = tac
	add_child(overlay)
	transplant = TransplantScreen.new()
	add_child(transplant)
	for a in level.get_node("Altars").get_children():
		(a as StitchingAltar).surgery_requested.connect(func(pl): transplant.open(pl))
	body_menu = BodyMenu.new()
	add_child(body_menu)
	controls = ControlsScreen.new()
	controls.name = "ControlsScreen"
	add_child(controls)
	hints = TutorialHints.new()
	hints.name = "TutorialHints"
	add_child(hints)
	hints.bind(player)
	var ai_debug := AiDebugOverlay.new()
	ai_debug.name = "AiDebugOverlay"
	add_child(ai_debug)
	dialogue = DialogueBox.new()
	hints.dialogue = dialogue
	add_child(dialogue)
	dialogue.action_requested.connect(_on_dialogue_action)
	boss_bar = BossBar.new()
	add_child(boss_bar)
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.custom_minimum_size = Vector2(600, 40)
	toast.position = Vector2(-300, 60)
	toast.add_theme_font_size_override("font_size", 24)
	toast.add_theme_color_override("font_color", Color("e8e2d6"))
	_ui.add_child(toast)
	overlay_label = Label.new()
	overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_label.add_theme_font_size_override("font_size", 30)
	overlay_label.add_theme_color_override("font_color", Color("c9a27a"))
	overlay_label.visible = false
	_ui.add_child(overlay_label)
	var data: PlayerData = player.get_node("PlayerData")
	data.message.connect(show_toast)

func show_toast(text: String) -> void:
	if toast == null:
		return
	toast.text = text
	toast.modulate.a = 1.0
	_toast_left = 2.5

func _show_overlay(title: String, sub: String) -> void:
	overlay_label.text = "%s\n\n%s" % [title, sub]
	overlay_label.visible = true

func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		toast.modulate.a = clampf(_toast_left / 0.6, 0.0, 1.0)
	_esc_armed = maxf(0.0, _esc_armed - delta)
	if _death_left > 0.0:
		_death_left -= delta
		if _death_left <= 0.0:
			respawn()

func _unhandled_input(event: InputEvent) -> void:
	if controls != null and controls.is_open():
		if event.is_action_pressed(&"pause_menu") or event.is_action_pressed(&"help"):
			controls.close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"help") and controls != null and (dialogue == null or not dialogue.is_open()):
		controls.open()
		return
	if event.is_action_pressed(&"pause_menu"):
		if dialogue != null and dialogue.is_open():
			return
		if ending_id != "" or _esc_armed > 0.0:
			_to_menu()
		else:
			_esc_armed = 2.0
			show_toast("再按一次 Esc 回到主選單（進度只保留到上次祭壇）")
	elif event.is_action_pressed(&"menu_body") and body_menu != null:
		body_menu.toggle(player)

func _to_menu() -> void:
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	if ResourceLoader.exists(MAIN_MENU):
		get_tree().change_scene_to_file(MAIN_MENU)
