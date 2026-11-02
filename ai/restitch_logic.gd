class_name RestitchLogic
extends RefCounted
## 縫屍者的特殊行為：找回自己被砍下的肢體並縫回去。

const SEARCH_RADIUS := 6.0
const CHANNEL_SECONDS := 2.5
const REACH := 0.9

## 找最近的、屬於自己且仍可縫回（父部位還在）的殘肢。
static func find_limb(ai: EnemyAI) -> SeveredPart:
	var best: SeveredPart = null
	var best_d := SEARCH_RADIUS
	for n in ai.get_tree().get_nodes_in_group(SeveredPart.GROUP):
		var g := n as SeveredPart
		if g == null or g.is_queued_for_deletion() or g.source_creature_id != ai.anatomy.creature_id:
			continue
		var p := ai.anatomy.state.get_part(g.part_id)
		if p == null or not p.severed:
			continue
		if p.def.parent_id != &"" and ai.anatomy.state.get_part(p.def.parent_id).severed:
			continue
		var d := g.global_position.distance_to(ai.body().global_position)
		if d < best_d:
			best_d = d
			best = g
	return best
