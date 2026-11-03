class_name AnatomyState
extends RefCounted
## 一個生物的身體即時狀態。玩家、一般敵人、NPC、精英、Boss 共用。
## 這是純資料物件：不依賴場景，表現層（DismembermentController、動畫、AI）透過 signal 反應。

## 部位受到傷害。hit 為 DamageResult.PartHit。
signal part_damaged(part_id: StringName, hit: DamageResult.PartHit)
signal part_status_changed(part_id: StringName, old_status: int, new_status: int)
## 部位從可運作變成功能失效（未斷離）。reason: "hp" / "fracture" / "dependency"
signal part_disabled(part_id: StringName, reason: String)
## 部位斷離。severed_ids 包含此部位與所有連帶斷離的子部位。
signal part_severed(part_id: StringName, severed_ids: PackedStringArray)
signal part_restored(part_id: StringName)
## 部位的定義被替換（器官移植、義肢）。
signal part_replaced(part_id: StringName, organ_id: StringName)
signal capabilities_changed(caps: CapabilitySet)
## 致命部位失效。rule 為 BodyPartDef.VitalRule。
signal vital_failed(part_id: StringName, rule: int)
signal died(cause_part_id: StringName)

const SAVE_VERSION := 1
## 斷離時，父部位斷面增加的出血速率 = 斷離部位最大 HP × 此係數。
const STUMP_BLEED_RATIO := 0.05
## 出血速率低於此值時視為止住。
const BLEED_STOP_RATE := 0.03
const LN2 := 0.6931471805599453

## 自然凝血：出血速率的半衰期（秒）。0 = 不會自己止血（純資料測試的預設）。
## CombatComponent 依角色設定（玩家較快、敵人較慢，讓流血武器仍然有用）。
var bleed_half_life: float = 0.0

var profile: AnatomyProfile
var is_dead: bool = false
var _parts := {}            # StringName -> BodyPartState
var _order: Array[StringName] = []
var _children := {}         # StringName -> Array[StringName]
var _caps: CapabilitySet = CapabilitySet.new()
var _vital_reported := {}   # StringName -> true
## 已移植的器官：part_id -> organ_id（存檔用）
var organs := {}

static func from_profile(p: AnatomyProfile) -> AnatomyState:
	var errors := p.validate()
	assert(errors.is_empty(), "Invalid AnatomyProfile %s: %s" % [p.id, ", ".join(errors)])
	var s := AnatomyState.new()
	s.profile = p
	for d in p.parts:
		s._parts[d.id] = BodyPartState.new(d)
		s._order.append(d.id)
		s._children[d.id] = [] as Array[StringName]
	for d in p.parts:
		if d.parent_id != &"":
			(s._children[d.parent_id] as Array).append(d.id)
	s._caps = s._compute_caps()
	return s

# ---------- 查詢 ----------

func get_part(part_id: StringName) -> BodyPartState:
	return _parts.get(part_id)

func part_ids() -> Array[StringName]:
	return _order.duplicate()

func status_of(part_id: StringName) -> int:
	return get_part(part_id).status()

func capabilities() -> CapabilitySet:
	return _caps

## 可被直接瞄準的部位（非內部、未斷離）。
func targetable_part_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		if not p.severed and not p.def.is_internal:
			out.append(pid)
	return out

func total_bleed_rate() -> float:
	var total := 0.0
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		if not p.severed:
			total += p.bleed_rate
	return total

