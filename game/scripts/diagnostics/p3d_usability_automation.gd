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
	# Cancel: nothing built, nothing consumed; empty inventory refuses to start a plan with affordable cells.
	inventory.try_transaction({}, {"dirt": 5})
	var revision_before: int = app.session.world.revision
	interaction.begin_drag_at(Vector3i(-2, 0, 46))
	interaction.set_drag_end(Vector3i(-6, 0, 46))
	var cancelled := interaction.cancel_drag_place()
	var cancel_ok: bool = str(cancelled.get("reason", "")) == "DRAG_CANCELLED" and not interaction.drag_active() 		and app.session.world.revision == revision_before and inventory.count("dirt") == 5 		and int(app.session.world.query_cell(Vector3i(-4, 0, 46)).get("voxel_id", 0)) == 0
	_record("T108_DRAG_BUILD", row_ok and column_ok and wall_ok and cancel_ok, "a right-drag plans a row, column or wall of the held block with support-first ordering, skips blocked cells, trims to the carried count, commits as one world edit plus one inventory transaction, and cancels with nothing built", {"row": row_plan, "row_commit": row_commit.get("reason"), "column": column_commit.get("reason"), "wall_blocked": blocked, "wall_unaffordable": unaffordable, "wall_commit": wall_commit.get("reason"), "cancel": cancelled.get("reason"), "dirt": inventory.count("dirt")})


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
	_record("T83_PRESENTATION", axe_image_ok and block_image_ok and ghost_visible, "rendered evidence shows the held axe beside the real iron marker and a low held block with its world placement ghost", {"axe_path": axe_path, "block_path": block_path, "size": get_viewport().get_visible_rect().size, "ghost_visible": ghost_visible})

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
