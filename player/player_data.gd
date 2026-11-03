class_name PlayerData
extends Node
## 玩家的身體照護與持有物：物品欄、緊急縫合（D2）、從屍體摘取器官。

signal suture_started(part_id: StringName, duration: float)
signal suture_finished(part_id: StringName)
signal suture_interrupted
signal harvested(organ: OrganDefinition)
signal message(text: String)

## 緊急縫合：花時間把一個斷離或失效的部位粗糙地接回，代價是異化。
const SUTURE_SECONDS := 2.5
const SUTURE_MUTATION := 6.0
const HARVEST_RADIUS := 1.8
## 捐贈部位 HP 比例達到此值 = 完好摘下（移植相容性提高）。
const FRESH_RATIO := 0.6
## 修復優先順序：手（能拿武器）> 腿（能移動）> 眼 > 下顎 > 其他。
const PRIORITY := ["arm_r", "arm_l", "leg_l", "leg_r", "eye_l", "eye_r", "jaw"]

var inventory := Inventory.new()
var combat: CombatComponent
var mutation: MutationComponent
var progression: ProgressionComponent
var suturing_part: StringName = &""
var _suture_left := 0.0

func _ready() -> void:
	combat = get_parent().get_node("CombatComponent")
	mutation = get_parent().get_node_or_null("MutationComponent")
	progression = get_parent().get_node_or_null("ProgressionComponent")
	combat.hit_received.connect(func(_r, _a): _interrupt())
	if progression != null and progression.class_definition != null:
		for k in progression.class_definition.starting_items:
			inventory.add(String(k), int(progression.class_definition.starting_items[k]))

## 下一個需要縫合的部位（父部位必須仍然連著）。
func next_suture_target() -> StringName:
	var st := combat.anatomy.state
	var candidates: Array[StringName] = []
	for pid in st.part_ids():
		var p := st.get_part(pid)
		if (p.severed or p.own_disabled) and p.def.detachable:
			if p.def.parent_id == &"" or not st.get_part(p.def.parent_id).severed:
				candidates.append(pid)
	candidates.sort_custom(func(a, b):
		var ia := PRIORITY.find(String(a)); var ib := PRIORITY.find(String(b))
		return (ia if ia >= 0 else 99) < (ib if ib >= 0 else 99))
	return candidates[0] if not candidates.is_empty() else &""

func suture_duration() -> float:
	var speed := progression.effect_total("suture_speed") if progression != null else 0.0
	return SUTURE_SECONDS * maxf(0.3, 1.0 - speed)

func start_suture() -> bool:
	if suturing_part != &"" or combat.is_dead() or combat.action != CombatComponent.Action.IDLE:
		return false
	if inventory.count("suture_kit") <= 0:
		message.emit("沒有縫合包")
		return false
	var target := next_suture_target()
	if target == &"":
		message.emit("沒有需要縫合的部位")
		return false
	suturing_part = target
	_suture_left = suture_duration()
	suture_started.emit(target, _suture_left)
	return true

func _interrupt() -> void:
	if suturing_part != &"":
		suturing_part = &""
		suture_interrupted.emit()
		message.emit("縫合被打斷")

func _physics_process(delta: float) -> void:
	advance(TimeScale.scaled(delta))

func advance(delta: float) -> void:
	if suturing_part == &"" or delta <= 0.0:
		return
	if combat.action != CombatComponent.Action.IDLE:
		_interrupt()
		return
	_suture_left -= delta
	if _suture_left <= 0.0:
		var part := suturing_part
		suturing_part = &""
		inventory.remove("suture_kit")
		combat.anatomy.state.restore_part(part)
		if mutation != null:
			mutation.add(SUTURE_MUTATION * (1.0 - _effect("suture_mutation")), "suture")
		suture_finished.emit(part)
		message.emit("縫回了%s" % combat.anatomy.state.get_part(part).def.display_name)

func is_suturing() -> bool:
	return suturing_part != &""

## 從附近的屍體摘取器官（捐贈部位必須完好；每具屍體每種器官只能摘一次）。
func try_harvest() -> bool:
	var me: Node3D = get_parent()
	for n in get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var c: CombatComponent = n.get_node_or_null("CombatComponent")
		if c == null or not c.is_dead() or c == combat:
			continue
		if (n as Node3D).global_position.distance_to(me.global_position) > HARVEST_RADIUS:
			continue
		var organs: Array = n.get_meta(&"harvestable", [])
		var taken: Array = n.get_meta(&"harvested", [])
		for o in organs:
			var organ := o as OrganDefinition
			if organ == null or organ.id in taken:
				continue
			var quality := harvest_quality(c.anatomy.state, organ)
			if quality == &"ruined":
				# 殺法太粗暴：器官在戰鬥中毀了。每具屍體只提示一次，教玩家下次避開它。
				var told: Array = n.get_meta(&"harvest_ruined", [])
				if not organ.id in told:
					told.append(organ.id)
					n.set_meta(&"harvest_ruined", told)
					message.emit("%s在戰鬥中毀了——下次避開它再下手" % organ.display_name)
					return true
				continue
			taken.append(organ.id)
			n.set_meta(&"harvested", taken)
			inventory.add("organ:%s" % organ.id)
			if quality == &"fresh":
				inventory.add(fresh_key(organ.id))
				message.emit("完好地摘下了%s（移植相容性 +%d%%）" % [organ.display_name, int(TransplantService.FRESH_BONUS * 100)])
			else:
				message.emit("摘取了受損的%s" % organ.display_name)
			harvested.emit(organ)
			return true
	return false

## 器官摘取品質：fresh（捐贈部位 HP ≥ 60%）、damaged（還在但受損）、ruined（斷離或 HP 歸零）。
static func harvest_quality(state: AnatomyState, organ: OrganDefinition) -> StringName:
	if organ.harvest_part == &"":
		return &"fresh"
	var donor := state.get_part(organ.harvest_part)
	if donor == null or donor.severed or donor.hp <= 0.0:
		return &"ruined"
	return &"fresh" if donor.hp_ratio() >= FRESH_RATIO else &"damaged"

func _effect(key: String) -> float:
	return progression.effect_total(key) if progression != null else 0.0

static func fresh_key(organ_id: StringName) -> String:
	return "fresh:%s" % organ_id

func to_save() -> Dictionary:
	return {"inventory": inventory.to_save()}

func load_save(d: Dictionary) -> void:
	inventory.load_save(d.get("inventory", {}))
