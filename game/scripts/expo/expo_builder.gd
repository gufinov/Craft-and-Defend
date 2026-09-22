class_name ExpoBuilder
extends Node

## Development Expo builder (docs/DEVELOPMENT_EXPO.md, handoff section 14).
## Applies the layout `ExpoLayout` solved: authored voxel terrain through
## `WorldAdapter.set_cell` and entities through `WorkstationService.try_place`
## with `{"_free": true}` (authored development-world initialisation, handoff
## section 13 - not player crafting).
##
## Everything is queued and drained a budget per frame the way
## `CoasterCraftMode` levels its plate, so a build never freezes the frame, and
## a column whose chunks are not streamed in yet is retried instead of lost.
## Districts far from the player therefore finish when the player (or a
## diagnostic) reaches them; `deferred_ops()` reports what is still waiting.
##
## The other Expo cards use this file's public API:
##   configure(layout) / bind_session(session)
##   build_all(), build_district(session, district_id), place_exhibit(session, id)
##   level_area / fill_box / carve_box / carve_tunnel / scatter_ore / plant_tree
##   sign_at(cell, facing, data, owner_id) / sign_requests() / pending_signs()
##   register_reset_group(name, callable) / reset_group(name)

signal build_reported(message: String)

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const LOG := 4
const COAL_ORE := 6
const IRON_ORE := 7
const CASTLE_STONE := 8
const LEAVES := 10
const GOLD_ORE := 11
const WATER := 12
## Work units drained per frame (one column, one cell batch or one placement).
const UNITS_PER_FRAME := 160
## A column that cannot run (chunks not streamed) is retried this many passes
## before the op is parked in `_deferred`.
const DEFER_PASSES := 3
## Parked ops are re-queued this often once the player has moved.
const RETRY_SECONDS := 2.0
const RETRY_DISTANCE := 12.0
## Cells per batch inside a "cells" op.
const CELL_BATCH := 48
## How often a fixture waits for the ground under it before it is recorded as
## a failure instead of being queued again.
const PLACE_ATTEMPTS := 60

## The sign entity the manifest's signs are made of (card B, docs/SIGNS.md).
const SIGN_ENTITY := "sign"
## Where a sign may stand, best first: its own cell, then the ring around it,
## then one cell up - an exhibit's corner is sometimes already taken.
const SIGN_OFFSETS: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1),
	Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(1, 0, 1),
	Vector3i(-2, 0, 0), Vector3i(0, 0, -2), Vector3i(2, 0, 0), Vector3i(0, 0, 2),
	Vector3i(0, 1, 0),
]
## How far above its requested cell a sign may climb to find standing room.
const SIGN_RISE := 48
## `_sign_stand` returns this y when the column offers no stand.
const SIGN_NO_STAND := -32768

var layout: ExpoLayout
var session: GameSession
## Queued ops, drained head first.
var _ops: Array[Dictionary] = []
## Ops whose chunks are not loaded; re-queued when the player moves.
var _deferred: Array[Dictionary] = []
var _retry_left := RETRY_SECONDS
var _retry_anchor := Vector3.ZERO
var _reset_groups: Dictionary = {}
## Every sign the manifest asked for, in request order: each entry gains its
## placed station's `instance_id` and `ok` once the queue reaches it (T215).
var _sign_requests: Array[Dictionary] = []
var _signs_placed := 0
## The Supply Depot catalog this build generated ({} until the depot is queued).
var _supply: Dictionary = {}
## One entry per placed supply chest: its catalog record, its cells and, once
## the stock op has run, the chest station's instance id (T223 reads these).
var _supply_stands: Array[Dictionary] = []
var _cells_written := 0
var _entities_placed := 0
var _failures: Array[String] = []


func configure(expo_layout: ExpoLayout) -> void:
	layout = expo_layout


func bind_session(game_session: GameSession) -> void:
	session = game_session


## Queues every district the manifest marks `prepare: "full"`, and the avenue
## of the ones a later card owns. Returns the queued op count.
func build_all() -> Dictionary:
	if layout == null or session == null:
		return {"ok": false, "reason": "EXPO_BUILDER_UNBOUND"}
	for district_id: String in layout.district_ids():
		build_district(session, district_id)
	return {"ok": true, "ops": _ops.size()}


## Card-facing entry point: queues one district's avenue, pad, exhibits and
## signs. Safe to call again (a rebuild overwrites the same cells).
func build_district(game_session: GameSession, district_id: String) -> Dictionary:
	if game_session != null:
		session = game_session
	if layout == null or session == null:
		return {"ok": false, "reason": "EXPO_BUILDER_UNBOUND"}
	var record := layout.district(district_id)
	if record.is_empty():
		return {"ok": false, "reason": "EXPO_UNKNOWN_DISTRICT"}
	var bounds := layout.district_bounds(district_id)
	var origin: Vector3i = bounds["origin"]
	var size: Vector3i = bounds["size"]
	for rectangle: Dictionary in layout.district_avenue(district_id):
		var avenue_origin: Vector3i = rectangle["origin"]
		var avenue_size: Vector3i = rectangle["size"]
		level_area(avenue_origin, avenue_size.x, avenue_size.z, CASTLE_STONE, 4, "avenue:" + district_id)
	var entrance := _cell(record.get("entrance", []))
	# The entrance sign reads back at the visitor arriving from outside, so it
	# faces away from the district centre they are walking towards.
	sign_at(Vector3i(entrance.x, layout.ground_y() + 1, entrance.z), _opposite(_facing_to_centre(entrance, origin, size)), layout.sign_data(district_id), district_id)
	if str(record.get("prepare", "connect")) != "full":
		return {"ok": true, "prepared": "connect"}
	if str(record.get("terrain", "level")) == "level":
		level_area(origin, size.x, size.z, STONE, layout.clear_height(), "pad:" + district_id)
	for exhibit_id: String in layout.exhibit_ids(district_id):
		place_exhibit(session, exhibit_id)
	var group := "district:" + district_id
	register_reset_group(group, _rebuild_district.bind(district_id))
	return {"ok": true, "prepared": "full", "ops": _ops.size()}


