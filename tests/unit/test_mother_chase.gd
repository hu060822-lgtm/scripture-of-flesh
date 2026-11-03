extends TestCase
## 母親追逐戰（強化版）：破牆、東梯被肉封住、只有逃上高台才算逃掉、距離連動速度、撲抓預備可翻滾閃開、
## 第一次被抓掙脫後少一條手臂而且她繼續追、第二次被抓會死、追逐音樂、燈熄滅、肉塊、畫面壓迫、庭院敵人縮著不動。

const SAVE := "user://test_mother_chase.json"

func _game() -> PrologueGame:
	var g := PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = SAVE
	tree.root.add_child(g)
	g.start_game("new")
	return g

func _cleanup_save() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)

func _pc(g: PrologueGame) -> CombatComponent:
	return g.player.get_node("CombatComponent")

## 拿著鑰匙站在聖器室，讓追逐開始並跳過破牆的愣住時間。
func _start(g: PrologueGame) -> MotherChase:
	var mc := g.mother_chase
	(g.player.get_node("PlayerData") as PlayerData).inventory.add("umbilical_key")
	g.player.global_position = Vector3(26, 0, -40)
	mc.advance(0.05)
	assert_true(mc.active, "chase starts")
	var wall := g.level.get_node("Secrets/SecretWall_MotherNook") as SecretWall
	wall._physics_process(0.016)
	for c in wall.get_children():
		if c is CollisionShape3D:
			c.disabled = true  # open() 用 set_deferred；測試沒有影格，直接關掉碰撞
	mc.advance(MotherChase.STARTUP_SECONDS + 0.01)
	assert_eq(mc.phase, MotherChase.Phase.CHASE)
	return mc

## 把她放在玩家身旁並讓她預備、撲出。
func _lunge_at_player(mc: MotherChase, g: PrologueGame, gap: float = 2.0) -> void:
	mc.mother.global_position = g.player.global_position + Vector3(gap, 0, 0)
	mc.advance(0.02)
	assert_eq(mc.phase, MotherChase.Phase.WINDUP, "close enough → windup first, never an instant grab")
	var t := 0.0
	while t < MotherChase.WINDUP_SECONDS + 0.02:
		mc.mother.global_position = g.player.global_position + Vector3(gap, 0, 0)
		mc.advance(0.02)
		t += 0.02
	assert_eq(mc.phase, MotherChase.Phase.LUNGE)

func _until_hold(mc: MotherChase) -> void:
	var t := 0.0
	while mc.phase == MotherChase.Phase.LUNGE and t < 1.0:
		mc.advance(0.02)
		t += 0.02

func test_burst_blocks_the_east_stairs_and_only_the_terrace_is_safe() -> void:
	var g := _game()
	var mc := g.mother_chase
	var wall: SecretWall = g.level.get_node("Secrets/SecretWall_MotherNook")
	mc.advance(0.1)
	assert_false(mc.active, "nothing before the key")
	var key: ItemPickup = g.level.get_node("Interactables/Item_item_umbilical_key")
	g.player.global_position = key.global_position
	assert_true(key.interact(g.player))
	mc.advance(0.1)
	assert_true(mc.active, "chase starts")
	assert_false(mc.mother.has_node("BossPhase"), "apparition is not the real boss")
	wall._physics_process(0.016)
	assert_true(wall.is_open, "nook wall breaks open")
	assert_true(mc.barrier != null and is_instance_valid(mc.barrier), "flesh seals the east stairs")
	assert_true(mc.barrier.global_position.distance_to(Vector3(8.5, 0, -37)) < 0.5)
	assert_true(AudioManager.played_ids().has(&"mother_wall_burst"), "wall burst sound")
	# 跑回庭院已經不夠了（舊版在這裡就結束）
	g.player.global_position = Vector3(5, 0, -40)
	mc.advance(0.05)
	assert_true(mc.active, "the courtyard floor is not safe any more")
	assert_false(mc.is_safe(Vector3(8.5, 1.0, -33)), "halfway up the stairs is not safe")
	# 高台（祭壇那層）才安全
	g.player.global_position = Vector3(-4.5, 2.0, -29.0)
	mc.advance(0.05)
	assert_false(mc.active)
	assert_eq(mc.end_reason, &"escaped")
	assert_true(GameState.has_flag(MotherChase.DONE_FLAG))
	assert_eq(mc.phase, MotherChase.Phase.RETREAT, "the cord drags her back")
	for i in 200:
		mc.advance(0.05)
	assert_eq(mc.mother, null, "pulled back along her trail and gone")
	assert_false(g.boss == null, "the real boss still waits in the chapel")
	_cleanup_save()

func test_speed_keeps_her_a_few_metres_behind() -> void:
	assert_near(MotherChase.speed_for_gap(1.0), MotherChase.SPEED_NEAR, 0.001, "slower than you when right behind")
	assert_near(MotherChase.speed_for_gap(20.0), MotherChase.SPEED_FAR, 0.001, "faster than you when far")
	assert_true(MotherChase.SPEED_NEAR < 4.2 and MotherChase.SPEED_FAR > 4.2, "player runs 4.2")
	# 平衡點（速度 = 玩家速度）落在撲擊距離內：直線跑也會被撲
	var eq := 0.0
	for i in 200:
		var d := i * 0.05
		if MotherChase.speed_for_gap(d) >= 4.2:
			eq = d
			break
	assert_true(eq > MotherChase.GRAB_RANGE and eq < MotherChase.LUNGE_RANGE, "equilibrium gap %.2f" % eq)

