class_name ExpoCoaster
extends RefCounted

## The Development Expo's CoasterCraft district (card F; handoff section 7,
## docs/DEVELOPMENT_EXPO.md). Two parts: a component gallery with one short,
## legible specimen of every current track technology, and the Grand
## Demonstration Coaster - one rideable circuit that uses all of them.
##
## Everything here is laid through the REAL lay tools' layouts
## (`CoasterRails.helix_layout` / `climb_layout` / `curve_layout` /
## `bend_layout` / `cross_layout`, all built on `TrackCurve`) and placed by
## `ExpoBuilder.place_track`, which writes each piece's curve, parameter range
## and recorded joints exactly as `InteractionService` commits a lay tool once
## its items are paid. Nothing is hand-placed as blocks, so the auto-shaping,
## banking, trestle trusses and flush joints all apply. The parked car is an
## ordinary `coaster_car` station: `CoasterCartService` registers it and
## `CoasterRide` boards it - there is no separate demo vehicle.
##
## An exhibit asks for a routine here with the manifest's `build` field; the
## routine owns its whole parcel (levelling included) and says where its sign
## should stand.

const STONE := 3
const CASTLE_STONE := 8
## Cells cleared above a gallery pad: the tallest specimen is the true loop.
const GALLERY_CLEAR := 12
## Cells cleared above the showpiece's pad: the lift hill is six over the
## rails and the true loop eight over that.
const SHOW_CLEAR := 20
## Heading of a piece laid toward +x / -x (`CoasterRails.switch_along`).
const EAST := 1
const WEST := 3

# --- The showpiece's geometry, in cells from its parcel's west / north edge.
## The station's first rail; the west U-turn bulges four cells west of it.
const SHOW_START_X := 8
## The boarding lane; the return lane is `SHOW_LANE_GAP` south of it.
const SHOW_LANE_Z := 12
## Two U-turn radii apart, so one U-turn carries a leg onto the other lane.
const SHOW_TURN_RADIUS := 3
const SHOW_LANE_GAP := SHOW_TURN_RADIUS * 2
const SHOW_STATION_RAILS := 6
const SHOW_CLIMB_LENGTH := 10
const SHOW_CLIMB_RISE := 6
const SHOW_CREST_LENGTH := 4
const SHOW_LOOP_DIAMETER := 8
const SHOW_SWITCH_LENGTH := 4
const SHOW_CROSS_LENGTH := 16
## Where the car waits on the station rails.
const SHOW_CAR_OFFSET := 2


