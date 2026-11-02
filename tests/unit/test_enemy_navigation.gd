extends TestCase
## AI-1：尋路（導航網格、跨房間）、視線遮擋、聲響調查、搜索、分離轉向、動畫／音效掛鉤訊號。

const GB := preload("res://game/greybox.gd")

func _enemy(id: String, pos: Vector3, yaw: float = PI) -> CharacterBody3D:
	var e := EnemyFactory.create(load("res://content/enemies/%s.tres" % id), StringName(id))
	e.position = pos
	e.rotation.y = yaw  # PI = 面向 +Z
	tree.root.add_child(e)
	var ai: EnemyAI = e.get_node("EnemyAI")
	ai.rng.seed = 7
	return e

func _player(pos: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var p := PlayerFactory.create()
	p.position = pos
	tree.root.add_child(p)
	return p

func _ai(e: Node) -> EnemyAI:
	return e.get_node("EnemyAI")

## 兩個房間：南房（z>0）與北房（z<0），中間一道 x 方向的牆，開口在 x=4（寬 2）。
func _two_rooms(with_nav: bool = true) -> Node3D:
	var lvl := Node3D.new()
	tree.root.add_child(lvl)
	var geo := Node3D.new()
	geo.name = "Geometry"
	lvl.add_child(geo)
	GB.floor_plane(geo, Vector3.ZERO, Vector2(12, 12))
	# 牆：x 從 -6 到 3（長 9）與 5 到 6（長 1），開口 3..5
	GB.box(geo, Vector3(-1.5, 2, 0), Vector3(9, 4, 0.5))
	GB.box(geo, Vector3(5.5, 2, 0), Vector3(1, 4, 0.5))
	if with_nav:
		LevelNavigation.bake(lvl, geo)
	return lvl

## 不經物理、直接依 desired_velocity 推進位置（測試路徑跟隨）。回傳經過的位置。
func _walk(ai: EnemyAI, seconds: float, dt: float = 0.05) -> Array[Vector3]:
	var trail: Array[Vector3] = []
	var t := 0.0
	while t < seconds:
		ai.advance(dt)
		ai.combat.advance(dt)
		ai.body().global_position += ai.desired_velocity * dt
		trail.append(ai.body().global_position)
		t += dt
	return trail

func test_navigator_falls_back_to_straight_line_without_navmesh() -> void:
	var e := _enemy("stitcher", Vector3(0, 0, 3))
	var ai := _ai(e)
	assert_false(AiNavigator.has_navigation(e), "no navmesh in empty world")
	var goal := Vector3(0, 0, -3)
	assert_eq(ai.navigator.next_point(e, goal), goal)

func test_path_goes_through_the_door_between_rooms() -> void:
	_two_rooms()
	var e := _enemy("stitcher", Vector3(-3, 0, 3))
	assert_true(AiNavigator.has_navigation(e), "navmesh baked")
	var goal := Vector3(-3, 0, -3)
	var ai := _ai(e)
	var straight := Vector3(-3, 0, 3).distance_to(goal)
	assert_true(AiNavigator.path_length(e, e.global_position, goal) > straight + 4.0, "detours via door")
	# 沿路徑走：穿過 z=0 時必須在開口內（x 介於 3 與 5）
	var prev := e.global_position
	var crossed_at := INF
	for i in 400:
		ai.move_towards(goal)
		ai.navigator.tick(0.05)
		e.global_position += ai.desired_velocity * 0.05
		var now := e.global_position
		if prev.z > 0.0 and now.z <= 0.0:
			crossed_at = now.x
		prev = now
		if now.distance_to(goal) < 0.3:
			break
	assert_true(crossed_at > 3.0 and crossed_at < 5.0, "crossed the wall through the door (x=%s)" % crossed_at)
	assert_true(e.global_position.distance_to(goal) < 0.5, "reached goal in the other room")

func test_walls_block_sight_but_open_space_does_not() -> void:
	var lvl := _two_rooms(false)
	var p := _player(Vector3(-3, 0, 2))
	var pc: CombatComponent = p.get_node("CombatComponent")
	var e := _enemy("stitcher", Vector3(-3, 0, -3))
	var ai := _ai(e)
	assert_false(ai.can_see(pc), "wall between")
	assert_false(ai.can_detect(pc), "cannot hear through wall at 5m either")
	lvl.get_node("Geometry").get_child(1).free()  # 拆掉長牆
	assert_true(ai.can_see(pc), "sees once the wall is gone")

func test_hearing_is_halved_through_walls() -> void:
	_two_rooms(false)
	var e := _enemy("stitcher", Vector3(-3, 0, -1.0))
	var ai := _ai(e)
	# 聽覺 3m；隔牆只有 1.5m
	var near := _player(Vector3(-3, 0, 0.4))
	assert_true(ai.can_hear(near.get_node("CombatComponent")), "1.4m through wall: heard")
	near.global_position = Vector3(-3, 0, 1.5)
	assert_false(ai.can_hear(near.get_node("CombatComponent")), "2.5m through wall: not heard")

func test_noise_sends_patrolling_enemy_to_investigate() -> void:
	var e := _enemy("stitcher", Vector3(0, 0, 0))
	var ai := _ai(e)
	var log := []
	ai.search_started.connect(func(pt): log.append(pt))
	ai.advance(0.05)
	assert_eq(ai.state(), &"patrol")
	EventBus.emit_noise(Vector3(5, 0, 0), 8.0, null, &"impact")
	assert_eq(ai.state(), &"search", "heard the noise")
	assert_eq(log.size(), 1)
	_walk(ai, 3.0)
	assert_true(e.global_position.distance_to(Vector3(5, 0, 0)) < 1.0, "walked to the noise")

func test_noise_out_of_range_or_from_allies_is_ignored_except_alarm() -> void:
	var e := _enemy("stitcher", Vector3(0, 0, 0))
	var ally := _enemy("many_hands", Vector3(2, 0, 0))
	var ai := _ai(e)
	ai.advance(0.05)
	EventBus.emit_noise(Vector3(20, 0, 0), 8.0, null, &"impact")
	assert_eq(ai.state(), &"patrol", "too far")
	EventBus.emit_noise(ally.global_position, 8.0, ally, &"attack")
	assert_eq(ai.state(), &"patrol", "ally's own swing")
	EventBus.emit_noise(ally.global_position, 8.0, ally, &"alarm")
	assert_eq(ai.state(), &"search", "ally's alarm call")

func test_player_attack_makes_noise_through_noise_emitter() -> void:
	var p := _player(Vector3(0, 0, 0))
	var heard := []
	EventBus.noise_emitted.connect(func(_pos, r, src, kind): heard.append([src, kind, r]))
	var pc: CombatComponent = p.get_node("CombatComponent")
	pc.try_attack(pc.available_attacks()[0])
	assert_true(heard.size() >= 1 and heard[0][0] == p and heard[0][1] == &"attack", "attack noise from player")

func test_lost_target_goes_to_last_known_position_then_searches_then_patrols() -> void:
	var lvl := _two_rooms(true)
	var p := _player(Vector3(-2, 0, 3))
	var e := _enemy("stitcher", Vector3(-2, 0, 5), 0.0)  # 面向 -Z，看著玩家
	var ai := _ai(e)
	ai.runtime.alert = 1.0
	ai.advance(0.05)
	assert_eq(ai.state(), &"chase")
	# 玩家瞬間躲到牆後（北房），敵人不應知道真實位置
	var lkp := p.global_position
	p.global_position = Vector3(-4, 0, -3)
	_walk(ai, 0.5)
	var to_lkp: float = e.global_position.distance_to(lkp)
	assert_true(ai.runtime.time_since_seen > 0.0, "lost sight")
	assert_true(ai.state() == &"chase" or ai.state() == &"search")
	_walk(ai, 2.0)
	assert_eq(ai.state(), &"search", "reached last known position: searching")
	assert_true(e.global_position.z > 0.0, "did not beeline to the hidden player")
	_walk(ai, 15.0)
	assert_eq(ai.state(), &"patrol", "gave up")

func test_separation_pushes_enemies_apart() -> void:
	var a := _enemy("stitcher", Vector3(0, 0, 0))
	var b := _enemy("stitcher", Vector3(0.3, 0, 0))
	var aa := _ai(a)
	var ab := _ai(b)
	aa.advance(0.05)
	ab.advance(0.05)
	assert_true(aa.separation().x < 0.0, "a pushed to -x")
	assert_true(ab.separation().x > 0.0, "b pushed to +x")
	aa.move_towards(Vector3(0, 0, -5))
	assert_true(aa.desired_velocity.x < 0.0, "steers away while moving")

func test_animation_and_audio_hooks_fire() -> void:
	var p := _player(Vector3(0, 0, 0))
	var e := _enemy("stitcher", Vector3(0, 0, -1.1))
	var ai := _ai(e)
	var log := []
	ai.alerted.connect(func(t): log.append(["alerted", t]))
	ai.bark.connect(func(k): log.append(["bark", k]))
	ai.telegraph.connect(func(a, w): log.append(["telegraph", a.id, w]))
	ai.locomotion_changed.connect(func(m): log.append(["loco", m]))
	for i in 40:
		ai.advance(0.05)
		ai.combat.advance(0.05)
	var kinds := log.map(func(x): return x[0])
	assert_true("alerted" in kinds, "alerted")
	assert_true(["bark", &"alert"] in log, "alert bark")
	assert_true("telegraph" in kinds, "telegraph on attack windup")
	ai.anatomy.state.sever_part(&"leg_l")
	ai.anatomy.state.sever_part(&"leg_r")
	assert_true(["bark", &"pain"] in log, "pain bark on sever")
	ai.desired_velocity = Vector3(0.3, 0, 0)
	ai._update_locomotion(0.3)
	assert_eq(ai.locomotion_mode, &"crawl", "no legs: crawl")

func test_prologue_level_bakes_a_connected_navmesh() -> void:
	var lvl: Node3D = (load("res://scenes/prologue/prologue_level.tscn") as PackedScene).instantiate()
	tree.root.add_child(lvl)
	LevelNavigation.bake(lvl, lvl.get_node("Geometry"))
	assert_true(AiNavigator.has_navigation(lvl), "baked")
	# 產房 → 庭院 → 東側聖器室：必須經過走廊與門，路徑比直線長
	var from := Vector3(0, 0, 0)
	var to := Vector3(17, 0, -36)
	var len := AiNavigator.path_length(lvl, from, to)
	assert_true(len < INF and len > from.distance_to(to), "connected via corridor (%s)" % len)
	var end := NavigationServer3D.map_get_path(lvl.get_world_3d().navigation_map, from, to, true)
	assert_true(end.size() > 2 and Vector2(end[-1].x, end[-1].z).distance_to(Vector2(to.x, to.z)) < 0.6, "path reaches the sacristy")
