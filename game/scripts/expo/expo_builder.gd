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

## How many times a deferred op may be taken up again before it is reported.
## A write that keeps failing is a fault in the fixture, not slow streaming.
const MAX_REQUEUES := 40
## Parked ops are re-queued this often once the player has moved.
const RETRY_SECONDS := 2.0
const RETRY_DISTANCE := 12.0
## Cells per batch inside a "cells" op.
const CELL_BATCH := 48
## How often a fixture waits for the ground under it before it is recorded as
## a failure instead of being queued again.
const PLACE_ATTEMPTS := 60
## How often a stocking op waits for its container. A chest and the op that
## fills it are queued together but are deferred and re-queued independently,
## so the filling has to out-wait the placing by a wide margin.
const STOCK_ATTEMPTS := 600

## Terrain kinds card E authors as one composite piece (the Construction Yard's
## assemblies, a Defense Range booth, the Battlefield's sides): the exhibit's
## declared entities are placed by the terrain builder itself - a weapon on its
## mount with its chest beside it and its target down range - so `place_exhibit`
## must not also drop one of each in the middle of the parcel.
const COMPOSITE_TERRAIN: Array[String] = ["wall_demo", "blueprint_demo", "castle_demo",
	"siege_booth", "field", "camp", "battery", "fortification", "magazine"]
## How many of each munition an authored ammunition chest opens with.
const MUNITIONS_PER_CHEST := 16
## The blueprint pieces the Construction Yard stamps, bottom course first
## (data/blueprints.json, P3K).
const STAMP_STACK: Array[String] = ["foundation_4", "tower_segment_4", "cap_4"]

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
## Cells a carve op emptied on purpose (the mine tunnel, the chambers). A
## column op that is deferred for streaming is taken up again later, possibly
## after the carve that followed it has already run, so a body fill must never
## be allowed to put the mountain back into its own tunnel.
var _carved: Dictionary = {}
## Scenario reset boundaries (card E, docs/DEVELOPMENT_EXPO.md section 14).
var reset_service := ExpoResetService.new()
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
	reset_service.configure(self, layout)


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
	# Scenario groups (card E): an exhibit may name a `reset_group` of its own,
	# and that group restores only what is inside its own parcels - the
	# Battlefield rebuilds without the rest of the campus being touched.
	for scenario: String in reset_service.register_district(district_id):
		register_reset_group(scenario, _rebuild_scenario.bind(scenario))
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
	var orientation := str(parcel.get("orientation", "north"))
	# An exhibit that names an authored `build` routine owns its whole parcel -
	# its own levelling, terrain and fixtures (card F's coaster district lays
	# track through the real lay tools' layouts, which no generic entity list
	# could describe). The routine may name where its sign should stand.
	var build := str(record.get("build", ""))
	if not build.is_empty():
		var built := ExpoCoaster.build(self, build, exhibit_id, origin, size, layout.ground_y())
		if not bool(built.get("ok", false)):
			_failures.append("%s: unknown build routine %s" % [exhibit_id, build])
		var sign_cell: Vector3i = built.get("sign_cell", origin)
		sign_at(sign_cell, str(built.get("sign_facing", orientation)), layout.sign_data(exhibit_id), exhibit_id)
		return built
	_build_terrain(exhibit_id, terrain, origin, size, record)
	# `placements` pins named fixtures at manifest offsets inside the parcel
	# (the Industry chain, the light gallery). The default per-entity geometry
	# below only runs for entities the manifest did not pin.
	var pinned := {}
	var placements: Variant = record.get("placements", [])
	if placements is Array:
		for entry: Variant in placements as Array:
			if not entry is Dictionary:
				continue
			var placement: Dictionary = entry
			var entity_id := str(placement.get("entity", ""))
			if entity_id.is_empty():
				continue
			pinned[entity_id] = true
	var entities: Variant = record.get("entities", [])
	# A composite parcel (card E) is authored as one piece: its terrain builder
	# places the declared entities itself, so the per-entity geometry is skipped.
	if entities is Array and not COMPOSITE_TERRAIN.has(terrain):
		_build_entities(exhibit_id, entities as Array, origin, size, orientation, pinned)
	if placements is Array:
		for entry: Variant in placements as Array:
			if not entry is Dictionary:
				continue
			var placement: Dictionary = entry
			var entity_id := str(placement.get("entity", ""))
			if entity_id.is_empty():
				continue
			place_entity(entity_id, origin + _cell(placement.get("offset", [])), int(placement.get("rotation", 0)), "placement:" + exhibit_id)
	var items: Variant = record.get("items", [])
	if kind == "catalog" and items is Array and not (items as Array).is_empty():
		# A catalog booth is a plinth plus its label; the item itself is named
		# on the sign (the sign card owns the item picker).
		_queue_cells("booth:" + exhibit_id, [{"cell": origin + Vector3i(size.x / 2, 0, size.z / 2), "voxel": CASTLE_STONE}])
	sign_at(origin, orientation, layout.sign_data(exhibit_id), exhibit_id)
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
				"carve": true,
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
				"carve": true,
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


