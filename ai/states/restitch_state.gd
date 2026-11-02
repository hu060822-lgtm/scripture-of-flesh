extends AiState
## 特殊行為（縫屍者）：走到殘肢旁，花時間把它縫回去。期間被打中就中斷。
## 同伴的殘肢：撿起來帶到同伴身邊再縫（序章提案 C）。帶著殘肢時被打中，殘肢會掉在地上。

## 被打斷後多久才會再嘗試縫回。
const RESTITCH_RETRY_COOLDOWN := 3.0

func enter(ai: EnemyAI) -> void:
	ai.runtime.special_target = RestitchLogic.find_limb(ai)
	ai.runtime.special_progress = 0.0
	ai.runtime.carry_owner = null
	ai.runtime.carry_part = &""
	ai.interrupted = false

func exit(ai: EnemyAI) -> void:
	_drop_carried(ai)

func update(ai: EnemyAI, delta: float) -> StringName:
	if ai.runtime.carry_owner != null:
		return _deliver(ai, delta)
	var g := ai.runtime.special_target as SeveredPart
	if g == null or not is_instance_valid(g) or g.is_queued_for_deletion():
		return &"chase"
	if ai.interrupted:
		ai.interrupted = false
		if ai.runtime.special_progress > 0.0:
			ai.runtime.special_cooldown = RESTITCH_RETRY_COOLDOWN
			return &"chase"  # 縫到一半被打斷
	var d := g.global_position.distance_to(ai.body().global_position)
	if d > RestitchLogic.REACH:
		ai.move_towards(g.global_position)
		return &""
	ai.stop()
	if g.source_creature_id != ai.anatomy.creature_id:
		# 同伴的殘肢：撿起來
		var owner := RestitchLogic.owner_of(ai, g)
		if owner == null:
			return &"chase"
		ai.runtime.carry_owner = owner
		ai.runtime.carry_part = g.part_id
		ai.runtime.special_progress = 0.0
		g.queue_free()
		ai.bark.emit(&"restitch_pickup")
		return &""
	ai.runtime.special_progress += delta
	if ai.runtime.special_progress >= RestitchLogic.CHANNEL_SECONDS:
		ai.anatomy.state.restore_part(g.part_id)
		g.queue_free()
		return &"chase"
	return &""

func _deliver(ai: EnemyAI, delta: float) -> StringName:
	var owner := ai.runtime.carry_owner
	if not is_instance_valid(owner) or owner.is_dead() or ai.combat.caps().count("grip") <= 0:
		ai.runtime.carry_owner = null
		return &"chase"
	if ai.interrupted:
		ai.interrupted = false
		ai.runtime.special_cooldown = RESTITCH_RETRY_COOLDOWN
		return &"chase"  # exit() 會把殘肢丟在地上
	var to := owner.body().global_position - ai.body().global_position
	to.y = 0
	if to.length() > RestitchLogic.ALLY_REACH:
		ai.runtime.special_progress = 0.0
		ai.move_towards(owner.body().global_position)
		return &""
	ai.stop()
	ai.face(owner.body().global_position)
	ai.runtime.special_progress += delta
	if ai.runtime.special_progress >= RestitchLogic.CHANNEL_SECONDS:
		owner.anatomy.state.restore_part(ai.runtime.carry_part)
		ai.runtime.carry_owner = null
		ai.runtime.carry_part = &""
		ai.bark.emit(&"restitch_ally")
		return &"chase"
	return &""

## 帶著同伴的殘肢時離開這個狀態（被打斷、死亡）：殘肢掉回地上（仍可被撿走或再被縫回）。
func _drop_carried(ai: EnemyAI) -> void:
	if ai.runtime.carry_owner == null:
		return
	var owner := ai.runtime.carry_owner
	var part := ai.runtime.carry_part
	ai.runtime.carry_owner = null
	ai.runtime.carry_part = &""
	if not is_instance_valid(owner) or not ai.body().is_inside_tree():
		return
	var vis := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.07
	cap.height = 0.6
	vis.mesh = cap
	var gib := SeveredPart.spawn(ai.body().get_parent(), vis, ai.body().global_transform.translated(Vector3.UP * 0.8), part,
		owner.anatomy.creature_id, Vector3.UP)
	if owner.anatomy.profile != null:
		LimbRelic.attach_if_relic(gib, owner.anatomy.profile.id, part)