## Card-facing entry point: queues one exhibit's terrain, entities and sign.
func place_exhibit(game_session: GameSession, exhibit_id: String) -> Dictionary:
	if game_session != null:
		session = game_session
	if layout == null or session == null:
		return {"ok": false, "reason": "EXPO_BUILDER_UNBOUND"}
	var record := layout.exhibit(exhibit_id)
	var parcel := layout.parcel_for(exhibit_id)
	if record.is_empty() or parcel.is_empty():
		return {"ok": false, "reason": "EXPO_UNKNOWN_EXHIBIT"}
	var origin: Vector3i = parcel["origin"]
	var size: Vector3i = parcel["size"]
	var kind := str(record.get("kind", ""))
	var terrain := str(record.get("terrain", "level"))
	# A reserved parcel is levelled, signed and left empty on purpose (section 6).
	if kind == "reserved":
		level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), "reserved:" + exhibit_id)
		sign_at(origin, str(parcel.get("orientation", "north")), layout.sign_data(exhibit_id), exhibit_id)
		return {"ok": true, "reserved": true}
	_build_terrain(exhibit_id, terrain, origin, size)
	var entities: Variant = record.get("entities", [])
	if entities is Array:
		_build_entities(exhibit_id, entities as Array, origin, size, str(parcel.get("orientation", "north")))
	var items: Variant = record.get("items", [])
	if kind == "catalog" and items is Array and not (items as Array).is_empty():
		# A catalog booth is a plinth plus its label; the item itself is named
		# on the sign (the sign card owns the item picker).
		_queue_cells("booth:" + exhibit_id, [{"cell": origin + Vector3i(size.x / 2, 0, size.z / 2), "voxel": CASTLE_STONE}])
	sign_at(origin, str(parcel.get("orientation", "north")), layout.sign_data(exhibit_id), exhibit_id)
	return {"ok": true}


# ---------------------------------------------------------------- terrain ops

## Levels a rectangle: `origin.y` becomes the top solid cell (`surface`), the
## `clear` cells above it become air and any air or water below it down to the
## manifest's fill bottom becomes stone, so nothing floats over or under a pad.
func level_area(origin: Vector3i, width: int, depth: int, surface: int = STONE, clear: int = 0, label: String = "level") -> void:
	var columns: Array[Dictionary] = []
	for x in range(width):
		for z in range(depth):
			columns.append({
				"x": origin.x + x, "z": origin.z + z,
				"bottom": layout.fill_bottom() if layout != null else -8,
				"top": origin.y + maxi(clear, 1),
				"fill_from": layout.fill_bottom() if layout != null else -8, "fill_to": origin.y - 1,
				"fill_voxel": STONE, "fill_air_only": true,
				"surface_y": origin.y, "surface_voxel": surface,
				"clear_from": origin.y + 1, "clear_to": origin.y + clear,
			})
	_queue_columns(label, columns)


## Fills a box with one voxel. `replace_air_only` keeps existing solid cells.
func fill_box(origin: Vector3i, size: Vector3i, voxel: int, replace_air_only: bool = false, label: String = "fill") -> void:
	var columns: Array[Dictionary] = []
	for x in range(size.x):
		for z in range(size.z):
			columns.append({
				"x": origin.x + x, "z": origin.z + z,
				"bottom": origin.y, "top": origin.y + size.y - 1,
				"fill_from": origin.y, "fill_to": origin.y + size.y - 1,
				"fill_voxel": voxel, "fill_air_only": replace_air_only,
				"surface_y": -9999, "surface_voxel": AIR,
				"clear_from": 1, "clear_to": 0,
			})
	_queue_columns(label, columns)


## Clears a box to air (the ordinary dig, not a decorative cut-out).
func carve_box(origin: Vector3i, size: Vector3i, label: String = "carve") -> void:
	var columns: Array[Dictionary] = []
	for x in range(size.x):
		for z in range(size.z):
			columns.append({
				"x": origin.x + x, "z": origin.z + z,
				"bottom": origin.y, "top": origin.y + size.y - 1,
				"fill_from": 1, "fill_to": 0,
				"fill_voxel": AIR, "fill_air_only": false,
				"surface_y": -9999, "surface_voxel": AIR,
				"clear_from": origin.y, "clear_to": origin.y + size.y - 1,
			})
	_queue_columns(label, columns)