## Fills the container fixture standing at `cell` with `per_item` of each id.
## Queued like everything else, so it runs after the chest it stocks has been
## placed; a chest that is already stocked simply has no room left.
func stock_container(cell: Vector3i, item_ids: Array, per_item: int = MUNITIONS_PER_CHEST, label: String = "stock") -> void:
	if item_ids.is_empty() or per_item <= 0:
		return
	var ids: Array[String] = []
	for value: Variant in item_ids:
		ids.append(str(value))
	_ops.append({"kind": "stock", "label": label, "anchor": cell, "items": ids, "per_item": per_item, "passes": 0})


## Queues one callable to run in its turn in the build order. Used where a step
## must happen after the fixtures before it exist (a scenario reset restoring
## what its rebuild left standing).
func queue_action(label: String, callable: Callable) -> void:
	if not callable.is_valid():
		return
	_ops.append({"kind": "action", "label": label, "action": callable, "passes": 0})


## Stamps one P3K blueprint (data/blueprints.json) as authored world: the same
## block list the in-game blueprint tool would place, written straight into the
## voxels, and the stamp recorded with the interaction service so a later piece
## can snap to its sockets exactly as a player-stamped one would.
func stamp_blueprint(blueprint_id: String, anchor: Vector3i, quarters: int = 0, label: String = "stamp") -> int:
	var definition := InteractionService.blueprint(blueprint_id)
	if definition.is_empty():
		_failures.append("%s unknown blueprint %s" % [label, blueprint_id])
		return 0
	var size_values: Array = definition.get("size", [1, 1, 1])
	var size := Vector3i(int(size_values[0]), int(size_values[1]), int(size_values[2]))
	var cells: Array = []
	for entry: Variant in definition.get("blocks", []):
		if not entry is Dictionary:
			continue
		var block: Dictionary = entry
		var offset_values: Array = block.get("offset", [0, 0, 0])
		var offset := Vector3i(int(offset_values[0]), int(offset_values[1]), int(offset_values[2]))
		var voxel := WorldAdapter.BLOCK_NAMES.find(str(block.get("block", "")))
		if voxel <= 0:
			continue
		cells.append({"cell": anchor + InteractionService.rotate_blueprint_offset(offset, size, quarters), "voxel": voxel})
	_queue_cells(label, cells)
	queue_action(label, _record_stamp.bind(blueprint_id, anchor, quarters))
	return cells.size()


func _record_stamp(blueprint_id: String, anchor: Vector3i, quarters: int) -> void:
	if session == null or session.interaction == null:
		return
	var stamps: Array = session.interaction.stamps_snapshot()
	for entry: Variant in stamps:
		var record: Dictionary = entry
		if str(record.get("blueprint_id", "")) == blueprint_id and record.get("anchor", []) == [anchor.x, anchor.y, anchor.z]:
			return
	stamps.append({"blueprint_id": blueprint_id, "anchor": [anchor.x, anchor.y, anchor.z], "rotation": posmod(quarters, 4)})
	session.interaction.restore_stamps(stamps)
