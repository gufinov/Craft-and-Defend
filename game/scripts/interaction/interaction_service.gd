class_name InteractionService
extends RefCounted

signal result_reported(result: Dictionary)

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const BEDROCK := 9
const BLOCK_SUPPORT_OFFSETS: Array[Vector3i] = [
	Vector3i(-1, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, 0, -1),
	Vector3i(0, 0, 1),
]

var world: WorldAdapter
var inventory: F0Inventory
var registry: ContentRegistry
var workstations: WorkstationService
var player_body_aabb: Callable
var station_raycast: Callable
var defense_interact: Callable
var placement_rotation_quarters := 0


func _init(
	world_adapter: WorldAdapter,
	player_inventory: F0Inventory,
	body_aabb: Callable,
	content_registry: ContentRegistry = null,
	station_service: WorkstationService = null,
	station_query: Callable = Callable(),
	defense_query: Callable = Callable()
) -> void:
	world = world_adapter
	inventory = player_inventory
	player_body_aabb = body_aabb
	registry = content_registry if content_registry != null else ContentRegistry.new()
	workstations = station_service
	station_raycast = station_query
	defense_interact = defense_query


func try_break_cell(cell: Vector3i, expected_world_revision: int = -1) -> Dictionary:
	if expected_world_revision >= 0 and expected_world_revision != world.revision:
		return _finish(false, "STALE_REVISION")
	var query := world.query_cell(cell)
	if query.get("state") != "LOADED":
		return _finish(false, query.get("state", "UNLOADED"))
	var voxel_id := int(query.get("voxel_id", AIR))
	if voxel_id == AIR:
		return _finish(false, "NO_TARGET")
	var block := registry.block_for_voxel(voxel_id)
	if block.is_empty():
		return _finish(false, "MISSING_CONTENT")
	if bool(block.get("protected", false)):
		return _finish(false, "PROTECTED")
	if workstations != null and workstations.supported_by(cell):
		return _finish(false, "SUPPORT_IN_USE")
	if inventory.active_pick_tier() < int(block.get("min_pick_tier", 0)):
		return _finish(false, "WRONG_TOOL")
	var break_cells: Array[Vector3i] = _axe_log_cells(cell, block)
	var drop_value: Variant = block.get("drop")
	var additions: Dictionary = {} if drop_value == null else {str(drop_value): break_cells.size()}
	if not inventory.can_transaction({}, additions):
		return _finish(false, "INVENTORY_FULL")
	var changed_cells: Array[Vector3i] = []
	for break_cell in break_cells:
		if not world.set_cell(break_cell, AIR):
			for rollback_cell in changed_cells:
				world.set_cell(rollback_cell, voxel_id)
			return _finish(false, "WORLD_WRITE_FAILED")
		changed_cells.append(break_cell)
	var committed := inventory.try_transaction({}, additions)
	if not committed.get("ok", false):
		for rollback_cell in changed_cells:
			world.set_cell(rollback_cell, voxel_id)
		return _finish(false, "INVENTORY_COMMIT_FAILED")
	var reason := "TREE_FELLED" if break_cells.size() > 1 else "OK"
	return _finish(true, reason, {"cell": cell, "cells": break_cells, "voxel_before": voxel_id, "voxel_after": AIR, "drops": additions})


func try_place_item(cell: Vector3i, item_id: String, expected_world_revision: int = -1, rotation_quarters: int = -1) -> Dictionary:
	if expected_world_revision >= 0 and expected_world_revision != world.revision:
		return _finish(false, "STALE_REVISION")
	var rotation := placement_rotation_quarters if rotation_quarters < 0 else rotation_quarters
	var checked := preview_place_item(cell, item_id, rotation)
	if not checked.get("ok", false):
		return _finish(false, str(checked.get("reason", "PLACEMENT_FAILED")))
	var item := registry.item(item_id)
	if checked.get("kind") == "entity":
		if workstations == null:
			return _finish(false, "PLACEMENT_UNAVAILABLE")
		var station_result := workstations.try_place(str(item.places_entity), cell, world.query_cell, player_body_aabb.call(), rotation)
		return _finish(bool(station_result.get("ok", false)), str(station_result.get("reason", "PLACEMENT_FAILED")), station_result.get("details", {}))
	var voxel_id := int(item.places_block)
	if not world.set_cell(cell, voxel_id):
		return _finish(false, "WORLD_WRITE_FAILED")
	var committed := inventory.try_transaction({item_id: 1}, {})
	if not committed.get("ok", false):
		world.set_cell(cell, AIR)
		return _finish(false, "INVENTORY_COMMIT_FAILED")
	return _finish(true, "OK", {"cell": cell, "voxel_before": AIR, "voxel_after": voxel_id, "items": {item_id: -1}})