## An axis-aligned passage between two floor cells: `width` across, `height`
## high, floor kept solid one cell under the opening.
func carve_tunnel(from_cell: Vector3i, to_cell: Vector3i, width: int, height: int, label: String = "tunnel") -> void:
	var half := width / 2
	var along_x: bool = absi(to_cell.x - from_cell.x) >= absi(to_cell.z - from_cell.z)
	var length := absi(to_cell.x - from_cell.x) if along_x else absi(to_cell.z - from_cell.z)
	var forward: bool = to_cell.x >= from_cell.x if along_x else to_cell.z >= from_cell.z
	var step := 1 if forward else -1
	var columns: Array[Dictionary] = []
	for index in range(length + 1):
		for offset in range(-half, width - half):
			var cell := Vector3i(from_cell.x + index * step, from_cell.y, from_cell.z + offset)
			if not along_x:
				cell = Vector3i(from_cell.x + offset, from_cell.y, from_cell.z + index * step)
			columns.append({
				"x": cell.x, "z": cell.z,
				"bottom": cell.y - 1, "top": cell.y + height - 1,
				"fill_from": cell.y - 1, "fill_to": cell.y - 1,
				"fill_voxel": STONE, "fill_air_only": true,
				"surface_y": -9999, "surface_voxel": AIR,
				"clear_from": cell.y, "clear_to": cell.y + height - 1,
			})
	_queue_columns(label, columns)


## Deliberate ore, not noise: every stone cell of the box whose deterministic
## hash falls under `per_thousand` becomes `voxel`. Same box, same result.
func scatter_ore(origin: Vector3i, size: Vector3i, voxel: int, per_thousand: int, salt: int, label: String = "ore") -> void:
	var cells: Array[Dictionary] = []
	for x in range(size.x):
		for y in range(size.y):
			for z in range(size.z):
				var cell := origin + Vector3i(x, y, z)
				if _hash_cell(cell, salt) % 1000 < per_thousand:
					cells.append({"cell": cell, "voxel": voxel, "stone_only": true})
	_queue_cells(label, cells)


## One voxel tree: a log trunk with a leaf cap, on the cell above the ground.
func plant_tree(base: Vector3i, height: int = 5, label: String = "tree") -> void:
	var cells: Array[Dictionary] = []
	for y in range(height):
		cells.append({"cell": base + Vector3i(0, y, 0), "voxel": LOG})
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in range(height - 2, height + 2):
				if absi(x) + absi(z) + absi(y - height) <= 3:
					var cell := base + Vector3i(x, y - 0, z)
					if cell != base + Vector3i(0, y, 0):
						cells.append({"cell": cell, "voxel": LEAVES, "air_only": true})
	_queue_cells(label, cells)


## Places one authored entity through the ordinary workstation path, free of
## its item cost (handoff section 13).
func place_entity(entity_id: String, anchor: Vector3i, rotation_quarters: int = 0, label: String = "entity") -> void:
	_ops.append({"kind": "place", "label": label, "entity": entity_id, "anchor": anchor, "rotation": rotation_quarters, "passes": 0})


## Requests one of the manifest's signs: a real `sign` station is placed at
## `cell` (or the nearest free cell beside it when the exhibit already stands
## there) and its board is written with card B's `GameSession.configure_sign`.
## `facing` is the compass direction the board reads towards; `data` is the
## manifest block (`title`, `lines`, optional `item`), translated here into the
## sign record's own display mode / text / item ids.
##
## The request is recorded either way, so `sign_requests()` is the list T215
## walks and `pending_signs()` is whatever is still unfulfilled.
func sign_at(cell: Vector3i, facing: String, data: Dictionary, owner_id: String = "") -> Dictionary:
	if data.is_empty():
		return {"ok": false, "reason": "NO_SIGN_DATA"}
	var block := _sign_block(data)
	var request := {"owner": owner_id, "cell": cell, "facing": facing, "data": data.duplicate(true),
		"sign": block, "instance_id": "", "ok": false, "reason": "QUEUED"}
	_sign_requests.append(request)
	_ops.append({"kind": "sign", "label": "sign:" + owner_id, "request": request,
		"anchor": cell, "rotation": _facing_rotation(facing), "passes": 0})
	return {"ok": true, "reason": "QUEUED", "cell": cell}


## Every sign the manifest asked for, in request order, with what became of it.
func sign_requests() -> Array[Dictionary]:
	return _sign_requests.duplicate(true)


## The sign requests that have not been placed and written yet.
func pending_signs() -> Array[Dictionary]:
	var waiting: Array[Dictionary] = []
	for request: Dictionary in _sign_requests:
		if not bool(request.get("ok", false)):
			waiting.append(request.duplicate(true))
	return waiting


## Manifest sign block -> the station record's sign (docs/SIGNS.md). A block
## naming an `item` becomes Header + Item Grid (the title heads the icon), one
## with only a title and body lines becomes Split Text (title beside body), and
## a bare title becomes Single Text.
static func _sign_block(data: Dictionary) -> Dictionary:
	var title := str(data.get("title", ""))
	var lines: Array[String] = []
	var raw: Variant = data.get("lines", [])
	if raw is Array:
		for value: Variant in raw as Array:
			lines.append(str(value))
	var body := "\n".join(lines)
	var items: Array[String] = []
	var item := str(data.get("item", ""))
	if not item.is_empty():
		items.append(item)
	var raw_items: Variant = data.get("items", [])
	if raw_items is Array:
		for value: Variant in raw_items as Array:
			var extra := str(value)
			if not extra.is_empty() and extra not in items:
				items.append(extra)
	if not items.is_empty():
		return {"mode": "header_items", "text_a": title, "text_b": body, "items": items}
	if body.is_empty():
		return {"mode": "text", "text_a": title, "text_b": "", "items": items}
	return {"mode": "split", "text_a": title, "text_b": body, "items": items}


## The board faces local +X, and a station body is turned by -quarters * 90°,
## so quarter 0 reads east, 1 south, 2 west and 3 north.
static func _facing_rotation(facing: String) -> int:
	match facing:
		"south":
			return 1
		"west":
			return 2
		"north":
			return 3
		_:
			return 0


