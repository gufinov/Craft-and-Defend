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
## The blocky lane-shift piece the loop element lays (`loop_element_layout`)
## as its entry / exit runs. Roles: "in" (entry, lane 0), "mid_a" (lane 0)
## and "mid_b" (lane 1) side by side carrying the 45-degree diagonal, "out"
## (exit, lane 1 = one cell to the RIGHT of travel), "fill" (base row).
## Every piece stores its joints; the entry and exit also join plain rails
## behind / ahead. The Rail Switch ITEM no longer lays these: since
## 2026-09-20 it is the smooth lane switcher (`bend_layout`, coaster_tool
## "bend"); this entity id remains its tool identity.
const SWITCH := "rail_switch"
const SWITCH_MID_OFFSET := 0.25
## The Climb (CoasterCraft card 5): the tool item's entity id; its pieces
## are `rail_loop` records carrying the climb curve.
const CLIMB := "rail_climb"
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
			# A curve piece (TrackCurve) joins only what it recorded: a loop's
			# entry and exit sit on neighbouring lanes and must not short-circuit.
			if not record.has("curve"):
				for side: Vector3i in HORIZONTAL:
					cells.append(anchor + side)
			var recorded: Variant = record.get("coaster_joints")
			if recorded is Array and not (recorded as Array).is_empty():
				# A crossing's shared cell (CoasterCraft card 3) carries a second
				# curve with its own joint pair (`coaster_joints_b`): it joins both.
				for pair_key in ["coaster_joints", "coaster_joints_b"]:
					var pair_joints: Variant = record.get(pair_key)
					if not (pair_joints is Array):
						continue
					for joint in pair_joints:
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


## Snap-to-track-end (owner playtest 2026-09-21 item 2): every place a next
## piece would join the laid track, given {anchor: record} (`track_records`):
## [{cell: the piece's cell, next: the free joint cell, along: unit Vector3
## from the piece toward the joint (a curve piece's end tangent, so a 45
## degree end reports its diagonal), instance_id}]. A joint whose cell holds
## a track is not open. A slope end offers one open end (its same-level
## joint; the one-lower alternative is the same end). A plain rail with no
## explicit joints has two implied ends: straight on from its one connected
## neighbour, or both cells along its placement axis when it stands alone;
## a rail joined on two sides (a run or a corner) has none. A loop piece
## placed by hand (no recorded joints) reports none.
static func open_ends(tracks: Dictionary) -> Array[Dictionary]:
	var ends: Array[Dictionary] = []
	for anchor_key: Variant in tracks.keys():
		var record: Dictionary = tracks[anchor_key]
		var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
		var entity_id := str(record.get("entity_id", ""))
		var instance_id := str(record.get("instance_id", ""))
		var candidates: Array[Vector3i] = []
		var joined := connected_cells(record, tracks)
		if entity_id == FLAT:
			if joined.size() == 1:
				var toward: Vector3i = joined[0] - anchor
				toward.y = 0
				if toward != Vector3i.ZERO:
					candidates.append(anchor - toward)
			elif joined.is_empty():
				var axis := switch_along(int(record.get("rotation_quarters", 0)))
				candidates.append(anchor + axis)
				candidates.append(anchor - axis)
		elif entity_id == LOOP and not (record.get("coaster_joints") is Array and not (record.get("coaster_joints") as Array).is_empty()):
			continue
		else:
			var offered := connections(record)
			for cell: Vector3i in offered:
				# A one-lower joint (a slope's low end, a rail's slope reach) is
				# the same end as its same-level joint: the level cell stands for it.
				if cell.y == anchor.y - 1 and offered.has(cell + Vector3i.UP):
					continue
				candidates.append(cell)
		for next: Vector3i in candidates:
			# Taken, or already joined through its one-lower alternative (a
			# slope's low end meeting the slope below it).
			if tracks.has(next) or joined.has(next + Vector3i.DOWN):
				continue
			var along := curve_end_heading(record, next) if record.has("curve") else Vector3.ZERO
			if along.length() < 0.5:
				along = Vector3(next.x - anchor.x, 0.0, next.z - anchor.z)
			if along.length() < 0.5:
				continue
			ends.append({"cell": anchor, "next": next, "along": along.normalized(), "instance_id": instance_id})
	return ends


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
			if record.has("curve"):
				return TrackCurve.point(record.get("curve", {}), TrackCurve.piece_t(record))
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
# ---------------------------------------------------------------------------
# The true loop (owner 2026-09-20): a real coaster loop that is not boxy. One
# turn of a helix in the vertical plane of travel: it leaves the ground at
# the entry cell, climbs the circle, and while going round drifts one lane
# to the right of travel, so it lands again exactly one cell beside the
# entry, heading the same way. Only those two cells touch the ground; every
# other piece floats. Pieces ride and draw the helix itself; the size is
# the circle's diameter in cells (any size that fits).
# ---------------------------------------------------------------------------

