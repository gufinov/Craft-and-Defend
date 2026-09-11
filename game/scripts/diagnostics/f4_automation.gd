class_name F4Automation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_foundation_phase1()
		"phase2":
			await _run_foundation_phase2()
		"capture-phase1":
			await _run_capture_phase1()
		"capture-phase2":
			await _run_capture_phase2()
		_:
			failures.append("unknown mode " + mode)
	_finish()


func _run_foundation_phase1() -> void:
	app.saves.select_slot("a")
	app._on_start_pressed()
	if not await _wait_ready():
		return
	await _wait_cell(Vector3i(0, -1, 38))
	var configured := is_equal_approx(app.session.clock.day_length_seconds, 1200.0) and absf(app.session.clock.phase - 0.25) < 0.002
	var initial_phase := app.session.clock.phase
	app.session.clock.advance(120.0, false)
	var playing_phase := app.session.clock.phase
	app.session.clock.advance(240.0, true)
	var explicit_pause_phase := app.session.clock.phase
	app._show_inventory()
	app.session.clock.advance(240.0, app.session.simulation_paused)
	var overlay_phase := app.session.clock.phase
	app._close_inventory()
	_record("T27_SIMULATION_CLOCK", configured and is_equal_approx(playing_phase, initial_phase + 0.1) and is_equal_approx(explicit_pause_phase, playing_phase) and is_equal_approx(overlay_phase, playing_phase), "configured day phase advances only during unpaused simulation and freezes in overlays", {"initial": initial_phase, "playing": playing_phase, "paused": explicit_pause_phase, "overlay": overlay_phase, "day_length": app.session.clock.day_length_seconds})

	var restored_night := app.session.clock.restore({"phase": 0.75, "day_index": 3})
	app.session.clock.apply_visuals(app.session._environment, app.session._sun)
	app.session._emit_hud()
	await _settle_frames(3)
	var night_capture := await app.screenshots.capture_viewport(get_viewport())
	var night_image := Image.load_from_file(str(night_capture.get("path", ""))) if night_capture.get("ok", false) else null
	var night_readable := restored_night and app.session._environment.ambient_light_energy >= 0.5 and app.session._environment.background_color.get_luminance() > 0.03 and night_image != null and not night_image.is_empty()
	_record("T27_NIGHT_READABLE", night_readable, "night uses a visible sky and minimum ambient fill instead of blacking out terrain", {"capture": night_capture, "ambient": app.session._environment.ambient_light_energy, "background": app.session._environment.background_color})

	var unique_colors := {}
	var all_assets := true
	for block_index in range(1, WorldAdapter.BLOCK_NAMES.size()):
		unique_colors[WorldAdapter.BLOCK_COLORS[block_index].to_html()] = true
		all_assets = all_assets and FileAccess.file_exists("res://assets/blocks/%s.svg" % WorldAdapter.BLOCK_NAMES[block_index])
	var hud_help := app.hud_label.text.contains("Slot 1") and app.hud_label.text.contains("F2 capture") and app.hud_label.text.contains("Night")
	var failed_craft := app.session.try_craft("planks", "hand")
	await get_tree().process_frame
	var feedback_visible: bool = failed_craft.get("reason") == "INSUFFICIENT_INPUT" and app.feedback_label.text.contains("Missing")
	_record("T28_PRESENTATION", all_assets and unique_colors.size() == WorldAdapter.BLOCK_NAMES.size() - 1 and hud_help and feedback_visible, "block resources are distinct and selection, key help, clock and craft feedback are visible", {"assets": all_assets, "unique_colors": unique_colors.size(), "hud": app.hud_label.text, "feedback": app.feedback_label.text})

	var capture_count := _capture_files().size()
	var capture_event := InputEventKey.new()
	capture_event.pressed = true
	capture_event.physical_keycode = KEY_F2
	var frame_before := Engine.get_physics_frames()
	app._unhandled_input(capture_event)
	var capture_path := await _wait_for_capture(capture_count + 1)
	var capture_image := Image.load_from_file(capture_path) if not capture_path.is_empty() else null
	var capture_live := app.state == app.AppState.PLAYING and not get_tree().paused and not app.session.simulation_paused and app.session.player.active and Engine.get_physics_frames() > frame_before
	_record("T28_CAPTURE_BACKGROUND", not capture_path.is_empty() and capture_live and capture_image != null and capture_image.get_size() == Vector2i(get_viewport().get_visible_rect().size), "F2 writes the rendered game viewport while gameplay remains active", {"path": capture_path, "frames_before": frame_before, "frames_after": Engine.get_physics_frames(), "tree_paused": get_tree().paused, "session_paused": app.session.simulation_paused})

	var metrics := await _measure_fixed_scenario()
	var save_result := await app.saves.save_session(app.session)
	metrics["save_msec"] = save_result.get("save_msec", -1)
	metrics["checkpoint_bytes"] = save_result.get("checkpoint_bytes", -1)
	_record("T29_FIXED_MEASUREMENTS", save_result.get("ok", false) and float(metrics.get("frame_p95_msec", 0.0)) > 0.0 and int(metrics.get("edit_count", 0)) == 100 and int(metrics.get("memory_static_bytes", 0)) > 0 and int(metrics.get("checkpoint_bytes", 0)) > 0, "fixed scenario records frame, edit, memory and coherent-save measurements", metrics)