static func _opposite(facing: String) -> String:
	match facing:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		_:
			return "east"


# -------------------------------------------------------------- reset groups

## Card A's `DevelopmentMode.reset_group` calls through here: a named group
## re-runs exactly the ops that built it, and nothing else.
func register_reset_group(group: String, callable: Callable) -> void:
	_reset_groups[group] = callable


func reset_groups() -> PackedStringArray:
	var names := PackedStringArray()
	for key: String in _reset_groups.keys():
		names.append(key)
	names.sort()
	return names


func reset_group(group: String) -> Dictionary:
	if not _reset_groups.has(group):
		return {"ok": false, "reason": "UNKNOWN_RESET_GROUP"}
	var callable: Callable = _reset_groups[group]
	if not callable.is_valid():
		return {"ok": false, "reason": "STALE_RESET_GROUP"}
	callable.call()
	return {"ok": true, "ops": _ops.size()}


# ------------------------------------------------------------------- progress

func pending_ops() -> int:
	return _ops.size()


func deferred_ops() -> int:
	return _deferred.size()


func is_idle() -> bool:
	return _ops.is_empty()


func progress() -> Dictionary:
	return {"pending": _ops.size(), "deferred": _deferred.size(), "cells": _cells_written,
		"entities": _entities_placed, "signs": _signs_placed, "signs_pending": pending_signs().size(),
		"signs_requested": _sign_requests.size(), "failures": _failures.duplicate()}


func failures() -> Array[String]:
	return _failures.duplicate()


func clear_queue() -> void:
	_ops.clear()
	_deferred.clear()


func _process(delta: float) -> void:
	if session == null or not session.world_ready or session.saving:
		return
	_retry_left -= delta
	if _retry_left <= 0.0:
		_retry_left = RETRY_SECONDS
		_requeue_deferred()
	advance(UNITS_PER_FRAME)


## Drains up to `budget` work units. Exposed so a diagnostic can push the build
## forward without waiting on frames it does not need.
func advance(budget: int) -> int:
	var spent := 0
	while spent < budget and not _ops.is_empty():
		var op: Dictionary = _ops[0]
		var used := _run_op(op, budget - spent)
		spent += maxi(used, 1)
		if bool(op.get("done", false)):
			_ops.pop_front()
		elif int(op.get("passes", 0)) >= DEFER_PASSES:
			_ops.pop_front()
			_deferred.append(op)
	return spent


func _requeue_deferred() -> void:
	if _deferred.is_empty() or session == null or session.player == null:
		return
	var here := session.player.global_position
	if here.distance_to(_retry_anchor) < RETRY_DISTANCE and not _ops.is_empty():
		return
	_retry_anchor = here
	for op: Dictionary in _deferred:
		op["passes"] = 0
		_ops.append(op)
	_deferred.clear()


func _run_op(op: Dictionary, budget: int) -> int:
	var kind := str(op.get("kind", ""))
	match kind:
		"columns":
			return _run_batch(op, "columns", budget, _run_column)
		"cells":
			return _run_batch(op, "cells", budget, _run_cell_batch)
		"place":
			op["done"] = true
			if not _run_place(op):
				op["done"] = false
				op["passes"] = int(op.get("passes", 0)) + 1
			return 4
		"stock":
			op["done"] = true
			if not _run_stock(op):
				op["done"] = false
				op["passes"] = int(op.get("passes", 0)) + 1
			return 4
		"sign":
			op["done"] = true
			if not _run_sign(op):
				op["done"] = false
				op["passes"] = int(op.get("passes", 0)) + 1
			return 4
	op["done"] = true
	return 1


## One pass over an op's work list: `runner` returns false for an entry whose
## chunks are not loaded, and that entry is kept for the next pass.
func _run_batch(op: Dictionary, field: String, budget: int, runner: Callable) -> int:
	var entries: Array = op.get(field, [])
	var cursor := int(op.get("cursor", 0))
	var retry: Array = op.get("retry", [])
	var spent := 0
	while cursor < entries.size() and spent < budget:
		var entry: Dictionary = entries[cursor]
		if not bool(runner.call(entry)):
			retry.append(entry)
		cursor += 1
		spent += 1
	op["cursor"] = cursor
	op["retry"] = retry
	if cursor < entries.size():
		return spent
	if retry.is_empty():
		op["done"] = true
		return spent
	# Another pass over what was not streamed in yet.
	op[field] = retry
	op["retry"] = []
	op["cursor"] = 0
	op["passes"] = int(op.get("passes", 0)) + 1
	return spent


## fill (optionally only where air/water) -> surface cell -> clear to air.
func _run_column(job: Dictionary) -> bool:
	var world: WorldAdapter = session.world
	var x := int(job["x"])
	var z := int(job["z"])
	if not _loaded(world, Vector3i(x, int(job["bottom"]), z)) or not _loaded(world, Vector3i(x, int(job["top"]), z)):
		return false
	var fill_voxel := int(job["fill_voxel"])
	var air_only := bool(job["fill_air_only"])
	for y in range(int(job["fill_from"]), int(job["fill_to"]) + 1):
		var cell := Vector3i(x, y, z)
		if air_only:
			var voxel := int(world.query_cell(cell).get("voxel_id", fill_voxel))
			if voxel != AIR and voxel != WATER:
				continue
		if world.set_cell(cell, fill_voxel):
			_cells_written += 1
	var surface_y := int(job["surface_y"])
	if surface_y > -9999 and world.set_cell(Vector3i(x, surface_y, z), int(job["surface_voxel"])):
		_cells_written += 1
	for y in range(int(job["clear_from"]), int(job["clear_to"]) + 1):
		if world.set_cell(Vector3i(x, y, z), AIR):
			_cells_written += 1
	return true


