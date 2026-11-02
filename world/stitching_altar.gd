class_name StitchingAltar
extends Node3D
## 縫合祭壇（D2）：完整修復身體（含斷肢）、回滿資源，並可進行器官移植。
## M7 起也是存檔點與重生點。【暫代】外觀為灰盒。

signal rested(player: Node3D)
signal surgery_requested(player: Node3D)

const GROUP := &"interactables"
@export var altar_id: StringName = &"altar"
@export var interact_radius: float = 2.0

func _ready() -> void:
	add_to_group(GROUP)
	if get_child_count() == 0:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.9, 0.9)
		mi.mesh = bm
		mi.position = Vector3(0, 0.45, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("e8e2d6")
		mat.emission_enabled = true
		mat.emission = Color("5a1a14")
		mat.emission_energy_multiplier = 0.4
		mi.material_override = mat
		add_child(mi)

func prompt() -> String:
	return "E：在縫合祭壇休息（修復身體）　T：器官移植"

func in_range(player: Node3D) -> bool:
	return player.global_position.distance_to(global_position) <= interact_radius

## 休息：依深度順序修復所有部位（父部位先），回滿 HP／ST，清除出血。
func rest(player: Node3D) -> void:
	var combat: CombatComponent = player.get_node("CombatComponent")
	var st := combat.anatomy.state
	if st.is_dead:
		return
	var ids := st.part_ids()
	ids.sort_custom(func(a, b): return _depth(st, a) < _depth(st, b))
	for pid in ids:
		var p := st.get_part(pid)
		if p.status() != AnatomyTypes.PartStatus.INTACT and p.status() != AnatomyTypes.PartStatus.MUTATED or p.bleed_rate > 0.0 or p.injuries.size() > 0:
			st.restore_part(pid, false)
	combat.pools.heal_hp(combat.pools.max_hp)
	combat.pools.st = combat.pools.max_st
	combat.vital_timer = -1.0
	var mut: MutationComponent = player.get_node_or_null("MutationComponent")
	if mut != null and mut.has_effect("heal_penalty"):
		mut.add(mut.effect_total("heal_penalty"), "altar")
	rested.emit(player)

func request_surgery(player: Node3D) -> void:
	surgery_requested.emit(player)

static func _depth(st: AnatomyState, pid: StringName) -> int:
	var n := 0
	var cur := st.get_part(pid)
	while cur != null and cur.def.parent_id != &"":
		n += 1
		cur = st.get_part(cur.def.parent_id)
	return n
