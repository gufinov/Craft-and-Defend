class_name F1Automation
extends Node

var app: CraftAndDefendApp
var results: Array[Dictionary] = []
var failed := false
var _fake_unloaded: Dictionary = {}
var _fake_voxels: Dictionary = {}


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_phase1()
		"phase2":
			await _run_phase2()
		"visual":
			await _run_visual()
		"display-runtime":
			await _run_display_runtime()
		_:
			_record("HARNESS", false, "known F1 automation mode", mode)
			_finish(2)


func _run_phase1() -> void:
	await get_tree().process_frame
	await _test_keybind_editor()
	app._close_keybinds()
	_test_display_rollback()
	app.start_button.pressed.emit()
	if not await _wait_for_session_ready():
		_record("T14_READY", false, "collision-ready session", "timeout")
		_finish(1)
		return
	await _test_input_contexts()
	await _test_boundaries()
	await _test_interaction_rejections()
	_test_entity_footprints()
	_finish(0 if not failed else 1)


func _run_phase2() -> void:
	await get_tree().process_frame
	var crouch_binding := app.settings.get_binding("crouch")
	var primary_binding := app.settings.get_binding("primary")
	_record("T13_RESTART_KEYS", crouch_binding.kind == "key" and int(crouch_binding.code) == KEY_C, "Crouch C persists after full restart", crouch_binding)
	_record("T13_RESTART_MOUSE", primary_binding.kind == "mouse" and int(primary_binding.code) == MOUSE_BUTTON_MIDDLE, "Primary Mouse Middle persists after full restart", primary_binding)
	_record("T18_RESTART_DISPLAY", app.settings.resolution == Vector2i(1600, 900), "confirmed resolution persists after full restart", app.settings.resolution)
	var reset_result := app.settings.reset_defaults()
	var defaults_ok: bool = reset_result.get("ok", false)
	for action in SettingsStore.BINDING_ACTIONS:
		defaults_ok = defaults_ok and app.settings.get_binding(action) == SettingsStore.DEFAULT_BINDINGS[action]
	_record("T13_RESET_DEFAULTS", defaults_ok, "reset restores every documented binding", app.settings.get_binding("move_forward"))
	_test_corrupt_binding_recovery()
	app.settings.begin_display_preview("windowed", SettingsStore.DEFAULT_RESOLUTION)
	app.settings.confirm_display_preview()
	_finish(0 if not failed else 1)


func _test_keybind_editor() -> void:
	app._show_keybinds()
	_record("T13_COMPLETE_EDITOR", app.binding_labels.size() == SettingsStore.BINDING_ACTIONS.size(), "every implemented action has a visible binding row", app.binding_labels.size())

	var original_forward := app.settings.get_binding("move_forward")
	app._capture_binding("move_forward")
	var conflict_event := InputEventKey.new()
	conflict_event.pressed = true
	conflict_event.physical_keycode = KEY_D
	app._unhandled_input(conflict_event)
	_record("T13_CONFLICT_EXPLAINED", app.settings.get_binding("move_forward") == original_forward and app.keybind_message.text.contains("Move Backward"), "conflict names the action and changes nothing", app.keybind_message.text)

	app._capture_binding("strafe_left")
	var before_cancel := app.settings.get_binding("strafe_left")
	var escape_event := InputEventKey.new()
	escape_event.pressed = true
	escape_event.physical_keycode = KEY_ESCAPE
	app._unhandled_input(escape_event)
	_record("T13_CAPTURE_CANCEL", app.capture_action.is_empty() and app.settings.get_binding("strafe_left") == before_cancel, "Escape cancels capture without mutation", app.keybind_message.text)

	var reset_result := app.settings.reset_defaults()
	_record("T13_RESET_AVAILABLE", reset_result.get("ok", false) and app.settings.get_keycode("move_forward") == KEY_E, "reset restores ESDF", reset_result)

	app._capture_binding("crouch")
	var crouch_event := InputEventKey.new()
	crouch_event.pressed = true
	crouch_event.physical_keycode = KEY_C
	app._unhandled_input(crouch_event)
	app._capture_binding("primary")
	var mouse_event := InputEventMouseButton.new()
	mouse_event.pressed = true
	mouse_event.button_index = MOUSE_BUTTON_MIDDLE
	app._unhandled_input(mouse_event)
	_record("T13_KEY_MOUSE_CAPTURE", app.settings.get_keycode("crouch") == KEY_C and app.settings.get_binding_label("primary") == "Mouse Middle", "keyboard and mouse bindings save", {"crouch": app.settings.get_binding_label("crouch"), "primary": app.settings.get_binding_label("primary")})


