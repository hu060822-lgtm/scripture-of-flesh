class_name BodyMenu
extends CanvasLayer
## 身體選單（B）：屬性分配、技能樹、異化、部位狀態、物品。開啟時暫停戰鬥。

var player: Node3D
var _label: RichTextLabel
var _stats_box: HBoxContainer
var _skills_box: VBoxContainer

func _ready() -> void:
	layer = 9
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 520)
	panel.position = Vector2(-380, -260)
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	_stats_box = HBoxContainer.new()
	v.add_child(_stats_box)
	var h := HBoxContainer.new()
	v.add_child(h)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.custom_minimum_size = Vector2(420, 440)
	h.add_child(_label)
	_skills_box = VBoxContainer.new()
	_skills_box.custom_minimum_size = Vector2(300, 440)
	h.add_child(_skills_box)
	visible = false

func toggle(p: Node3D) -> void:
	player = p
	visible = not visible
	TimeScale.set_mode(TimeScale.Mode.PAUSE if visible else TimeScale.Mode.NORMAL)
	(p.get_node("PlayerController") as PlayerController).input_enabled = not visible
	if visible:
		refresh()

func refresh() -> void:
	var prog: ProgressionComponent = player.get_node("ProgressionComponent")
	for c in _stats_box.get_children():
		c.queue_free()
	for n in CharacterStats.NAMES:
		var b := Button.new()
		b.text = "%s %d%s" % [n, prog.stats.get_stat(n), "  +" if prog.stat_points > 0 else ""]
		b.disabled = prog.stat_points <= 0
		b.pressed.connect(func(): prog.allocate_stat(n); refresh())
		_stats_box.add_child(b)
	for c in _skills_box.get_children():
		c.queue_free()
	var t := Label.new()
	t.text = "技能（點數 %d）" % prog.skill_points
	_skills_box.add_child(t)
	for s in prog.all_skills():
		var b := Button.new()
		var owned: bool = s.id in prog.unlocked
		b.text = ("✓ " if owned else "") + "%s：%s" % [s.display_name, s.description]
		b.disabled = owned or not prog.can_unlock(s.id)
		b.pressed.connect(func(): prog.unlock_skill(s.id); refresh())
		_skills_box.add_child(b)
	_label.text = text_for(player)

static func text_for(p: Node3D) -> String:
	var prog: ProgressionComponent = p.get_node("ProgressionComponent")
	var mut: MutationComponent = p.get_node("MutationComponent")
	var data: PlayerData = p.get_node("PlayerData")
	var combat: CombatComponent = p.get_node("CombatComponent")
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]　Lv %d（經驗 %d/%d，屬性點 %d）" % [prog.class_definition.display_name if prog.class_definition else "空白者", prog.level, prog.xp, ProgressionComponent.XP_PER_LEVEL * prog.level, prog.stat_points])
	var stage := mut.current_stage()
	lines.append("異化 %d／100　%s" % [int(mut.value), ("【%s】" % stage.display_name) if stage != null else ""])
	if stage != null:
		lines.append("[i]%s[/i]" % stage.description)
	lines.append("")
	lines.append("[b]身體[/b]")
	var st := combat.anatomy.state
	for pid in st.part_ids():
		var part := st.get_part(pid)
		var organ: String = (" ← %s" % OrganRegistry.get_organ(st.organs[pid]).display_name) if st.organs.has(pid) else ""
		lines.append("%s　%d/%d　%s%s" % [part.def.display_name, ceili(part.hp), int(part.def.max_hp), AnatomyTypes.status_name(part.status()), organ])
	lines.append("")
	lines.append("[b]物品[/b]")
	for k in data.inventory.items:
		lines.append("%s ×%d" % [Inventory.display_name(String(k)), data.inventory.items[k]])
	var profs := PackedStringArray()
	for wt in prog.proficiency:
		profs.append("%s Lv%d" % [wt, prog.proficiency_level(wt)])
	if not profs.is_empty():
		lines.append("")
		lines.append("武器熟練度：" + "、".join(profs))
	return "\n".join(lines)
