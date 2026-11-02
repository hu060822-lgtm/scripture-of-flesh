extends TestCase
## 部位狀態、功能失效 vs 斷離、依賴傳播、致命部位、能力彙整、修復、存檔。

const T := DamageTypes.Type
const S := AnatomyTypes.PartStatus
const H := preload("res://tests/helpers.gd")

func test_initial_state_and_capabilities() -> void:
	var s := H.humanoid()
	for pid in s.part_ids():
		assert_eq(s.status_of(pid), S.INTACT, String(pid))
	var c := s.capabilities()
	assert_eq(c.count("grip"), 2)
	assert_eq(c.count("locomotion"), 2)
	assert_eq(c.count("vision"), 2)
	assert_eq(c.count("bite"), 1)

func test_status_thresholds_and_signal() -> void:
	var s := H.humanoid()
	var log := H.SignalLog.new(); log.connect_all(s)
	s.receive(H.no_sever(&"arm_l", {T.CRUSH: 10.0}), H.rng())  # 30 → 17
	assert_eq(s.status_of(&"arm_l"), S.DAMAGED)
	assert_eq(log.of("status"), [["status", &"arm_l", S.INTACT, S.DAMAGED]])
	s.receive(H.no_sever(&"arm_l", {T.CRUSH: 6.0}), H.rng())   # 17 → 9.2
	assert_eq(s.status_of(&"arm_l"), S.SEVERELY_DAMAGED)

func test_disabled_is_a_different_event_from_severed() -> void:
	var s := H.humanoid()
	var log := H.SignalLog.new(); log.connect_all(s)
	s.receive(H.no_sever(&"arm_r", {T.CRUSH: 30.0}), H.rng())
	var arm := s.get_part(&"arm_r")
	assert_eq(arm.status(), S.DISABLED)
	assert_false(arm.severed, "disabled arm is still attached")
	assert_eq(log.of("disabled").size(), 1)
	assert_eq(log.of("severed").size(), 0)
	assert_true(&"arm_r" in s.targetable_part_ids(), "disabled arm can still be hit")
	assert_eq(s.capabilities().count("grip"), 1)

func test_sever_updates_capabilities_and_stump_bleeds() -> void:
	var s := H.humanoid()
	var log := H.SignalLog.new(); log.connect_all(s)
	var r := s.receive(DamagePacket.make(&"arm_r", {T.CUT: 30.0}), H.rng())  # 機率 = 1
	assert_true(r.hits[0].severed)
	assert_eq(s.status_of(&"arm_r"), S.SEVERED)
	assert_eq(log.of("severed"), [["severed", &"arm_r", PackedStringArray(["arm_r"])]])
	assert_eq(log.of("disabled").size(), 0, "severing does not also fire disabled")
	assert_eq(s.capabilities().count("grip_r"), 0)
	assert_eq(s.capabilities().count("grip"), 1)
	assert_near(s.get_part(&"chest").bleed_rate, 30.0 * AnatomyState.STUMP_BLEED_RATIO)
	assert_eq(s.get_part(&"arm_r").bleed_rate, 0.0, "severed part no longer bleeds")

func test_decapitation_cascades_children_and_kills() -> void:
	var s := H.humanoid()
	var log := H.SignalLog.new(); log.connect_all(s)
	assert_true(s.sever_part(&"head"))
	for pid in [&"head", &"eye_l", &"eye_r", &"jaw"]:
		assert_eq(s.status_of(pid), S.SEVERED, String(pid))
	var sev: Array = log.of("severed")
	assert_eq(sev.size(), 1)
	assert_eq(Array(sev[0][2]).size(), 4)
	assert_eq(s.capabilities().count("vision"), 0)
	assert_true(s.is_dead)
	assert_eq(log.of("died"), [["died", &"head"]])

func test_non_detachable_parts_cannot_be_severed() -> void:
	var s := H.humanoid()
	for pid in [&"spine", &"heart", &"chest", &"neck"]:
		assert_false(s.sever_part(pid), String(pid))

func test_dependency_propagation_spine_disables_legs() -> void:
	var s := H.humanoid()
	var log := H.SignalLog.new(); log.connect_all(s)
	s.receive(H.no_sever(&"spine", {T.CRUSH: 40.0}), H.rng())
	assert_eq(s.status_of(&"spine"), S.DISABLED)
	assert_eq(s.status_of(&"leg_l"), S.DISABLED)
	assert_eq(s.get_part(&"leg_l").hp, 40.0, "legs themselves undamaged")
	assert_eq(s.capabilities().count("locomotion"), 0)
	var reasons := {}
	for e in log.of("disabled"):
		reasons[e[1]] = e[2]
	assert_eq(reasons.get(&"leg_l"), "dependency")
	assert_eq(reasons.get(&"spine"), "hp")
	# 修復脊椎後雙腿恢復
	assert_true(s.restore_part(&"spine"))
	assert_eq(s.capabilities().count("locomotion"), 2)

