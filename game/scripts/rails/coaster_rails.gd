class_name CoasterRails
extends RefCounted

## Coaster rails side project (docs/COASTER_RAILS.md): the track graph shared
## by kettles, carts, visuals and the loop drag tool. Every placed track piece
## lists the cells it can join; two pieces are connected only when EACH lists
## the other's anchor (mutual rule), so a wall-top rail never joins a rail on
## the ground beside the wall and a slope only joins the pieces at its two ends.
##
## Pieces (station records: entity_id, anchor, rotation_quarters):
## - `rail` (flat): the four same-level neighbours, plus the cell diagonally
##   below in each direction so a slope's high end can reach it.
## - `rail_slope`: rises one cell toward its front; low end -> the same-level
##   cell behind it or a same-direction slope one lower behind it; high end ->
##   the cell one up and one forward (a flat rail, or the next slope up).
## - `rail_loop`: the four same-level neighbours (so a lead-in joins ordinary
##   rails) plus the joints the loop drag tool recorded in the piece's record
##   (`coaster_joints`: offsets to the previous and next cell of the drawn
##   path; kept by save/restore). A loop piece without recorded joints (placed
##   by hand) falls back to the eight in-plane neighbours of its rotation's
##   plane (quarters 1/3 = x-y, 0/2 = z-y). Recorded joints are needed because
##   a loop's risers sit directly above its lead-in and exit cells, which pure
##   adjacency would wrongly join.
## Flat-only chains are exactly the P4C 4-neighbour chains.

const FLAT := "rail"
const SLOPE := "rail_slope"
const LOOP := "rail_loop"
const TRACK_IDS: Array[String] = [FLAT, SLOPE, LOOP]
const HORIZONTAL: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


static func is_track_id(entity_id: String) -> bool:
	return TRACK_IDS.has(entity_id)


## The direction a slope rises in (world axis unit) for its rotation: the model
## front (-z) turned by the body yaw (-quarters * PI/2), matching
## EntityFootprintService.rotate_offset.
static func slope_high_direction(rotation_quarters: int) -> Vector3i:
	match posmod(rotation_quarters, 4):
		1:
			return Vector3i(1, 0, 0)
		2:
			return Vector3i(0, 0, 1)
		3:
			return Vector3i(-1, 0, 0)
		_:
			return Vector3i(0, 0, -1)


## The horizontal axis of a loop piece's vertical plane for its rotation
## (quarters 1/3 lie along x like an entity line with rotation 1).
static func loop_plane_axis(rotation_quarters: int) -> Vector3i:
	return Vector3i(1, 0, 0) if posmod(rotation_quarters, 2) == 1 else Vector3i(0, 0, 1)


## Cells this record offers a joint to (see the header). Empty for non-track
## records.
static func connections(record: Dictionary) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var quarters := int(record.get("rotation_quarters", 0))
	match str(record.get("entity_id", "")):
		FLAT:
			for side: Vector3i in HORIZONTAL:
				cells.append(anchor + side)
				cells.append(anchor + side + Vector3i.DOWN)
		SLOPE:
			var high := slope_high_direction(quarters)
			cells.append(anchor - high)
			cells.append(anchor - high + Vector3i.DOWN)
			cells.append(anchor + high + Vector3i.UP)
		LOOP:
			for side: Vector3i in HORIZONTAL:
				cells.append(anchor + side)
			var recorded: Variant = record.get("coaster_joints")
			if recorded is Array and not (recorded as Array).is_empty():
				for joint in recorded:
					if joint is Array and joint.size() == 3:
						var offset := Vector3i(int(joint[0]), int(joint[1]), int(joint[2]))
						if not cells.has(anchor + offset):
							cells.append(anchor + offset)
			else:
				var axis := loop_plane_axis(quarters)
				for along in [-1, 1]:
					for rise in [-1, 1]:
						cells.append(anchor + axis * along + Vector3i.UP * rise)
				cells.append(anchor + Vector3i.UP)
				cells.append(anchor + Vector3i.DOWN)
	return cells


