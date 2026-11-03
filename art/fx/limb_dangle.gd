class_name LimbDangle
extends SkeletonModifier3D
## 失效（骨折、HP 歸零、依賴部位失效）但還連著的手臂：在動畫之後覆寫骨骼姿勢，
## 讓它直直垂著、只隨身體輕微晃動，不再跟著攻擊或走路擺動。
## 斷離的部位不處理（骨骼已縮為零）。腿失效時能力已變成單腿，動畫系統會改用跛行。
## 由 InjuryVisuals 加到 Skeleton3D 底下；不修改 CreatureAnimator。

var anatomy: AnatomyComponent
## 輕微晃動的幅度（弧度）。
const SWAY := 0.10

## 目前應該垂著的部位（測試與修改共用）。
func dangling_parts() -> Array[StringName]:
	var out: Array[StringName] = []
	if anatomy == null or anatomy.state == null:
		return out
	for pid in anatomy.state.part_ids():
		var p := anatomy.state.get_part(pid)
		if p.severed or p.is_functional() or p.def.is_internal:
			continue
		if p.def.functions.has("grip") or p.def.functions.has("arm"):
			out.append(pid)
	return out

func _process_modification() -> void:
	apply_now(Time.get_ticks_msec() / 1000.0)

## 覆寫姿勢（測試可直接呼叫）。回傳覆寫了幾根骨骼。
func apply_now(t: float) -> int:
	var skel := get_skeleton()
	if skel == null:
		return 0
	var n := 0
	for pid in dangling_parts():
		var idx := skel.find_bone(String(anatomy.state.get_part(pid).def.bone_name))
		if idx < 0:
			continue
		var side := 1.0 if String(pid).ends_with("_l") else -1.0
		var sway := sin(t * 1.7 + side) * SWAY
		var q := Quaternion(Vector3.RIGHT, sway) * Quaternion(Vector3.FORWARD, side * 0.06)
		skel.set_bone_pose_rotation(idx, q)
		n += 1
	return n