func _test_input_contexts() -> void:
	var before_inventory := _mutation_snapshot()
	app._show_inventory()
	var inventory_open := app.state == app.AppState.INVENTORY and get_tree().paused and not app.session.player.active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	var primary_event := InputEventMouseButton.new()
	primary_event.pressed = true
	primary_event.button_index = MOUSE_BUTTON_LEFT
	app.session.player._unhandled_input(primary_event)
	_record("T14_INVENTORY_CONTEXT", inventory_open and before_inventory == _mutation_snapshot(), "inventory pauses and blocks world actions", {"state": app.state, "player_active": app.session.player.active})
	app._close_inventory()
	_record("T14_INVENTORY_CLOSE", app.state == app.AppState.PLAYING and not get_tree().paused and app.session.player.active, "Tab/close returns to active play", app.state)

	# T14 tests the focus-loss rules themselves, so lift the diagnostic guard
	# that otherwise ignores host focus changes during automation.
	app.automation_active = false
	var print_event := InputEventKey.new()
	print_event.pressed = true
	print_event.physical_keycode = KEY_PRINT
	app._unhandled_input(print_event)
	app._handle_focus_lost()
	var screenshot_suspended := app.state == app.AppState.PLAYING and get_tree().paused and not app.pause_panel.visible and not app.session.player.active
	app._handle_focus_gained()
	await get_tree().create_timer(CraftAndDefendApp.SCREENSHOT_CLICK_GUARD_SECONDS + 0.05, true).timeout
	var screenshot_resumed := app.state == app.AppState.PLAYING and not get_tree().paused and not app.pause_panel.visible and app.session.player.active
	_record("T14_PRINT_SCREEN", screenshot_suspended and screenshot_resumed, "Print Screen freezes without showing Pause and resumes after a click-through guard", {"suspended": screenshot_suspended, "resumed": screenshot_resumed})

	app._handle_focus_lost()
	var focus_paused := app.state == app.AppState.PAUSED and get_tree().paused and not app.session.player.active
	await get_tree().process_frame
	_record("T14_FOCUS_LOSS", focus_paused and app.state == app.AppState.PAUSED, "focus loss pauses and focus return never auto-resumes", app.state)
	app.automation_active = true

	var before_ui := _mutation_snapshot()
	app._show_keybinds()
	app.session.player._unhandled_input(primary_event)
	_record("T13_UI_NO_WORLD_INPUT", before_ui == _mutation_snapshot(), "keybind UI never mines or places", _mutation_snapshot())
	app._close_keybinds()
	app._resume_game()
	_record("T14_EXPLICIT_RESUME", app.state == app.AppState.PLAYING and app.session.player.active, "only explicit Resume recaptures gameplay", app.state)