## Lays a whole track element the real lay tools produced (card F: the pieces
## of `CoasterRails.helix_layout` / `climb_layout` / `curve_layout` /
## `bend_layout` / `cross_layout`, which are `TrackCurve.pieces`). Each piece
## keeps its curve, its parameter range and its recorded joints - exactly what
## `InteractionService._commit_curve_tool` writes once the items are paid - so
## riding, joining, banking and drawing need nothing new here.
##
## Track pieces are `strict`: a cell already taken is a real conflict in an
## authored layout, not a rebuild finding its own fixture standing.
func place_track(pieces: Array, label: String = "track") -> void:
	for entry: Variant in pieces:
		if not entry is Dictionary:
			continue
		var piece: Dictionary = entry
		var cell: Vector3i = piece.get("cell", Vector3i.ZERO)
		var extra: Dictionary = (piece.get("extra", {}) as Dictionary).duplicate(true)
		var joints := _joint_offsets(cell, piece.get("joints", []))
		if not joints.is_empty():
			extra["coaster_joints"] = joints
		var joints_b := _joint_offsets(cell, piece.get("joints_b", []))
		if not joints_b.is_empty():
			extra["coaster_joints_b"] = joints_b
		_ops.append({"kind": "place", "label": label, "entity": str(piece.get("entity_id", "rail")),
			"anchor": cell, "rotation": int(piece.get("rotation", 0)), "extra": extra, "strict": true, "passes": 0})


## A piece's joint cells as the record's JSON-safe offsets from its own cell.
static func _joint_offsets(cell: Vector3i, joints: Variant) -> Array:
	var out: Array = []
	if joints is Array:
		for joint: Variant in joints as Array:
			if joint is Vector3i:
				var offset: Vector3i = (joint as Vector3i) - cell
				out.append([offset.x, offset.y, offset.z])
	return out


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


## Registers every district's reset group and every scenario group inside it
## without queueing any build work. A continued development world already has
## its fixture, but its controls must still reach their group: the Battlefield
## pedestal's RESET is `reset_group("battlefield")`.
func register_reset_groups() -> void:
	if layout == null:
		return
	for district_id: String in layout.district_ids():
		register_reset_group("district:" + district_id, _rebuild_district.bind(district_id))
		for scenario: String in reset_service.register_district(district_id):
			register_reset_group(scenario, _rebuild_scenario.bind(scenario))


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


## Ops still queued or parked whose label names one of `owners` (a district or
## exhibit id: every label is "<what>:<owner>"). A district on the far side of
## the campus stays parked until someone walks there, so a diagnostic standing
## in one district waits on that district's work, not on the whole campus.
func pending_for(owners: PackedStringArray) -> int:
	var count := 0
	var waiting: Array[Dictionary] = _ops.duplicate()
	waiting.append_array(_deferred)
	for op: Dictionary in waiting:
		if owners.has(_op_owner(op)):
			count += 1
	return count


