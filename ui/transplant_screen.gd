class_name TransplantScreen
extends CanvasLayer
## 器官移植介面（在縫合祭壇使用）。開啟時暫停戰鬥。
## 左：可移植的部位；右：適用該部位的持有器官、相容性、異化代價、排斥風險。
## 確認移植後播放 TransplantCutscene（舊部位移開、新器官降下、一針一針縫合；排斥時壞死轉暗）。

signal closed
signal transplanted(outcome: TransplantService.Outcome)

var player: Node3D
var _root: PanelContainer
var _slots: ItemList
var _organs: ItemList
var _detail: RichTextLabel
var _confirm: Button
var _flash: ColorRect
var _options := []  # 目前選中部位的 [organ, slot, prediction]
var _slot_ids: Array[StringName] = []
var rng := RandomNumberGenerator.new()
var cutscene: TransplantCutscene

func _ready() -> void:
	layer = 10
	_flash = ColorRect.new()
	_flash.color = Color(0.35, 0.03, 0.02, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	cutscene = TransplantCutscene.new()
	cutscene.name = "Cutscene"
	add_child(cutscene)
	cutscene.finished.connect(func(): _root.visible = true)
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.custom_minimum_size = Vector2(820, 460)
	_root.position = Vector2(-410, -230)
	add_child(_root)
	var v := VBoxContainer.new()
	_root.add_child(v)
	var title := Label.new()
	title.text = "器官移植　—　縫合祭壇"
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_slots = ItemList.new()
	_slots.custom_minimum_size = Vector2(220, 300)
	_slots.item_selected.connect(_on_slot_selected)
	h.add_child(_slots)
	_organs = ItemList.new()
	_organs.custom_minimum_size = Vector2(240, 300)
	_organs.item_selected.connect(_on_organ_selected)
	h.add_child(_organs)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.custom_minimum_size = Vector2(320, 300)
	h.add_child(_detail)
	var buttons := HBoxContainer.new()
	v.add_child(buttons)
	_confirm = Button.new()
	_confirm.text = "執行移植"
	_confirm.disabled = true
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)
	var close := Button.new()
	close.text = "離開"
	close.pressed.connect(close_screen)
	buttons.add_child(close)
	visible = false

func open(p: Node3D) -> void:
	player = p
	visible = true
	TimeScale.set_mode(TimeScale.Mode.PAUSE)
	_set_player_input(false)
	refresh()

func close_screen() -> void:
	visible = false
	TimeScale.set_mode(TimeScale.Mode.NORMAL)
	_set_player_input(true)
	closed.emit()

func _set_player_input(on: bool) -> void:
	if player != null and player.has_node("PlayerController"):
		(player.get_node("PlayerController") as PlayerController).input_enabled = on

## 所有可行的（器官、部位）組合。純邏輯，供測試使用。
static func options_for(p: Node3D) -> Array:
	var out := []
	var data: PlayerData = p.get_node("PlayerData")
	var combat: CombatComponent = p.get_node("CombatComponent")
	var prog: ProgressionComponent = p.get_node_or_null("ProgressionComponent")
	var mut: MutationComponent = p.get_node_or_null("MutationComponent")
	for organ in data.inventory.organs():
		for slot in organ.slots:
			var pred := TransplantService.predict(organ, StringName(slot), combat.anatomy.state, prog, mut)
			out.append([organ, StringName(slot), pred])
	return out

## 執行移植並消耗器官。
static func perform(p: Node3D, organ: OrganDefinition, slot: StringName, rng: RandomNumberGenerator) -> TransplantService.Outcome:
	var data: PlayerData = p.get_node("PlayerData")
	var combat: CombatComponent = p.get_node("CombatComponent")
	var o := TransplantService.perform(organ, slot, combat.anatomy.state,
		p.get_node_or_null("ProgressionComponent"), p.get_node_or_null("MutationComponent"), rng)
	if o.success:
		data.inventory.remove("organ:%s" % organ.id)
	return o

## 播放移植過場（介面暫時隱藏，過場結束後回來）。
func play_cutscene(organ: OrganDefinition, slot: StringName, outcome: TransplantService.Outcome) -> void:
	var anatomy: AnatomyComponent = player.get_node("AnatomyComponent")
	var st := anatomy.state.get_part(slot)
	if st == null:
		return
	var look: StringName = player.get_meta(&"model_look", &"humanoid")
	var variant: StringName = ModelSkinner.ORGAN_VARIANTS.get(organ.id, &"")
	_root.visible = false
	cutscene.play(st.def, anatomy.profile, look, variant, outcome.rejected, organ.display_name)

func refresh() -> void:
	_slots.clear()
	_organs.clear()
	_slot_ids.clear()
	_confirm.disabled = true
	var st: AnatomyState = (player.get_node("CombatComponent") as CombatComponent).anatomy.state
	var opts := options_for(player)
	for o in opts:
		if not o[1] in _slot_ids:
			_slot_ids.append(o[1])
			var part := st.get_part(o[1])
			_slots.add_item("%s　[%s]" % [part.def.display_name, AnatomyTypes.status_name(part.status())])
	_detail.text = "選擇要替換的部位。" if not opts.is_empty() else "你沒有可移植的器官。\n擊倒敵人後，靠近屍體按 E 摘取。"

func _on_slot_selected(i: int) -> void:
	_organs.clear()
	_options = options_for(player).filter(func(o): return o[1] == _slot_ids[i])
	for o in _options:
		_organs.add_item((o[0] as OrganDefinition).display_name)
	_confirm.disabled = true

func _on_organ_selected(i: int) -> void:
	var o: Array = _options[i]
	var organ: OrganDefinition = o[0]
	var pred: TransplantService.Prediction = o[2]
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % organ.display_name)
	lines.append(organ.description)
	lines.append("")
	lines.append("功能：%s" % ", ".join(organ.template.functions))
	lines.append("HP %d　護甲 %d" % [int(organ.template.max_hp), int(organ.template.armor)])
	if pred.allowed:
		lines.append("相容性：%d%%（排斥風險 %d%%）" % [roundi(pred.compatibility * 100), roundi((1.0 - pred.compatibility) * 100)])
		lines.append("異化：+%.1f（排斥時更多）" % pred.mutation)
	else:
		lines.append("[color=#8b2a20]無法移植：%s[/color]" % pred.reason)
	_detail.text = "\n".join(lines)
	_confirm.disabled = not pred.allowed
	_confirm.set_meta(&"choice", o)

func _on_confirm() -> void:
	var o: Array = _confirm.get_meta(&"choice")
	var outcome := perform(player, o[0], o[1], rng)
	play_cutscene(o[0], o[1], outcome)
	var msg := "移植完成。" if not outcome.rejected else "[color=#8b2a20]身體正在排斥新的器官……部位開始壞死。[/color]"
	refresh()
	_detail.text = "%s\n相容性 %d%%，異化 +%.1f" % [msg, roundi(outcome.compatibility * 100), outcome.mutation_added]
	transplanted.emit(outcome)
