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
	_record("T94_TRANSACTIONAL_AUTOLOAD", target_15.get("ok", false) and int(loaded_slots.input.count) == 15 and int(loaded_slots.fuel.count) == 5 and lowered.get("ok", false) and int(lowered_slots.input.count) == 4 and int(lowered_slots.fuel.count) == 2 and auto_inventory.count("iron_ore") + int(lowered_slots.input.count) == 15 and auto_inventory.count("coal") + int(lowered_slots.fuel.count) == 10 and int(auto_status.get("details", {}).get("limit", 0)) == 15, "the 0–64 target loads the counted 1:3 coal ratio, lowers transactionally and conserves exact totals", {"loaded": loaded_slots, "lowered": lowered_slots, "status": auto_status.get("details", {})})

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
	var fuel_after_one := timed_service.furnace_fuel_status(timed_id)
	_record("T95_ITEM_PROGRESS_SEQUENCE", started.get("ok", false) and absf(float(halfway.progress) - 0.5) < 0.01 and int(after_one.output.count) == 1 and bool(next_job.active) and float(next_job.progress) < 0.01 and int(after_one.input.count) == 1 and str(after_one.fuel.item_id) == "coal" and int(after_one.fuel.count) == 1 and int(fuel_after_one.get("details", {}).get("stored_operations", -1)) == 1 and bool(fuel_after_one.get("details", {}).get("burning", false)), "each item exposes measurable progress, deposits one retained output, resets for the next loaded item, spends only one stored fuel operation and keeps the burning Coal in the Fuel slot", {"halfway": halfway, "after_one": after_one, "next_job": next_job, "fuel": fuel_after_one})

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
	_level_catapult_ground(Vector3i(7, 0, 38))
	var catapult := app.session.workstations.try_place("catapult", Vector3i(7, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var catapult_id := str(catapult.get("details", {}).get("station", {}).get("instance_id", ""))
	var catapult_body: Node3D = app.session._station_visuals.get(catapult_id)
	var wheel_count := 0
	var part_count := 0
	var turret_ok := false
	if catapult_body != null:
		var turret: Node = catapult_body.get_node_or_null("SiegeTurret")
		turret_ok = turret != null and turret.find_child("CatapultArm", true, false) != null and turret.find_child("CatapultBucket", true, false) != null
		wheel_count = catapult_body.find_children("CatapultWheel_*", "", true, false).size()
		part_count = catapult_body.find_children("*", "MeshInstance3D", true, false).size()
	_record("T97_CATAPULT_WORLD_IDENTITY", catapult.get("ok", false) and catapult_body != null and wheel_count == 4 and part_count >= 14 and turret_ok, "the placed Catapult has a recognizable wheeled chassis, axle, throwing arm, basket and projectile rather than generic boxes", {"parts": part_count, "wheels": wheel_count, "turret": turret_ok})

	# P3I: a Furnace with input and fuel deposited, never started by hand, runs
	# on its own and keeps running one item at a time until the input is spent.
	var auto_run := _fixture(2, 1)
	var auto_run_service: WorkstationService = auto_run.service
	var auto_run_inventory: F0Inventory = auto_run.inventory
	var auto_run_id := str(auto_run.furnace_id)
	var ore_moved := auto_run_service.try_transfer_inventory_stack_to_furnace(auto_run_id, _slot_for(auto_run_inventory, "iron_ore"))
	var coal_moved := auto_run_service.try_transfer_inventory_stack_to_furnace(auto_run_id, _slot_for(auto_run_inventory, "coal"))
	var idle_before := not bool(auto_run_service.furnace_job_status(auto_run_id).get("active", false))
	auto_run_service.advance(0.01, false)
	var self_started := bool(auto_run_service.furnace_job_status(auto_run_id).get("active", false))
	var paused_no_start := true
	var paused_fixture := _fixture(1, 1)
	var paused_service: WorkstationService = paused_fixture.service
	var paused_inventory: F0Inventory = paused_fixture.inventory
	var paused_id := str(paused_fixture.furnace_id)
	paused_service.try_transfer_inventory_stack_to_furnace(paused_id, _slot_for(paused_inventory, "iron_ore"))
	paused_service.try_transfer_inventory_stack_to_furnace(paused_id, _slot_for(paused_inventory, "coal"))
	paused_service.advance(0.5, true)
	paused_no_start = not bool(paused_service.furnace_job_status(paused_id).get("active", false))
	var duration := float(app.session.registry.recipe("iron_ingot").get("duration_seconds", 0.0))
	auto_run_service.advance(duration * 2.0 + 0.1, false)
	auto_run_service.advance(duration + 0.1, false)
	var finished_slots := auto_run_service.furnace_slots(auto_run_id)
	var finished_job := auto_run_service.furnace_job_status(auto_run_id)
	var two_ingots := str(finished_slots.get("output", {}).get("item_id", "")) == "iron_ingot" and int(finished_slots.get("output", {}).get("count", 0)) == 2
	var input_spent := int(finished_slots.get("input", {}).get("count", 0)) == 0
	var stops_idle := not bool(finished_job.get("active", false))
	# Fuel model 2: two operations used of the Coal's three, so the Coal is still
	# in the slot with one operation left; it leaves only when burnt out.
	var burning_coal_kept := str(finished_slots.get("fuel", {}).get("item_id", "")) == "coal" and int(finished_slots.get("fuel", {}).get("count", 0)) == 1 		and int(auto_run_service.furnace_fuel_status(auto_run_id).get("details", {}).get("stored_operations", -1)) == 1
	var burn_out := _fixture(3, 1)
	var burn_service: WorkstationService = burn_out.service
	var burn_inventory: F0Inventory = burn_out.inventory
	var burn_id := str(burn_out.furnace_id)
	var counted_move := burn_service.try_transfer_inventory_item_to_furnace(burn_id, "iron_ore", 5)
	burn_service.try_transfer_inventory_stack_to_furnace(burn_id, _slot_for(burn_inventory, "coal"))
	burn_service.advance(0.01, false)
	# Round 3 fuel timing: after two full items the THIRD job is running on the
	# Coal's last operation; the Coal must still sit in the Fuel slot (0 left,
	# burning) and leave only when that third job completes.
	burn_service.advance(duration * 2.0 + 0.5, false)
	var third_running_slots := burn_service.furnace_slots(burn_id)
	var third_running_job := burn_service.furnace_job_status(burn_id)
	var third_running_fuel: Dictionary = burn_service.furnace_fuel_status(burn_id).get("details", {})
	var coal_present_during_last_job: bool = bool(third_running_job.get("active", false)) and int(third_running_slots.get("output", {}).get("count", 0)) == 2 \
		and str(third_running_slots.get("fuel", {}).get("item_id", "")) == "coal" and int(third_running_slots.get("fuel", {}).get("count", 0)) == 1 \
		and int(third_running_fuel.get("stored_operations", -1)) == 0 and bool(third_running_fuel.get("burning", false)) and int(third_running_fuel.get("available_operations", -1)) == 0
	var third_completed := burn_service.advance(duration, false)
	var burnt_slots := burn_service.furnace_slots(burn_id)
	var completion_fuel: Dictionary = third_completed[0].get("details", {}).get("fuel", {}) if third_completed.size() == 1 else {}
	var coal_burnt_out: bool = int(counted_move.get("details", {}).get("moved", 0)) == 3 and int(burnt_slots.get("output", {}).get("count", 0)) == 3 \
		and str(burnt_slots.get("fuel", {}).get("item_id", "")).is_empty() and not bool(burn_service.furnace_job_status(burn_id).get("active", false)) \
		and int(burn_service.furnace_fuel_status(burn_id).get("details", {}).get("stored_operations", -1)) == 0 \
		and not bool(burn_service.furnace_fuel_status(burn_id).get("details", {}).get("burning", true)) \
		and third_completed.size() == 1 and str(third_completed[0].get("details", {}).get("furnace_slots", {}).get("fuel", {}).get("item_id", "x")).is_empty() and not bool(completion_fuel.get("burning", true))
	# Snapshot/restore round-trips the lit-but-exhausted Coal (round 3 field).
	var trip_fixture := _fixture(3, 1)
	var trip_service: WorkstationService = trip_fixture.service
	var trip_inventory: F0Inventory = trip_fixture.inventory
	var trip_id := str(trip_fixture.furnace_id)
	trip_service.try_transfer_inventory_stack_to_furnace(trip_id, _slot_for(trip_inventory, "iron_ore"))
	trip_service.try_transfer_inventory_stack_to_furnace(trip_id, _slot_for(trip_inventory, "coal"))
	trip_service.advance(duration * 2.0 + 0.5, false)
	var trip_saved := trip_service.snapshot()
	var trip_restored := WorkstationService.new(app.session.registry, F0Inventory.new(app.session.registry))
	var trip_restore := trip_restored.restore(trip_saved, _fixture_world_query)
	var trip_fuel_after_restore: Dictionary = trip_restored.furnace_fuel_status(trip_id).get("details", {})
	var trip_slots_after_restore := trip_restored.furnace_slots(trip_id)
	trip_restored.advance(duration, false)
	var trip_final := trip_restored.furnace_slots(trip_id)
	var legacy_saved: Dictionary = trip_saved.duplicate(true)
	for legacy_station: Dictionary in legacy_saved.get("stations", []):
		legacy_station.erase("furnace_fuel_burning")
	var legacy_restored := WorkstationService.new(app.session.registry, F0Inventory.new(app.session.registry))
	var legacy_restore := legacy_restored.restore(legacy_saved, _fixture_world_query)
	legacy_restored.advance(duration, false)
	var legacy_final := legacy_restored.furnace_slots(trip_id)
	var round_trip_ok: bool = trip_restore.get("ok", false) and bool(trip_fuel_after_restore.get("burning", false)) and int(trip_fuel_after_restore.get("stored_operations", -1)) == 0 \
		and str(trip_slots_after_restore.get("fuel", {}).get("item_id", "")) == "coal" and int(trip_final.get("output", {}).get("count", 0)) == 3 and str(trip_final.get("fuel", {}).get("item_id", "")).is_empty() \
		and legacy_restore.get("ok", false) and int(legacy_final.get("output", {}).get("count", 0)) == 3
	_record("T107_FURNACE_AUTO_PROCESSING", ore_moved.get("ok", false) and coal_moved.get("ok", false) and idle_before and self_started and paused_no_start and two_ingots and input_spent and stops_idle and burning_coal_kept and coal_present_during_last_job and coal_burnt_out and round_trip_ok, "a Furnace holding input and fuel starts without a manual press on the next unpaused tick, never while paused, processes every input one at a time into retained Output, returns to idle when the input is spent, keeps the Coal in the slot while its last job runs and removes it only when that job completes, round-trips the lit Coal through snapshot/restore (legacy records included) and accepts counted +N transfers", {"idle_before": idle_before, "self_started": self_started, "paused_no_start": paused_no_start, "slots": finished_slots, "job": finished_job, "burning_coal_kept": burning_coal_kept, "third_running_slots": third_running_slots, "third_running_fuel": third_running_fuel, "coal_present_during_last_job": coal_present_during_last_job, "burnt_slots": burnt_slots, "completion_fuel": completion_fuel, "round_trip_ok": round_trip_ok, "trip_fuel_after_restore": trip_fuel_after_restore, "legacy_final": legacy_final, "counted_move": counted_move.get("details", {})})

	# Round 3 gesture: select an ore or Coal tile, then click Raw Input / Fuel
	# (+1, Shift +5); the Load button works without the recipe book.
	app.session.inventory.try_transaction({}, {"furnace": 1, "iron_ore": 9, "coal": 3})
	var gesture_placed := app.session.workstations.try_place("furnace", Vector3i(11, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var gesture_id := str(gesture_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	app.state = app.AppState.PLAYING
	app._show_crafting(gesture_id, "furnace")
	var ore_slot := _slot_for(app.session.inventory, "iron_ore")
	var coal_slot := _slot_for(app.session.inventory, "coal")
	app._select_crafting_inventory_slot(ore_slot)
	var ore_selection_message := str(app.crafting_message.text)
	var ore_tile_highlighted: bool = app.crafting_inventory_slots[ore_slot].is_selected() and not app.crafting_inventory_slots[coal_slot].is_selected()
	var recipe_after_select := str(app._selected_recipe_id)
	var load_enabled_after_select: bool = not app.craft_selected_button.disabled
	app._on_crafting_grid_slot_pressed(0)
	var input_after_one := int(app.session.workstations.furnace_slots(gesture_id).get("input", {}).get("count", 0))
	var selection_kept_after_click: bool = app._crafting_selected_inventory_item == "iron_ore" and app.crafting_inventory_slots[ore_slot].is_selected()
	app._on_crafting_stack_gesture("furnace", 0, MOUSE_BUTTON_LEFT, false, false, true)
	var input_after_shift := int(app.session.workstations.furnace_slots(gesture_id).get("input", {}).get("count", 0))
	app._select_crafting_inventory_slot(coal_slot)
	var coal_selection_message := str(app.crafting_message.text)
	var coal_tile_highlighted: bool = app.crafting_inventory_slots[coal_slot].is_selected() and not app.crafting_inventory_slots[ore_slot].is_selected()
	app._on_crafting_grid_slot_pressed(1)
	var gesture_fuel_after_one := int(app.session.workstations.furnace_slots(gesture_id).get("fuel", {}).get("count", 0))
	app._on_crafting_grid_slot_pressed(0)
	var wrong_slot_message := str(app.crafting_message.text)
	var input_after_wrong := int(app.session.workstations.furnace_slots(gesture_id).get("input", {}).get("count", 0))
	# Load button with no recipe chosen in the book: one more batch is staged.
	app._crafting_selected_inventory_item = ""
	app._selected_recipe_id = ""
	app._refresh_crafting_panel()
	var recipe_inferred_from_input := str(app._selected_recipe_id)
	var load_enabled_without_book: bool = not app.craft_selected_button.disabled
	var before_load: Dictionary = app.session.workstations.furnace_slots(gesture_id)
	app._craft_selected_recipe()
	var after_load: Dictionary = app.session.workstations.furnace_slots(gesture_id)
	# Additive Load x1: 6 -> 7 ore, and the Coal owed to 7 staged ore (7 ops
	# against 3 available) tops Fuel up from 1 to 3; nothing is returned.
	var loaded_one_batch: bool = int(after_load.get("input", {}).get("count", 0)) == int(before_load.get("input", {}).get("count", 0)) + 1 and int(after_load.get("fuel", {}).get("count", 0)) == 3 and int(before_load.get("fuel", {}).get("count", 0)) == 1
	var slider_editable: bool = app.furnace_auto_load_slider.editable and app.furnace_auto_load_slider.max_value >= 8.0
	var layout_limit := get_viewport().get_visible_rect().size.y
	await _settle_frames(2)
	var headless_bottom := app.crafting_clear_button.get_global_rect().end.y
	var headless_message_bottom := app.crafting_message.get_global_rect().end.y
	app._close_crafting()
	var gesture_ok: bool = gesture_placed.get("ok", false) and ore_selection_message == "Iron Ore selected — click Raw Input to add 1, Shift+Click adds 5" and ore_tile_highlighted \
		and recipe_after_select == "iron_ingot" and load_enabled_after_select and input_after_one == 1 and selection_kept_after_click and input_after_shift == 6 \
		and coal_selection_message == "Coal selected — click Fuel to add 1, Shift+Click adds 5" and coal_tile_highlighted and gesture_fuel_after_one == 1 \
		and wrong_slot_message == "Coal belongs in the Fuel slot." and input_after_wrong == 6 \
		and recipe_inferred_from_input == "iron_ingot" and load_enabled_without_book and loaded_one_batch and slider_editable \
		and headless_bottom <= layout_limit and headless_message_bottom <= layout_limit
	_record("T114_FURNACE_SELECT_THEN_ADD", gesture_ok, "clicking an ore or Coal tile highlights it and names its slot; Raw Input / Fuel clicks add +1 (Shift +5); the Load button and slider work with the recipe inferred from the ore, no recipe-book choice needed; the modal's buttons stay inside the viewport", {"ore_selection_message": ore_selection_message, "ore_tile_highlighted": ore_tile_highlighted, "recipe_after_select": recipe_after_select, "load_enabled_after_select": load_enabled_after_select, "input_after_one": input_after_one, "input_after_shift": input_after_shift, "coal_selection_message": coal_selection_message, "fuel_after_one": gesture_fuel_after_one, "wrong_slot_message": wrong_slot_message, "recipe_inferred_from_input": recipe_inferred_from_input, "load_enabled_without_book": load_enabled_without_book, "before_load": before_load, "after_load": after_load, "slider_max": app.furnace_auto_load_slider.max_value, "clear_button_bottom": headless_bottom, "message_bottom": headless_message_bottom, "viewport_height": layout_limit})

func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.inventory.try_transaction({}, {"furnace": 1, "iron_ore": 12, "coal": 5, "catapult": 1})
	var furnace := app.session.workstations.try_place("furnace", Vector3i(3, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var furnace_id := str(furnace.get("details", {}).get("station", {}).get("instance_id", ""))
	app.session.workstations.try_set_furnace_autoload_target(furnace_id, "iron_ingot", 8)
	app.session.workstations.try_start_furnace(furnace_id, "iron_ingot")
	app.state = app.AppState.PLAYING
	app._show_crafting(furnace_id, "furnace")
	app._process(2.5)
	app._select_crafting_inventory_slot(_slot_for(app.session.inventory, "iron_ore"))
	await _settle_frames(4)
	var modal_path := app.data_root.path_join("p3g-furnace-autoload-progress.png")
	var modal_ok := await _save_viewport(modal_path)
	# Round 3: the whole modal, including the bottom button and the message,
	# must sit inside the 1280x720 canvas in furnace and workbench modes.
	var viewport_height := get_viewport().get_visible_rect().size.y
	var furnace_button_bottom := app.crafting_clear_button.get_global_rect().end.y
	var furnace_message_bottom := app.crafting_message.get_global_rect().end.y
	var furnace_fits := furnace_button_bottom <= viewport_height and furnace_message_bottom <= viewport_height
	app._close_crafting()
	app.session.inventory.try_transaction({}, {"workbench": 1})
	var workbench := app.session.workstations.try_place("workbench", Vector3i(5, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	app._show_crafting(str(workbench.get("details", {}).get("station", {}).get("instance_id", "")), "workbench")
	app._select_crafting_inventory_slot(_slot_for(app.session.inventory, "iron_ore"))
	await _settle_frames(4)
	var workbench_path := app.data_root.path_join("p3g-workbench-modal-fit.png")
	var workbench_ok := await _save_viewport(workbench_path)
	var workbench_button_bottom := app.crafting_clear_button.get_global_rect().end.y
	var workbench_message_bottom := app.crafting_message.get_global_rect().end.y
	var workbench_fits: bool = workbench.get("ok", false) and workbench_button_bottom <= viewport_height and workbench_message_bottom <= viewport_height
	app._close_crafting()
	# Round 3: drive the real click path (viewport input, not handler calls):
	# press/release on the ore tile, then on Raw Input, then Shift+click on
	# Raw Input. CraftingItemSlot._gui_input must not swallow the plain click.
	app.session.inventory.try_transaction({}, {"furnace": 1})
	var click_furnace := app.session.workstations.try_place("furnace", Vector3i(9, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	var click_id := str(click_furnace.get("details", {}).get("station", {}).get("instance_id", ""))
	app._show_crafting(click_id, "furnace")
	await _settle_frames(2)
	var ore_tile: CraftingItemSlot = app.crafting_inventory_slots[_slot_for(app.session.inventory, "iron_ore")]
	await _click_at(ore_tile.get_global_rect().get_center(), false)
	var clicked_selected := str(app._crafting_selected_inventory_item)
	var clicked_highlight: bool = ore_tile.is_selected()
	var raw_input_cell: Control = app.crafting_grid_slots[0]
	await _click_at(raw_input_cell.get_global_rect().get_center(), false)
	var clicked_input := int(app.session.workstations.furnace_slots(click_id).get("input", {}).get("count", 0))
	raw_input_cell = app.crafting_grid_slots[0]
	await _click_at(raw_input_cell.get_global_rect().get_center(), true)
	var shift_clicked_input := int(app.session.workstations.furnace_slots(click_id).get("input", {}).get("count", 0))
	var click_path_path := app.data_root.path_join("p3g-furnace-select-then-add.png")
	var click_path_ok := await _save_viewport(click_path_path)
	app._close_crafting()
	_record("T115_FURNACE_CLICK_PATH", click_furnace.get("ok", false) and clicked_selected == "iron_ore" and clicked_highlight and clicked_input == 1 and shift_clicked_input == 4 and click_path_ok, "real mouse presses on the ore tile then Raw Input add one ore (Shift+click adds the rest, up to five) through the slot's own input handling", {"selected": clicked_selected, "highlighted": clicked_highlight, "input_after_click": clicked_input, "input_after_shift_click": shift_clicked_input, "path": click_path_path})
	_level_catapult_ground(Vector3i(7, 0, 38))
	var catapult := app.session.workstations.try_place("catapult", Vector3i(7, 0, 38), app.session.world.query_cell, app.session.player.get_body_aabb())
	app.session.apply_world_settings("1200", false)
	app.session.player.global_position = Vector3(11.4, 0.9, 43.6)
	app.session.player.look_at(Vector3(8.0, 0.4, 39.8), Vector3.UP)
	await _settle_frames(12)
	var catapult_path := app.data_root.path_join("p3g-catapult-world-model.png")
	var catapult_ok := await _save_viewport(catapult_path)
	_record("T98_FURNACE_AND_CATAPULT_PRESENTATION", modal_ok and catapult.get("ok", false) and catapult_ok and furnace_fits and workbench_ok and workbench_fits, "rendered evidence shows the auto-load/progress controls and the revised placed Catapult, and the crafting modal (furnace and workbench, with a selection message showing) ends inside the 720-unit canvas", {"modal_path": modal_path, "workbench_path": workbench_path, "catapult_path": catapult_path, "size": get_viewport().get_visible_rect().size, "furnace_button_bottom": furnace_button_bottom, "furnace_message_bottom": furnace_message_bottom, "workbench_button_bottom": workbench_button_bottom, "workbench_message_bottom": workbench_message_bottom})


func _click_at(global_position: Vector2, shift: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.shift_pressed = shift
		event.position = global_position
		event.global_position = global_position
		get_viewport().push_input(event)
		await get_tree().process_frame
	await _settle_frames(2)


## The Catapult occupies 2 x 4 cells (P4 footprint); give it flat ground and
## clear air so the placement depends on the definition, not the seeded hills.
func _level_catapult_ground(anchor: Vector3i) -> void:
	for x in range(2):
		for z in range(4):
			app.session.world.set_cell(anchor + Vector3i(x, -1, z), 3)
			for y in range(3):
				app.session.world.set_cell(anchor + Vector3i(x, y, z), 0)


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