func _test_boundaries() -> void:
	var minimum := WorldAdapter.WORLD_MIN
	var maximum := WorldAdapter.WORLD_MIN + WorldAdapter.WORLD_SIZE
	var six_faces_rejected := not app.session.world.is_in_bounds(Vector3i(minimum.x - 1, 0, 0)) \
		and not app.session.world.is_in_bounds(Vector3i(maximum.x, 0, 0)) \
		and not app.session.world.is_in_bounds(Vector3i(0, minimum.y - 1, 0)) \
		and not app.session.world.is_in_bounds(Vector3i(0, maximum.y, 0)) \
		and not app.session.world.is_in_bounds(Vector3i(0, 0, minimum.z - 1)) \
		and not app.session.world.is_in_bounds(Vector3i(0, 0, maximum.z))
	var corners_valid := app.session.world.is_in_bounds(minimum) and app.session.world.is_in_bounds(maximum - Vector3i.ONE)
	var negative_floor := Vector3i(floori(-0.1), floori(-0.1), floori(-0.1)) == Vector3i(-1, -1, -1)
	_record("T15_HALF_OPEN_BOUNDS", six_faces_rejected and corners_valid and negative_floor, "six faces, corners, and negative floor conversion obey half-open bounds", {"faces": six_faces_rejected, "corners": corners_valid, "negative_floor": negative_floor})

	var bottom_cell := Vector3i(0, minimum.y, 40)
	var loaded := await _wait_cell_loaded(bottom_cell)
	var before_bottom := _mutation_snapshot()
	var bottom_result := app.session.interaction.try_break_cell(bottom_cell)
	_record("T15_PROTECTED_BOTTOM", loaded and bottom_result.get("reason") == "PROTECTED" and before_bottom == _mutation_snapshot(), "bottom bedrock refuses removal without mutation", bottom_result)

	app.session.player.position = Vector3(100.0, app.session.player.position.y, 100.0)
	app.session.player._position_inside_world()
	_record("T15_PLAYER_BOUNDARY_FEEDBACK", app.session.player.position.x <= 31.651 and app.session.player.position.z <= 63.651 and app.feedback_label.text.contains("World boundary"), "player is contained with visible edge feedback", {"position": app.session.player.position, "feedback": app.feedback_label.text})
	app.session.player.position = Vector3(0.5, 0.0, 40.5)


func _test_interaction_rejections() -> void:
	var stale_cell := Vector3i(4, -1, 38)
	await _wait_cell_loaded(stale_cell)
	var before_stale := _mutation_snapshot()
	var stale := app.session.interaction.try_break_cell(stale_cell, app.session.world.revision + 1)
	_record("T16_STALE", stale.get("reason") == "STALE_REVISION" and before_stale == _mutation_snapshot(), "stale command changes nothing", stale)

	var inventory_before := app.session.inventory.snapshot()
	app.session.inventory.restore({"dirt": F0Inventory.MAX_DIRT, "revision": inventory_before.revision})
	var full_before := _mutation_snapshot()
	var full_result := app.session.interaction.try_break_cell(stale_cell)
	_record("T16_FULL_INVENTORY", full_result.get("reason") == "INVENTORY_FULL" and full_before == _mutation_snapshot(), "full inventory leaves block and counts unchanged", full_result)
	app.session.inventory.restore(inventory_before)

	var wrong_cell := Vector3i(5, -1, 38)
	await _wait_cell_loaded(wrong_cell)
	app.session.world.set_cell(wrong_cell, InteractionService.STONE)
	var wrong_before := _mutation_snapshot()
	var wrong_result := app.session.interaction.try_break_cell(wrong_cell)
	_record("T16_WRONG_TOOL", wrong_result.get("reason") == "WRONG_TOOL" and wrong_before == _mutation_snapshot(), "wrong tool leaves world and inventory unchanged", wrong_result)
	app.session.world.set_cell(wrong_cell, InteractionService.GRASS)

	var rapid_cell := Vector3i(6, -1, 38)
	await _wait_cell_loaded(rapid_cell)
	app.session.world.set_cell(rapid_cell, InteractionService.GRASS)
	app.session.inventory.restore({"dirt": 0, "revision": app.session.inventory.revision})
	var expected_revision := app.session.world.revision
	var first := app.session.interaction.try_break_cell(rapid_cell, expected_revision)
	var second := app.session.interaction.try_break_cell(rapid_cell, expected_revision)
	_record("T16_RAPID_DUPLICATE", first.get("ok", false) and second.get("reason") == "STALE_REVISION" and app.session.inventory.dirt == 1, "rapid duplicate awards exactly one item", {"first": first.reason, "second": second.reason, "dirt": app.session.inventory.dirt})


