class_name P3DUsabilityAutomation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_phase1()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p3d_usability_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3D_USABILITY_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3D_USABILITY_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var registry := app.session.registry

	var batch_inventory := F0Inventory.new(registry)
	batch_inventory.try_transaction({}, {"log": 5})
	var batch_start_revision := batch_inventory.revision
	var batch_crafting := CraftingService.new(registry, batch_inventory)
	var crafted := batch_crafting.try_craft_many("planks", "hand", 5)
	var exact_five: bool = crafted.get("ok", false) and batch_inventory.count("log") == 0 and batch_inventory.count("planks") == 20 and batch_inventory.revision == batch_start_revision + 1

	var reject_inventory := F0Inventory.new(registry)
	reject_inventory.try_transaction({}, {"log": 4})
	var reject_before := reject_inventory.snapshot()
	var reject_crafting := CraftingService.new(registry, reject_inventory)
	var rejected := reject_crafting.try_craft_many("planks", "hand", 5)
	var atomic_reject: bool = not rejected.get("ok", false) and rejected.get("reason") == "INSUFFICIENT_INPUT" and reject_inventory.snapshot() == reject_before
	var tooltip_ok := app.craft_selected_button.tooltip_text.contains("five batches")
	_record("T79_SHIFT_CRAFT", exact_five and atomic_reject and tooltip_ok, "Shift+Click crafts exactly five recipe batches in one atomic inventory transaction and insufficient materials change nothing", {"crafted": crafted, "logs": batch_inventory.count("log"), "planks": batch_inventory.count("planks"), "revision_delta": batch_inventory.revision - batch_start_revision, "rejected": rejected, "atomic_reject": atomic_reject, "tooltip_ok": tooltip_ok})

	app.session.inventory.try_transaction({}, {"wood_axe": 1, "wood_pick": 1, "iron_sword": 1, "dirt": 1})
	var axe_slot := _move_to_hotbar("wood_axe", 0)
	app.session.inventory.select_hotbar(axe_slot)
	await get_tree().process_frame
	var held := app.session._held_item_view
	var axe_parts := held.model_root.get_child_count()
	var axe_hinge: Vector3 = held.debug_presentation().hinge_position
	var dirt_slot := _move_to_hotbar("dirt", 1)
	app.session.inventory.select_hotbar(dirt_slot)
	await get_tree().process_frame
	var dirt_parts := held.model_root.get_child_count()
	var block_hinge: Vector3 = held.debug_presentation().hinge_position
	var held_ok := held.current_item_id == "dirt" and axe_parts >= 1 and held.model_root.get_child_count() == 1 and dirt_parts == 1 and is_equal_approx(block_hinge.x, axe_hinge.x) and block_hinge.y > axe_hinge.y and ItemIconCatalog.world_reference_texture_for("wood_axe") != null
	_record("T80_HELD_ITEMS", held_ok, "the active hotbar item owns one persistent lower-right first-person hand column; tools hinge at the screen base and placeables sit above the hotbar", {"axe_parts": axe_parts, "axe_hinge": axe_hinge, "block_parts": dirt_parts, "block_hinge": block_hinge, "current": held.current_item_id})

	app.session.inventory.select_hotbar(axe_slot)
	var tree_cells: Array[Vector3i] = [Vector3i(4, 0, 40), Vector3i(4, 1, 40), Vector3i(4, 2, 40), Vector3i(4, 3, 40)]
	if not await _wait_cells(tree_cells):
		return
	var logs_before := app.session.inventory.count("log")
	var felled := app.session.interaction.try_break_cell(tree_cells[0])
	var targeted_removed := int(app.session.world.query_cell(tree_cells[0]).get("voxel_id", -1)) == InteractionService.AIR
	var upper_trunk_retained := true
	for cell in tree_cells.slice(1):
		upper_trunk_retained = upper_trunk_retained and int(app.session.world.query_cell(cell).get("voxel_id", -1)) == 4
	var axe_ok: bool = felled.get("ok", false) and felled.get("reason") == "OK" and felled.get("changes", {}).get("cells", []).size() == 1 and app.session.inventory.count("log") == logs_before + 1 and targeted_removed and upper_trunk_retained
	_record("T81_WOOD_AXE", axe_ok, "one Wood Axe swing removes and gathers only the targeted log block; the remaining trunk stays in place", {"result": felled, "logs_before": logs_before, "logs_after": app.session.inventory.count("log"), "targeted_removed": targeted_removed, "upper_trunk_retained": upper_trunk_retained})

	var preview := app.session.interaction.preview_place_item(Vector3i(5, 0, 40), "dirt", 0)
	var marker_label := _find_label(app.session._resource_markers)
	var iron_cell := app.session.world.query_cell(Vector3i(-8, -4, 35))
	var feedback_ok: bool = preview.get("ok", false) and preview.get("kind") == "block" and int(preview.get("voxel_id", 0)) == InteractionService.DIRT and marker_label != null and marker_label.text.contains("DIG 2 BLOCKS") and int(iron_cell.get("voxel_id", 0)) == P1TerrainGenerator.IRON_ORE
	_record("T82_WORLD_FEEDBACK", feedback_ok, "block placement exposes the same non-mutating validation used by placement and the visible marker points to the real guaranteed iron vein", {"preview": preview, "marker": marker_label.text if marker_label != null else "", "iron_cell": iron_cell})

	# P3J drag building. Ground is at y = -1 here; y = 0 is the first air layer.
	var drag_cells: Array[Vector3i] = [Vector3i(-2, 0, 44), Vector3i(-14, 0, 44), Vector3i(-2, 4, 44), Vector3i(-14, 4, 44)]
	if not await _wait_cells(drag_cells):
		return
	var interaction := app.session.interaction
	var inventory := app.session.inventory
	var dirt_before := inventory.count("dirt")
	if dirt_before > 0:
		inventory.try_transaction({"dirt": dirt_before}, {})
	inventory.try_transaction({}, {"dirt": 30})
	var drag_dirt_slot := _move_to_hotbar("dirt", 2)
	inventory.select_hotbar(drag_dirt_slot)
	app.session.player.global_position = Vector3(-8.5, 1.0, 50.0)
	# Row of 6 along x.
	var row_begin := interaction.begin_drag_at(Vector3i(-2, 0, 44))
	var row_plan := interaction.set_drag_end(Vector3i(-7, 0, 44))
	var row_commit := interaction.commit_drag_place()
	var row_ok: bool = row_begin.get("ok", false) and str(row_plan.get("shape", "")) == "row" and int(row_plan.get("affordable", 0)) == 6 		and row_commit.get("ok", false) and int(row_commit.get("changes", {}).get("count", 0)) == 6 and inventory.count("dirt") == 24 		and int(app.session.world.query_cell(Vector3i(-7, 0, 44)).get("voxel_id", 0)) == 2
	# Column of 3 rising from a row cell: upper cells are supported by planned cells.
	interaction.begin_drag_at(Vector3i(-2, 1, 44))
	var column_plan := interaction.set_drag_end(Vector3i(-2, 3, 44))
	var column_commit := interaction.commit_drag_place()
	var column_ok: bool = str(column_plan.get("shape", "")) == "column" and int(column_plan.get("affordable", 0)) == 3 		and column_commit.get("ok", false) and int(column_commit.get("changes", {}).get("count", 0)) == 3 and inventory.count("dirt") == 21 		and int(app.session.world.query_cell(Vector3i(-2, 3, 44)).get("voxel_id", 0)) == 2
	# Wall 4 wide x 3 high on top of the row with one pre-blocked cell (skipped) and
	# only 10 dirt left after trimming: 12 cells - 1 blocked = 11 valid, 10 affordable.
	inventory.try_transaction({"dirt": 11}, {})
	app.session.world.set_cell(Vector3i(-5, 2, 44), 3)
	interaction.begin_drag_at(Vector3i(-3, 1, 44))
	var wall_plan := interaction.set_drag_end(Vector3i(-6, 3, 44))
	var blocked := 0
	var unaffordable := 0
	for entry in wall_plan.get("cells", []):
		if str(entry.state) == "blocked":
			blocked += 1
		elif str(entry.state) == "unaffordable":
			unaffordable += 1
	var wall_commit := interaction.commit_drag_place()
	var wall_ok: bool = str(wall_plan.get("shape", "")) == "wall" and wall_plan.get("cells", []).size() == 12 and blocked == 1 and unaffordable == 1 		and int(wall_plan.get("affordable", 0)) == 10 and wall_commit.get("ok", false) and int(wall_commit.get("changes", {}).get("count", 0)) == 10 		and inventory.count("dirt") == 0 and int(app.session.world.query_cell(Vector3i(-5, 2, 44)).get("voxel_id", 0)) == 3
	# Sky drag: with the aim off the terrain, the plan stretches along the row's
	# vertical plane so moving the mouse up builds up (owner playtest 2026-09-18).
	inventory.try_transaction({}, {"dirt": 40})
	interaction.begin_drag_at(Vector3i(-2, 0, 48))
	interaction.set_drag_end(Vector3i(-6, 0, 48))
	var sky_origin := Vector3(-4.5, 1.6, 54.0)
	var sky_direction := (Vector3(-6.5, 3.5, 48.5) - sky_origin).normalized()
	var sky_plan := interaction.update_drag_place(sky_origin, sky_direction)
	var sky_commit := interaction.commit_drag_place()
	var sky_end: Vector3i = sky_plan.get("end", Vector3i.ZERO)
	var sky_cells := (absi(sky_end.x + 2) + 1) * (absi(sky_end.y) + 1)
	var sky_ok: bool = str(sky_plan.get("shape", "")) == "wall" and sky_end.y == 3 and sky_end.z == 48 and sky_end.x <= -6 		and sky_plan.get("cells", []).size() == sky_cells and sky_commit.get("ok", false) and int(sky_commit.get("changes", {}).get("count", 0)) == sky_cells 		and int(app.session.world.query_cell(Vector3i(-6, 3, 48)).get("voxel_id", 0)) == 2
	inventory.try_transaction({"dirt": inventory.count("dirt")}, {})
	# Shift-held vertical: the horizontal extent freezes and only height follows
	# the aim, even when the aim would hit terrain (owner direction 2026-09-18).
	inventory.try_transaction({}, {"dirt": 40})
	interaction.begin_drag_at(Vector3i(-2, 0, 50))
	interaction.set_drag_end(Vector3i(-5, 0, 50))
	var lift_origin := Vector3(-3.5, 1.6, 56.0)
	var lift_direction := (Vector3(-9.5, 2.5, 50.5) - lift_origin).normalized()
	var lift_plan := interaction.update_drag_place(lift_origin, lift_direction, true)
	var lift_end: Vector3i = lift_plan.get("end", Vector3i.ZERO)
	var lift_commit := interaction.commit_drag_place()
	var lift_ok: bool = lift_end.x == -5 and lift_end.z == 50 and lift_end.y >= 2 and str(lift_plan.get("shape", "")) == "wall" 		and lift_commit.get("ok", false) and int(lift_commit.get("changes", {}).get("count", 0)) == 4 * (lift_end.y + 1)
	inventory.try_transaction({"dirt": inventory.count("dirt")}, {})
	# Cancel: nothing built, nothing consumed; empty inventory refuses to start a plan with affordable cells.
	inventory.try_transaction({}, {"dirt": 5})
	var revision_before: int = app.session.world.revision
	interaction.begin_drag_at(Vector3i(-2, 0, 46))
	interaction.set_drag_end(Vector3i(-6, 0, 46))
	var cancelled := interaction.cancel_drag_place()
	var cancel_ok: bool = str(cancelled.get("reason", "")) == "DRAG_CANCELLED" and not interaction.drag_active() 		and app.session.world.revision == revision_before and inventory.count("dirt") == 5 		and int(app.session.world.query_cell(Vector3i(-4, 0, 46)).get("voxel_id", 0)) == 0
	_record("T108_DRAG_BUILD", row_ok and column_ok and wall_ok and sky_ok and lift_ok and cancel_ok, "a right-drag plans a row, column or wall of the held block with support-first ordering, skips blocked cells, trims to the carried count, commits as one world edit plus one inventory transaction, and cancels with nothing built", {"row": row_plan, "row_commit": row_commit.get("reason"), "column": column_commit.get("reason"), "wall_blocked": blocked, "wall_unaffordable": unaffordable, "wall_commit": wall_commit.get("reason"), "sky": sky_plan.get("shape", ""), "sky_end": sky_plan.get("end", Vector3i.ZERO), "sky_commit": sky_commit.get("reason"), "lift_end": lift_end, "lift_commit": lift_commit.get("reason"), "cancel": cancelled.get("reason"), "dirt": inventory.count("dirt")})

	await _run_sign_phase1()