func preview_place_item(cell: Vector3i, item_id: String, rotation_quarters: int = -1) -> Dictionary:
	var item := registry.item(item_id)
	if item.is_empty() or inventory.count(item_id) < 1:
		return {"ok": false, "reason": "NO_RESOURCE"}
	var rotation := placement_rotation_quarters if rotation_quarters < 0 else rotation_quarters
	if item.has("places_entity"):
		if workstations == null:
			return {"ok": false, "reason": "PLACEMENT_UNAVAILABLE"}
		var entity_id := str(item.places_entity)
		var entity_result := workstations.preview_placement(entity_id, cell, rotation, world.query_cell, player_body_aabb.call())
		return {"ok": bool(entity_result.get("ok", false)), "reason": str(entity_result.get("reason", "PLACEMENT_FAILED")), "kind": "entity", "entity_id": entity_id, "rotation_quarters": rotation}
	if not item.has("places_block"):
		return {"ok": false, "reason": "NOT_PLACEABLE"}
	var query := world.query_cell(cell)
	if query.get("state") != "LOADED":
		return {"ok": false, "reason": str(query.get("state", "UNLOADED"))}
	if int(query.get("voxel_id", AIR)) != AIR or (workstations != null and not workstations.station_at_cell(cell).is_empty()):
		return {"ok": false, "reason": "OCCUPIED"}
	if player_body_aabb.is_valid() and player_body_aabb.call().intersects(AABB(Vector3(cell), Vector3.ONE)):
		return {"ok": false, "reason": "PLAYER_OVERLAP"}
	var support_result := _block_support_result(cell)
	if not support_result.get("ok", false):
		return {"ok": false, "reason": str(support_result.get("reason", "UNSUPPORTED"))}
	return {"ok": true, "reason": "OK", "kind": "block", "voxel_id": int(item.places_block), "rotation_quarters": rotation}


# ---------------------------------------------------------------------------
# P3J drag building. A right-press on a block item anchors a drag; while held,
# the aimed cell stretches the plan into a row (dominant horizontal axis), a
# column (vertical) or a wall (both). Every planned cell is validated on its
# own, with earlier planned cells counting as support so columns and walls can
# rise from one anchor. Blocked cells are skipped; cells beyond what the player
# can afford are trimmed. Release commits one world edit plus one inventory
# transaction; a left-press while dragging cancels with nothing built.
# ---------------------------------------------------------------------------

## Longest run of cells along either axis of one drag.
const DRAG_MAX_SPAN := 16

var _drag: Dictionary = {}


func drag_active() -> bool:
	return not _drag.is_empty()


func begin_drag_place(origin: Vector3, direction: Vector3) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_block"):
		return _finish(false, "NOT_PLACEABLE")
	var hit := world.raycast(origin, direction)
	if hit == null:
		return _finish(false, "NO_TARGET")
	return begin_drag_at(hit.previous_position)


## Anchors a drag for the active block item at a known cell (also used by
## diagnostics that do not aim a camera).
func begin_drag_at(anchor: Vector3i) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_block"):
		return _finish(false, "NOT_PLACEABLE")
	_drag = {"item_id": item_id, "voxel_id": int(item.places_block), "anchor": anchor, "end": anchor, "cells": [], "shape": "single"}
	_replan_drag()
	return {"ok": true, "reason": "DRAG_STARTED", "anchor": anchor}


## Stretches the active drag to `end` (also used by diagnostics).
func set_drag_end(end: Vector3i) -> Dictionary:
	if _drag.is_empty():
		return {"ok": false, "reason": "NO_DRAG"}
	if end != _drag.end:
		_drag.end = end
		_replan_drag()
	return drag_state()


