class_name CombatHud
extends CanvasLayer
## 戰鬥 HUD：HP／ST／AP、武器、可用攻擊、自身受損部位。

var player: CombatComponent
var controller: PlayerController
var _hp: ProgressBar
var _st: ProgressBar
var _ap: ProgressBar
var _info: Label

func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	box.custom_minimum_size = Vector2(320, 0)
	add_child(box)
	_hp = _bar(box, "HP", Color("8b2a20"))
	_st = _bar(box, "ST", Color("b9b09a"))
	_ap = _bar(box, "AP", Color("8c7a4b"))
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
	var hurt := PackedStringArray()
	var st := player.anatomy.state
	for pid in st.part_ids():
		var s := st.status_of(pid)
		if s != AnatomyTypes.PartStatus.INTACT:
			hurt.append("%s:%s" % [st.get_part(pid).def.display_name, AnatomyTypes.status_name(s)])
	if not hurt.is_empty():
		lines.append("受損：" + "、".join(hurt))
	if st.total_bleed_rate() > 0.0:
		lines.append("出血 %.1f/s" % st.total_bleed_rate())
	if player.vital_timer >= 0.0:
		lines.append("窒息倒數 %.1f 秒" % player.vital_timer)
	var mut: MutationComponent = player.body().get_node_or_null("MutationComponent")
	if mut != null:
		var stage := mut.current_stage()
		lines.append("異化 %d%s" % [int(mut.value), ("　【%s】" % stage.display_name) if stage != null else ""])
	var data: PlayerData = player.body().get_node_or_null("PlayerData")
	if data != null:
		lines.append("縫合包 ×%d（F）" % data.inventory.count("suture_kit"))
		if data.is_suturing():
			lines.append("縫合中：%s……" % st.get_part(data.suturing_part).def.display_name)
	if controller != null:
		var altar := controller.nearest_altar()
		if altar != null:
			lines.append(altar.prompt())
	if player.is_dead():
		lines.append("【死亡】")
	_info.text = "\n".join(lines)
