class_name CastleKitAutomation
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
		"inventory":
			await _run_inventory(false, Vector2i.ZERO)
		"inventory_visual":
			await _run_inventory(true, Vector2i(1280, 720))
		"inventory_ultrawide":
			await _run_inventory(true, Vector2i(1720, 720))
		_:
			failures.append("unknown mode " + mode)
	if failures.is_empty():
		print("CASTLE_KIT_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("CASTLE_KIT_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	_test_content_contract()
	_test_footprints_and_rotation()
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var cells: Array[Vector3i] = []
	for z in range(36, 42):
		for x in range(-6, 7):
			cells.append(Vector3i(x, 0, z))
	if not await _wait_cells(cells):
		return
	app.session.player.deactivate()
	app.session.inventory.try_transaction({}, {
		"stone_stair": 1,
		"wall_walk_slab": 1,
		"parapet_merlon": 1,
		"tower_platform": 1,
		"gate_frame": 1,
	})
	for support in [
		Vector3i(-6, 0, 38), Vector3i(-5, 0, 38), Vector3i(-4, 0, 38), Vector3i(-3, 0, 38), Vector3i(-1, 0, 38),
		Vector3i(1, 0, 38), Vector3i(0, 0, 38), Vector3i(1, 0, 37), Vector3i(0, 0, 37),
		Vector3i(5, 0, 36), Vector3i(5, 0, 38),
	]:
		app.session.world.set_cell(support, 8)
	var stair := app.session.interaction.try_place_item(Vector3i(-5, 1, 38), "stone_stair", -1, 1)
	var slab := app.session.interaction.try_place_item(Vector3i(-3, 1, 38), "wall_walk_slab", -1, 0)
	var merlon := app.session.interaction.try_place_item(Vector3i(-1, 1, 38), "parapet_merlon", -1, 0)
	var platform := app.session.interaction.try_place_item(Vector3i(1, 1, 38), "tower_platform", -1, 2)
	var gate := app.session.interaction.try_place_item(Vector3i(5, 1, 36), "gate_frame", -1, 1)
	var placed_all := [stair, slab, merlon, platform, gate].all(func(result: Dictionary) -> bool: return result.get("ok", false))
	var platform_record: Dictionary = platform.get("changes", {}).get("station", {})
	var gate_record: Dictionary = gate.get("changes", {}).get("station", {})
	_record("T44_CASTLE_PLACEMENT", placed_all and int(platform_record.get("rotation_quarters", -1)) == 2 and int(gate_record.get("rotation_quarters", -1)) == 1 and app.session.workstations.stations.size() == 5, "five castle kit pieces place atomically with their requested orientation", {"stair": stair, "slab": slab, "merlon": merlon, "platform": platform, "gate": gate})
	await _test_stair_walk(str(stair.get("changes", {}).get("station", {}).get("instance_id", "")))
	var saved := await app.saves.save_session(app.session)
	_record("T45_CASTLE_SAVE", saved.get("ok", false), "oriented castle entities and inventory publish in the coherent checkpoint", saved)


func _run_phase2() -> void:
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	var records: Dictionary = app.session.workstations.stations
	var types: Array[String] = []
	var rotations: Dictionary = {}
	for record: Dictionary in records.values():
		var entity_id := str(record.get("entity_id", ""))
		types.append(entity_id)
		rotations[entity_id] = int(record.get("rotation_quarters", -1))
	types.sort()
	var expected := ["gate_frame", "parapet_merlon", "stone_stair", "tower_platform", "wall_walk_slab"]
	var restored := types == expected and int(rotations.get("stone_stair", -1)) == 1 and int(rotations.get("tower_platform", -1)) == 2 and int(rotations.get("gate_frame", -1)) == 1 and app.session._station_visuals.size() == 5
	_record("T45_CASTLE_CONTINUE", restored, "Continue restores every castle piece once with orientation and collision visuals", {"types": types, "rotations": rotations, "visuals": app.session._station_visuals.size()})
	var gate_id := ""
	for instance_id: String in records:
		if str(records[instance_id].get("entity_id", "")) == "gate_frame":
			gate_id = instance_id
			break
	var before := app.session.inventory.count("gate_frame")
	var dismantled := app.session.interaction.try_dismantle_station(gate_id)
	_record("T45_CASTLE_DISMANTLE", dismantled.get("ok", false) and app.session.inventory.count("gate_frame") == before + 1 and app.session.workstations.stations.size() == 4, "dismantling a multi-cell frame releases its whole footprint and refunds exactly one item", dismantled)


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.apply_world_settings("0830", false)
	app.session.player.deactivate()
	app.session.player.position = Vector3(0.5, 3.0, 44.5)
	app.session.player.rotation.y = 0.0
	var cells: Array[Vector3i] = []
	for z in range(36, 42):
		for x in range(-8, 9):
			cells.append(Vector3i(x, 0, z))
	if not await _wait_cells(cells):
		return
	app.session.inventory.try_transaction({}, {"stone_stair": 2, "wall_walk_slab": 2, "parapet_merlon": 4, "tower_platform": 1, "gate_frame": 1})
	for support in [Vector3i(-7, 0, 38), Vector3i(-5, 0, 38), Vector3i(-3, 0, 38), Vector3i(-1, 0, 38), Vector3i(0, 0, 38), Vector3i(-1, 0, 39), Vector3i(0, 0, 39), Vector3i(3, 0, 38), Vector3i(5, 0, 38)]:
		app.session.world.set_cell(support, 8)
	app.session.interaction.try_place_item(Vector3i(-7, 1, 38), "stone_stair", -1, 0)
	app.session.interaction.try_place_item(Vector3i(-5, 1, 38), "wall_walk_slab", -1, 0)
	app.session.interaction.try_place_item(Vector3i(-3, 1, 38), "parapet_merlon", -1, 0)
	app.session.interaction.try_place_item(Vector3i(-1, 1, 38), "tower_platform", -1, 0)
	app.session.interaction.try_place_item(Vector3i(3, 1, 38), "gate_frame", -1, 0)
	for _frame in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("p1-castle-kit.png")
	var error := image.save_png(path)
	_record("T46_CASTLE_VISUAL", error == OK and not image.is_empty() and image.get_size() == Vector2i(1280, 720), "rendered evidence shows the first structural castle kit at 1280×720", {"path": path, "size": image.get_size(), "error": error})


func _run_inventory(capture_visual: bool, expected_size: Vector2i) -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	if capture_visual and expected_size != Vector2i.ZERO:
		get_window().content_scale_size = expected_size
		get_window().size = expected_size
		for _resize_frame in range(3):
			await get_tree().process_frame
	app.session.inventory.try_transaction({}, {"dirt": 12, "log": 5, "planks": 8, "stone_stair": 2, "parapet_merlon": 3})
	app.session.inventory.swap_slots(0, 12)
	app.session.inventory.swap_slots(3, 10)
	app.session.inventory.try_transaction({}, {"workbench": 1, "iron_pick": 1})
	app.session.inventory.swap_slots(0, 15)
	app.session.inventory.swap_slots(3, 9)
	app.session.inventory.try_transaction({}, {"coal": 6, "stone": 9})
	app._show_inventory()
	for _frame in range(4):
		await get_tree().process_frame
	var section_counts_ok := app.inventory_carried_grid.get_child_count() == F0Inventory.SLOT_COUNT - F0Inventory.HOTBAR_COUNT \
		and app.inventory_hotbar_grid.get_child_count() == F0Inventory.HOTBAR_COUNT \
		and app.inventory_armor_slot_buttons.size() == 6
	var mapping_ok := app.inventory_slot_buttons[0].get_parent() == app.inventory_hotbar_grid \
		and app.inventory_slot_buttons[8].get_parent() == app.inventory_hotbar_grid \
		and app.inventory_slot_buttons[9].get_parent() == app.inventory_carried_grid \
		and app.inventory_slot_buttons[26].get_parent() == app.inventory_carried_grid
	var armor_truthful := app.inventory_armor_slot_buttons.all(func(button: Button) -> bool: return button.disabled and button.text.ends_with("Empty"))
	var heights_align := absf(app.inventory_left_column.size.y - app.inventory_armor_card.size.y) <= 2.0
	_record("T47_INVENTORY_LAYOUT", app.state == app.AppState.INVENTORY and section_counts_ok and mapping_ok and armor_truthful and heights_align, "Tab separates 18 carried slots, one 1–9 hotbar row and a truthful six-position full-height armor loadout", {"carried": app.inventory_carried_grid.get_child_count(), "hotbar": app.inventory_hotbar_grid.get_child_count(), "armor": app.inventory_armor_slot_buttons.size(), "left_height": app.inventory_left_column.size.y, "armor_height": app.inventory_armor_card.size.y})
	var drag_source_item := str(app.session.inventory.slots[12].item_id)
	var drag_target_before := app.session.inventory.slots[8].duplicate(true)
	var drag_payload := {"kind": "inventory_slot", "source_index": 12, "item_id": drag_source_item}
	var drag_accepted: bool = app.inventory_slot_buttons[8]._can_drop_data(Vector2.ZERO, drag_payload)
	app.inventory_slot_buttons[8]._drop_data(Vector2.ZERO, drag_payload)
	var drag_moved: bool = str(app.session.inventory.slots[8].item_id) == drag_source_item and app.session.inventory.slots[12] == drag_target_before
	app.inventory_slot_buttons[12]._drop_data(Vector2.ZERO, {"kind": "inventory_slot", "source_index": 8, "item_id": drag_source_item})
	app._set_inventory_filter("resource")
	var visible_resource_slots := 0
	for index in range(F0Inventory.HOTBAR_COUNT, app.inventory_slot_buttons.size()):
		if app.inventory_slot_buttons[index].visible:
			visible_resource_slots += 1
	var filter_ok: bool = visible_resource_slots == 1 and app.inventory_filter_buttons["resource"].button_pressed and not app.inventory_filter_empty_label.visible
	app._set_inventory_filter("food")
	var empty_filter_ok: bool = app.inventory_filter_empty_label.visible and app.inventory_filter_buttons["food"].button_pressed
	app._set_inventory_filter("all")
	var hotbar_before := app.session.inventory.slots.slice(0, F0Inventory.HOTBAR_COUNT).duplicate(true)
	var revision_before := app.session.inventory.revision
	app._sort_carried_inventory()
	var category_order: Array[String] = []
	for index in range(F0Inventory.HOTBAR_COUNT, F0Inventory.SLOT_COUNT):
		var carried_item_id := str(app.session.inventory.slots[index].item_id)
		if not carried_item_id.is_empty():
			category_order.append(app.session.registry.item_category(carried_item_id))
	var expected_order: Array[String] = ["resource", "building", "tool", "station"]
	var sort_ok: bool = hotbar_before == app.session.inventory.slots.slice(0, F0Inventory.HOTBAR_COUNT) and category_order == expected_order and app.session.inventory.revision == revision_before + 1
	var sorted_snapshot := app.session.inventory.snapshot()
	var restored_inventory := F0Inventory.new(app.session.registry)
	var restore_ok: bool = restored_inventory.restore(sorted_snapshot) and restored_inventory.snapshot() == sorted_snapshot
	_record("T49_INVENTORY_ORGANIZATION", drag_accepted and drag_moved and filter_ok and empty_filter_ok and sort_ok and restore_ok, "drag/drop swaps exact slots; carried filters are presentation-only; type sort preserves the hotbar and round-trips through the inventory snapshot", {"drag": drag_moved, "visible_resources": visible_resource_slots, "empty_food": empty_filter_ok, "categories": category_order, "hotbar_unchanged": hotbar_before == app.session.inventory.slots.slice(0, F0Inventory.HOTBAR_COUNT), "revision": app.session.inventory.revision, "restored": restore_ok})
	if not capture_visual:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("p1-inventory-loadout-%dx%d.png" % [expected_size.x, expected_size.y])
	var error := image.save_png(path)
	_record("T48_INVENTORY_VISUAL", error == OK and not image.is_empty() and image.get_size() == expected_size, "rendered evidence shows all three inventory sections at the requested Windows viewport without clipping", {"path": path, "size": image.get_size(), "expected": expected_size, "error": error})


func _test_content_contract() -> void:
	var registry := ContentRegistry.new()
	var expected := ["gate_frame", "parapet_merlon", "stone_stair", "tower_platform", "wall_walk_slab"]
	var recipe_ids: Array[String] = []
	for recipe in registry.recipes_for("workbench"):
		recipe_ids.append(str(recipe.id))
	var all_defined := expected.all(func(item_id: String) -> bool: return not registry.item(item_id).is_empty() and not registry.entity(item_id).is_empty() and item_id in recipe_ids)
	var platform := registry.entity("tower_platform")
	var socket: Dictionary = platform.get("mount_sockets", [{}])[0]
	_record("T42_CASTLE_CONTENT", all_defined and str(socket.get("id", "")) == "center_mount" and str(socket.get("type", "")) == "light_siege", "the workbench exposes stable castle kit IDs and the tower platform reserves a typed future defense socket", {"recipes": recipe_ids, "socket": socket})


func _test_footprints_and_rotation() -> void:
	var registry := ContentRegistry.new()
	var inventory := F0Inventory.new(registry)
	var service := WorkstationService.new(registry, inventory)
	var supported_query := func(cell: Vector3i) -> Dictionary: return {"state": "LOADED", "voxel_id": 8 if cell.y == -1 else 0}
	var empty_query := func(_cell: Vector3i) -> Dictionary: return {"state": "LOADED", "voxel_id": 0}
	var before_reservations := service.footprints.reservation_count()
	var preview := service.preview_placement("tower_platform", Vector3i.ZERO, 1, supported_query, AABB())
	var after_reservations := service.footprints.reservation_count()
	var unsupported := service.preview_placement("tower_platform", Vector3i.ZERO, 0, empty_query, AABB())
	inventory.try_transaction({}, {"tower_platform": 1})
	var placed := service.try_place("tower_platform", Vector3i.ZERO, supported_query, AABB(), 1)
	var cells: Array = service.footprints._instances.get("tower_platform_0001", {}).get("cells", [])
	var rotated_cells := [Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(-1, 0, 1)]
	var rotation_ok := rotated_cells.all(func(cell: Vector3i) -> bool: return cell in cells)
	_record("T43_CASTLE_FOOTPRINT", preview.get("ok", false) and before_reservations == after_reservations and unsupported.get("reason") == "UNSUPPORTED" and placed.get("ok", false) and rotation_ok, "preview is non-mutating; all support cells are required; 90-degree placement rotates the full footprint atomically", {"preview": preview, "unsupported": unsupported, "placed": placed, "cells": cells})


func _test_stair_walk(instance_id: String) -> void:
	if instance_id.is_empty() or not app.session._station_visuals.has(instance_id):
		_record("T50_STAIR_WALK", false, "two half-block steps climb under ordinary forward movement without Jump", {"reason": "missing stair visual", "instance_id": instance_id})
		return
	var stair_body: StaticBody3D = app.session._station_visuals[instance_id]
	var ascent := (stair_body.global_basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var player := app.session.player
	for _frame in range(30):
		await get_tree().physics_frame
	player.deactivate()
	player.global_position = stair_body.global_position - ascent * 1.0
	player.global_position.y = stair_body.global_position.y - 0.48
	player.look_at(player.global_position + ascent, Vector3.UP)
	Input.action_release("jump")
	player.activate(false)
	var settle_frames := 0
	while not player.is_on_floor() and settle_frames < 90:
		await get_tree().physics_frame
		settle_frames += 1
	var start := player.global_position
	var max_height := start.y
	Input.action_press("move_forward")
	for _frame in range(36):
		await get_tree().physics_frame
		max_height = maxf(max_height, player.global_position.y)
	Input.action_release("move_forward")
	player.deactivate()
	var forward_distance := (player.global_position - start).dot(ascent)
	var climbed_height := max_height - start.y
	_record("T50_STAIR_WALK", settle_frames < 90 and climbed_height >= 0.85 and forward_distance >= 1.25, "two half-block steps climb under ordinary forward movement without Jump", {"start": start, "finish": player.global_position, "climbed_height": climbed_height, "forward_distance": forward_distance, "settle_frames": settle_frames, "step_height": PlayerController.MAX_STEP_HEIGHT})
	for cell in [Vector3i(4, 0, 38), Vector3i(4, 0, 39), Vector3i(4, 0, 40), Vector3i(4, 1, 40)]:
		app.session.world.set_cell(cell, 8)
	for _frame in range(24):
		await get_tree().physics_frame
	player.global_position = Vector3(4.5, 1.02, 39.0)
	player.look_at(player.global_position + Vector3(0.0, 0.0, 1.0), Vector3.UP)
	player.activate(false)
	for _frame in range(8):
		await get_tree().physics_frame
	var barrier_start := player.global_position
	var barrier_max_height := barrier_start.y
	Input.action_press("move_forward")
	for _frame in range(36):
		await get_tree().physics_frame
		barrier_max_height = maxf(barrier_max_height, player.global_position.y)
	Input.action_release("move_forward")
	player.deactivate()
	var barrier_distance := player.global_position.z - barrier_start.z
	var barrier_climb := barrier_max_height - barrier_start.y
	_record("T50_FULL_BLOCK_BARRIER", barrier_climb < 0.3 and barrier_distance < 1.0, "the stair helper remains capped below one full block", {"start": barrier_start, "finish": player.global_position, "climbed_height": barrier_climb, "forward_distance": barrier_distance, "step_height": PlayerController.MAX_STEP_HEIGHT})


func _wait_ready() -> bool:
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 30000:
		await get_tree().process_frame
	if app.state != app.AppState.PLAYING:
		failures.append("session ready timeout: " + app.status_label.text)
		return false
	return true


func _wait_cells(cells: Array[Vector3i]) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000:
		var loaded := true
		for cell in cells:
			if app.session.world.query_cell(cell).get("state") != "LOADED":
				loaded = false
				break
		if loaded:
			return true
		await get_tree().process_frame
	failures.append("castle kit test cells did not load")
	return false


func _record(test_id: String, passed: bool, expected: String, evidence: Variant) -> void:
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if passed else "FAIL", expected, JSON.stringify(evidence)])
	if not passed:
		failures.append(test_id)
