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
	await _run_warehouse_foundry()
	await _run_live_under_modals()


## Industry wave 1 (docs/INDUSTRY.md): a Foundry beside a Warehouse smelts on
## its own, "any" takes iron before gold, a lone Foundry says so, and a save
## round-trip keeps the target, the counter and the warehouse contents.
func _run_warehouse_foundry() -> void:
	var service := app.session.workstations
	var inventory := app.session.inventory
	var foundry_service: FoundryService = app.session.foundry
	var origin := Vector3i(8, 0, 42)
	var warehouse_anchor := Vector3i(11, 0, 45)
	var foundry_anchor := Vector3i(13, 0, 45)
	var lone_anchor := Vector3i(11, 0, 48)
	var cells: Array[Vector3i] = [warehouse_anchor, warehouse_anchor + Vector3i(1, 0, 1), foundry_anchor + Vector3i(1, 0, 0), lone_anchor + Vector3i(1, 0, 0)]
	var plate_ok := await _wait_levelled(origin, 10, 9, 4, cells)
	inventory.try_transaction({}, {"warehouse": 1, "foundry": 2, "iron_ore": 3, "coal": 3, "gold_ore": 2})
	var warehouse_placed := service.try_place("warehouse", warehouse_anchor, app.session.world.query_cell, app.session.player.get_body_aabb())
	var warehouse_id := str(warehouse_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var foundry_placed := service.try_place("foundry", foundry_anchor, app.session.world.query_cell, app.session.player.get_body_aabb())
	var foundry_id := str(foundry_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var lone_placed := service.try_place("foundry", lone_anchor, app.session.world.query_cell, app.session.player.get_body_aabb())
	var lone_id := str(lone_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var stocked: bool = service.container_deposit(warehouse_id, "iron_ore", 3).get("ok", false) and service.container_deposit(warehouse_id, "coal", 3).get("ok", false) and service.container_deposit(warehouse_id, "gold_ore", 2).get("ok", false)
	var initial_target := str(foundry_service.state(foundry_id).get("target", ""))
	var adjacent := foundry_service.warehouse_for(foundry_id) == warehouse_id and foundry_service.warehouse_for(lone_id).is_empty()
	var glow_lit := false
	var iron_events := 0
	for _cycle in range(3):
		iron_events += foundry_service.advance(FoundryService.FOUNDRY_SECONDS + 0.1, false).size()
		var body: Node3D = app.session._station_visuals.get(foundry_id)
		var glow: Node3D = body.get_node_or_null("Glow") if body != null else null
		glow_lit = glow_lit or (glow != null and glow.visible)
	var iron_done := service.container_count(warehouse_id, "iron_ingot") == 3 and service.container_count(warehouse_id, "gold_ingot") == 0 and service.container_count(warehouse_id, "iron_ore") == 0 and service.container_count(warehouse_id, "coal") == 0 and service.container_count(warehouse_id, "gold_ore") == 2
	var waiting_status := str(foundry_service.state(foundry_id).get("status", ""))
	var lone_status := str(foundry_service.state(lone_id).get("status", ""))
	var warehouse_body: Node3D = app.session._station_visuals.get(warehouse_id)
	var crates: Node = warehouse_body.get_node_or_null("Crates") if warehouse_body != null else null
	var crates_ok := crates != null and crates.get_child_count() >= 1
	var target_set: bool = foundry_service.set_target(foundry_id, "gold_ingot").get("ok", false)
	inventory.try_transaction({}, {"coal": 2})
	var coal_added: bool = service.container_deposit(warehouse_id, "coal", 2).get("ok", false)
	var gold_events := 0
	for _cycle in range(2):
		gold_events += foundry_service.advance(FoundryService.FOUNDRY_SECONDS + 0.1, false).size()
	var gold_done := service.container_count(warehouse_id, "gold_ingot") == 2 and service.container_count(warehouse_id, "gold_ore") == 0 and service.container_count(warehouse_id, "iron_ingot") == 3
	var made := int(foundry_service.state(foundry_id).get("made", 0))
	# Save round-trip: the target, the counter and the warehouse contents ride
	# in the workstation snapshot.
	var restored_service := WorkstationService.new(app.session.registry, F0Inventory.new(app.session.registry))
	var restored := restored_service.restore(service.snapshot(), app.session.world.query_cell)
	var restored_foundry := FoundryService.new(restored_service, app.session.registry)
	var restored_state := restored_foundry.state(foundry_id)
	var restore_ok: bool = restored.get("ok", false) and str(restored_state.get("target", "")) == "gold_ingot" and int(restored_state.get("made", 0)) == 5 and restored_service.container_count(warehouse_id, "gold_ingot") == 2 and restored_service.container_count(warehouse_id, "iron_ingot") == 3 and restored_foundry.warehouse_for(foundry_id) == warehouse_id
	# The modal: title, one button per target with the current one pressed,
	# the status line; Escape closes it.
	app.state = app.AppState.PLAYING
	app._show_workstation(foundry_id, "foundry")
	var modal_ok := app.state == app.AppState.CRAFTING and app.foundry_card.visible and not app.crafting_inventory_card.visible and app.crafting_title_label.text == "FOUNDRY" and app.foundry_target_buttons.size() == 3 and app.foundry_target_buttons[2].button_pressed and app.foundry_status_label.text.contains("made 5")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.physical_keycode = KEY_ESCAPE
	app._input(escape)
	var modal_closed := app.state == app.AppState.PLAYING and not app.crafting_panel.visible
	app._show_workstation(warehouse_id, "warehouse")
	var warehouse_modal_ok := app.state == app.AppState.CRAFTING and app.chest_card.visible and app.crafting_title_label.text == "WAREHOUSE"
	app._close_crafting()
	_record("T194_WAREHOUSE_FOUNDRY", plate_ok and warehouse_placed.get("ok", false) and foundry_placed.get("ok", false) and lone_placed.get("ok", false) and stocked and initial_target == "any" and adjacent and iron_events == 3 and iron_done and glow_lit and waiting_status.begins_with("waiting for") and lone_status == FoundryService.STATUS_NO_WAREHOUSE and crates_ok and target_set and coal_added and gold_events == 2 and gold_done and made == 5 and restore_ok and modal_ok and modal_closed and warehouse_modal_ok, "a foundry beside a warehouse smelts one furnace recipe per FOUNDRY_SECONDS from the warehouse into it (any = iron before gold), a lone foundry reports no warehouse, the target and counter survive a save round-trip, and the modals open and close", {"warehouse": warehouse_id, "foundry": foundry_id, "iron_events": iron_events, "waiting": waiting_status, "lone": lone_status, "gold_events": gold_events, "made": made, "restore": restored, "restored_state": restored_state, "modal": modal_ok, "warehouse_modal": warehouse_modal_ok, "slots": service.container_slots(warehouse_id)})


## Owner 2026-09-22: "all actions and world events stop when I am in a menu
## ... only the game menu should stop the world." A furnace job finishes and
## the clock ticks while the inventory, the workbench and the hand-build modal
## are open; the pause menu still stops the clock; a raider keeps approaching
## while the inventory is open.
func _run_live_under_modals() -> void:
	var service := app.session.workstations
	var inventory := app.session.inventory
	var clock := app.session.clock
	var anchors: Array[Vector3i] = [Vector3i(16, 0, 43), Vector3i(16, 0, 46), Vector3i(16, 0, 49)]
	var plate_ok := await _wait_levelled(Vector3i(8, 0, 42), 10, 9, 4, anchors)
	app.state = app.AppState.PLAYING
	app.session.simulation_paused = false
	var bench_id := ""
	for record: Dictionary in service.stations.values():
		if str(record.get("entity_id", "")) == "workbench":
			bench_id = str(record.get("instance_id", ""))
	var evidence: Dictionary = {"plate": plate_ok, "bench": bench_id}
	var all_ok := plate_ok and not bench_id.is_empty()
	var modals: Array[String] = ["inventory", "workbench", "hand"]
	for index in range(modals.size()):
		var modal := modals[index]
		inventory.try_transaction({}, {"furnace": 1, "iron_ore": 1, "coal": 1})
		var placed := service.try_place("furnace", anchors[index], app.session.world.query_cell, AABB())
		var furnace_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
		var loaded: bool = service.try_transfer_inventory_stack_to_furnace(furnace_id, _slot_for("iron_ore")).get("ok", false) and service.try_transfer_inventory_stack_to_furnace(furnace_id, _slot_for("coal")).get("ok", false)
		var started := service.try_start_furnace(furnace_id, "iron_ingot")
		# A 3 s job (the recipe takes 5): the modal stays open for 4 s of real
		# frames, after which the ingot sits in the output (leftover ore from the
		# earlier tests may already have started the next job).
		if service.jobs.has(furnace_id):
			service.jobs[furnace_id]["remaining_seconds"] = 3.0
		var phase_before := float(clock.phase) + float(clock.day_index)
		match modal:
			"inventory":
				app._show_inventory()
			"workbench":
				app._show_workstation(bench_id, "workbench")
			"hand":
				app._show_crafting()
		var opened := app.state == (app.AppState.INVENTORY if modal == "inventory" else app.AppState.CRAFTING) and app.session.menu_open and not app.session.simulation_paused and not get_tree().paused and not app.session.player.active
		await _wait_seconds(4.0)
		var job_after := service.furnace_job_status(furnace_id)
		var output_after: Dictionary = service.furnace_slots(furnace_id).get("output", {})
		var clock_moved := float(clock.phase) + float(clock.day_index) > phase_before
		var still_open := app.state != app.AppState.PLAYING
		if modal == "inventory":
			app._close_inventory()
		else:
			app._close_crafting()
		var closed := app.state == app.AppState.PLAYING and not app.session.menu_open and app.session.player.active
		var ok: bool = placed.get("ok", false) and loaded and started.get("ok", false) and opened and still_open and int(output_after.get("count", 0)) >= 1 and str(output_after.get("item_id", "")) == "iron_ingot" and clock_moved and closed
		all_ok = all_ok and ok
		evidence[modal] = {"ok": ok, "placed": placed.get("reason"), "loaded": loaded, "started": started.get("reason"), "opened": opened, "still_open": still_open, "job_after": job_after, "output": output_after, "clock_moved": clock_moved, "closed": closed}
	# The pause menu is the one menu that stops the world.
	var paused_phase_before := float(clock.phase) + float(clock.day_index)
	app._pause_game()
	var pause_opened := app.state == app.AppState.PAUSED and app.session.simulation_paused and get_tree().paused
	await _wait_seconds(1.0)
	var pause_clock_still := float(clock.phase) + float(clock.day_index) == paused_phase_before
	app._resume_game()
	var pause_closed := app.state == app.AppState.PLAYING and not app.session.simulation_paused and not get_tree().paused
	evidence["pause_menu"] = {"opened": pause_opened, "clock_still": pause_clock_still, "closed": pause_closed}
	all_ok = all_ok and pause_opened and pause_clock_still and pause_closed
	# A raider keeps walking at the core while the inventory is open.
	var core := app.session.core_defense
	var drill := core.start_prototype()
	core.warning_remaining = 0.0
	core._begin_attack()
	var waited := 0
	while (not is_instance_valid(core.raider) or core.last_route_reason == "WAITING_FOR_TERRAIN") and waited < 600:
		await get_tree().process_frame
		waited += 1
	var raider_ok := false
	var raider_evidence: Dictionary = {"drill": drill.get("reason"), "route": core.last_route_reason, "waited": waited}
	if is_instance_valid(core.raider):
		var core_point := Vector3(core.arena_center + Vector3i(0, 0, 5)) + Vector3(0.5, 0.0, 0.5)
		var distance_before := Vector2(core.raider.global_position.x - core_point.x, core.raider.global_position.z - core_point.z).length()
		app._show_inventory()
		var inventory_open := app.state == app.AppState.INVENTORY
		await _wait_seconds(2.0)
		var distance_after := Vector2(core.raider.global_position.x - core_point.x, core.raider.global_position.z - core_point.z).length()
		app._close_inventory()
		raider_ok = inventory_open and distance_after < distance_before - 0.5
		raider_evidence.merge({"inventory_open": inventory_open, "before": distance_before, "after": distance_after, "state": core.state}, true)
	evidence["raider"] = raider_evidence
	core.clear_for_other_mode()
	app.session.simulation_paused = true
	app.session.player.deactivate()
	_record("T199_LIVE_UNDER_MODALS", all_ok and raider_ok, "a furnace job finishes and the clock ticks while the inventory, the workbench and the hand-build modal are open; the pause menu stops the clock; a raider keeps approaching while the inventory is open", evidence)


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


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


func _level_ground(origin: Vector3i, width: int, depth: int, height: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(origin + Vector3i(x, -1, z), 3)
			for y in range(height):
				app.session.world.set_cell(origin + Vector3i(x, y, z), 0)


## A levelled stone plate (the coaster suites' idiom): waits until the plate
## and the cells it must keep clear are loaded and as set.
func _wait_levelled(origin: Vector3i, width: int, depth: int, height: int, cells: Array[Vector3i]) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		_level_ground(origin, width, depth, height)
		var clear := true
		for cell: Vector3i in cells:
			var query := app.session.world.query_cell(cell)
			if query.get("state") != "LOADED" or int(query.get("voxel_id", 1)) != 0:
				clear = false
				break
		for x in range(width):
			for z in range(depth):
				var plate := app.session.world.query_cell(origin + Vector3i(x, -1, z))
				if plate.get("state") != "LOADED" or int(plate.get("voxel_id", 0)) != 3:
					clear = false
		if clear:
			return true
		await get_tree().process_frame
	return false


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