static func _op_owner(op: Dictionary) -> String:
	var parts := str(op.get("label", "")).split(":")
	return parts[parts.size() - 1] if parts.size() > 1 else ""


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
		var requeues := int(op.get("requeues", 0)) + 1
		if requeues > MAX_REQUEUES:
			# Ground that will not take a write after this many tries is a real
			# fault, not streaming: report it rather than building for ever.
			_failures.append("%s: gave up after %d requeues" % [str(op.get("label", "op")), MAX_REQUEUES])
			continue
		op["requeues"] = requeues
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
		"stock":
			op["done"] = true
			if not _run_stock(op):
				op["done"] = false
				op["passes"] = int(op.get("passes", 0)) + 1
			return 4
		"action":
			op["done"] = true
			var action: Callable = op.get("action", Callable())
			if action.is_valid():
				action.call()
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
	# A column can cross a region boundary, so the ends being loaded does not
	# promise every cell between them is. A write that does not take leaves the
	# job unfinished and it is run again - authored ground is never half laid.
	var wrote_all := true
	var carving := bool(job.get("carve", false))
	for y in range(int(job["fill_from"]), int(job["fill_to"]) + 1):
		var cell := Vector3i(x, y, z)
		if _carved.has(cell) and fill_voxel != AIR:
			continue
		if air_only:
			var voxel := int(world.query_cell(cell).get("voxel_id", fill_voxel))
			if voxel != AIR and voxel != WATER:
				continue
		if world.set_cell(cell, fill_voxel):
			_cells_written += 1
		else:
			wrote_all = false
	var surface_y := int(job["surface_y"])
	if surface_y > -9999 and not _carved.has(Vector3i(x, surface_y, z)):
		if world.set_cell(Vector3i(x, surface_y, z), int(job["surface_voxel"])):
			_cells_written += 1
		else:
			wrote_all = false
	for y in range(int(job["clear_from"]), int(job["clear_to"]) + 1):
		var clear_cell := Vector3i(x, y, z)
		if world.set_cell(clear_cell, AIR):
			_cells_written += 1
			if carving:
				_carved[clear_cell] = true
		else:
			wrote_all = false
	return wrote_all


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
		else:
			# The cell read as LOADED but the write did not take; run it again
			# rather than leaving a hole in authored terrain.
			missed.append(record)
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
	var extra: Dictionary = (op.get("extra", {}) as Dictionary).duplicate(true)
	extra["_free"] = true
	var placed := session.workstations.try_place(entity_id, anchor, world.query_cell, AABB(), int(op.get("rotation", 0)), extra)
	if bool(placed.get("ok", false)):
		_entities_placed += 1
		return true
	var reason := str(placed.get("reason", "PLACE_FAILED"))
	# The ground under a fixture may still be streaming or still queued, and a
	# mounted fixture's mount (a tower platform, a rail) may be an op that has
	# not run yet: retry until PLACE_ATTEMPTS, then record it rather than
	# queueing for ever.
	if reason == "UNLOADED" or reason == "UNSUPPORTED" or reason == "INVALID_MOUNT":
		if int(op.get("attempts", 0)) < PLACE_ATTEMPTS:
			op["attempts"] = int(op.get("attempts", 0)) + 1
			return false
	# OCCUPIED means the fixture is already standing (a rebuild): not a failure.
	# A `strict` op (a track piece, whose cells an authored layout owns) accepts
	# that only when the piece standing there is the same one - anything else in
	# the way is a real collision the gate must see.
	if reason == "OCCUPIED" and bool(op.get("strict", false)) and not _same_entity_at(anchor, entity_id):
		_failures.append("%s %s at %s: OCCUPIED by another piece" % [str(op.get("label", "")), entity_id, anchor])
		return true
	if reason != "OCCUPIED":
		_failures.append("%s %s at %s: %s" % [str(op.get("label", "")), entity_id, anchor, reason])
	return true


## Fills one authored container: `units` (card G's supply chests) or `per_item`
## (card E's munition chests) of each of its item ids, through the container
## service the running game uses. The container op ahead of this one may not
## have run yet, or its ground may still be streaming, so a cell with no
## container is retried rather than reported. A rebuild finds the chest already
## stocked and tops it back up to the same count, so the depot is idempotent
## and a chest the owner emptied is refilled.
func _run_stock(op: Dictionary) -> bool:
	var anchor: Vector3i = op["anchor"]
	if not _loaded(session.world, anchor):
		return false
	var instance_id := session.workstations.station_at_cell(anchor)
	if instance_id.is_empty() or not session.workstations.is_container(instance_id):
		if int(op.get("attempts", 0)) < STOCK_ATTEMPTS:
			op["attempts"] = int(op.get("attempts", 0)) + 1
			return false
		_failures.append("%s stock at %s: NO_CONTAINER" % [str(op.get("label", "")), anchor])
		return true
	var units := int(op.get("units", 0))
	if units > 0:
		# Card G's depot counts: each chest holds exactly `units` of each id,
		# so a partly emptied chest is topped back up and never overfilled.
		for entry: Variant in op.get("items", []):
			var supplied_id := str(entry)
			var held := session.workstations.container_count(instance_id, supplied_id)
			if held >= units:
				continue
			var put := session.workstations.container_put(instance_id, supplied_id, units - held)
			if not bool(put.get("ok", false)):
				_failures.append("%s stock %s in %s: %s" % [str(op.get("label", "")), supplied_id, instance_id, str(put.get("reason", "PUT_FAILED"))])
		var stand: Dictionary = op.get("stand", {})
		if not stand.is_empty():
			stand["instance_id"] = instance_id
			stand["stocked"] = true
		return true
	var per_item := int(op.get("per_item", MUNITIONS_PER_CHEST))
	for item_id: String in op.get("items", []):
		var room := session.workstations.container_room(instance_id, item_id)
		if room <= 0:
			continue
		session.workstations.container_put(instance_id, item_id, mini(per_item, room))
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


