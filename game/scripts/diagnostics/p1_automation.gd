class_name P1Automation
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
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	if failures.is_empty():
		print("P1_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P1_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	var config := _read_json("res://data/world.json")
	var terrain_settings: Dictionary = config.get("terrain", {})
	var legacy := WorldAdapter.resolve_generation({}, config)
	var current := WorldAdapter.resolve_generation({"generator_version": "terrain_p1_1", "seed": 41026}, config)
	var unknown := WorldAdapter.resolve_generation({"generator_version": "future_unknown"}, config)
	_record("T37_GENERATOR_ROUTING", legacy.get("generator_version") == "flat_fixture_1" and current.get("generator_version") == "terrain_p1_1" and not unknown.get("ok", true) and unknown.get("reason") == "UNSUPPORTED_GENERATOR_VERSION", "metadata-free saves remain flat, P1 saves select P1, and unknown generation is refused", {"legacy": legacy, "current": current, "unknown": unknown})

	var first := P1TerrainGenerator.new(41026, terrain_settings)
	var second := P1TerrainGenerator.new(41026, terrain_settings)
	var minimum := 999
	var maximum := -999
	var tree_count := 0
	var coal_count := 0
	var iron_count := 0
	var deterministic := true
	for z in range(-56, 57, 2):
		for x in range(-28, 29, 2):
			var height := first.surface_height(x, z)
			minimum = mini(minimum, height)
			maximum = maxi(maximum, height)
			deterministic = deterministic and height == second.surface_height(x, z)
			if first.is_procedural_tree_root(x, z):
				tree_count += 1
			for y in range(-14, height - 2):
				var voxel := first.sample_voxel(x, y, z, height)
				coal_count += 1 if voxel == P1TerrainGenerator.COAL_ORE else 0
				iron_count += 1 if voxel == P1TerrainGenerator.IRON_ORE else 0
	var clearing_flat := true
	for z in range(31, 50):
		for x in range(-12, 13):
			clearing_flat = clearing_flat and first.surface_height(x, z) == -1 and not first.is_procedural_tree_root(x, z)
	var fixtures := first.sample_voxel(4, 0, 40) == P1TerrainGenerator.LOG and first.sample_voxel(8, -4, 35) == P1TerrainGenerator.COAL_ORE and first.sample_voxel(-8, -4, 35) == P1TerrainGenerator.IRON_ORE
	_record("T38_TERRAIN_DISTRIBUTION", deterministic and minimum < -1 and maximum > 0 and clearing_flat and fixtures and tree_count > 0 and coal_count > 0 and iron_count > 0, "the seed deterministically yields hills, valleys, a safe home clearing, trees, reachable coal and reachable iron", {"minimum": minimum, "maximum": maximum, "trees": tree_count, "coal_samples": coal_count, "iron_samples": iron_count, "clearing_flat": clearing_flat, "fixtures": fixtures})

	app._on_start_pressed()
	if not await _wait_ready():
		return
	var version_ok := app.session.world.generator_version == "terrain_p1_1" and app.session.world.world_seed == 41026 and app.session.world.terrain.generator is P1TerrainGenerator
	_record("T37_RUNTIME_GENERATOR", version_ok, "a new runtime session uses the pinned P1 seed and generator", app.session.world.snapshot())
	app.session.player.deactivate()
	app.session.player.position = Vector3(20.5, 7.0, 0.5)
	app.session._emit_navigation()
	var outward_cue := app.navigation_label.text
	app.session.player.position = WorldAdapter.SPAWN_FEET
	app.session._emit_navigation()
	var home_cue := app.navigation_label.text
	_record("T39_EXPLORE_RETURN", outward_cue.begins_with("HOME  ") and outward_cue.contains("m") and home_cue == "HOME CLEARING", "the HUD provides a distance/bearing return cue outside the home clearing and a clear arrival state", {"away": outward_cue, "home": home_cue})

	var edit_cell := Vector3i(3, -1, 38)
	if not await _wait_cell_loaded(edit_cell):
		_record("T40_EDIT_READY", false, "P1 edit cell becomes editable", edit_cell)
		return
	var edited := app.session.world.set_cell(edit_cell, P1TerrainGenerator.AIR)
	app.session.player.position = Vector3(9.5, 2.0, 36.5)
	var expected := {"edit_cell": [edit_cell.x, edit_cell.y, edit_cell.z], "player": app.session.player.snapshot(), "generator_version": app.session.world.generator_version, "seed": app.session.world.world_seed}
	_write_json(app.data_root.path_join("p1_expected.json"), expected)
	var saved := await app.saves.save_session(app.session)
	_record("T40_SAVE", edited and saved.get("ok", false), "P1 terrain edit, player location, generator version and seed publish coherently", {"edited": edited, "save": saved, "world": app.session.world.snapshot()})


func _run_phase2() -> void:
	_record("T40_CONTINUE_AVAILABLE", app.saves.has_checkpoint() and not app.continue_button.disabled, "the P1 checkpoint is available after a full process restart", app.saves.checkpoint_status())
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	var expected := _read_json(app.data_root.path_join("p1_expected.json"))
	var cell_data: Array = expected.get("edit_cell", [])
	var cell := Vector3i(int(cell_data[0]), int(cell_data[1]), int(cell_data[2]))
	var edit_ok := int(app.session.world.query_cell(cell).get("voxel_id", -1)) == P1TerrainGenerator.AIR
	var expected_position: Array = expected.get("player", {}).get("position", [])
	var expected_vector := Vector3(float(expected_position[0]), float(expected_position[1]), float(expected_position[2]))
	var persisted := app.session.world.generator_version == str(expected.get("generator_version")) and app.session.world.world_seed == int(expected.get("seed")) and app.session.player.position.distance_to(expected_vector) < 0.05
	_record("T40_CONTINUE_RESTORE", edit_ok and persisted, "Continue restores the P1 terrain edit, player location and exact generation identity", {"edit": app.session.world.query_cell(cell), "world": app.session.world.snapshot(), "player": app.session.player.snapshot()})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.apply_world_settings("1000", false)
	app.session.player.deactivate()
	app.session.player.position = Vector3(0.5, 2.0, 40.5)
	app.session.player.rotation.y = 0.0
	for _frame in range(120):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("p1-terrain.png")
	var error := image.save_png(path)
	_record("T41_TERRAIN_VISUAL", error == OK and not image.is_empty() and image.get_size() == Vector2i(1280, 720), "rendered 1280×720 P1 landscape evidence captures the home-to-exploration view", {"path": path, "size": image.get_size(), "error": error})


func _wait_ready() -> bool:
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 30000:
		await get_tree().process_frame
	if app.state != app.AppState.PLAYING:
		failures.append("session ready timeout: " + app.status_label.text)
		return false
	return true


func _wait_cell_loaded(cell: Vector3i) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		if app.session.world.query_cell(cell).get("state") == "LOADED":
			return true
		await get_tree().process_frame
	return false


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()


func _record(test_id: String, passed: bool, expected: String, evidence: Variant) -> void:
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if passed else "FAIL", expected, JSON.stringify(evidence)])
	if not passed:
		failures.append(test_id)