func descendants_of(part_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for c in _children.get(part_id, []):
		out.append(c)
		out.append_array(descendants_of(c))
	return out

# ---------- 修改 ----------

## 便利方法：計算並套用一次命中。
func receive(packet: DamagePacket, rng: RandomNumberGenerator) -> DamageResult:
	var result := DamageResolver.resolve(self, packet, rng)
	apply_result(result)
	return result

func apply_result(result: DamageResult) -> void:
	if result.rejected or is_dead:
		return
	var before := _snapshot()
	var to_sever: Array[StringName] = []
	for h in result.hits:
		var p: BodyPartState = _parts.get(h.part_id)
		if p == null or p.severed:
			continue
		p.hp = maxf(0.0, p.hp - h.hp_loss)
		for t in h.injuries:
			p.injuries[t] = p.injury(t) + float(h.injuries[t])
		p.bleed_rate = maxf(0.0, p.bleed_rate + h.bleed_delta)
		p.mutation = clampf(p.mutation + h.mutation_delta, 0.0, 100.0)
		_update_own_disabled(p)
		part_damaged.emit(p.id, h)
		if h.severed:
			to_sever.append(p.id)
	var severed_events := []
	for pid in to_sever:
		var ids := _do_sever(pid)
		if not ids.is_empty():
			severed_events.append([pid, ids])
	_refresh(before, severed_events)

## 直接斷離部位（劇情、處決、測試用）。不可斷離的部位回傳 false。
func sever_part(part_id: StringName) -> bool:
	var p: BodyPartState = _parts.get(part_id)
	if p == null or p.severed or not p.def.detachable or is_dead:
		return false
	var before := _snapshot()
	var ids := _do_sever(part_id)
	_refresh(before, [[part_id, ids]])
	return true

## 修復部位（玩家縫合、器官移植後使用）。斷離的部位需要父部位仍連接。
## include_children 為 true 時，一併修復連帶斷離的子部位。
func restore_part(part_id: StringName, include_children: bool = true) -> bool:
	var p: BodyPartState = _parts.get(part_id)
	if p == null or is_dead:
		return false
	if p.def.parent_id != &"" and (_parts[p.def.parent_id] as BodyPartState).severed:
		return false
	var before := _snapshot()
	var targets: Array[StringName] = [part_id]
	if include_children:
		targets.append_array(descendants_of(part_id))
	for pid in targets:
		var t: BodyPartState = _parts[pid]
		if t.severed:
			t.sutured = true
		t.hp = t.def.max_hp
		t.injuries.clear()
		t.bleed_rate = 0.0
		t.bandaged = false
		t.severed = false
		t.own_disabled = false
		_vital_reported.erase(pid)
	_refresh(before, [])
	part_restored.emit(part_id)
	return true

## 治療部位 HP（不會接回斷離部位）。HP 回到 0 以上且骨折未達門檻時恢復功能。
func heal_part(part_id: StringName, amount: float) -> void:
	var p: BodyPartState = _parts.get(part_id)
	if p == null or p.severed or is_dead or amount <= 0.0:
		return
	var before := _snapshot()
	p.hp = minf(p.def.max_hp, p.hp + amount)
	if p.own_disabled and p.hp > 0.0 and p.injury(DamageTypes.Type.FRACTURE) < p.def.max_hp * DamageTypes.FRACTURE_DISABLE_RATIO:
		p.own_disabled = false
	_refresh(before, [])

## 時間推進：壞死扣 HP。回傳這段時間內的總失血量，由 HP 資源池扣除（M3）。
func tick(delta: float) -> float:
	if is_dead:
		return 0.0
	var before := _snapshot()
	var blood := 0.0
	# 指數衰減的精確積分：這段時間流出的量 = rate × (1 - f) / k
	var k := LN2 / bleed_half_life if bleed_half_life > 0.0 else 0.0
	var f := exp(-k * delta)
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		if p.severed:
			continue
		if p.bleed_rate > 0.0:
			if k > 0.0:
				blood += p.bleed_rate * (1.0 - f) / k
				p.bleed_rate *= f
				if p.bleed_rate < BLEED_STOP_RATE:
					p.bleed_rate = 0.0
			else:
				blood += p.bleed_rate * delta
		var nec := p.injury(DamageTypes.Type.NECROSIS)
		if nec > 0.0 and p.hp > 0.0:
			p.hp = maxf(0.0, p.hp - nec * DamageTypes.NECROSIS_HP_PER_SEC * delta)
			_update_own_disabled(p)
	_refresh(before, [])
	return blood

## 止血（壓迫包紮、縫合後）：所有出血部位的出血速率 ×(1 - reduction)，並標記為已包紮。
## 回傳被包紮的部位。
func stanch(reduction: float) -> Array[StringName]:
	var out: Array[StringName] = []
	if is_dead:
		return out
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		if p.severed or p.bleed_rate <= 0.0:
			continue
		p.bleed_rate *= clampf(1.0 - reduction, 0.0, 1.0)
		if p.bleed_rate < BLEED_STOP_RATE:
			p.bleed_rate = 0.0
		p.bandaged = true
		out.append(pid)
	return out

## 以新的部位定義取代現有部位（器官移植、機械義肢）。ID、父部位與依賴關係必須維持，
## 以免破壞身體結構；新定義的功能、HP、護甲、抗性會生效，部位恢復為完整狀態。
func replace_part_definition(part_id: StringName, new_def: BodyPartDef, organ_id: StringName = &"") -> bool:
	var old: BodyPartState = _parts.get(part_id)
	if old == null or is_dead or new_def.id != part_id or new_def.parent_id != old.def.parent_id:
		return false
	if old.def.parent_id != &"" and (_parts[old.def.parent_id] as BodyPartState).severed:
		return false
	var before := _snapshot()
	var st := BodyPartState.new(new_def)
	st.mutation = old.mutation
	_parts[part_id] = st
	_vital_reported.erase(part_id)
	if organ_id != &"":
		organs[part_id] = organ_id
	else:
		organs.erase(part_id)
	_refresh(before, [])
	part_replaced.emit(part_id, organ_id)
	part_restored.emit(part_id)
	return true

# ---------- 存檔 ----------

func to_save() -> Dictionary:
	var parts := {}
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		var inj := {}
		for t in p.injuries:
			inj[DamageTypes.name_of(int(t))] = p.injuries[t]
		parts[String(pid)] = {
			"hp": p.hp, "injuries": inj, "bleed": p.bleed_rate, "mutation": p.mutation,
			"severed": p.severed, "own_disabled": p.own_disabled,
			"bandaged": p.bandaged, "sutured": p.sutured,
		}
	var organ_ids := {}
	for k in organs:
		organ_ids[String(k)] = String(organs[k])
	return {"version": SAVE_VERSION, "profile_id": String(profile.id), "dead": is_dead, "parts": parts, "organs": organ_ids}

## 從存檔還原。存檔中不存在的部位（新版本新增的部位）保持完整；
## 存檔中有但 profile 已移除的部位會被忽略。
## organ_lookup：Callable(organ_id: StringName) -> BodyPartDef，用來還原已移植器官的部位定義。
static func from_save(p: AnatomyProfile, data: Dictionary, organ_lookup: Callable = Callable()) -> AnatomyState:
	var s := from_profile(p)
	var saved_organs: Dictionary = data.get("organs", {})
	if organ_lookup.is_valid():
		for key in saved_organs:
			var pid := StringName(key)
			var def: BodyPartDef = organ_lookup.call(StringName(saved_organs[key]))
			if def != null and s._parts.has(pid):
				s._parts[pid] = BodyPartState.new(def)
				s.organs[pid] = StringName(saved_organs[key])
	var parts: Dictionary = data.get("parts", {})
	for key in parts:
		var st: BodyPartState = s._parts.get(StringName(key))
		if st == null:
			continue
		var d: Dictionary = parts[key]
		st.hp = clampf(float(d.get("hp", st.def.max_hp)), 0.0, st.def.max_hp)
		st.bleed_rate = float(d.get("bleed", 0.0))
		st.mutation = float(d.get("mutation", 0.0))
		st.severed = bool(d.get("severed", false))
		st.own_disabled = bool(d.get("own_disabled", false))
		st.bandaged = bool(d.get("bandaged", false))
		st.sutured = bool(d.get("sutured", false))
		var inj: Dictionary = d.get("injuries", {})
		for tname in inj:
			var t := DamageTypes.Type.keys().find(String(tname))
			if t >= 0:
				st.injuries[t] = float(inj[tname])
	s.is_dead = bool(data.get("dead", false))
	s._recompute_dependencies()
	for pid in s._order:
		if not (s._parts[pid] as BodyPartState).is_functional() and s._parts[pid].def.vital != BodyPartDef.VitalRule.NONE:
			s._vital_reported[pid] = true
	s._caps = s._compute_caps()
	return s

# ---------- 內部 ----------

func _update_own_disabled(p: BodyPartState) -> void:
	if p.own_disabled:
		return
	if p.hp <= 0.0:
		p.own_disabled = true
		p.set_meta(&"disable_reason", "hp")
	elif p.injury(DamageTypes.Type.FRACTURE) >= p.def.max_hp * DamageTypes.FRACTURE_DISABLE_RATIO:
		p.own_disabled = true
		p.set_meta(&"disable_reason", "fracture")

func _do_sever(part_id: StringName) -> PackedStringArray:
	var p: BodyPartState = _parts[part_id]
	if p.severed or not p.def.detachable:
		return PackedStringArray()
	var ids := PackedStringArray([String(part_id)])
	for c in descendants_of(part_id):
		ids.append(String(c))
	for pid in ids:
		var t: BodyPartState = _parts[StringName(pid)]
		t.severed = true
		t.bleed_rate = 0.0
	if p.def.parent_id != &"":
		var parent: BodyPartState = _parts[p.def.parent_id]
		parent.bleed_rate += p.def.max_hp * STUMP_BLEED_RATIO
	return ids

func _recompute_dependencies() -> void:
	# 反覆傳播直到穩定（依賴圖已驗證無循環，最多 N 輪）。
	for pid in _order:
		(_parts[pid] as BodyPartState).dependency_disabled = false
	var changed := true
	var guard := _order.size() + 1
	while changed and guard > 0:
		changed = false
		guard -= 1
		for pid in _order:
			var p: BodyPartState = _parts[pid]
			if p.dependency_disabled or p.severed:
				continue
			for dep in p.def.dependencies:
				if not (_parts[StringName(dep)] as BodyPartState).is_functional():
					p.dependency_disabled = true
					changed = true
					break

func _compute_caps() -> CapabilitySet:
	var caps := CapabilitySet.new()
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		if p.is_functional():
			for f in p.def.functions:
				caps.add(f)
	return caps

func _snapshot() -> Dictionary:
	var snap := {}
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		snap[pid] = [p.status(), p.is_functional()]
	return snap

func _refresh(before: Dictionary, severed_events: Array) -> void:
	_recompute_dependencies()
	for ev in severed_events:
		part_severed.emit(ev[0], ev[1])
	for pid in _order:
		var p: BodyPartState = _parts[pid]
		var old_status: int = before[pid][0]
		var was_functional: bool = before[pid][1]
		var new_status := p.status()
		if new_status != old_status:
			part_status_changed.emit(pid, old_status, new_status)
		if was_functional and not p.is_functional() and not p.severed:
			var reason := "dependency" if (p.dependency_disabled and not p.own_disabled) else String(p.get_meta(&"disable_reason", "hp"))
			part_disabled.emit(pid, reason)
		if not p.is_functional() and p.def.vital != BodyPartDef.VitalRule.NONE and not _vital_reported.has(pid):
			_vital_reported[pid] = true
			vital_failed.emit(pid, p.def.vital)
			if p.def.vital == BodyPartDef.VitalRule.INSTANT_DEATH and not is_dead:
				is_dead = true
				died.emit(pid)
	var new_caps := _compute_caps()
	if not new_caps.equals(_caps):
		_caps = new_caps
		capabilities_changed.emit(_caps)
