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


## Industry wave 1 (docs/INDUSTRY.md): a Foundry beside a Warehouse smelts on
## its own, "any" takes iron before gold, a lone Foundry says so, and a save
## round-trip keeps the target, the counter and the warehouse contents.
## Storage network card: the foundry now pulls into its own slots and pushes
## the ingot back; one ingot per recipe duration (iron 5 s, gold 8 s).
func _run_warehouse_foundry() -> void:
	var service := app.session.workstations
	var inventory := app.session.inventory
	var foundry_service: FoundryService = app.session.foundry
	var iron_seconds := foundry_service.job_seconds(app.session.registry.recipe("iron_ingot")) + 0.1
	var gold_seconds := foundry_service.job_seconds(app.session.registry.recipe("gold_ingot")) + 0.1
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
		iron_events += foundry_service.advance(iron_seconds, false).size()
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
		gold_events += foundry_service.advance(gold_seconds, false).size()
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
	var modal_ok := app.state == app.AppState.CRAFTING and app.foundry_card.visible and app.crafting_inventory_card.visible and app.crafting_grid_card.visible and app.crafting_grid.get_child_count() == 3 and app.crafting_title_label.text == "FOUNDRY" and app.foundry_target_buttons.size() == 3 and app.foundry_target_buttons[2].button_pressed and app.foundry_status_label.text.contains("made 5")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.physical_keycode = KEY_ESCAPE
	app._input(escape)
	var modal_closed := app.state == app.AppState.PLAYING and not app.crafting_panel.visible
	app._show_workstation(warehouse_id, "warehouse")
	var warehouse_modal_ok := app.state == app.AppState.CRAFTING and app.chest_card.visible and app.crafting_title_label.text == "WAREHOUSE"
	app._close_crafting()
	await _run_storage_network()
	_record("T194_WAREHOUSE_FOUNDRY", plate_ok and warehouse_placed.get("ok", false) and foundry_placed.get("ok", false) and lone_placed.get("ok", false) and stocked and initial_target == "any" and adjacent and iron_events == 3 and iron_done and glow_lit and waiting_status == FoundryService.STATUS_NO_FUEL and lone_status == FoundryService.STATUS_NO_STORAGE and crates_ok and target_set and coal_added and gold_events == 2 and gold_done and made == 5 and restore_ok and modal_ok and modal_closed and warehouse_modal_ok, "a foundry beside a warehouse smelts one furnace recipe per job from the warehouse back into it (any = iron before gold), a lone foundry reports no storage, the target and counter survive a save round-trip, and the modals open and close", {"warehouse": warehouse_id, "foundry": foundry_id, "iron_events": iron_events, "waiting": waiting_status, "lone": lone_status, "gold_events": gold_events, "made": made, "restore": restored, "restored_state": restored_state, "modal": modal_ok, "warehouse_modal": warehouse_modal_ok, "slots": service.container_slots(warehouse_id)})


