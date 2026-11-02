class_name MutationComponent
extends Node
## 異化程度 0–100。影響身體（新攻擊、再生）、能力、感官（戰術介面資訊）與劇情（旗標）。
## 來源：異化傷害（凝視）、器官移植、緊急縫合。意志（WIL）與技能可降低增加量。

signal mutation_changed(value: float)
signal stage_reached(stage: MutationStage)

const STAGE_DIR := "res://content/mutation"
## 部位受到的異化傷害轉為整體異化的比例。
const WOUND_TO_MUTATION := 0.5

var value := 0.0
var stages: Array[MutationStage] = []
var reached: Array[StringName] = []
var combat: CombatComponent
var progression: ProgressionComponent
var _granted_attacks: Array[AttackDefinition] = []

func _ready() -> void:
	combat = get_parent().get_node("CombatComponent")
	progression = get_parent().get_node_or_null("ProgressionComponent")
	for f in DirAccess.get_files_at(STAGE_DIR):
		if f.ends_with(".tres"):
			stages.append(load(STAGE_DIR.path_join(f)))
	stages.sort_custom(func(a, b): return a.threshold < b.threshold)
	combat.anatomy.state.part_damaged.connect(_on_part_damaged)

func resistance() -> float:
	var r := 0.0
	if progression != null:
		r = progression.stats.mutation_resistance() + progression.effect_total("mutation_resist")
	return clampf(r, -0.5, 0.8)

## 增加異化（套用抗性）。回傳實際增加量。
func add(amount: float, _source: String = "") -> float:
	if amount <= 0.0:
		return 0.0
	var actual := amount * (1.0 - resistance())
	set_value(value + actual)
	return actual

func set_value(v: float) -> void:
	value = clampf(v, 0.0, 100.0)
	mutation_changed.emit(value)
	for st in stages:
		if value >= st.threshold and not st.id in reached:
			reached.append(st.id)
			_apply_stage(st)
			stage_reached.emit(st)
			if is_inside_tree():
				EventBus.mutation_stage_reached.emit(&"player", st.id)
				if st.story_flag != &"":
					EventBus.flag_changed.emit(st.story_flag, true)

func current_stage() -> MutationStage:
	var cur: MutationStage = null
	for st in stages:
		if st.id in reached:
			cur = st
	return cur

func has_effect(key: String) -> bool:
	return effect_total(key) != 0.0

func effect_total(key: String) -> float:
	var t := 0.0
	for st in stages:
		if st.id in reached and st.effects.has(key):
			t += float(st.effects[key])
	return t

func _apply_stage(st: MutationStage) -> void:
	for k in st.effects:
		var key := String(k)
		if key.begins_with("grant_attack:"):
			var path := "res://content/attacks/%s.tres" % key.substr(13)
			if ResourceLoader.exists(path):
				var a: AttackDefinition = load(path)
				if not a in combat.natural_attacks:
					combat.natural_attacks.append(a)
					_granted_attacks.append(a)
		elif key == "max_st":
			combat.pools.max_st += float(st.effects[k])
		elif key == "ap_bonus":
			combat.ap_gain_bonus += float(st.effects[k])

func _physics_process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

func advance(delta: float) -> void:
	var regen := effect_total("part_regen")
	if regen <= 0.0 or delta <= 0.0 or combat.is_dead():
		return
	var st := combat.anatomy.state
	for pid in st.part_ids():
		var p := st.get_part(pid)
		if not p.severed and p.hp < p.def.max_hp:
			st.heal_part(pid, regen * delta)

func _on_part_damaged(_part_id: StringName, hit: DamageResult.PartHit) -> void:
	if hit.mutation_delta > 0.0:
		add(hit.mutation_delta * WOUND_TO_MUTATION, "wound")

func to_save() -> Dictionary:
	return {"value": value, "reached": reached.map(func(s): return String(s))}

func load_save(d: Dictionary) -> void:
	reached.clear()
	value = 0.0
	set_value(float(d.get("value", 0.0)))