## True when `entity_id` is already standing on `cell` (a rebuild laying the
## same authored track piece again).
func _same_entity_at(cell: Vector3i, entity_id: String) -> bool:
	var instance_id := session.workstations.station_at_cell(cell)
	if instance_id.is_empty():
		return false
	var record: Dictionary = session.workstations.stations.get(instance_id, {})
	return str(record.get("entity_id", "")) == entity_id


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


## One scenario reset boundary (`ExpoResetService`): only the exhibits of that
## group and the live state inside their box.
func _rebuild_scenario(group: String) -> void:
	reset_service.reset(session, group)


# ------------------------------------------------------- exhibit construction

## Terrain kinds the manifest may ask for. Everything stays ordinary editable
## voxels (handoff section 11): no decorative mesh, no special-cased blocks.
func _build_terrain(exhibit_id: String, terrain: String, origin: Vector3i, size: Vector3i, record: Dictionary = {}) -> void:
	var ground := layout.ground_y()
	match terrain:
		"field":
			# The Battlefield's no-man's-land: open dirt, deliberately plain, so
			# a wave crossing it is the only thing to watch.
			level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, DIRT, layout.clear_height(), "field:" + exhibit_id)
		"wall_demo":
			_build_drag_wall(exhibit_id, origin, size)
		"blueprint_demo":
			_build_blueprint_stamp(exhibit_id, origin, size)
		"castle_demo":
			_build_castle_demo(exhibit_id, origin, size)
		"siege_booth":
			_build_siege_booth(exhibit_id, origin, size, record)
		"battery":
			_build_battery(exhibit_id, origin, size, record)
		"fortification":
			_build_fortification(exhibit_id, origin, size, record)
		"magazine":
			_build_magazine(exhibit_id, origin, size, record)
		"camp":
			_build_camp(exhibit_id, origin, size)
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
		"pavilion":
			_build_pavilion(exhibit_id, origin, size)
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


## A roofed gallery: a levelled floor, a castle-stone wall down each long side,
## a roof over the whole span and both ends left open, with a doorway through
## the near wall so the avenue walks straight in. The shade is the point - a
## light source inside reads at midday as well as at midnight.
func _build_pavilion(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	var ground := layout.ground_y()
	var walls := maxi(3, size.y - 1)
	level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, CASTLE_STONE, layout.clear_height(), "pavilion:" + exhibit_id)
	fill_box(Vector3i(origin.x, origin.y, origin.z), Vector3i(size.x, walls, 1), CASTLE_STONE, false, "pavilion:" + exhibit_id)
	fill_box(Vector3i(origin.x, origin.y, origin.z + size.z - 1), Vector3i(size.x, walls, 1), CASTLE_STONE, false, "pavilion:" + exhibit_id)
	fill_box(Vector3i(origin.x, origin.y + walls, origin.z), Vector3i(size.x, 1, size.z), CASTLE_STONE, false, "pavilion:" + exhibit_id)
	# The doorway sits two cells in from the near corner, where the avenue from
	# the plaza meets the gallery.
	carve_box(Vector3i(origin.x + 2, origin.y, origin.z), Vector3i(3, 3, 1), "pavilion:" + exhibit_id)
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
func _build_entities(exhibit_id: String, entities: Array, origin: Vector3i, size: Vector3i, _orientation: String, pinned: Dictionary = {}) -> void:
	for entry: Variant in entities:
		var entity_id := str(entry)
		if pinned.has(entity_id):
			continue  # the manifest's `placements` owns this fixture's cell
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