## Storage network card (docs/INDUSTRY.md "Storage network"): the foundry's
## slots fill from the warehouse (64 each, the rest stays), an ingot per job
## goes back, the panel shows a running bar; a chest + two warehouses form
## one network; siege weapons reload from the chest beside them.
func _run_storage_network() -> void:
	var service := app.session.workstations
	var inventory := app.session.inventory
	var foundry_service: FoundryService = app.session.foundry
	var registry := app.session.registry
	# --- T200: foundry slots + auto-feed ---------------------------------
	var origin := Vector3i(24, 0, 42)
	var warehouse_anchor := Vector3i(27, 0, 45)
	var foundry_anchor := Vector3i(29, 0, 45)
	var cells: Array[Vector3i] = [warehouse_anchor, warehouse_anchor + Vector3i(1, 0, 1), foundry_anchor, foundry_anchor + Vector3i(1, 0, 0)]
	var plate_ok := await _wait_levelled(origin, 10, 9, 4, cells)
	inventory.try_transaction({}, {"warehouse": 1, "foundry": 1})
	var warehouse_placed := service.try_place("warehouse", warehouse_anchor, app.session.world.query_cell, app.session.player.get_body_aabb())
	var warehouse_id := str(warehouse_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var foundry_placed := service.try_place("foundry", foundry_anchor, app.session.world.query_cell, app.session.player.get_body_aabb())
	var foundry_id := str(foundry_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var stocked: bool = int(service.container_put(warehouse_id, "iron_ore", 70).get("details", {}).get("moved", 0)) == 70 and int(service.container_put(warehouse_id, "coal", 70).get("details", {}).get("moved", 0)) == 70
	var fresh_slots := foundry_service.slots(foundry_id)
	var slots_present := fresh_slots.has("ore") and fresh_slots.has("fuel") and fresh_slots.has("output")
	foundry_service.advance(0.01, false)
	var after_pull := foundry_service.slots(foundry_id)
	var pulled_ok := str(after_pull.ore.item_id) == "iron_ore" and int(after_pull.ore.count) == 64 and str(after_pull.fuel.item_id) == "coal" and int(after_pull.fuel.count) == 64 and service.container_count(warehouse_id, "iron_ore") == 6 and service.container_count(warehouse_id, "coal") == 6
	var iron_seconds := foundry_service.job_seconds(registry.recipe("iron_ingot"))
	var job_events := foundry_service.advance(iron_seconds + 0.1, false)
	var after_job := foundry_service.slots(foundry_id)
	var smelted_ok := job_events.size() == 1 and service.container_count(warehouse_id, "iron_ingot") == 1 and int(after_job.ore.count) == 63 and int(after_job.fuel.count) == 63 and int(after_job.output.count) == 0
	var foundry_state := foundry_service.state(foundry_id)
	var fields_ok := foundry_state.has("status") and foundry_state.has("elapsed") and foundry_state.has("working") and bool(foundry_state.get("working", false)) and str(foundry_state.get("status", "")).begins_with("smelting")
	# Mid-job: 2 s into the next ingot the panel's bar is running.
	foundry_service.advance(2.0, false)
	var job := foundry_service.job_status(foundry_id)
	var job_ok: bool = bool(job.get("active", false)) and float(job.get("progress", 0.0)) > 0.3 and float(job.get("remaining_seconds", 0.0)) < iron_seconds
	app.state = app.AppState.PLAYING
	app._show_workstation(foundry_id, "foundry")
	app._refresh_foundry_live()
	var bar_ok := app.state == app.AppState.CRAFTING and app.furnace_progress_bar != null and app.furnace_progress_bar.visible and app.furnace_progress_bar.value > 0.0 and app.furnace_progress_label.text.contains(" s") and app.crafting_grid.get_child_count() == 3 and app.foundry_card.visible and app.crafting_inventory_card.visible and not app.furnace_auto_load_slider.visible
	app._close_crafting()
	# The 2 s step topped the slots back up to 64 (the warehouse keeps 5 + 5).
	# Hand access like the furnace: collect the ore slot into the pack, then
	# the next advance refills it from the warehouse's remaining 5.
	var topped_ok := int(foundry_service.slots(foundry_id).ore.count) == 64 and service.container_count(warehouse_id, "iron_ore") == 5 and service.container_count(warehouse_id, "coal") == 5
	var ore_before := inventory.count("iron_ore")
	var collected := service.try_collect_furnace_stack(foundry_id, "input")
	var hand_ok: bool = collected.get("ok", false) and inventory.count("iron_ore") == ore_before + 64 and int(foundry_service.slots(foundry_id).ore.count) == 0
	foundry_service.advance(0.01, false)
	var refilled_ok := int(foundry_service.slots(foundry_id).ore.count) == 5 and service.container_count(warehouse_id, "iron_ore") == 0
	# Save round-trip keeps the slots.
	var restored_service := WorkstationService.new(registry, F0Inventory.new(registry))
	var restored := restored_service.restore(service.snapshot(), app.session.world.query_cell)
	var restored_slots: Dictionary = FoundryService.new(restored_service, registry).slots(foundry_id)
	var restore_ok: bool = restored.get("ok", false) and int(restored_slots.ore.count) == 5 and int(restored_slots.fuel.count) == 64 and str(restored_slots.fuel.item_id) == "coal"
	_record("T200_FOUNDRY_SLOTS", plate_ok and warehouse_placed.get("ok", false) and foundry_placed.get("ok", false) and stocked and slots_present and pulled_ok and smelted_ok and fields_ok and job_ok and bar_ok and topped_ok and hand_ok and refilled_ok and restore_ok, "a foundry beside a warehouse holding 70 ore + 70 coal fills its ore and fuel slots to 64 (6 + 6 stay), smelts one ingot per job back into the warehouse (63/63 left), exposes status/progress, shows a running bar in its panel, allows hand access to the slots, and keeps them across a save", {"pulled": pulled_ok, "smelted": smelted_ok, "topped": topped_ok, "slots": after_job, "state": foundry_state, "job_status": job, "bar": bar_ok, "bar_value": app.furnace_progress_bar.value, "hand": hand_ok, "refilled": refilled_ok, "restore": restore_ok})

	# --- T201: the network ---------------------------------------------------
	var net_origin := Vector3i(-24, 0, 42)
	var first_anchor := Vector3i(-20, 0, 45)
	var second_anchor := Vector3i(-18, 0, 45)
	var chest_anchor := Vector3i(-22, 0, 45)
	var lone_anchor := Vector3i(-14, 0, 45)
	var net_cells: Array[Vector3i] = [first_anchor, first_anchor + Vector3i(1, 0, 1), second_anchor, second_anchor + Vector3i(1, 0, 1), chest_anchor, chest_anchor + Vector3i(1, 0, 0), lone_anchor, lone_anchor + Vector3i(1, 0, 0)]
	var net_plate_ok := await _wait_levelled(net_origin, 12, 9, 4, net_cells)
	inventory.try_transaction({}, {"warehouse": 2, "chest": 2})
	var first_id := str(service.try_place("warehouse", first_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var second_id := str(service.try_place("warehouse", second_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var chest_id := str(service.try_place("chest", chest_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var lone_id := str(service.try_place("chest", lone_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var storage := StorageNetwork.new(service)
	var probe: Array[Vector3i] = [first_anchor + Vector3i(0, 0, -1)]
	var network := storage.network_for(probe)
	var members_ok := not first_id.is_empty() and not second_id.is_empty() and not chest_id.is_empty() and not lone_id.is_empty() and network.size() == 3 and network[0] == first_id and network.has(second_id) and network.has(chest_id) and not network.has(lone_id)
	var capacity := 27 * registry.max_stack("iron_ore")
	var filled: bool = int(service.container_put(first_id, "iron_ore", capacity).get("details", {}).get("moved", 0)) == capacity
	var overflow_left := storage.put(network, "iron_ore", 10)
	var overflow_ok := overflow_left == 0 and service.container_count(first_id, "iron_ore") == capacity and service.container_count(second_id, "iron_ore") + service.container_count(chest_id, "iron_ore") == 10 and storage.count(network, "iron_ore") == capacity + 10
	var drained := storage.take(network, "iron_ore", capacity + 10)
	var drain_ok := drained == capacity + 10 and storage.count(network, "iron_ore") == 0 and service.container_count(chest_id, "iron_ore") == 0 and service.container_count(second_id, "iron_ore") == 0
	var room_ok := storage.room(network, "iron_ore") == capacity * 2 + 9 * registry.max_stack("iron_ore")
	_record("T201_STORAGE_NETWORK", net_plate_ok and members_ok and filled and overflow_ok and drain_ok and room_ok, "a chest beside a warehouse beside another warehouse is one network from a cell touching the first (nearest first, a chest three cells off is not), put overflows a full warehouse into the rest, take drains across them", {"network": network, "first": first_id, "second": second_id, "chest": chest_id, "lone": lone_id, "overflow_left": overflow_left, "drained": drained, "room": storage.room(network, "iron_ore")})

	# --- T202: adjacent ammo ---------------------------------------------------
	var siege_origin := Vector3i(-48, 0, 26)
	var catapult_anchor := Vector3i(-46, 0, 28)
	var shot_chest_anchor := Vector3i(-44, 0, 28)
	var ballista_anchor := Vector3i(-46, 0, 34)
	var bolt_chest_anchor := Vector3i(-48, 0, 34)
	var cannon_anchor := Vector3i(-40, 0, 34)
	var wrong_chest_anchor := Vector3i(-38, 0, 34)
	var siege_cells: Array[Vector3i] = [catapult_anchor, catapult_anchor + Vector3i(1, 0, 3), shot_chest_anchor, ballista_anchor, ballista_anchor + Vector3i(1, 0, 1), bolt_chest_anchor, cannon_anchor, cannon_anchor + Vector3i(1, 0, 1), wrong_chest_anchor]
	var siege_plate_ok := await _wait_levelled(siege_origin, 14, 12, 4, siege_cells)
	inventory.try_transaction({}, {"catapult": 1, "ballista": 1, "cannon": 1, "chest": 3})
	var catapult_id := str(service.try_place("catapult", catapult_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var shot_chest_id := str(service.try_place("chest", shot_chest_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var ballista_id := str(service.try_place("ballista", ballista_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var bolt_chest_id := str(service.try_place("chest", bolt_chest_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var cannon_id := str(service.try_place("cannon", cannon_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var wrong_chest_id := str(service.try_place("chest", wrong_chest_anchor, app.session.world.query_cell, app.session.player.get_body_aabb()).get("details", {}).get("station", {}).get("instance_id", ""))
	var siege_placed := not catapult_id.is_empty() and not shot_chest_id.is_empty() and not ballista_id.is_empty() and not bolt_chest_id.is_empty() and not cannon_id.is_empty() and not wrong_chest_id.is_empty()
	for weapon_id: String in [catapult_id, ballista_id, cannon_id]:
		if service.stations.has(weapon_id):
			service.stations[weapon_id]["siege_ammo"] = 0
	var siege_stocked: bool = int(service.container_put(shot_chest_id, "stone_shot", 5).get("details", {}).get("moved", 0)) == 5 and int(service.container_put(bolt_chest_id, "ballista_bolt", 3).get("details", {}).get("moved", 0)) == 3 and int(service.container_put(wrong_chest_id, "stone_shot", 4).get("details", {}).get("moved", 0)) == 4
	var reload_messages: Array[String] = []
	var on_reload := func(_instance_id: String, _anchor: Vector3i, message: String) -> void: reload_messages.append(message)
	app.session.siege_defense.storage_reloaded.connect(on_reload)
	app.session.siege_defense.advance(SiegeDefenseService.SIEGE_AUTO_RELOAD_SECONDS + 0.1, false)
	app.session.siege_defense.storage_reloaded.disconnect(on_reload)
	var catapult_ammo := int(service.siege_status(catapult_id).get("details", {}).get("ammo", 0))
	var ballista_ammo := int(service.siege_status(ballista_id).get("details", {}).get("ammo", 0))
	var cannon_ammo := int(service.siege_status(cannon_id).get("details", {}).get("ammo", 0))
	var catapult_ok := catapult_ammo == 5 and service.container_count(shot_chest_id, "stone_shot") == 0 and str(service.siege_status(catapult_id).get("details", {}).get("ammo_item", "")) == "stone_shot"
	var ballista_ok := ballista_ammo == 3 and service.container_count(bolt_chest_id, "ballista_bolt") == 0
	var wrong_ok := cannon_ammo == 0 and service.container_count(wrong_chest_id, "stone_shot") == 4
	var messages_ok := reload_messages.size() == 2 and reload_messages.all(func(message: String) -> bool: return message.contains("reloaded from storage"))
	_record("T202_ADJACENT_AMMO", siege_plate_ok and siege_placed and siege_stocked and catapult_ok and ballista_ok and wrong_ok and messages_ok, "an empty catapult beside a chest with 5 stone shot and an empty ballista beside a chest with 3 bolts reload from them after SIEGE_AUTO_RELOAD_SECONDS (one HUD line each); a cannon beside a chest of stone shot stays empty", {"catapult": catapult_ammo, "ballista": ballista_ammo, "cannon": cannon_ammo, "messages": reload_messages, "shot_left": service.container_count(shot_chest_id, "stone_shot"), "bolts_left": service.container_count(bolt_chest_id, "ballista_bolt")})


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
