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
## Height of a slope's rails at its high edge above the slope cell's floor
## (the loop ring meets the slope there).
const SLOPE_RAIL_TOP := 1.04
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
			if role == "in" or role == "out" or role == "fill":
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
			# A snapped arch piece rides on the true circle (owner 2026-09-20:
			# the cell-centre polygon looked broken); others ride their centre.
			if record.has("loop_center"):
				return arc_point(record, Vector3(anchor) + Vector3(0.5, 0.5, 0.5))
			return Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
		SWITCH:
			# The middle pieces ride on the diagonal: a quarter cell toward the
			# entry side / the exit side of the piece's centre.
			return Vector3(anchor) + Vector3(0.5, 0.55, 0.5) + switch_mid_shift(record)
		_:
			return Vector3(anchor) + Vector3(0.5, 0.55, 0.5)


## Where a slope's rails end at its high edge (world), for track pieces
## that continue them.
static func slope_rail_corner(record: Dictionary) -> Vector3:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var high := Vector3(slope_high_direction(int(record.get("rotation_quarters", 0))))
	return Vector3(anchor) + Vector3(0.5, SLOPE_RAIL_TOP, 0.5) + high * 0.5


## The point a loop piece's riders lean toward (its loop's centre), from
## `loop_center` (true-circle pieces) or `loop_up_center` (octagon pieces);
## Vector3.INF when the piece has neither.
static func lean_center(record: Dictionary) -> Vector3:
	for key in ["loop_center", "loop_up_center"]:
		var stored: Variant = record.get(key)
		if stored is Array and (stored as Array).size() == 3:
			return Vector3(float(stored[0]), float(stored[1]), float(stored[2]))
	return Vector3.INF


## The circle a snapped arch piece belongs to: {center: Vector3, radius}
## from its record, or empty.
static func arc_of(record: Dictionary) -> Dictionary:
	var stored: Variant = record.get("loop_center")
	if not (stored is Array) or (stored as Array).size() != 3:
		return {}
	return {"center": Vector3(float(stored[0]), float(stored[1]), float(stored[2])), "radius": float(record.get("loop_radius", 1.0))}


## `point` projected onto the piece's circle (in the circle's vertical plane).
static func arc_point(record: Dictionary, point: Vector3) -> Vector3:
	var arc := arc_of(record)
	if arc.is_empty():
		return point
	var center: Vector3 = arc.center
	var spoke := point - center
	spoke[2 if int(record.get("rotation_quarters", 0)) % 2 == 1 else 0] = 0.0
	if spoke.length() < 0.001:
		return point
	var projected: Vector3 = center + spoke.normalized() * float(arc.radius)
	# Below the slope corners is not track: snap to the corner on this side.
	if record.has("loop_corner_y") and projected.y < float(record.get("loop_corner_y")):
		var corner_y := float(record.get("loop_corner_y"))
		var drop := center.y - corner_y
		var reach := sqrt(maxf(0.0, float(arc.radius) * float(arc.radius) - drop * drop))
		var horizontal := spoke
		horizontal.y = 0.0
		if horizontal.length() < 0.001:
			return projected
		return center + horizontal.normalized() * reach + Vector3.DOWN * drop
	return projected


## Angle of `point` around the piece's circle, in the plane (0 = +axis).
static func arc_angle(record: Dictionary, point: Vector3) -> float:
	var arc := arc_of(record)
	if arc.is_empty():
		return 0.0
	var spoke: Vector3 = point - arc.center
	var horizontal := spoke.x if int(record.get("rotation_quarters", 0)) % 2 == 1 else spoke.z
	return atan2(spoke.y, horizontal)


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


## The Loop element (owner 2026-09-20): a complete loop with foundation.
## `anchor` is the entry piece on the entry lane; `quarters` gives the
## travel direction (`switch_along`); the lane shift is to the right of
## travel (`switch_side`). Base row = entry lane + side, exit lane = + 2 side.
## Base row along travel, from behind to ahead: right slope R (rising back),
## the second switcher's mid_a, [the first switcher's mid_b], plain rails,
## left slope L (rising ahead) - `size` cells in all (4..9). The first
## switcher: entry (anchor), mid_a (anchor + along, entry lane), mid_b (same
## column, base row) which joins L directly. The second: mid_a (anchor's
## column, base row) joined to R, mid_b (exit lane), exit (anchor + along,
## exit lane) heading on. The circle continues the slopes' 45-degree rise:
## radius = size / sqrt(2), centred over the base's middle, size / 2 above
## the slope tops; its cells run from L's top over the top to R's top.
## Returns {pieces: [{cell, entity_id, rotation, joints: Array[Vector3i],
## extra}], center: Vector3, radius: float}.
## Ring fit variants for the owner to compare (L cycles): how far above the
## slopes' rail corners the circle's tangent point sits.
const LOOP_LIFTS: Array[float] = [0.0, 0.25, 0.5]