## Runs the named authored routine over `origin`/`size` (the exhibit's solved
## parcel). Returns {ok, sign_cell, sign_facing}; `ok` false means the manifest
## named a routine this build does not have.
static func build(builder: ExpoBuilder, routine: String, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	match routine:
		"arrival":
			return _arrival(builder, exhibit_id, origin, size, ground_y)
		"rail":
			return _rail(builder, exhibit_id, origin, size, ground_y)
		"slope":
			return _slope(builder, exhibit_id, origin, size, ground_y)
		"loop":
			return _loop(builder, exhibit_id, origin, size, ground_y)
		"switch":
			return _switch(builder, exhibit_id, origin, size, ground_y)
		"cross":
			return _cross(builder, exhibit_id, origin, size, ground_y)
		"curve":
			return _curve(builder, exhibit_id, origin, size, ground_y)
		"climb":
			return _climb(builder, exhibit_id, origin, size, ground_y)
		"mine_cart":
			return _cart_booth(builder, exhibit_id, origin, size, ground_y, "mine_cart")
		"coaster_car":
			return _cart_booth(builder, exhibit_id, origin, size, ground_y, CoasterRails.CAR)
		"shop":
			return _shop(builder, exhibit_id, origin, size, ground_y)
		"grand_coaster":
			return _grand_coaster(builder, exhibit_id, origin, size, ground_y)
	return {"ok": false, "reason": "UNKNOWN_BUILD"}


# ------------------------------------------------------------------ helpers

## Levels the parcel and hands back the rail level on it (the parcel's own y:
## the top solid cell is `ground_y`, so track sits one above it).
static func _pad(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int, clear: int, surface: int = STONE) -> int:
	builder.level_area(Vector3i(origin.x, ground_y, origin.z), size.x, size.z, surface, clear, "coaster:" + exhibit_id)
	return ground_y + 1


## A straight run of plain rails as lay-tool pieces, so they are placed with
## the same strict, free path as every curve piece.
static func _rail_run(from_cell: Vector3i, step: Vector3i, count: int) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	for index in range(count):
		pieces.append({"cell": from_cell + step * index, "entity_id": CoasterRails.FLAT, "rotation": 0, "joints": [] as Array[Vector3i], "extra": {}})
	return pieces


## The sign of a track specimen stands at the near corner of its parcel, where
## a visitor reads it with the specimen behind it.
static func _corner(origin: Vector3i) -> Vector3i:
	return origin


## The pieces of a lay-tool layout, typed for `ExpoBuilder.place_track`.
static func _pieces(layout: Dictionary) -> Array:
	var value: Variant = layout.get("pieces", [])
	return value if value is Array else []


## One cell field of a lay-tool layout (`entry`, `exit`, `landing` ...).
static func _cell_at(layout: Dictionary, key: String) -> Vector3i:
	var value: Variant = layout.get(key, Vector3i.ZERO)
	return value if value is Vector3i else Vector3i.ZERO


# ------------------------------------------------------------ the gallery

## The district's arrival plaza: paved, lit, and signed with the routes on.
static func _arrival(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR, CASTLE_STONE)
	builder.place_entity("post_lantern", Vector3i(origin.x + 1, y, origin.z + 1), 0, "coaster:" + exhibit_id)
	builder.place_entity("post_lantern", Vector3i(origin.x + 1, y, origin.z + size.z - 2), 0, "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": Vector3i(origin.x + size.x / 2, y, origin.z + size.z / 2), "sign_facing": "west"}


## Rail: the plain track piece, a straight run of it.
static func _rail(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	builder.place_track(_rail_run(Vector3i(origin.x + 2, y, origin.z + 5), Vector3i(1, 0, 0), 8), "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## Rail Slope: rails, the slope, rails one level up on the bank it climbs.
static func _slope(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	var lane := origin.z + 5
	# The bank the slope climbs onto: one cell of stone at rail level, so the
	# rails on top of it stand one level over the lower run.
	builder.fill_box(Vector3i(origin.x + 7, y, lane - 2), Vector3i(3, 1, 5), STONE, false, "coaster:" + exhibit_id)
	builder.place_track(_rail_run(Vector3i(origin.x + 2, y, lane), Vector3i(1, 0, 0), 4), "coaster:" + exhibit_id)
	builder.place_track([{"cell": Vector3i(origin.x + 6, y, lane), "entity_id": CoasterRails.SLOPE, "rotation": EAST, "joints": [] as Array[Vector3i], "extra": {}}], "coaster:" + exhibit_id)
	builder.place_track(_rail_run(Vector3i(origin.x + 7, y + 1, lane), Vector3i(1, 0, 0), 3), "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## Rail Loop: the true loop (one helix turn drifting a lane) between rails.
static func _loop(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	var lane := origin.z + 4
	var entry := Vector3i(origin.x + 6, y, lane)
	var layout := CoasterRails.helix_layout(entry, EAST, 5)
	builder.place_track(_rail_run(Vector3i(origin.x + 3, y, lane), Vector3i(1, 0, 0), 3), "coaster:" + exhibit_id)
	builder.place_track(_pieces(layout), "coaster:" + exhibit_id)
	builder.place_track(_rail_run(Vector3i(origin.x + 7, y, lane + 1), Vector3i(1, 0, 0), 3), "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## Rail Switch: the smooth lane switcher, one lane over in four cells.
static func _switch(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	var lane := origin.z + 4
	var entry := Vector3i(origin.x + 3, y, lane)
	var layout := CoasterRails.bend_layout(entry, EAST, CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
	builder.place_track(_rail_run(Vector3i(origin.x + 1, y, lane), Vector3i(1, 0, 0), 2), "coaster:" + exhibit_id)
	builder.place_track(_pieces(layout), "coaster:" + exhibit_id)
	var exit_cell := _cell_at(layout, "exit")
	builder.place_track(_rail_run(exit_cell + Vector3i(1, 0, 0), Vector3i(1, 0, 0), 2), "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## Rail Cross: two lane switchers swapping lanes, crossing in the middle.
static func _cross(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	var entry := Vector3i(origin.x + 2, y, origin.z + 3)
	var layout := CoasterRails.cross_layout(entry, EAST, CoasterRails.CROSS_DEFAULT_LENGTH, CoasterRails.CROSS_DEFAULT_LANES)
	for cell: Vector3i in [_cell_at(layout, "entry_a"), _cell_at(layout, "entry_b")]:
		builder.place_track(_rail_run(cell - Vector3i(1, 0, 0), Vector3i(-1, 0, 0), 1), "coaster:" + exhibit_id)
	builder.place_track(_pieces(layout), "coaster:" + exhibit_id)
	for cell: Vector3i in [_cell_at(layout, "exit_a"), _cell_at(layout, "exit_b")]:
		builder.place_track(_rail_run(cell + Vector3i(1, 0, 0), Vector3i(1, 0, 0), 1), "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## Rail Curve: a banked 90-degree arc with a plain rail on each end.
static func _curve(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	var entry := Vector3i(origin.x + 2, y, origin.z + 2)
	var layout := CoasterRails.curve_layout(entry, EAST, 3.0, 90.0)
	builder.place_track(_rail_run(entry - Vector3i(1, 0, 0), Vector3i(-1, 0, 0), 1), "coaster:" + exhibit_id)
	builder.place_track(_pieces(layout), "coaster:" + exhibit_id)
	var ahead := _cell_at(layout, "exit_cell_ahead")
	var step := ahead - _cell_at(layout, "exit")
	builder.place_track(_rail_run(ahead, step, 2), "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## Rail Climb: slope-in, grade and slope-out as one curve, up onto its landing.
static func _climb(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	var lane := origin.z + 5
	var entry := Vector3i(origin.x + 2, y, lane)
	var layout := CoasterRails.climb_layout(entry, EAST, 8, 4)
	builder.place_track(_rail_run(entry - Vector3i(1, 0, 0), Vector3i(-1, 0, 0), 1), "coaster:" + exhibit_id)
	builder.place_track(_pieces(layout), "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## Mine Cart / Coaster Car: the rider standing on its own run of rails.
static func _cart_booth(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int, entity_id: String) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR)
	var lane := origin.z + 5
	builder.place_track(_rail_run(Vector3i(origin.x + 2, y, lane), Vector3i(1, 0, 0), 8), "coaster:" + exhibit_id)
	builder.place_entity(entity_id, Vector3i(origin.x + 4, y + 1, lane), 0, "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


## The CoasterCraft Shop, placed and usable: right-click opens its book.
static func _shop(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var y := _pad(builder, exhibit_id, origin, size, ground_y, GALLERY_CLEAR, CASTLE_STONE)
	builder.place_entity("coastercraft_shop", Vector3i(origin.x + size.x / 2 - 1, y, origin.z + size.z / 2), 0, "coaster:" + exhibit_id)
	return {"ok": true, "sign_cell": _corner(origin)}


# ------------------------------------------- the Grand Demonstration Coaster

## One closed, rideable circuit that uses every current track family. In plan
## it is a figure eight: the boarding lane runs east past the lift hill, the
## crest, the drop and the true loop, a lane switcher brings the track back
## onto its lane, the crossing swaps it onto the return lane, a U-turn brings
## it back heading west along the other track of the same crossing, and a
## second U-turn returns it to the station. Both tracks of the crossing are
## therefore ridden on one lap - it is a real crossing, not a spur.
##
## Order along the ride: station -> lift hill (Climb +6) -> crest -> drop
## (Climb -6) -> true loop (Rail Loop) -> lane switcher (Rail Switch) ->
## crossing track A (Rail Cross) -> U-turn (Rail Curve 180) -> crossing track
## B -> U-turn -> station.
static func _grand_coaster(builder: ExpoBuilder, exhibit_id: String, origin: Vector3i, size: Vector3i, ground_y: int) -> Dictionary:
	var label := "coaster:" + exhibit_id
	var y := _pad(builder, exhibit_id, origin, size, ground_y, SHOW_CLEAR)
	var lane_a := origin.z + SHOW_LANE_Z
	var lane_b := lane_a + SHOW_LANE_GAP
	var x0 := origin.x + SHOW_START_X
	var east := Vector3i(1, 0, 0)
	# The station: a castle-stone platform along the boarding lane.
	builder.level_area(Vector3i(x0 - 1, ground_y, lane_a - 4), SHOW_STATION_RAILS + 2, 3, CASTLE_STONE, SHOW_CLEAR, label)
	# Leg one, east along the boarding lane.
	builder.place_track(_rail_run(Vector3i(x0, y, lane_a), east, SHOW_STATION_RAILS), label)
	var lift := CoasterRails.climb_layout(Vector3i(x0 + SHOW_STATION_RAILS, y, lane_a), EAST, SHOW_CLIMB_LENGTH, SHOW_CLIMB_RISE)
	builder.place_track(_pieces(lift), label)
	var crest := CoasterRails.climb_layout(_cell_at(lift, "landing") + east, EAST, SHOW_CREST_LENGTH, 0)
	builder.place_track(_pieces(crest), label)
	var drop := CoasterRails.climb_layout(_cell_at(crest, "landing") + east, EAST, SHOW_CLIMB_LENGTH, -SHOW_CLIMB_RISE)
	builder.place_track(_pieces(drop), label)
	var landing := _cell_at(drop, "landing")
	builder.place_track(_rail_run(landing + east, east, 2), label)
	# The true loop: it leaves the ground at its entry and lands one lane over.
	var loop := CoasterRails.helix_layout(landing + east * 3, EAST, SHOW_LOOP_DIAMETER)
	builder.place_track(_pieces(loop), label)
	# The lane switcher brings the track back onto the boarding lane.
	var switcher := CoasterRails.bend_layout(_cell_at(loop, "exit") + east, EAST, SHOW_SWITCH_LENGTH, -1)
	builder.place_track(_pieces(switcher), label)
	var switch_exit := _cell_at(switcher, "exit")
	builder.place_track(_rail_run(switch_exit + east, east, 3), label)
	# The crossing: track A carries this leg onto the return lane, track B
	# carries the far leg back onto the boarding lane. They cross in the middle.
	var cross_entry := switch_exit + east * 4
	var crossing := CoasterRails.cross_layout(cross_entry, EAST, SHOW_CROSS_LENGTH, SHOW_LANE_GAP)
	builder.place_track(_pieces(crossing), label)
	var exit_a := _cell_at(crossing, "exit_a")
	var exit_b := _cell_at(crossing, "exit_b")
	builder.place_track(_rail_run(exit_a + east, east, 3), label)
	builder.place_track(_rail_run(exit_b + east, east, 3), label)
	# The east U-turn takes the return lane back onto the boarding lane,
	# heading west (it turns to the LEFT of travel, the inside of the eight).
	var east_turn := CoasterRails.curve_layout(exit_a + east * 4, EAST, float(SHOW_TURN_RADIUS), 180.0, true)
	builder.place_track(_pieces(east_turn), label)
	# Leg two runs west along the boarding lane through the crossing's other
	# track, then west along the return lane to the second U-turn, which puts
	# the car back on the station rails.
	builder.place_track(_rail_run(Vector3i(x0, y, lane_b), east, cross_entry.x - x0), label)
	var west_turn := CoasterRails.curve_layout(Vector3i(x0 - 1, y, lane_b), WEST, float(SHOW_TURN_RADIUS), 180.0)
	builder.place_track(_pieces(west_turn), label)
	# The car waits on the station rails, parked and ready to board.
	builder.place_entity(CoasterRails.CAR, Vector3i(x0 + SHOW_CAR_OFFSET, y + 1, lane_a), 0, label)
	# The station board reads back at a visitor arriving from the gallery.
	return {"ok": true, "sign_cell": Vector3i(x0 + SHOW_CAR_OFFSET, y, lane_a - 3), "sign_facing": "north"}


## Where the showpiece's station stands, for the diagnostics and the docs:
## {station: the first rail, car: the parked car's cell, lane_a, lane_b}.
static func show_station(origin: Vector3i) -> Dictionary:
	var y := origin.y
	var lane_a := origin.z + SHOW_LANE_Z
	return {"station": Vector3i(origin.x + SHOW_START_X, y, lane_a),
		"car": Vector3i(origin.x + SHOW_START_X + SHOW_CAR_OFFSET, y + 1, lane_a),
		"lane_a": lane_a, "lane_b": lane_a + SHOW_LANE_GAP}