## T212 (docs/SIGNS.md, Development Expo section 9): the Sign places on the
## ground and on a wall side, refuses an occupied cell, keeps each of the four
## display modes plus eight item ids across a save/restore, and opens its own
## editor panel through the app's real right-click path.
func _run_sign_phase1() -> void:
	var ws := app.session.workstations
	var world := app.session.world
	var ground_anchor := Vector3i(8, 0, 34)
	var wall_block := Vector3i(10, 1, 34)
	var wall_anchor := Vector3i(11, 1, 34)
	if not await _wait_cells([ground_anchor, wall_block, wall_anchor, ground_anchor + Vector3i.DOWN]):
		return
	app.session.inventory.try_transaction({}, {"sign": 4})
	var ground := ws.try_place("sign", ground_anchor, world.query_cell, AABB(), 0)
	var ground_id := str(ground.get("details", {}).get("station", {}).get("instance_id", ""))
	var blocked := ws.try_place("sign", ground_anchor, world.query_cell, AABB(), 0)
	world.set_cell(wall_block, InteractionService.DIRT)
	var wall := ws.try_place("sign", wall_anchor, world.query_cell, AABB(), 0)
	var wall_id := str(wall.get("details", {}).get("station", {}).get("instance_id", ""))
	var placement_ok: bool = ground.get("ok", false) and str(ground.get("details", {}).get("mount", "")) == "ground" 		and wall.get("ok", false) and str(wall.get("details", {}).get("mount", "")) == "wall" 		and ws.sign_mount(wall_id) == "wall" and ws.sign_mount(ground_id) == "ground" 		and not blocked.get("ok", false) and str(blocked.get("reason", "")) == "OCCUPIED"

	var grid_items: Array[String] = ["dirt", "stone", "log", "planks", "coal", "iron_ore", "iron_ingot", "stick"]
	var modes: Array[Dictionary] = [
		{"mode": "text", "text_a": "SUPPLY DEPOT", "text_b": "", "items": []},
		{"mode": "split", "text_a": "ORE", "text_b": "INGOT", "items": []},
		{"mode": "items", "text_a": "", "text_b": "", "items": grid_items},
		{"mode": "header_items", "text_a": "AMMUNITION", "text_b": "", "items": ["stone_shot", "flame_shot", "cannonball", "ballista_bolt"]},
	]
	var mode_results: Array[Dictionary] = []
	var modes_ok := true
	for requested: Dictionary in modes:
		var applied := app.session.configure_sign(ground_id, requested)
		var stored := app.session.sign_data(ground_id)
		var matched: bool = applied.get("ok", false) and str(stored.get("mode", "")) == str(requested.mode) 			and str(stored.get("text_a", "")) == str(requested.text_a) and str(stored.get("text_b", "")) == str(requested.text_b) 			and _same_items(stored.get("items", []), requested.get("items", []))
		modes_ok = modes_ok and matched
		mode_results.append({"mode": str(requested.mode), "ok": matched, "stored": stored})
	var rejected := app.session.configure_sign(ground_id, {"mode": "billboard"})
	var unknown_item := app.session.configure_sign(ground_id, {"items": ["not_an_item"]})
	var guard_ok: bool = not rejected.get("ok", false) and not unknown_item.get("ok", false)

	# Eight entries through a real save round trip: the record is JSON first.
	app.session.configure_sign(ground_id, {"mode": "items", "text_a": "TEST STOCK", "items": grid_items})
	app.session.configure_sign(wall_id, {"mode": "split", "text_a": "LEFT", "text_b": "RIGHT"})
	var snapshot: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(snapshot if snapshot is Dictionary else {}, world.query_cell)
	var restored_ground := app.session.sign_data(ground_id)
	var restored_wall := app.session.sign_data(wall_id)
	var round_trip_ok: bool = restored.get("ok", false) and str(restored_ground.get("mode", "")) == "items" 		and str(restored_ground.get("text_a", "")) == "TEST STOCK" 		and _same_items(restored_ground.get("items", []), grid_items) 		and str(restored_wall.get("mode", "")) == "split" and str(restored_wall.get("text_b", "")) == "RIGHT" 		and ws.sign_mount(wall_id) == "wall"
	# A record saved before the editor existed migrates to an empty text sign.
	var legacy: Dictionary = ws.snapshot()
	for station: Variant in legacy.get("stations", []):
		if str((station as Dictionary).get("instance_id", "")) == ground_id:
			(station as Dictionary).erase("sign")
	var migrated := ws.restore(legacy, world.query_cell)
	var migration_ok: bool = migrated.get("ok", false) and app.session.sign_data(ground_id) == WorkstationService.default_sign()
	app.session.configure_sign(ground_id, {"mode": "items", "text_a": "TEST STOCK", "items": grid_items})

	# The owner's path: right-click the sign, read the panel, close it.
	app._show_workstation(ground_id, "sign")
	await get_tree().process_frame
	var draft: Dictionary = app._sign_draft.duplicate(true)
	var draft_items: Array = draft.get("items", [])
	var panel_ok: bool = app.state == CraftAndDefendApp.AppState.SIGN and app.sign_panel.visible 		and str(draft.get("mode", "")) == "items" and str(draft.get("text_a", "")) == "TEST STOCK" 		and _same_items(draft_items, grid_items) and app.sign_slot_buttons.size() == WorkstationService.SIGN_ITEM_SLOTS 		and app.sign_items_card.visible and app.sign_picker_card.visible and app.sign_picker_grid.get_child_count() > 0 		and app.sign_picker_category_row.get_child_count() >= 2 		and app.sign_slot_buttons[1].text.contains(app.session.registry.display_name("stone"))
	# Editing through the panel controls: pick a different item into slot 1,
	# then save and read the record back.
	app._select_sign_slot(0)
	app._set_sign_picker_category("lighting_and_utility")
	app._pick_sign_item("torch")
	app._save_sign()
	var edited: Array = app.session.sign_data(ground_id).get("items", [])
	var edit_ok: bool = edited.size() == 8 and str(edited[0]) == "torch" and str(edited[1]) == "stone"
	app._close_sign()
	var closed_ok: bool = app.state == CraftAndDefendApp.AppState.PLAYING and not app.sign_panel.visible
	var wide := await _run_wide_board_phase1(grid_items)

	await _run_stacked_board_phase1()
	_record("T212_SIGN_PLACEMENT_AND_EDITOR", placement_ok and modes_ok and guard_ok and round_trip_ok and migration_ok and panel_ok and edit_ok and closed_ok and bool(wide.get("ok", false)),
		"a sign places on the ground with a post and on a wall side without one, refuses an occupied cell, keeps each of the four display modes and eight item ids across a save/restore (a record without the block migrates to an empty text sign), and right-click opens the sign editor showing exactly the stored mode, text and items",
		{"ground": ground.get("reason"), "wall": wall.get("reason"), "blocked": blocked.get("reason"), "placement_ok": placement_ok, "modes": mode_results, "guard_ok": guard_ok, "restored": restored.get("reason"), "restored_wall": restored_wall, "restored_ground": restored_ground, "migration_ok": migration_ok, "panel_ok": panel_ok, "draft": draft, "edited": edited, "closed_ok": closed_ok, "wide_board": wide})


