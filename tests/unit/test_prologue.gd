extends TestCase
## 序章：關卡內容、遊戲流程（職業選擇、武器台、鑰匙門、Boss、結局）、祭壇存檔與死亡重生、主選單。

const SAVE := "user://test_prologue_save.json"

func _game(mode: String = "new") -> PrologueGame:
	var g := PrologueGame.new()
	g.autostart = false
	g.play_opening = false
	g.save_path = SAVE
	tree.root.add_child(g)
	g.start_game(mode)
	return g

func _cleanup() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)

func _find(g: PrologueGame, path: String) -> Node:
	return g.level.get_node(path)

func _ctrl(g: PrologueGame) -> PlayerController: return g.player.get_node("PlayerController")
func _data(g: PrologueGame) -> PlayerData: return g.player.get_node("PlayerData")

func test_level_contains_required_content() -> void:
	var lvl: Node3D = (load(PrologueGame.LEVEL) as PackedScene).instantiate()
	assert_true(lvl.get_node("Altars").get_child_count() >= 2, "at least two altars")
	var weapons := []
	var enemy_types := {}
	var dialogue_ids := []
	for n in lvl.get_node("Interactables").get_children():
		if n is WeaponPedestal:
			weapons.append(String(n.weapon().id))
		if n is DialogueInteractable:
			dialogue_ids.append(n.dialogue_id)
			if n.repeat_dialogue_id != "":
				dialogue_ids.append(n.repeat_dialogue_id)
		if n is BossGate and not n is ShortcutGate:
			dialogue_ids.append(n.locked_dialogue_id)
			dialogue_ids.append(n.open_dialogue_id)
	for n in lvl.get_node("Triggers").get_children():
		if n.dialogue_id != "":
			dialogue_ids.append(n.dialogue_id)
	weapons.sort()
	assert_eq(weapons, ["anatomist_rapier", "bone_saw_cleaver", "reliquary_hammer"], "all three weapons obtainable")
	for s in lvl.get_node("Spawns").get_children():
		enemy_types[(load(s.enemy_path) as EnemyDefinition).id] = true
	for t in [&"stitcher", &"reverse_legged", &"faceless_watcher", &"many_hands"]:
		assert_true(enemy_types.has(t), "has %s" % t)
	var known := DialogueRunner.all_ids()
	for id in dialogue_ids:
		assert_true(id in known, "dialogue %s exists" % id)
	for room in ["DeliveryRoom", "SutureCorridor", "Courtyard", "Archive", "Sacristy", "Chapel"]:
		assert_true(lvl.get_node_or_null("Geometry/" + room) != null, room)
	assert_true(lvl.get_node_or_null("Markers/BossSpawn") != null)
	assert_true(lvl.get_node_or_null("Interactables/Item_item_umbilical_key") != null)
	for id in ["note_register", "note_stitcher", "note_stripping", "note_magdalene"]:
		assert_true(lvl.get_node_or_null("Interactables/Note_" + id) != null, "note %s placed" % id)
	assert_true(lvl.get_node_or_null("Interactables/NPC_Ignatius") != null, "dying priest placed")
	assert_eq(lvl.get_node("Triggers/Trigger_enter_corridor").dialogue_id, "corridor_thought")
	lvl.free()

func test_new_game_plays_opening_and_boss_lines() -> void:
	var g := PrologueGame.new()
	g.autostart = false
	g.save_path = SAVE
	tree.root.add_child(g)
	g.start_game("new")
	assert_true(g.dialogue.is_open(), "opening narration plays on a new game")
	assert_eq(g.dialogue.runner.data.get("id"), "prologue_opening")
	var guard := 0
	while g.dialogue.runner.active and guard < 10:
		g.dialogue.runner.advance(); guard += 1
	assert_false(g.dialogue.is_open())
	assert_eq(TimeScale.mode, TimeScale.Mode.NORMAL)
	var bp: BossPhaseComponent = g.boss.get_node("BossPhase")
	bp.phase_changed.emit(2)
	assert_eq(g.toast.text, g.boss_line(&"kneel"))
	GameState.set_flag(&"knows_mother")
	assert_true("伊蓮" in g.boss_line(&"defeated"))
	g.queue_free()
	_cleanup()

