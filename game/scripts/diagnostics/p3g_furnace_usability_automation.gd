class_name P3GFurnaceUsabilityAutomation
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
	_write_json(app.data_root.path_join("p3g_furnace_usability_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3G_FURNACE_USABILITY_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3G_FURNACE_USABILITY_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true

	var quick := _fixture(70, 0)
	var quick_service: WorkstationService = quick.service
	var quick_inventory: F0Inventory = quick.inventory
	var quick_id := str(quick.furnace_id)
	var loaded_60 := quick_service.try_set_furnace_autoload_target(quick_id, "iron_ingot", 60)
	var partial_transfer := quick_service.try_transfer_inventory_stack_to_furnace(quick_id, _slot_for(quick_inventory, "iron_ore"))
	var after_partial := quick_service.furnace_slots(quick_id)
	var collected := quick_service.try_collect_furnace_stack(quick_id, "input")
	var after_collect := quick_service.furnace_slots(quick_id)
	_record("T93_SHIFT_QUICK_TRANSFER", loaded_60.get("ok", false) and partial_transfer.get("ok", false) and int(partial_transfer.get("details", {}).get("count", 0)) == 4 and int(after_partial.input.count) == 64 and quick_inventory.count("iron_ore") == 70 and collected.get("ok", false) and str(after_collect.input.item_id).is_empty(), "quick transfer moves the maximum legal stack amount in either direction without loss", {"partial": partial_transfer, "after_partial": after_partial, "collected": collected, "inventory_total": quick_inventory.count("iron_ore")})

	var auto := _fixture(15, 10)
	var auto_service: WorkstationService = auto.service
	var auto_inventory: F0Inventory = auto.inventory
	var auto_id := str(auto.furnace_id)
	var target_15 := auto_service.try_set_furnace_autoload_target(auto_id, "iron_ingot", 15)
	var loaded_slots := auto_service.furnace_slots(auto_id)
	var lowered := auto_service.try_set_furnace_autoload_target(auto_id, "iron_ingot", 4)
	var lowered_slots := auto_service.furnace_slots(auto_id)
	var auto_status := auto_service.furnace_autoload_status(auto_id, "iron_ingot")
	_record("T94_TRANSACTIONAL_AUTOLOAD", target_15.get("ok", false) and int(loaded_slots.input.count) == 15 and int(loaded_slots.fuel.count) == 10 and lowered.get("ok", false) and int(lowered_slots.input.count) == 4 and int(lowered_slots.fuel.count) == 4 and auto_inventory.count("iron_ore") + int(lowered_slots.input.count) == 15 and auto_inventory.count("coal") + int(lowered_slots.fuel.count) == 10 and int(auto_status.get("details", {}).get("limit", 0)) == 15, "the 0–64 target independently fills each ingredient up to its available amount and safely returns excess when lowered", {"loaded": loaded_slots, "lowered": lowered_slots, "status": auto_status.get("details", {})})

	var timed := _fixture(3, 3)
	var timed_service: WorkstationService = timed.service
	var timed_id := str(timed.furnace_id)
	timed_service.try_set_furnace_autoload_target(timed_id, "iron_ingot", 3)
	var started := timed_service.try_start_furnace(timed_id, "iron_ingot")
	timed_service.advance(2.5, false)
	var halfway := timed_service.furnace_job_status(timed_id)
	timed_service.advance(2.5, false)
	var after_one := timed_service.furnace_slots(timed_id)
	var next_job := timed_service.furnace_job_status(timed_id)
	_record("T95_ITEM_PROGRESS_SEQUENCE", started.get("ok", false) and absf(float(halfway.progress) - 0.5) < 0.01 and int(after_one.output.count) == 1 and bool(next_job.active) and float(next_job.progress) < 0.01 and int(after_one.input.count) == 1 and int(after_one.fuel.count) == 1, "each item exposes measurable progress, deposits one retained output, then resets for the next loaded item", {"halfway": halfway, "after_one": after_one, "next_job": next_job})

	app.session.inventory.try_transaction({}, {"furnace": 1, "iron_ore": 2, "coal": 2})
	var placed := app.session.workstations.try_place("furnace", Vector3i(3, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var furnace_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	app.state = app.AppState.PLAYING
	app._show_crafting(furnace_id, "furnace")
	app._on_crafting_stack_gesture("inventory", _slot_for(app.session.inventory, "iron_ore"), MOUSE_BUTTON_LEFT, false, false, true)
	app._on_crafting_stack_gesture("inventory", _slot_for(app.session.inventory, "coal"), MOUSE_BUTTON_LEFT, false, false, true)
	app._selected_recipe_id = "iron_ingot"
	app._craft_selected_recipe()
	app._process(2.5)
	var modal_half := app.session.workstations.furnace_job_status(furnace_id)
	var progress_value := float(app.furnace_progress_bar.value)
	app._process(2.5)
	var modal_slots := app.session.workstations.furnace_slots(furnace_id)
	var modal_next := app.session.workstations.furnace_job_status(furnace_id)
	var modal_ok := get_tree().paused and app.furnace_controls.visible and absf(progress_value - 50.0) < 1.0 and int(modal_slots.output.count) == 1 and bool(modal_next.active)
	app._close_crafting()
	_record("T96_MODAL_LIVE_PROCESSING", placed.get("ok", false) and modal_ok and absf(float(modal_half.progress) - 0.5) < 0.01, "the Furnace clock and progress bar advance while its modal is open even though world simulation remains paused", {"halfway": modal_half, "progress_bar": progress_value, "slots": modal_slots, "next_job": modal_next})

	app.session.inventory.try_transaction({}, {"catapult": 1})
	var catapult := app.session.workstations.try_place("catapult", Vector3i(7, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var catapult_id := str(catapult.get("details", {}).get("station", {}).get("instance_id", ""))
	var catapult_body: Node3D = app.session._station_visuals.get(catapult_id)
	var wheel_count := 0
	if catapult_body != null:
		for child in catapult_body.get_children():
			if str(child.name).begins_with("CatapultWheel_"):
				wheel_count += 1
	_record("T97_CATAPULT_WORLD_IDENTITY", catapult.get("ok", false) and catapult_body != null and wheel_count == 4 and catapult_body.get_child_count() >= 14, "the placed Catapult has a recognizable wheeled chassis, axle, throwing arm, basket and projectile rather than generic boxes", {"parts": catapult_body.get_child_count() if catapult_body != null else 0, "wheels": wheel_count})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.inventory.try_transaction({}, {"furnace": 1, "iron_ore": 8, "coal": 5, "catapult": 1})
	var furnace := app.session.workstations.try_place("furnace", Vector3i(3, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var furnace_id := str(furnace.get("details", {}).get("station", {}).get("instance_id", ""))
	app.session.workstations.try_set_furnace_autoload_target(furnace_id, "iron_ingot", 8)
	app.session.workstations.try_start_furnace(furnace_id, "iron_ingot")
	app.state = app.AppState.PLAYING
	app._show_crafting(furnace_id, "furnace")
	app._process(2.5)
	await _settle_frames(4)
	var modal_path := app.data_root.path_join("p3g-furnace-autoload-progress.png")
	var modal_ok := await _save_viewport(modal_path)
	app._close_crafting()
	var catapult := app.session.workstations.try_place("catapult", Vector3i(7, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	app.session.apply_world_settings("1200", false)
	app.session.player.global_position = Vector3(11.2, 1.35, 34.2)
	app.session.player.look_at(Vector3(7.6, 0.65, 38.6), Vector3.UP)
	await _settle_frames(12)
	var catapult_path := app.data_root.path_join("p3g-catapult-world-model.png")
	var catapult_ok := await _save_viewport(catapult_path)
	_record("T98_FURNACE_AND_CATAPULT_PRESENTATION", modal_ok and catapult.get("ok", false) and catapult_ok, "rendered evidence shows the auto-load/progress controls and the revised placed Catapult", {"modal_path": modal_path, "catapult_path": catapult_path, "size": get_viewport().get_visible_rect().size})


func _fixture(ore: int, coal: int) -> Dictionary:
	var inventory := F0Inventory.new(app.session.registry)
	var additions := {"furnace": 1}
	if ore > 0:
		additions["iron_ore"] = ore
	if coal > 0:
		additions["coal"] = coal
	inventory.try_transaction({}, additions)
	var service := WorkstationService.new(app.session.registry, inventory)
	var placed := service.try_place("furnace", Vector3i.ZERO, _fixture_world_query, AABB(Vector3(100.0, 100.0, 100.0), Vector3.ONE))
	return {"inventory": inventory, "service": service, "furnace_id": str(placed.get("details", {}).get("station", {}).get("instance_id", ""))}


func _fixture_world_query(cell: Vector3i) -> Dictionary:
	return {"state": "LOADED", "voxel_id": 1 if cell.y < 0 else 0}


func _slot_for(inventory: F0Inventory, item_id: String) -> int:
	for index in range(F0Inventory.SLOT_COUNT):
		if str(inventory.slots[index].get("item_id", "")) == item_id:
			return index
	return -1


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