## T212, the wide board (docs/SIGNS.md, signs card 2): `sign_board` is the same
## sign two cells across. It must place on the ground and on a wall side,
## reserve both of its cells, refuse a placement whose second cell is taken -
## the first cell being free is not enough - and carry the same content through
## a real save round trip.
func _run_wide_board_phase1(grid_items: Array[String]) -> Dictionary:
	var ws := app.session.workstations
	var world := app.session.world
	var entity := WorkstationService.SIGN_BOARD_ENTITY
	var ground_anchor := Vector3i(14, 0, 34)
	# Rotation 0 leaves the board facing +x, so its second cell is anchor + z.
	var second_cell := ground_anchor + Vector3i(0, 0, 1)
	var blocker_anchor := Vector3i(14, 0, 37)
	var wall_block := Vector3i(16, 1, 34)
	var wall_anchor := Vector3i(17, 1, 34)
	var needed: Array[Vector3i] = [ground_anchor, second_cell, blocker_anchor, blocker_anchor + Vector3i(0, 0, 1),
		wall_block, wall_anchor, wall_anchor + Vector3i(0, 0, 1), ground_anchor + Vector3i.DOWN]
	if not await _wait_cells(needed):
		return {"ok": false, "reason": "CELLS_NOT_LOADED"}
	app.session.inventory.try_transaction({}, {"sign_board": 4, "sign": 1})
	# Both cells of a ground board need something under them.
	for support: Vector3i in [ground_anchor, second_cell, blocker_anchor, blocker_anchor + Vector3i(0, 0, 1)]:
		world.set_cell(support + Vector3i.DOWN, InteractionService.DIRT)
	var placed := ws.try_place(entity, ground_anchor, world.query_cell, AABB(), 0)
	var board_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var cells: Array = placed.get("details", {}).get("occupied_cells", [])
	var reserved_both: bool = ws.station_at_cell(ground_anchor) == board_id \
		and ws.station_at_cell(second_cell) == board_id and cells.size() == 2
	# A one-cell sign in the second cell of an otherwise free pair: the wide
	# board must refuse the pair, not overlap it.
	var blocker := ws.try_place(WorkstationService.SIGN_ENTITY, blocker_anchor + Vector3i(0, 0, 1), world.query_cell, AABB(), 0)
	var refused := ws.try_place(entity, blocker_anchor, world.query_cell, AABB(), 0)
	var refuses_occupied: bool = bool(blocker.get("ok", false)) and not bool(refused.get("ok", false)) \
		and str(refused.get("reason", "")) == "OCCUPIED" and ws.station_at_cell(blocker_anchor).is_empty()
	world.set_cell(wall_block, InteractionService.DIRT)
	# No ground under either cell, so the board takes the wall beside it: the
	# mount rule prefers ground whenever there is ground.
	for below: Vector3i in [wall_anchor + Vector3i.DOWN, wall_anchor + Vector3i(0, -1, 1)]:
		world.set_cell(below, 0)
	var wall := ws.try_place(entity, wall_anchor, world.query_cell, AABB(), 0)
	var wall_id := str(wall.get("details", {}).get("station", {}).get("instance_id", ""))
	var wall_ok: bool = bool(wall.get("ok", false)) and str(wall.get("details", {}).get("mount", "")) == "wall" \
		and ws.sign_mount(wall_id) == "wall"
	var configured := app.session.configure_sign(board_id, {"mode": "header_items", "text_a": "SUPPLY DEPOT", "items": grid_items})
	var snapshot: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(snapshot if snapshot is Dictionary else {}, world.query_cell)
	var stored := app.session.sign_data(board_id)
	var round_trip: bool = bool(restored.get("ok", false)) and str(stored.get("mode", "")) == "header_items" \
		and str(stored.get("text_a", "")) == "SUPPLY DEPOT" and _same_items(stored.get("items", []), grid_items) \
		and ws.station_at_cell(second_cell) == board_id
	# The board reads as one board: one face, laid out for two cells of width.
	var body: Node3D = app.session._station_visuals.get(board_id, null)
	var face: Node3D = body.get_node_or_null("SignFace") as Node3D if body != null else null
	var rendered: bool = face != null and face.get_child_count() >= 9 \
		and is_equal_approx(GameSession.sign_board_width(entity), GameSession.SIGN_WIDE_BOARD_WIDTH)
	var ok: bool = bool(placed.get("ok", false)) and reserved_both and refuses_occupied and wall_ok \
		and bool(configured.get("ok", false)) and round_trip and rendered
	return {"ok": ok, "placed": placed.get("reason", ""), "cells": cells, "reserved_both": reserved_both,
		"blocker": blocker.get("reason", ""), "refused": refused.get("reason", ""), "refuses_occupied": refuses_occupied,
		"wall": wall.get("reason", ""), "wall_ok": wall_ok, "wall_mount": wall.get("details", {}).get("mount", ""),
		"wall_record_mount": ws.sign_mount(wall_id), "stored": stored, "round_trip": round_trip,
		"face_children": face.get_child_count() if face != null else 0, "rendered": rendered}


	# T224 flight (owner 2026-09-23): a double tap of Right Shift toggles it;
	# a single tap does not. While flying there is no gravity, the movement
	# keys steer along the camera's own axes and Space / Z lift and drop.
	var fly_player := app.session.player
	var was_paused: bool = app.session.simulation_paused
	app.session.simulation_paused = false
	fly_player.global_position = Vector3(0.0, 20.0, 40.0)
	fly_player.activate(false)
	await get_tree().process_frame
	var single_tap := await _tap_right_shift()
	var single_ignored: bool = not fly_player.flying
	await _wait_msec(GameSession.FLIGHT_DOUBLE_TAP_MSEC + 80)
	var double_tap_a := await _tap_right_shift()
	var double_tap_b := await _tap_right_shift()
	var flying_on: bool = fly_player.flying
	# Airborne with no input: a walking body would fall, a flying one holds.
	var height_before := fly_player.global_position.y
	for _frame in range(30):
		await get_tree().physics_frame
	var hovered: bool = absf(fly_player.global_position.y - height_before) < 0.05 and absf(fly_player.velocity.y) < 0.01
	# The keys follow the view: look down-left, press forward, travel that way.
	fly_player.rotation.y = PI * 0.5
	fly_player.look_pitch = -0.6
	fly_player.apply_mouse_look(Vector2.ZERO)
	var aim_forward := -fly_player.camera.global_basis.z
	var before_move := fly_player.global_position
	Input.action_press("move_forward")
	for _frame in range(30):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var travelled := fly_player.global_position - before_move
	var follows_view: bool = travelled.length() > 1.0 and travelled.normalized().dot(aim_forward) > 0.9
	# Space rises.
	var lift_before := fly_player.global_position.y
	Input.action_press("jump")
	for _frame in range(20):
		await get_tree().physics_frame
	Input.action_release("jump")
	var rose: bool = fly_player.global_position.y > lift_before + 1.0
	# Another double tap lands: gravity is back.
	await _wait_msec(GameSession.FLIGHT_DOUBLE_TAP_MSEC + 80)
	await _tap_right_shift()
	await _tap_right_shift()
	var flying_off: bool = not fly_player.flying
	var fall_before := fly_player.global_position.y
	for _frame in range(30):
		await get_tree().physics_frame
	var fell: bool = fly_player.global_position.y < fall_before - 0.5
	fly_player.deactivate()
	fly_player.look_pitch = 0.0
	fly_player.rotation = Vector3.ZERO
	app.session.simulation_paused = was_paused
	_record("T224_FLIGHT", single_tap and single_ignored and double_tap_a and double_tap_b and flying_on and hovered and follows_view and rose and flying_off and fell,
		"one Right Shift tap does not start flight; two taps within the double-tap window do; a flying body holds its height with no input, travels along the camera's aim when the movement keys are pressed, rises on Space; a second double tap lands it and gravity pulls it down again",
		{"single_ignored": single_ignored, "flying_on": flying_on, "hovered": hovered, "follows_view": follows_view, "travelled": str(travelled), "rose": rose, "flying_off": flying_off, "fell": fell})