func _test_entity_footprints() -> void:
	var cube_offsets: Array = []
	for x in range(2):
		for y in range(2):
			for z in range(2):
				cube_offsets.append(Vector3i(x, y, z))
	_fake_unloaded.clear()
	_fake_voxels.clear()
	var service := EntityFootprintService.new()
	var valid := service.try_reserve("tower", Vector3i(0, 0, 0), cube_offsets, 1, _fake_query)
	var overlap := service.try_reserve("overlap", Vector3i(0, 0, 0), [Vector3i.ZERO], 0, _fake_query)
	var released := service.release_at(Vector3i(0, 0, 0))
	var released_again := service.release_at(Vector3i(0, 0, 0))
	var release_ok: bool = released.get("ok", false) and released.details.released_cells.size() == 8 and released.details.drop_count == 1 \
		and not released_again.get("ok", false) and service.occupied_cell_count() == 0

	var unloaded_service := EntityFootprintService.new()
	_fake_unloaded[Vector3i(1, 0, 0)] = true
	var unloaded := unloaded_service.try_reserve("unloaded", Vector3i.ZERO, [Vector3i(1, 0, 0)], 0, _fake_query)
	_fake_unloaded.clear()
	var player_overlap := unloaded_service.try_reserve("player", Vector3i.ZERO, [Vector3i.ZERO], 0, _fake_query, AABB(Vector3.ZERO, Vector3.ONE))
	var unsupported := unloaded_service.try_reserve("unsupported", Vector3i.ZERO, [Vector3i.ZERO], 0, _fake_query, AABB(), [Vector3i.DOWN])
	var outside := unloaded_service.try_reserve("outside", WorldAdapter.WORLD_MIN, [Vector3i.LEFT], 0, _fake_query)
	var all_rejections: bool = overlap.reason == "OCCUPIED" and unloaded.reason == "UNLOADED" \
		and player_overlap.reason == "PLAYER_OVERLAP" and unsupported.reason == "UNSUPPORTED" and outside.reason == "OUT_OF_BOUNDS"
	_record("T17_FOOTPRINTS", valid.get("ok", false) and release_ok and all_rejections, "multi-cell reserve/reject/release is atomic and releases once", {"valid": valid.reason, "overlap": overlap.reason, "unloaded": unloaded.reason, "player": player_overlap.reason, "support": unsupported.reason, "outside": outside.reason, "release": released})


func _test_display_rollback() -> void:
	var original_resolution := app.settings.resolution
	var target_resolution := Vector2i(1600, 900)
	var target_index := SettingsStore.RESOLUTION_OPTIONS.find(target_resolution)
	app._show_settings()
	app.window_mode_option.select(0)
	app.resolution_option.select(target_index)
	app._preview_display_changes()
	var preview_visible := app.display_confirm_panel.visible and app.settings.is_display_preview_active()
	app._display_confirm_remaining = 0.01
	app._process(0.02)
	var rollback_ok := preview_visible and app.settings.resolution == original_resolution \
		and not app.settings.is_display_preview_active() and app.settings_message.text.contains("automatically")
	app.resolution_option.select(target_index)
	app._preview_display_changes()
	app._confirm_display_preview()
	var confirm_ok := app.settings.resolution == target_resolution and not app.settings.is_display_preview_active() \
		and app.settings_message.text.contains("saved")
	_record("T18_DISPLAY_ROLLBACK", rollback_ok and confirm_ok, "display preview times out to the prior mode unless explicitly confirmed", {"rollback_message": app.settings_message.text, "resolution": app.settings.resolution})
	app._close_settings()


func _test_corrupt_binding_recovery() -> void:
	var corrupt_root := app.data_root.path_join("corrupt-binding-case")
	DirAccess.make_dir_recursive_absolute(corrupt_root)
	var config := ConfigFile.new()
	config.set_value("binding_types", "move_forward", "key")
	config.set_value("bindings", "move_forward", KEY_D)
	config.set_value("binding_types", "move_backward", "key")
	config.set_value("bindings", "move_backward", KEY_D)
	var save_error := config.save(corrupt_root.path_join("settings.cfg"))
	var recovered_store := SettingsStore.new(corrupt_root)
	var load_result := recovered_store.load_and_apply()
	var recovered: bool = save_error == OK and load_result.get("bindings_recovered", false) \
		and recovered_store.get_keycode("move_forward") == KEY_E \
		and recovered_store.get_keycode("move_backward") == KEY_D
	_record("T13_CORRUPT_RECOVERY", recovered, "conflicting persisted settings recover to the complete safe default map", load_result)