func _run_cell_batch(batch: Dictionary) -> bool:
	var world: WorldAdapter = session.world
	var cells: Array = batch.get("cells", [])
	var missed: Array = []
	for entry: Variant in cells:
		var record: Dictionary = entry
		var cell: Vector3i = record["cell"]
		var query := world.query_cell(cell)
		if str(query.get("state", "")) != "LOADED":
			missed.append(record)
			continue
		var voxel := int(query.get("voxel_id", AIR))
		if bool(record.get("stone_only", false)) and voxel != STONE:
			continue
		if bool(record.get("air_only", false)) and voxel != AIR:
			continue
		if world.set_cell(cell, int(record["voxel"])):
			_cells_written += 1
	if missed.is_empty():
		return true
	batch["cells"] = missed
	return false


func _run_place(op: Dictionary) -> bool:
	var world: WorldAdapter = session.world
	var anchor: Vector3i = op["anchor"]
	if not _loaded(world, anchor) or not _loaded(world, anchor + Vector3i(0, -1, 0)):
		return false
	var entity_id := str(op["entity"])
	var placed := session.workstations.try_place(entity_id, anchor, world.query_cell, AABB(), int(op.get("rotation", 0)), {"_free": true})
	if bool(placed.get("ok", false)):
		_entities_placed += 1
		return true
	var reason := str(placed.get("reason", "PLACE_FAILED"))
	# The ground under a fixture may still be streaming or still queued: retry
	# until PLACE_ATTEMPTS, then record it rather than queueing for ever.
	if reason == "UNLOADED" or reason == "UNSUPPORTED":
		if int(op.get("attempts", 0)) < PLACE_ATTEMPTS:
			op["attempts"] = int(op.get("attempts", 0)) + 1
			return false
	# OCCUPIED means the fixture is already standing (a rebuild): not a failure.
	if reason != "OCCUPIED":
		_failures.append("%s %s at %s: %s" % [str(op.get("label", "")), entity_id, anchor, reason])
	return true


## Fills one supply chest: eight units of each of its item types, through the
## container service the running game uses. A rebuild finds the chest already
## stocked and the puts simply have no room, so the depot is idempotent and a
## chest the owner emptied is topped back up.
func _run_stock(op: Dictionary) -> bool:
	var anchor: Vector3i = op["anchor"]
	var instance_id := session.workstations.station_at_cell(anchor)
	if instance_id.is_empty() or str(session.workstations.stations.get(instance_id, {}).get("entity_id", "")) != "chest":
		# The chest op ahead of this one has not run (or its ground is still
		# streaming): wait for it rather than recording a failure.
		if int(op.get("attempts", 0)) < PLACE_ATTEMPTS:
			op["attempts"] = int(op.get("attempts", 0)) + 1
			return false
		_failures.append("%s stock at %s: NO_CHEST" % [str(op.get("label", "")), anchor])
		return true
	var units := int(op.get("units", 0))
	var items: Array = op.get("items", [])
	for entry: Variant in items:
		var item_id := str(entry)
		var held := session.workstations.container_count(instance_id, item_id)
		if held >= units:
			continue
		var put := session.workstations.container_put(instance_id, item_id, units - held)
		if not bool(put.get("ok", false)):
			_failures.append("%s stock %s in %s: %s" % [str(op.get("label", "")), item_id, instance_id, str(put.get("reason", "PUT_FAILED"))])
	var stand: Dictionary = op.get("stand", {})
	if not stand.is_empty():
		stand["instance_id"] = instance_id
		stand["stocked"] = true
	return true


## Places one manifest sign and writes its board. The requested cell is the
## exhibit's own corner, so it may already carry the fixture (the mine rail
## runs along it): the sign then takes the nearest free cell around it rather
## than being dropped. The station is placed free (authored fixture) and its
## content is written through card B's `GameSession.configure_sign`.
func _run_sign(op: Dictionary) -> bool:
	var request: Dictionary = op["request"]
	if bool(request.get("ok", false)):
		return true
	var world: WorldAdapter = session.world
	var anchor: Vector3i = op["anchor"]
	if not _loaded(world, anchor) or not _loaded(world, anchor + Vector3i(0, -1, 0)):
		return false
	var rotation := int(op.get("rotation", 0))
	var last_reason := "PLACE_FAILED"
	for offset: Vector3i in SIGN_OFFSETS:
		var cell := _sign_stand(world, anchor + offset)
		if cell.y == SIGN_NO_STAND:
			continue
		# A rebuild (Reset Expo, a district reset group) finds its own sign
		# already standing: rewrite that board rather than adding a second one.
		var instance_id := _standing_sign(cell)
		if instance_id.is_empty():
			var placed := session.workstations.try_place(SIGN_ENTITY, cell, world.query_cell, AABB(), rotation, {"_free": true})
			if not bool(placed.get("ok", false)):
				last_reason = str(placed.get("reason", "PLACE_FAILED"))
				continue
			instance_id = str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
		var written := session.configure_sign(instance_id, request.get("sign", {}))
		request["cell"] = cell
		request["instance_id"] = instance_id
		request["ok"] = bool(written.get("ok", false))
		request["reason"] = str(written.get("reason", "OK"))
		_entities_placed += 1
		if request["ok"]:
			_signs_placed += 1
		else:
			_failures.append("%s sign at %s: %s" % [str(op.get("label", "")), cell, request["reason"]])
		return true
	# Nothing free yet: the ground here may still be streaming or still queued.
	if int(op.get("attempts", 0)) < PLACE_ATTEMPTS:
		op["attempts"] = int(op.get("attempts", 0)) + 1
		return false
	request["reason"] = last_reason
	_failures.append("%s sign at %s: %s" % [str(op.get("label", "")), anchor, last_reason])
	return true


