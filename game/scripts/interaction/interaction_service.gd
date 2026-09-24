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
		if not creative:
			return _finish(false, "INVENTORY_FULL")
		additions = {}
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


## Undo (owner 2026-09-20: "when I place something big improperly, it takes
## forever to chop it down"): every placement - a single piece or block, or a
## whole lay tool commit - is recorded as the stations it created, the
## voxels it changed and the pack's net change; `undo_last` reverses the
## newest one (pieces removed without their own refund, voxels restored,
## the items the lay cost handed back, its drops taken back). UNDO_DEPTH deep.
const UNDO_DEPTH := 12
var _undo: Array[Dictionary] = []


func undo_count() -> int:
	return _undo.size()


func _pack_counts() -> Dictionary:
	var counts: Dictionary = {}
	for slot: Dictionary in inventory.slots:
		var slot_item := str(slot.get("item_id", ""))
		if slot_item.is_empty():
			continue
		counts[slot_item] = int(counts.get(slot_item, 0)) + int(slot.get("count", 0))
	return counts


## Voxel ids of the cells a placement may touch (the cells themselves and
## whatever auto-clear would mine), before it happens.
func _undo_snapshot(cells: Array[Vector3i]) -> Dictionary:
	var voxels: Dictionary = {}
	for cell: Vector3i in cells:
		if voxels.has(cell):
			continue
		var query := world.query_cell(cell)
		if query.get("state") == "LOADED":
			voxels[cell] = int(query.get("voxel_id", 0))
	return {"stations": workstations.stations.keys() if workstations != null else [], "voxels": voxels, "pack": _pack_counts()}


## After a successful placement: what changed since `snapshot` becomes an
## undo entry (nothing recorded when nothing changed).
func _undo_record(snapshot: Dictionary, label: String) -> void:
	var before_ids: Array = snapshot.get("stations", [])
	var created: Array[String] = []
	if workstations != null:
		for instance_id: String in workstations.stations:
			if not before_ids.has(instance_id):
				created.append(instance_id)
	var voxels: Array[Dictionary] = []
	var before_voxels: Dictionary = snapshot.get("voxels", {})
	for cell: Vector3i in before_voxels:
		var now := int(world.query_cell(cell).get("voxel_id", before_voxels[cell]))
		if now != int(before_voxels[cell]):
			voxels.append({"cell": cell, "before": int(before_voxels[cell]), "after": now})
	var items: Dictionary = {}
	var before_pack: Dictionary = snapshot.get("pack", {})
	var after_pack := _pack_counts()
	for item_id: String in before_pack:
		var delta := int(after_pack.get(item_id, 0)) - int(before_pack[item_id])
		if delta != 0:
			items[item_id] = delta
	for item_id: String in after_pack:
		if not before_pack.has(item_id):
			items[item_id] = int(after_pack[item_id])
	var restore: Array[Dictionary] = _undo_restore
	_undo_restore = []
	if created.is_empty() and voxels.is_empty():
		return
	_undo.append({"label": label, "stations": created, "voxels": voxels, "items": items, "restore": restore})
	while _undo.size() > UNDO_DEPTH:
		_undo.pop_front()


## Reverses the newest placement. Pieces already gone are skipped; a voxel
## is restored only if it still holds what the placement wrote; the refund
## is what the pack can take (creative: whatever fits, no complaint).
func undo_last() -> Dictionary:
	if _undo.is_empty():
		return _finish(false, "NOTHING_TO_UNDO")
	var entry: Dictionary = _undo.pop_back()
	if not _drag.is_empty():
		_drag = {}
	var stamps_before := int(entry.get("stamps_before", -1))
	if stamps_before >= 0 and stamps_before < _stamps.size():
		_stamps.resize(stamps_before)
	var removed := 0
	for instance_id: String in entry.get("stations", []):
		if workstations == null or not workstations.stations.has(instance_id):
			continue
		var gone := workstations.try_dismantle(instance_id, world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB(), false)
		if gone.get("ok", false):
			removed += 1
	# Plain rails an auto-shape replaced (docs/COASTER_RAILS.md, Auto-shape):
	# back in place, free, once the shaped pieces are gone.
	var replaced := 0
	for record: Dictionary in entry.get("restore", []):
		var back := workstations.try_place(str(record.get("entity_id", CoasterRails.FLAT)), record.get("anchor", Vector3i.ZERO), world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB(), int(record.get("rotation_quarters", 0)), {"_free": true})
		if back.get("ok", false):
			replaced += 1
	var restored := 0
	for change: Dictionary in entry.get("voxels", []):
		var cell: Vector3i = change.cell
		if int(world.query_cell(cell).get("voxel_id", -1)) == int(change.after) and world.set_cell(cell, int(change.before)):
			restored += 1
	var refunds: Dictionary = {}
	var take_back: Dictionary = {}
	var items: Dictionary = entry.get("items", {})
	for item_id: String in items:
		var delta := int(items[item_id])
		if delta < 0:
			refunds[item_id] = -delta
		elif delta > 0 and mini(delta, inventory.count(item_id)) > 0:
			take_back[item_id] = mini(delta, inventory.count(item_id))
	var refunded := inventory.try_transaction(take_back, refunds)
	if not refunded.get("ok", false):
		# The pack cannot take the whole refund: give back what fits, one
		# item kind at a time (creative packs are full by design).
		inventory.try_transaction(take_back, {})
		for item_id: String in refunds:
			var amount := int(refunds[item_id])
			while amount > 0 and not inventory.can_transaction({}, {item_id: amount}):
				amount -= 1
			if amount > 0:
				inventory.try_transaction({}, {item_id: amount})
	return _finish(true, "UNDONE", {"label": str(entry.get("label", "")), "removed": removed, "restored": restored, "replaced": replaced, "refunds": refunds, "taken_back": take_back, "remaining": _undo.size()})


func try_place_item(cell: Vector3i, item_id: String, expected_world_revision: int = -1, rotation_quarters: int = -1) -> Dictionary:
	var checked_first := preview_place_item(cell, item_id, placement_rotation_quarters if rotation_quarters < 0 else rotation_quarters)
	var touched: Array[Vector3i] = [cell]
	for clear_cell in checked_first.get("clear", []):
		if clear_cell is Vector3i:
			touched.append(clear_cell)
	var snapshot := _undo_snapshot(touched)
	var placed := _try_place_item(cell, item_id, expected_world_revision, rotation_quarters)
	if placed.get("ok", false):
		if str(registry.item(item_id).get("places_entity", "")) == CoasterRails.FLAT:
			_auto_shape_result(placed, _auto_shape_rails([cell] as Array[Vector3i]))
		_undo_record(snapshot, item_id)
	return placed


func _try_place_item(cell: Vector3i, item_id: String, expected_world_revision: int = -1, rotation_quarters: int = -1) -> Dictionary:
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
		var clearing: Dictionary = {}
		var to_clear: Array[Vector3i] = []
		for clear_cell in checked.get("clear", []):
			if clear_cell is Vector3i:
				to_clear.append(clear_cell)
		if not to_clear.is_empty():
			clearing = clear_cells_for_track(to_clear)
		var station_result := workstations.try_place(str(item.places_entity), cell, world.query_cell, player_body_aabb.call(), rotation)
		var details: Dictionary = (station_result.get("details", {}) as Dictionary).duplicate()
		if int(clearing.get("cleared", 0)) > 0:
			details["cleared"] = int(clearing.cleared)
			details["drops"] = clearing.drops
		return _finish(bool(station_result.get("ok", false)), str(station_result.get("reason", "PLACEMENT_FAILED")), details)
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
		var clear_cells: Array[Vector3i] = []
		if not entity_result.get("ok", false):
			var plan := auto_clear_plan(entity_id, cell, rotation, str(entity_result.get("reason", "PLACEMENT_FAILED")))
			if plan.get("ok", false):
				entity_result = {"ok": true, "reason": "OK"}
				clear_cells = plan.cells
		return {"ok": bool(entity_result.get("ok", false)), "reason": str(entity_result.get("reason", "PLACEMENT_FAILED")), "kind": "entity", "entity_id": entity_id, "rotation_quarters": rotation, "clear": clear_cells}
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

## Snap to a track end (owner playtest 2026-09-21 item 2: "give the piece it
## is going to attach to a color highlight ... indicating that a connect was
## made"): while a track ghost follows the aim, an aimed cell within this
## many cells (horizontal, same level or one up / down) of an open track
## end's free joint cell moves the ghost's entry onto that cell and turns it
## to leave the end; `drag_state().snap` names the piece for the highlight.
## A 45-degree curve end has no placement rotation and is never snapped to.
const SNAP_REACH := 1.6


func drag_active() -> bool:
	return not _drag.is_empty()


## True when the held item lays track that can join an open end.
func is_track_item(item_id: String) -> bool:
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_entity"):
		return false
	var entity_id := str(item.places_entity)
	return CoasterRails.is_track_id(entity_id) or not str(registry.entity(entity_id).get("coaster_tool", "")).is_empty()


## The nearest open track end whose free joint cell lies within SNAP_REACH
## of `raw` ({instance_id, cell, next, along}), or {} when none is in reach.
func find_snap(raw: Vector3i) -> Dictionary:
	if workstations == null or raw == Vector3i.MAX:
		return {}
	var best: Dictionary = {}
	var best_distance := SNAP_REACH
	for end: Dictionary in CoasterRails.open_ends(CoasterRails.track_records(workstations.stations)):
		var next: Vector3i = end.next
		if absi(next.y - raw.y) > 1:
			continue
		var along: Vector3 = end.along
		if absf(along.x) > 0.3 and absf(along.z) > 0.3:
			continue
		var distance := Vector2(float(next.x - raw.x), float(next.z - raw.z)).length()
		if distance < best_distance:
			best_distance = distance
			best = end
	return best


## Moves the active ghost's entry to `raw`, or onto the open end it snaps
## to (turning the piece to leave that end); returns true when the entry,
## the rotation or the snap changed so the caller replans.
func _follow_anchor(raw: Vector3i) -> bool:
	if raw == Vector3i.MAX:
		return false
	var snap := find_snap(raw)
	var anchor := raw
	var snapped: Dictionary = {}
	if not snap.is_empty():
		anchor = snap.next
		snapped = {"instance_id": str(snap.instance_id), "cell": snap.cell, "next": snap.next}
		placement_rotation_quarters = facing_quarters(snap.along)
	var changed: bool = anchor != _drag.anchor or snapped != _drag.get("snap", {}) or placement_rotation_quarters != int(_drag.get("rotation", placement_rotation_quarters))
	_drag.anchor = anchor
	_drag.snap = snapped
	return changed


func begin_drag_place(origin: Vector3, direction: Vector3) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if item.has("places_entity") and (is_linear_entity_item(item_id) or is_coaster_loop_item(item_id) or is_climb_item(item_id) or is_curve_tool_item(item_id) or is_curve_item(item_id)):
		var anchor := placement_anchor_from_view(origin, direction)
		if anchor == Vector3i.MAX:
			return _finish(false, "NO_TARGET")
		if not is_linear_entity_item(item_id):
			# Coaster tools (owner 2026-09-20, "the item should start from
			# where I place and extend towards its rotated direction"): the
			# aimed cell is the ENTRY and the piece heads the way the player
			# faces, so the ghost is seen from its entry; W / R still turn it
			# and a Shift-drag re-aims it.
			placement_rotation_quarters = facing_quarters(direction)
		# Snap to a track end: a press near an open end starts the piece on
		# the end's free joint cell, heading out of it (a rail line too: its
		# entry snaps, its end follows the aim as before).
		var snap := find_snap(anchor) if is_track_item(item_id) else {}
		if not snap.is_empty():
			anchor = snap.next
			placement_rotation_quarters = facing_quarters(snap.along)
		var started: Dictionary
		if is_coaster_loop_item(item_id):
			started = begin_coaster_loop_at(anchor)
		elif is_curve_item(item_id):
			started = begin_curve_at(anchor)
		elif is_climb_item(item_id):
			started = begin_climb_at(anchor)
		elif is_curve_tool_item(item_id):
			started = begin_curve_tool_at(anchor)
		else:
			started = begin_entity_line_at(anchor)
		if not snap.is_empty() and not _drag.is_empty():
			_drag.snap = {"instance_id": str(snap.instance_id), "cell": snap.cell, "next": snap.next}
		return started
	if item.is_empty() or not item.has("places_block"):
		return _finish(false, "NOT_PLACEABLE")
	var hit := world.raycast(origin, direction)
	if hit == null:
		return _finish(false, "NO_TARGET")
	return begin_drag_at(hit.previous_position)


