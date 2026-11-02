class_name DamageResolver
extends RefCounted
## 損傷計算。只讀取 AnatomyState，不修改它（方便單元測試與預覽傷害）。
## 流程：護甲 → 抗性 → 部位 HP → 損傷累積 → 出血 → 異化 → 斷肢判定 → 穿刺貫穿。

static func resolve(state: AnatomyState, packet: DamagePacket, rng: RandomNumberGenerator) -> DamageResult:
	var part := state.get_part(packet.target_part_id)
	if part == null:
		return DamageResult.reject("unknown part: %s" % packet.target_part_id)
	if part.severed:
		return DamageResult.reject("part already severed: %s" % packet.target_part_id)
	if part.def.is_internal:
		return DamageResult.reject("internal part not directly targetable: %s" % packet.target_part_id)

	var result := DamageResult.new()
	result.hits.append(_hit(part, packet.amounts, packet, rng, false))

	var pierce := float(packet.amounts.get(DamageTypes.Type.PIERCE, 0.0))
	if pierce > 0.0:
		var candidates: Array[BodyPartState] = []
		for iid in part.def.internal_parts:
			var inner := state.get_part(StringName(iid))
			if inner != null and not inner.severed:
				candidates.append(inner)
		if not candidates.is_empty():
			var inner_target: BodyPartState = candidates[rng.randi_range(0, candidates.size() - 1)]
			var inner_amounts := {DamageTypes.Type.PIERCE: pierce * DamageTypes.PIERCE_PASS_THROUGH}
			result.hits.append(_hit(inner_target, inner_amounts, packet, rng, true))
	return result

static func _hit(part: BodyPartState, amounts: Dictionary, packet: DamagePacket,
		rng: RandomNumberGenerator, pass_through: bool) -> DamageResult.PartHit:
	var h := DamageResult.PartHit.new()
	h.part_id = part.id
	h.pass_through = pass_through
	var def := part.def

	# 護甲只減免物理傷害（異化不受護甲影響），依比例平均分攤到各類型。
	var physical := 0.0
	for t in amounts:
		if int(t) != DamageTypes.Type.MUTATION:
			physical += float(amounts[t])
	var armor_eff := def.armor * (1.0 - clampf(packet.armor_penetration, 0.0, 1.0))
	var armor_factor := 0.0 if physical <= 0.0 else maxf(0.0, physical - armor_eff) / physical

	var sever_score := 0.0
	for t in amounts:
		var ti := int(t)
		var raw := float(amounts[t])
		if raw <= 0.0:
			continue
		var eff := raw * def.get_resistance(ti)
		if ti != DamageTypes.Type.MUTATION:
			eff *= armor_factor
		if eff <= 0.0:
			continue
		h.injuries[ti] = float(h.injuries.get(ti, 0.0)) + eff
		h.hp_loss += eff * DamageTypes.HP_FACTOR[ti]
		h.bleed_delta += eff * DamageTypes.BLEED_FACTOR[ti] * (packet.bleed_multiplier if DamageTypes.BLEED_FACTOR[ti] > 0.0 else 1.0)
		sever_score += eff * DamageTypes.SEVER_FACTOR[ti]
		if ti == DamageTypes.Type.BURN:
			var n := DamageTypes.Type.NECROSIS
			h.injuries[n] = float(h.injuries.get(n, 0.0)) + eff * DamageTypes.BURN_TO_NECROSIS
		elif ti == DamageTypes.Type.MUTATION:
			h.mutation_delta += eff

	# 斷肢判定：斷肢分數相對部位最大 HP，乘上武器與部位倍率，部位剩餘 HP 越低越容易斷。
	if def.detachable and not pass_through and sever_score > 0.0:
		var hp_after := maxf(0.0, part.hp - h.hp_loss)
		var missing_ratio := 1.0 - hp_after / def.max_hp
		h.sever_chance = clampf(sever_score / def.max_hp * packet.sever_power * def.sever_multiplier * missing_ratio, 0.0, 1.0)
		if h.sever_chance > 0.0:
			h.severed = h.sever_chance >= 1.0 or rng.randf() < h.sever_chance
	return h
