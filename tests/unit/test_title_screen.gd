extends TestCase
## 主畫面（TitleChapel 3D 背景＋像素標題＋原有選項）與預設 360p 內部解析度。

const BASE_LABELS := ["新遊戲", "繼續", "戰鬥沙盒", "美術測試（PS1 風格）", "聲音設定", "離開"]

## 操作說明畫面合併後，選單會多一個「操作說明」（在聲音設定前）。
static func labels() -> Array:
	var l := BASE_LABELS.duplicate()
	if ResourceLoader.exists(MainMenu.CONTROLS):
		l.insert(4, "操作說明")
	return l

func _menu() -> MainMenu:
	var m := MainMenu.new()
	tree.root.add_child(m)
	return m

func test_retro_screen_defaults_to_360p() -> void:
	var r := RetroScreen.new()
	assert_eq(r.target_height(), 360, "default internal resolution")
	assert_true(240 in RetroScreen.HEIGHTS and 480 in RetroScreen.HEIGHTS, "F2 can still cycle 240p/480p")
	r.cycle_resolution()
	assert_eq(r.target_height(), 480)
	r.free()

func test_project_window_is_integer_multiple_of_360p() -> void:
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	assert_eq(h, 720)
	assert_eq(h % RetroScreen.DEFAULT_HEIGHT, 0, "720 = 2 × 360, crisp nearest scaling")

func test_menu_keeps_all_entries_in_order() -> void:
	var m := _menu()
	var want := labels()
	assert_eq(m.buttons.size(), want.size())
	for i in want.size():
		assert_eq(String(m.buttons[i].get_meta(&"label")), want[i])
	assert_eq(m.continue_button, m.buttons[1])
	assert_eq(m.continue_button.disabled, not SaveSystem.exists())

func test_menu_renders_chapel_in_360p_screen() -> void:
	var m := _menu()
	assert_true(m.screen != null and m.chapel != null)
	assert_true(m.screen.world.is_ancestor_of(m.chapel), "3D background lives in the low-res viewport")
	assert_eq(m.screen.target_height(), 360)
	assert_true(m.chapel.camera.current, "chapel camera drives the viewport")
	assert_true(m.find_child("Logo", true, false) is SubViewportContainer, "pixel-scaled title logo")
	assert_eq((m.find_child("Logo", true, false) as SubViewportContainer).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

func test_focus_marker_follows_selection() -> void:
	var m := _menu()
	assert_true(m.buttons[0].has_focus(), "keyboard ready: first entry focused")
	assert_true(m.buttons[0].text.begins_with(MainMenu.MARKER))
	m.buttons[2].grab_focus()
	assert_false(m.buttons[0].text.begins_with(MainMenu.MARKER), "marker removed from old entry")
	assert_eq(m.buttons[2].text, MainMenu.MARKER + "戰鬥沙盒")

func test_new_game_fades_out_before_leaving() -> void:
	var m := _menu()
	m.new_game()
	assert_true(m.is_leaving())
	assert_eq(GameState.start_mode, "new")
	assert_true(tree.root.is_ancestor_of(m), "scene does not switch instantly (fade first)")
	m.continue_game()  # 淡出中再選擇會被忽略
	assert_eq(GameState.start_mode, "continue", "flag set but…")
	assert_eq(m._leaving, MainMenu.PROLOGUE, "…the pending target is unchanged")

func test_audio_settings_hide_and_restore_menu() -> void:
	var m := _menu()
	m.open_audio_settings()
	assert_true(m.audio_panel.visible)
	assert_false(m._menu_box.visible)
	m.audio_panel.close()
	assert_true(m._menu_box.visible)
	assert_true(m.audio_button.has_focus(), "focus returns to 聲音設定")

func test_chapel_contains_key_motifs() -> void:
	var c := TitleChapel.new()
	tree.root.add_child(c)
	for n in ["Heart", "Shroud", "StitchedArm", "RoseWindow", "Drip", "Candlestand"]:
		assert_true(c.find_child(n, true, false) != null, "has %s" % n)
	var saints := c.find_children("FacelessSaint*", "", true, false)
	assert_eq(saints.size(), 2, "two faceless saints")

func test_chapel_animates_at_12fps_with_heartbeat() -> void:
	var c := TitleChapel.new()
	tree.root.add_child(c)
	c.advance(1.0 / TitleChapel.FPS * 0.5)
	assert_eq(c.frames, 0, "no update between frames (stepped animation)")
	c.advance(1.0 + 0.0001)
	assert_eq(c.frames, 12, "12 frames per second")
	assert_near(TitleChapel.beat_scale(0.0), 1.0)
	assert_true(TitleChapel.beat_scale(0.08) > 1.1, "first contraction")
	assert_true(TitleChapel.beat_scale(0.33) > 1.05, "second contraction")
	assert_near(TitleChapel.beat_scale(1.0), 1.0, 0.0001, "rest between beats")
	var cam0 := c.camera.position
	c.advance(3.0)
	assert_true(c.camera.position.distance_to(cam0) > 0.001, "camera drifts")

func test_candles_sit_on_altar_steps() -> void:
	assert_near(TitleChapel.step_top(0.0, -7.3), 0.66)
	assert_near(TitleChapel.step_top(2.9, -7.3), 0.22)
	assert_near(TitleChapel.step_top(5.0, -7.3), 0.0)
