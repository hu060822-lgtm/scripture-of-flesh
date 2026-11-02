extends TestCase
## 損傷計算：護甲、抗性、出血、八種損傷規則、斷肢機率、穿刺貫穿。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _single_part_profile(armor: float = 0.0) -> AnatomyState:
	var d := BodyPartDef.new(); d.id = &"limb"; d.max_hp = 30; d.armor = armor; d.detachable = true
	var p := AnatomyProfile.new(); p.id = &"test"; p.parts = [d] as Array[BodyPartDef]
	return AnatomyState.from_profile(p)

func test_armor_flat_reduction_and_penetration() -> void:
	var s := _single_part_profile(5.0)
	var r := DamageResolver.resolve(s, H.no_sever(&"limb", {T.CUT: 10.0}), H.rng())
	assert_near(r.hits[0].hp_loss, 5.0, 0.0001, "armor 5 vs cut 10")
	var pkt := H.no_sever(&"limb", {T.CUT: 10.0}); pkt.armor_penetration = 1.0
	r = DamageResolver.resolve(s, pkt, H.rng())
	assert_near(r.hits[0].hp_loss, 10.0, 0.0001, "full penetration")

func test_resistance_by_type_name() -> void:
	var s := H.humanoid()  # 胸腔 CUT 抗性 0.8
	var r := DamageResolver.resolve(s, H.no_sever(&"chest", {T.CUT: 10.0}), H.rng())
	assert_near(r.hits[0].hp_loss, 8.0)

func test_resolver_does_not_mutate_state() -> void:
	var s := H.humanoid()
	DamageResolver.resolve(s, DamagePacket.make(&"arm_r", {T.CUT: 30.0}), H.rng())
	assert_eq(s.get_part(&"arm_r").hp, 30.0)
	assert_false(s.get_part(&"arm_r").severed)

func test_cut_and_laceration_cause_bleeding() -> void:
	var s := H.humanoid()
	s.receive(H.no_sever(&"arm_l", {T.CUT: 10.0}), H.rng())
	assert_near(s.get_part(&"arm_l").bleed_rate, 1.0)
	s.receive(H.no_sever(&"leg_l", {T.LACERATION: 10.0}), H.rng())
	assert_near(s.get_part(&"leg_l").bleed_rate, 1.5)
	assert_near(s.total_bleed_rate(), 2.5)
	assert_near(s.tick(2.0), 5.0, 0.0001, "blood lost over 2s")

func test_burn_cauterizes_and_causes_necrosis_over_time() -> void:
	var s := H.humanoid()
	s.receive(H.no_sever(&"arm_l", {T.CUT: 10.0}), H.rng())
	s.receive(H.no_sever(&"arm_l", {T.BURN: 5.0}), H.rng())
	var arm := s.get_part(&"arm_l")
	assert_near(arm.bleed_rate, 0.5, 0.0001, "burn reduces bleeding")
	assert_near(arm.injury(T.NECROSIS), 1.0, 0.0001, "burn -> necrosis")
	assert_near(arm.hp, 15.5)
	s.tick(10.0)
	assert_near(arm.hp, 15.0, 0.0001, "necrosis drains hp over time")

func test_crush_deals_heavy_part_damage() -> void:
	var s := H.humanoid()
	s.receive(H.no_sever(&"arm_l", {T.CRUSH: 10.0}), H.rng())
	assert_near(s.get_part(&"arm_l").hp, 17.0)

func test_fracture_disables_function_without_zero_hp_or_severing() -> void:
	var s := H.humanoid()
	var log := H.SignalLog.new(); log.connect_all(s)
	s.receive(H.no_sever(&"arm_r", {T.FRACTURE: 16.0}), H.rng())
	var arm := s.get_part(&"arm_r")
	assert_true(arm.hp > 0.0, "hp still above zero")
	assert_eq(arm.status(), AnatomyTypes.PartStatus.DISABLED)
	assert_false(arm.severed)
	assert_eq(log.of("disabled"), [["disabled", &"arm_r", "fracture"]])
	assert_eq(s.capabilities().count("grip_r"), 0)

func test_mutation_ignores_armor_and_hp_and_sets_mutated_status() -> void:
	var s := _single_part_profile(100.0)
	s.receive(H.no_sever(&"limb", {T.MUTATION: 60.0}), H.rng())
	var limb := s.get_part(&"limb")
	assert_eq(limb.hp, 30.0)
	assert_near(limb.mutation, 60.0)
	assert_eq(limb.status(), AnatomyTypes.PartStatus.MUTATED)
	assert_true(limb.is_functional(), "mutated part still works")

func test_sever_chance_formula() -> void:
	var s := H.humanoid()
	# 手臂 30 HP：切割 10 → 剩 20，缺損 1/3；分數 10/30 → 機率 1/9
	var r := DamageResolver.resolve(s, DamagePacket.make(&"arm_l", {T.CUT: 10.0}), H.rng())
	assert_near(r.hits[0].sever_chance, 1.0 / 9.0)
	# 穿刺沒有斷肢分數
	r = DamageResolver.resolve(s, DamagePacket.make(&"arm_l", {T.PIERCE: 50.0}), H.rng())
	assert_eq(r.hits[0].sever_chance, 0.0)
	# 不可斷離的部位永遠是 0
	r = DamageResolver.resolve(s, DamagePacket.make(&"spine", {T.CUT: 500.0}), H.rng())
	assert_eq(r.hits[0].sever_chance, 0.0)
	assert_false(r.hits[0].severed)

func test_weapon_sever_power_scales_chance() -> void:
	var s := H.humanoid()
	var pkt := DamagePacket.make(&"arm_l", {T.CUT: 10.0}); pkt.sever_power = 3.0
	var r := DamageResolver.resolve(s, pkt, H.rng())
	assert_near(r.hits[0].sever_chance, 1.0 / 3.0)

func test_sever_roll_is_statistically_close_to_chance() -> void:
	var s := H.humanoid()
	var rng := H.rng(42)
	var severed := 0
	for i in 3000:
		if DamageResolver.resolve(s, DamagePacket.make(&"arm_l", {T.CUT: 10.0}), rng).hits[0].severed:
			severed += 1
	assert_near(severed / 3000.0, 1.0 / 9.0, 0.02, "observed sever rate")

func test_pierce_passes_through_to_internal_organ() -> void:
	var s := H.humanoid()
	var r := DamageResolver.resolve(s, H.no_sever(&"chest", {T.PIERCE: 20.0}), H.rng(7))
	assert_eq(r.hits.size(), 2)
	var inner := r.hits[1]
	assert_true(inner.pass_through)
	assert_true(inner.part_id in [&"heart", &"lungs"], "inner hit %s" % inner.part_id)
	assert_near(inner.hp_loss, 20.0 * DamageTypes.PIERCE_PASS_THROUGH * DamageTypes.HP_FACTOR[T.PIERCE])

func test_internal_and_severed_parts_cannot_be_targeted() -> void:
	var s := H.humanoid()
	assert_true(DamageResolver.resolve(s, DamagePacket.make(&"heart", {T.CUT: 5.0}), H.rng()).rejected)
	assert_true(DamageResolver.resolve(s, DamagePacket.make(&"tail", {T.CUT: 5.0}), H.rng()).rejected)
	s.sever_part(&"arm_l")
	assert_true(DamageResolver.resolve(s, DamagePacket.make(&"arm_l", {T.CUT: 5.0}), H.rng()).rejected)
	assert_false(&"heart" in s.targetable_part_ids())
	assert_false(&"arm_l" in s.targetable_part_ids())