func test_dodge_through_the_lunge_and_she_slams_the_floor() -> void:
	var g := _game()
	var mc := _start(g)
	_lunge_at_player(mc, g)
	assert_true(_pc(g).dodge(Vector3(-1, 0, 0)), "roll")
	var t := 0.0
	while t < MotherChase.LUNGE_SECONDS + 0.05 and mc.phase == MotherChase.Phase.LUNGE:
		mc.advance(0.02)
		t += 0.02
		if t < 0.25:
			mc.mother.global_position = g.player.global_position + Vector3(0.5, 0, 0)  # 撲到身上，但翻滾無敵
	assert_eq(mc.catches, 0, "i-frames beat the grab")
	assert_eq(mc.phase, MotherChase.Phase.RECOVER, "missed → slams down")
	_cleanup_save()

func test_first_catch_struggle_costs_an_arm_and_she_keeps_coming() -> void:
	var g := _game()
	var mc := _start(g)
	_lunge_at_player(mc, g)
	_until_hold(mc)
	assert_eq(mc.phase, MotherChase.Phase.HOLD, "caught")
	assert_eq(mc.catches, 1)
	assert_false(mc.is_lethal(), "first catch is not lethal")
	assert_false(g.player.get_node("PlayerController").input_enabled, "held: no control")
	var before := g.player.global_position
	for i in MotherChase.STRUGGLE_PRESSES:
		mc.struggle()
		mc.advance(0.1)
	assert_true(mc.phase != MotherChase.Phase.HOLD, "mashing E breaks free")
	assert_true(g.player.get_node("PlayerController").input_enabled, "control returns")
	var st := _pc(g).anatomy.state
	assert_true(st.get_part(&"arm_l").severed or st.get_part(&"arm_r").severed, "she tore an arm off")
	assert_false(_pc(g).is_dead())
	assert_true(mc.active, "she does not retreat after the first catch")
	assert_false(GameState.has_flag(MotherChase.DONE_FLAG))
	assert_true(mc.gap() > 1.9, "thrown clear of her (%.2f)" % mc.gap())
	assert_true(before != Vector3.INF)
	_cleanup_save()

func test_not_struggling_still_releases_after_the_hold() -> void:
	var g := _game()
	var mc := _start(g)
	_lunge_at_player(mc, g)
	_until_hold(mc)
	assert_eq(mc.phase, MotherChase.Phase.HOLD)
	var t := 0.0
	while t < MotherChase.HOLD_SECONDS + 0.2:
		mc.advance(0.05)
		t += 0.05
	assert_true(mc.phase != MotherChase.Phase.HOLD, "released after HOLD_SECONDS even without mashing")
	assert_false(_pc(g).is_dead())
	_cleanup_save()

func test_second_catch_kills_and_the_chase_replays() -> void:
	var g := _game()
	var mc := _start(g)
	_lunge_at_player(mc, g)
	_until_hold(mc)
	for i in MotherChase.STRUGGLE_PRESSES:
		mc.struggle()
		mc.advance(0.05)
	assert_eq(mc.catches, 1)
	# 等她恢復，再撲一次
	var t := 0.0
	while (mc.phase != MotherChase.Phase.CHASE or mc._lunge_cd > 0.0) and t < 5.0:
		g.player.global_position = mc.mother.global_position + Vector3(-8, 0, 0)  # 先拉開，讓她追
		mc.advance(0.05)
		t += 0.05
	_lunge_at_player(mc, g)
	_until_hold(mc)
	assert_eq(mc.catches, 2)
	assert_true(mc.is_lethal(), "second catch is lethal")
	var presses_before := mc.presses
	mc.struggle()
	assert_eq(mc.presses, presses_before, "struggling does nothing now")
	t = 0.0
	while not _pc(g).is_dead() and t < MotherChase.LETHAL_HOLD + 0.5:
		mc.advance(0.05)
		t += 0.05
	assert_true(_pc(g).is_dead(), "dragged into the wall")
	assert_false(GameState.has_flag(MotherChase.DONE_FLAG), "not done → replays after respawn")
	_cleanup_save()