## The cell a sign may stand in above `column`: the first air cell from the
## requested one upwards with something solid under it. An exhibit that is a
## volume rather than a pad (the mountain mass, the ore core) has its requested
## cell buried in rock, so its board climbs to the surface above it instead of
## being lost. `y == SIGN_NO_STAND` means no stand here (or not streamed yet).
func _sign_stand(world: WorldAdapter, column: Vector3i) -> Vector3i:
	for rise in range(SIGN_RISE):
		var cell := Vector3i(column.x, column.y + rise, column.z)
		if not _loaded(world, cell) or not _loaded(world, cell + Vector3i(0, -1, 0)):
			return Vector3i(column.x, SIGN_NO_STAND, column.z)
		if int(world.query_cell(cell).get("voxel_id", AIR)) != AIR:
			continue
		if int(world.query_cell(cell + Vector3i(0, -1, 0)).get("voxel_id", AIR)) != AIR:
			return cell
	return Vector3i(column.x, SIGN_NO_STAND, column.z)


## The instance id of a `sign` already standing in `cell` ("" when the cell is
## empty or holds something else).
func _standing_sign(cell: Vector3i) -> String:
	var instance_id := session.workstations.station_at_cell(cell)
	if instance_id.is_empty():
		return ""
	var record: Dictionary = session.workstations.stations.get(instance_id, {})
	return instance_id if str(record.get("entity_id", "")) == SIGN_ENTITY else ""


func _queue_columns(label: String, columns: Array[Dictionary]) -> void:
	if columns.is_empty():
		return
	_ops.append({"kind": "columns", "label": label, "columns": columns, "cursor": 0, "retry": [], "passes": 0})


func _queue_cells(label: String, cells: Array) -> void:
	if cells.is_empty():
		return
	var batches: Array[Dictionary] = []
	var batch: Array = []
	for entry: Variant in cells:
		batch.append(entry)
		if batch.size() >= CELL_BATCH:
			batches.append({"cells": batch})
			batch = []
	if not batch.is_empty():
		batches.append({"cells": batch})
	_ops.append({"kind": "cells", "label": label, "cells": batches, "cursor": 0, "retry": [], "passes": 0})


static func _loaded(world: WorldAdapter, cell: Vector3i) -> bool:
	return str(world.query_cell(cell).get("state", "")) == "LOADED"


static func _hash_cell(cell: Vector3i, salt: int) -> int:
	var value := (cell.x * 73856093) ^ (cell.y * 19349663) ^ (cell.z * 83492791) ^ (salt * 2654435761)
	value = absi(value)
	value = (value ^ (value >> 13)) * 1274126177
	return absi(value)


## The compass direction from a district's edge cell towards its centre: the
## way a visitor arriving at that entrance is looking.
static func _facing_to_centre(entrance: Vector3i, origin: Vector3i, size: Vector3i) -> String:
	var centre := Vector3i(origin.x + size.x / 2, origin.y, origin.z + size.z / 2)
	if absi(centre.x - entrance.x) >= absi(centre.z - entrance.z):
		return "east" if centre.x >= entrance.x else "west"
	return "south" if centre.z >= entrance.z else "north"


static func _cell(value: Variant) -> Vector3i:
	if value is Array and (value as Array).size() == 3:
		var raw: Array = value
		return Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	return Vector3i.ZERO


func _rebuild_district(district_id: String) -> void:
	build_district(session, district_id)


# ------------------------------------------------------- exhibit construction