const HELIX_MIN := 3
const HELIX_MAX := 64


## How many pieces a true loop of `diameter` takes (its item price).
static func helix_piece_count(diameter: int) -> int:
	return (helix_layout(Vector3i.ZERO, 0, diameter).cells as Array).size()


## The true loop's pieces: {pieces, cells, center, radius, entry, exit}.
static func helix_layout(entry: Vector3i, quarters: int, diameter: int) -> Dictionary:
	diameter = clampi(diameter, HELIX_MIN, HELIX_MAX)
	var along := switch_along(quarters)
	var side := switch_side(quarters)
	var radius := float(diameter) * 0.5
	var ground := Vector3(entry) + Vector3(0.5, 0.55, 0.5)
	var curve := TrackCurve.make_helix(ground, Vector3(along), Vector3(side), radius, 1.0, 1.0)
	var exit := entry + side
	var loop_rotation := 1 if along.x != 0 else 0
	var pieces := TrackCurve.pieces(curve, LOOP, loop_rotation, entry - along, exit + along, {}, maxi(720, diameter * 90))
	var cells: Array[Vector3i] = []
	for piece: Dictionary in pieces:
		cells.append(piece.cell)
	return {"pieces": pieces, "cells": cells, "center": ground + Vector3.UP * radius, "radius": radius, "entry": entry, "exit": exit}


# ---------------------------------------------------------------------------
# The Climb (CoasterCraft card 5, 2026-09-20): with `rail_climb` held a
# press ghosts a complete climb from the entry cell to a landing `length`
# cells ahead and `rise` cells up (negative = a descent): a concave slope-in,
# a straight at the grade and a convex slope-out, one TrackCurve
# (`make_climb`) laid as `rail_loop` pieces. The entry and the landing are
# at rail height on their levels, so plain rails join them flush.
# ---------------------------------------------------------------------------

const CLIMB_LENGTH_MIN := 3
const CLIMB_LENGTH_MAX := 60
const CLIMB_RISE_MIN := -30
const CLIMB_RISE_MAX := 30
const CLIMB_LENGTH_DEFAULT := 8
const CLIMB_RISE_DEFAULT := 4


## How many pieces a climb of `length` and `rise` takes (its item price).
static func climb_piece_count(length: int, rise: int) -> int:
	return (climb_layout(Vector3i.ZERO, 0, length, rise).cells as Array).size()


## The climb's pieces: {pieces, cells, curve, entry, landing}. The landing
## cell is `entry + along * length + up * rise` (its floor is the entry's
## floor plus the rise).
static func climb_layout(entry: Vector3i, quarters: int, length: int, rise: int) -> Dictionary:
	length = clampi(length, CLIMB_LENGTH_MIN, CLIMB_LENGTH_MAX)
	rise = clampi(rise, CLIMB_RISE_MIN, CLIMB_RISE_MAX)
	var along := switch_along(quarters)
	var side := switch_side(quarters)
	var origin := Vector3(entry) + Vector3(0.5, 0.55, 0.5)
	var curve := TrackCurve.make_climb(origin, Vector3(along), Vector3(side), float(length), float(rise))
	var landing := entry + along * length + Vector3i.UP * rise
	var loop_rotation := 1 if along.x != 0 else 0
	var pieces := TrackCurve.pieces(curve, LOOP, loop_rotation, entry - along, landing + along, {}, maxi(720, (length + absi(rise)) * 40))
	var cells: Array[Vector3i] = []
	for piece: Dictionary in pieces:
		cells.append(piece.cell)
	return {"pieces": pieces, "cells": cells, "curve": curve, "entry": entry, "landing": landing}