func test_music_goes_chase_then_near_then_silent_right_behind_you() -> void:
	var g := _game()
	var mc := _start(g)
	var dir: AudioDirector = AudioManager.director
	mc.mother.global_position = g.player.global_position + Vector3(8, 0, 0)
	assert_eq(dir.compute_music_state(), &"chase")
	mc.mother.global_position = g.player.global_position + Vector3(4, 0, 0)
	assert_eq(dir.compute_music_state(), &"chase_near")
	mc.mother.global_position = g.player.global_position + Vector3(1.8, 0, 0)
	assert_eq(dir.compute_music_state(), &"chase_hush", "music drops out when she is right behind")
	mc.mother.global_position = g.player.global_position + Vector3(2.5, 0, 0)
	assert_eq(dir.compute_music_state(), &"chase_hush", "hysteresis: stays silent until she backs off")
	for st in [&"chase", &"chase_near", &"chase_hush"]:
		assert_true(MusicMixer.MIXES.has(st), "mix for %s" % st)
		for stem in MusicMixer.MIXES[st]:
			assert_true(ResourceLoader.exists("res://audio/music/stems/%s.ogg" % stem), "stem %s exists" % stem)
	_cleanup_save()

func test_candles_die_as_she_passes_and_come_back_after() -> void:
	var g := _game()
	var mc := _start(g)
	var candle: OmniLight3D = g.level.get_node("Lights/ChaseCandle_3")
	var e0 := candle.light_energy
	assert_true(e0 > 0.0)
	g.player.global_position = Vector3(0, 0, -40)  # 遠一點，不讓她撲
	mc.mother.global_position = Vector3(candle.global_position.x, 0, candle.global_position.z)
	for i in 15:
		mc.advance(0.05)
		mc.mother.global_position = Vector3(candle.global_position.x, 0, candle.global_position.z)
	assert_near(candle.light_energy, 0.0, 0.001, "candle is out")
	assert_true(mc.dark_lights() >= 1)
	assert_true(AudioManager.played_ids().has(&"light_die"))
	g.player.global_position = Vector3(-4.5, 2.0, -29.0)
	for i in 300:
		mc.advance(0.05)
	assert_near(candle.light_energy, e0, 0.01, "lights come back after she is gone")
	_cleanup_save()

func test_trail_grows_flesh_and_a_cord_follows_her() -> void:
	var g := _game()
	for e in g.level.find_children("*", "CharacterBody3D", true, false):
		if e.has_node("EnemyAI") and e.global_position.x > 12.0:
			e.free()  # 聖器室的多手人擋在路上（測試裡沒有物理影格，不會滑開）
	var mc := _start(g)
	mc.mother.global_position = Vector3(27, 0, -40)  # 已經出了壁龕（測試裡破牆的碰撞要到下一個影格才會關）
	g.player.global_position = Vector3(0, 0, -40)
	var t := 0.0
	while t < 3.0 and mc.active:
		mc.advance(0.05)
		t += 0.05

	assert_true(mc.trail.size() > 4, "footprints recorded (%d)" % mc.trail.size())
	assert_true(mc.flesh.size() > 1, "flesh lumps along the way")
	assert_true(mc.cord != null and (mc.cord.mesh as ImmediateMesh).get_surface_count() == 2, "umbilical cord drawn")
	assert_true(mc.hum != null, "she hums (positional)")
	_cleanup_save()

func test_courtyard_enemies_cower_during_the_chase() -> void:
	var g := _game()
	var spawn: EnemySpawn = g.level.get_node("Spawns/Spawn_courtyard_reverse_1")
	var mc := _start(g)
	assert_true(mc.cowering.size() >= 1, "someone cowers")
	var e: Node = mc.cowering[0]
	assert_eq(e.get_node("EnemyAI").process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(e.get_node("CreatureAnimator").override_clip, &"block")
	g.player.global_position = Vector3(-4.5, 2.0, -29.0)
	mc.advance(0.05)
	assert_eq(e.get_node("EnemyAI").process_mode, Node.PROCESS_MODE_INHERIT, "back to normal after")
	assert_true(spawn != null)
	_cleanup_save()

func test_dread_drives_the_screen_and_camera() -> void:
	var g := _game()
	var mc := _start(g)
	mc.mother.global_position = g.player.global_position + Vector3(8.5, 0, 0)
	var far := mc.dread()
	mc.mother.global_position = g.player.global_position + Vector3(2.6, 0, 0)
	var near := mc.dread()
	assert_true(near > far, "closer = more dread (%.2f > %.2f)" % [near, far])
	g._update_chase_fx()
	assert_near(g.injury.dread, near, 0.001, "overlay gets the dread")
	assert_true(g.injury.threat > 0.0, "direction cue")
	assert_true(g.rig.bias.length() > 0.1, "camera leans toward her")
	g.injury._apply(0.0)
	assert_true(g.injury.rect.visible, "overlay shown")
	var before := g.rig.trauma
	mc.stomped.emit(0.5)
	assert_true(g.rig.trauma > before, "stomps shake the camera")
	_cleanup_save()

func test_mother_has_chase_animation_clips() -> void:
	var prof := (load("res://content/enemies/walking_mother.tres") as EnemyDefinition)
	var e := EnemyFactory.create(prof, &"anim_check")
	tree.root.add_child(e)
	var anim: CreatureAnimator = e.get_node("CreatureAnimator")
	for clip in [&"chase_run", &"lunge_windup", &"lunge", &"grab_hold"]:
		assert_true(anim.tree.has_animation(clip), "has %s" % clip)
	anim.play_override(&"chase_run")
	assert_eq(anim.current_clip, &"chase_run")
	e.queue_free()