## Terrain kinds the manifest may ask for. Everything stays ordinary editable
## voxels (handoff section 11): no decorative mesh, no special-cased blocks.
func _build_terrain(exhibit_id: String, terrain: String, origin: Vector3i, size: Vector3i) -> void:
	var ground := layout.ground_y()
	match terrain:
		"level":
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, STONE, layout.clear_height(), "level:" + exhibit_id)
		"tree":
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, GRASS, size.y, "tree:" + exhibit_id)
			plant_tree(Vector3i(origin.x + size.x / 2, ground + 1, origin.z + size.z / 2), maxi(4, size.y - 3), "tree:" + exhibit_id)
		"forest":
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, GRASS, size.y, "forest:" + exhibit_id)
			for step in range(6):
				var tree_x := origin.x + 2 + (step * 5) % maxi(1, size.x - 4)
				var tree_z := origin.z + 2 + (step * 7) % maxi(1, size.z - 4)
				plant_tree(Vector3i(tree_x, ground + 1, tree_z), 5, "forest:" + exhibit_id)
		"quarry":
			# A stepped rock cut: each step one cell higher than the last.
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, STONE, size.y, "quarry:" + exhibit_id)
			var steps := maxi(1, size.y - 2)
			for step in range(steps):
				var depth := maxi(1, size.z / maxi(1, steps))
				fill_box(Vector3i(origin.x, ground + 1, origin.z + step * depth), Vector3i(size.x, step + 1, depth), STONE, false, "quarry:" + exhibit_id)
		"coal_seam":
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, STONE, size.y, "coal_seam:" + exhibit_id)
			fill_box(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, maxi(2, size.y - 2), size.z), STONE, false, "coal_seam:" + exhibit_id)
			scatter_ore(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, maxi(2, size.y - 2), size.z), COAL_ORE, 420, 11, "coal_seam:" + exhibit_id)
		"surface_ore":
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, STONE, size.y, "surface_ore:" + exhibit_id)
			fill_box(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, 2, size.z), STONE, false, "surface_ore:" + exhibit_id)
			scatter_ore(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, 2, size.z), IRON_ORE, 260, 12, "surface_ore:" + exhibit_id)
			scatter_ore(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, 2, size.z), GOLD_ORE, 90, 13, "surface_ore:" + exhibit_id)
		"ore_face":
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, STONE, size.y, "ore_face:" + exhibit_id)
			fill_box(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, maxi(2, size.y - 1), 2), STONE, false, "ore_face:" + exhibit_id)
			scatter_ore(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, maxi(2, size.y - 1), 2), IRON_ORE, 380, 14, "ore_face:" + exhibit_id)
			scatter_ore(Vector3i(origin.x, ground + 1, origin.z), Vector3i(size.x, maxi(2, size.y - 1), 2), COAL_ORE, 260, 15, "ore_face:" + exhibit_id)
		"supply_depot":
			_build_supply_depot(exhibit_id, origin, size)
		"mountain":
			_build_mountain(exhibit_id, origin, size)
		"tunnel":
			_build_tunnel(exhibit_id, origin, size)
		"ore_core":
			scatter_ore(origin, size, COAL_ORE, 150, 21, "ore_core:" + exhibit_id)
			scatter_ore(origin, size, IRON_ORE, 110, 22, "ore_core:" + exhibit_id)
			scatter_ore(origin + Vector3i(0, 0, 0), Vector3i(size.x, maxi(1, size.y / 2), size.z), GOLD_ORE, 45, 23, "ore_core:" + exhibit_id)
		"chamber":
			_build_chamber(exhibit_id, origin, size)
		_:
			pass