## T232 (signs card 3, docs/SIGNS.md): the stacked board the owner asked for.
## The `header_body` mode stores and restores its header, subheader and body;
## the rendered labels come out ordered header > subheader > body with none of
## them under its readable floor; a ground board hangs at head height on a post
## that reaches the ground it stands on; and a wall board centres at eye height
## with no post at all.
func _run_stacked_board_phase1() -> void:
	var ws := app.session.workstations
	var world := app.session.world
	var entity := WorkstationService.SIGN_BOARD_LARGE_ENTITY
	var ground_anchor := Vector3i(20, 1, 34)
	var wall_block := Vector3i(26, 1, 34)
	var wall_anchor := Vector3i(27, 1, 34)
	var needed: Array[Vector3i] = [ground_anchor, ground_anchor + Vector3i(0, 0, 1), ground_anchor + Vector3i(0, 0, 2),
		ground_anchor + Vector3i.DOWN, wall_block, wall_anchor, wall_anchor + Vector3i(0, 0, 1),
		wall_anchor + Vector3i(0, 0, 2)]
	if not await _wait_cells(needed):
		_record("T232_SIGN_STACKED", false, "the stacked board's cells loaded for the test", {"reason": "CELLS_NOT_LOADED"})
		return
	app.session.inventory.try_transaction({}, {"sign_board_large": 4})
	# Three clear cells with something solid under each: the terrain here is
	# whatever the world generator made of it.
	for index in range(3):
		world.set_cell(ground_anchor + Vector3i(0, 0, index), 0)
		world.set_cell(ground_anchor + Vector3i(0, -1, index), InteractionService.DIRT)
	var placed := ws.try_place(entity, ground_anchor, world.query_cell, AABB(), 0)
	var board_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var cells: Array = placed.get("details", {}).get("occupied_cells", [])
	var reserved_all: bool = cells.size() == 3 and ws.station_at_cell(ground_anchor + Vector3i(0, 0, 2)) == board_id
	var header := "DEFENSE RANGE"
	var subheader := "Siege weapons and ammunition."
	var body := "Every weapon on its own mount.\nAmmunition in the chest beside it.\nTargets down the range."
	var configured := app.session.configure_sign(board_id,
		{"mode": "header_body", "text_a": header, "text_b": subheader, "text_c": body})
	var snapshot: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(snapshot if snapshot is Dictionary else {}, world.query_cell)
	var stored := app.session.sign_data(board_id)
	var round_trip: bool = bool(restored.get("ok", false)) and str(stored.get("mode", "")) == "header_body" \
		and str(stored.get("text_a", "")) == header and str(stored.get("text_b", "")) == subheader \
		and str(stored.get("text_c", "")) == body
	var sizes := _stacked_sizes(board_id)
	var ordered: bool = float(sizes.get("header", 0.0)) > float(sizes.get("subheader", 0.0)) \
		and float(sizes.get("subheader", 0.0)) > float(sizes.get("body", 0.0))
	var above_floor: bool = float(sizes.get("header", 0.0)) >= GameSession.SIGN_MIN_HEADER_HEIGHT \
		and float(sizes.get("subheader", 0.0)) >= GameSession.SIGN_MIN_SUBHEADER_HEIGHT \
		and float(sizes.get("body", 0.0)) >= GameSession.SIGN_MIN_BODY_HEIGHT
	# Head height on a post that reaches the ground: the board's centre, in
	# metres above the floor the sign stands on, and the post's own foot.
	var ground_board := _sign_part_box(board_id, "SignBoard")
	var ground_post := _sign_part_box(board_id, "SignPost0")
	var board_height: float = float(ground_board.get("centre", 0.0)) + 0.5
	var post_foot: float = float(ground_post.get("bottom", 1.0)) + 0.5
	var head_height: bool = not ground_board.is_empty() and board_height >= 1.5 and board_height <= 1.8
	var post_grounded: bool = not ground_post.is_empty() and absf(post_foot) <= 0.01 \
		and float(ground_post.get("top", 0.0)) <= float(ground_board.get("bottom", 0.0)) + 0.01
	# The wall board: no ground under any of its cells, so it hangs on the
	# block beside it, centred at eye height and standing on nothing.
	world.set_cell(wall_block, InteractionService.DIRT)
	for index in range(3):
		world.set_cell(wall_anchor + Vector3i(0, -1, index), 0)
	var wall := ws.try_place(entity, wall_anchor, world.query_cell, AABB(), 0)
	var wall_id := str(wall.get("details", {}).get("station", {}).get("instance_id", ""))
	var wall_board := _sign_part_box(wall_id, "SignBoard")
	var wall_height: float = float(wall_board.get("centre", 0.0)) + 0.5
	var wall_ok: bool = bool(wall.get("ok", false)) and ws.sign_mount(wall_id) == "wall" \
		and not wall_board.is_empty() and absf(wall_height - GameSession.SIGN_WALL_BOARD_HEIGHT) <= 0.01 \
		and _sign_part_box(wall_id, "SignPost0").is_empty()
	var ok: bool = bool(placed.get("ok", false)) and reserved_all and bool(configured.get("ok", false)) \
		and round_trip and ordered and above_floor and head_height and post_grounded and wall_ok
	_record("T232_SIGN_STACKED", ok,
		"the stacked Header + Subheader + Body board stores and restores all three fields, renders them at sizes ordered header > subheader > body with none under its readable floor, carries its board at head height on a post that reaches the ground, and centres a wall board at eye height with no post",
		{"placed": placed.get("reason", ""), "cells": cells.size(), "stored": stored, "round_trip": round_trip,
		"sizes": sizes, "ordered": ordered, "above_floor": above_floor,
		"board_height_m": board_height, "post_foot_m": post_foot, "wall": wall.get("reason", ""),
		"wall_height_m": wall_height, "wall_ok": wall_ok})


