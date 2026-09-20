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
## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): the rideable car.
const CAR := "coaster_car"
## Lane Switcher (owner 2026-09-20): four `rail_switch` pieces laid at once.
## Roles: "in" (entry, lane 0), "mid_a" (lane 0) and "mid_b" (lane 1) side
## by side carrying the 45-degree diagonal, "out" (exit, lane 1 = one cell
## to the RIGHT of travel). Every piece stores its joints; the entry and
## exit also join plain rails behind / ahead.
const SWITCH := "rail_switch"
const SWITCH_MID_OFFSET := 0.25
const TRACK_IDS: Array[String] = [FLAT, SLOPE, LOOP, SWITCH]
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
## Travel direction of a lane switcher piece (its rotation's front) and the
## lane-shift side (the right of travel).
static func switch_along(rotation_quarters: int) -> Vector3i:
	return slope_high_direction(rotation_quarters)


static func switch_side(rotation_quarters: int) -> Vector3i:
	return Vector3i(Vector3(switch_along(rotation_quarters)).cross(Vector3.UP).round())


## The four cells and joints of a lane switcher anchored at `entry` with
## rotation `quarters`: [{cell, role, joints: Array[Vector3i]}] in ride order.
static func switch_layout(entry: Vector3i, quarters: int) -> Array[Dictionary]:
	var along := switch_along(quarters)
	var side := switch_side(quarters)
	var mid_a := entry + along
	var mid_b := mid_a + side
	var exit := mid_b + along
	var entry_joints: Array[Vector3i] = [mid_a]
	var mid_a_joints: Array[Vector3i] = [entry, mid_b]
	var mid_b_joints: Array[Vector3i] = [mid_a, exit]
	var exit_joints: Array[Vector3i] = [mid_b]
	return [{"cell": entry, "role": "in", "joints": entry_joints}, {"cell": mid_a, "role": "mid_a", "joints": mid_a_joints}, {"cell": mid_b, "role": "mid_b", "joints": mid_b_joints}, {"cell": exit, "role": "out", "joints": exit_joints}]


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
		SWITCH:
			var role := str(record.get("switch_role", ""))
			if role == "in" or role == "out":
				# Only along the travel axis: a rail beside the entry or exit
				# (in the other lane) must not join.
				var along := switch_along(quarters)
				for step in [along, -along]:
					cells.append(anchor + step)
					cells.append(anchor + step + Vector3i.DOWN)
			var switch_joints: Variant = record.get("coaster_joints")
			if switch_joints is Array:
				for joint in switch_joints:
					if joint is Array and joint.size() == 3:
						var joint_offset := Vector3i(int(joint[0]), int(joint[1]), int(joint[2]))
						if not cells.has(anchor + joint_offset):
							cells.append(anchor + joint_offset)
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
		SWITCH:
			# The middle pieces ride on the diagonal: a quarter cell toward the
			# entry side / the exit side of the piece's centre.
			return Vector3(anchor) + Vector3(0.5, 0.55, 0.5) + switch_mid_shift(record)
		_:
			return Vector3(anchor) + Vector3(0.5, 0.55, 0.5)


## Horizontal shift of a switch piece's ride point from its cell centre
## (zero for the entry and exit pieces).
static func switch_mid_shift(record: Dictionary) -> Vector3:
	var quarters := int(record.get("rotation_quarters", 0))
	var along := Vector3(switch_along(quarters))
	var side := Vector3(switch_side(quarters))
	match str(record.get("switch_role", "")):
		"mid_a":
			return (side - along) * SWITCH_MID_OFFSET
		"mid_b":
			return (along - side) * SWITCH_MID_OFFSET
	return Vector3.ZERO


## The ordered cells of a discrete vertical circle of `radius` cells in the
## plane spanned by `along` (horizontal unit) and +y, as offsets from the
## circle's bottom-left cell: the bottom row first (left to right), then up
## the far side, over the top and down the near side. Midpoint-circle cells
## sorted by angle, so consecutive cells are 8-neighbours.
## The midpoint-circle cells of `radius` around (0, 0), unordered.
static func circle_points(radius: int) -> Array[Vector2i]:
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
	return points


## Loop snap (owner 2026-09-20): the arch that closes a loop over a base
## row whose ends are two slopes rising outward. `half_width` is half the
## distance between the slopes; the arch is the upper part of a circle of
## radius half_width + 1 whose vertical sides start at the slope tops.
## Returns the arch cells as (x, y) offsets from the base row's midpoint
## (y = 1 is the slope-top row), ordered from the left slope top over the
## top to the right slope top. Empty when no circle fits.
static func loop_arch_offsets(half_width: int) -> Array[Vector2i]:
	var radius := half_width + 1
	var side_extent := 0
	for point in circle_points(radius):
		if point.x == radius:
			side_extent = maxi(side_extent, absi(point.y))
	var kept: Array[Array] = []
	for point in circle_points(radius):
		if point.y < -side_extent:
			continue
		var angle := atan2(float(point.y), float(point.x))
		if angle < -PI / 2.0:
			angle += TAU
		kept.append([angle, point])
	kept.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var offsets: Array[Vector2i] = []
	for entry in kept:
		var point: Vector2i = entry[1]
		# Lift so the lowest side cell (the slope top) sits one row above the base.
		offsets.append(Vector2i(point.x, point.y + side_extent + 1))
	if offsets.is_empty() or offsets[0] != Vector2i(-radius, 1) or offsets[offsets.size() - 1] != Vector2i(radius, 1):
		return []
	return offsets


static func loop_offsets(radius: int, along: Vector3i) -> Array[Vector3i]:
	radius = maxi(1, radius)
	var points := circle_points(radius)
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
