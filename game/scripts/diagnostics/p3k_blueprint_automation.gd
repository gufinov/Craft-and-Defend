class_name P3KBlueprintAutomation
extends Node

## P3K blueprints: stamped castle pieces made of ordinary blocks.
## gate   — catalogue, rotation, stacking through sockets, trimming, blocking, cancel.
## visual — renders a stamped foundation + segment + cap tower and a cap ghost.

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
	_write_json(app.data_root.path_join("p3k_blueprint_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3K_BLUEPRINT_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3K_BLUEPRINT_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var interaction := app.session.interaction
	var inventory := app.session.inventory

	# T110: catalogue integrity as the runtime sees it.
	var catalogue := InteractionService.blueprints()
	var expected_ids := ["foundation_4", "tower_segment_4", "cap_4", "cap_6", "cap_8", "wall_4", "wall_kit_8"]
	var ids_ok := true
	for id in expected_ids:
		ids_ok = ids_ok and catalogue.has(id)
	var resolved_ok := true
	var total_cells := 0
	for id in catalogue.keys():
		var cells := interaction.blueprint_cells(str(id), Vector3i.ZERO, 0)
		var definition: Dictionary = catalogue[id]
		# Defence sets: a kit blueprint resolves its entity cells alongside
		# its blocks, so the plan is blocks + pieces.
		resolved_ok = resolved_ok and cells.size() == definition.get("blocks", []).size() + definition.get("entities", []).size()
		total_cells += cells.size()
	var rotated := interaction.blueprint_cells("wall_4", Vector3i.ZERO, 1)
	var rotated_along_z := true
	for entry in rotated:
		var cell: Vector3i = entry.cell
		rotated_along_z = rotated_along_z and cell.x == 0 and cell.z >= 0 and cell.z < 4
	var rotation_ok := rotated.size() == 12 and rotated_along_z
	_record("T110_BLUEPRINT_CATALOGUE", ids_ok and resolved_ok and rotation_ok, "the runtime catalogue exposes every generated blueprint, every block resolves to a placeable item, and a quarter turn rotates a wall from x onto z", {"ids": catalogue.keys(), "total_cells": total_cells, "rotation_ok": rotation_ok})

	# T111: stack foundation → segment → cap through top sockets; each stamp is
	# one world edit plus one inventory transaction across two block types.
	var base := Vector3i(14, 0, 44)
	if not await _wait_area(base, 4, 4, 7):
		return
	_level_area(base, 4, 4, 7)
	_clear_inventory()
	inventory.try_transaction({}, {"castle_stone": 64, "planks": 16, "stone": 8})
	inventory.try_transaction({}, {"castle_stone": 64})
	var foundation_begin := interaction.begin_blueprint_at("foundation_4", base, 0)
	var foundation_plan := interaction.drag_state()
	var foundation_commit := interaction.commit_drag_place()
	var foundation_ok: bool = foundation_begin.get("ok", false) and int(foundation_plan.get("affordable", 0)) == 16 \
		and foundation_commit.get("ok", false) and str(foundation_commit.get("reason", "")) == "BLUEPRINT_STAMPED" \
		and int(foundation_commit.get("changes", {}).get("count", 0)) == 16 and inventory.count("castle_stone") == 112 \
		and int(app.session.world.query_cell(base + Vector3i(3, 0, 3)).get("voxel_id", 0)) == 8
	var top_socket := _socket_offset("foundation_4", "top")
	interaction.begin_blueprint_at("tower_segment_4", base + top_socket, 0)
	var segment_plan := interaction.drag_state()
	var segment_commit := interaction.commit_drag_place()
	var segment_costs: Dictionary = segment_plan.get("costs", {})
	var segment_ok: bool = int(segment_costs.get("castle_stone", 0)) == 36 and int(segment_costs.get("stone", 0)) == 3 \
		and segment_commit.get("ok", false) and int(segment_commit.get("changes", {}).get("count", 0)) == 39 \
		and inventory.count("castle_stone") == 76 and inventory.count("stone") == 5 \
		and int(app.session.world.query_cell(base + Vector3i(0, 3, 0)).get("voxel_id", 0)) == 8 \
		and int(app.session.world.query_cell(base + Vector3i(1, 2, 1)).get("voxel_id", 0)) == 0 \
		and int(app.session.world.query_cell(base + Vector3i(1, 1, 1)).get("voxel_id", 0)) == 3 \
		and int(app.session.world.query_cell(base + Vector3i(2, 2, 1)).get("voxel_id", 0)) == 3
	var segment_top := _socket_offset("tower_segment_4", "top")
	interaction.begin_blueprint_at("cap_4", base + top_socket + segment_top, 0)
	var cap_plan := interaction.drag_state()
	var cap_commit := interaction.commit_drag_place()
	var cap_costs: Dictionary = cap_plan.get("costs", {})
	var cap_ok: bool = int(cap_costs.get("castle_stone", 0)) == 20 and int(cap_costs.get("planks", 0)) == 4 \
		and cap_commit.get("ok", false) and int(cap_commit.get("changes", {}).get("count", 0)) == 24 \
		and inventory.count("castle_stone") == 56 and inventory.count("planks") == 12 \
		and int(app.session.world.query_cell(base + Vector3i(1, 4, 1)).get("voxel_id", 0)) == 5 \
		and int(app.session.world.query_cell(base + Vector3i(0, 5, 0)).get("voxel_id", 0)) == 8
	_record("T111_BLUEPRINT_TOWER_STACK", foundation_ok and segment_ok and cap_ok, "foundation, tower segment and cap stamp on top of each other through their top sockets, each as one world edit plus one inventory transaction across castle stone, stone and planks", {"foundation": foundation_commit.get("reason"), "segment": segment_commit.get("reason"), "segment_costs": segment_costs, "cap": cap_commit.get("reason"), "cap_costs": cap_costs, "castle_stone_left": inventory.count("castle_stone"), "planks_left": inventory.count("planks")})

	# T112: trimming, blocked cells and cancel. 8 planks short of a cap_8 floor;
	# one cell pre-blocked; cancel builds nothing.
	var far := Vector3i(-30, 0, 44)
	if not await _wait_area(far, 8, 8, 3):
		return
	_level_area(far, 8, 8, 3)
	_clear_inventory()
	inventory.try_transaction({}, {"castle_stone": 64, "planks": 28})
	app.session.world.set_cell(far + Vector3i(3, 0, 3), 3)
	interaction.begin_blueprint_at("cap_8", far, 0)
	var trimmed_plan := interaction.drag_state()
	var blocked := 0
	var unaffordable := 0
	for entry in trimmed_plan.get("cells", []):
		match str(entry.state):
			"blocked":
				blocked += 1
			"unaffordable":
				unaffordable += 1
	var trimmed_costs: Dictionary = trimmed_plan.get("costs", {})
	var revision_before: int = app.session.world.revision
	var cancelled := interaction.cancel_drag_place()
	var cancel_ok: bool = str(cancelled.get("reason", "")) == "DRAG_CANCELLED" and app.session.world.revision == revision_before and inventory.count("planks") == 28
	interaction.begin_blueprint_at("cap_8", far, 0)
	var trimmed_commit := interaction.commit_drag_place()
	var trimmed_ok: bool = blocked == 1 and unaffordable == 7 and int(trimmed_costs.get("planks", 0)) == 28 and int(trimmed_costs.get("castle_stone", 0)) == 44 \
		and trimmed_commit.get("ok", false) and int(trimmed_commit.get("changes", {}).get("count", 0)) == 72 \
		and inventory.count("planks") == 0 and inventory.count("castle_stone") == 20 \
		and int(app.session.world.query_cell(far + Vector3i(3, 0, 3)).get("voxel_id", 0)) == 3
	# T117: stamps are remembered, expose sockets, snap the next piece, and
	# round-trip through the session snapshot.
	var stamps_after := interaction.stamps_snapshot()
	var sockets := interaction.stamp_sockets()
	var top_of_segment := base + top_socket + segment_top
	var has_segment_top := false
	for socket in sockets:
		if str(socket.blueprint_id) == "tower_segment_4" and str(socket.socket_id) == "top" and Vector3i(socket.cell) == top_of_segment:
			has_segment_top = true
	var snap := interaction.snap_to_socket(top_of_segment + Vector3i(1, 0, 0), "cap_4")
	var no_snap := interaction.snap_to_socket(top_of_segment + Vector3i(5, 0, 5), "cap_4")
	var saved_session := app.session.snapshot()
	var restored_service := InteractionService.new(app.session.world, app.session.inventory, app.session.player.get_body_aabb, app.session.registry, app.session.workstations)
	var restore_ok := restored_service.restore_stamps(saved_session.get("blueprints", {}).get("stamps", null))
	var refused := restored_service.restore_stamps([{"blueprint_id": "not_a_piece", "anchor": [0, 0, 0]}])
	_record("T117_BLUEPRINT_SOCKET_SNAP", stamps_after.size() >= 4 and has_segment_top and bool(snap.snapped) and Vector3i(snap.cell) == top_of_segment and not bool(no_snap.snapped) and restore_ok and restored_service.stamps_snapshot().size() == stamps_after.size() and not refused, "stamped pieces are remembered with their sockets, a piece aimed within one cell of a socket snaps to it, an aim far away does not, and the stamp list round-trips through the session snapshot while an unknown piece is refused", {"stamps": stamps_after.size(), "sockets": sockets.size(), "snap": snap, "no_snap": no_snap.snapped, "restore_ok": restore_ok, "refused": refused, "has_segment_top": has_segment_top, "restored_count": restored_service.stamps_snapshot().size(), "top_of_segment": top_of_segment})

	await _run_wall_kit_test()

	_record("T112_BLUEPRINT_TRIM_BLOCK_CANCEL", trimmed_ok and cancel_ok, "a blueprint short on one block type trims only that type's cells, skips an occupied cell, cancels with nothing built, and otherwise stamps every affordable cell", {"blocked": blocked, "unaffordable": unaffordable, "costs": trimmed_costs, "commit": trimmed_commit.get("reason"), "cancel": cancelled.get("reason")})


## T227 (docs/DEFENSE_SETS.md): the wall kit. One stamp raises a finished
## defensive section - two courses of castle stone, a wall-walk, merlons and a
## stair up at each end - for the real items, refuses a site it does not fit,
## and comes back out with one U.
func _run_wall_kit_test() -> void:
	var interaction := app.session.interaction
	var inventory := app.session.inventory
	var ws := app.session.workstations
	var world := app.session.world
	var base := Vector3i(30, 0, 44)
	if not await _wait_area(base, 8, 2, 6):
		return
	_level_area(base, 8, 2, 6)
	_clear_inventory()

	# Short of everything: the plan is drawn but nothing is affordable.
	interaction.begin_blueprint_at("wall_kit_8", base, 0)
	var empty_plan := interaction.drag_state()
	var unaffordable := 0
	var empty_cells := 0
	var empty_buildable := 0
	for entry in empty_plan.get("cells", []):
		empty_cells += 1
		if str(entry.state) == "unaffordable":
			unaffordable += 1
		elif str(entry.state) == "ok":
			empty_buildable += 1
	interaction.cancel_drag_place()

	# A site it does not fit: a castle-stone pillar standing in the section.
	inventory.try_transaction({}, {"castle_stone": 16, "wall_walk_slab": 8, "parapet_merlon": 4, "stone_stair": 4})
	world.set_cell(base + Vector3i(3, 0, 0), 8)
	world.set_cell(base + Vector3i(3, 1, 0), 8)
	interaction.begin_blueprint_at("wall_kit_8", base, 0)
	var blocked_plan := interaction.drag_state()
	var blocked := 0
	for entry in blocked_plan.get("cells", []):
		if str(entry.state) == "blocked":
			blocked += 1
	interaction.cancel_drag_place()
	world.set_cell(base + Vector3i(3, 0, 0), 0)
	world.set_cell(base + Vector3i(3, 1, 0), 0)

	# The real stamp.
	var stations_before := ws.stations.size()
	var revision_before := world.revision
	interaction.begin_blueprint_at("wall_kit_8", base, 0)
	var plan := interaction.drag_state()
	var costs: Dictionary = plan.get("costs", {})
	var stamped := interaction.commit_drag_place()
	var changes: Dictionary = stamped.get("changes", {})
	var raised: Array = changes.get("entities", [])
	var course_ok := int(world.query_cell(base + Vector3i(4, 1, 0)).get("voxel_id", 0)) == 8
	var walk_id := ws.station_at_cell(base + Vector3i(4, 2, 0))
	var merlon_id := ws.station_at_cell(base + Vector3i(4, 3, 0))
	var stair_id := ws.station_at_cell(base + Vector3i(0, 1, 1))
	var walk_is_slab := str(ws.station(walk_id).get("entity_id", "")) == "wall_walk_slab"
	var merlon_is_merlon := str(ws.station(merlon_id).get("entity_id", "")) == "parapet_merlon"
	var stair_is_stair := str(ws.station(stair_id).get("entity_id", "")) == "stone_stair"
	var paid: bool = inventory.count("castle_stone") == 0 and inventory.count("wall_walk_slab") == 0 \
		and inventory.count("parapet_merlon") == 0 and inventory.count("stone_stair") == 0
	var stamps_after := interaction.stamps_snapshot().size()
	var stations_after_stamp := ws.stations.size()

	# One U takes the whole section back out and hands the items back.
	var undone := interaction.undo_last()
	var world_restored := int(world.query_cell(base + Vector3i(4, 1, 0)).get("voxel_id", -1)) == 0
	var stations_restored := ws.stations.size() == stations_before
	var refunded: bool = inventory.count("castle_stone") == 16 and inventory.count("wall_walk_slab") == 8 \
		and inventory.count("parapet_merlon") == 4 and inventory.count("stone_stair") == 4
	var stamp_forgotten := interaction.stamps_snapshot().size() == stamps_after - 1
	_clear_inventory()

	_record("T227_WALL_KIT", empty_cells == 32 and unaffordable > 0 and empty_buildable == 0 and blocked >= 2
			and int(costs.get("castle_stone", 0)) == 16 and int(costs.get("wall_walk_slab", 0)) == 8
			and int(costs.get("parapet_merlon", 0)) == 4 and int(costs.get("stone_stair", 0)) == 4
			and stamped.get("ok", false) and str(stamped.get("reason", "")) == "BLUEPRINT_STAMPED"
			and raised.size() == 16 and stations_after_stamp == stations_before + 16
			and world.revision > revision_before and course_ok
			and walk_is_slab and merlon_is_merlon and stair_is_stair and paid
			and undone.get("ok", false) and world_restored and stations_restored and refunded and stamp_forgotten,
		"one Wall Kit stamp raises a finished defensive section - sixteen castle stone in two courses, an eight-cell wall-walk, four merlons and a pair of stone stairs up at each end - paid for with the real items in one transaction; an empty pack builds none of its thirty-two cells and a pillar standing in the section blocks its cells; and one U takes the section back out, blocks and pieces together, and hands every item back",
		{"empty_cells": empty_cells, "unaffordable": unaffordable, "empty_buildable": empty_buildable, "blocked": blocked, "costs": costs, "stamped": stamped.get("reason"), "entities": raised.size(), "stations_added": stations_after_stamp - stations_before, "course": course_ok, "walk": walk_is_slab, "merlon": merlon_is_merlon, "stair": stair_is_stair, "paid": paid, "undone": undone.get("reason"), "world_restored": world_restored, "stations_restored": stations_restored, "refunded": refunded, "stamp_forgotten": stamp_forgotten})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var interaction := app.session.interaction
	var inventory := app.session.inventory
	var base := Vector3i(6, 0, 44)
	if not await _wait_area(base, 12, 8, 7):
		return
	_level_area(base, 12, 8, 7)
	_clear_inventory()
	inventory.try_transaction({}, {"castle_stone": 64, "planks": 16, "stone": 8})
	inventory.try_transaction({}, {"castle_stone": 64})
	interaction.begin_blueprint_at("foundation_4", base, 0)
	interaction.commit_drag_place()
	interaction.begin_blueprint_at("tower_segment_4", base + _socket_offset("foundation_4", "top"), 0)
	interaction.commit_drag_place()
	interaction.begin_blueprint_at("cap_4", base + _socket_offset("foundation_4", "top") + _socket_offset("tower_segment_4", "top"), 0)
	interaction.commit_drag_place()
	app.session.player.deactivate()
	app.session.simulation_paused = false
	app.session.player.global_position = Vector3(1.5, 1.0, 36.0)
	app.session.player.look_at(Vector3(8.0, 2.5, 46.0), Vector3.UP)
	await _settle_frames(40)
	var tower_path := app.data_root.path_join("p3k-stamped-tower.png")
	var tower_ok := await _save_viewport(tower_path)
	# Ghost of a cap_6 beside the tower, following the aim.
	inventory.try_transaction({}, {"castle_stone": 64, "planks": 16})
	interaction.begin_blueprint_at("cap_6", base + Vector3i(6, 0, 0), 0)
	app.session._placement_preview_key = ""
	var ghost_seen := await _wait_for_ghost("DragPreview", 10)
	await _settle_frames(4)
	var ghost_path := app.data_root.path_join("p3k-blueprint-ghost.png")
	var ghost_ok := await _save_viewport(ghost_path)
	interaction.cancel_drag_place()
	_record("T113_BLUEPRINT_PRESENTATION", tower_ok and ghost_ok and ghost_seen, "rendered evidence shows a stamped foundation, segment and cap tower made of ordinary blocks, and a multi-block blueprint ghost", {"tower_path": tower_path, "ghost_path": ghost_path, "ghost_seen": ghost_seen})


func _socket_offset(blueprint_id: String, socket_id: String) -> Vector3i:
	for socket in InteractionService.blueprint(blueprint_id).get("sockets", []):
		if str(socket.get("id", "")) == socket_id:
			var values: Array = socket.get("offset", [0, 0, 0])
			return Vector3i(int(values[0]), int(values[1]), int(values[2]))
	return Vector3i.ZERO


## Test fixture: solid stone at y = -1 and air above over the footprint, so the
## stamp result depends on the blueprint rules rather than the seeded terrain.
func _level_area(base: Vector3i, width: int, depth: int, height: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(base + Vector3i(x, -1, z), 3)
			for y in range(height):
				app.session.world.set_cell(base + Vector3i(x, y, z), 0)


func _clear_inventory() -> void:
	var removals: Dictionary = {}
	for slot in app.session.inventory.slots:
		var item_id := str(slot.get("item_id", ""))
		if not item_id.is_empty():
			removals[item_id] = int(removals.get(item_id, 0)) + int(slot.get("count", 0))
	if not removals.is_empty():
		app.session.inventory.try_transaction(removals, {})


func _wait_for_ghost(ghost_name: String, minimum_cells: int = 1) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var ghost := app.session._placement_preview
		if ghost != null and str(ghost.name) == ghost_name and ghost.get_child_count() >= minimum_cells:
			return true
		await get_tree().process_frame
	return false


## Waits for every cell `_level_area` is about to write, not a handful of
## corners. `_level_area` writes a floor course at **y = -1** as well as the
## clear volume above it, and y = -1 is the top cell of the data block *below*
## the one the site stands in - a different block, which streams in on its own
## schedule. Waiting only for cells at y >= 0 let the floor writes be issued
## against an unloaded block, where `set_cell` silently does nothing: the
## levelled site came out one course short, a blueprint cell that should read
## `unaffordable` read as something else and the stamp answered
## `PLACEMENT_FAILED`. That made `T227_WALL_KIT` fail about two runs in five,
## at this head and at the wave-4 head alike. Probing the whole box, floor
## course included, is the same rule the Expo builder now follows.
func _wait_area(base: Vector3i, width: int, depth: int, height: int) -> bool:
	var cells: Array[Vector3i] = []
	for x in range(width):
		for z in range(depth):
			for y in range(-1, height):
				cells.append(base + Vector3i(x, y, z))
	return await _wait_cells(cells)


func _wait_cells(cells: Array[Vector3i]) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var loaded := true
		for cell in cells:
			if app.session.world.query_cell(cell).get("state") != "LOADED":
				loaded = false
				break
		if loaded:
			return true
		await get_tree().process_frame
	failures.append("required cells did not load")
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
