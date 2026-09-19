class_name P3HBalanceAndControlsAutomation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"gate":
			await _run_gate()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p3h_balance_and_controls_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3H_BALANCE_AND_CONTROLS_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3H_BALANCE_AND_CONTROLS_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var registry := app.session.registry
	var catalogue_ok: bool = registry.balance_integer("furnace.operations_per_fuel", 0) == 3 \
		and registry.balance_string("furnace.fuel_item", "") == "coal" \
		and app.session.core_defense.raider_damage == registry.balance_integer("core_defense.raider_damage", 0) \
		and app.session.defense.wall_max_integrity == registry.balance_integer("practice_defense.wall_integrity", 0)
	_record("T99_BALANCE_CATALOGUE", catalogue_ok, "named runtime balance values drive the active Furnace, harvesting and defense services instead of duplicated gameplay literals", registry.balance)

	var fixture := _fixture(3, 1)
	var service: WorkstationService = fixture.service
	var furnace_id := str(fixture.furnace_id)
	var loaded := service.try_set_furnace_autoload_target(furnace_id, "iron_ingot", 3)
	var staged := service.furnace_slots(furnace_id)
	var started := service.try_start_furnace(furnace_id, "iron_ingot")
	service.advance(5.0, false)
	var saved := service.snapshot()
	var restored_inventory := F0Inventory.new(registry)
	var restored := WorkstationService.new(registry, restored_inventory)
	var restore_result := restored.restore(saved, _fixture_world_query)
	var restored_fuel := restored.furnace_fuel_status(furnace_id)
	restored.advance(5.0, false)
	restored.advance(5.0, false)
	var finished_slots := restored.furnace_slots(furnace_id)
	var finished_fuel := restored.furnace_fuel_status(furnace_id)
	var ratio_ok: bool = bool(loaded.get("ok", false)) and int(staged.input.count) == 3 and int(staged.fuel.count) == 1 \
		and started.get("ok", false) and restore_result.get("ok", false) \
		and int(restored_fuel.get("details", {}).get("stored_operations", -1)) == 1 \
		and int(finished_slots.output.count) == 3 and str(finished_slots.input.item_id).is_empty() and str(finished_slots.fuel.item_id).is_empty() \
		and int(finished_fuel.get("details", {}).get("stored_operations", -1)) == 0 and not bool(restored.furnace_job_status(furnace_id).active)
	_record("T100_COUNTED_FURNACE_FUEL", ratio_ok, "one Coal funds exactly three persisted smelting operations without loss, duplication or a fourth free output", {"loaded": staged, "restored_fuel": restored_fuel, "finished": finished_slots, "finished_fuel": finished_fuel})

	app.session.interaction.placement_rotation_quarters = 0
	var clockwise := app.session.interaction.rotate_placement(1)
	var counterclockwise := app.session.interaction.rotate_placement(-1)
	var controls_ok: bool = clockwise == 1 and counterclockwise == 0 \
		and app.settings.get_binding_label("rotate_build_clockwise") == "W" \
		and app.settings.get_binding_label("rotate_build_counterclockwise") == "R" \
		and app.settings.get_binding_label("interact") == "Shift"
	_record("T101_DIRECTIONAL_BUILD_ROTATION", controls_ok, "W rotates the preview clockwise, R reverses it and Left Shift remains the editable Interact action", {"clockwise": clockwise, "counterclockwise": counterclockwise, "w": app.settings.get_binding_label("rotate_build_clockwise"), "r": app.settings.get_binding_label("rotate_build_counterclockwise"), "interact": app.settings.get_binding_label("interact")})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.inventory.try_transaction({}, {"furnace": 1, "iron_ore": 6, "coal": 2})
	var placed := app.session.workstations.try_place("furnace", Vector3i(3, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var furnace_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	app.session.workstations.try_set_furnace_autoload_target(furnace_id, "iron_ingot", 6)
	app.session.workstations.try_start_furnace(furnace_id, "iron_ingot")
	app.state = app.AppState.PLAYING
	app._show_crafting(furnace_id, "furnace")
	await _settle_frames(4)
	var furnace_path := app.data_root.path_join("p3h-furnace-fuel-ratio.png")
	var furnace_ok := await _save_viewport(furnace_path)
	app._close_crafting()
	app._pause_game()
	app._show_keybinds()
	app.keybind_search.text = "Rotate Build"
	app._on_keybind_search_changed(app.keybind_search.text)
	await _settle_frames(4)
	var controls_path := app.data_root.path_join("p3h-directional-controls.png")
	var controls_ok := await _save_viewport(controls_path)
	_record("T102_BALANCE_AND_CONTROLS_PRESENTATION", placed.get("ok", false) and furnace_ok and controls_ok, "rendered evidence exposes the counted 1:3 fuel ratio and separate W/R rotation bindings", {"furnace_path": furnace_path, "controls_path": controls_path, "size": get_viewport().get_visible_rect().size})


func _fixture(ore: int, coal: int) -> Dictionary:
	var inventory := F0Inventory.new(app.session.registry)
	inventory.try_transaction({}, {"furnace": 1, "iron_ore": ore, "coal": coal})
	var service := WorkstationService.new(app.session.registry, inventory)
	var placed := service.try_place("furnace", Vector3i.ZERO, _fixture_world_query, AABB(Vector3(100.0, 100.0, 100.0), Vector3.ONE))
	return {"inventory": inventory, "service": service, "furnace_id": str(placed.get("details", {}).get("station", {}).get("instance_id", ""))}


func _fixture_world_query(cell: Vector3i) -> Dictionary:
	return {"state": "LOADED", "voxel_id": 1 if cell.y < 0 else 0}


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


func _settle_frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _save_viewport(path: String) -> bool:
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	return image != null and image.get_size() == Vector2i(1280, 720) and image.save_png(path) == OK


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
