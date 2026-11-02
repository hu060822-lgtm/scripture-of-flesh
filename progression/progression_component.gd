class_name ProgressionComponent
extends Node
## 角色成長：屬性、職業起點、等級、技能樹、武器熟練度。
## 職業只決定起點；升級點數可自由分配到任何屬性與技能。

signal leveled_up(level: int)
signal stats_changed
signal skill_unlocked(skill_id: StringName)

const SKILL_DIR := "res://content/skills"
const XP_PER_LEVEL := 100
const PROFICIENCY_MAX := 10

@export var class_definition: ClassDefinition
var stats := CharacterStats.new()
var level := 1
var xp := 0
var stat_points := 0
var skill_points := 1
var unlocked: Array[StringName] = []
var proficiency := {}  # weapon_type -> 經驗值
var combat: CombatComponent
var _skills := {}      # id -> SkillDefinition

func _ready() -> void:
	combat = get_parent().get_node("CombatComponent")
	_load_skills()
	if class_definition != null and unlocked.is_empty():
		apply_class(class_definition)
	combat.damage_modifier = outgoing_scale
	combat.attack_landed.connect(_on_attack_landed)
	EventBus.creature_killed.connect(_on_creature_killed)
	apply_to_combat()

func _load_skills() -> void:
	for f in DirAccess.get_files_at(SKILL_DIR):
		if f.ends_with(".tres"):
			var s: SkillDefinition = load(SKILL_DIR.path_join(f))
			_skills[s.id] = s

func skill(id: StringName) -> SkillDefinition:
	return _skills.get(id)

func all_skills() -> Array:
	return _skills.values()

func apply_class(c: ClassDefinition) -> void:
	class_definition = c
	stats = c.stats.duplicate()
	for sid in c.starting_skills:
		if not sid in unlocked:
			unlocked.append(sid)
	stats_changed.emit()

## 依屬性重算資源上限（保持目前比例）。
func apply_to_combat() -> void:
	var p := combat.pools
	var hp_ratio := p.hp / p.max_hp if p.max_hp > 0 else 1.0
	p.max_hp = stats.max_hp() + (60.0 if combat.faction == &"player" else 0.0)
	p.max_st = stats.max_st()
	p.max_ap = stats.max_ap()
	p.hp = p.max_hp * hp_ratio
	p.st = minf(p.st, p.max_st)
	combat.bleed_scale = maxf(0.2, 1.0 - effect_total("bleed_resist"))
	combat.ap_gain_bonus = effect_total("ap_gain")

func effect_total(key: String) -> float:
	var total := 0.0
	for sid in unlocked:
		var s := skill(sid)
		if s != null:
			total += float(s.effects.get(key, 0.0))
	return total

func proficiency_level(weapon_type: StringName) -> int:
	return mini(PROFICIENCY_MAX, int(sqrt(float(proficiency.get(weapon_type, 0)) / 5.0)))

## 輸出傷害倍率：屬性 × 熟練度（每級 +4%）× 技能。
func outgoing_scale(attack: AttackDefinition, weapon: WeaponDefinition) -> float:
	var wtype: StringName = weapon.weapon_type if weapon != null else &"unarmed"
	var m := stats.damage_scale(wtype)
	m *= 1.0 + 0.04 * proficiency_level(wtype)
	m *= 1.0 + effect_total("damage_scale:%s" % wtype)
	return maxf(0.1, m)

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= XP_PER_LEVEL * level:
		xp -= XP_PER_LEVEL * level
		level += 1
		stat_points += 1
		skill_points += 1
		leveled_up.emit(level)

func allocate_stat(stat_name: String) -> bool:
	if stat_points <= 0 or not stat_name in CharacterStats.NAMES:
		return false
	stat_points -= 1
	stats.add(stat_name, 1)
	apply_to_combat()
	stats_changed.emit()
	return true

func can_unlock(id: StringName) -> bool:
	var s := skill(id)
	if s == null or id in unlocked or skill_points < s.cost:
		return false
	for pre in s.prerequisites:
		if not pre in unlocked:
			return false
	return true

func unlock_skill(id: StringName) -> bool:
	if not can_unlock(id):
		return false
	skill_points -= skill(id).cost
	unlocked.append(id)
	apply_to_combat()
	skill_unlocked.emit(id)
	return true

func _on_attack_landed(_target: CombatComponent, _result: DamageResult) -> void:
	var w := combat.weapon()
	var t: StringName = w.weapon_type if w != null else &"unarmed"
	proficiency[t] = int(proficiency.get(t, 0)) + 1

func _on_creature_killed(victim: Node, killer: Node) -> void:
	if killer != combat or victim == combat:
		return
	var reward := 40
	var body: Node = (victim as CombatComponent).body()
	if body.has_meta(&"xp_reward"):
		reward = int(body.get_meta(&"xp_reward"))
	add_xp(reward)

func to_save() -> Dictionary:
	return {"class": String(class_definition.id) if class_definition else "", "stats": stats.to_dict(),
		"level": level, "xp": xp, "stat_points": stat_points, "skill_points": skill_points,
		"skills": unlocked.map(func(s): return String(s)), "proficiency": proficiency.duplicate()}

func load_save(d: Dictionary) -> void:
	stats.load_dict(d.get("stats", {}))
	level = int(d.get("level", 1)); xp = int(d.get("xp", 0))
	stat_points = int(d.get("stat_points", 0)); skill_points = int(d.get("skill_points", 0))
	unlocked.clear()
	for s in d.get("skills", []):
		unlocked.append(StringName(s))
	proficiency = d.get("proficiency", {}).duplicate()
	apply_to_combat()
	stats_changed.emit()