# ------------------------------------------------- card E composite exhibits
#
# Construction Yard, Defense Range and Battlefield exhibits are assemblies, not
# single fixtures: a weapon is only demonstrable with its mount, its munition,
# the storage that reloads it and something to shoot at. Each of these builds
# one whole exhibit from the ids the manifest declares, so the manifest still
# owns what is shown and this file only owns how it stands.


## The siege weapons an exhibit declares, in manifest order.
func _siege_entities(entities: Array) -> Array[String]:
	var found: Array[String] = []
	for value: Variant in entities:
		var siege: Dictionary = session.registry.entity(str(value)).get("siege", {})
		if not siege.is_empty():
			found.append(str(value))
	return found


func _siege_entity(entities: Array) -> String:
	var found := _siege_entities(entities)
	return found[0] if not found.is_empty() else ""


## The munitions of `weapon_id` among the ones this exhibit declares, so a
## chest beside a ballista holds bolts and never stone shot.
func _ammo_for(weapon_id: String, items: Array) -> Array:
	var siege: Dictionary = session.registry.entity(weapon_id).get("siege", {})
	var allowed: Array = siege.get("ammo_items", [siege.get("ammo_item", "")])
	var found: Array = []
	for value: Variant in items:
		if allowed.has(str(value)):
			found.append(str(value))
	return found if not found.is_empty() else allowed


## Stands a weapon on the mount its sheet allows: on the tower platform when
## the exhibit declares one and the weapon takes a light-siege socket, else on
## the ground. Returns the cell the weapon itself ended up in.
func _place_mounted_weapon(weapon_id: String, stand: Vector3i, entities: Array, label: String) -> Vector3i:
	var mount: Dictionary = session.registry.entity(weapon_id).get("mount", {})
	var allowed: Array = mount.get("allowed", [])
	if entities.has("tower_platform") and allowed.has("light_siege"):
		place_entity("tower_platform", stand, 0, label)
		place_entity(weapon_id, stand + Vector3i(0, 1, 0), 0, label)
		return stand + Vector3i(0, 1, 0)
	place_entity(weapon_id, stand, 0, label)
	return stand


## A battlemented top on a run of wall: the wall-walk deck first, the merlons
## on every other cell above it (each supported by the deck below, exactly as
## a player stacks them).
func _build_battlements(label: String, cells: Array[Vector3i], deck_y: int) -> void:
	for cell: Vector3i in cells:
		place_entity("wall_walk_slab", Vector3i(cell.x, deck_y, cell.z), 0, label)
	for index in range(cells.size()):
		if index % 2 == 0:
			place_entity("parapet_merlon", Vector3i(cells[index].x, deck_y + 1, cells[index].z), 0, label)


## The Construction Yard's drag-built wall: one run of Castle Stone three
## courses high with a battlemented top - what a player gets by holding
## right-click and pulling the block along the line.
func _build_drag_wall(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	var label := "wall:" + exhibit_id
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), label)
	var wall_z := origin.z + 1
	fill_box(Vector3i(origin.x, origin.y, wall_z), Vector3i(size.x, 3, 1), CASTLE_STONE, false, label)
	var top: Array[Vector3i] = []
	for step in range(size.x):
		top.append(Vector3i(origin.x + step, origin.y, wall_z))
	_build_battlements(label, top, origin.y + 3)


## The Construction Yard's stamped structure: the P3K blueprint stack
## FOUNDATION 4 > TOWER SEGMENT 4 > CAP 4, each piece stamped on the top
## socket of the one under it, as the blueprint tool snaps them.
func _build_blueprint_stamp(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	var label := "stamp:" + exhibit_id
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), label)
	var anchor := Vector3i(origin.x + 3, origin.y, origin.z + 3)
	for blueprint_id: String in STAMP_STACK:
		stamp_blueprint(blueprint_id, anchor, 0, label)
		var definition := InteractionService.blueprint(blueprint_id)
		var size_values: Array = definition.get("size", [1, 1, 1])
		anchor.y += maxi(1, int(size_values[1]))


