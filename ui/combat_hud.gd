class_name CombatHud
extends CanvasLayer
## 戰鬥 HUD：HP／ST／AP、異常狀態圖標列、人體剪影（自身傷殘部位）、武器與可用攻擊。

var player: CombatComponent
var controller: PlayerController
var _hp: ProgressBar
var _st: ProgressBar
var _ap: ProgressBar
var _info: Label
var status_bar: StatusIconBar
var body_doll: BodyDoll

func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	box.custom_minimum_size = Vector2(320, 0)
	add_child(box)
	_hp = _bar(box, "HP", Color("8b2a20"))
	_st = _bar(box, "ST", Color("b9b09a"))
	_ap = _bar(box, "AP", Color("8c7a4b"))
	status_bar = StatusIconBar.new()
	status_bar.name = "StatusIcons"
	box.add_child(status_bar)
	body_doll = BodyDoll.new()
	body_doll.name = "BodyDoll"
	body_doll.position = Vector2(16 + 320 + 20, 20)
	add_child(body_doll)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	box.add_child(_info)

func _bar(parent: Node, label: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(32, 0)
	row.add_child(l)
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(260, 16)
	b.show_percentage = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	b.add_theme_stylebox_override("fill", sb)
	row.add_child(b)
	parent.add_child(row)
	return b

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var p := player.pools
	_hp.max_value = p.max_hp; _hp.value = p.hp
	_st.max_value = p.max_st; _st.value = p.st
	_ap.max_value = p.max_ap; _ap.value = p.ap
	var w := player.weapon()
	var lines := PackedStringArray()
	lines.append("武器：%s" % (w.display_name if w != null else "（無）"))
	var names := PackedStringArray()
	for a in player.available_attacks():
		names.append(a.display_name + ("（AP %d）" % a.ap_cost if a.ap_cost > 0 else ""))
	lines.append("可用攻擊：" + "、".join(names))
	# 異常狀態與傷殘部位改由圖標列與人體剪影顯示
	var st := player.anatomy.state
	status_bar.set_effects(StatusEffects.collect(player))
	body_doll.anatomy = st
	var mut: MutationComponent = player.body().get_node_or_null("MutationComponent")
	if mut != null:
		lines.append("異化 %d" % int(mut.value))
	var data: PlayerData = player.body().get_node_or_null("PlayerData")
	if data != null:
		lines.append("縫合包 ×%d（F：縫合／止血）" % data.inventory.count("suture_kit"))
	if controller != null:
		var it := Interactable.nearest(controller.get_tree(), player.body())
		if it != null:
			lines.append(it.prompt())
		var altar := controller.nearest_altar()
		if altar != null:
			lines.append(altar.prompt())
	if player.is_dead():
		lines.append("【死亡】")
	_info.text = "\n".join(lines)
