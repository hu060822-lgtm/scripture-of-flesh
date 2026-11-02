class_name TacticalOverlay
extends CanvasLayer
## 戰術介面 UI：目標的部位清單（HP、狀態、護甲）、指定部位的預估傷害與斷肢機率、
## AP 消耗、時間模式。並在 3D 場景中標示指定的部位。

var tactical: TacticalController
var _panel: PanelContainer
var _label: RichTextLabel
var _tint: ColorRect
var _marker: MeshInstance3D

func _ready() -> void:
	_tint = ColorRect.new()
	_tint.color = Color(0.35, 0.05, 0.03, 0.12)  # 乾涸紅薄霧
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint)
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -380
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(360, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.09
	torus.outer_radius = 0.12
	_marker.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c9a227")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_marker.material_override = mat
	_marker.visible = false

func _process(_delta: float) -> void:
	if tactical == null or not is_instance_valid(tactical):
		return
	if _marker.get_parent() == null and tactical.controller != null:
		tactical.controller.body().get_parent().add_child(_marker)
	var c := tactical.controller
	var target := c.tactical_target
	var part := c.targeted_part()
	_tint.visible = tactical.active
	_panel.visible = tactical.active or part != &""
	_update_marker(target, part)
	if not _panel.visible:
		return
	_label.text = text_for(tactical)

func _update_marker(target: CombatComponent, part: StringName) -> void:
	if target == null or part == &"" or not is_instance_valid(target):
		_marker.visible = false
		return
	var ctrl: DismembermentController = target.body().get_node_or_null("DismembermentController")
	var hb := ctrl.hurtbox_for(part) if ctrl != null else null
	_marker.visible = hb != null and hb.active
	if _marker.visible:
		_marker.global_position = hb.global_position
		_marker.look_at(_marker.global_position + Vector3.UP, Vector3.FORWARD)

## 純文字產生（可測試）。
static func text_for(tac: TacticalController) -> String:
	var c := tac.controller
	var lines := PackedStringArray()
	var mode := "減速 10%" if TimeScale.mode == TimeScale.Mode.SLOW else ("暫停" if TimeScale.mode == TimeScale.Mode.PAUSE else "即時")
	lines.append("[b]戰術介面[/b]　%s　（Tab 關閉，P 暫停）" % mode if tac.active else "[b]部位鎖定中[/b]　（Tab 開啟戰術介面）")
	var target := c.tactical_target
	if target == null or target.is_dead():
		lines.append("沒有目標")
		return "\n".join(lines)
	lines.append("目標：%s" % target.body().name)
	var st := target.anatomy.state
	var selected := c.targeted_part()
	for pid in st.targetable_part_ids():
		var p := st.get_part(pid)
		var mark := "▶ " if pid == selected else "　"
		var color := _status_color(p.status())
		lines.append("%s[color=%s]%s　%d/%d　%s%s[/color]" % [mark, color, p.def.display_name, ceili(p.hp), int(p.def.max_hp),
			AnatomyTypes.status_name(p.status()), ("　甲%d" % int(p.def.armor)) if p.def.armor > 0 else ""])
	# 異化「異樣感知」：看見內臟狀態與敵人剩餘的攻擊手段
	var mut: MutationComponent = c.body().get_node_or_null("MutationComponent")
	if mut != null and mut.has_effect("anatomical_sight"):
		for pid in st.part_ids():
			var ip := st.get_part(pid)
			if ip.def.is_internal:
				lines.append("　[color=#7a8c4b]（內臟）%s　%d/%d　%s[/color]" % [ip.def.display_name, ceili(ip.hp), int(ip.def.max_hp), AnatomyTypes.status_name(ip.status())])
		var names := PackedStringArray()
		for a in target.available_attacks():
			names.append(a.display_name)
		lines.append("[color=#7a8c4b]剩餘攻擊手段：%s[/color]" % ("、".join(names) if not names.is_empty() else "無"))
	var pv := tac.preview_light()
	if pv != null and not pv.rejected:
		var h := pv.hits[0]
		var extra := ""
		if pv.hits.size() > 1:
			extra = "，貫穿 %s" % st.get_part(pv.hits[1].part_id).def.display_name
		lines.append("預估（普通攻擊）：部位 -%.1f HP，斷肢機率 %d%%%s" % [h.hp_loss, roundi(h.sever_chance * 100.0), extra])
	var ap_ok := c.combat.pools.ap >= PlayerController.TARGETED_AP_COST
	lines.append("指定部位攻擊每次消耗 %d AP（目前 %d）%s" % [int(PlayerController.TARGETED_AP_COST), int(c.combat.pools.ap), "" if ap_ok else "　[color=#8b2a20]AP 不足：將自動選擇部位[/color]"])
	lines.append("點擊部位或 Q／R 切換")
	return "\n".join(lines)

static func _status_color(s: int) -> String:
	match s:
		AnatomyTypes.PartStatus.INTACT: return "#e8e2d6"
		AnatomyTypes.PartStatus.DAMAGED: return "#c9b78f"
		AnatomyTypes.PartStatus.SEVERELY_DAMAGED: return "#c0703a"
		AnatomyTypes.PartStatus.DISABLED: return "#8b2a20"
		AnatomyTypes.PartStatus.MUTATED: return "#7a8c4b"
		_: return "#777777"
