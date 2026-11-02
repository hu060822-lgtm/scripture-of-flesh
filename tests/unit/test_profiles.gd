extends TestCase

const H := preload("res://tests/helpers.gd")

func test_humanoid_has_required_14_parts_and_is_valid() -> void:
	var p: AnatomyProfile = load(H.HUMANOID)
	assert_eq(p.validate().size(), 0, "validate errors: %s" % [p.validate()])
	for id in ["head", "eye_l", "eye_r", "jaw", "neck", "arm_l", "arm_r", "chest", "abdomen", "heart", "lungs", "spine", "leg_l", "leg_r"]:
		assert_true(p.has_part(StringName(id)), "missing %s" % id)
	assert_eq(p.parts.size(), 14)

func test_multi_armed_is_valid_with_six_arms() -> void:
	var p: AnatomyProfile = load(H.MULTI_ARMED)
	assert_eq(p.validate().size(), 0, "validate errors: %s" % [p.validate()])
	var arms := p.parts.filter(func(d): return d.functions.has("arm"))
	assert_eq(arms.size(), 6)

func test_validate_catches_bad_data() -> void:
	var a := BodyPartDef.new(); a.id = &"a"; a.dependencies = PackedStringArray(["b"])
	var b := BodyPartDef.new(); b.id = &"b"; b.dependencies = PackedStringArray(["a"])
	var c := BodyPartDef.new(); c.id = &"c"; c.parent_id = &"missing"
	var d := BodyPartDef.new(); d.id = &"c"
	var e := BodyPartDef.new(); e.id = &"e"; e.resistances = {"SLASH": 0.5}
	var p := AnatomyProfile.new()
	p.parts = [a, b, c, d, e] as Array[BodyPartDef]
	var errs := " | ".join(p.validate())
	assert_true(errs.contains("duplicate part id: c"), errs)
	assert_true(errs.contains("missing parent missing"), errs)
	assert_true(errs.contains("dependency cycle"), errs)
	assert_true(errs.contains("unknown resistance key SLASH"), errs)

func test_parts_are_not_hardcoded_creature_can_lack_parts() -> void:
	# 一個只有軀幹與一條腿的生物也必須能運作。
	var torso := BodyPartDef.new(); torso.id = &"torso"; torso.max_hp = 20
	var leg := BodyPartDef.new(); leg.id = &"leg"; leg.parent_id = &"torso"; leg.detachable = true; leg.functions = PackedStringArray(["locomotion"])
	var p := AnatomyProfile.new(); p.id = &"blob"; p.parts = [torso, leg] as Array[BodyPartDef]
	var s := AnatomyState.from_profile(p)
	assert_eq(s.capabilities().count("locomotion"), 1)
	assert_true(s.sever_part(&"leg"))
	assert_eq(s.capabilities().count("locomotion"), 0)
