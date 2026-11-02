class_name TutorialHints
extends CanvasLayer
## 新手提示：依情境在畫面下方顯示一次性的操作提示（不打斷遊戲、不使用對話框）。
## 每個提示只出現一次，以 GameState 旗標 hint_<id> 記錄（隨存檔保存）。
## 文字中的 {action} 會換成實際按鍵（KeyNames）。

signal hint_shown(id: StringName, text: String)

const SHOW_SECONDS := 7.0
const GAP_SECONDS := 0.6
## 開場提示的延遲（讓玩家先看到「白色產房」標題）。
const INTRO_DELAY := 2.5
const COMBAT_RADIUS := 9.0
const NEAR_RADIUS := 3.5
const LOW_ST_RATIO := 0.2

const HINTS := {
	&"intro": "{move_up}{move_left}{move_down}{move_right} 移動，滑鼠決定面向。按 {help} 隨時查看操作說明。",
	&"interact": "靠近發光的東西或人按 {interact} 互動。",
	&"combat": "{attack_light} 輕攻擊、{attack_heavy} 重攻擊。看到敵人舉手預備時，按住 {block} 防禦或按 {dodge} 閃避。",
	&"tactical": "按 {tactical} 進入戰術模式：時間變慢，用 {target_prev}／{target_next} 選擇要砍的部位。砍斷手臂，牠就不能用那隻手。",
	&"injury": "你的部位受損失效了。按 {use_item} 使用縫合包修復，或按 {menu_body} 查看身體狀態。",
	&"low_st": "耐力快用完了：攻擊、防禦、閃避都要耐力。先拉開距離恢復。",
	&"altar": "縫合祭壇：按 {interact} 休息，修復全身並存檔（敵人不會重生）。",
	&"weapon": "按 {interact} 拾取武器，之後用 {weapon_1}／{weapon_2}／{weapon_3} 切換。",
	&"sever": "你砍斷了敵人的部位！牠能做的攻擊變少了。有些敵人會想把肢體縫回去。",
}

var player: Node3D
var queue: Array[StringName] = []
var current: StringName = &""
var _label: Label
var _panel: PanelContainer
var _show_left := 0.0
var _gap_left := 0.0
var _intro_left := INTRO_DELAY
var _connected := false

func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.035, 0.85)
	sb.border_color = Color("8c7a4b")
	sb.border_width_top = 2
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.custom_minimum_size = Vector2(596, 0)
	_panel.add_child(_label)
	_panel.visible = false

func bind(p: Node3D) -> void:
	player = p
	if _connected or p == null:
		return
	_connected = true
	var c: CombatComponent = p.get_node("CombatComponent")
	c.anatomy.state.part_disabled.connect(func(_id, _r): request(&"injury"))
	c.anatomy.state.part_severed.connect(func(_id, _ids): request(&"injury"))
	c.attack_landed.connect(_on_attack_landed)

static func seen(id: StringName) -> bool:
	return GameState.has_flag(StringName("hint_%s" % id))

## 要求顯示提示（已看過或已在佇列中則忽略）。
func request(id: StringName) -> void:
	if not HINTS.has(id) or seen(id) or id == current or id in queue:
		return
	queue.append(id)

static func text_of(id: StringName) -> String:
	return KeyNames.format(HINTS[id])

func _process(delta: float) -> void:
	advance(delta)

## 推進（測試直接呼叫）。用真實時間，不受戰術減速影響。
func advance(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_watch(delta)
	if current != &"":
		_show_left -= delta
		var fade := clampf(_show_left / 0.5, 0.0, 1.0)
		_panel.modulate.a = fade
		if _show_left <= 0.0:
			current = &""
			_panel.visible = false
			_gap_left = GAP_SECONDS
		return
	_gap_left -= delta
	if _gap_left <= 0.0 and not queue.is_empty():
		_show(queue.pop_front())

func _show(id: StringName) -> void:
	current = id
	GameState.set_flag(StringName("hint_%s" % id))
	_label.text = text_of(id)
	_panel.visible = true
	_panel.modulate.a = 1.0
	_panel.reset_size()
	var vp := _panel.get_viewport_rect().size
	_panel.position = Vector2((vp.x - _panel.size.x) * 0.5, vp.y - _panel.size.y - 40.0)
	_show_left = SHOW_SECONDS
	hint_shown.emit(id, _label.text)

## 情境偵測：開場、附近有敵人追擊、耐力過低、靠近祭壇／武器台。
func _watch(delta: float) -> void:
	if _intro_left > 0.0 and seen(&"intro"):
		_intro_left = 0.0  # 讀檔或重生後不必再等開場提示
	if _intro_left > 0.0:
		_intro_left -= delta
		if _intro_left > 0.0:
			return  # 開場提示之前不偵測其他情境，讓「移動／操作說明」永遠是第一個
		request(&"intro")
		request(&"interact")
	var pc: CombatComponent = player.get_node("CombatComponent")
	var pos := player.global_position
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var ai := n.get_node_or_null("EnemyAI") as EnemyAI
		if ai == null or ai.combat.is_dead() or ai.runtime.target != pc:
			continue
		if ai.state() in [&"chase", &"attack"] and (n as Node3D).global_position.distance_to(pos) <= COMBAT_RADIUS:
			request(&"combat")
			break
	if seen(&"combat") and pc.pools.st < pc.pools.max_st * LOW_ST_RATIO:
		request(&"low_st")
	for n in get_tree().get_nodes_in_group(Interactable.GROUP) + get_tree().get_nodes_in_group(StitchingAltar.GROUP):
		if not (n is Node3D) or (n as Node3D).global_position.distance_to(pos) > NEAR_RADIUS:
			continue
		if n is StitchingAltar:
			request(&"altar")
		elif n is WeaponPedestal:
			request(&"weapon")

func _on_attack_landed(target: CombatComponent, result: DamageResult) -> void:
	if target == null:
		return
	request(&"tactical")
	if result == null:
		return
	for h in result.hits:
		if h.severed:
			request(&"sever")
			return