# Flat curves (CoasterCraft card 4, 2026-09-20): the Curve tool lays a flat
# arc of `rail_loop` pieces that leaves its entry heading `along` and turns
# `sweep` degrees (45 / 90 / 135 / 180) to the RIGHT of travel (or the left,
# mirrored) with radius `radius`. The entry is the aimed cell; the arc's
# centre is `radius` cells to the side of the entry's ride point, so the
# first piece rides its cell centre and joins a plain rail behind it. The
# exit piece joins the cell ahead of it in the end tangent snapped to the
# nearest grid direction: an axis neighbour for 90 / 180 (a plain rail joins
# it), the DIAGONAL neighbour for 45 / 135 (only another curve can continue
# it - the next curve's entry takes the diagonal heading automatically, see
# `curve_end_heading`). Pieces float; the arc is banked 0.35 (make_arc's
# default) so riders lean into the bend.
# ---------------------------------------------------------------------------

const CURVE_RADIUS_MIN := 2
const CURVE_RADIUS_MAX := 30
const CURVE_SWEEPS: Array[int] = [45, 90, 135, 180]


## Snaps any turn to the nearest laid sweep (45 / 90 / 135 / 180 degrees).
static func curve_sweep_snap(degrees: float) -> int:
	if degrees <= 22.5:
		return 45
	if degrees <= 67.5:
		return 90
	if degrees <= 112.5:
		return 135
	return 180


## The grid step a unit heading rounds to (an axis or a diagonal).
static func heading_cell(heading: Vector3) -> Vector3i:
	return Vector3i(roundi(heading.x), 0, roundi(heading.z))


## The pieces of a flat curve entered at `entry` heading `along` (a unit
## horizontal vector; an axis from the placement rotation, or a diagonal
## when continuing a 45-degree end): {pieces, cells, curve, center, radius,
## entry, exit, exit_heading (unit tangent at the end), exit_cell_ahead,
## along, side}. `left` mirrors the bend to the left of travel.
static func curve_layout(entry: Vector3i, quarters: int, radius: float, sweep: float, left: bool = false, along: Vector3 = Vector3.ZERO) -> Dictionary:
	radius = clampf(radius, float(CURVE_RADIUS_MIN), float(CURVE_RADIUS_MAX))
	if along.length() < 0.5:
		along = Vector3(switch_along(quarters))
	along = Vector3(along.x, 0.0, along.z).normalized()
	var side := along.cross(Vector3.UP).normalized()
	if left:
		side = -side
	var ground := Vector3(entry) + Vector3(0.5, 0.55, 0.5)
	var center := ground + side * radius
	var curve := TrackCurve.make_arc(center, along, side, radius, 0.0, sweep)
	var steps := maxi(720, int(radius * sweep * 2.0))
	var spans := TrackCurve.cells(curve, steps)
	var exit: Vector3i = spans[spans.size() - 1].cell if not spans.is_empty() else entry
	var exit_heading := TrackCurve.tangent(curve, 1.0)
	var ahead := exit + heading_cell(exit_heading)
	var before := entry - heading_cell(along)
	var pieces := TrackCurve.pieces(curve, LOOP, posmod(quarters, 4), before, ahead, {}, steps)
	var cells: Array[Vector3i] = []
	for piece: Dictionary in pieces:
		cells.append(piece.cell)
	return {"pieces": pieces, "cells": cells, "curve": curve, "center": center, "radius": radius, "entry": entry, "exit": exit, "exit_heading": exit_heading, "exit_cell_ahead": ahead, "before": before, "along": along, "side": side}


## How many pieces a curve of `radius` and `sweep` takes (its item price).
static func curve_piece_count(radius: int, sweep: int) -> int:
	return (curve_layout(Vector3i.ZERO, 0, float(radius), float(sweep)).cells as Array).size()


## The heading a track continuing a curve piece into `next_cell` should
## take: the curve's end tangent when `record` is its last piece and
## `next_cell` is the cell it joins ahead, the reversed start tangent when it
## is the first piece and `next_cell` lies behind it; Vector3.ZERO otherwise.
static func curve_end_heading(record: Dictionary, next_cell: Vector3i) -> Vector3:
	if not record.has("curve"):
		return Vector3.ZERO
	var curve: Dictionary = record.get("curve", {})
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var offset := next_cell - anchor
	if float(record.get("t1", 0.0)) >= 0.999:
		var forward := TrackCurve.tangent(curve, 1.0)
		if heading_cell(forward) == offset:
			return forward
	if float(record.get("t0", 1.0)) <= 0.001:
		var backward := -TrackCurve.tangent(curve, 0.0)
		if heading_cell(backward) == offset:
			return backward
	return Vector3.ZERO


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


