class_name P3EContainerAutomation
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
	_write_json(app.data_root.path_join("p3e_container_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3E_CONTAINER_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3E_CONTAINER_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var service := app.session.workstations
	var inventory := app.session.inventory
	inventory.try_transaction({}, {"furnace": 1, "iron_ore": 7, "coal": 6, "workbench": 1, "wood_axe": 1, "stone_pick": 1})
	var furnace_placed := service.try_place("furnace", Vector3i(3, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var furnace_id := str(furnace_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var bench_placed := service.try_place("workbench", Vector3i(2, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var iron_slot := _slot_for("iron_ore")
	var coal_slot := _slot_for("coal")
	var iron_transfer := service.try_transfer_inventory_stack_to_furnace(furnace_id, iron_slot)
	var coal_transfer := service.try_transfer_inventory_stack_to_furnace(furnace_id, coal_slot)
	var loaded_slots := service.furnace_slots(furnace_id)
	_record("T84_CONTAINER_TRANSFER", furnace_placed.get("ok", false) and bench_placed.get("ok", false) and iron_transfer.get("ok", false) and coal_transfer.get("ok", false) and int(loaded_slots.input.count) == 7 and int(loaded_slots.fuel.count) == 6 and inventory.count("iron_ore") == 0 and inventory.count("coal") == 0, "whole-stack transfer moves inventory ore and fuel into distinct Furnace-owned slots", {"iron": iron_transfer, "coal": coal_transfer, "slots": loaded_slots})

	var picked_half := service.cursor_pick_furnace_stack(furnace_id, "input", true)
	var cursor_snapshot := inventory.snapshot()
	var cursor_restore := F0Inventory.new(app.session.registry)
	var cursor_restored := cursor_restore.restore(cursor_snapshot)
	var deposited_one := service.cursor_deposit_furnace_stack(furnace_id, "input", true)
	var spread_slots: Array[int] = [20, 21, 22]
	var spread_ok := true
	for slot_index in spread_slots:
		spread_ok = spread_ok and inventory.cursor_deposit_slot(slot_index, true).get("ok", false)
	var split_slots := service.furnace_slots(furnace_id)
	_record("T85_STACK_GESTURES", picked_half.get("ok", false) and int(picked_half.get("details", {}).get("count", 0)) == 4 and cursor_restored and str(cursor_restore.cursor_stack.item_id) == "iron_ore" and int(cursor_restore.cursor_stack.count) == 4 and deposited_one.get("ok", false) and int(split_slots.input.count) == 4 and spread_ok and str(inventory.cursor_stack.item_id).is_empty() and spread_slots.all(func(index: int) -> bool: return str(inventory.slots[index].item_id) == "iron_ore" and int(inventory.slots[index].count) == 1), "right-click takes the larger half, persists the cursor stack, right-click deposits one, and right-drag semantics distribute one to each traversed slot", {"picked": picked_half, "cursor_restored": cursor_restore.cursor_stack, "deposited": deposited_one, "furnace": split_slots, "cursor": inventory.cursor_stack, "inventory_slots": spread_slots.map(func(index: int) -> Dictionary: return inventory.slots[index])})

	var started := service.try_start_furnace(furnace_id, "iron_ingot")
	service.advance(5.0, false)
	var retained := service.furnace_slots(furnace_id)
	var before_collect := inventory.count("iron_ingot")
	var snapshot := service.snapshot()
	var inventory_snapshot := inventory.snapshot()
	var restored_inventory := F0Inventory.new(app.session.registry)
	var inventory_restored := restored_inventory.restore(inventory_snapshot)
	var restored_service := WorkstationService.new(app.session.registry, restored_inventory)
	var service_restored := restored_service.restore(snapshot, app.session.world.query_cell)
	var restored_output := restored_service.furnace_slots(furnace_id)
	var collected := restored_service.try_collect_furnace_stack(furnace_id, "output")
	_record("T86_RETAINED_OUTPUT", started.get("ok", false) and before_collect == 0 and int(retained.output.count) == 1 and str(retained.output.item_id) == "iron_ingot" and inventory_restored and service_restored.get("ok", false) and int(restored_output.output.count) == 1 and collected.get("ok", false) and restored_inventory.count("iron_ingot") == 1 and str(restored_service.furnace_slots(furnace_id).output.item_id).is_empty(), "smelting consumes one input and one counted fuel operation, retains output in the placed Furnace across restore, and only collection moves it to inventory", {"started": started, "retained": retained, "restored": service_restored, "collected": collected})

	app.state = app.AppState.PLAYING
	app._show_crafting(furnace_id, "furnace")
	var modal_ok := app.crafting_grid.columns == 3 and app.crafting_grid.get_child_count() == 3 and app.crafting_context_label.text.contains("RETAINED OUTPUT") and app.crafting_grid_help.text.contains("Raw Input") and app.crafting_grid_help.tooltip_text.contains("persist")
	app.crafting_recipe_search.grab_focus()
	await get_tree().process_frame
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.physical_keycode = KEY_ESCAPE
	app._input(escape)
	var single_escape_ok := app.state == app.AppState.PLAYING and not app.crafting_panel.visible
	var furnace_body: Node3D = app.session._station_visuals.get(furnace_id)
	var bench_id := str(bench_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var bench_body: Node3D = app.session._station_visuals.get(bench_id)
	inventory.select_hotbar(_slot_for("stone_pick"))
	await get_tree().process_frame
	var held_texture_ok := app.session._held_item_view.model_root.get_child_count() == 1 and ItemIconCatalog.world_reference_texture_for("stone_pick") != null
	_record("T87_VISUAL_IDENTITY", modal_ok and single_escape_ok and furnace_body != null and furnace_body.get_child_count() >= 5 and bench_body != null and bench_body.get_child_count() >= 9 and held_texture_ok, "the Furnace exposes three real slots, closes with one Escape even when search owns focus, and detailed station/held identities remain intact", {"modal": modal_ok, "single_escape": single_escape_ok, "furnace_parts": furnace_body.get_child_count() if furnace_body != null else 0, "workbench_parts": bench_body.get_child_count() if bench_body != null else 0, "held": held_texture_ok})

	var manual_recipe := app.session.registry.recipe("planks")
	app.state = app.AppState.PLAYING
	app._show_crafting("", "hand")
	app._clear_crafting_grid(false, false)
	app._craft_grid_items[0] = "log"
	app._after_manual_grid_change()
	var manual_ok := app._selected_recipe_id == "planks" and app._grid_matches_recipe(manual_recipe)
	app._close_crafting()
	_record("T88_MANUAL_DISCOVERY", manual_ok, "manual grid patterns remain recognized without selecting or searching the recipe book", {"selected_recipe": app._selected_recipe_id, "recognized": manual_ok})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.inventory.try_transaction({}, {"furnace": 1, "iron_ore": 4, "coal": 4, "stone_pick": 1})
	var placed := app.session.workstations.try_place("furnace", Vector3i(3, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var furnace_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	app.session.workstations.try_load_furnace_recipe(furnace_id, "iron_ingot")
	app.state = app.AppState.PLAYING
	app._show_crafting(furnace_id, "furnace")
	app._selected_recipe_id = "iron_ingot"
	app._refresh_crafting_panel()
	await _settle_frames(20)
	var modal_path := app.data_root.path_join("p3e-furnace-container.png")
	var modal_ok := await _save_viewport(modal_path)
	app._close_crafting()
	app.session.inventory.select_hotbar(_slot_for("stone_pick"))
	app.session.player.global_position = Vector3(2.5, 1.0, 34.0)
	app.session.player.look_at(Vector3(3.5, 0.5, 38.5), Vector3.UP)
	await _settle_frames(20)
	var world_path := app.data_root.path_join("p3e-world-and-held-identity.png")
	var world_ok := await _save_viewport(world_path)
	_record("T89_PRESENTATION", modal_ok and world_ok, "rendered evidence shows the real three-slot Furnace and the revised world/held visual identity", {"modal_path": modal_path, "world_path": world_path, "size": get_viewport().get_visible_rect().size})


func _slot_for(item_id: String) -> int:
	for index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[index].get("item_id", "")) == item_id:
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