## {anchor: record} of every track piece among `stations` (a WorkstationService
## `stations` dictionary or any {id: record}).
static func track_records(stations: Dictionary) -> Dictionary:
	var tracks: Dictionary = {}
	for record_id: String in stations.keys():
		var record: Dictionary = stations[record_id]
		if is_track_id(str(record.get("entity_id", ""))):
			tracks[record.get("anchor", Vector3i.ZERO)] = record
	return tracks


## Cells connected to `record` by the mutual rule, given {anchor: record}.
static func connected_cells(record: Dictionary, tracks: Dictionary) -> Array[Vector3i]:
	var joined: Array[Vector3i] = []
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	for cell in connections(record):
		if joined.has(cell) or not tracks.has(cell):
			continue
		var other: Dictionary = tracks[cell]
		if connections(other).has(anchor):
			joined.append(cell)
	return joined


## The connected track reachable from `start`: {cell: Array[Vector3i] of the
## cells it joins}. A start with no track piece yields {start: []} so riders
## keep a one-cell chain exactly as before.
static func chain(stations: Dictionary, start: Vector3i) -> Dictionary:
	var tracks := track_records(stations)
	var result: Dictionary = {}
	if not tracks.has(start):
		var alone: Array[Vector3i] = []
		result[start] = alone
		return result
	var frontier: Array[Vector3i] = [start]
	result[start] = connected_cells(tracks[start], tracks)
	while not frontier.is_empty():
		var cell: Vector3i = frontier.pop_back()
		for next: Vector3i in result[cell]:
			if not result.has(next):
				result[next] = connected_cells(tracks[next], tracks)
				frontier.append(next)
	return result


## Where a rider's wheels touch the track in `cell` (world units): the rail
## top of a flat piece, the mid-height of a slope, the centre of a loop piece.
static func ride_point(record: Dictionary) -> Vector3:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	match str(record.get("entity_id", "")):
		SLOPE:
			return Vector3(anchor) + Vector3(0.5, 1.05, 0.5)
		LOOP:
			return Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
		_:
			return Vector3(anchor) + Vector3(0.5, 0.55, 0.5)


## The ordered cells of a discrete vertical circle of `radius` cells in the
## plane spanned by `along` (horizontal unit) and +y, as offsets from the
## circle's bottom-left cell: the bottom row first (left to right), then up
## the far side, over the top and down the near side. Midpoint-circle cells
## sorted by angle, so consecutive cells are 8-neighbours.
static func loop_offsets(radius: int, along: Vector3i) -> Array[Vector3i]:
	radius = maxi(1, radius)
	var points: Array[Vector2i] = []
	var x := radius
	var y := 0
	var error := 1 - radius
	while x >= y:
		for point in [Vector2i(x, y), Vector2i(y, x), Vector2i(-y, x), Vector2i(-x, y), Vector2i(-x, -y), Vector2i(-y, -x), Vector2i(y, -x), Vector2i(x, -y)]:
			if not points.has(point):
				points.append(point)
		y += 1
		if error < 0:
			error += 2 * y + 1
		else:
			x -= 1
			error += 2 * (y - x) + 1
	var bottom_left := Vector2i(radius, 0)
	for point in points:
		if point.y < bottom_left.y or (point.y == bottom_left.y and point.x < bottom_left.x):
			bottom_left = point
	var start_angle := atan2(float(bottom_left.y), float(bottom_left.x))
	var keyed: Array[Array] = []
	for point in points:
		keyed.append([fposmod(atan2(float(point.y), float(point.x)) - start_angle, TAU), point])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var offsets: Array[Vector3i] = []
	for entry in keyed:
		var point: Vector2i = entry[1]
		offsets.append(along * (point.x - bottom_left.x) + Vector3i.UP * (point.y - bottom_left.y))
	return offsets