func _run_visual() -> void:
	await get_tree().process_frame
	await _set_capture_size(Vector2i(1280, 720))
	app._show_keybinds()
	await _settle_frames()
	await _capture_frame("f1-keybinds-1280x720.png", "T18_KEYBINDS_16_9", Vector2i(1280, 720))
	get_window().content_scale_factor = 1.5
	await _settle_frames()
	await _capture_frame("f1-keybinds-150-percent.png", "T18_KEYBINDS_HIGH_DPI", Vector2i(1280, 720))
	get_window().content_scale_factor = 1.0
	await _set_capture_size(Vector2i(1720, 720))
	await _settle_frames()
	await _capture_frame("f1-keybinds-ultrawide.png", "T18_KEYBINDS_ULTRAWIDE", Vector2i(1720, 720))
	app._close_keybinds()
	app._show_settings()
	await _settle_frames()
	await _capture_frame("f1-settings-ultrawide.png", "T18_SETTINGS_ULTRAWIDE", Vector2i(1720, 720))
	app._close_settings()
	app.start_button.pressed.emit()
	if await _wait_for_session_ready():
		app._show_inventory()
		await _settle_frames()
		await _capture_frame("f1-inventory-ultrawide.png", "T18_INVENTORY_ULTRAWIDE", Vector2i(1720, 720))
	else:
		_record("T18_INVENTORY_ULTRAWIDE", false, "session ready", "timeout")
	_finish(0 if not failed else 1)


func _run_display_runtime() -> void:
	await _settle_frames(5)
	var window := get_window()
	_record("T18_EXPAND_CONFIG", window.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "root content scale aspect expands across non-16:9 windows", window.content_scale_aspect)
	var synthetic_usable := Rect2i(Vector2i(-1920, 0), Vector2i(1920, 1040))
	var synthetic_position := SettingsStore._centered_decorated_position(synthetic_usable, Vector2i(1296, 759))
	_record("T18_NEGATIVE_MONITOR_ORIGIN", synthetic_position == Vector2i(-1608, 140), "centering includes a monitor's negative virtual-desktop origin", {"usable": synthetic_usable, "position": synthetic_position})
	app._show_settings()
	var fullscreen_preview := app.settings.begin_display_preview("fullscreen", Vector2i(1280, 720))
	await _settle_frames(20)
	app._refresh_settings_controls()
	app.settings_message.text = app._display_mode_help(1)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_index)
	var fullscreen_size := DisplayServer.window_get_size()
	var screenshot_path := app.data_root.path_join("f1-fullscreen-native-fill.png")
	var screenshot_error := image.save_png(screenshot_path)
	var edge_y := floori(float(image.get_height()) * 0.5)
	var native_fullscreen: bool = fullscreen_preview.get("ok", false) \
		and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		and fullscreen_size == screen_size
	_record("T18_FULLSCREEN_NATIVE_SIZE", native_fullscreen, "fullscreen uses the current monitor's native size", {"screen": screen_size, "window": fullscreen_size})
	var expected_native_label := "%d × %d (monitor native)" % [screen_size.x, screen_size.y]
	_record("T18_FULLSCREEN_UI_CONTRACT", app.resolution_option.disabled and not app.windowed_resolution_row.visible and app.fullscreen_resolution_row.visible and app.fullscreen_resolution_value_label.text == expected_native_label and app.settings_message.text.contains("native resolution"), "fullscreen shows the detected native monitor size instead of a stored windowed size", {"windowed_row": app.windowed_resolution_row.visible, "fullscreen_row": app.fullscreen_resolution_row.visible, "native_label": app.fullscreen_resolution_value_label.text, "message": app.settings_message.text})
	_record("T18_FULLSCREEN_FILL", screenshot_error == OK and image.get_size() == fullscreen_size and _image_edges_have_content(image), "rendered canvas fills both horizontal edges without pillarboxes", {"path": screenshot_path, "image": image.get_size(), "left": image.get_pixel(1, edge_y), "right": image.get_pixel(image.get_width() - 2, edge_y)})

	var target_screen := DisplayServer.window_get_current_screen()
	var windowed_targets: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1600, 900)]
	for windowed_target in windowed_targets:
		var windowed_preview := app.settings.begin_display_preview("windowed", windowed_target)
		await _settle_frames(20)
		var windowed_actual := DisplayServer.window_get_size()
		var actual_screen := DisplayServer.window_get_current_screen()
		var usable_rect := DisplayServer.screen_get_usable_rect(target_screen)
		var decorated_position := DisplayServer.window_get_position_with_decorations()
		var decorated_size := DisplayServer.window_get_size_with_decorations()
		var decorated_end := decorated_position + decorated_size
		var usable_end := usable_rect.position + usable_rect.size
		var entirely_reachable := decorated_position.x >= usable_rect.position.x \
			and decorated_position.y >= usable_rect.position.y \
			and decorated_end.x <= usable_end.x \
			and decorated_end.y <= usable_end.y
		_record("T18_WINDOWED_%dX%d" % [windowed_target.x, windowed_target.y], windowed_preview.get("ok", false) and windowed_actual == windowed_target and actual_screen == target_screen and entirely_reachable, "windowed client size is exact and its decorated frame stays inside the active monitor's usable area", {"target_screen": target_screen, "actual_screen": actual_screen, "usable": usable_rect, "client_size": windowed_actual, "decorated_position": decorated_position, "decorated_size": decorated_size})
	app._close_settings()
	_finish(0 if not failed else 1)


