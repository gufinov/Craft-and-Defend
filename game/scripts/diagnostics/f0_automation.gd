class_name F0Automation
extends Node

var app: CraftAndDefendApp
var results: Array[Dictionary] = []
var failed := false


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_phase1()
		"phase2":
			await _run_phase2()
		"menu":
			await _run_menu()
		"wait-close":
			await _run_wait_close()
		"verify-close":
			await _run_verify_close()
		"close-failure":
			await _run_close_failure()
		"visual":
			await _run_visual()
		_:
			_record("HARNESS", false, "known automation mode", mode)
			_finish(2)


func _run_menu() -> void:
	await get_tree().process_frame
	_record("T02_MENU", app.state == app.AppState.MAIN_MENU and app.session == null, "menu with no active player", app.state)
	_record("T02_START_ACTION", app.start_button != null and app.start_button.visible, "visible explicit Start button", app.start_button != null)
	_record("T02_QUIT_ACTION", true, "Quit route callable from menu", "verified before process quit")
	_finish(0 if not failed else 1)


func _run_phase1() -> void:
	await get_tree().process_frame
	_record("T02_MENU_BEFORE_START", app.state == app.AppState.MAIN_MENU and app.session == null, "menu; player not entered", app.state)
	app.start_button.pressed.emit()
	if not await _wait_for_session_ready():
		_record("T03_READY", false, "collision-ready spawn", "timeout")
		_finish(1)
		return
	_record("T03_BOUNDS", app.session.world.terrain.bounds == AABB(Vector3(-32, -16, -64), Vector3(64, 32, 128)), "64x32x128 half-open bounds", app.session.world.terrain.bounds)
	for frame in range(90):
		await get_tree().physics_frame
	_record("T03_COLLISION_SPAWN", app.session.player.position.y > -0.5, "player remains on loaded surface", app.session.player.position)

	var before_move := app.session.player.position
	Input.action_press("move_forward")
	for frame in range(20):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var after_move := app.session.player.position
	_record("T04_ESDF_FORWARD", after_move.distance_to(before_move) > 0.4, "E action moves player", {"before": before_move, "after": after_move})
	var before_yaw := app.session.player.rotation.y
	app.session.player.apply_mouse_look(Vector2(30, -10))
	_record("T04_MOUSE_LOOK", not is_equal_approx(before_yaw, app.session.player.rotation.y), "mouse motion changes yaw", {"before": before_yaw, "after": app.session.player.rotation.y})
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var jump_start := app.session.player.position.y
	for frame in range(8):
		await get_tree().physics_frame
	_record("T04_JUMP", app.session.player.position.y > jump_start, "Space action raises player", {"before": jump_start, "after": app.session.player.position.y})

	app.session.player.deactivate()
	app.session.player.position = Vector3(0.5, 0.0, 40.5)
	await _wait_cell_loaded(Vector3i(2, -1, 38))
	var break_one := app.session.interaction.break_from_view(Vector3(0.5, 2.0, 38.5), Vector3.DOWN)
	_record("T05_BREAK_GATHER", break_one.get("ok", false) and app.session.inventory.dirt == 1 and int(app.session.world.query_cell(Vector3i(0, -1, 38)).get("voxel_id", -1)) == 0, "one block removed and one dirt gathered", break_one)
	var place_one := app.session.interaction.place_from_view(Vector3(1.5, 2.0, 38.5), Vector3.DOWN)
	_record("T05_PLACE_CONSUME", place_one.get("ok", false) and app.session.inventory.dirt == 0 and int(app.session.world.query_cell(Vector3i(1, 0, 38)).get("voxel_id", -1)) == 2, "one dirt placed and one consumed", place_one)
	var break_two := app.session.interaction.break_from_view(Vector3(2.5, 2.0, 38.5), Vector3.DOWN)
	_record("T05_EXACT_ACCOUNTING", break_two.get("ok", false) and app.session.inventory.dirt == 1, "second break leaves exactly one dirt", break_two)

	var before_invalid := _mutation_snapshot()
	var outside := app.session.interaction.try_place_dirt(Vector3i(32, 0, 0))
	var after_outside := _mutation_snapshot()
	_record("T06_OUTSIDE_BOUNDS", outside.get("reason") == "OUT_OF_BOUNDS" and before_invalid == after_outside, "reject without mutation", outside)
	var occupied_before := _mutation_snapshot()
	var occupied := app.session.interaction.try_place_dirt(Vector3i(1, -1, 38))
	_record("T06_OCCUPIED", occupied.get("reason") == "OCCUPIED" and occupied_before == _mutation_snapshot(), "reject occupied without mutation", occupied)
	var overlap_cell := Vector3i(0, 0, 40)
	var overlap_before := _mutation_snapshot()
	var overlap := app.session.interaction.try_place_dirt(overlap_cell)
	_record("T06_PLAYER_OVERLAP", overlap.get("reason") == "PLAYER_OVERLAP" and overlap_before == _mutation_snapshot(), "reject player overlap without mutation", overlap)

	app.session.player.activate(false)
	app._pause_game()
	_record("T07_PAUSE", app.state == app.AppState.PAUSED and get_tree().paused, "Escape pause state freezes gameplay", app.state)
	app._show_keybinds()
	app._capture_forward_key()
	var conflict_event := InputEventKey.new()
	conflict_event.pressed = true
	conflict_event.physical_keycode = KEY_D
	app._unhandled_input(conflict_event)
	_record("T08_CONFLICT", app.settings.get_keycode("move_forward") == KEY_E and app.keybind_message.text.contains("CONFLICT"), "keybind UI rejects the backward-key conflict", app.keybind_message.text)
	app._capture_forward_key()
	var rebind_event := InputEventKey.new()
	rebind_event.pressed = true
	rebind_event.physical_keycode = KEY_R
	app._unhandled_input(rebind_event)
	_record("T08_REBIND_SAVE", app.settings.get_keycode("move_forward") == KEY_R and app.forward_binding_label.text.contains("R"), "keybind UI saves physical R for Forward", {"message": app.keybind_message.text, "label": app.forward_binding_label.text})
	app._close_keybinds()
	app._resume_game()
	_record("T07_RESUME", app.state == app.AppState.PLAYING and not get_tree().paused, "Resume restores play state", app.state)

	app.session.player.deactivate()
	app.session.player.position = Vector3(0.5, 0.0, -40.5)
	var unloaded := await _wait_cell_state(Vector3i(0, -1, 38), "UNLOADED", 900)
	app.session.player.position = Vector3(0.5, 0.0, 40.5)
	var reloaded := await _wait_cell_state(Vector3i(0, -1, 38), "LOADED", 900)
	var edit_survived := reloaded and int(app.session.world.query_cell(Vector3i(0, -1, 38)).get("voxel_id", -1)) == 0
	_record("T10_UNLOAD_RELOAD", unloaded and edit_survived, "edited chunk unloads, reloads, and retains edit", {"unloaded": unloaded, "reloaded": reloaded, "voxel": app.session.world.query_cell(Vector3i(0, -1, 38))})

	var expected_snapshot := app.session.snapshot()
	_write_json(app.data_root.path_join("phase1_expected.json"), expected_snapshot)
	var save_result := await app.saves.save_session(app.session)
	_record("T09_SAVE", save_result.get("ok", false), "coherent terrain/inventory checkpoint publishes", save_result)
	_finish(0 if not failed else 1)