# ---------------------------------------------------------------------------
# CoasterCraft cards 2 and 3 (docs/COASTERCRAFT_TRACKS.md): the Rail Switch
# (`rail_switch`, coaster_tool "bend" - the smooth lane switcher since
# 2026-09-20) and the Crossing (`rail_cross`, "cross").
# Both lay `rail_loop` records carrying a TrackCurve s-bend: the track leaves
# the entry cell heading along its rotation, drifts `lanes` lanes sideways
# (positive = to the RIGHT of travel, negative = left) with a smoothstep
# profile and lands `length` cells ahead heading along again, flat (rise 0,
# bank 0.35). The first cell is the entry, the last the exit; both ride at
# rail height (y + 0.55) so plain rails behind / ahead join them flush.
#
# The Crossing lays two such tracks of one length whose lanes swap - track
# A from lane 0 to lane `lanes`, track B from lane `lanes` to lane 0 - so
# they cross in the middle. A cell both curves pass through is ONE record
# carrying both: `curve` / `t0` / `t1` / `coaster_joints` are track A's,
# `curve_b` / `t0_b` / `t1_b` / `coaster_joints_b` track B's. `pair_for`
# resolves which of the two a rider is on from the cell it came from (or
# the track it was already riding when both pairs join that cell - the two
# curves run side by side through consecutive shared cells). Kettles
# (SiegeDefenseService._rail_point) simply ride such a cell as track A's.
# ---------------------------------------------------------------------------

const BEND_MIN_LENGTH := 3
const BEND_MAX_LENGTH := 40
const BEND_MAX_LANES := 6
const BEND_DEFAULT_LENGTH := 4
const BEND_DEFAULT_LANES := 1
const CROSS_DEFAULT_LENGTH := 8
const CROSS_DEFAULT_LANES := 2


static func bend_length_clamp(length: int) -> int:
	return clampi(length, BEND_MIN_LENGTH, BEND_MAX_LENGTH)


## Lanes clamped to -BEND_MAX_LANES..BEND_MAX_LANES, never 0 (a bend needs a
## side; 0 keeps the sign of `fallback`).
static func bend_lanes_clamp(lanes: int, fallback: int = 1) -> int:
	if lanes == 0:
		lanes = 1 if fallback >= 0 else -1
	return clampi(lanes, -BEND_MAX_LANES, BEND_MAX_LANES)


## The s-bend from `entry`'s ride point along rotation `quarters`: `lanes`
## to the right of travel (negative = left), landing `length` cells ahead.
static func bend_curve(entry: Vector3i, quarters: int, length: int, lanes: int) -> Dictionary:
	length = bend_length_clamp(length)
	lanes = bend_lanes_clamp(lanes)
	var along := Vector3(switch_along(quarters))
	var side := Vector3(switch_side(quarters)) * float(signi(lanes))
	var origin := Vector3(entry) + Vector3(0.5, 0.55, 0.5)
	return TrackCurve.make_s_bend(origin, along, side, float(length), float(absi(lanes)), 0.0)


## The Rail Switch's pieces: {pieces, cells, entry, exit, curve}.
static func bend_layout(entry: Vector3i, quarters: int, length: int, lanes: int) -> Dictionary:
	length = bend_length_clamp(length)
	lanes = bend_lanes_clamp(lanes)
	var along := switch_along(quarters)
	var side := switch_side(quarters) * signi(lanes)
	var exit := entry + along * length + side * absi(lanes)
	var curve := bend_curve(entry, quarters, length, lanes)
	var loop_rotation := 1 if along.x != 0 else 0
	var pieces := TrackCurve.pieces(curve, LOOP, loop_rotation, entry - along, exit + along, {}, maxi(720, length * 90))
	var cells: Array[Vector3i] = []
	for piece: Dictionary in pieces:
		cells.append(piece.cell)
	return {"pieces": pieces, "cells": cells, "entry": entry, "exit": exit, "curve": curve}


## How many pieces a Rail Switch of `length` / `lanes` takes (its price).
static func bend_piece_count(length: int, lanes: int) -> int:
	return (bend_layout(Vector3i.ZERO, 0, length, lanes).cells as Array).size()