## The placement rotation whose travel direction best matches `direction`
## (horizontal part; a straight-down aim keeps the current rotation).
func facing_quarters(direction: Vector3) -> int:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.05:
		return placement_rotation_quarters
	flat = flat.normalized()
	var best := placement_rotation_quarters
	var best_dot := -2.0
	for quarters in range(4):
		var dot := flat.dot(Vector3(CoasterRails.switch_along(quarters)))
		if dot > best_dot:
			best_dot = dot
			best = quarters
	return best


## The rotation that heads along the dominant horizontal axis of `span`
## (MAX-less: the current rotation when the span is too short to tell).
func _span_quarters(span: Vector3i, minimum: int = 2) -> int:
	if maxi(absi(span.x), absi(span.z)) < minimum:
		return placement_rotation_quarters
	var axis := Vector3i(signi(span.x), 0, 0) if absi(span.x) >= absi(span.z) else Vector3i(0, 0, signi(span.z))
	for quarters in range(4):
		if CoasterRails.switch_along(quarters) == axis:
			return quarters
	return placement_rotation_quarters


## Rails, walkway slabs and merlons (`linear: true` in content) lay in one
## straight horizontal line by drag; they never stack (no Shift).
func is_linear_entity_item(item_id: String) -> bool:
	var item := registry.item(item_id)
	if not item.has("places_entity"):
		return false
	return bool(registry.entity(str(item.places_entity)).get("linear", false))


func begin_entity_line_at(anchor: Vector3i) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if not is_linear_entity_item(item_id) or workstations == null:
		return _finish(false, "NOT_PLACEABLE")
	_drag = {"mode": "entity_line", "item_id": item_id, "entity_id": str(item.places_entity), "voxel_id": 0, "anchor": anchor, "end": anchor, "cells": [], "shape": "single"}
	_replan_entity_line()
	return {"ok": true, "reason": "DRAG_STARTED", "anchor": anchor}


## Cells from anchor to end along the dominant horizontal axis, at the
## anchor's height, each validated as an entity placement with the rotation
## that follows the line (rails auto-align).
func _replan_entity_line() -> void:
	var anchor: Vector3i = _drag.anchor
	var end: Vector3i = _drag.end
	var delta := end - anchor
	var axis := 0 if absi(delta.x) >= absi(delta.z) else 2
	var span := clampi(delta[axis], -(DRAG_MAX_SPAN - 1), DRAG_MAX_SPAN - 1)
	var step := 1 if span >= 0 else -1
	var rotation := 1 if axis == 0 else 0
	_drag.rotation = rotation
	_drag.shape = "single" if span == 0 else "row"
	var budget: int = inventory.count(str(_drag.item_id))
	var entries: Array[Dictionary] = []
	var count := absi(span) + 1
	for index in range(count):
		var cell := anchor
		cell[axis] += index * step
		var check := workstations.preview_placement(str(_drag.entity_id), cell, rotation, world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB())
		var reason := str(check.get("reason", "PLACEMENT_FAILED"))
		var clear_plan := {"ok": false, "cells": []} if check.get("ok", false) else auto_clear_plan(str(_drag.entity_id), cell, rotation, reason)
		var state := "ok"
		if not check.get("ok", false) and not clear_plan.get("ok", false):
			state = "blocked"
		elif budget <= 0:
			state = "unaffordable"
		else:
			budget -= 1
			if clear_plan.get("ok", false):
				state = "clear"
		entries.append({"cell": cell, "state": state, "reason": reason, "voxel_id": 0, "item_id": str(_drag.item_id), "entity_id": str(_drag.entity_id), "clear": clear_plan.cells})
	_drag.cells = entries


## Anchors a drag for the active block item at a known cell (also used by
## diagnostics that do not aim a camera).
func begin_drag_at(anchor: Vector3i) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_block"):
		return _finish(false, "NOT_PLACEABLE")
	_drag = {"mode": "drag", "item_id": item_id, "voxel_id": int(item.places_block), "anchor": anchor, "end": anchor, "cells": [], "shape": "single"}
	_replan_drag()
	return {"ok": true, "reason": "DRAG_STARTED", "anchor": anchor}


## Stretches the active drag to `end` (also used by diagnostics).
func set_drag_end(end: Vector3i) -> Dictionary:
	if _drag.is_empty() or str(_drag.get("mode", "drag")) not in ["drag", "entity_line"]:
		return {"ok": false, "reason": "NO_DRAG"}
	if str(_drag.get("mode", "drag")) == "entity_line":
		end.y = _drag.anchor.y
	if end != _drag.end:
		_drag.end = end
		if str(_drag.get("mode", "drag")) == "entity_line":
			_replan_entity_line()
		else:
			_replan_drag()
	return drag_state()


## `vertical` (Shift held, owner direction 2026-09-18): the horizontal extent
## is frozen and only the height follows the aim, so "drag sideways, hold
## Shift, drag up" raises a wall without needing an obstruction behind it.
func update_drag_place(origin: Vector3, direction: Vector3, vertical: bool = false) -> Dictionary:
	if _drag.is_empty():
		return {"ok": false, "reason": "NO_DRAG"}
	if str(_drag.get("mode", "drag")) == "blueprint":
		# A blueprint follows the aimed placement cell instead of stretching.
		var aimed := world.raycast(origin, direction, 12.0)
		if aimed != null:
			var snapped := snap_to_socket(aimed.previous_position, str(_drag.blueprint_id))
			move_blueprint(snapped.cell)
			_drag.snapped = bool(snapped.snapped)
		return drag_state()
	if str(_drag.get("mode", "drag")) == "climb":
		# The whole climb follows the aim; W / R and 4-9 / X / C replan it.
		# Shift held: the entry stays put and the aim sets both the length
		# (its distance ahead along the heading) and the rise (its height
		# above or below the entry - aim at a hillside to climb onto it).
		if vertical:
			var reach := placement_anchor_from_view(origin, direction, 80.0)
			if reach == Vector3i.MAX:
				var plane := _drag_plane_end(origin, direction)
				if plane.has("cell"):
					reach = plane.cell
			if reach != Vector3i.MAX:
				# The drag's direction is the climb's heading (a climb dragged
				# behind the entry heads the other way - owner 2026-09-20).
				var span: Vector3i = reach - _drag.anchor
				placement_rotation_quarters = _span_quarters(span)
				var along := CoasterRails.switch_along(placement_rotation_quarters)
				set_climb(span.x * along.x + span.z * along.z, span.y)
			return drag_state()
		if _follow_anchor(placement_anchor_from_view(origin, direction, 12.0)):
			_replan_climb()
		return drag_state()
	if CURVE_TOOL_MODES.has(str(_drag.get("mode", "drag"))):
		# Rail Switch / Crossing (CoasterCraft cards 2-3): the ghost follows
		# the aim; Shift held: the entry stays put and the aim's offset from it
		# sets the length (forward) and the lanes (sideways, negative = left).
		if vertical:
			var reach := placement_anchor_from_view(origin, direction, 80.0)
			if reach == Vector3i.MAX:
				var floor_end := _drag_floor_end(origin, direction)
				if floor_end.has("cell"):
					reach = floor_end.cell
			if reach != Vector3i.MAX:
				var span: Vector3i = reach - _drag.anchor
				var along := CoasterRails.switch_along(placement_rotation_quarters)
				var forward: int = span.x * along.x + span.z * along.z
				if forward <= -2:
					# Dragged behind the entry: the piece heads that way instead.
					placement_rotation_quarters = posmod(placement_rotation_quarters + 2, 4)
					along = CoasterRails.switch_along(placement_rotation_quarters)
					forward = -forward
				var side := CoasterRails.switch_side(placement_rotation_quarters)
				var sideways: int = span.x * side.x + span.z * side.z
				set_curve_size(forward, sideways)
			return drag_state()
		if _follow_anchor(placement_anchor_from_view(origin, direction, 12.0)):
			_replan_curve_tool()
		return drag_state()
	if str(_drag.get("mode", "drag")) == "loop_element":
		# The whole-loop ghost follows the aim; W / R and 4-9 replan it.
		# Shift held (owner 2026-09-20, "Shift drag"): the entry stays put and
		# the aim's distance from it sets the true loop's diameter.
		if vertical and loop_true:
			var reach := placement_anchor_from_view(origin, direction, 80.0)
			if reach == Vector3i.MAX:
				var plane := _drag_plane_end(origin, direction)
				if plane.has("cell"):
					reach = plane.cell
			if reach != Vector3i.MAX:
				# The drag's direction is the loop's heading, its length the diameter.
				placement_rotation_quarters = _span_quarters(reach - _drag.anchor)
				var span := Vector3(reach - _drag.anchor)
				span.y = 0.0
				set_loop_diameter(int(round(span.length())))
				_replan_loop_element()
			return drag_state()
		if _follow_anchor(placement_anchor_from_view(origin, direction, 12.0)):
			_replan_loop_element()
		return drag_state()
	if str(_drag.get("mode", "drag")) == "curve":
		# The whole-curve ghost follows the aim; W / R and 4-9 replan it.
		# Shift held: the entry stays put; the aim's direction from it picks
		# the sweep (45 / 90 / 135 / 180 by its angle from the travel
		# direction) and its side (left of travel mirrors the bend); the
		# aim's distance sets the radius (half of it).
		if vertical:
			var reach := placement_anchor_from_view(origin, direction, 80.0)
			if reach == Vector3i.MAX:
				var plane := _drag_plane_end(origin, direction)
				if plane.has("cell"):
					reach = plane.cell
			if reach != Vector3i.MAX:
				var span := Vector3(reach - _drag.anchor)
				span.y = 0.0
				if span.length() >= 1.5:
					var along: Vector3 = _drag.get("along", Vector3.FORWARD)
					var right: Vector3 = _drag.get("right", Vector3.RIGHT)
					var ahead := span.dot(along)
					var sideways := span.dot(right)
					curve_sweep = CoasterRails.curve_sweep_snap(rad_to_deg(atan2(absf(sideways), ahead)))
					curve_left = sideways < 0.0
					curve_radius = curve_radius_limit(roundi(span.length() * 0.5))
					_replan_curve()
			return drag_state()
		if _follow_anchor(placement_anchor_from_view(origin, direction, 12.0)):
			_replan_curve()
		return drag_state()
	if str(_drag.get("mode", "drag")) == "entity_line":
		var line_anchor := placement_anchor_from_view(origin, direction, 12.0)
		if line_anchor != Vector3i.MAX:
			return set_drag_end(line_anchor)
		var line_plane := _drag_plane_end(origin, direction)
		if line_plane.has("cell"):
			return set_drag_end(line_plane.cell)
		return drag_state()
	# Once Shift raised the drag, it stays vertical until release.
	if vertical:
		_drag.vertical_latched = true
	if vertical or bool(_drag.get("vertical_latched", false)):
		var vertical_end := _drag_plane_end(origin, direction)
		if vertical_end.has("cell"):
			var current: Vector3i = _drag.end
			var lifted: Vector3i = vertical_end.cell
			return set_drag_end(Vector3i(current.x, lifted.y, current.z))
		return drag_state()
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
		if str(entry.state) in ["ok", "clear"]:
			affordable += 1
	var costs: Dictionary = {}
	for entry in _drag.cells:
		if str(entry.state) in ["ok", "clear"]:
			var entry_item := str(entry.get("item_id", _drag.get("item_id", "")))
			costs[entry_item] = int(costs.get(entry_item, 0)) + 1
	return {"active": true, "snapped": bool(_drag.get("snapped", false)), "mode": str(_drag.get("mode", "drag")), "blueprint_id": str(_drag.get("blueprint_id", "")), "rotation_quarters": int(_drag.get("rotation", 0)), "item_id": str(_drag.get("item_id", "")), "voxel_id": int(_drag.get("voxel_id", 0)), "anchor": _drag.anchor, "end": _drag.get("end", _drag.anchor), "cells": _drag.cells.duplicate(true), "affordable": affordable, "costs": costs, "shape": _drag.get("shape", "single"), "loop_size": loop_diameter if loop_true else loop_size, "loop_true": loop_true, "loop_radius": float(_drag.get("radius", 0.0)), "loop_cells": int(_drag.get("loop_cells", 0)), "climb_length": climb_length, "climb_rise": climb_rise, "curve_length": int(_drag.get("curve_length", 0)), "curve_lanes": int(_drag.get("curve_lanes", 0)), "curve_cells": int(_drag.get("curve_cells", 0)), "curve_radius": curve_radius, "curve_sweep": curve_sweep, "curve_left": curve_left, "curve_exit": _drag.get("curve_exit", _drag.anchor), "curve_diagonal_entry": bool(_drag.get("diagonal_entry", false)), "snap": (_drag.get("snap", {}) as Dictionary).duplicate()}