func update_drag_place(origin: Vector3, direction: Vector3) -> Dictionary:
	if _drag.is_empty():
		return {"ok": false, "reason": "NO_DRAG"}
	var hit := world.raycast(origin, direction, 12.0)
	if hit != null:
		return set_drag_end(hit.previous_position)
	# Aim left the terrain (open sky): stretch along the vertical plane of the
	# current row so moving the mouse up builds up (owner playtest 2026-09-18).
	var plane_end := _drag_plane_end(origin, direction)
	if plane_end.has("cell"):
		return set_drag_end(plane_end.cell)
	return drag_state()


## Intersects the aim ray with the vertical plane through the anchor that
## contains the current row axis. With no row yet, the plane faces the camera.
func _drag_plane_end(origin: Vector3, direction: Vector3) -> Dictionary:
	var anchor: Vector3i = _drag.anchor
	var delta: Vector3i = _drag.end - anchor
	var row_axis := 0
	if delta.x == 0 and delta.z == 0:
		row_axis = 0 if absf(direction.z) >= absf(direction.x) else 2
	else:
		row_axis = 0 if absi(delta.x) >= absi(delta.z) else 2
	var normal := Vector3(0.0, 0.0, 1.0) if row_axis == 0 else Vector3(1.0, 0.0, 0.0)
	var plane_point := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	var denominator := direction.dot(normal)
	if absf(denominator) < 0.05:
		return {}
	var distance := (plane_point - origin).dot(normal) / denominator
	if distance <= 0.0 or distance > 24.0:
		return {}
	var point := origin + direction * distance
	var cell := Vector3i(floori(point.x), floori(point.y), floori(point.z))
	if row_axis == 0:
		cell.z = anchor.z
	else:
		cell.x = anchor.x
	return {"cell": cell}


## Planned cells with their state: "ok", "blocked" (invalid, skipped) or
## "unaffordable" (valid but beyond the carried count, trimmed on commit).
func drag_state() -> Dictionary:
	if _drag.is_empty():
		return {"active": false}
	var affordable := 0
	for entry in _drag.cells:
		if str(entry.state) == "ok":
			affordable += 1
	return {"active": true, "item_id": _drag.item_id, "voxel_id": _drag.voxel_id, "anchor": _drag.anchor, "end": _drag.end, "cells": _drag.cells.duplicate(true), "affordable": affordable, "shape": _drag.get("shape", "single")}


func cancel_drag_place() -> Dictionary:
	if _drag.is_empty():
		return {"ok": false, "reason": "NO_DRAG"}
	_drag = {}
	return _finish(false, "DRAG_CANCELLED")


func commit_drag_place(expected_world_revision: int = -1) -> Dictionary:
	if _drag.is_empty():
		return _finish(false, "NO_DRAG")
	if expected_world_revision >= 0 and expected_world_revision != world.revision:
		_drag = {}
		return _finish(false, "STALE_REVISION")
	var item_id: String = _drag.item_id
	var voxel_id: int = _drag.voxel_id
	_replan_drag()
	var cells: Array[Vector3i] = []
	for entry in _drag.cells:
		if str(entry.state) == "ok":
			cells.append(entry.cell)
	_drag = {}
	if cells.is_empty():
		return _finish(false, "DRAG_EMPTY")
	if inventory.count(item_id) < cells.size():
		return _finish(false, "INSUFFICIENT_BLOCKS", {"needed": cells.size(), "have": inventory.count(item_id)})
	var written: Array[Vector3i] = []
	for cell in cells:
		if not world.set_cell(cell, voxel_id):
			for undo in written:
				world.set_cell(undo, AIR)
			return _finish(false, "WORLD_WRITE_FAILED")
		written.append(cell)
	var committed := inventory.try_transaction({item_id: cells.size()}, {})
	if not committed.get("ok", false):
		for undo in written:
			world.set_cell(undo, AIR)
		return _finish(false, "INVENTORY_COMMIT_FAILED")
	return _finish(true, "DRAG_PLACED", {"cells": cells, "count": cells.size(), "voxel_after": voxel_id, "items": {item_id: -cells.size()}})