func test_continue_does_not_replay_opening() -> void:
	var g := _game()
	g.queue_free()
	var g2 := PrologueGame.new()
	g2.autostart = false
	g2.save_path = SAVE
	tree.root.add_child(g2)
	g2.start_game("continue")
	assert_false(g2.dialogue.is_open())
	g2.queue_free()
	_cleanup()

func test_new_game_starts_unarmed_and_class_choice_through_agnes() -> void:
	var g := _game()
	assert_eq(_ctrl(g).weapons.size(), 0, "wakes unarmed")
	assert_true(g.boss != null, "boss spawned")
	assert_eq(g.boss.get_node("EnemyAI").process_mode, Node.PROCESS_MODE_DISABLED, "boss dormant")
	var spawned := g.level.get_children().filter(func(n): return n.has_meta(&"spawn_id"))
	assert_eq(spawned.size(), g.level.get_node("Spawns").get_child_count())
	assert_true(SaveSystem.exists(SAVE), "initial save")
	var agnes: DialogueInteractable = _find(g, "Interactables/NPC_Agnes")
	assert_eq(agnes.current_dialogue(), "agnes_intro")
	assert_true(agnes.interact(g.player))
	assert_true(g.dialogue.is_open())
	var r := g.dialogue.runner
	var guard := 0
	while r.choices().is_empty() and guard < 10:
		r.advance(); guard += 1
	r.choose(2)  # 刑體師
	while r.active and guard < 30:
		r.advance(); guard += 1
	assert_false(g.dialogue.is_open())
	assert_eq(GameState.class_id, &"mutilator")
	assert_eq((g.player.get_node("CombatComponent") as CombatComponent).weapon().id, &"bone_saw_cleaver")
	assert_eq(_data(g).inventory.count("suture_kit"), 2 + int((load("res://content/classes/mutilator.tres") as ClassDefinition).starting_items.get("suture_kit", 0)))
	assert_eq(agnes.current_dialogue(), "agnes_return")
	assert_eq(TimeScale.mode, TimeScale.Mode.NORMAL, "time resumes after dialogue")
	_cleanup()

func test_pedestal_gate_and_key() -> void:
	var g := _game()
	var ped: WeaponPedestal = _find(g, "Interactables/Pedestal_reliquary_hammer")
	assert_true(ped.interact(g.player))
	assert_true(_ctrl(g).weapons.any(func(w): return w.id == &"reliquary_hammer"))
	assert_false(ped.available(), "pedestal used")
	var gate: BossGate = _find(g, "Interactables/ChapelGate")
	assert_false(gate.interact(g.player), "locked without key")
	g.dialogue.close_box()
	assert_false(gate.is_open())
	var key: ItemPickup = _find(g, "Interactables/Item_item_umbilical_key")
	assert_true(key.interact(g.player))
	assert_true(gate.interact(g.player))
	assert_true(gate.is_open())
	g.dialogue.runner.advance()  # chapel_gate_open 設定旗標
	assert_true(GameState.has_flag(&"chapel_open"))
	_cleanup()

func test_boss_fight_and_ending() -> void:
	var g := _game()
	var arena: AreaTrigger = _find(g, "Triggers/Trigger_chapel_arena")
	arena.global_position = g.player.global_position
	assert_false(arena.check(), "requires chapel_open")
	GameState.set_flag(&"chapel_open")
	assert_true(arena.check())
	assert_true(g.dialogue.is_open(), "mother_intro plays")
	var guard := 0
	while g.dialogue.runner.active and guard < 10:
		g.dialogue.runner.advance(); guard += 1  # 最後一句觸發 start_boss
	assert_false(g.dialogue.is_open())
	assert_true(g.boss_intro != null and g.boss_intro.playing, "boss intro cinematic plays after the dialogue")
	assert_eq(TimeScale.mode, TimeScale.Mode.PAUSE, "combat paused during the intro")
	assert_eq(g.boss.get_node("EnemyAI").process_mode, Node.PROCESS_MODE_DISABLED, "boss waits for the intro")
	assert_eq((g.boss.get_node("CreatureAnimator") as CreatureAnimator).current_clip, &"intro")
	g.boss_intro.advance(BossIntro.DURATION + 0.1)
	assert_eq(TimeScale.mode, TimeScale.Mode.NORMAL)
	assert_eq(g.boss.get_node("EnemyAI").process_mode, Node.PROCESS_MODE_INHERIT, "boss awake")
	assert_true((g.boss.get_node("BossPhase") as BossPhaseComponent).engaged)
	assert_true(g.boss_bar.visible)
	var womb: DialogueInteractable = _find(g, "Interactables/WombChamber_Ending")
	assert_false(womb.available(), "ending locked before boss dies")
	(g.boss.get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"head")
	assert_true(GameState.has_flag(&"boss_defeated"))
	assert_false(g.boss_bar.visible)
	assert_true(womb.available())
	var ends := []
	g.ending_reached.connect(func(id): ends.append(id))
	womb.interact(g.player)
	g.dialogue.runner.choose(0)
	while g.dialogue.runner.active and guard < 20:
		g.dialogue.runner.advance(); guard += 1
	assert_eq(ends, ["burn"])
	assert_true(GameState.has_flag(&"ending_burn"))
	_cleanup()