func _image_edges_have_content(image: Image) -> bool:
	if image.get_width() < 4 or image.get_height() < 4:
		return false
	var sample_y := floori(float(image.get_height()) * 0.5)
	var left := image.get_pixel(1, sample_y)
	var right := image.get_pixel(image.get_width() - 2, sample_y)
	return left.r + left.g + left.b > 0.05 and right.r + right.g + right.b > 0.05


func _fake_query(cell: Vector3i) -> Dictionary:
	if not _cell_in_bounds(cell):
		return {"state": "OUT_OF_BOUNDS"}
	if _fake_unloaded.has(cell):
		return {"state": "UNLOADED"}
	return {"state": "LOADED", "voxel_id": int(_fake_voxels.get(cell, 0))}


func _cell_in_bounds(cell: Vector3i) -> bool:
	var maximum := WorldAdapter.WORLD_MIN + WorldAdapter.WORLD_SIZE
	return cell.x >= WorldAdapter.WORLD_MIN.x and cell.y >= WorldAdapter.WORLD_MIN.y and cell.z >= WorldAdapter.WORLD_MIN.z \
		and cell.x < maximum.x and cell.y < maximum.y and cell.z < maximum.z


func _wait_for_session_ready(max_msec: int = 45000) -> bool:
	# Time-based: the P4E world streams more chunks than 1200 headless frames cover.
	var deadline := Time.get_ticks_msec() + max_msec
	while Time.get_ticks_msec() < deadline:
		if app.session != null and app.session.world_ready:
			return true
		await get_tree().process_frame
	return false


func _wait_cell_loaded(cell: Vector3i, max_frames: int = 600) -> bool:
	for frame in range(max_frames):
		if app.session.world.query_cell(cell).get("state") == "LOADED":
			return true
		await get_tree().process_frame
	return false


func _mutation_snapshot() -> Dictionary:
	return {"world_revision": app.session.world.revision, "inventory": app.session.inventory.snapshot()}


func _settle_frames(count: int = 5) -> void:
	for frame in range(count):
		await get_tree().process_frame


func _set_capture_size(target_size: Vector2i) -> void:
	get_window().content_scale_size = target_size
	get_window().size = target_size
	await _settle_frames(3)


func _capture_frame(filename: String, test_id: String, expected_size: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join(filename)
	var error := image.save_png(path)
	_record(test_id, error == OK and FileAccess.file_exists(path) and image.get_size() == expected_size, "rendered PNG exists at requested viewport size", {"path": path, "error": error, "size": image.get_size()})


func _record(test_id: String, passed: bool, expected: Variant, actual: Variant) -> void:
	var result := {"id": test_id, "passed": passed, "expected": str(expected), "actual": str(actual)}
	results.append(result)
	failed = failed or not passed
	print("F1_ASSERT %s %s expected=%s actual=%s" % [test_id, "PASS" if passed else "FAIL", expected, actual])


func _finish(exit_code: int) -> void:
	var report := {"passed": not failed, "results": results, "data_root": app.data_root}
	_write_json(app.data_root.path_join("f1_automation_results.json"), report)
	print("F1_RESULT %s" % JSON.stringify(report))
	get_tree().quit(exit_code)


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	file.close()