## Cells between anchor and end in support-first order: outward along the
## horizontal axis, upward along y, so each cell can rest on the one before it.
func drag_plan_cells(anchor: Vector3i, end: Vector3i) -> Dictionary:
	var delta := end - anchor
	var horizontal_axis := 0 if absi(delta.x) >= absi(delta.z) else 2
	var horizontal_span := clampi(delta[horizontal_axis], -(DRAG_MAX_SPAN - 1), DRAG_MAX_SPAN - 1)
	var vertical_span := clampi(delta.y, -(DRAG_MAX_SPAN - 1), DRAG_MAX_SPAN - 1)
	var horizontal_step := signi(horizontal_span)
	var vertical_step := signi(vertical_span)
	var cells: Array[Vector3i] = []
	var shape := "single"
	if horizontal_span != 0 and vertical_span != 0:
		shape = "wall"
	elif horizontal_span != 0:
		shape = "row"
	elif vertical_span != 0:
		shape = "column"
	for v in range(0, absi(vertical_span) + 1):
		for h in range(0, absi(horizontal_span) + 1):
			var cell := anchor
			cell[horizontal_axis] += h * horizontal_step
			cell.y += v * vertical_step
			cells.append(cell)
	return {"cells": cells, "shape": shape}


func _replan_drag() -> void:
	var plan := drag_plan_cells(_drag.anchor, _drag.end)
	_drag.shape = plan.shape
	var planned: Dictionary = {}
	var budget: int = inventory.count(str(_drag.item_id))
	var entries: Array[Dictionary] = []
	for cell in plan.cells:
		var reason := _drag_cell_reason(cell, planned)
		var state := "ok"
		if reason != "OK":
			state = "blocked"
		elif budget <= 0:
			state = "unaffordable"
		else:
			budget -= 1
		if state == "ok":
			planned[cell] = true
		entries.append({"cell": cell, "state": state, "reason": reason})
	_drag.cells = entries


## Same rules as preview_place_item for a block, except that cells already
## planned in this drag count as support for later cells.
func _drag_cell_reason(cell: Vector3i, planned: Dictionary) -> String:
	var query := world.query_cell(cell)
	if query.get("state") != "LOADED":
		return str(query.get("state", "UNLOADED"))
	if int(query.get("voxel_id", AIR)) != AIR or (workstations != null and not workstations.station_at_cell(cell).is_empty()):
		return "OCCUPIED"
	if player_body_aabb.is_valid() and player_body_aabb.call().intersects(AABB(Vector3(cell), Vector3.ONE)):
		return "PLAYER_OVERLAP"
	for offset: Vector3i in BLOCK_SUPPORT_OFFSETS:
		if planned.has(cell + offset):
			return "OK"
	var support := _block_support_result(cell)
	return "OK" if support.get("ok", false) else str(support.get("reason", "UNSUPPORTED"))


func try_place_dirt(cell: Vector3i, expected_world_revision: int = -1) -> Dictionary:
	return try_place_item(cell, "dirt", expected_world_revision)


func _block_support_result(cell: Vector3i) -> Dictionary:
	var saw_unloaded_neighbor := false
	for offset: Vector3i in BLOCK_SUPPORT_OFFSETS:
		var neighbor := world.query_cell(cell + offset)
		var state := str(neighbor.get("state", "UNLOADED"))
		if state == "LOADED" and int(neighbor.get("voxel_id", AIR)) != AIR:
			return {"ok": true, "reason": "OK", "support_cell": cell + offset}
		if state == "UNLOADED":
			saw_unloaded_neighbor = true
	return {"ok": false, "reason": "UNLOADED" if saw_unloaded_neighbor else "UNSUPPORTED"}


func try_dismantle_station(instance_id: String) -> Dictionary:
	if workstations == null:
		return _finish(false, "NO_ENTITY")
	var result := workstations.try_dismantle(instance_id, world.query_cell, player_body_aabb.call())
	return _finish(bool(result.get("ok", false)), str(result.get("reason", "DISMANTLE_FAILED")), result.get("details", {}))


func break_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	var station_id := _station_from_view(origin, direction)
	if not station_id.is_empty():
		return try_dismantle_station(station_id)
	var hit := world.raycast(origin, direction)
	if hit == null:
		return _finish(false, "NO_TARGET")
	return try_break_cell(hit.position)


func place_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	var hit := world.raycast(origin, direction)
	if hit == null:
		return _finish(false, "NO_TARGET")
	return try_place_item(hit.previous_position, inventory.active_item_id())