func test_altar_save_and_death_respawn() -> void:
	var g := _game()
	var altar: StitchingAltar = _find(g, "Altars/Altar_altar_courtyard")
	# 擊殺一隻敵人並在祭壇休息（存檔）
	var e: Node = g.level.get_children().filter(func(n): return n.get_meta(&"spawn_id", &"") == &"corridor_stitcher_1")[0]
	(e.get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"head")
	assert_true(GameState.killed.has(&"corridor_stitcher_1"))
	altar.rest(g.player)
	assert_eq(GameState.checkpoint_altar, &"altar_courtyard")
	# 存檔後再殺一隻、拿一個武器，然後死亡 → 這些進度回復到存檔時
	var e2: Node = g.level.get_children().filter(func(n): return n.get_meta(&"spawn_id", &"") == &"corridor_stitcher_2")[0]
	(e2.get_node("CombatComponent") as CombatComponent).anatomy.state.sever_part(&"head")
	(_find(g, "Interactables/Pedestal_anatomist_rapier") as WeaponPedestal).interact(g.player)
	var pc: CombatComponent = g.player.get_node("CombatComponent")
	pc.anatomy.state.sever_part(&"head")
	assert_true(pc.is_dead())
	assert_true(g._death_left > 0.0, "death screen")
	g.respawn()
	assert_false((g.player.get_node("CombatComponent") as CombatComponent).is_dead())
	assert_true(g.player.global_position.distance_to(_find(g, "Altars/Altar_altar_courtyard").global_position) < 2.0, "respawn at altar")
	var ids := g.level.get_children().filter(func(n): return n.has_meta(&"spawn_id")).map(func(n): return n.get_meta(&"spawn_id"))
	assert_false(&"corridor_stitcher_1" in ids, "killed before save stays dead")
	assert_true(&"corridor_stitcher_2" in ids, "killed after save is back")
	assert_true((_find(g, "Interactables/Pedestal_anatomist_rapier") as WeaponPedestal).available(), "pedestal restored")
	assert_true(g.boss != null)
	_cleanup()

func test_continue_restores_progress() -> void:
	var g := _game()
	PlayerFactory.apply_class(g.player, "res://content/classes/anatomist.tres")
	GameState.set_flag(&"met_agnes")
	(_find(g, "Interactables/Item_item_umbilical_key") as ItemPickup).interact(g.player)
	(_find(g, "Altars/Altar_altar_delivery") as StitchingAltar).rest(g.player)
	g.queue_free()
	tree.root.remove_child(g)
	GameState.reset()
	var h := _game("continue")
	assert_eq(GameState.class_id, &"anatomist")
	assert_true(GameState.has_flag(&"met_agnes"))
	assert_eq(_data(h).inventory.count("umbilical_key"), 1)
	assert_false((_find(h, "Interactables/Item_item_umbilical_key") as ItemPickup).available(), "key stays taken")
	assert_eq((h.player.get_node("CombatComponent") as CombatComponent).weapon().id, &"anatomist_rapier")
	_cleanup()

func test_main_menu_builds() -> void:
	var m := MainMenu.new()
	tree.root.add_child(m)
	assert_true(m.continue_button != null)
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/main_menu.tscn")
	assert_true(ResourceLoader.exists(MainMenu.PROLOGUE))