## A broad voxel mass: stone body, dirt and grass skin, a rounded profile so
## it reads as a mountain and not a block. Every cell is an ordinary voxel.
func _build_mountain(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	var ground := layout.ground_y()
	var centre := Vector2(float(origin.x) + float(size.x) * 0.5, float(origin.z) + float(size.z) * 0.5)
	var radius := float(mini(size.x, size.z)) * 0.5
	var peak := size.y - 2
	var columns: Array[Dictionary] = []
	for x in range(size.x):
		for z in range(size.z):
			var cell := Vector2(float(origin.x + x), float(origin.z + z))
			var distance := cell.distance_to(centre) / maxf(1.0, radius)
			if distance >= 1.0:
				continue
			var profile := 1.0 - distance * distance
			var height := int(round(float(peak) * profile))
			if height <= 0:
				continue
			var top := ground + height
			columns.append({
				"x": origin.x + x, "z": origin.z + z,
				"bottom": ground, "top": top + 1,
				"fill_from": ground, "fill_to": top - 1,
				"fill_voxel": STONE, "fill_air_only": false,
				"surface_y": top, "surface_voxel": GRASS if height <= 3 else STONE,
				"clear_from": top + 1, "clear_to": top + 1,
			})
	_queue_columns("mountain:" + exhibit_id, columns)


## The main gallery: carved end to end, floored, lit with post lanterns down
## one side and left clear for the rail line down the middle.
func _build_tunnel(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	var centre_z := origin.z + size.z / 2
	var floor_y := origin.y
	carve_tunnel(Vector3i(origin.x, floor_y, centre_z), Vector3i(origin.x + size.x - 1, floor_y, centre_z), size.z, size.y, "tunnel:" + exhibit_id)
	var lantern_z := origin.z + 1
	for x in range(2, size.x - 2, 8):
		place_entity("post_lantern", Vector3i(origin.x + x, floor_y, lantern_z), 0, "tunnel:" + exhibit_id)
	for x in range(6, size.x - 2, 8):
		place_entity("post_lantern", Vector3i(origin.x + x, floor_y, origin.z + size.z - 2), 0, "tunnel:" + exhibit_id)


## A working chamber off the main tunnel: carved out, joined to the tunnel by
## a spur wide enough to walk round the machines, ore left in its far wall.
func _build_chamber(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	carve_box(origin, size, "chamber:" + exhibit_id)
	level_area(Vector3i(origin.x, origin.y - 1, origin.z), size.x, size.z, STONE, size.y, "chamber:" + exhibit_id)
	var tunnel := layout.parcel_for("mountain_tunnel")
	if not tunnel.is_empty():
		var tunnel_origin: Vector3i = tunnel["origin"]
		var tunnel_size: Vector3i = tunnel["size"]
		var tunnel_z := tunnel_origin.z + tunnel_size.z / 2
		var spur_x := origin.x + size.x / 2
		carve_tunnel(Vector3i(spur_x, origin.y, tunnel_z), Vector3i(spur_x, origin.y, origin.z + size.z / 2), 5, mini(size.y, tunnel_size.y), "spur:" + exhibit_id)
	# The ore face this chamber is about: a solid block of ore in its far wall,
	# deep enough that mining it (by hand or by machine) lasts.
	var face := Vector3i(origin.x + 1, origin.y, origin.z + size.z - 4)
	fill_box(face, Vector3i(size.x - 2, 3, 3), IRON_ORE, false, "chamber:" + exhibit_id)
	scatter_ore(face, Vector3i(size.x - 2, 3, 3), COAL_ORE, 340, 31, "chamber:" + exhibit_id)
	scatter_ore(face, Vector3i(size.x - 2, 3, 3), GOLD_ORE, 70, 32, "chamber:" + exhibit_id)


## The Supply Depot (docs/DEVELOPMENT_EXPO.md, handoff sections 8 and 9): the
## pad, then one stand per chest the generator asked for - a two-cell stone
## plinth with the chest in front of it, the chest stocked with eight units of
## each of its item types and the plinth's top carrying the chest's own Header
## + Item Grid sign. Categories the game has no items for yet get the same
## stand with a reserved board and no chest.
##
## The catalog comes from `SupplyDepot`, never from a list in this file, so a
## new item joins the depot by being registered and classified and nothing
## here changes.
func _build_supply_depot(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), "supply:" + exhibit_id)
	var config: Dictionary = {}
	var raw_config: Variant = layout.manifest.get("supply", {})
	if raw_config is Dictionary:
		config = raw_config
	_supply = SupplyDepot.catalog(session.registry, config)
	_supply_stands.clear()
	var chests: Array = _supply.get("chests", [])
	var reserved: Array = _supply.get("reserved", [])
	var units := int(_supply.get("units", SupplyDepot.DEFAULT_UNITS))
	var unassigned: Array = _supply.get("unassigned", [])
	if not unassigned.is_empty():
		# Never silently bucketed: the depot reports it and validation names it.
		_failures.append("supply depot: unclassified items %s" % str(unassigned))
	var stands := chests.size() + reserved.size()
	if stands > SupplyDepot.stand_capacity(size):
		_failures.append("supply depot: %d stands do not fit the %s parcel (%d)" % [stands, size, SupplyDepot.stand_capacity(size)])
		return
	for index in range(chests.size()):
		var chest: Dictionary = chests[index]
		var stand := SupplyDepot.stand_at(origin, size, index)
		var plinth: Vector3i = stand["plinth"]
		var anchor: Vector3i = stand["chest"]
		_queue_plinth("supply:" + exhibit_id, plinth)
		place_entity("chest", anchor, 0, "supply:" + exhibit_id)
		var items: Array[String] = chest["items"]
		var record := {"index": index, "category": str(chest.get("category", "")), "label": str(chest.get("label", "")),
			"items": items.duplicate(), "units": units, "chest": anchor, "plinth": plinth,
			"sign_owner": _supply_owner(index), "instance_id": "", "stocked": false}
		_supply_stands.append(record)
		_ops.append({"kind": "stock", "label": "supply:" + exhibit_id, "anchor": anchor,
			"items": items.duplicate(), "units": units, "stand": record, "passes": 0})
		# The board reads back at a visitor walking in from the plaza (+z).
		sign_at(plinth, "south", SupplyDepot.chest_sign(chest), record["sign_owner"])
	for offset in range(reserved.size()):
		var stand_reserved := SupplyDepot.stand_at(origin, size, chests.size() + offset)
		var reserved_plinth: Vector3i = stand_reserved["plinth"]
		_queue_plinth("supply:" + exhibit_id, reserved_plinth)
		sign_at(reserved_plinth, "south", SupplyDepot.reserved_sign(reserved[offset], units),
			"supply_reserved_" + str((reserved[offset] as Dictionary).get("category", offset)))


## The two stone cells a supply sign stands on, so its board reads above the
## chest in front of it rather than at the chest's own height.
func _queue_plinth(label: String, base: Vector3i) -> void:
	var cells: Array = []
	for step in range(SupplyDepot.PLINTH_HEIGHT):
		cells.append({"cell": base + Vector3i(0, step, 0), "voxel": STONE})
	_queue_cells(label, cells)


static func _supply_owner(index: int) -> String:
	return "supply_chest_%02d" % index


## The Supply Depot catalog this build generated ({} before the depot is built).
func supply_catalog() -> Dictionary:
	return _supply.duplicate(true)


## One record per placed supply chest, with the instance id it was stocked in.
func supply_stands() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _supply_stands:
		result.append(record.duplicate(true))
	return result


## Entities of an exhibit: the rail line lays along its parcel, a miner stands
## in front of its ore face with an ore bin beside it, everything else stands
## on the parcel's anchor cell.
func _build_entities(exhibit_id: String, entities: Array, origin: Vector3i, size: Vector3i, _orientation: String) -> void:
	for entry: Variant in entities:
		var entity_id := str(entry)
		match entity_id:
			"rail":
				for x in range(size.x):
					place_entity("rail", Vector3i(origin.x + x, origin.y, origin.z), 0, "rail:" + exhibit_id)
			"post_lantern":
				pass  # the tunnel places its own lanterns as it carves
			"miner":
				# Two cells clear of the ore face, with walking room all round.
				place_entity("miner", Vector3i(origin.x + size.x / 2, origin.y, origin.z + size.z - 6), 0, "miner:" + exhibit_id)
			"ore_bin":
				place_entity("ore_bin", Vector3i(origin.x + size.x / 2 + 1, origin.y, origin.z + size.z - 6), 0, "miner:" + exhibit_id)
			_:
				# A one-cell fixture stands in the middle of its parcel; a
				# multi-cell one (the Core) anchors at the parcel corner so its
				# whole footprint stays inside the parcel it was given.
				var footprint: Variant = session.registry.entity(entity_id).get("occupied_offsets", [])
				var wide: bool = footprint is Array and (footprint as Array).size() > 1
				var anchor := origin if wide else Vector3i(origin.x + size.x / 2, origin.y, origin.z + size.z / 2)
				place_entity(entity_id, anchor, 0, "exhibit:" + exhibit_id)
