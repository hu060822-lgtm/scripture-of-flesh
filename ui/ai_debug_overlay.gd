class_name AiDebugOverlay
extends Node
## 敵人 AI 除錯顯示（F9 切換，預設關閉；F1–F6 已被美術測試場景使用）：在每隻敵人頭上顯示 狀態／意圖／是否持有攻擊令牌／移動方式，
## Boss 另顯示階段、連段與狂暴。方便實際遊玩時調整戰術係數。不影響遊戲邏輯。

const KEY := KEY_F9

var visible := false
var _labels := {}  # EnemyAI instance_id -> Label3D

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY:
		toggle()

func toggle() -> void:
	visible = not visible
	if not visible:
		for k in _labels:
			var l = _labels[k]
			if is_instance_valid(l):
				l.queue_free()
		_labels.clear()

func _process(_delta: float) -> void:
	if visible:
		refresh()

func refresh() -> void:
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var ai := n.get_node_or_null("EnemyAI") as EnemyAI
		if ai == null:
			continue
		var key := ai.get_instance_id()
		var label: Label3D = _labels.get(key)
		if label == null or not is_instance_valid(label):
			label = Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.pixel_size = 0.004
			label.font_size = 28
			label.outline_size = 6
			label.position = Vector3.UP * (ai.definition.collision_height + 0.4)
			ai.body().add_child(label)
			_labels[key] = label
		label.text = describe(ai)

static func describe(ai: EnemyAI) -> String:
	var t := ai.runtime.target
	var lines := ["%s  %s" % [ai.state(), ai.runtime.intent]]
	var extra := []
	if t != null and AttackTokens.has(ai, t):
		extra.append("TOKEN")
	extra.append(String(ai.locomotion_mode))
	if t != null:
		extra.append("%.1fm" % ai.distance_to(t))
	lines.append(" ".join(extra))
	var bp := ai.body().get_node_or_null("BossPhase") as BossPhaseComponent
	if bp != null:
		lines.append("P%d combo:%s%s" % [bp.phase, ",".join(bp.combo_queue.map(func(x): return String(x))), " ENRAGED" if bp.is_enraged() else ""])
	return "\n".join(lines)