func placement_preview_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if item.is_empty() or (not item.has("places_entity") and not item.has("places_block")):
		return {"visible": false}
	var hit := world.raycast(origin, direction)
	if hit == null:
		return {"visible": false, "reason": "NO_TARGET"}
	var anchor: Vector3i = hit.previous_position
	var checked := preview_place_item(anchor, item_id, placement_rotation_quarters)
	return {
		"visible": true,
		"ok": bool(checked.get("ok", false)),
		"reason": str(checked.get("reason", "PLACEMENT_FAILED")),
		"item_id": item_id,
		"kind": str(checked.get("kind", "entity" if item.has("places_entity") else "block")),
		"entity_id": str(checked.get("entity_id", "")),
		"voxel_id": int(checked.get("voxel_id", item.get("places_block", AIR))),
		"anchor": anchor,
		"rotation_quarters": placement_rotation_quarters,
	}


func _axe_log_cells(cell: Vector3i, block: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = [cell]
	if str(block.get("id", "")) != "log":
		return result
	var active_tool := registry.item(inventory.active_item_id())
	if str(active_tool.get("tool_kind", "")) != "axe":
		return result
	var bottom := cell
	var maximum_trunk_blocks := maxi(1, registry.balance_integer("harvesting.maximum_connected_trunk_blocks", 6))
	for _step in range(maximum_trunk_blocks - 1):
		var below := bottom + Vector3i.DOWN
		var below_query := world.query_cell(below)
		if below_query.get("state") != "LOADED" or str(registry.block_for_voxel(int(below_query.get("voxel_id", AIR))).get("id", "")) != "log":
			break
		bottom = below
	result.clear()
	for step in range(maximum_trunk_blocks):
		var candidate := bottom + Vector3i.UP * step
		var candidate_query := world.query_cell(candidate)
		if candidate_query.get("state") != "LOADED" or str(registry.block_for_voxel(int(candidate_query.get("voxel_id", AIR))).get("id", "")) != "log":
			break
		if workstations != null and workstations.supported_by(candidate):
			break
		result.append(candidate)
	return result if not result.is_empty() else [cell]


func rotate_placement(direction: int = 1) -> int:
	placement_rotation_quarters = posmod(placement_rotation_quarters + signi(direction), 4)
	return placement_rotation_quarters


func secondary_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	var station_id := _station_from_view(origin, direction)
	if not station_id.is_empty() and not workstations.station_type(station_id).is_empty():
		return _finish(true, "OPEN_STATION", {"instance_id": station_id, "station": workstations.station(station_id)})
	return place_from_view(origin, direction)


## Right-press: open a station, start a block drag, or place an entity at once.
func secondary_press_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	if drag_active():
		return {"ok": false, "reason": "DRAG_ACTIVE"}
	var station_id := _station_from_view(origin, direction)
	if not station_id.is_empty() and not workstations.station_type(station_id).is_empty():
		return _finish(true, "OPEN_STATION", {"instance_id": station_id, "station": workstations.station(station_id)})
	var item := registry.item(inventory.active_item_id())
	if item.has("places_block"):
		return begin_drag_place(origin, direction)
	return place_from_view(origin, direction)


## Right-release: commit the drag, if one is active.
func secondary_release_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	if not drag_active():
		return {"ok": false, "reason": "NO_DRAG"}
	update_drag_place(origin, direction)
	return commit_drag_place()


func interact_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	if defense_interact.is_valid():
		var defense_result: Dictionary = defense_interact.call(origin, direction)
		if defense_result.get("handled", false):
			return _finish(bool(defense_result.get("ok", false)), str(defense_result.get("reason", "REPAIR_FAILED")), defense_result.get("changes", {}))
	var station_id := _station_from_view(origin, direction)
	if station_id.is_empty() or workstations.station_type(station_id).is_empty():
		return _finish(false, "NO_STATION")
	return _finish(false, "SECONDARY_REQUIRED", {"instance_id": station_id, "station": workstations.station(station_id)})


func _station_from_view(origin: Vector3, direction: Vector3) -> String:
	if not station_raycast.is_valid():
		return ""
	return str(station_raycast.call(origin, direction))


func _finish(ok: bool, reason: String, changes: Dictionary = {}) -> Dictionary:
	var result := {"ok": ok, "reason": reason, "changes": changes, "world_revision": world.revision, "inventory_revision": inventory.revision, "dirt": inventory.dirt}
	result_reported.emit(result)
	return result
