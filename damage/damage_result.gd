class_name DamageResult
extends RefCounted
## DamageResolver 的輸出：描述「將會發生的變化」，由 AnatomyState.apply_result 套用。

class PartHit:
	var part_id: StringName
	var hp_loss: float = 0.0
	var injuries := {}  # DamageTypes.Type -> float
	var bleed_delta: float = 0.0
	var mutation_delta: float = 0.0
	var sever_chance: float = 0.0
	var severed: bool = false
	var pass_through: bool = false  # 由穿刺貫穿造成

var rejected: bool = false
var reject_reason: String = ""
var hits: Array[PartHit] = []

static func reject(reason: String) -> DamageResult:
	var r := DamageResult.new()
	r.rejected = true
	r.reject_reason = reason
	return r

func hit_for(part_id: StringName) -> PartHit:
	for h in hits:
		if h.part_id == part_id:
			return h
	return null