## The cap heights the three stacked roles rendered at (0.0 for a role the
## board does not carry).
func _stacked_sizes(instance_id: String) -> Dictionary:
	var sizes := {"header": 0.0, "subheader": 0.0, "body": 0.0}
	var body: Node3D = app.session._station_visuals.get(instance_id, null)
	if body == null:
		return sizes
	var face: Node3D = body.get_node_or_null("SignFace") as Node3D
	if face == null:
		return sizes
	for key: String in ["header", "subheader", "body"]:
		var label: Label3D = face.get_node_or_null("Sign" + key.capitalize()) as Label3D
		if label != null:
			sizes[key] = label.pixel_size * float(label.font_size)
	return sizes


## One named box of a placed sign's body, as {centre, top, bottom} in the
## body's own local space ({} when the sign does not carry that part).
func _sign_part_box(instance_id: String, part_name: String) -> Dictionary:
	var body: Node3D = app.session._station_visuals.get(instance_id, null)
	if body == null:
		return {}
	var mesh: MeshInstance3D = body.get_node_or_null(part_name) as MeshInstance3D
	if mesh == null:
		return {}
	var box: BoxMesh = mesh.mesh as BoxMesh
	if box == null:
		return {}
	return {"centre": mesh.position.y, "top": mesh.position.y + box.size.y / 2.0,
		"bottom": mesh.position.y - box.size.y / 2.0}