func cancel_drag_place() -> Dictionary:
	if _drag.is_empty():
		return {"ok": false, "reason": "NO_DRAG"}
	_drag = {}
	return _finish(false, "DRAG_CANCELLED")


func commit_drag_place(expected_world_revision: int = -1) -> Dictionary:
	if _drag.is_empty():
		return _finish(false, "NO_DRAG")
	var touched: Array[Vector3i] = []
	for entry in _drag.cells:
		touched.append(Vector3i(entry.cell))
		for clear_cell in entry.get("clear", []):
			if clear_cell is Vector3i:
				touched.append(clear_cell)
	var label := str(_drag.get("mode", "drag"))
	var line_entity := str(_drag.get("entity_id", "")) if label == "entity_line" else ""
	var stamps_before := _stamps.size()
	var snapshot := _undo_snapshot(touched)
	var committed := _commit_drag_place(expected_world_revision)
	if committed.get("ok", false):
		if line_entity == CoasterRails.FLAT:
			var laid: Array[Vector3i] = []
			for laid_cell in committed.get("changes", {}).get("cells", []):
				if laid_cell is Vector3i:
					laid.append(laid_cell)
			_auto_shape_result(committed, _auto_shape_rails(laid))
		_undo_record(snapshot, label)
		# Undoing a stamp has to forget the piece as well, or its sockets keep
		# attracting the next one to a wall that is no longer there.
		if label == "blueprint" and not _undo.is_empty():
			_undo[_undo.size() - 1]["stamps_before"] = stamps_before
	return committed


func _commit_drag_place(expected_world_revision: int = -1) -> Dictionary:
	if _drag.is_empty():
		return _finish(false, "NO_DRAG")
	if expected_world_revision >= 0 and expected_world_revision != world.revision:
		_drag = {}
		return _finish(false, "STALE_REVISION")
	var mode := str(_drag.get("mode", "drag"))
	var default_item := str(_drag.get("item_id", ""))
	var default_voxel := int(_drag.get("voxel_id", AIR))
	if mode == "entity_line":
		return _commit_entity_line()
	if mode == "loop_element":
		return _commit_loop_element()
	if mode == "climb":
		return _commit_climb()
	if CURVE_TOOL_MODES.has(mode):
		return _commit_curve_tool()
	if mode == "curve":
		return _commit_curve()
	if mode == "blueprint":
		_replan_blueprint()
	else:
		_replan_drag()
	var cells: Array[Vector3i] = []
	var voxels: Array[int] = []
	var pieces: Array[Dictionary] = []
	var removals: Dictionary = {}
	for entry in _drag.cells:
		if str(entry.state) != "ok":
			continue
		var entry_item := str(entry.get("item_id", default_item))
		removals[entry_item] = int(removals.get(entry_item, 0)) + 1
		var entry_entity := str(entry.get("entity_id", ""))
		if entry_entity.is_empty():
			cells.append(entry.cell)
			voxels.append(int(entry.get("voxel_id", default_voxel)))
		else:
			# Defence sets: kit entity cells are placed after the voxels, so
			# the course they stand on already exists. `_drag.cells` is
			# ordered bottom-up, which is what a stack of stairs needs.
			pieces.append({"cell": entry.cell, "entity_id": entry_entity, "rotation_quarters": int(entry.get("rotation_quarters", 0)), "item_id": entry_item})
	var blueprint_id := str(_drag.get("blueprint_id", ""))
	var stamp_anchor: Vector3i = _drag.anchor
	var stamp_rotation := int(_drag.get("rotation", 0))
	_drag = {}
	if cells.is_empty() and pieces.is_empty():
		return _finish(false, "DRAG_EMPTY")
	for needed_item: String in removals:
		if inventory.count(needed_item) < int(removals[needed_item]):
			return _finish(false, "INSUFFICIENT_BLOCKS", {"item_id": needed_item, "needed": int(removals[needed_item]), "have": inventory.count(needed_item)})
	var written: Array[Vector3i] = []
	for index in range(cells.size()):
		if not world.set_cell(cells[index], voxels[index]):
			for undo in written:
				world.set_cell(undo, AIR)
			return _finish(false, "WORLD_WRITE_FAILED")
		written.append(cells[index])
	# One stamp is one purchase: the entity pieces are placed `_free` and the
	# single transaction below pays for them together with the blocks, so the
	# whole kit is one atomic cost and one undo step. Anything that refuses
	# takes the whole stamp back out again.
	var raised: Array[String] = []
	var player_aabb: AABB = player_body_aabb.call() if player_body_aabb.is_valid() else AABB()
	for piece in pieces:
		var placed := workstations.try_place(str(piece.entity_id), piece.cell, world.query_cell, player_aabb, int(piece.rotation_quarters), {"_free": true})
		if not placed.get("ok", false):
			_revert_stamped_pieces(raised, player_aabb)
			for undo in written:
				world.set_cell(undo, AIR)
			return _finish(false, "PLACEMENT_FAILED", {"cell": piece.cell, "entity_id": str(piece.entity_id), "reason_detail": str(placed.get("reason", ""))})
		raised.append(str(placed.get("details", {}).get("station", {}).get("instance_id", "")))
	var committed := inventory.try_transaction(removals, {})
	if not committed.get("ok", false):
		_revert_stamped_pieces(raised, player_aabb)
		for undo in written:
			world.set_cell(undo, AIR)
		return _finish(false, "INVENTORY_COMMIT_FAILED")
	var items: Dictionary = {}
	for spent_item: String in removals:
		items[spent_item] = -int(removals[spent_item])
	if mode == "blueprint":
		_stamps.append({"blueprint_id": blueprint_id, "anchor": [stamp_anchor.x, stamp_anchor.y, stamp_anchor.z], "rotation": stamp_rotation})
	return _finish(true, "BLUEPRINT_STAMPED" if mode == "blueprint" else "DRAG_PLACED", {"cells": cells, "count": cells.size() + raised.size(), "entities": raised.duplicate(), "voxel_after": default_voxel, "items": items, "blueprint_id": blueprint_id, "stamps": _stamps.size()})


## Takes a half-finished stamp's entity pieces back out, newest first so a
## stacked pair of stairs releases from the top. No refund: the transaction
## that would have paid for them has not run (or has just failed).
func _revert_stamped_pieces(instance_ids: Array[String], player_aabb: AABB) -> void:
	for index in range(instance_ids.size() - 1, -1, -1):
		var instance_id := instance_ids[index]
		if not instance_id.is_empty():
			workstations.try_dismantle(instance_id, world.query_cell, player_aabb, false)


func _commit_entity_line() -> Dictionary:
	var entity_id := str(_drag.get("entity_id", ""))
	var rotation := int(_drag.get("rotation", 0))
	var cells: Array[Vector3i] = []
	for entry in _drag.cells:
		if str(entry.state) in ["ok", "clear"]:
			cells.append(entry.cell)
	var to_clear := _clear_cells_of(_drag.cells)
	var item_id := str(_drag.get("item_id", ""))
	_drag = {}
	if cells.is_empty():
		return _finish(false, "DRAG_EMPTY")
	var clearing := clear_cells_for_track(to_clear)
	var placed := 0
	for cell in cells:
		var result := workstations.try_place(entity_id, cell, world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB(), rotation)
		if result.get("ok", false):
			placed += 1
	if placed == 0:
		return _finish(false, "PLACEMENT_FAILED")
	return _finish(true, "LINE_PLACED", {"cells": cells, "count": placed, "entity_id": entity_id, "items": {item_id: -placed}, "cleared": int(clearing.cleared), "drops": clearing.drops})


# ---------------------------------------------------------------------------
# Auto-shape (owner playtest 2026-09-21, items 3b + 4: "These 90 degree
# corners should be created automatically, no piece needed ... Any time 2
# rail blocks touch, we should be able to auto course correct and make them
# merge"). Plain `rail` pieces stay the wire the player lays; after every
# plain-rail placement (a single rail, or a rail line) `_auto_shape_rails`
# looks at the plain-rail graph around the laid cells and, where a pattern
# matches, replaces the matching plain rails IN PLACE with curve pieces
# (`rail_loop` records carrying a TrackCurve, laid free exactly like the
# curve tools), the plain rails dismantled without refund: the cell count
# never changes, the pack never changes, the rails are simply "course
# corrected". Always on; no item, no setting.
#
# Patterns (AUTO_SHAPE_PATTERNS, tried in that order; flat, one level, plain
# rails only - never a curve piece, a slope, a junction cell with three or
# more joins, or a rail carrying a kettle / cart):
# - "elbow": a corner cell C joined to exactly two plain rails A and B at a
#   right angle, each continuing straight one more plain rail (A2 beyond A,
#   B2 beyond B). A, C, B become a quarter arc of radius 1.5 centred on the
#   corner of the 2x2 block opposite C (the owner's sketch: the arc enters
#   through A's far edge, crosses C, leaves through B's far edge; the
#   fourth cell of the block stays empty). It needs the straights: a corner
#   laid alone stays plain until both straights exist.
# - "lane_shift": a plain-rail run ending at E and a run in the next lane
#   over starting at S diagonally ahead of E (S = E + along + side), both
#   at least three cells long and straight: the three cells ending at E and
#   the three starting at S become one s-bend (TrackCurve.make_s_bend over
#   six cells, one lane), joining the rails beyond both ends.
# Nothing else auto-shapes: a "+" of two lines stays a crossroads, a T stays
# a T. To add a pattern: append its name here and a `_auto_shape_<name>`
# branch in `_auto_shape_match` returning {kind, cells, pieces}.
# Undo: the pass runs inside the placement's undo window; the dismantled
# plain rails are kept on the entry ("restore") and re-laid free by
# `undo_last` after the shaped pieces are removed.
# ---------------------------------------------------------------------------

const AUTO_SHAPE_PATTERNS: Array[String] = ["elbow", "lane_shift"]
const AUTO_SHAPE_ELBOW_RADIUS := 1.5
const AUTO_SHAPE_SHIFT_RUN := 3
## Plain rails the last auto-shape dismantled, attached to the next undo entry.
var _undo_restore: Array[Dictionary] = []
## Optional: returns the track cells riders (carts, kettles) are on right now
## (Array[Vector3i]); a rail under a rider is never reshaped.
var rider_cells: Callable = Callable()


## Marks a placement result with what the pass did (the feedback line).
func _auto_shape_result(result: Dictionary, shaping: Dictionary) -> void:
	var kinds: Array = shaping.get("shaped", [])
	if kinds.is_empty():
		return
	var changes: Dictionary = result.get("changes", {})
	changes["shaped"] = kinds.duplicate()
	changes["shaped_cells"] = shaping.get("cells", [])
	result["changes"] = changes
	result["reason"] = "RAILS_SHAPED_LANE_SHIFT" if str(kinds[kinds.size() - 1]) == "lane_shift" else "RAILS_SHAPED_ELBOW"


## The pass: every pattern, on every plain rail within two cells of what was
## just laid (a pattern must include at least one laid cell). Returns
## {shaped: [kinds], cells: [replaced cells], count}.
func _auto_shape_rails(laid: Array[Vector3i]) -> Dictionary:
	var shaped: Array[String] = []
	var replaced: Array[Vector3i] = []
	if workstations == null or laid.is_empty():
		return {"shaped": shaped, "cells": replaced, "count": 0}
	var candidates: Array[Vector3i] = []
	for cell: Vector3i in laid:
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var near := cell + Vector3i(dx, 0, dz)
				if not candidates.has(near):
					candidates.append(near)
	for pattern: String in AUTO_SHAPE_PATTERNS:
		for cell: Vector3i in candidates:
			if replaced.has(cell):
				continue
			var found := _auto_shape_match(pattern, cell, laid)
			if found.is_empty():
				continue
			if _auto_shape_apply(found):
				shaped.append(str(found.kind))
				for done: Vector3i in found.cells:
					replaced.append(done)
	return {"shaped": shaped, "cells": replaced, "count": replaced.size()}


