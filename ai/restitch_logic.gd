class_name RestitchLogic
extends RefCounted
## 縫屍者的特殊行為：找回被砍下的肢體並縫回去。
## 自己的殘肢優先；序章提案 C 起也會撿同伴（同陣營、還活著、不是 Boss）的殘肢，
## 走到同伴身邊幫它縫回去。縫屍者需要至少一隻能抓握的手才縫得了同伴 —— 先砍它的手就能阻止。

const SEARCH_RADIUS := 6.0
const CHANNEL_SECONDS := 2.5
const REACH := 0.9
## 走到同伴身邊這麼近就開始縫。
const ALLY_REACH := 1.4

## 找最近的可縫回殘肢（父部位還在）。自己的殘肢優先於同伴的。
static func find_limb(ai: EnemyAI) -> SeveredPart:
	var own_best: SeveredPart = null
	var own_d := SEARCH_RADIUS
	var ally_best: SeveredPart = null
	var ally_d := SEARCH_RADIUS
	var can_help := ai.combat.caps().count("grip") > 0
	for n in ai.get_tree().get_nodes_in_group(SeveredPart.GROUP):
		var g := n as SeveredPart
		if g == null or g.is_queued_for_deletion():
			continue
		var d := g.global_position.distance_to(ai.body().global_position)
		if g.source_creature_id == ai.anatomy.creature_id:
			if d < own_d and _restorable(ai.anatomy.state, g.part_id):
				own_d = d
				own_best = g
		elif can_help and d < ally_d and owner_of(ai, g) != null:
			ally_d = d
			ally_best = g
	return own_best if own_best != null else ally_best

## 殘肢屬於哪個還活著、可以幫忙縫的同伴（找不到回傳 null）。
static func owner_of(ai: EnemyAI, g: SeveredPart) -> CombatComponent:
	for n in ai.get_tree().get_nodes_in_group(CombatComponent.GROUP):
		var c := n.get_node_or_null("CombatComponent") as CombatComponent
		if c == null or c == ai.combat or c.is_dead() or c.faction != ai.combat.faction:
			continue
		if c.anatomy == null or c.anatomy.creature_id != g.source_creature_id:
			continue
		var e := n.get_node_or_null("EnemyAI") as EnemyAI
		if e != null and e.definition != null and e.definition.special_behavior == &"boss":
			return null
		if not _restorable(c.anatomy.state, g.part_id):
			return null
		return c
	return null

static func _restorable(st: AnatomyState, part_id: StringName) -> bool:
	var p := st.get_part(part_id)
	if p == null or not p.severed:
		return false
	return p.def.parent_id == &"" or not st.get_part(p.def.parent_id).severed