## The Crossing's pieces: track A (entry -> `lanes` over) and track B (from
## `lanes` over -> the entry lane) merged cell by cell; a cell on both gets
## B's curve as `curve_b` / `t0_b` / `t1_b` and B's joints as `joints_b`.
## {pieces, cells, shared: Array[Vector3i], entry_a, exit_a, entry_b, exit_b}.
static func cross_layout(entry: Vector3i, quarters: int, length: int, lanes: int) -> Dictionary:
	length = bend_length_clamp(length)
	lanes = bend_lanes_clamp(lanes)
	var along := switch_along(quarters)
	var side := switch_side(quarters) * signi(lanes)
	var track_a := bend_layout(entry, quarters, length, lanes)
	var entry_b: Vector3i = entry + side * absi(lanes)
	var track_b := bend_layout(entry_b, quarters, length, -lanes)
	var pieces: Array[Dictionary] = []
	var cells: Array[Vector3i] = []
	var shared: Array[Vector3i] = []
	for piece: Dictionary in track_a.pieces:
		pieces.append(piece)
		cells.append(piece.cell)
	for piece: Dictionary in track_b.pieces:
		var cell: Vector3i = piece.cell
		var index := cells.find(cell)
		if index < 0:
			pieces.append(piece)
			cells.append(cell)
			continue
		var host: Dictionary = pieces[index]
		var extra: Dictionary = host.extra
		var b_extra: Dictionary = piece.extra
		extra["curve_b"] = b_extra.get("curve", {})
		extra["t0_b"] = float(b_extra.get("t0", 0.0))
		extra["t1_b"] = float(b_extra.get("t1", 1.0))
		host["joints_b"] = piece.joints
		shared.append(cell)
	return {"pieces": pieces, "cells": cells, "shared": shared, "entry_a": entry, "exit_a": track_a.exit, "entry_b": entry_b, "exit_b": track_b.exit, "along": along, "side": side}


static func cross_piece_count(length: int, lanes: int) -> int:
	return (cross_layout(Vector3i.ZERO, 0, length, lanes).cells as Array).size()


## True for a crossing's shared cell: a record carrying two curves.
static func has_second_curve(record: Dictionary) -> bool:
	return record.has("curve") and record.has("curve_b")


static func _joint_cells(record: Dictionary, key: String) -> Array[Vector3i]:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var cells: Array[Vector3i] = []
	var recorded: Variant = record.get(key)
	if recorded is Array:
		for joint in recorded:
			if joint is Array and joint.size() == 3:
				cells.append(anchor + Vector3i(int(joint[0]), int(joint[1]), int(joint[2])))
	return cells


## The one-curve view of `record` a rider arriving from `neighbour` is on:
## a record-shaped Dictionary (anchor, entity_id, rotation_quarters, curve,
## t0, t1, coaster_joints) plus "pair" ("a" / "b") and "joints"
## (Array[Vector3i], the pair's two cells). A record with one curve is its
## own pair "a". With two: the pair whose joints hold `neighbour`; when both
## do (consecutive shared cells) or `neighbour` is Vector3i.MAX, `preferred`.
static func pair_for(record: Dictionary, neighbour: Vector3i, preferred: String = "a") -> Dictionary:
	var joints_a := _joint_cells(record, "coaster_joints")
	var pair := record.duplicate()
	pair["pair"] = "a"
	pair["joints"] = joints_a
	if not has_second_curve(record):
		return pair
	var joints_b := _joint_cells(record, "coaster_joints_b")
	var in_a := joints_a.has(neighbour)
	var in_b := joints_b.has(neighbour)
	var use_b := false
	if in_a != in_b:
		use_b = in_b
	else:
		use_b = preferred == "b"
	if not use_b:
		return pair
	pair["pair"] = "b"
	pair["joints"] = joints_b
	pair["curve"] = record.get("curve_b", {})
	pair["t0"] = float(record.get("t0_b", 0.0))
	pair["t1"] = float(record.get("t1_b", 1.0))
	pair["coaster_joints"] = record.get("coaster_joints_b", [])
	pair.erase("curve_b")
	pair.erase("t0_b")
	pair.erase("t1_b")
	pair.erase("coaster_joints_b")
	return pair


## The other end of the pair a rider on `record` came into from `previous`
## (Vector3i.MAX when the pair has no other cell).
static func pair_partner(pair: Dictionary, previous: Vector3i) -> Vector3i:
	var joints: Array[Vector3i] = pair.get("joints", [] as Array[Vector3i])
	for cell: Vector3i in joints:
		if cell != previous:
			return cell
	return Vector3i.MAX
