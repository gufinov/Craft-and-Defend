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
		Vector3i(-5, 0, 38), Vector3i(-3, 0, 38), Vector3i(-1, 0, 38),
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
