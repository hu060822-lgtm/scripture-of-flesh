extends TestCase
## 序章趣味性改進（提案 A／B／C／H）：
## B 阿格妮絲縫的手臂必定相容；A 殘肢可以撿起來當道具（掌紋鎖、隱藏經文、丟出去引開敵人）；
## C 無面觀察者被看著就定住、縫屍者幫同伴縫回殘肢；H 砍斷臍帶讓母親踉蹌並延後生產。

const T := DamageTypes.Type
const H := preload("res://tests/helpers.gd")

func _enemy(id: String, pos: Vector3, yaw: float = PI) -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % id), StringName(id + "_%d" % randi()))
	tree.root.add_child(e)
	e.global_position = pos
	e.rotation.y = yaw
	return e

func _player(pos: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var p := PlayerFactory.create()
	tree.root.add_child(p)
	p.global_position = pos
	return p

func _data(p: Node) -> PlayerData: return p.get_node("PlayerData")
func _ai(e: Node) -> EnemyAI: return e.get_node("EnemyAI")

func _step(ais: Array, seconds: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		for ai in ais:
			ai.advance(dt)
			ai.combat.advance(dt)
		t += dt

func _gibs() -> Array:
	return tree.root.get_children().filter(func(n): return n is SeveredPart and not n.is_queued_for_deletion())

# ---------- B ----------

func test_agnes_arm_is_guaranteed_even_with_low_tec() -> void:
	var o := OrganRegistry.get_organ(&"agnes_arm")
	assert_true(o != null, "agnes_arm registered")
	assert_true(o.guaranteed)
	var p := _player()
	var prog: ProgressionComponent = p.get_node("ProgressionComponent")
	prog.stats.TEC = 4
	assert_eq(TransplantService.compatibility(o, prog), 1.0)
	var st := (p.get_node("CombatComponent") as CombatComponent).anatomy.state
	var pred := TransplantService.predict(o, &"arm_l", st, prog, null)
	assert_eq(pred.compatibility, 1.0)
	var res := TransplantService.perform(o, &"arm_l", st, prog, null, H.rng(7))
	assert_false(res.rejected, "never rejected")
	assert_eq(st.organs.get(&"arm_l"), &"agnes_arm")
	assert_eq((p.get_node("ModelSkinner") as ModelSkinner).variants.get(&"arm_l"), &"stitched_arm", "uses stitched look")

func test_item_pickup_hint_is_appended() -> void:
	var p := _player()
	var it := ItemPickup.new()
	it.item_id = "organ:agnes_arm"
	it.hint_text = "在祭壇按 T 移植"
	tree.root.add_child(it)
	var msgs := []
	_data(p).message.connect(func(m): msgs.append(m))
	assert_true(it.interact(p))
	assert_eq(_data(p).inventory.count("organ:agnes_arm"), 1)
	assert_true(String(msgs[-1]).contains("在祭壇按 T 移植"))

# ---------- A ----------

func test_useful_severed_parts_become_relics() -> void:
	assert_eq(LimbRelic.item_for(&"multi_armed", &"arm_l2"), LimbRelic.HAND)
	assert_eq(LimbRelic.item_for(&"faceless", &"stalk_3"), LimbRelic.EYE)
	assert_eq(LimbRelic.item_for(&"reverse_legged", &"leg_r"), LimbRelic.LEG)
	assert_eq(LimbRelic.item_for(&"humanoid", &"arm_l"), "", "the player's own arm is not a relic")
	assert_eq(LimbRelic.item_for(&"multi_armed", &"head"), "")
	var p := _player()
	var e := _enemy("many_hands", Vector3(0, 0, -1.5))
	(e.get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"arm_l1")
	var gibs := _gibs()
	assert_eq(gibs.size(), 1)
	var g: SeveredPart = gibs[0]
	assert_true(g.keep, "relic limbs do not despawn")
	var relic := g.get_node_or_null("LimbRelic") as LimbRelic
	assert_true(relic != null)
	g.freeze = true
	g.global_position = p.global_position + Vector3(0.6, 0, 0)
	assert_true(relic.in_range(p))
	assert_true((p.get_node("PlayerController") as PlayerController).interact(), "E picks it up")
	assert_eq(_data(p).inventory.count(LimbRelic.HAND), 1)
	assert_true(g.is_queued_for_deletion())

func test_kept_relics_survive_the_gib_limit() -> void:
	var parent := Node3D.new()
	tree.root.add_child(parent)
	var keepers := []
	for i in SeveredPart.MAX_ACTIVE + 6:
		var g := SeveredPart.spawn(parent, Node3D.new(), Transform3D(), &"arm", &"x", Vector3.ZERO)
		if i < 3:
			g.keep = true
			keepers.append(g)
	for g in keepers:
		assert_false(g.is_queued_for_deletion(), "kept gib not culled")

func test_palm_lock_needs_a_severed_hand() -> void:
	var p := _player()
	var lock := PalmLock.new()
	lock.object_id = &"test_palm_lock"
	lock.rewards = {"blood_vial": 2, "organ:many_hands_heart": 1}
	tree.root.add_child(lock)
	GameState.taken.erase(&"test_palm_lock")
	assert_false(lock.interact(p), "locked without a hand")
	assert_true(lock.available(), "still usable later")
	_data(p).inventory.add(LimbRelic.HAND)
	assert_true(lock.interact(p))
	assert_eq(_data(p).inventory.count(LimbRelic.HAND), 0, "hand consumed")
	assert_eq(_data(p).inventory.count("blood_vial"), 2)
	assert_eq(_data(p).inventory.count("organ:many_hands_heart"), 1)
	assert_false(lock.available(), "opened once")
	assert_false(lock.get_node("Door").visible)
	GameState.taken.erase(&"test_palm_lock")

func test_hidden_scripture_needs_a_watcher_eye() -> void:
	var p := _player()
	var hs := HiddenScripture.new()
	hs.dialogue_id = "hidden_scripture"
	tree.root.add_child(hs)
	hs.global_position = p.global_position + Vector3(0, 0, -1)
	hs._process(1.0)
	assert_false(hs.is_revealed())
	assert_false(hs.in_range(p), "cannot read without sight")
	_data(p).inventory.add(LimbRelic.EYE)
	hs._process(1.0)
	assert_true(hs.is_revealed())
	assert_true(hs.in_range(p))
	_data(p).inventory.remove(LimbRelic.EYE)
	assert_false(HiddenScripture.can_see(p))
	# 移植了觀察者之眼也看得見
	var st := (p.get_node("CombatComponent") as CombatComponent).anatomy.state
	var eye := OrganRegistry.get_organ(&"watcher_eye")
	var prog: ProgressionComponent = p.get_node("ProgressionComponent")
	var slot := StringName(eye.slots[0])
	st.replace_part_definition(slot, TransplantService.build_definition(eye, st.get_part(slot).def), &"watcher_eye")
	assert_true(HiddenScripture.can_see(p), "transplanted eye sees it")
	assert_true(&"hidden_scripture" in DialogueRunner.all_ids().map(func(i): return StringName(i)), "dialogue exists")

func test_secret_wall_opens_on_flag() -> void:
	var w := SecretWall.new()
	w.open_flag = &"test_secret_wall"
	tree.root.add_child(w)
	assert_false(w.is_open)
	GameState.set_flag(&"test_secret_wall")
	w._physics_process(0.016)
	assert_true(w.is_open)
	GameState.flags.erase(&"test_secret_wall")

func test_thrown_limb_lures_an_idle_enemy() -> void:
	var p := _player()
	_data(p).inventory.add(LimbRelic.LEG)
	var e := _enemy("stitcher", Vector3(0, 0, -14), 0.0)  # 背對玩家、聽不到
	var ai := _ai(e)
	_step([ai], 0.2)
	assert_eq(ai.runtime.target, null)
	var t := (p.get_node("PlayerController") as PlayerController).throw_limb()
	assert_true(t != null, "throws the leg")
	assert_eq(_data(p).inventory.count(LimbRelic.LEG), 0)
	assert_eq((p.get_node("PlayerController") as PlayerController).throw_limb(), null, "nothing left to throw")
	t.global_position = e.global_position + Vector3(3, 0, 0)
	t._land()
	assert_eq(ai.state(), &"search", "goes to look")
	assert_true(ai.runtime.investigate_point.distance_to(t.global_position) < 0.5)
	assert_true(t.get_node_or_null("LimbRelic") != null, "can be picked up again")

# ---------- C ----------

func test_watcher_freezes_while_watched_and_rushes_when_not() -> void:
	var p := _player(Vector3.ZERO)
	p.rotation.y = 0.0  # 面向 -Z
	var e := _enemy("faceless_watcher", Vector3(0, 0, -5))
	var ai := _ai(e)
	ai.runtime.target = p.get_node("CombatComponent")
	ai.runtime.last_known_position = p.global_position
	ai.force_state(&"chase")
	_step([ai], 0.1)
	assert_true(ai.frozen_by_gaze, "frozen when the player looks at it")
	var z0 := e.global_position.z
	ai._physics_process(0.1)
	assert_near(e.global_position.z, z0, 0.001, "does not move while watched")
	# 背對
	p.rotation.y = PI
	_step([ai], 0.1)
	assert_false(ai.frozen_by_gaze)
	assert_true(ai.definition.unwatched_speed_factor > 1.0)
	# 失明後不再受影響
	p.rotation.y = 0.0
	var st := ai.anatomy.state
	for i in range(1, 5):
		st.sever_part(StringName("stalk_%d" % i))
	_step([ai], 0.1)
	assert_false(ai.frozen_by_gaze, "blind watcher ignores gaze")

func test_other_enemies_never_freeze() -> void:
	var p := _player()
	var e := _enemy("stitcher", Vector3(0, 0, -3))
	var ai := _ai(e)
	ai.runtime.target = p.get_node("CombatComponent")
	_step([ai], 0.1)
	assert_false(ai.frozen_by_gaze)

func test_stitcher_carries_an_allys_limb_back() -> void:
	var p := _player(Vector3(0, 0, 12))
	var s := _enemy("stitcher", Vector3(0, 0, 0))
	var r := _enemy("reverse_legged", Vector3(3, 0, 0))
	var sai := _ai(s)
	var rai := _ai(r)
	rai.process_mode = Node.PROCESS_MODE_DISABLED
	var rst := rai.anatomy.state
	rst.sever_part(&"leg_l")
	var gibs := _gibs()
	assert_eq(gibs.size(), 1)
	gibs[0].freeze = true
	gibs[0].global_position = s.global_position + Vector3(0.5, 0, 0)
	assert_eq(RestitchLogic.find_limb(sai), gibs[0], "finds the ally's limb")
	sai.force_state(&"special")
	_step([sai], 0.2)
	assert_true(sai.runtime.carry_owner == rai.combat, "picked it up")
	assert_true(gibs[0].is_queued_for_deletion())
	# 走到同伴身邊（測試中直接移過去）再縫
	s.global_position = r.global_position + Vector3(0.8, 0, 0)
	_step([sai], RestitchLogic.CHANNEL_SECONDS + 0.3)
	assert_false(rst.get_part(&"leg_l").severed, "ally's leg sewn back")
	assert_true(sai.state() != &"special", "done sewing")
	assert_eq(sai.runtime.carry_owner, null)

func test_stitcher_without_hands_cannot_help_and_drops_carried_limb() -> void:
	var s := _enemy("stitcher", Vector3(0, 0, 0))
	var r := _enemy("reverse_legged", Vector3(3, 0, 0))
	var sai := _ai(s)
	_ai(r).process_mode = Node.PROCESS_MODE_DISABLED
	_ai(r).anatomy.state.sever_part(&"leg_l")
	var g: SeveredPart = _gibs()[0]
	g.freeze = true
	g.global_position = s.global_position + Vector3(0.5, 0, 0)
	sai.force_state(&"special")
	_step([sai], 0.2)
	assert_true(sai.runtime.carry_owner != null)
	# 被打中 → 殘肢掉回地上
	sai.interrupted = true
	_step([sai], 0.1)
	assert_eq(sai.runtime.carry_owner, null)
	var dropped := _gibs().filter(func(x): return x.part_id == &"leg_l")
	assert_eq(dropped.size(), 1, "limb dropped")
	assert_true(dropped[0].get_node_or_null("LimbRelic") != null, "still a relic")
	# 雙手都斷了就不會去撿同伴的殘肢
	sai.anatomy.state.sever_part(&"arm_l")
	sai.anatomy.state.sever_part(&"arm_r")
	for x in _gibs():
		if x.source_creature_id == sai.anatomy.creature_id:
			x.queue_free()
	assert_eq(RestitchLogic.find_limb(sai) == dropped[0], false, "no hands, no help")

# ---------- H ----------

func test_cutting_a_cord_staggers_her_and_slows_births() -> void:
	var b := BossFactory.create_mother()
	b.position = Vector3(0, 0, -4)
	tree.root.add_child(b)
	var bp: BossPhaseComponent = b.get_node("BossPhase")
	var c: CombatComponent = b.get_node("CombatComponent")
	bp.engage()
	assert_eq(bp.summon_interval(), BossPhaseComponent.SUMMON_INTERVAL)
	var cuts := []
	bp.cord_cut.connect(func(left): cuts.append(left))
	var before := bp.summon_timer
	c.anatomy.state.sever_part(&"cord_1")
	assert_eq(cuts, [2])
	assert_eq(c.action, CombatComponent.Action.STAGGER, "she reels")
	assert_near(bp.summon_timer, before + BossPhaseComponent.SUMMON_DELAY_PER_CORD, 0.001)
	assert_eq(bp.summon_interval(), BossPhaseComponent.SUMMON_INTERVAL + BossPhaseComponent.SUMMON_DELAY_PER_CORD)
	c.anatomy.state.sever_part(&"cord_2")
	assert_eq(cuts, [2, 1])
	assert_eq(bp.cords_lost(), 2)