## The Construction Yard's payoff: the same pieces assembled into something
## that defends. A curtain wall with a battlemented north face, a gate through
## the south face, a stair up to the wall-walk and a solid tower carrying a
## tower platform for a light siege weapon.
func _build_castle_demo(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	var label := "castle:" + exhibit_id
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), label)
	var gate_x := origin.x + size.x / 2 - 1
	var south_z := origin.z + size.z - 1
	var ring: Array = []
	for x in range(size.x):
		for z in range(size.z):
			var on_ring: bool = x == 0 or x == size.x - 1 or z == 0 or z == size.z - 1
			if not on_ring:
				continue
			var cell_x := origin.x + x
			# The gateway stays open: the gate frame is the way through.
			if origin.z + z == south_z and cell_x >= gate_x and cell_x <= gate_x + 2:
				continue
			for y in range(3):
				ring.append({"cell": Vector3i(cell_x, origin.y + y, origin.z + z), "voxel": CASTLE_STONE})
	_queue_cells(label, ring)
	# The tower: solid to its top course, with the platform on it.
	fill_box(Vector3i(origin.x, origin.y, origin.z), Vector3i(4, 4, 4), CASTLE_STONE, false, label)
	var north: Array[Vector3i] = []
	for x in range(4, size.x):
		north.append(Vector3i(origin.x + x, origin.y, origin.z))
	_build_battlements(label, north, origin.y + 3)
	# The stair up to the wall-walk: a step of stone under each tread.
	for step in range(3):
		fill_box(Vector3i(origin.x + 5 + step, origin.y, origin.z + 1), Vector3i(1, step + 1, 1), CASTLE_STONE, false, label)
		place_entity("stone_stair", Vector3i(origin.x + 5 + step, origin.y + step + 1, origin.z + 1), 0, label)
	place_entity("tower_platform", Vector3i(origin.x + 1, origin.y + 4, origin.z + 1), 0, label)
	place_entity("gate_frame", Vector3i(gate_x, origin.y, south_z), 0, label)


## One Defense Range booth: the weapon on the mount its sheet allows, its
## ammunition in the chest touching it (the storage network is what tops the
## clip up), a target at the far end of the lane and the lane itself kept clear.
func _build_siege_booth(exhibit_id: String, origin: Vector3i, size: Vector3i, record: Dictionary) -> void:
	var label := "booth:" + exhibit_id
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), label)
	# The target, down range at the far end of the booth's own lane.
	fill_box(Vector3i(origin.x + 2, origin.y, origin.z + 2), Vector3i(2, 3, 1), CASTLE_STONE, false, label)
	var entities: Array = record.get("entities", [])
	var items: Array = record.get("items", [])
	var weapon_id := _siege_entity(entities)
	if weapon_id.is_empty():
		return
	var stand := Vector3i(origin.x + 1, origin.y, origin.z + size.z - 4)
	if entities.has("rail"):
		# The kettle is a wall weapon: a stretch of wall, the rail it rides
		# along its top and the oil chest beside it on the same course.
		fill_box(Vector3i(stand.x, origin.y, stand.z), Vector3i(4, 3, 1), CASTLE_STONE, false, label)
		place_entity("rail", stand + Vector3i(0, 3, 0), 0, label)
		place_entity("rail", stand + Vector3i(1, 3, 0), 0, label)
		place_entity(weapon_id, stand + Vector3i(1, 4, 0), 0, label)
		if entities.has("chest"):
			var oil_chest := stand + Vector3i(2, 3, 0)
			place_entity("chest", oil_chest, 0, label)
			stock_container(oil_chest, _ammo_for(weapon_id, items), MUNITIONS_PER_CHEST, label)
		return
	_place_mounted_weapon(weapon_id, stand, entities, label)
	if entities.has("chest"):
		var chest_cell := stand + Vector3i(2, 0, 0)
		place_entity("chest", chest_cell, 0, label)
		stock_container(chest_cell, _ammo_for(weapon_id, items), MUNITIONS_PER_CHEST, label)


