class_name F2Automation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	if mode == "visual":
		await _run_visual()
		return
	if mode == "continue":
		await _run_continue()
		_finish_gate()
		return
	if mode != "gate":
		push_error("Unknown F2 automation mode: " + mode)
		get_tree().quit(2)
		return
	await _run_gate()
	if failures.is_empty():
		var saved := await app.saves.save_session(app.session)
		_record("F2_CHECKPOINT", saved.get("ok", false), "F2 terrain, slots and stations publish in one checkpoint", saved)
	_finish_gate()


func _finish_gate() -> void:
	if failures.is_empty():
		print("F2_AUTOMATION_PASS T19-T22")
		get_tree().quit(0)
	else:
		push_error("F2_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_continue() -> void:
	app._on_continue_pressed()
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 20000:
		await get_tree().process_frame
	var restored := app.state == app.AppState.PLAYING and app.session.inventory.count("iron_pick") == 1 and app.session.workstations.stations.size() == 2 and app.session.workstations.jobs.is_empty()
	_record("F2_CONTINUE", restored, "Continue restores F2 inventory and both placed idle workstations without duplicates", {"state": app.state, "status": app.status_label.text, "inventory": app.session.inventory.snapshot() if app.session != null else {}, "stations": app.session.workstations.snapshot() if app.session != null else {}})


func _run_visual() -> void:
	for _frame in range(3):
		await get_tree().process_frame
	app._show_keybinds()
	await _capture("f2-keybinds.png", "F2_VISUAL_KEYBINDS")
	app._close_keybinds()
	app._on_start_pressed()
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 20000:
		await get_tree().process_frame
	if app.state != app.AppState.PLAYING:
		push_error("F2 visual session failed: " + app.status_label.text)
		get_tree().quit(1)
		return
	app._show_inventory()
	for _frame in range(3):
		await get_tree().process_frame
	await _capture("f2-inventory.png", "F2_VISUAL_INVENTORY")
	get_tree().quit(0)


func _capture(filename: String, test_id: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join(filename)
	var error := image.save_png(path)
	print("%s %s path=%s size=%s" % [test_id, "PASS" if error == OK else "FAIL", path, image.get_size()])


func _run_gate() -> void:
	_test_keybind_ui()
	app._on_start_pressed()
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 20000:
		await get_tree().process_frame
	_record("T19_WORLD_READY", app.state == app.AppState.PLAYING, "fresh empty-inventory world becomes collision/edit ready", {"state": app.state, "status": app.status_label.text})
	if app.state != app.AppState.PLAYING:
		return
	await _wait_cells([Vector3i(4, 0, 40), Vector3i(-8, -3, 35), Vector3i(10, -4, 35), Vector3i(5, -4, 32)])
	await _test_progression()
	_test_atomic_crafting()
	_test_workstation_placement()
	_test_furnace_jobs()


func _test_progression() -> void:
	var inventory := app.session.inventory
	var interaction := app.session.interaction
	var empty_start := _total_items(inventory) == 0
	for x in [4, 7]:
		for y in range(4):
			var result := interaction.try_break_cell(Vector3i(x, y, 40))
			if not result.get("ok", false):
				failures.append("T19 log harvest " + str(result))
	for _index in range(3):
		_require_ok(app.session.try_craft("planks", "hand"), "T19 hand planks")
	_require_ok(app.session.try_craft("sticks", "hand"), "T19 hand sticks")
	_require_ok(app.session.try_craft("workbench", "hand"), "T19 hand workbench")
	var bench_place := interaction.try_place_item(Vector3i(2, 0, 38), "workbench")
	_require_ok(bench_place, "T19 workbench placement")
	var bench_id := str(bench_place.get("changes", {}).get("station", {}).get("instance_id", ""))
	_require_ok(app.session.try_craft("wood_pick", "workbench", bench_id), "T19 wood pick")
	_require_ok(app.session.try_craft("sticks", "hand"), "T19 second sticks")
	_select_item("wood_pick")
	for x in range(-5, 6):
		for y in [-1, -2, -3, -4]:
			var result := interaction.try_break_cell(Vector3i(x, y, 32))
			if not result.get("ok", false):
				failures.append("T19 stone route %s %s" % [Vector3i(x, y, 32), result])
	_require_ok(app.session.try_craft("stone_pick", "workbench", bench_id), "T19 stone pick")
	_require_ok(app.session.try_craft("furnace", "workbench", bench_id), "T19 furnace")
	var furnace_place := interaction.try_place_item(Vector3i(3, 0, 38), "furnace")
	_require_ok(furnace_place, "T19 furnace placement")
	var furnace_id := str(furnace_place.get("changes", {}).get("station", {}).get("instance_id", ""))
	_select_item("stone_pick")
	for x in range(8, 11):
		_require_ok(interaction.try_break_cell(Vector3i(x, -3, 35)), "T19 coal harvest")
	for x in range(-8, -5):
		_require_ok(interaction.try_break_cell(Vector3i(x, -3, 35)), "T19 iron harvest")
	for _index in range(3):
		_require_ok(app.session.try_craft("iron_ingot", "furnace", furnace_id), "T19 furnace start")
		app.session.workstations.advance(5.0, false)
	_require_ok(app.session.try_craft("iron_pick", "workbench", bench_id), "T19 iron pick")
	var reached := empty_start and inventory.count("wood_pick") == 1 and inventory.count("stone_pick") == 1 and inventory.count("iron_pick") == 1 and inventory.count("iron_ingot") == 0
	_record("T19_PROGRESSION", reached, "empty inventory reaches wood pick, stone pick, three smelts and iron pick through world/crafting commands", inventory.snapshot())


func _test_atomic_crafting() -> void:
	var registry := ContentRegistry.new()
	var inventory := F0Inventory.new(registry)
	var crafting := CraftingService.new(registry, inventory)
	var before := inventory.snapshot()
	var insufficient := crafting.try_craft("planks", "hand")
	_record("T20_INSUFFICIENT", insufficient.get("reason") == "INSUFFICIENT_INPUT" and before == inventory.snapshot(), "missing inputs leave inventory unchanged", insufficient)
	inventory.try_transaction({}, {"log": 2, "wood_pick": 26})
	before = inventory.snapshot()
	var full := crafting.try_craft("planks", "hand")
	_record("T20_CAPACITY", full.get("reason") == "INVENTORY_FULL" and before == inventory.snapshot(), "blocked output capacity leaves inputs untouched", full)
	var exact_inventory := F0Inventory.new(registry)
	var exact_crafting := CraftingService.new(registry, exact_inventory)
	exact_inventory.try_transaction({}, {"log": 1})
	var first := exact_crafting.try_craft("planks", "hand")
	var second := exact_crafting.try_craft("planks", "hand")
	_record("T20_EXACT_DOUBLE_CLICK", first.get("ok", false) and second.get("reason") == "INSUFFICIENT_INPUT" and exact_inventory.count("planks") == 4, "double activation produces one exact output only", {"first": first, "second": second, "snapshot": exact_inventory.snapshot()})
	var wrong := exact_crafting.try_craft("wood_pick", "hand")
	_record("T20_WRONG_STATION", wrong.get("reason") == "WRONG_WORKSTATION", "wrong workstation is explicit", wrong)
	var slot_inventory := F0Inventory.new(registry)
	slot_inventory.try_transaction({}, {"log": 1})
	var moved := slot_inventory.swap_slots(0, 10)
	var selected := slot_inventory.select_hotbar(8)
	var before_invalid := slot_inventory.snapshot()
	var invalid := slot_inventory.swap_slots(10, 99)
	var slot_passed: bool = bool(moved.get("ok", false)) and str(slot_inventory.slots[10].item_id) == "log" and int(slot_inventory.slots[0].count) == 0 and bool(selected.get("ok", false)) and slot_inventory.selected_hotbar == 8 and invalid.get("reason") == "INVALID_SLOT" and before_invalid == slot_inventory.snapshot()
	_record("T20_SLOT_HOTBAR", slot_passed, "items move between hotbar/storage slots, selection changes, and invalid moves are harmless", {"moved": moved, "selected": selected, "invalid": invalid, "snapshot": slot_inventory.snapshot()})


func _test_keybind_ui() -> void:
	app._show_keybinds()
	var all_rows := app.binding_rows.size() == SettingsStore.BINDING_ACTIONS.size()
	app.keybind_search.text = "forward"
	app._refresh_binding_labels()
	var visible_actions: Array[String] = []
	for action in app.binding_rows:
		if app.binding_rows[action].visible:
			visible_actions.append(str(action))
	var rebound := app.settings.rebind_key("move_forward", KEY_R)
	app._refresh_binding_labels()
	var reset_enabled: bool = not app.binding_reset_buttons["move_forward"].disabled
	app._reset_binding("move_forward")
	var restored: bool = app.settings.is_default_binding("move_forward") and app.settings.get_binding_label("move_forward") == "E" and app.binding_reset_buttons["move_forward"].disabled
	var passed: bool = all_rows and visible_actions == ["move_forward"] and bool(rebound.get("ok", false)) and reset_enabled and restored
	_record("F2_KEYBIND_UI", passed, "all actions are grouped into rows; search filters; one action can be rebound and reset independently", {"row_count": app.binding_rows.size(), "visible_actions": visible_actions, "rebound": rebound, "reset_enabled": reset_enabled, "restored_label": app.settings.get_binding_label("move_forward")})
	app._close_keybinds()


func _test_workstation_placement() -> void:
	var registry := ContentRegistry.new()
	var inventory := F0Inventory.new(registry)
	var service := WorkstationService.new(registry, inventory)
	var query := func(cell: Vector3i) -> Dictionary: return {"state": "LOADED", "voxel_id": 1 if cell.y == -1 else 0}
	inventory.try_transaction({}, {"workbench": 1})
	var placed := service.try_place("workbench", Vector3i(0, 0, 0), query, AABB())
	var instance_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var after_place := inventory.snapshot()
	var duplicate := service.try_place("workbench", Vector3i(0, 0, 0), query, AABB())
	var support_locked := service.supported_by(Vector3i(0, -1, 0))
	var dismantled := service.try_dismantle(instance_id, query, AABB())
	_record("T21_PLACE_DISMANTLE", placed.get("ok", false) and inventory.count("workbench") == 1 and not duplicate.get("ok", false) and duplicate.get("reason") in ["NO_RESOURCE", "OCCUPIED"] and support_locked and dismantled.get("ok", false) and int(after_place.dirt) == 0, "placement consumes one; duplicate is refused; support is owned; idle dismantle returns one", {"placed": placed, "duplicate": duplicate, "dismantled": dismantled, "inventory": inventory.snapshot()})


func _test_furnace_jobs() -> void:
	var registry := ContentRegistry.new()
	var inventory := F0Inventory.new(registry)
	var service := WorkstationService.new(registry, inventory)
	var query := func(cell: Vector3i) -> Dictionary: return {"state": "LOADED", "voxel_id": 1 if cell.y == -1 else 0}
	inventory.try_transaction({}, {"furnace": 1, "iron_ore": 1, "coal": 1})
	var placed := service.try_place("furnace", Vector3i(1, 0, 0), query, AABB())
	var instance_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var started := service.try_start_furnace(instance_id, "iron_ingot")
	var after_start := inventory.snapshot()
	var duplicate := service.try_start_furnace(instance_id, "iron_ingot")
	service.advance(20.0, true)
	var paused_remaining := float(service.jobs[instance_id].remaining_seconds)
	service.advance(4.0, false)
	var before_finish := inventory.count("iron_ingot")
	service.advance(1.0, false)
	var once := inventory.count("iron_ingot")
	service.advance(10.0, false)
	var after_extra := inventory.count("iron_ingot")
	var busy_dismantle_inventory := F0Inventory.new(registry)
	var busy_service := WorkstationService.new(registry, busy_dismantle_inventory)
	busy_dismantle_inventory.try_transaction({}, {"furnace": 1, "iron_ore": 1, "coal": 1})
	var busy_placed := busy_service.try_place("furnace", Vector3i(2, 0, 0), query, AABB())
	var busy_id := str(busy_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	busy_service.try_start_furnace(busy_id, "iron_ingot")
	var busy_dismantle := busy_service.try_dismantle(busy_id, query, AABB())
	var passed: bool = bool(started.get("ok", false)) and after_start.get("reservations", {}).size() == 1 and inventory.count("iron_ore") == 0 and inventory.count("coal") == 0 and duplicate.get("reason") == "STATION_BUSY" and is_equal_approx(paused_remaining, 5.0) and before_finish == 0 and once == 1 and after_extra == 1 and busy_dismantle.get("reason") == "STATION_BUSY"
	_record("T22_FURNACE", passed, "inputs/fuel consumed once; output reserved; pause freezes; completion occurs once; busy dismantle refused", {"started": started, "duplicate": duplicate, "paused_remaining": paused_remaining, "once": once, "after_extra": after_extra, "busy_dismantle": busy_dismantle})


func _select_item(item_id: String) -> void:
	for index in range(F0Inventory.HOTBAR_COUNT):
		if str(app.session.inventory.slots[index].item_id) == item_id:
			app.session.inventory.select_hotbar(index)
			return
	failures.append("Hotbar item not found: " + item_id)


func _wait_cells(cells: Array[Vector3i]) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		var all_loaded := true
		for cell in cells:
			if app.session.world.query_cell(cell).get("state") != "LOADED":
				all_loaded = false
				break
		if all_loaded:
			return
		await get_tree().process_frame
	failures.append("F2 resource cells did not load")


func _total_items(inventory: F0Inventory) -> int:
	var total := 0
	for slot in inventory.slots:
		total += int(slot.count)
	return total


func _require_ok(result: Dictionary, label: String) -> void:
	if not result.get("ok", false):
		failures.append(label + ": " + str(result))


func _record(test_id: String, passed: bool, expected: String, evidence: Variant) -> void:
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if passed else "FAIL", expected, JSON.stringify(evidence)])
	if not passed:
		failures.append(test_id)