func _run_foundation_phase2() -> void:
	app.saves.select_slot("a")
	var phase_before_open := -1.0
	var status := app.saves.checkpoint_status()
	if status.get("ok", false):
		var checkpoint_dir := str(status.get("checkpoint_dir", ""))
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(checkpoint_dir.path_join("gameplay.json")))
		if parsed is Dictionary:
			phase_before_open = float(parsed.get("clock", {}).get("phase", -1.0))
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	var restored_phase := app.session.clock.phase
	var no_offline_catchup := phase_before_open >= 0.0 and absf(restored_phase - phase_before_open) < 0.002
	var before_resume := restored_phase
	await _settle_frames(10)
	var resumed := app.session.clock.phase > before_resume
	_record("T27_CLOCK_RESTART", no_offline_catchup and resumed and app.session.clock.day_index == 3, "Continue restores the saved phase without wall-clock catch-up, then resumes advancing", {"saved": phase_before_open, "restored": restored_phase, "after_frames": app.session.clock.phase, "day": app.session.clock.day_index})
	_record("T30_FOUNDATION_CONTINUE", app.session.world_ready and app.session.inventory != null and app.session.workstations != null and app.session.clock != null, "clean-process Continue restores the complete Foundation session", {"world_ready": app.session.world_ready, "slot": app.saves.slot_id, "clock": app.session.clock.snapshot()})


func _run_capture_phase1() -> void:
	_record("T28_CAPTURE_DEFAULT", app.settings.get_keycode("capture_screenshot") == KEY_F2, "gameplay capture defaults to F2", app.settings.get_binding("capture_screenshot"))
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var frame_before := Engine.get_physics_frames()
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_F2
	app._unhandled_input(event)
	var capture_path := await _wait_for_capture(1)
	var image := Image.load_from_file(capture_path) if not capture_path.is_empty() else null
	var state_unchanged := app.state == app.AppState.PLAYING and not get_tree().paused and not app.session.simulation_paused and app.session.player.active
	var image_valid := image != null and not image.is_empty() and image.get_size() == Vector2i(get_viewport().get_visible_rect().size)
	_record("T28_CAPTURE_BACKGROUND", not capture_path.is_empty() and state_unchanged and Engine.get_physics_frames() > frame_before and image_valid, "one F2 press writes the rendered game viewport while gameplay remains active", {"path": capture_path, "state": app.state, "tree_paused": get_tree().paused, "session_paused": app.session.simulation_paused, "player_active": app.session.player.active, "frames_before": frame_before, "frames_after": Engine.get_physics_frames(), "image_size": image.get_size() if image != null else Vector2i.ZERO})
	var rebound := app.settings.rebind_key("capture_screenshot", KEY_F8)
	_record("T28_CAPTURE_REBIND", rebound.get("ok", false) and app.settings.get_keycode("capture_screenshot") == KEY_F8, "capture can be rebound and saved through the global settings store", rebound)