## The plain-rail record at `cell` ({} for anything else).
func _plain_rail_at(cell: Vector3i, tracks: Dictionary) -> Dictionary:
	var record: Dictionary = tracks.get(cell, {})
	if str(record.get("entity_id", "")) != CoasterRails.FLAT:
		return {}
	return record


## True when a kettle, cart or car stands or rides on the rail at `cell`.
func _rail_carries_rider(cell: Vector3i) -> bool:
	if not workstations.station_at_cell(cell + Vector3i.UP).is_empty():
		return true
	if rider_cells.is_valid():
		var riding: Variant = rider_cells.call()
		if riding is Array and (riding as Array).has(cell):
			return true
	return false


## A plain rail at `cell` whose joins (mutual rule) are exactly `expected`,
## carrying no rider: the record, or {}.
func _plain_rail_joined(cell: Vector3i, expected: Array[Vector3i], tracks: Dictionary) -> Dictionary:
	var record := _plain_rail_at(cell, tracks)
	if record.is_empty() or _rail_carries_rider(cell):
		return {}
	var joined := CoasterRails.connected_cells(record, tracks)
	if joined.size() != expected.size():
		return {}
	for other: Vector3i in expected:
		if not joined.has(other):
			return {}
	return record


## A straight plain-rail run: `cell` joins `next` and, if it has a second
## join, that join is `behind` (the run continuing straight, never a branch).
func _plain_rail_straight(cell: Vector3i, next: Vector3i, behind: Vector3i, tracks: Dictionary) -> bool:
	var record := _plain_rail_at(cell, tracks)
	if record.is_empty():
		return false
	var joined := CoasterRails.connected_cells(record, tracks)
	if not joined.has(next) or joined.size() > 2:
		return false
	for other: Vector3i in joined:
		if other != next and other != behind:
			return false
	return true


static func _quarters_along(direction: Vector3i) -> int:
	for quarters in range(4):
		if CoasterRails.switch_along(quarters) == direction:
			return quarters
	return 0


## `rail_loop` pieces of `curve` restricted to `wanted` (the curve starts and
## ends on cell faces, so a sample on a face may land in the cell beyond;
## those zero-width spans are dropped and the end pieces' ranges stretched
## to the curve's ends). [] unless the pieces cover exactly `wanted`.
func _curve_pieces_within(curve: Dictionary, wanted: Array[Vector3i], rotation: int, before: Vector3i, after: Vector3i) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	for span: Dictionary in TrackCurve.cells(curve, 720):
		var cell: Vector3i = span.cell
		if not wanted.has(cell):
			continue
		if not spans.is_empty() and Vector3i(spans[spans.size() - 1].cell) == cell:
			spans[spans.size() - 1].t1 = float(span.t1)
			continue
		spans.append({"cell": cell, "t0": float(span.t0), "t1": float(span.t1)})
	if spans.size() != wanted.size():
		return []
	for cell: Vector3i in wanted:
		var present := false
		for span: Dictionary in spans:
			if Vector3i(span.cell) == cell:
				present = true
		if not present:
			return []
	spans[0].t0 = 0.0
	spans[spans.size() - 1].t1 = 1.0
	var out: Array[Dictionary] = []
	for index in range(spans.size()):
		var span: Dictionary = spans[index]
		var joints: Array[Vector3i] = []
		joints.append(Vector3i(spans[index - 1].cell) if index > 0 else before)
		joints.append(Vector3i(spans[index + 1].cell) if index + 1 < spans.size() else after)
		out.append({"cell": Vector3i(span.cell), "entity_id": CoasterRails.LOOP, "rotation": rotation, "joints": joints, "extra": {"curve": curve, "t0": float(span.t0), "t1": float(span.t1)}})
	return out


## One pattern at one candidate cell: {kind, cells (the plain rails to
## replace, in ride order), pieces (their curve pieces)} or {}.
func _auto_shape_match(pattern: String, cell: Vector3i, laid: Array[Vector3i]) -> Dictionary:
	var tracks := CoasterRails.track_records(workstations.stations)
	match pattern:
		"elbow":
			return _auto_shape_elbow(cell, laid, tracks)
		"lane_shift":
			return _auto_shape_lane_shift(cell, laid, tracks)
	return {}


func _auto_shape_elbow(corner: Vector3i, laid: Array[Vector3i], tracks: Dictionary) -> Dictionary:
	var record := _plain_rail_at(corner, tracks)
	if record.is_empty() or _rail_carries_rider(corner):
		return {}
	var joined := CoasterRails.connected_cells(record, tracks)
	if joined.size() != 2:
		return {}
	var a: Vector3i = joined[0]
	var b: Vector3i = joined[1]
	var along := corner - a
	var side := b - corner
	if along.y != 0 or side.y != 0 or along.length_squared() != 1 or side.length_squared() != 1 or along.x * side.x + along.z * side.z != 0:
		return {}
	var a2 := a - along
	var b2 := b + side
	if _plain_rail_joined(a, [corner, a2] as Array[Vector3i], tracks).is_empty() or _plain_rail_joined(b, [corner, b2] as Array[Vector3i], tracks).is_empty():
		return {}
	if _plain_rail_at(a2, tracks).is_empty() or _plain_rail_at(b2, tracks).is_empty():
		return {}
	var involved := false
	for cell: Vector3i in [a2, a, corner, b, b2]:
		if laid.has(cell):
			involved = true
	if not involved:
		return {}
	var centre := Vector3(corner) + Vector3(0.5, 0.55, 0.5) - Vector3(along) * AUTO_SHAPE_ELBOW_RADIUS + Vector3(side) * AUTO_SHAPE_ELBOW_RADIUS
	var curve := TrackCurve.make_arc(centre, Vector3(along), Vector3(side), AUTO_SHAPE_ELBOW_RADIUS, 0.0, 90.0)
	var cells: Array[Vector3i] = [a, corner, b]
	var pieces := _curve_pieces_within(curve, cells, _quarters_along(along), a2, b2)
	if pieces.is_empty():
		return {}
	return {"kind": "elbow", "cells": cells, "pieces": pieces}


func _auto_shape_lane_shift(end: Vector3i, laid: Array[Vector3i], tracks: Dictionary) -> Dictionary:
	for along: Vector3i in CoasterRails.HORIZONTAL:
		var right := Vector3i(Vector3(along).cross(Vector3.UP).round())
		for side: Vector3i in [right, -right]:
			var start := end + along + side
			# The two run ends: E joins only the cell behind it, S only the
			# cell ahead (plain rails never join diagonally).
			if _plain_rail_joined(end, [end - along] as Array[Vector3i], tracks).is_empty() or _plain_rail_joined(start, [start + along] as Array[Vector3i], tracks).is_empty():
				continue
			if _plain_rail_joined(end - along, [end, end - along * 2] as Array[Vector3i], tracks).is_empty() or _plain_rail_joined(start + along, [start, start + along * 2] as Array[Vector3i], tracks).is_empty():
				continue
			if not _plain_rail_straight(end - along * 2, end - along, end - along * 3, tracks) or not _plain_rail_straight(start + along * 2, start + along, start + along * 3, tracks):
				continue
			if _rail_carries_rider(end - along * 2) or _rail_carries_rider(start + along * 2):
				continue
			var cells: Array[Vector3i] = [end - along * 2, end - along, end, start, start + along, start + along * 2]
			var involved := false
			for cell: Vector3i in cells:
				if laid.has(cell):
					involved = true
			if not involved:
				continue
			var origin := Vector3(cells[0]) + Vector3(0.5, 0.55, 0.5) - Vector3(along) * 0.5
			var curve := TrackCurve.make_s_bend(origin, Vector3(along), Vector3(side), float(AUTO_SHAPE_SHIFT_RUN * 2), 1.0, 0.0)
			var pieces := _curve_pieces_within(curve, cells, _quarters_along(along), end - along * 3, start + along * 3)
			if pieces.is_empty():
				continue
			return {"kind": "lane_shift", "cells": cells, "pieces": pieces}
	return {}


## Replaces the match's plain rails with its pieces: dismantle (no refund),
## lay free; on any failure the plain rails go back and nothing changes.
func _auto_shape_apply(found: Dictionary) -> bool:
	var aabb: AABB = player_body_aabb.call() if player_body_aabb.is_valid() else AABB()
	var removed: Array[Dictionary] = []
	for cell: Vector3i in found.cells:
		var station_id := workstations.station_at_cell(cell)
		var record := workstations.station(station_id).duplicate(true)
		var gone := workstations.try_dismantle(station_id, world.query_cell, aabb, false)
		if not gone.get("ok", false):
			_auto_shape_restore(removed, aabb)
			return false
		removed.append(record)
	var laid: Array[String] = []
	for piece: Dictionary in found.pieces:
		var cell: Vector3i = piece.cell
		var joints: Array = []
		for joint in piece.get("joints", []):
			if joint is Vector3i:
				var offset: Vector3i = joint - cell
				joints.append([offset.x, offset.y, offset.z])
		var extra: Dictionary = (piece.get("extra", {}) as Dictionary).duplicate()
		extra["coaster_joints"] = joints
		extra["auto_shaped"] = str(found.kind)
		extra["_free"] = true
		var result := workstations.try_place(str(piece.entity_id), cell, world.query_cell, aabb, int(piece.rotation), extra)
		if not result.get("ok", false):
			for placed_id: String in laid:
				workstations.try_dismantle(placed_id, world.query_cell, aabb, false)
			_auto_shape_restore(removed, aabb)
			return false
		laid.append(str(result.get("details", {}).get("station", {}).get("instance_id", "")))
	for record: Dictionary in removed:
		_undo_restore.append({"entity_id": str(record.get("entity_id", CoasterRails.FLAT)), "anchor": record.get("anchor", Vector3i.ZERO), "rotation_quarters": int(record.get("rotation_quarters", 0))})
	return true


func _auto_shape_restore(records: Array[Dictionary], aabb: AABB) -> void:
	for record: Dictionary in records:
		workstations.try_place(str(record.get("entity_id", CoasterRails.FLAT)), record.get("anchor", Vector3i.ZERO), world.query_cell, aabb, int(record.get("rotation_quarters", 0)), {"_free": true})


# ---------------------------------------------------------------------------
# Coaster rails: the Loop element (owner 2026-09-20). With `rail_loop` held,
# a right-press shows the ghost of a COMPLETE loop with its foundation at
# the aim: two lane switchers (entry lane -> base row -> exit lane), a slope
# at each end of the base rising outward, and the circle continuing the
# slopes' 45-degree incline over the top. Number keys 4-9 (or X / C) set
# the base width while the ghost is shown; W / R turn it. Release lays every
# piece for one Rail Loop item; a blocked cell (tree, hill, block) shows red
# and nothing is laid.
# ---------------------------------------------------------------------------

const LOOP_SIZE_MIN := 4
const LOOP_SIZE_MAX := 9
const LOOP_SIZE_DEFAULT := 4
var loop_size := LOOP_SIZE_DEFAULT
## The classic (foundation) loop's ring fit: C, raised half a block (owner
## pick 2026-09-20).
var loop_lift_index := 2
## The true loop (owner 2026-09-20): a helix that touches the ground only at
## its entry and its exit one lane over. Default; L switches to the classic
## foundation loop and back. Its size is the circle's diameter in cells,
## set by Shift-drag (aim distance from the entry) or 4-9 / X / C.
var loop_true := true
var loop_diameter := 8
## Creative (the sandbox, later a game mode): loops cost nothing and are not
## capped by the pack; in the real game each true-loop piece costs one Rail
## Loop item from anywhere in the pack, so the biggest loop is as big as the
## pack allows (owner 2026-09-20), and never taller than the world.
var creative := false
## Track auto-clear (CoasterCraft card 6, docs/COASTER_RAILS.md): the
## "Track auto-clear" setting. When on, every track lay tool treats a cell
## blocked only by clearable natural terrain as clearable: the ghost shows
## it amber ("clear"), and on commit the blocking voxels are mined first
## (their drops go to the pack, or are lost when it is full), then the piece
## is laid. Water, bedrock, protected blocks, castle stone and planks (the
## player's own building) and entity cells are never cleared; support cells
## (below a slope) are never cleared either.
var auto_clear := false
## Blocks that read as player-built: the world keeps no edit record, so
## these voxels are never cleared wherever they stand.
const NEVER_CLEARED: Array[String] = ["castle_stone", "planks"]