## One Battlefield battery: every siege weapon the exhibit declares, in a row
## facing the enemy side, each on its mount with its own munition chest
## touching it so the storage network reloads it while the fight runs.
func _build_battery(exhibit_id: String, origin: Vector3i, size: Vector3i, record: Dictionary) -> void:
	var label := "battery:" + exhibit_id
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), label)
	var entities: Array = record.get("entities", [])
	var items: Array = record.get("items", [])
	var cursor := origin.x + 1
	for weapon_id: String in _siege_entities(entities):
		var stand := Vector3i(cursor, origin.y, origin.z + 1)
		_place_mounted_weapon(weapon_id, stand, entities, label)
		if entities.has("chest"):
			var chest_cell := Vector3i(cursor + 2, origin.y, origin.z + 1)
			place_entity("chest", chest_cell, 0, label)
			stock_container(chest_cell, _ammo_for(weapon_id, items), MUNITIONS_PER_CHEST, label)
		cursor += 5


## The Battlefield's curtain wall: the Construction Yard kit assembled in front
## of the Core - a solid tower carrying a light-siege platform, a battlemented
## wall and a gate frame through it. The gateway is left open on purpose: a
## wave that can walk in shows the routing, one that cannot stands and chews
## stone.
func _build_fortification(exhibit_id: String, origin: Vector3i, size: Vector3i, _record: Dictionary) -> void:
	var label := "wall:" + exhibit_id
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), label)
	var wall_z := origin.z + 2
	var gate_x := origin.x + 8
	fill_box(Vector3i(origin.x, origin.y, wall_z), Vector3i(4, 4, 4), CASTLE_STONE, false, label)
	var run: Array[Vector3i] = []
	var courses: Array = []
	for x in range(4, size.x):
		var cell_x := origin.x + x
		if cell_x >= gate_x and cell_x <= gate_x + 2:
			continue
		run.append(Vector3i(cell_x, origin.y, wall_z))
		for y in range(3):
			courses.append({"cell": Vector3i(cell_x, origin.y + y, wall_z), "voxel": CASTLE_STONE})
	_queue_cells(label, courses)
	_build_battlements(label, run, origin.y + 3)
	place_entity("tower_platform", Vector3i(origin.x + 1, origin.y + 4, origin.z + 3), 0, label)
	place_entity("gate_frame", Vector3i(gate_x, origin.y, wall_z), 0, label)
	var barricade_z := wall_z - 2
	for step in range(2):
		place_entity("wood_barricade", Vector3i(gate_x + step * 2, origin.y, barricade_z), 0, label)


## The Battlefield magazine: the chest wall behind the Core holding every
## munition in the game. RESET BATTLEFIELD fills it again.
func _build_magazine(exhibit_id: String, origin: Vector3i, size: Vector3i, record: Dictionary) -> void:
	var label := "magazine:" + exhibit_id
	level_area(Vector3i(origin.x, layout.ground_y(), origin.z), size.x, size.z, STONE, layout.clear_height(), label)
	var items: Array = record.get("items", [])
	for step in range(0, size.x - 1, 2):
		var cell := Vector3i(origin.x + step, origin.y, origin.z + 1)
		place_entity("chest", cell, 0, label)
		stock_container(cell, items, MUNITIONS_PER_CHEST, label)


## The Battlefield muster ground: the enemy side's staging. Flanking walls mark
## it without closing it - the lane down the middle is the way the wave comes,
## and the paved band across it is the line the wave enters on.
func _build_camp(exhibit_id: String, origin: Vector3i, size: Vector3i) -> void:
	var label := "camp:" + exhibit_id
	var ground := layout.ground_y()
	level_area(Vector3i(origin.x, ground, origin.z), size.x, size.z, DIRT, layout.clear_height(), label)
	fill_box(Vector3i(origin.x, origin.y, origin.z), Vector3i(2, 3, size.z), CASTLE_STONE, false, label)
	fill_box(Vector3i(origin.x + size.x - 2, origin.y, origin.z), Vector3i(2, 3, size.z), CASTLE_STONE, false, label)
	var line: Array = []
	for x in range(4, size.x - 4):
		for z in range(2, 7):
			line.append({"cell": Vector3i(origin.x + x, ground, origin.z + z), "voxel": CASTLE_STONE})
	_queue_cells(label, line)
