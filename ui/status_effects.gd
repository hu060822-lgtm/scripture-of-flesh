class_name StatusEffects
extends RefCounted
## 從角色身上彙整「目前有哪些異常狀態」，給 HUD 圖標列使用。純讀取，不修改任何狀態。
## 每個狀態：{ id, label, level (1–3，決定圖標強度), text (數值，可空) }。
## 判斷全部來自實際的戰鬥／解剖資料，沒有獨立的假狀態。

const BLEED_LEVELS := [0.5, 1.5]  # 總出血速率 < 0.5 → 1 級、< 1.5 → 2 級、其餘 3 級

## 圖標列的排列順序（越前面越危險）。
const ORDER := [
	&"suffocating", &"bleed_floor", &"bleeding", &"necrosis", &"burn", &"fracture",
	&"staggered", &"blind", &"crawling", &"limping", &"armless", &"one_armed",
	&"bandaging", &"suturing", &"mutation",
]

static func collect(combat: CombatComponent) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if combat == null or combat.anatomy == null or combat.anatomy.state == null:
		return out
	var st := combat.anatomy.state
	if combat.vital_timer >= 0.0 and not combat.is_dead():
		out.append(_fx(&"suffocating", "窒息", 3, "%d秒" % ceili(combat.vital_timer)))
	var bleed := st.total_bleed_rate()
	if combat.bleed_floored and bleed > 0.0:
		out.append(_fx(&"bleed_floor", "失血昏沉", 3))
	if bleed > 0.0:
		var lvl := 1 if bleed < BLEED_LEVELS[0] else (2 if bleed < BLEED_LEVELS[1] else 3)
		out.append(_fx(&"bleeding", "出血", lvl, "%.1f/s" % bleed))
	var nec := 0; var burn := 0; var frac := 0
	for pid in st.part_ids():
		var p := st.get_part(pid)
		if p.severed:
			continue
		if p.injury(DamageTypes.Type.NECROSIS) > 0.0 and p.hp > 0.0:
			nec += 1
		if p.injury(DamageTypes.Type.BURN) > 0.0:
			burn += 1
		if p.injury(DamageTypes.Type.FRACTURE) >= p.def.max_hp * DamageTypes.FRACTURE_DISABLE_RATIO:
			frac += 1
	if nec > 0:
		out.append(_fx(&"necrosis", "壞死", mini(3, nec)))
	if burn > 0:
		out.append(_fx(&"burn", "灼傷", mini(3, burn)))
	if frac > 0:
		out.append(_fx(&"fracture", "骨折", mini(3, frac), "×%d" % frac if frac > 1 else ""))
	if combat.action == CombatComponent.Action.STAGGER:
		out.append(_fx(&"staggered", "踉蹌", 2))
	var caps := st.capabilities()
	var eyes_total := 0
	for pid in st.part_ids():
		if st.get_part(pid).def.functions.has("vision"):
			eyes_total += 1
	if eyes_total > 0 and caps.count("vision") == 0:
		out.append(_fx(&"blind", "失明", 3))
	var aset := AnimationSet.from_capabilities(caps)
	if aset["legs"] == AnimationSet.LEGS_CRAWL:
		out.append(_fx(&"crawling", "爬行", 3))
	elif aset["legs"] == AnimationSet.LEGS_ONE:
		out.append(_fx(&"limping", "跛行", 2))
	if aset["arms"] == AnimationSet.ARMS_NONE:
		out.append(_fx(&"armless", "無法持握", 3))
	elif aset["arms"] == AnimationSet.ARMS_ONE:
		out.append(_fx(&"one_armed", "單手", 1))
	var data: PlayerData = combat.body().get_node_or_null("PlayerData")
	if data != null:
		if data.is_bandaging():
			out.append(_fx(&"bandaging", "包紮中", 1))
		elif data.is_suturing():
			out.append(_fx(&"suturing", "縫合中", 1, st.get_part(data.suturing_part).def.display_name))
	var mut: MutationComponent = combat.body().get_node_or_null("MutationComponent")
	if mut != null:
		var stage := mut.current_stage()
		if stage != null:
			out.append(_fx(&"mutation", stage.display_name, clampi(mut.stages.find(stage) + 1, 1, 3), "%d" % int(mut.value)))
	out.sort_custom(func(a, b): return ORDER.find(a["id"]) < ORDER.find(b["id"]))
	return out

static func ids(effects: Array[Dictionary]) -> Array:
	return effects.map(func(e): return e["id"])

static func _fx(id: StringName, label: String, level: int, text: String = "") -> Dictionary:
	return {"id": id, "label": label, "level": level, "text": text}