## Whether a voxel may be mined away for a track piece.
func clearable_voxel(voxel_id: int) -> bool:
	if voxel_id == AIR:
		return false
	var block := registry.block_for_voxel(voxel_id)
	if block.is_empty() or bool(block.get("protected", false)) or not bool(block.get("solid", true)):
		return false
	return str(block.get("id", "")) not in NEVER_CLEARED


## With auto-clear on and `entity_id` a track piece refused as OCCUPIED at
## `cell`, the terrain cells the piece would clear: {ok, cells, reason}.
## `ok` only when every occupied cell holds air or clearable terrain (no
## entity, nothing propping another entity) and the placement passes with
## those cells treated as air (its support cells stay as they are).
func auto_clear_plan(entity_id: String, cell: Vector3i, rotation: int, reason: String) -> Dictionary:
	if not auto_clear or reason != "OCCUPIED" or workstations == null or not CoasterRails.is_track_id(entity_id):
		return {"ok": false, "cells": [], "reason": reason}
	var definition := registry.entity(entity_id)
	var cleared: Array[Vector3i] = []
	for offset_value in definition.get("occupied_offsets", [[0, 0, 0]]):
		if not offset_value is Array or (offset_value as Array).size() != 3:
			return {"ok": false, "cells": [], "reason": reason}
		var offset := Vector3i(int(offset_value[0]), int(offset_value[1]), int(offset_value[2]))
		var occupied: Vector3i = cell + workstations.footprints.rotate_offset(offset, rotation)
		var query := world.query_cell(occupied)
		if query.get("state") != "LOADED":
			return {"ok": false, "cells": [], "reason": str(query.get("state", "UNLOADED"))}
		var voxel_id := int(query.get("voxel_id", AIR))
		if voxel_id == AIR:
			continue
		if not clearable_voxel(voxel_id) or workstations.supported_by(occupied) or not workstations.station_at_cell(occupied).is_empty():
			return {"ok": false, "cells": [], "reason": reason}
		cleared.append(occupied)
	if cleared.is_empty():
		return {"ok": false, "cells": [], "reason": reason}
	var check := workstations.preview_placement(entity_id, cell, rotation, masked_query(cleared), player_body_aabb.call() if player_body_aabb.is_valid() else AABB())
	if not check.get("ok", false):
		return {"ok": false, "cells": [], "reason": str(check.get("reason", reason))}
	return {"ok": true, "cells": cleared, "reason": "OK"}


## A world query that reports `cleared` cells as air (the world after the
## clearing), for validating a placement before the terrain is mined.
func masked_query(cleared: Array[Vector3i]) -> Callable:
	return func(cell: Vector3i) -> Dictionary:
		var query := world.query_cell(cell)
		if cleared.has(cell) and query.get("state") == "LOADED":
			return {"state": "LOADED", "voxel_id": AIR}
		return query


## Mines `cells` for a track piece: the voxels become air and their drops
## join the pack as if mined by hand (a full pack loses the drop). Returns
## {cleared, drops}; cells that are already air are skipped.
func clear_cells_for_track(cells: Array[Vector3i]) -> Dictionary:
	var cleared := 0
	var drops: Dictionary = {}
	for cell in cells:
		var query := world.query_cell(cell)
		var voxel_id := int(query.get("voxel_id", AIR))
		if query.get("state") != "LOADED" or voxel_id == AIR or not clearable_voxel(voxel_id):
			continue
		if not world.set_cell(cell, AIR):
			continue
		cleared += 1
		var drop_value: Variant = registry.block_for_voxel(voxel_id).get("drop")
		if drop_value != null:
			drops[str(drop_value)] = int(drops.get(str(drop_value), 0)) + 1
	var banked: Dictionary = {}
	for drop_id: String in drops:
		var count := int(drops[drop_id])
		while count > 0 and not inventory.try_transaction({}, {drop_id: count}).get("ok", false):
			count -= 1
		if count > 0:
			banked[drop_id] = count
	return {"cleared": cleared, "drops": banked}


## The clearable cells of every "clear" ghost entry, in plan order.
func _clear_cells_of(entries: Array) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for entry in entries:
		if str(entry.get("state", "")) != "clear":
			continue
		for cell in entry.get("clear", []):
			if cell is Vector3i and not cells.has(cell):
				cells.append(cell)
	return cells


## The largest diameter at or under `wanted` whose pieces the pack can pay
## for and whose top stays under the world's ceiling.
func loop_diameter_limit(wanted: int) -> int:
	var ceiling := WorldAdapter.WORLD_MIN.y + WorldAdapter.WORLD_SIZE.y - 2
	var anchor: Vector3i = _drag.get("anchor", Vector3i.ZERO) if not _drag.is_empty() else Vector3i.ZERO
	var diameter := clampi(mini(wanted, ceiling - anchor.y), CoasterRails.HELIX_MIN, CoasterRails.HELIX_MAX)
	if creative:
		return diameter
	var budget := inventory.count(str(_drag.get("item_id", inventory.active_item_id())))
	while diameter > CoasterRails.HELIX_MIN and CoasterRails.helix_piece_count(diameter) > budget:
		diameter -= 1
	return diameter


func is_coaster_loop_item(item_id: String) -> bool:
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_entity"):
		return false
	return str(registry.entity(str(item.places_entity)).get("coaster_tool", "")) == "loop"


func begin_coaster_loop_at(anchor: Vector3i) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if not is_coaster_loop_item(item_id) or workstations == null:
		return _finish(false, "NOT_PLACEABLE")
	_drag = {"mode": "loop_element", "item_id": item_id, "entity_id": str(item.places_entity), "voxel_id": 0, "anchor": anchor, "end": anchor, "cells": [], "shape": "loop", "rotation": placement_rotation_quarters, "x_down": false, "c_down": false}
	_replan_loop_element()
	return {"ok": true, "reason": "DRAG_STARTED", "anchor": anchor}


## Number keys 4-9 while the ghost is shown: the base width in cells.
func set_loop_size(size: int) -> Dictionary:
	if loop_true:
		return set_loop_diameter(size)
	loop_size = clampi(size, LOOP_SIZE_MIN, LOOP_SIZE_MAX)
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "loop_element":
		_replan_loop_element()
	return drag_state()



## Raw key states each frame (X smaller, C bigger); edges change the size once.
## L while the ghost shows: true loop <-> classic foundation loop.
func toggle_loop_kind() -> bool:
	loop_true = not loop_true
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "loop_element":
		_replan_loop_element()
	return loop_true


func set_loop_diameter(diameter: int) -> Dictionary:
	loop_diameter = loop_diameter_limit(diameter)
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "loop_element":
		_replan_loop_element()
	return drag_state()


func coaster_loop_keys(x_pressed: bool, c_pressed: bool) -> void:
	if _drag.is_empty():
		return
	var mode := str(_drag.get("mode", ""))
	if mode == "climb":
		# The Climb: X lowers the rise by one, C raises it (negative = descent).
		if x_pressed and not bool(_drag.get("x_down", false)):
			set_climb_rise(climb_rise - 1)
		if c_pressed and not bool(_drag.get("c_down", false)):
			set_climb_rise(climb_rise + 1)
		_drag.x_down = x_pressed
		_drag.c_down = c_pressed
		return
	if mode != "loop_element" and not CURVE_TOOL_MODES.has(mode):
		return
	var x_edge := x_pressed and not bool(_drag.get("x_down", false))
	var c_edge := c_pressed and not bool(_drag.get("c_down", false))
	_drag.x_down = x_pressed
	_drag.c_down = c_pressed
	if CURVE_TOOL_MODES.has(mode):
		if x_edge:
			set_curve_length(curve_length() - 1)
		if c_edge:
			set_curve_length(curve_length() + 1)
		return
	if x_edge:
		set_loop_size((loop_diameter if loop_true else loop_size) - 1)
	if c_edge:
		set_loop_size((loop_diameter if loop_true else loop_size) + 1)


## Every piece of the element validated at its cell (loop pieces float, the
## foundation needs ground); the ghost carries each piece's entity.
func _replan_loop_element() -> void:
	var rotation := placement_rotation_quarters
	_drag.rotation = rotation
	var layout: Dictionary = CoasterRails.helix_layout(_drag.anchor, rotation, loop_diameter) if loop_true else CoasterRails.loop_element_layout(_drag.anchor, rotation, loop_size, CoasterRails.LOOP_LIFTS[loop_lift_index])
	var affordable: bool = creative or inventory.count(str(_drag.item_id)) >= (layout.pieces.size() if loop_true else 1)
	var entries: Array[Dictionary] = []
	for piece: Dictionary in layout.pieces:
		var cell: Vector3i = piece.cell
		var entity_id := str(piece.entity_id)
		var check := workstations.preview_placement(entity_id, cell, int(piece.rotation), world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB())
		var clear_plan := {"ok": false, "cells": []} if check.get("ok", false) else auto_clear_plan(entity_id, cell, int(piece.rotation), str(check.get("reason", "PLACEMENT_FAILED")))
		var state := "ok"
		if not check.get("ok", false) and not clear_plan.get("ok", false):
			state = "blocked"
		elif not affordable:
			state = "unaffordable"
		elif clear_plan.get("ok", false):
			state = "clear"
		entries.append({"cell": cell, "state": state, "reason": str(check.get("reason", "PLACEMENT_FAILED")), "voxel_id": 0, "item_id": str(_drag.item_id), "entity_id": entity_id, "rotation": int(piece.rotation), "joints": piece.joints, "extra": piece.extra, "clear": clear_plan.cells})
	_drag.cells = entries
	_drag.loop_cells = layout.pieces.size()
	_drag.radius = layout.radius


## All pieces or nothing, for one Rail Loop item; the pieces are laid free
## (`_free`) since the item paid for the element.
func _commit_loop_element() -> Dictionary:
	var item_id := str(_drag.get("item_id", ""))
	var entries: Array = _drag.cells
	_drag = {}
	for entry in entries:
		if str(entry.state) not in ["ok", "clear"]:
			return _finish(false, "LOOP_BLOCKED" if str(entry.state) == "blocked" else "NO_RESOURCE", {"cell": entry.cell, "why": entry.reason})
	var price := 0 if creative else (entries.size() if loop_true else 1)
	if price > 0:
		var paid := inventory.try_transaction({item_id: price}, {})
		if not paid.get("ok", false):
			return _finish(false, str(paid.get("reason", "NO_RESOURCE")))
	var clearing := clear_cells_for_track(_clear_cells_of(entries))
	var cells: Array[Vector3i] = []
	for entry in entries:
		var cell: Vector3i = entry.cell
		var joints: Array = []
		for joint in entry.get("joints", []):
			if joint is Vector3i:
				var offset: Vector3i = joint - cell
				joints.append([offset.x, offset.y, offset.z])
		var extra: Dictionary = (entry.get("extra", {}) as Dictionary).duplicate()
		extra["coaster_joints"] = joints
		extra["_free"] = true
		var result := workstations.try_place(str(entry.entity_id), cell, world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB(), int(entry.rotation), extra)
		if not result.get("ok", false):
			return _finish(false, str(result.get("reason", "PLACEMENT_FAILED")), {"cells": cells, "cell": cell})
		cells.append(cell)
	return _finish(true, "LOOP_PLACED", {"cells": cells, "count": cells.size(), "size": loop_diameter if loop_true else loop_size, "items": {item_id: -price}, "cleared": int(clearing.cleared), "drops": clearing.drops})


# ---------------------------------------------------------------------------
# CoasterCraft cards 2 and 3 (docs/COASTERCRAFT_TRACKS.md): the Rail Switch
# (`rail_switch`, coaster_tool "bend" - the smooth lane switcher; owner
# 2026-09-20: "the Rail Switch should be updated to be smooth", replacing the
# four-piece blocky drag) and the Crossing (`rail_cross`, "cross").
# A right-press with either held ghosts the whole piece at the aim as
# `rail_loop` records riding a TrackCurve s-bend (CoasterRails.bend_layout /
# cross_layout); W / R turn it; X / C and 4-9 set the length; Shift held
# sizes it by the aim (forward = length 3..40, sideways = lanes -6..6,
# negative = to the left of travel). Release lays every piece or nothing
# for one item per piece (creative: free); the length is capped by the pack
# exactly like the true loop (`curve_length_limit`).
# ---------------------------------------------------------------------------

