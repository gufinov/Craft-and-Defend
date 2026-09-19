class_name F3Automation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_phase1()
		"phase2":
			await _run_phase2()
		"validation":
			_run_validation()
		_:
			failures.append("unknown mode " + mode)
	_finish()


func _run_phase1() -> void:
	app.saves.select_slot("a")
	app._on_start_pressed()
	if not await _wait_ready():
		return
	await _wait_cell(Vector3i(0, -1, 38))
	var edit_a := app.session.interaction.try_break_cell(Vector3i(0, -1, 38))
	app.session.inventory.try_transaction({}, {"furnace": 1, "iron_ore": 1, "coal": 1})
	var placed := app.session.workstations.try_place("furnace", Vector3i(3, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var furnace_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var loaded := app.session.workstations.try_load_furnace_recipe(furnace_id, "iron_ingot")
	var started := app.session.workstations.try_start_furnace(furnace_id, "iron_ingot")
	app.session.workstations.advance(2.0, false)
	var remaining := float(app.session.workstations.jobs.get(furnace_id, {}).get("remaining_seconds", -1.0))
	var saved_a := await app.saves.save_session(app.session)
	_record("T26_MIDJOB_SAVED", edit_a.get("ok", false) and placed.get("ok", false) and loaded.get("ok", false) and started.get("ok", false) and is_equal_approx(remaining, 3.0) and saved_a.get("ok", false), "slot A saves a three-second remaining furnace job and its owned container", {"loaded": loaded, "remaining": remaining, "save": saved_a})
	await _dispose_session()
	app.saves.select_slot("a")
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	app.saves.set_test_failure("denied_write")
	await app._save_then(false)
	var save_error_ui := app.state == app.AppState.ERROR and app.session != null and app.session.simulation_paused and app.loading_retry_button.visible and app.loading_return_button.visible
	app._return_from_save_error()
	var returned_paused := app.state == app.AppState.PAUSED and app.session != null and app.session.simulation_paused and app.pause_panel.visible
	_record("T24_RECOVERABLE_UI", save_error_ui and returned_paused, "save failure offers retry or a safe return to the paused session", {"error_ui": save_error_ui, "returned_paused": returned_paused})
	app._resume_game()
	var failure_results: Dictionary = {}
	for point in ["disk_full", "before_checkpoint_publish", "after_checkpoint_publish", "before_pointer_publish", "during_pointer_publish"]:
		app.saves.set_test_failure(point)
		var failed_save := await app.saves.save_session(app.session)
		var prior := app.saves.checkpoint_status()
		failure_results[point] = {"save_reason": failed_save.get("reason", ""), "prior_ok": prior.get("ok", false), "prior_revision": prior.get("revision", -1)}
	var expected_reasons := {
		"disk_full": "INJECTED_DISK_FULL",
		"before_checkpoint_publish": "INJECTED_BEFORE_CHECKPOINT_PUBLISH",
		"after_checkpoint_publish": "INJECTED_AFTER_CHECKPOINT_PUBLISH",
		"before_pointer_publish": "INJECTED_BEFORE_POINTER_PUBLISH",
		"during_pointer_publish": "INJECTED_DURING_POINTER_PUBLISH",
	}
	var failures_safe := true
	for point in expected_reasons:
		var result: Dictionary = failure_results.get(point, {})
		failures_safe = failures_safe and str(result.get("save_reason", "")) == expected_reasons[point] and result.get("prior_ok", false) and int(result.get("prior_revision", -1)) == 1
	_record("T24_FAILURE_RECOVERY", failures_safe, "five injected publication failures preserve slot A checkpoint 1", failure_results)
	var saved_a2 := await app.saves.save_session(app.session)
	await _dispose_session()
	app.saves.select_slot("a")
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	var saved_a3 := await app.saves.save_session(app.session)
	var retained := _completed_checkpoint_count(app.saves.slots_root)
	var retention_ok: bool = saved_a2.get("ok", false) and int(saved_a2.get("revision", -1)) == 2 and saved_a3.get("ok", false) and int(saved_a3.get("revision", -1)) == 3 and retained == SaveCoordinator.CHECKPOINTS_TO_KEEP
	_record("T24_RETENTION", retention_ok, "repeated saves advance revisions and retain exactly two completed checkpoints", {"save_2": saved_a2, "save_3": saved_a3, "retained": retained})
	await _dispose_session()
	app.saves.select_slot("b")
	var b_empty := not app.saves.has_checkpoint()
	app._show_main_menu()
	app._on_start_pressed()
	if not await _wait_ready():
		return
	await _wait_cell(Vector3i(2, -1, 38))
	var clean_b := app.session.inventory.count("dirt") == 0 and int(app.session.world.query_cell(Vector3i(0, -1, 38)).get("voxel_id", -1)) != 0
	var edit_b := app.session.interaction.try_break_cell(Vector3i(2, -1, 38))
	var saved_b := await app.saves.save_session(app.session)
	_record("T23_SLOT_B_CREATED", b_empty and clean_b and edit_b.get("ok", false) and saved_b.get("ok", false), "slot B starts clean and publishes only its own edit", {"empty": b_empty, "clean": clean_b, "save": saved_b})


func _run_phase2() -> void:
	app.saves.select_slot("a")
	app._show_main_menu()
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	var a_cell := app.session.world.query_cell(Vector3i(0, -1, 38))
	var a_other := app.session.world.query_cell(Vector3i(2, -1, 38))
	var jobs := app.session.workstations.jobs
	var furnace_id := str(jobs.keys()[0]) if jobs.size() == 1 else ""
	var remaining := float(jobs.get(furnace_id, {}).get("remaining_seconds", -1.0))
	var a_isolated := int(a_cell.get("voxel_id", -1)) == 0 and int(a_other.get("voxel_id", -1)) != 0 and app.session.inventory.count("dirt") == 1
	_record("T23_SLOT_A_RESTORE", a_isolated, "slot A restores only A terrain and inventory", {"a_cell": a_cell, "b_cell": a_other, "dirt": app.session.inventory.count("dirt")})
	var before := int(app.session.workstations.furnace_slots(furnace_id).output.count)
	app.session.workstations.advance(2.9, false)
	var before_finish := int(app.session.workstations.furnace_slots(furnace_id).output.count)
	app.session.workstations.advance(0.11, false)
	var completed := int(app.session.workstations.furnace_slots(furnace_id).output.count)
	app.session.workstations.advance(10.0, false)
	var after_extra := int(app.session.workstations.furnace_slots(furnace_id).output.count)
	var collected := app.session.collect_furnace_stack(furnace_id, "output")
	_record("T26_MIDJOB_CONTINUE", is_equal_approx(remaining, 3.0) and before == 0 and before_finish == 0 and completed == 1 and after_extra == 1 and collected.get("ok", false) and app.session.inventory.count("iron_ingot") == 1 and app.session.workstations.jobs.is_empty(), "mid-job restart preserves remaining time, retains one output exactly once and permits explicit collection", {"remaining": remaining, "before": before, "before_finish": before_finish, "completed": completed, "after_extra": after_extra, "collected": collected})
	await _dispose_session()
	app.saves.select_slot("b")
	app._show_main_menu()
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	var b_cell := app.session.world.query_cell(Vector3i(2, -1, 38))
	var b_other := app.session.world.query_cell(Vector3i(0, -1, 38))
	var b_isolated := int(b_cell.get("voxel_id", -1)) == 0 and int(b_other.get("voxel_id", -1)) != 0 and app.session.inventory.count("dirt") == 1 and app.session.workstations.jobs.is_empty()
	_record("T23_SLOT_B_RESTORE", b_isolated, "slot B restores only B terrain and inventory", {"b_cell": b_cell, "a_cell": b_other, "dirt": app.session.inventory.count("dirt")})


func _run_validation() -> void:
	var root := app.data_root.path_join("validation")
	var malformed_root := root.path_join("malformed")
	_write_text(malformed_root.path_join("slots/a/current.json"), "{not-json")
	var malformed_store := SaveCoordinator.new(malformed_root)
	var malformed_before := FileAccess.get_file_as_string(malformed_store.current_pointer_path)
	var malformed := malformed_store.checkpoint_status()
	var malformed_after := FileAccess.get_file_as_string(malformed_store.current_pointer_path)
	var newer_root := root.path_join("newer")
	_write_json(newer_root.path_join("slots/a/current.json"), {"schema_version": 999, "revision": 1, "checkpoint": "future"})
	var newer_store := SaveCoordinator.new(newer_root)
	var newer := newer_store.checkpoint_status()
	var newer_after := FileAccess.get_file_as_string(newer_store.current_pointer_path)
	var missing_root := root.path_join("missing-content")
	_make_checkpoint(missing_root, "a", "missing-foundation")
	var missing_store := SaveCoordinator.new(missing_root)
	var missing := missing_store.checkpoint_status()
	var refused: bool = malformed.get("reason") == "MALFORMED_POINTER" and malformed_before == malformed_after and newer.get("reason") == "UNSUPPORTED_SAVE_SCHEMA" and newer_after.contains("999") and missing.get("reason") == "MISSING_CONTENT_VERSION"
	_record("T25_INVALID_REFUSAL", refused, "malformed, newer and missing-content saves are refused without replacement", {"malformed": malformed, "newer": newer, "missing": missing})
	var migration_root := root.path_join("migration")
	_make_checkpoint(migration_root, "default", SaveCoordinator.CONTENT_VERSION)
	var legacy_pointer := migration_root.path_join("slots/default/current.json")
	var legacy_before := FileAccess.get_file_as_string(legacy_pointer)
	var migrated_store := SaveCoordinator.new(migration_root)
	var migrated := migrated_store.checkpoint_status("a")
	var migration_safe: bool = migrated_store.migration_report.get("migrated", false) and migrated_store.migration_report.get("source_preserved", false) and migrated.get("ok", false) and FileAccess.get_file_as_string(legacy_pointer) == legacy_before
	_record("T25_LAYOUT_MIGRATION", migration_safe, "legacy default slot is copied to A and the source remains unchanged", {"report": migrated_store.migration_report, "status": migrated})


func _make_checkpoint(root: String, slot: String, content_version: String) -> void:
	var checkpoint := root.path_join("slots/%s/checkpoints/checkpoint_000001_fixture" % slot)
	_write_text(checkpoint.path_join("world.sqlite"), "fixture-database")
	var gameplay := {"schema_version": SaveCoordinator.SAVE_SCHEMA, "content_version": content_version, "inventory": {"dirt": 0, "revision": 0}, "workstations": {"stations": [], "jobs": {}}, "player": {"position": [0.5, 2.0, 40.5]}}
	_write_json(checkpoint.path_join("gameplay.json"), gameplay)
	var manifest := {"schema_version": SaveCoordinator.SAVE_SCHEMA, "content_version": content_version, "checkpoint_revision": 1, "database_sha256": FileAccess.get_sha256(checkpoint.path_join("world.sqlite")), "gameplay_sha256": FileAccess.get_sha256(checkpoint.path_join("gameplay.json"))}
	_write_json(checkpoint.path_join("manifest.json"), manifest)
	_write_json(root.path_join("slots/%s/current.json" % slot), {"schema_version": SaveCoordinator.SAVE_SCHEMA, "revision": 1, "checkpoint": "checkpoint_000001_fixture", "slot_id": slot})


func _write_json(path: String, data: Dictionary) -> void:
	_write_text(path, JSON.stringify(data, "  "))


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("write failed " + path)
		return
	file.store_string(text)
	file.close()


func _completed_checkpoint_count(checkpoints_root: String) -> int:
	var directory := DirAccess.open(checkpoints_root)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if directory.current_is_dir() and name.begins_with("checkpoint_") and FileAccess.file_exists(checkpoints_root.path_join(name).path_join("manifest.json")):
			count += 1
		name = directory.get_next()
	directory.list_dir_end()
	return count


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


func _dispose_session() -> void:
	if app.session != null:
		if app.session.world != null and app.session.world.stream != null and not app.session.world.stream.database_path.is_empty():
			app.session.world.detach_and_close_stream()
		app.session.queue_free()
		app.session = null
		await get_tree().process_frame
	app._show_main_menu()


func _record(test_id: String, passed: bool, expected: String, actual: Variant) -> void:
	print("F3_ASSERT %s %s expected=%s actual=%s" % [test_id, "PASS" if passed else "FAIL", expected, JSON.stringify(actual)])
	if not passed:
		failures.append(test_id)


func _finish() -> void:
	if failures.is_empty():
		print("F3_AUTOMATION_PASS T23-T26")
		get_tree().quit(0)
	else:
		push_error("F3_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)