static func loop_element_layout(anchor: Vector3i, quarters: int, size: int, lift: float = 0.0) -> Dictionary:
	size = clampi(size, 4, 9)
	var along := switch_along(quarters)
	var side := switch_side(quarters)
	var base := anchor + side
	var right_slope := base - along
	var left_slope := base + along * (size - 2)
	var s1_entry := anchor
	var s1_mid_a := anchor + along
	var s1_mid_b := base + along
	var s2_mid_a := base
	var s2_mid_b := base + side
	var s2_exit := base + side + along
	var pieces: Array[Dictionary] = []
	var switch_rotation := posmod(quarters, 4)
	var slope_ahead := posmod(quarters, 4)
	var slope_back := posmod(quarters + 2, 4)
	pieces.append(_piece(s1_entry, SWITCH, switch_rotation, [s1_mid_a], {"switch_role": "in"}))
	pieces.append(_piece(s1_mid_a, SWITCH, switch_rotation, [s1_entry, s1_mid_b], {"switch_role": "mid_a"}))
	# mid_b hands on to the next base cell (the left slope for size 4, else
	# the first filler); fillers are switch pieces too (role "fill") so they
	# join only along the row, never a rail on the lanes beside them.
	pieces.append(_piece(s1_mid_b, SWITCH, switch_rotation, [s1_mid_a, base + along * 2], {"switch_role": "mid_b"}))
	for step in range(2, size - 2):
		pieces.append(_piece(base + along * step, SWITCH, switch_rotation, [], {"switch_role": "fill"}))
	pieces.append(_piece(left_slope, SLOPE, slope_ahead, [], {}))
	pieces.append(_piece(right_slope, SLOPE, slope_back, [], {}))
	pieces.append(_piece(s2_mid_a, SWITCH, switch_rotation, [right_slope, s2_mid_b], {"switch_role": "mid_a"}))
	pieces.append(_piece(s2_mid_b, SWITCH, switch_rotation, [s2_mid_a, s2_exit], {"switch_role": "mid_b"}))
	pieces.append(_piece(s2_exit, SWITCH, switch_rotation, [s2_mid_b], {"switch_role": "out"}))
	# The ring (owner 2026-09-20: "the round ring is best"): the circle that
	# continues the slopes' 45-degree rise, radius size / sqrt(2), tangent at
	# the slopes' rail corners; its pieces ride and draw the true circle and
	# store the circle so riders lean at its centre (upside down over the
	# top). No piece's point may drop below the corners (`loop_corner_y`):
	# the first and last pieces snap to the corner instead of dipping.
	var arch: Array[Vector3i] = []
	var loop_rotation := 1 if along.x != 0 else 0
	var slope_corner_y := float(base.y) + SLOPE_RAIL_TOP + lift
	var left_edge := Vector3(left_slope) + Vector3(0.5, 0.0, 0.5) + Vector3(along) * 0.5
	var right_edge := Vector3(right_slope) + Vector3(0.5, 0.0, 0.5) - Vector3(along) * 0.5
	var radius := float(size) / sqrt(2.0)
	var center := (left_edge + right_edge) * 0.5
	center.y = slope_corner_y + float(size) * 0.5
	var toward_left := Vector3(along)
	var extra_loop := {"loop_center": [center.x, center.y, center.z], "loop_radius": radius, "loop_corner_y": slope_corner_y, "loop_lift": lift}
	var steps := 720
	for index in range(1, steps):
		var angle := deg_to_rad(225.0) - deg_to_rad(270.0) * float(index) / float(steps)
		var point := center + toward_left * (-cos(angle)) * radius + Vector3.UP * sin(angle) * radius
		var cell := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if cell == left_slope or cell == right_slope or cell == left_slope + Vector3i.UP or cell == right_slope + Vector3i.UP or cell.y <= base.y:
			continue
		if not arch.has(cell):
			arch.append(cell)
	for index in range(arch.size()):
		var cell: Vector3i = arch[index]
		var before: Vector3i = arch[index - 1] if index > 0 else left_slope
		var after: Vector3i = arch[index + 1] if index + 1 < arch.size() else right_slope
		pieces.append(_piece(cell, LOOP, loop_rotation, [before, after], extra_loop))
	return {"pieces": pieces, "center": center, "radius": radius, "arch": arch, "left_slope": left_slope, "right_slope": right_slope, "exit": s2_exit}


static func _piece(cell: Vector3i, entity_id: String, rotation: int, joints: Array, extra: Dictionary) -> Dictionary:
	var typed: Array[Vector3i] = []
	for joint in joints:
		if joint is Vector3i:
			typed.append(joint)
	return {"cell": cell, "entity_id": entity_id, "rotation": rotation, "joints": typed, "extra": extra}


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