const CURVE_TOOL_MODES: Array[String] = ["smooth_bend", "rail_cross"]
var bend_length := CoasterRails.BEND_DEFAULT_LENGTH
var bend_lanes := CoasterRails.BEND_DEFAULT_LANES
var cross_length := CoasterRails.CROSS_DEFAULT_LENGTH
var cross_lanes := CoasterRails.CROSS_DEFAULT_LANES


func is_smooth_bend_item(item_id: String) -> bool:
	return _coaster_tool_of(item_id) == "bend"


func is_rail_cross_item(item_id: String) -> bool:
	return _coaster_tool_of(item_id) == "cross"


func is_curve_tool_item(item_id: String) -> bool:
	return is_smooth_bend_item(item_id) or is_rail_cross_item(item_id)


func _coaster_tool_of(item_id: String) -> String:
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_entity"):
		return ""
	return str(registry.entity(str(item.places_entity)).get("coaster_tool", ""))


## The active curve tool's mode ("" when no curve drag is active).
func curve_tool_mode() -> String:
	if _drag.is_empty():
		return ""
	var mode := str(_drag.get("mode", ""))
	return mode if CURVE_TOOL_MODES.has(mode) else ""


func curve_length() -> int:
	return cross_length if curve_tool_mode() == "rail_cross" else bend_length


func curve_lanes() -> int:
	return cross_lanes if curve_tool_mode() == "rail_cross" else bend_lanes


func begin_curve_tool_at(anchor: Vector3i) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if not is_curve_tool_item(item_id) or workstations == null:
		return _finish(false, "NOT_PLACEABLE")
	var mode := "rail_cross" if is_rail_cross_item(item_id) else "smooth_bend"
	_drag = {"mode": mode, "item_id": item_id, "entity_id": str(item.places_entity), "voxel_id": 0, "anchor": anchor, "end": anchor, "cells": [], "shape": mode, "rotation": placement_rotation_quarters, "x_down": false, "c_down": false}
	_replan_curve_tool()
	return {"ok": true, "reason": "DRAG_STARTED", "anchor": anchor}


## The pieces a curve tool would lay at `anchor` for the given size.
func curve_tool_layout(mode: String, anchor: Vector3i, rotation: int, length: int, lanes: int) -> Dictionary:
	if mode == "rail_cross":
		return CoasterRails.cross_layout(anchor, rotation, length, lanes)
	return CoasterRails.bend_layout(anchor, rotation, length, lanes)


func curve_tool_piece_count(mode: String, length: int, lanes: int) -> int:
	return (curve_tool_layout(mode, Vector3i.ZERO, 0, length, lanes).cells as Array).size()


## The longest length at or under `wanted` whose pieces the pack can pay for
## (creative: only the 3..40 clamp).
func curve_length_limit(wanted: int, lanes: int = 0) -> int:
	var mode := curve_tool_mode()
	if mode.is_empty():
		mode = "smooth_bend"
	if lanes == 0:
		lanes = curve_lanes()
	var length := CoasterRails.bend_length_clamp(wanted)
	if creative:
		return length
	var budget := inventory.count(str(_drag.get("item_id", inventory.active_item_id())))
	while length > CoasterRails.BEND_MIN_LENGTH and curve_tool_piece_count(mode, length, lanes) > budget:
		length -= 1
	return length


func set_curve_length(length: int) -> Dictionary:
	return set_curve_size(length, curve_lanes())


func set_curve_lanes(lanes: int) -> Dictionary:
	return set_curve_size(curve_length(), lanes)


## Length (3..40, pack-capped) and lanes (-6..6, never 0) of the active
## curve tool - or of the Rail Switch when none is active.
func set_curve_size(length: int, lanes: int) -> Dictionary:
	var mode := curve_tool_mode()
	lanes = CoasterRails.bend_lanes_clamp(lanes, curve_lanes())
	length = curve_length_limit(length, lanes)
	if mode == "rail_cross":
		cross_length = length
		cross_lanes = lanes
	else:
		bend_length = length
		bend_lanes = lanes
	if not mode.is_empty():
		_replan_curve_tool()
	return drag_state()


## Every piece validated at its cell (curve pieces float); amber when the
## pack cannot pay one item per piece.
func _replan_curve_tool() -> void:
	var rotation := placement_rotation_quarters
	_drag.rotation = rotation
	var mode := str(_drag.get("mode", ""))
	var layout := curve_tool_layout(mode, _drag.anchor, rotation, curve_length(), curve_lanes())
	var affordable: bool = creative or inventory.count(str(_drag.item_id)) >= (layout.pieces as Array).size()
	var entries: Array[Dictionary] = []
	for piece: Dictionary in layout.pieces:
		var cell: Vector3i = piece.cell
		var entity_id := str(piece.entity_id)
		var check := workstations.preview_placement(entity_id, cell, int(piece.rotation), world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB())
		var state := "ok"
		if not check.get("ok", false):
			state = "blocked"
		elif not affordable:
			state = "unaffordable"
		var entry := {"cell": cell, "state": state, "reason": str(check.get("reason", "PLACEMENT_FAILED")), "voxel_id": 0, "item_id": str(_drag.item_id), "entity_id": entity_id, "rotation": int(piece.rotation), "joints": piece.joints, "extra": piece.extra}
		if piece.has("joints_b"):
			entry["joints_b"] = piece.joints_b
		entries.append(entry)
	_drag.cells = entries
	_drag.curve_cells = entries.size()
	_drag.curve_length = curve_length()
	_drag.curve_lanes = curve_lanes()


static func _joint_offsets(cell: Vector3i, joints: Variant) -> Array:
	var out: Array = []
	if joints is Array:
		for joint in joints:
			if joint is Vector3i:
				var offset: Vector3i = joint - cell
				out.append([offset.x, offset.y, offset.z])
	return out


## Flat curves (CoasterCraft card 4, 2026-09-20): with the Curve item held a
## right-press ghosts a whole flat arc of `rail_loop` pieces from the aimed
## entry cell: it leaves in the entry heading (W / R) and bends `curve_sweep`
## degrees to the right of travel with radius `curve_radius` (4-9 / X / C).
## Shift held: the aim sets the arc - its angle from the travel direction
## snaps the sweep to 45 / 90 / 135 / 180, aiming left of travel mirrors the
## bend, and half its distance is the radius. Release lays every piece for
## one Curve item each (creative: free); the radius is capped like the loop
## by what the pack can pay for. A press on the diagonal end of a 45 / 135
## curve continues it: the entry heading is taken from that curve.
var curve_radius := 4
var curve_sweep := 90
var curve_left := false


func is_curve_item(item_id: String) -> bool:
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_entity"):
		return false
	return str(registry.entity(str(item.places_entity)).get("coaster_tool", "")) == "curve"


## The largest radius at or under `wanted` (2..30) whose pieces the pack can
## pay for at the current sweep (creative: uncapped).
func curve_radius_limit(wanted: int) -> int:
	var radius := clampi(wanted, CoasterRails.CURVE_RADIUS_MIN, CoasterRails.CURVE_RADIUS_MAX)
	if creative:
		return radius
	var budget := inventory.count(str(_drag.get("item_id", inventory.active_item_id())))
	while radius > CoasterRails.CURVE_RADIUS_MIN and CoasterRails.curve_piece_count(radius, curve_sweep) > budget:
		radius -= 1
	return radius


func begin_curve_at(anchor: Vector3i) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if not is_curve_item(item_id) or workstations == null:
		return _finish(false, "NOT_PLACEABLE")
	_drag = {"mode": "curve", "item_id": item_id, "entity_id": str(item.places_entity), "voxel_id": 0, "anchor": anchor, "end": anchor, "cells": [], "shape": "curve", "rotation": placement_rotation_quarters, "x_down": false, "c_down": false}
	_replan_curve()
	return {"ok": true, "reason": "DRAG_STARTED", "anchor": anchor}


## Number keys 4-9 (or X / C) while the ghost shows: the radius in cells.
func set_curve_radius(radius: int) -> Dictionary:
	curve_radius = curve_radius_limit(radius)
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "curve":
		_replan_curve()
	return drag_state()


## 45 / 90 / 135 / 180 degrees; `left` mirrors the bend to the left of travel.
func set_curve_sweep(sweep: int, left: bool = false) -> Dictionary:
	curve_sweep = CoasterRails.curve_sweep_snap(float(sweep))
	curve_left = left
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "curve":
		curve_radius = curve_radius_limit(curve_radius)
		_replan_curve()
	return drag_state()


## Raw key states each frame (X smaller, C bigger); edges change the radius once.
func curve_keys(x_pressed: bool, c_pressed: bool) -> void:
	if _drag.is_empty() or str(_drag.get("mode", "")) != "curve":
		return
	if x_pressed and not bool(_drag.get("x_down", false)):
		set_curve_radius(curve_radius - 1)
	if c_pressed and not bool(_drag.get("c_down", false)):
		set_curve_radius(curve_radius + 1)
	_drag.x_down = x_pressed
	_drag.c_down = c_pressed


## The heading a curve pressed at `anchor` leaves in: the diagonal end of a
## curve piece that joins the anchor (continuing a 45 / 135 curve), else the
## placement rotation's travel direction.
func curve_entry_heading(anchor: Vector3i, rotation: int) -> Dictionary:
	if workstations != null:
		var tracks := CoasterRails.track_records(workstations.stations)
		for dx in [-1, 1]:
			for dz in [-1, 1]:
				var cell := anchor + Vector3i(dx, 0, dz)
				if not tracks.has(cell):
					continue
				var record: Dictionary = tracks[cell]
				if not record.has("curve") or not CoasterRails.connections(record).has(anchor):
					continue
				var heading := CoasterRails.curve_end_heading(record, anchor)
				if heading.length() > 0.5:
					return {"along": heading, "diagonal": true}
	return {"along": Vector3(CoasterRails.switch_along(rotation)), "diagonal": false}


## Every piece of the arc validated at its cell (curve pieces float); the
## ghost carries each piece's joints and curve.
func _replan_curve() -> void:
	var rotation := placement_rotation_quarters
	_drag.rotation = rotation
	var heading := curve_entry_heading(_drag.anchor, rotation)
	var layout := CoasterRails.curve_layout(_drag.anchor, rotation, float(curve_radius), float(curve_sweep), curve_left, heading.along)
	var along: Vector3 = layout.along
	_drag.along = along
	_drag.right = along.cross(Vector3.UP).normalized()
	_drag.diagonal_entry = bool(heading.diagonal)
	var affordable: bool = creative or inventory.count(str(_drag.item_id)) >= layout.pieces.size()
	var entries: Array[Dictionary] = []
	for piece: Dictionary in layout.pieces:
		var cell: Vector3i = piece.cell
		var entity_id := str(piece.entity_id)
		var check := workstations.preview_placement(entity_id, cell, int(piece.rotation), world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB())
		var state := "ok"
		if not check.get("ok", false):
			state = "blocked"
		elif not affordable:
			state = "unaffordable"
		entries.append({"cell": cell, "state": state, "reason": str(check.get("reason", "PLACEMENT_FAILED")), "voxel_id": 0, "item_id": str(_drag.item_id), "entity_id": entity_id, "rotation": int(piece.rotation), "joints": piece.joints, "extra": piece.extra})
	_drag.cells = entries
	_drag.curve_cells = layout.pieces.size()
	_drag.curve_exit = layout.exit
	# The exit is the drag's end so the ghost redraws when only the bend changes.
	_drag.end = layout.exit
	_drag.radius = layout.radius


