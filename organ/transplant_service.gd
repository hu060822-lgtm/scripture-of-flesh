class_name TransplantService
extends RefCounted
## 器官移植規則。純函式，方便測試與在 UI 中預覽。

## 排斥時，壞死量 = (1 - 相容性) × 部位最大 HP × 此係數。
const REJECTION_NECROSIS := 0.6
const REJECTION_EXTRA_MUTATION := 0.5

class Prediction:
	var allowed := true
	var reason := ""
	var compatibility := 0.0
	var mutation := 0.0

static func compatibility(organ: OrganDefinition, progression: ProgressionComponent) -> float:
	var c := organ.base_compatibility
	if organ.origin == &"mechanical":
		return 1.0
	if progression != null:
		c += progression.stats.compatibility_bonus() + progression.effect_total("compatibility")
	return clampf(c, 0.05, 1.0)

static func predict(organ: OrganDefinition, slot: StringName, state: AnatomyState,
		progression: ProgressionComponent, mutation: MutationComponent) -> Prediction:
	var p := Prediction.new()
	if not slot in organ.slots or state.get_part(slot) == null:
		p.allowed = false
		p.reason = "此器官不適用這個部位"
		return p
	var part := state.get_part(slot)
	if part.def.parent_id != &"" and state.get_part(part.def.parent_id).severed:
		p.allowed = false
		p.reason = "連接處已不存在"
		return p
	if progression != null and progression.stats.TEC < organ.min_tec:
		p.allowed = false
		p.reason = "技術不足（需要 TEC %d）" % organ.min_tec
		return p
	p.compatibility = compatibility(organ, progression)
	p.mutation = organ.mutation_cost * (1.0 - (mutation.resistance() if mutation != null else 0.0))
	return p

## 依樣板建立受體部位的新定義。
static func build_definition(organ: OrganDefinition, current: BodyPartDef) -> BodyPartDef:
	var d: BodyPartDef = organ.template.duplicate()
	d.id = current.id
	d.parent_id = current.parent_id
	d.dependencies = current.dependencies
	d.internal_parts = current.internal_parts
	d.is_internal = current.is_internal
	d.vital = current.vital
	d.bone_name = current.bone_name
	d.mesh_segment = current.mesh_segment
	d.display_name = "%s（%s）" % [current.display_name, organ.display_name]
	var fns := PackedStringArray(organ.template.functions)
	for f in current.functions:  # 保留左右手標記
		if (f == "grip_l" or f == "grip_r") and not fns.has(f):
			fns.append(f)
	d.functions = fns
	return d

class Outcome:
	var success := false
	var rejected := false
	var reason := ""
	var compatibility := 0.0
	var mutation_added := 0.0

## 執行移植。相容性擲骰失敗＝排斥：器官仍然接上，但部位累積壞死並額外異化。
static func perform(organ: OrganDefinition, slot: StringName, state: AnatomyState,
		progression: ProgressionComponent, mutation: MutationComponent, rng: RandomNumberGenerator) -> Outcome:
	var o := Outcome.new()
	var pred := predict(organ, slot, state, progression, mutation)
	if not pred.allowed:
		o.reason = pred.reason
		return o
	o.compatibility = pred.compatibility
	var def := build_definition(organ, state.get_part(slot).def)
	if not state.replace_part_definition(slot, def, organ.id):
		o.reason = "移植失敗"
		return o
	o.success = true
	var mut := organ.mutation_cost
	if rng.randf() > pred.compatibility:
		o.rejected = true
		var r := DamageResult.new()
		var h := DamageResult.PartHit.new()
		h.part_id = slot
		h.injuries[DamageTypes.Type.NECROSIS] = (1.0 - pred.compatibility) * def.max_hp * REJECTION_NECROSIS
		r.hits.append(h)
		state.apply_result(r)
		mut *= 1.0 + REJECTION_EXTRA_MUTATION
	if mutation != null:
		o.mutation_added = mutation.add(mut, "transplant")
	return o