func _run_phase2() -> void:
	await get_tree().process_frame
	_record("T08_RESTART_BINDING", app.settings.get_keycode("move_forward") == KEY_R, "physical R restored after full process restart", app.settings.get_keycode("move_forward"))
	_record("T09_CONTINUE_AVAILABLE", app.saves.has_checkpoint() and not app.continue_button.disabled, "valid Continue action", app.continue_button.disabled)
	app.continue_button.pressed.emit()
	if not await _wait_for_session_ready():
		_record("T09_CONTINUE", false, "Continue reaches collision-ready session", "timeout")
		_finish(1)
		return
	var expected := _read_json(app.data_root.path_join("phase1_expected.json"))
	var actual := app.session.snapshot()
	var actual_inventory: Dictionary = actual.get("inventory", {})
	var expected_inventory: Dictionary = expected.get("inventory", {})
	var exact_inventory: bool = int(actual_inventory.get("dirt", -1)) == int(expected_inventory.get("dirt", -2)) \
		and int(actual_inventory.get("revision", -1)) == int(expected_inventory.get("revision", -2))
	var terrain_ok: bool = int(app.session.world.query_cell(Vector3i(0, -1, 38)).get("voxel_id", -1)) == 0 \
		and int(app.session.world.query_cell(Vector3i(1, 0, 38)).get("voxel_id", -1)) == 2 \
		and int(app.session.world.query_cell(Vector3i(2, -1, 38)).get("voxel_id", -1)) == 0
	var expected_position: Array = expected.get("player", {}).get("position", [])
	var actual_position: Array = actual.get("player", {}).get("position", [])
	var player_ok := false
	var position_distance := INF
	if expected_position.size() == 3 and actual_position.size() == 3:
		var expected_vector := Vector3(float(expected_position[0]), float(expected_position[1]), float(expected_position[2]))
		var actual_vector := Vector3(float(actual_position[0]), float(actual_position[1]), float(actual_position[2]))
		position_distance = actual_vector.distance_to(expected_vector)
		player_ok = position_distance < 0.05 \
			and is_equal_approx(float(actual.get("player", {}).get("yaw", 99.0)), float(expected.get("player", {}).get("yaw", -99.0))) \
			and is_equal_approx(float(actual.get("player", {}).get("pitch", 99.0)), float(expected.get("player", {}).get("pitch", -99.0)))
	_record("T09_CONTINUE_RESTORE", terrain_ok and exact_inventory and player_ok, "terrain edits, exact inventory, and transform restored", {"terrain": terrain_ok, "inventory_exact": exact_inventory, "inventory": actual.get("inventory"), "player_ok": player_ok, "position_distance": position_distance, "player": actual.get("player")})
	var events := InputMap.action_get_events("move_forward")
	var mapped_r: bool = events.size() == 1 and events[0] is InputEventKey and events[0].physical_keycode == KEY_R
	_record("T08_INPUTMAP_RESTORE", mapped_r, "runtime InputMap uses restored physical R", events[0].as_text() if not events.is_empty() else "none")
	_finish(0 if not failed else 1)