## All pieces or nothing, one item per piece (creative: free); pieces are
## laid `_free` since the items were paid up front.
func _commit_curve_tool() -> Dictionary:
	var mode := str(_drag.get("mode", ""))
	var item_id := str(_drag.get("item_id", ""))
	var entries: Array = _drag.cells
	_drag = {}
	var blocked_reason := "CROSS_BLOCKED" if mode == "rail_cross" else "BEND_BLOCKED"
	for entry in entries:
		if str(entry.state) != "ok":
			return _finish(false, blocked_reason if str(entry.state) == "blocked" else "NO_RESOURCE", {"cell": entry.cell, "why": entry.reason})
	var price := 0 if creative else entries.size()
	if price > 0:
		var paid := inventory.try_transaction({item_id: price}, {})
		if not paid.get("ok", false):
			return _finish(false, str(paid.get("reason", "NO_RESOURCE")))
	var cells: Array[Vector3i] = []
	for entry in entries:
		var cell: Vector3i = entry.cell
		var extra: Dictionary = (entry.get("extra", {}) as Dictionary).duplicate()
		extra["coaster_joints"] = _joint_offsets(cell, entry.get("joints", []))
		if entry.has("joints_b"):
			extra["coaster_joints_b"] = _joint_offsets(cell, entry.get("joints_b", []))
		extra["_free"] = true
		var result := workstations.try_place(str(entry.entity_id), cell, world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB(), int(entry.rotation), extra)
		if not result.get("ok", false):
			return _finish(false, str(result.get("reason", "PLACEMENT_FAILED")), {"cells": cells, "cell": cell})
		cells.append(cell)
	var placed_reason := "CROSS_PLACED" if mode == "rail_cross" else "BEND_PLACED"
	return _finish(true, placed_reason, {"cells": cells, "count": cells.size(), "length": cross_length if mode == "rail_cross" else bend_length, "lanes": cross_lanes if mode == "rail_cross" else bend_lanes, "items": {item_id: -price}})


## All pieces or nothing, one Curve item per piece (creative: free); the
## pieces are laid free (`_free`) since the items paid for them.
func _commit_curve() -> Dictionary:
	var item_id := str(_drag.get("item_id", ""))
	var entries: Array = _drag.cells
	var exit: Vector3i = _drag.get("curve_exit", _drag.anchor)
	_drag = {}
	for entry in entries:
		if str(entry.state) != "ok":
			return _finish(false, "CURVE_BLOCKED" if str(entry.state) == "blocked" else "NO_RESOURCE", {"cell": entry.cell, "why": entry.reason})
	var price := 0 if creative else entries.size()
	if price > 0:
		var paid := inventory.try_transaction({item_id: price}, {})
		if not paid.get("ok", false):
			return _finish(false, str(paid.get("reason", "NO_RESOURCE")))
	var cells: Array[Vector3i] = []
	for entry in entries:
		var cell: Vector3i = entry.cell
		var joints: Array = []
		for joint in entry.get("joints", []):
			if joint is Vector3i:
				var offset: Vector3i = joint - cell
				joints.append([offset.x, offset.y, offset.z])
		var extra: Dictionary = (entry.get("extra", {}) as Dictionary).duplicate()
		extra["coaster_joints"] = joints
		extra["_free"] = true
		var result := workstations.try_place(str(entry.entity_id), cell, world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB(), int(entry.rotation), extra)
		if not result.get("ok", false):
			return _finish(false, str(result.get("reason", "PLACEMENT_FAILED")), {"cells": cells, "cell": cell})
		cells.append(cell)
	return _finish(true, "CURVE_PLACED", {"cells": cells, "count": cells.size(), "radius": curve_radius, "sweep": curve_sweep, "left": curve_left, "exit": exit, "items": {item_id: -price}})


## The aim ray's hit on the horizontal plane through the drag anchor's
## centre (Shift sizing of the flat curve tools when nothing solid is aimed).
func _drag_floor_end(origin: Vector3, direction: Vector3) -> Dictionary:
	var anchor: Vector3i = _drag.anchor
	var plane_y := float(anchor.y) + 0.5
	if absf(direction.y) < 0.02:
		return {}
	var distance := (plane_y - origin.y) / direction.y
	if distance <= 0.0 or distance > 80.0:
		return {}
	var point := origin + direction * distance
	return {"cell": Vector3i(floori(point.x), anchor.y, floori(point.z))}


# ---------------------------------------------------------------------------
# The Climb (CoasterCraft card 5, 2026-09-20). With `rail_climb` held a
# right-press ghosts a complete climb from the entry (the aim) to a landing
# `climb_length` cells ahead and `climb_rise` cells up (negative = a
# descent): slope-in, straight grade, slope-out as one TrackCurve
# (`CoasterRails.climb_layout`) of `rail_loop` pieces. Shift held: the aim
# sets both (its distance ahead = length, its height = rise); 4-9 / X / C
# set the rise; W / R turn it. Release lays every piece all-or-nothing for
# one Climb item each (creative: free); the pack caps the length, the sky
# caps the rise.
# ---------------------------------------------------------------------------

var climb_length := CoasterRails.CLIMB_LENGTH_DEFAULT
var climb_rise := CoasterRails.CLIMB_RISE_DEFAULT


func is_climb_item(item_id: String) -> bool:
	var item := registry.item(item_id)
	if item.is_empty() or not item.has("places_entity"):
		return false
	return str(registry.entity(str(item.places_entity)).get("coaster_tool", "")) == "climb"


func begin_climb_at(anchor: Vector3i) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if not is_climb_item(item_id) or workstations == null:
		return _finish(false, "NOT_PLACEABLE")
	_drag = {"mode": "climb", "item_id": item_id, "entity_id": str(item.places_entity), "voxel_id": 0, "anchor": anchor, "end": anchor, "cells": [], "shape": "climb", "rotation": placement_rotation_quarters, "x_down": false, "c_down": false}
	_replan_climb()
	return {"ok": true, "reason": "DRAG_STARTED", "anchor": anchor}


## The rise at or under `wanted` whose landing stays under the world's
## ceiling and above its floor.
func climb_rise_limit(wanted: int) -> int:
	var anchor: Vector3i = _drag.get("anchor", Vector3i.ZERO) if not _drag.is_empty() else Vector3i.ZERO
	var ceiling := WorldAdapter.WORLD_MIN.y + WorldAdapter.WORLD_SIZE.y - 2
	var floor_y := WorldAdapter.WORLD_MIN.y + 1
	return clampi(wanted, maxi(CoasterRails.CLIMB_RISE_MIN, floor_y - anchor.y), mini(CoasterRails.CLIMB_RISE_MAX, ceiling - anchor.y))


## The longest length at or under `wanted` whose pieces (at `rise`) the pack
## can pay for; creative is uncapped.
func climb_length_limit(wanted: int, rise: int) -> int:
	var length := clampi(wanted, CoasterRails.CLIMB_LENGTH_MIN, CoasterRails.CLIMB_LENGTH_MAX)
	if creative:
		return length
	var budget := inventory.count(str(_drag.get("item_id", inventory.active_item_id())))
	while length > CoasterRails.CLIMB_LENGTH_MIN and CoasterRails.climb_piece_count(length, rise) > budget:
		length -= 1
	return length


## Number keys 4-9 / X / C while the ghost shows: the rise in cells.
func set_climb_rise(rise: int) -> Dictionary:
	return set_climb(climb_length, rise)


func set_climb_length(length: int) -> Dictionary:
	return set_climb(length, climb_rise)


func set_climb(length: int, rise: int) -> Dictionary:
	climb_rise = climb_rise_limit(rise)
	climb_length = climb_length_limit(length, climb_rise)
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "climb":
		_replan_climb()
	return drag_state()


## Every piece of the climb validated at its cell (they float); the ghost
## carries each piece's curve and joints.
func _replan_climb() -> void:
	var rotation := placement_rotation_quarters
	_drag.rotation = rotation
	var layout: Dictionary = CoasterRails.climb_layout(_drag.anchor, rotation, climb_length, climb_rise)
	var affordable: bool = creative or inventory.count(str(_drag.item_id)) >= (layout.pieces as Array).size()
	var entries: Array[Dictionary] = []
	for piece: Dictionary in layout.pieces:
		var cell: Vector3i = piece.cell
		var entity_id := str(piece.entity_id)
		var check := workstations.preview_placement(entity_id, cell, int(piece.rotation), world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB())
		var state := "ok"
		if not check.get("ok", false):
			state = "blocked"
		elif not affordable:
			state = "unaffordable"
		entries.append({"cell": cell, "state": state, "reason": str(check.get("reason", "PLACEMENT_FAILED")), "voxel_id": 0, "item_id": str(_drag.item_id), "entity_id": entity_id, "rotation": int(piece.rotation), "joints": piece.joints, "extra": piece.extra})
	_drag.cells = entries
	_drag.end = layout.landing
	_drag.loop_cells = entries.size()


## All pieces or nothing, one Climb item per piece (creative: free); the
## pieces are laid `_free` since the items paid for them.
func _commit_climb() -> Dictionary:
	var item_id := str(_drag.get("item_id", ""))
	var entries: Array = _drag.cells
	var landing: Vector3i = _drag.get("end", _drag.anchor)
	_drag = {}
	for entry in entries:
		if str(entry.state) != "ok":
			return _finish(false, "CLIMB_BLOCKED" if str(entry.state) == "blocked" else "NO_RESOURCE", {"cell": entry.cell, "why": entry.reason})
	var price := 0 if creative else entries.size()
	if price > 0:
		var paid := inventory.try_transaction({item_id: price}, {})
		if not paid.get("ok", false):
			return _finish(false, str(paid.get("reason", "NO_RESOURCE")))
	var cells: Array[Vector3i] = []
	for entry in entries:
		var cell: Vector3i = entry.cell
		var joints: Array = []
		for joint in entry.get("joints", []):
			if joint is Vector3i:
				var offset: Vector3i = joint - cell
				joints.append([offset.x, offset.y, offset.z])
		var extra: Dictionary = (entry.get("extra", {}) as Dictionary).duplicate()
		extra["coaster_joints"] = joints
		extra["_free"] = true
		var result := workstations.try_place(str(entry.entity_id), cell, world.query_cell, player_body_aabb.call() if player_body_aabb.is_valid() else AABB(), int(entry.rotation), extra)
		if not result.get("ok", false):
			return _finish(false, str(result.get("reason", "PLACEMENT_FAILED")), {"cells": cells, "cell": cell})
		cells.append(cell)
	return _finish(true, "CLIMB_PLACED", {"cells": cells, "count": cells.size(), "length": climb_length, "rise": climb_rise, "landing": landing, "items": {item_id: -price}})


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


# ---------------------------------------------------------------------------
# P3K blueprints. A blueprint is a list of block cells relative to an anchor
# (see data/blueprints.json, generated by tools/generate_blueprints.py). It is
# planned like a drag: every cell validated on its own with earlier planned
# cells as support, blocked cells skipped, cells beyond the carried stock of
# their block trimmed, and committed as one world edit plus one inventory
# transaction. Once stamped the world holds ordinary voxels.
# ---------------------------------------------------------------------------

const BLUEPRINTS_PATH := "res://data/blueprints.json"
## The block a kit blueprint's entity cells are ghosted as; the castle kit is
## cut from castle stone, so that is what the preview shows.
const BLUEPRINT_ENTITY_GHOST_BLOCK := "castle_stone"

static var _blueprints: Dictionary = {}
static var _blueprints_loaded := false


static func blueprints() -> Dictionary:
	if not _blueprints_loaded:
		_blueprints_loaded = true
		if FileAccess.file_exists(BLUEPRINTS_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BLUEPRINTS_PATH))
			if parsed is Dictionary and int(parsed.get("schema_version", 0)) == 1:
				for entry in parsed.get("blueprints", []):
					if entry is Dictionary and entry.has("id"):
						_blueprints[str(entry.id)] = entry
	return _blueprints


static func blueprint(blueprint_id: String) -> Dictionary:
	return blueprints().get(blueprint_id, {})


## Rotates a blueprint offset by quarter turns about +y within its footprint.
static func rotate_blueprint_offset(offset: Vector3i, size: Vector3i, quarters: int) -> Vector3i:
	var result := offset
	for _turn in range(posmod(quarters, 4)):
		var rotated_size := Vector3i(size.z, size.y, size.x) if _turn % 2 == 1 else size
		result = Vector3i(rotated_size.z - 1 - result.z, result.y, result.x)
	return result


