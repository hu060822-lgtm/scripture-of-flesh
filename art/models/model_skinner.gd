class_name ModelSkinner
extends Node
## 部位被替換（器官移植、Boss 階段轉換）時，把該部位的外觀換成新部位的造型；
## 修復斷肢後也重新套用（DismembermentController 的修復複本是原本的外觀）。
## 由 CreatureModels.apply 加入；必須排在 DismembermentController 之後，修復時才會在它重建分段之後執行。

## 器官 id -> 外觀變體（CreatureModels._model_for）
const ORGAN_VARIANTS := {
	&"iron_arm": &"iron_arm", &"stitched_arm": &"stitched_arm", &"reverse_leg": &"reverse_leg",
	&"watcher_eye": &"watcher_eye", &"agnes_arm": &"stitched_arm",
}

var creature: Node3D
var anatomy: AnatomyComponent
## part_id -> 目前的外觀變體
var variants := {}

func _ready() -> void:
	creature = get_parent() as Node3D
	anatomy = creature.get_node("AnatomyComponent")
	if anatomy.state == null:
		anatomy.setup()
	anatomy.state.part_replaced.connect(_on_part_replaced)
	anatomy.state.part_restored.connect(_on_part_restored)
	# 讀檔時器官可能在加入場景前就已替換
	for d in anatomy.profile.parts:
		var st := anatomy.state.get_part(d.id)
		if st != null and st.def != d:
			_on_part_replaced(d.id, anatomy.state.organs.get(d.id, &""))

func variant_for(part_id: StringName, organ_id: StringName) -> StringName:
	if ORGAN_VARIANTS.has(organ_id):
		return ORGAN_VARIANTS[organ_id]
	var st := anatomy.state.get_part(part_id)
	if st != null and st.def.resource_path.get_file().get_basename() == "womb_exposed":
		return &"womb_exposed"
	return &""

func _on_part_replaced(part_id: StringName, organ_id: StringName) -> void:
	variants[part_id] = variant_for(part_id, organ_id)
	_rebuild(part_id)

func _on_part_restored(part_id: StringName) -> void:
	for id in [part_id] + anatomy.state.descendants_of(part_id):
		if variants.has(id):
			_rebuild(id)

func _rebuild(part_id: StringName) -> void:
	var st := anatomy.state.get_part(part_id)
	if st == null or st.def.is_internal:
		return
	var seg := creature.find_child(String(st.def.mesh_segment), true, false) as MeshInstance3D
	if seg == null or not creature.is_ancestor_of(seg):
		return  # 已斷離：外觀隨殘肢飛出，修復時再套用
	var look: StringName = creature.get_meta(&"model_look", &"humanoid")
	var lk: Dictionary = CreatureModels.LOOKS.get(look, CreatureModels.LOOKS[&"humanoid"])
	CreatureModels.build_segment(seg, st.def, anatomy.profile, look, lk, variants.get(part_id, &""))