func _run_capture_phase2() -> void:
	_record("T28_CAPTURE_RESTART", app.settings.get_keycode("capture_screenshot") == KEY_F8, "capture binding persists across a full process restart", app.settings.get_binding("capture_screenshot"))
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var existing := _capture_files().size()
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_F8
	app._unhandled_input(event)
	var capture_path := await _wait_for_capture(existing + 1)
	_record("T28_CAPTURE_REBOUND_ACTION", not capture_path.is_empty() and app.state == app.AppState.PLAYING and not get_tree().paused and not app.session.simulation_paused, "the persisted replacement key captures without pausing", {"path": capture_path, "feedback": app.feedback_label.text})
	var reset := app.settings.reset_action("capture_screenshot")
	_record("T28_CAPTURE_RESET", reset.get("ok", false) and app.settings.get_keycode("capture_screenshot") == KEY_F2, "per-action Reset restores F2", reset)


func _wait_ready() -> bool:
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 20000:
		await get_tree().process_frame
	if app.state != app.AppState.PLAYING:
		failures.append("session ready timeout: " + app.status_label.text)
		return false
	return true


func _wait_cell(cell: Vector3i) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		if app.session.world.query_cell(cell).get("state") == "LOADED":
			return
		await get_tree().process_frame
	failures.append("cell load timeout " + str(cell))


func _settle_frames(count: int = 3) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func _measure_fixed_scenario() -> Dictionary:
	var frame_samples: Array[float] = []
	for _frame in range(60):
		var started := Time.get_ticks_usec()
		await get_tree().process_frame
		frame_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	frame_samples.sort()
	var edit_cell := Vector3i(0, -1, 38)
	var original_voxel := int(app.session.world.query_cell(edit_cell).get("voxel_id", 1))
	var edit_started := Time.get_ticks_usec()
	var edits_ok := true
	for index in range(100):
		var voxel_id := 0 if index % 2 == 0 else original_voxel
		edits_ok = app.session.world.set_cell(edit_cell, voxel_id) and edits_ok
	var edit_total_usec := Time.get_ticks_usec() - edit_started
	if int(app.session.world.query_cell(edit_cell).get("voxel_id", -1)) != original_voxel:
		edits_ok = app.session.world.set_cell(edit_cell, original_voxel) and edits_ok
	return {
		"scenario": "60 rendered frames; 100 alternating loaded-cell edits; coherent slot A save",
		"resolution": Vector2i(get_viewport().get_visible_rect().size),
		"renderer": RenderingServer.get_video_adapter_name(),
		"frame_average_msec": _average(frame_samples),
		"frame_p95_msec": frame_samples[min(frame_samples.size() - 1, floori(frame_samples.size() * 0.95))],
		"frame_max_msec": frame_samples[-1],
		"edit_count": 100,
		"edits_ok": edits_ok,
		"edit_total_msec": float(edit_total_usec) / 1000.0,
		"edit_average_msec": float(edit_total_usec) / 100000.0,
		"memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size()) if not values.is_empty() else 0.0


func _wait_for_capture(expected_count: int) -> String:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 5000:
		var files := _capture_files()
		if files.size() >= expected_count:
			return app.screenshots.screenshots_root.path_join(files[-1])
		await get_tree().process_frame
	return ""


func _capture_files() -> PackedStringArray:
	var files := PackedStringArray()
	var directory := DirAccess.open(app.screenshots.screenshots_root)
	if directory == null:
		return files
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.get_extension().to_lower() == "png":
			files.append(filename)
		filename = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files


func _record(test_id: String, passed: bool, expected: String, actual: Variant) -> void:
	print("F4_ASSERT %s %s expected=%s actual=%s" % [test_id, "PASS" if passed else "FAIL", expected, JSON.stringify(actual)])
	if not passed:
		failures.append(test_id)


func _finish() -> void:
	if failures.is_empty():
		print("F4_CAPTURE_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("F4_CAPTURE_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)