## The block cells of a blueprint at `anchor` with `quarters` rotation, as
## {cell, block, voxel_id, item_id}, ordered bottom course first.
func blueprint_cells(blueprint_id: String, anchor: Vector3i, quarters: int) -> Array[Dictionary]:
	var definition := blueprint(blueprint_id)
	var cells: Array[Dictionary] = []
	if definition.is_empty():
		return cells
	var size_values: Array = definition.get("size", [1, 1, 1])
	var size := Vector3i(int(size_values[0]), int(size_values[1]), int(size_values[2]))
	for entry in definition.get("blocks", []):
		var offset_values: Array = entry.get("offset", [0, 0, 0])
		var offset := Vector3i(int(offset_values[0]), int(offset_values[1]), int(offset_values[2]))
		var block_name := str(entry.get("block", ""))
		var voxel_id := WorldAdapter.BLOCK_NAMES.find(block_name)
		var item_id := _item_placing_voxel(voxel_id)
		if voxel_id <= 0 or item_id.is_empty():
			continue
		cells.append({"cell": anchor + rotate_blueprint_offset(offset, size, quarters), "block": block_name, "voxel_id": voxel_id, "item_id": item_id, "entity_id": ""})
	# Defence sets (docs/DEFENSE_SETS.md): a kit blueprint also stamps the
	# one-cell castle-kit entities that have no voxel form - the wall-walk
	# slab, the merlon and the stone stair. They plan through the same
	# per-cell rules and the same per-item budget as the blocks; only the
	# commit differs. `voxel_id` on these rows is the ghost's colour, not
	# something the commit writes: the drag preview textures a cell by the
	# block it will become, and castle stone is what these pieces are cut from.
	for entry in definition.get("entities", []):
		var entity_offsets: Array = entry.get("offset", [0, 0, 0])
		var entity_offset := Vector3i(int(entity_offsets[0]), int(entity_offsets[1]), int(entity_offsets[2]))
		var entity_id := str(entry.get("entity", ""))
		var entity_item := _item_placing_entity(entity_id)
		if entity_id.is_empty() or entity_item.is_empty():
			continue
		var ghost_voxel := WorldAdapter.BLOCK_NAMES.find(BLUEPRINT_ENTITY_GHOST_BLOCK)
		cells.append({"cell": anchor + rotate_blueprint_offset(entity_offset, size, quarters), "block": BLUEPRINT_ENTITY_GHOST_BLOCK, "voxel_id": maxi(0, ghost_voxel), "item_id": entity_item, "entity_id": entity_id, "rotation_quarters": posmod(int(entry.get("rotation", 0)) + quarters, 4)})
	cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector3i = a.cell
		var cb: Vector3i = b.cell
		if ca.y != cb.y:
			return ca.y < cb.y
		if ca.x != cb.x:
			return ca.x < cb.x
		return ca.z < cb.z)
	return cells


## Anchors a blueprint plan; the plan then follows `move_blueprint` / aim.
func begin_blueprint_at(blueprint_id: String, anchor: Vector3i, quarters: int = -1) -> Dictionary:
	if blueprint(blueprint_id).is_empty():
		return _finish(false, "UNKNOWN_BLUEPRINT")
	var rotation := placement_rotation_quarters if quarters < 0 else posmod(quarters, 4)
	_drag = {"mode": "blueprint", "blueprint_id": blueprint_id, "anchor": anchor, "end": anchor, "rotation": rotation, "cells": [], "shape": "blueprint", "item_id": "", "voxel_id": AIR}
	_replan_blueprint()
	return {"ok": true, "reason": "BLUEPRINT_STARTED", "anchor": anchor, "rotation_quarters": rotation}


func move_blueprint(anchor: Vector3i, quarters: int = -1) -> Dictionary:
	if _drag.is_empty() or str(_drag.get("mode", "")) != "blueprint":
		return {"ok": false, "reason": "NO_DRAG"}
	var rotation := int(_drag.rotation) if quarters < 0 else posmod(quarters, 4)
	if anchor != _drag.anchor or rotation != int(_drag.rotation):
		_drag.anchor = anchor
		_drag.end = anchor
		_drag.rotation = rotation
		_replan_blueprint()
	return drag_state()


## Stamped pieces are remembered so later pieces can snap to their sockets and
## saves can restore that knowledge. Stamping records `{blueprint_id, anchor,
## rotation}`; the blocks themselves are ordinary voxels and need no record.
var _stamps: Array[Dictionary] = []


func stamps_snapshot() -> Array[Dictionary]:
	return _stamps.duplicate(true)


## Replaces the stamp list only when every entry validates; a refused snapshot
## leaves the current list untouched.
func restore_stamps(values: Variant) -> bool:
	if values == null:
		_stamps.clear()
		return true
	if not values is Array:
		return false
	var accepted: Array[Dictionary] = []
	for value in values:
		if not value is Dictionary or not blueprint(str(value.get("blueprint_id", ""))).has("id"):
			return false
		var anchor_values: Array = value.get("anchor", [])
		if anchor_values.size() != 3:
			return false
		accepted.append({"blueprint_id": str(value.blueprint_id), "anchor": [int(anchor_values[0]), int(anchor_values[1]), int(anchor_values[2])], "rotation": posmod(int(value.get("rotation", 0)), 4)})
	_stamps = accepted
	return true


## World-space sockets of every stamped piece: {cell, type, blueprint_id, socket_id}.
## `cell` is where a piece attaching to that socket anchors.
func stamp_sockets() -> Array[Dictionary]:
	var sockets: Array[Dictionary] = []
	for stamp in _stamps:
		var definition := blueprint(str(stamp.blueprint_id))
		var anchor_values: Array = stamp.anchor
		var anchor := Vector3i(int(anchor_values[0]), int(anchor_values[1]), int(anchor_values[2]))
		var size_values: Array = definition.get("size", [1, 1, 1])
		var size := Vector3i(int(size_values[0]), int(size_values[1]), int(size_values[2]))
		var rotation := int(stamp.rotation)
		for socket in definition.get("sockets", []):
			var offset_values: Array = socket.get("offset", [0, 0, 0])
			var offset := Vector3i(int(offset_values[0]), int(offset_values[1]), int(offset_values[2]))
			sockets.append({"cell": anchor + rotate_blueprint_offset(offset, size, rotation), "type": str(socket.get("type", "")), "blueprint_id": str(stamp.blueprint_id), "socket_id": str(socket.get("id", ""))})
	return sockets


## If `aimed` lies within `radius` cells of a stamped socket of a type the
## active blueprint can attach to, returns that socket's anchor cell; else `aimed`.
func snap_to_socket(aimed: Vector3i, blueprint_id: String, radius: int = 1) -> Dictionary:
	var definition := blueprint(blueprint_id)
	if definition.is_empty():
		return {"cell": aimed, "snapped": false}
	var wants_top := false
	for block in definition.get("blocks", []):
		var offset_values: Array = block.get("offset", [0, 0, 0])
		if int(offset_values[1]) == 0:
			wants_top = true
			break
	var best: Dictionary = {}
	var best_distance := radius + 1
	for socket in stamp_sockets():
		var socket_cell: Vector3i = socket.cell
		var distance := maxi(absi(socket_cell.x - aimed.x), maxi(absi(socket_cell.y - aimed.y), absi(socket_cell.z - aimed.z)))
		if distance <= radius and distance < best_distance and (wants_top or str(socket.type) == "side"):
			best = socket
			best_distance = distance
	if best.is_empty():
		return {"cell": aimed, "snapped": false}
	return {"cell": best.cell, "snapped": true, "socket": best}


func _replan_blueprint() -> void:
	# Support-first as a fixpoint: cells that lack support are retried after
	# the rest of the pass, so a step beside a wall waits for that wall cell
	# regardless of catalogue order. Whatever never gains support is blocked.
	var planned: Dictionary = {}
	var budgets: Dictionary = {}
	var entries: Array[Dictionary] = []
	var pending: Array[Dictionary] = blueprint_cells(str(_drag.blueprint_id), _drag.anchor, int(_drag.rotation))
	var progress := true
	while not pending.is_empty() and progress:
		progress = false
		var deferred: Array[Dictionary] = []
		for planned_cell in pending:
			var cell: Vector3i = planned_cell.cell
			var reason := _drag_cell_reason(cell, planned)
			if reason == "UNSUPPORTED":
				deferred.append(planned_cell)
				continue
			progress = true
			var item_id := str(planned_cell.item_id)
			if not budgets.has(item_id):
				budgets[item_id] = inventory.count(item_id)
			var state := "ok"
			if reason != "OK":
				state = "blocked"
			elif int(budgets[item_id]) <= 0:
				state = "unaffordable"
			else:
				budgets[item_id] = int(budgets[item_id]) - 1
			if state == "ok":
				planned[cell] = true
			entries.append({"cell": cell, "state": state, "reason": reason, "voxel_id": int(planned_cell.voxel_id), "item_id": item_id, "block": str(planned_cell.block), "entity_id": str(planned_cell.get("entity_id", "")), "rotation_quarters": int(planned_cell.get("rotation_quarters", 0))})
		pending = deferred
	for planned_cell in pending:
		entries.append({"cell": planned_cell.cell, "state": "blocked", "reason": "UNSUPPORTED", "voxel_id": int(planned_cell.voxel_id), "item_id": str(planned_cell.item_id), "block": str(planned_cell.block), "entity_id": str(planned_cell.get("entity_id", "")), "rotation_quarters": int(planned_cell.get("rotation_quarters", 0))})
	_drag.cells = entries


func _item_placing_entity(entity_id: String) -> String:
	if entity_id.is_empty():
		return ""
	for item_id in registry.items.keys():
		var item: Dictionary = registry.items[item_id]
		if str(item.get("places_entity", "")) == entity_id:
			return str(item_id)
	return ""


func _item_placing_voxel(voxel_id: int) -> String:
	for item_id in registry.items.keys():
		var item: Dictionary = registry.items[item_id]
		if int(item.get("places_block", -1)) == voxel_id:
			return str(item_id)
	return ""


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
		entries.append({"cell": cell, "state": state, "reason": reason, "voxel_id": int(_drag.voxel_id), "item_id": str(_drag.item_id)})
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
	var anchor := placement_anchor_from_view(origin, direction)
	if anchor == Vector3i.MAX:
		return _finish(false, "NO_TARGET")
	return try_place_item(anchor, inventory.active_item_id())


## The cell a held item lands in: the last free cell along the aim before the
## first solid voxel OR entity-owned cell. The voxel raycast alone sees
## through entities, so aiming at a rail/platform used to pick the rail's own
## (occupied) cell instead of the cell on top of it. Vector3i.MAX = nothing
## within reach.
func placement_anchor_from_view(origin: Vector3, direction: Vector3, reach: float = 5.0) -> Vector3i:
	var step := direction.normalized() * 0.05
	var point := origin
	var previous := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var travelled := 0.0
	while travelled <= reach:
		point += step
		travelled += 0.05
		var cell := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if cell == previous:
			continue
		var query := world.query_cell(cell)
		if str(query.get("state", "")) != "LOADED":
			return Vector3i.MAX
		var blocked := int(query.get("voxel_id", AIR)) != AIR
		if not blocked and workstations != null and not workstations.station_at_cell(cell).is_empty():
			blocked = true
		if blocked:
			return previous
		previous = cell
	return Vector3i.MAX


func placement_preview_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	if item.is_empty() or (not item.has("places_entity") and not item.has("places_block")):
		return {"visible": false}
	var anchor := placement_anchor_from_view(origin, direction)
	if anchor == Vector3i.MAX:
		return {"visible": false, "reason": "NO_TARGET"}
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
		"clear": (checked.get("clear", []) as Array).size(),
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
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "loop_element":
		_replan_loop_element()
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "climb":
		_replan_climb()
	if not _drag.is_empty() and CURVE_TOOL_MODES.has(str(_drag.get("mode", ""))):
		_replan_curve_tool()
	if not _drag.is_empty() and str(_drag.get("mode", "")) == "curve":
		_replan_curve()
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
	if item.has("places_block") or is_linear_entity_item(inventory.active_item_id()) or is_coaster_loop_item(inventory.active_item_id()) or is_climb_item(inventory.active_item_id()) or is_curve_tool_item(inventory.active_item_id()) or is_curve_item(inventory.active_item_id()):
		return begin_drag_place(origin, direction)
	return place_from_view(origin, direction)


## Right-release: commit the drag, if one is active.
func secondary_release_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	if not drag_active():
		return {"ok": false, "reason": "NO_DRAG"}
	# Commit exactly what the ghost showed: no re-plan on release (Shift is
	# often lifted a frame before the mouse, which used to flatten a column
	# into a long row — owner playtest 2026-09-19).
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