## One Right Shift press / release through the real input path.
func _tap_right_shift() -> bool:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SHIFT
		key.physical_keycode = KEY_SHIFT
		key.location = KEY_LOCATION_RIGHT
		key.pressed = pressed
		Input.parse_input_event(key)
		await get_tree().process_frame
	await get_tree().process_frame
	return true


func _wait_msec(msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return true


func _same_items(actual: Variant, expected: Variant) -> bool:
	var left: Array = actual if actual is Array else []
	var right: Array = expected if expected is Array else []
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if str(left[index]) != str(right[index]):
			return false
	return true


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.inventory.try_transaction({}, {"wood_axe": 1, "dirt": 16})
	var axe_slot := _move_to_hotbar("wood_axe", 0)
	var dirt_slot := _move_to_hotbar("dirt", 1)
	app.session.player.deactivate()
	app.session.simulation_paused = false
	app.session.player.global_position = Vector3(-2.5, 1.0, 31.0)
	app.session.player.look_at(GameSession.STARTER_IRON_MARKER + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	app.session.inventory.select_hotbar(axe_slot)
	await _settle_frames(30)
	var axe_path := app.data_root.path_join("p3d-held-axe-iron-marker.png")
	var axe_image_ok := await _save_viewport(axe_path)

	app.session.player.global_position = Vector3(4.5, 1.0, 36.0)
	app.session.player.look_at(Vector3(4.5, 0.5, 39.5), Vector3.UP)
	app.session.inventory.select_hotbar(dirt_slot)
	app.session._placement_preview_key = ""
	var ghost_visible: bool = await _wait_for_ghost("PlacementPreview") and app.session._held_item_view.current_item_id == "dirt"
	await _settle_frames(4)
	var block_path := app.data_root.path_join("p3d-held-block-placement-ghost.png")
	var block_image_ok := await _save_viewport(block_path)
	# Owner playtest 2026-09-18: the hotbar must end above the window edge with
	# square, fully contained tiles.
	var hotbar_16_9 := _hotbar_containment()
	var captions_ok := app.gameplay_hotbar_slots[axe_slot]._name_label.text == "Wood Axe" and app.gameplay_hotbar_slots[dirt_slot]._name_label.text == "Dirt" and app.gameplay_hotbar_slots[dirt_slot]._count_label.text == "×16"
	_record("T83_PRESENTATION", axe_image_ok and block_image_ok and ghost_visible and bool(hotbar_16_9.ok) and captions_ok, "rendered evidence shows the held axe beside the real iron marker and a low held block with its world placement ghost; the hotbar ends at least 8 px above the viewport bottom with square tiles whose contents stay inside and whose captions are the item name only", {"axe_path": axe_path, "block_path": block_path, "size": get_viewport().get_visible_rect().size, "ghost_visible": ghost_visible, "hotbar": hotbar_16_9, "captions_ok": captions_ok})

	# 21:9 frame: the same containment must hold when the canvas widens
	# (canvas_items / expand keeps the height at 720 and widens the width).
	var ultrawide_size := Vector2i(1720, 720)
	get_window().content_scale_size = ultrawide_size
	get_window().size = ultrawide_size
	for _resize_frame in range(3):
		await get_tree().process_frame
	await _settle_frames(4)
	var ultrawide_path := app.data_root.path_join("p3d-hotbar-ultrawide.png")
	var ultrawide_image_ok := await _save_viewport_sized(ultrawide_path, ultrawide_size)
	var hotbar_21_9 := _hotbar_containment()
	var ultrawide_centred: bool = absf(app.gameplay_hotbar.get_global_rect().get_center().x - ultrawide_size.x / 2.0) <= 1.0
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().size = Vector2i(1280, 720)
	for _restore_frame in range(3):
		await get_tree().process_frame
	await _settle_frames(2)
	var restored_ok := get_viewport().get_visible_rect().size == Vector2(1280, 720)
	_record("T83_HOTBAR_ULTRAWIDE", ultrawide_image_ok and bool(hotbar_21_9.ok) and ultrawide_centred and restored_ok, "at a 21:9 canvas the hotbar stays centred, square and fully inside the viewport with its bottom margin, and the viewport restores to 1280×720", {"path": ultrawide_path, "hotbar": hotbar_21_9, "centred": ultrawide_centred, "restored": restored_ok})

	# P3J: a held right-drag from the aimed anchor shows every planned cell.
	# The camera ray sets the drag end each frame, so aim at the ground ahead.
	app.session.player.global_position = Vector3(8.5, 1.0, 33.0)
	app.session.player.look_at(Vector3(2.5, -4.0, 39.5), Vector3.UP)
	app.session.interaction.begin_drag_at(Vector3i(8, 0, 38))
	app.session._placement_preview_key = ""
	var drag_ghost_seen: bool = await _wait_for_ghost("DragPreview", 2)
	await _settle_frames(4)
	var drag := app.session.interaction.drag_state()
	var drag_ghost_visible: bool = drag_ghost_seen and drag.get("active", false) and drag.get("cells", []).size() >= 2
	var drag_path := app.data_root.path_join("p3j-drag-build-ghost.png")
	var drag_image_ok := await _save_viewport(drag_path)
	app.session.interaction.cancel_drag_place()
	_record("T109_DRAG_BUILD_PRESENTATION", drag_image_ok and drag_ghost_visible, "rendered evidence shows a multi-cell drag-build ghost stretched from the anchor toward the aimed cell", {"path": drag_path, "shape": drag.get("shape", ""), "cells": drag.get("cells", []).size(), "affordable": drag.get("affordable", 0), "ghost_visible": drag_ghost_visible})

	# Sign (docs/SIGNS.md): rendered evidence that a configured board reads at
	# player distance - the header line plus the eight-item 4 x 2 grid.
	# One cell up on a dirt plinth so the board sits at eye height for the shot.
	var sign_anchor := Vector3i(8, 1, 34)
	var sign_ok := false
	var sign_path := app.data_root.path_join("p3d-sign-item-grid.png")
	var sign_entries: Array[String] = ["dirt", "stone", "log", "planks", "coal", "iron_ore", "iron_ingot", "stick"]
	if await _wait_cells([sign_anchor, sign_anchor + Vector3i.DOWN]):
		app.session.inventory.try_transaction({}, {"sign": 1})
		app.session.world.set_cell(sign_anchor + Vector3i.DOWN, InteractionService.DIRT)
		# Quarter turn 1 points the board's face down +Z, at the camera below.
		var placed := app.session.workstations.try_place("sign", sign_anchor, app.session.world.query_cell, AABB(), 1)
		var sign_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
		var configured := app.session.configure_sign(sign_id, {"mode": "header_items", "text_a": "SUPPLY DEPOT", "items": sign_entries})
		app.session.player.global_position = Vector3(8.5, 0.05, 36.8)
		app.session.player.look_at(Vector3(8.5, 0.05, 34.5), Vector3.UP)
		# Empty hand: no placement ghost between the camera and the board.
		app.session.inventory.select_hotbar(4)
		await _settle_frames(6)
		app.session._hide_placement_preview()
		await _settle_frames(24)
		var face: Node3D = app.session._station_visuals.get(sign_id, null)
		var face_node: Node3D = face.get_node_or_null("SignFace") as Node3D if face != null else null
		sign_ok = placed.get("ok", false) and configured.get("ok", false) and face_node != null and face_node.get_child_count() >= 9 and await _save_viewport(sign_path)
		_record("T212_SIGN_PRESENTATION", sign_ok, "rendered evidence shows a placed ground sign whose board carries its header line and its eight-item 4 x 2 grid of icons and names", {"path": sign_path, "placed": placed.get("reason", ""), "face_children": face_node.get_child_count() if face_node != null else 0, "items": sign_entries})
	else:
		_record("T212_SIGN_PRESENTATION", false, "the sign cell loaded for the capture", {"path": sign_path})

	# The wide board carrying the same Supply Depot grid: the heading must sit
	# on one line (no "DEVELO / PMENT" break) and the 4 x 2 grid must read.
	var wide_anchor := Vector3i(14, 1, 34)
	var wide_path := app.data_root.path_join("p3d-sign-wide-board.png")
	# Quarter turn 1 turns the board's second cell (its local +z) onto -x, so
	# the plinth under it runs the same way.
	var wide_second := wide_anchor + Vector3i(-1, 0, 0)
	if await _wait_cells([wide_anchor, wide_second, wide_anchor + Vector3i.DOWN, wide_second + Vector3i.DOWN]):
		app.session.inventory.try_transaction({}, {"sign_board": 1})
		for support: Vector3i in [wide_anchor + Vector3i.DOWN, wide_second + Vector3i.DOWN]:
			app.session.world.set_cell(support, InteractionService.DIRT)
		# Quarter turn 1 points the board's face down +Z, at the camera below.
		var wide_placed := app.session.workstations.try_place(WorkstationService.SIGN_BOARD_ENTITY, wide_anchor, app.session.world.query_cell, AABB(), 1)
		var wide_id := str(wide_placed.get("details", {}).get("station", {}).get("instance_id", ""))
		var wide_configured := app.session.configure_sign(wide_id, {"mode": "header_items", "text_a": "DEVELOPMENT EXPO SUPPLY DEPOT", "items": sign_entries})
		# The board runs from the anchor along -x at this rotation, so the
		# camera stands off its centre line half a cell to the -x side.
		app.session.player.global_position = Vector3(14.0, 0.05, 37.4)
		app.session.player.look_at(Vector3(14.0, 0.05, 34.5), Vector3.UP)
		app.session.inventory.select_hotbar(4)
		await _settle_frames(6)
		app.session._hide_placement_preview()
		await _settle_frames(24)
		var wide_body: Node3D = app.session._station_visuals.get(wide_id, null)
		var wide_face: Node3D = wide_body.get_node_or_null("SignFace") as Node3D if wide_body != null else null
		var heading := _find_label(wide_face)
		# The layout is decided before the render: the heading is wrapped on
		# word boundaries, so no rendered line is a fragment of a word.
		var laid_out: PackedStringArray = heading.text.replace("\n", " ").split(" ", false) if heading != null else PackedStringArray()
		var whole_words: bool = heading != null and laid_out == "DEVELOPMENT EXPO SUPPLY DEPOT".split(" ", false)
		var wide_ok: bool = bool(wide_placed.get("ok", false)) and bool(wide_configured.get("ok", false)) \
			and wide_face != null and wide_face.get_child_count() >= 9 and whole_words \
			and await _save_viewport(wide_path)
		_record("T212_SIGN_WIDE_PRESENTATION", wide_ok,
			"rendered evidence shows the two-cell wide board carrying a Supply Depot heading that is not broken mid-word and the same eight-item 4 x 2 grid of icons and names, readable from about four metres",
			{"path": wide_path, "placed": wide_placed.get("reason", ""), "heading": heading.text if heading != null else "",
			"line_height": heading.pixel_size * heading.font_size if heading != null else 0.0,
			"face_children": wide_face.get_child_count() if wide_face != null else 0})
	else:
		_record("T212_SIGN_WIDE_PRESENTATION", false, "the wide board cells loaded for the capture", {"path": wide_path})

	# T232 (signs card 3): the district board, read the way the owner reads it -
	# standing five metres in front of it with his eyes at 1.6 m, not looking
	# down at a board on a stub.
	var stacked_anchor := Vector3i(20, 1, 34)
	var stacked_path := app.data_root.path_join("p3d-sign-stacked-board.png")
	# Quarter turn 1 turns the board's run (its local +z) onto -x and points
	# its face down +Z, at the camera.
	var stacked_cells: Array[Vector3i] = [stacked_anchor, stacked_anchor + Vector3i(-1, 0, 0), stacked_anchor + Vector3i(-2, 0, 0)]
	var stacked_needed: Array[Vector3i] = []
	for cell: Vector3i in stacked_cells:
		stacked_needed.append(cell)
		stacked_needed.append(cell + Vector3i.DOWN)
	if await _wait_cells(stacked_needed):
		app.session.inventory.try_transaction({}, {"sign_board_large": 1})
		for cell: Vector3i in stacked_cells:
			app.session.world.set_cell(cell + Vector3i.DOWN, InteractionService.DIRT)
		var stacked_placed := app.session.workstations.try_place(WorkstationService.SIGN_BOARD_LARGE_ENTITY, stacked_anchor, app.session.world.query_cell, AABB(), 1)
		var stacked_id := str(stacked_placed.get("details", {}).get("station", {}).get("instance_id", ""))
		var stacked_configured := app.session.configure_sign(stacked_id, {"mode": "header_body",
			"text_a": "DEFENSE RANGE", "text_b": "Siege weapons and ammunition.",
			"text_c": "Every weapon on its own mount.\nAmmunition in the chest beside it.\nTargets down the range."})
		# The board runs from the anchor along -x at this rotation, so the eye
		# stands on its centre line, five metres out, at standing height.
		app.session.player.global_position = Vector3(19.5, 1.1, 39.5)
		app.session.player.look_at(Vector3(19.5, 1.0 + GameSession.SIGN_GROUND_BOARD_HEIGHT, 34.5), Vector3.UP)
		app.session.inventory.select_hotbar(4)
		await _settle_frames(6)
		app.session._hide_placement_preview()
		await _settle_frames(24)
		var stacked_sizes := _stacked_sizes(stacked_id)
		var stacked_ok: bool = bool(stacked_placed.get("ok", false)) and bool(stacked_configured.get("ok", false)) \
			and float(stacked_sizes.get("header", 0.0)) > float(stacked_sizes.get("subheader", 0.0)) \
			and float(stacked_sizes.get("subheader", 0.0)) > float(stacked_sizes.get("body", 0.0)) \
			and await _save_viewport(stacked_path)
		_record("T232_SIGN_STACKED_PRESENTATION", stacked_ok,
			"rendered evidence shows the three-cell district board at head height on a full post, its header, subheader and body stacked and readable from five metres at standing eye height",
			{"path": stacked_path, "placed": stacked_placed.get("reason", ""), "sizes": stacked_sizes,
			"eye": Vector3(19.5, 1.1, 39.5), "distance_m": 5.0})
	else:
		_record("T232_SIGN_STACKED_PRESENTATION", false, "the district board cells loaded for the capture", {"path": stacked_path})


func _move_to_hotbar(item_id: String, target: int) -> int:
	var source := _slot_for(item_id)
	if source < 0:
		return target
	if source != target:
		app.session.inventory.swap_slots(source, target)
	return target


func _slot_for(item_id: String) -> int:
	for index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[index].get("item_id", "")) == item_id:
			return index
	return -1


func _find_label(root: Node) -> Label3D:
	if root == null:
		return null
	for child in root.get_children():
		if child is Label3D:
			return child
		var nested := _find_label(child)
		if nested != null:
			return nested
	return null


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


## Waits (up to ~10 s) for the placement ghost to exist; the exported build
## runs more frames per second than the editor, so a fixed frame count is not
## a reliable wait for terrain streaming and the aim raycast.
func _wait_for_ghost(ghost_name: String, minimum_cells: int = 1) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var ghost := app.session._placement_preview
		if ghost != null and str(ghost.name) == ghost_name and ghost.get_child_count() >= minimum_cells:
			return true
		await get_tree().process_frame
	return false


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


func _settle_frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _save_viewport(path: String) -> bool:
	return await _save_viewport_sized(path, Vector2i(1280, 720))


func _save_viewport_sized(path: String, expected_size: Vector2i) -> bool:
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	return image != null and image.get_size() == expected_size and image.save_png(path) == OK


## Measures the in-game hotbar against the visible canvas: bottom margin of at
## least 8 px, every slot square, inside the viewport, and every visible
## control inside its slot rect (half-pixel tolerance).
func _hotbar_containment() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	var hotbar_rect := app.gameplay_hotbar.get_global_rect()
	var bottom_ok := hotbar_rect.end.y <= viewport_size.y - 8.0
	var square_ok := true
	var inside_ok := true
	var children_ok := true
	var slot_sizes: Array = []
	for slot in app.gameplay_hotbar_slots:
		var rect := slot.get_global_rect()
		slot_sizes.append(rect.size)
		if not is_equal_approx(rect.size.x, rect.size.y):
			square_ok = false
		if rect.position.x < 0.0 or rect.position.y < 0.0 or rect.end.x > viewport_size.x or rect.end.y > viewport_size.y:
			inside_ok = false
		if not _controls_inside(slot, rect):
			children_ok = false
	return {"ok": bottom_ok and square_ok and inside_ok and children_ok, "bottom": hotbar_rect.end.y, "viewport": viewport_size, "hotbar_rect": hotbar_rect, "bottom_ok": bottom_ok, "square_ok": square_ok, "inside_ok": inside_ok, "children_ok": children_ok, "slot_sizes": slot_sizes}


func _controls_inside(root: Node, bounds: Rect2) -> bool:
	for child in root.get_children():
		if child is Control and child.visible:
			var rect: Rect2 = child.get_global_rect()
			if rect.position.x < bounds.position.x - 0.5 or rect.position.y < bounds.position.y - 0.5 or rect.end.x > bounds.end.x + 0.5 or rect.end.y > bounds.end.y + 0.5:
				return false
		if not _controls_inside(child, bounds):
			return false
	return true


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