func test_vital_rules_instant_death_and_countdown() -> void:
	var heart := BodyPartDef.new(); heart.id = &"heart"; heart.max_hp = 10; heart.is_internal = true; heart.parent_id = &"torso"; heart.vital = BodyPartDef.VitalRule.INSTANT_DEATH
	var lungs := BodyPartDef.new(); lungs.id = &"lungs"; lungs.max_hp = 10; lungs.is_internal = true; lungs.parent_id = &"torso"; lungs.vital = BodyPartDef.VitalRule.COUNTDOWN
	var torso := BodyPartDef.new(); torso.id = &"torso"; torso.max_hp = 500; torso.internal_parts = PackedStringArray(["lungs"])
	var p := AnatomyProfile.new(); p.id = &"t"; p.parts = [torso, heart, lungs] as Array[BodyPartDef]
	var s := AnatomyState.from_profile(p)
	var log := H.SignalLog.new(); log.connect_all(s)
	s.receive(H.no_sever(&"torso", {T.PIERCE: 40.0}), H.rng())  # 貫穿 20 → 肺 hp 10 - 12 → 0
	assert_eq(log.of("vital"), [["vital", &"lungs", BodyPartDef.VitalRule.COUNTDOWN]])
	assert_false(s.is_dead, "countdown does not kill immediately")
	torso.internal_parts = PackedStringArray(["heart"])
	s.receive(H.no_sever(&"torso", {T.PIERCE: 40.0}), H.rng())
	assert_true(s.is_dead)
	assert_eq(log.of("died"), [["died", &"heart"]])
	# 死亡後不再接受傷害
	var hp_before := s.get_part(&"torso").hp
	s.receive(H.no_sever(&"torso", {T.CUT: 10.0}), H.rng())
	assert_eq(s.get_part(&"torso").hp, hp_before)

func test_multi_armed_keeps_fighting_with_remaining_arms() -> void:
	var s := H.multi_armed()
	var two_hand_attack := {"grip": 2}
	var one_hand_attack := {"grip": 1}
	var bite_attack := {"bite": 1}
	assert_eq(s.capabilities().count("grip"), 6)
	s.sever_part(&"arm_l1")
	s.sever_part(&"arm_r1")
	assert_eq(s.capabilities().count("grip"), 4)
	assert_true(s.capabilities().satisfies(two_hand_attack))
	for pid in [&"arm_l2", &"arm_r2", &"arm_l3"]:
		s.sever_part(pid)
	assert_false(s.capabilities().satisfies(two_hand_attack), "one arm left")
	assert_true(s.capabilities().satisfies(one_hand_attack))
	s.sever_part(&"arm_r3")
	assert_false(s.capabilities().satisfies(one_hand_attack))
	assert_true(s.capabilities().satisfies(bite_attack), "falls back to biting")
	assert_false(s.is_dead)

func test_restore_severed_arm_requires_attached_parent() -> void:
	var s := H.humanoid()
	var log := H.SignalLog.new(); log.connect_all(s)
	s.sever_part(&"arm_l")
	assert_true(s.restore_part(&"arm_l"))
	assert_eq(s.status_of(&"arm_l"), S.INTACT)
	assert_eq(s.capabilities().count("grip"), 2)
	assert_eq(log.of("restored"), [["restored", &"arm_l"]])
	# 父部位仍斷離時，無法單獨修復子部位
	var upper := BodyPartDef.new(); upper.id = &"upper"; upper.parent_id = &"torso"; upper.detachable = true
	var hand := BodyPartDef.new(); hand.id = &"hand"; hand.parent_id = &"upper"; hand.detachable = true; hand.functions = PackedStringArray(["grip"])
	var torso := BodyPartDef.new(); torso.id = &"torso"
	var p := AnatomyProfile.new(); p.id = &"t"; p.parts = [torso, upper, hand] as Array[BodyPartDef]
	var s2 := AnatomyState.from_profile(p)
	s2.sever_part(&"upper")
	assert_eq(s2.status_of(&"hand"), S.SEVERED, "child cascades")
	assert_false(s2.restore_part(&"hand"), "parent still severed")
	assert_true(s2.restore_part(&"upper"), "restore parent with children")
	assert_eq(s2.capabilities().count("grip"), 1)

func test_save_roundtrip() -> void:
	var s := H.humanoid()
	s.receive(H.no_sever(&"arm_l", {T.CUT: 10.0, T.BURN: 2.0}), H.rng())
	s.sever_part(&"arm_r")
	s.receive(H.no_sever(&"leg_l", {T.MUTATION: 30.0}), H.rng())
	s.receive(H.no_sever(&"spine", {T.CRUSH: 40.0}), H.rng())
	var data := s.to_save()
	var json := JSON.stringify(data)  # 必須能序列化成 JSON
	var loaded := AnatomyState.from_save(load(H.HUMANOID), JSON.parse_string(json))
	for pid in s.part_ids():
		var a := s.get_part(pid)
		var b := loaded.get_part(pid)
		assert_near(b.hp, a.hp, 0.0001, "%s hp" % pid)
		assert_eq(b.status(), a.status(), "%s status" % pid)
		assert_near(b.bleed_rate, a.bleed_rate, 0.0001, "%s bleed" % pid)
		assert_near(b.mutation, a.mutation, 0.0001, "%s mutation" % pid)
		for t in DamageTypes.ALL:
			assert_near(b.injury(t), a.injury(t), 0.0001, "%s injury %d" % [pid, t])
	assert_true(loaded.capabilities().equals(s.capabilities()))

func test_save_forward_compatibility() -> void:
	# 舊存檔缺少新部位、或含有已移除的部位，都不能讓讀檔失敗。
	var data := {"version": 1, "profile_id": "humanoid", "parts": {
		"arm_l": {"hp": 5.0, "severed": false},
		"tail": {"hp": 1.0, "severed": true},
	}}
	var s := AnatomyState.from_save(load(H.HUMANOID), data)
	assert_near(s.get_part(&"arm_l").hp, 5.0)
	assert_eq(s.status_of(&"leg_l"), S.INTACT)
	assert_eq(s.get_part(&"tail"), null)