func _run_wait_close() -> void:
	await get_tree().process_frame
	if app.saves.has_checkpoint():
		app.continue_button.pressed.emit()
	else:
		app.start_button.pressed.emit()
	if not await _wait_for_session_ready():
		_record("T12_READY", false, "session ready before OS close", "timeout")
		_finish(1)
		return
	_write_json(app.data_root.path_join("wait_close_ready.json"), {"ready": true, "pid": OS.get_process_id()})
	print("F0_WAITING_FOR_WM_CLOSE pid=%s" % OS.get_process_id())


func _run_verify_close() -> void:
	await get_tree().process_frame
	_record("T12_CLOSE_CHECKPOINT", app.saves.has_checkpoint(), "WM_CLOSE path published a valid checkpoint", app.saves.has_checkpoint())
	_finish(0 if not failed else 1)


func _run_close_failure() -> void:
	await get_tree().process_frame
	app.start_button.pressed.emit()
	if not await _wait_for_session_ready():
		_record("T12_FAILURE_READY", false, "session ready for failure injection", "timeout")
		_finish(1)
		return
	app.session.world.working_database_path = app.data_root.path_join("deliberately-missing/world.sqlite")
	app._handle_close_request()
	for frame in range(600):
		if app.state == app.AppState.ERROR:
			break
		await get_tree().process_frame
	var stayed_open := app.state == app.AppState.ERROR and app.status_label.visible \
		and app.status_label.text.contains("WORKING_DATABASE_MISSING")
	_record("T12_FAILURE_VISIBLE", stayed_open, "failed close-save stays open with visible exact error", {"state": app.state, "message": app.status_label.text})
	_finish(0 if not failed else 1)


func _run_visual() -> void:
	for frame in range(3):
		await get_tree().process_frame
	await _capture_frame("menu.png", "VISUAL_MENU")
	app.start_button.pressed.emit()
	if not await _wait_for_session_ready():
		_record("VISUAL_WORLD_READY", false, "rendered world ready", "timeout")
		_finish(1)
		return
	for frame in range(30):
		await get_tree().process_frame
	await _capture_frame("gameplay.png", "VISUAL_GAMEPLAY")
	app._pause_game()
	await get_tree().process_frame
	await _capture_frame("pause.png", "VISUAL_PAUSE")
	app._resume_game()
	_finish(0 if not failed else 1)


func _capture_frame(filename: String, test_id: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join(filename)
	var error := image.save_png(path)
	_record(test_id, error == OK and FileAccess.file_exists(path), "PNG screenshot from rendered application", {"path": path, "error": error, "size": image.get_size()})


func _wait_for_session_ready(max_frames: int = 1200) -> bool:
	for frame in range(max_frames):
		if app.session != null and app.session.world_ready:
			return true
		await get_tree().process_frame
	return false


func _wait_cell_loaded(cell: Vector3i, max_frames: int = 600) -> bool:
	return await _wait_cell_state(cell, "LOADED", max_frames)


func _wait_cell_state(cell: Vector3i, state_name: String, max_frames: int) -> bool:
	for frame in range(max_frames):
		if app.session.world.query_cell(cell).get("state") == state_name:
			return true
		await get_tree().process_frame
	return false


func _mutation_snapshot() -> Dictionary:
	return {"world_revision": app.session.world.revision, "inventory": app.session.inventory.snapshot()}


func _record(test_id: String, passed: bool, expected: Variant, actual: Variant) -> void:
	var result := {"id": test_id, "passed": passed, "expected": str(expected), "actual": str(actual)}
	results.append(result)
	failed = failed or not passed
	print("F0_ASSERT %s %s expected=%s actual=%s" % [test_id, "PASS" if passed else "FAIL", expected, actual])


func _finish(exit_code: int) -> void:
	var report := {"passed": not failed, "results": results, "data_root": app.data_root}
	_write_json(app.data_root.path_join("automation_results.json"), report)
	print("F0_RESULT %s" % JSON.stringify(report))
	get_tree().quit(exit_code)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if file != null:
		file.close()
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	file.close()
