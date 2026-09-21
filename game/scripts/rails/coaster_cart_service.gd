class_name CoasterCartService
extends Node

## Coaster rails side project (docs/COASTER_RAILS.md): mine carts ride their
## connected track end to end at a constant speed. GameSession adds this node
## only while a `mine_cart` exists and calls `advance` each frame; the kettle's
## rail riding in SiegeDefenseService is untouched.
##
## Traversal: at each cell the cart picks the joined cell with the smallest
## turn from its arrival direction, never the cell it came from. A curved loop
## piece (a `rail_loop` with a joint on another level) that is not yet visited
## and lies within a 90-degree turn wins over a flat continuation, so the cart
## climbs into the loop instead of running straight through the loop's shared
## bottom row; a curved piece already ridden this pass is shunned, so the cart
## leaves the loop onto the exit. At a dead end it turns around and forgets
## what it visited. No gravity: constant speed.
##
## CoasterCraft crossing (docs/COASTERCRAFT_TRACKS.md card 3): a cell that
## carries two curves (`CoasterRails.has_second_curve`) is left toward the
## partner of the cell the cart came from (`CoasterRails.pair_for`), and its
## ride point / up come from that pair's curve; the rider remembers the pair
## (`track`) so consecutive shared cells, where both pairs join, stay on it.
##
## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): a cart registered
## `parked` (the `coaster_car`) stands still until `set_parked(id, false)`;
## `set_speed(id, cells_per_second)` overrides the entity's `rail_speed` for
## one cart (the rider's 1-9 keys). `cart_rig(id)` / `travel_direction(id)` feed
## the ride camera.
##
## Hauling (docs/INDUSTRY.md): a `mine_cart` carries `cargo` ({item_id: count},
## saved in its station record, `CART_CARGO` items at most). When it reaches a
## track cell with an `ore_bin` beside it (the four sides, same level or one
## below) it loads what the bin holds up to the limit; beside a `warehouse` it
## unloads everything that fits. Bins are sources and warehouses are sinks:
## nothing goes back into a bin. One transfer per pass: the cell of the last
## transfer is remembered (`last_dock`) and no dock happens until the cart is
## at least `REDOCK_CELLS` cells from it. The rideable `coaster_car` never hauls.

## Emitted after a cart loaded or unloaded: `moved` is {item_id: count}.
signal cargo_changed(instance_id: String, moved: Dictionary, loaded: bool, cell: Vector3i)

## Turn-score bonus for an unvisited loop piece and penalty for a visited one,
## in degrees of turn (a straight flat exit scores 0, a 45-degree climb 45).
const LOOP_BONUS := 150.0
const LOOP_PENALTY := 60.0
const REACH_EPSILON := 0.02
const DEFAULT_SPEED := 3.0
## Hauling: items a mine cart carries at most, the station ids it docks at
## and how far it must travel from a dock before it docks again.
const CART_CARGO := 16
const HAULER := "mine_cart"
const ORE_BIN := "ore_bin"
const WAREHOUSE := "warehouse"
const REDOCK_CELLS := 3
const DOCK_SIDES: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

var workstations: WorkstationService
## instance_id -> the placed cart body (its "CartRig" child is moved).
var _bodies: Dictionary = {}
## instance_id -> {cell, previous, target, visited, trail, up}.
var _riders: Dictionary = {}
## instance_id -> true while the cart must not move (a car without a rider).
var _parked: Dictionary = {}
## instance_id -> cells per second overriding the entity's rail_speed.
var _speeds: Dictionary = {}
## instance_id -> the last non-zero unit travel direction.
var _directions: Dictionary = {}


func initialize(station_service: WorkstationService) -> void:
	workstations = station_service


func register_cart(instance_id: String, body: Node3D, parked: bool = false) -> void:
	_bodies[instance_id] = body
	if parked:
		_parked[instance_id] = true


func unregister_cart(instance_id: String) -> void:
	_bodies.erase(instance_id)
	_riders.erase(instance_id)
	_parked.erase(instance_id)
	_speeds.erase(instance_id)
	_directions.erase(instance_id)


func set_parked(instance_id: String, parked: bool) -> void:
	if parked:
		_parked[instance_id] = true
	else:
		_parked.erase(instance_id)


func is_parked(instance_id: String) -> bool:
	return _parked.has(instance_id)


## Overrides the entity's rail_speed for one cart (cells per second); a value
## of zero or less restores the entity speed.
func set_speed(instance_id: String, cells_per_second: float) -> void:
	if cells_per_second > 0.0:
		_speeds[instance_id] = cells_per_second
	else:
		_speeds.erase(instance_id)


func speed_of(instance_id: String) -> float:
	if _speeds.has(instance_id):
		return float(_speeds[instance_id])
	if workstations == null:
		return DEFAULT_SPEED
	var record := workstations.station(instance_id)
	return float(workstations.registry.entity(str(record.get("entity_id", ""))).get("cart", {}).get("rail_speed", DEFAULT_SPEED))


## The moving "CartRig" node of a registered cart, or null.
## How fast the body's heading follows the track (per second).
const HEADING_RATE := 10.0


func cart_rig(instance_id: String) -> Node3D:
	var body: Node3D = _bodies.get(instance_id)
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null("CartRig")


## The cart's last unit travel direction (world), -z of the body until it moves.
func travel_direction(instance_id: String) -> Vector3:
	if _directions.has(instance_id):
		return _directions[instance_id]
	var body: Node3D = _bodies.get(instance_id)
	if body != null and is_instance_valid(body):
		return -body.global_basis.z
	return Vector3.FORWARD


func cart_count() -> int:
	return _bodies.size()


## The track cell a cart currently sits on (diagnostics).
func rider_cell(instance_id: String) -> Vector3i:
	var rider: Dictionary = _riders.get(instance_id, {})
	return rider.get("cell", Vector3i(0, -9999, 0))


## The track cell of every cart (the auto-shape pass leaves those rails alone).
func rider_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for instance_id: String in _bodies.keys():
		var rider: Dictionary = _riders.get(instance_id, {})
		var record := workstations.station(instance_id) if workstations != null else {}
		cells.append(rider.get("cell", Vector3i(record.get("anchor", Vector3i.ZERO)) + Vector3i.DOWN))
	return cells


## Every track cell a cart has reached since it was placed (diagnostics).
func trail(instance_id: String) -> Dictionary:
	var rider: Dictionary = _riders.get(instance_id, {})
	return rider.get("trail", {}).duplicate()


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0 or workstations == null:
		return
	var tracks := CoasterRails.track_records(workstations.stations)
	for instance_id: String in _bodies.keys():
		var body: Node3D = _bodies[instance_id]
		if body == null or not is_instance_valid(body):
			_bodies.erase(instance_id)
			continue
		if _parked.has(instance_id):
			continue
		var moving_rig: Node3D = body.get_node_or_null("CartRig")
		var record := workstations.station(instance_id)
		if moving_rig == null or record.is_empty():
			continue
		_ride(instance_id, body, moving_rig, record, tracks, delta)


func _ride(instance_id: String, body: Node3D, rig: Node3D, record: Dictionary, tracks: Dictionary, delta: float) -> void:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var home := anchor + Vector3i.DOWN
	var chain := CoasterRails.chain(workstations.stations, home)
	var rider: Dictionary = _riders.get(instance_id, {"cell": home, "previous": Vector3i.MAX, "target": Vector3i.MAX, "visited": {}, "trail": {home: true}, "up": Vector3.UP})
	var current: Vector3i = rider.cell
	if not chain.has(current):
		current = home
		rider.previous = Vector3i.MAX
		rider.target = Vector3i.MAX
		rider.visited = {}
	var target: Vector3i = rider.target
	if target == Vector3i.MAX or not chain.has(target) or target == current:
		target = _choose_next(chain, tracks, current, rider)
	var speed := speed_of(instance_id)
	var up: Vector3 = rider.up
	var track := str(rider.get("track", "a"))
	var desired := _ride_point(tracks, target, up, current, track)
	var travel := desired - rig.global_position
	var moved := rig.global_position.move_toward(desired, speed * delta)
	rig.global_position = moved
	if travel.length() > 0.001:
		# Heading: the chord from the previous cell's point to the target's
		# point (owner 2026-09-20: pointing at the very next point made the
		# body flick sideways where two points sit close together on the
		# circle or across a switcher), eased so no cell boundary snaps it.
		var chord := travel.normalized()
		var previous_cell: Vector3i = rider.get("previous", Vector3i.MAX)
		if previous_cell != Vector3i.MAX and chain.has(previous_cell):
			var from_previous := desired - _ride_point(tracks, previous_cell, up, current, track)
			if from_previous.length() > 0.3:
				chord = from_previous.normalized()
		var forward: Vector3 = _directions.get(instance_id, chord)
		if forward.length() < 0.5 or forward.dot(chord) < -0.2:
			forward = chord
		else:
			forward = forward.slerp(chord, minf(1.0, delta * HEADING_RATE)).normalized()
		_directions[instance_id] = forward
		var basis_up := up
		if absf(forward.dot(basis_up)) > 0.98:
			basis_up = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		rig.global_basis = Basis.looking_at(forward, basis_up)
	if moved.distance_to(desired) < REACH_EPSILON and target != current:
		rider.previous = current
		current = target
		rider.trail[current] = true
		_dock(instance_id, record, current, rider)
		if _is_curved(chain, tracks, current):
			rider.visited[current] = true
		elif not rider.visited.is_empty() and not _beside_curve(chain, tracks, current):
			# Clear of the loop on flat track: forget it, so a closed circuit
			# takes the loop again on the next lap (owner sandbox 2026-09-20).
			rider.visited = {}
		var next := _choose_next(chain, tracks, current, rider)
		rider.target = next
		rider.up = _up_at(tracks, current, rider.previous, next, up, str(rider.get("track", "a")))
	else:
		rider.target = target
	rider.cell = current
	_riders[instance_id] = rider
	body.set_meta("rail_cell", current)
	# The clickable/blocking shapes ride along so dismantling aims at the cart.
	for child in body.get_children():
		if child is CollisionShape3D:
			if not child.has_meta("rest_position"):
				child.set_meta("rest_position", child.position)
			child.position = child.get_meta("rest_position") + rig.position


## The cargo of a cart, {item_id: count} (a copy).
func cargo(instance_id: String) -> Dictionary:
	if workstations == null:
		return {}
	return workstations.station(instance_id).get("cargo", {}).duplicate()


func cargo_count(instance_id: String) -> int:
	var total := 0
	for value in cargo(instance_id).values():
		total += int(value)
	return total


## Loads from bins / unloads into warehouses beside `cell` (see the header).
func _dock(instance_id: String, record: Dictionary, cell: Vector3i, rider: Dictionary) -> void:
	if str(record.get("entity_id", "")) != HAULER:
		return
	var last_dock: Vector3i = rider.get("last_dock", Vector3i.MAX)
	if last_dock != Vector3i.MAX and Vector3(cell - last_dock).length() < float(REDOCK_CELLS):
		return
	var bins: Array[String] = []
	var warehouses: Array[String] = []
	for side: Vector3i in DOCK_SIDES:
		for level: Vector3i in [Vector3i.ZERO, Vector3i.DOWN]:
			var owner := workstations.footprints.owner_at(cell + side + level)
			if owner.is_empty():
				continue
			var entity_id := str(workstations.stations.get(owner, {}).get("entity_id", ""))
			if entity_id == ORE_BIN and not bins.has(owner):
				bins.append(owner)
			elif entity_id == WAREHOUSE and not warehouses.has(owner):
				warehouses.append(owner)
	if bins.is_empty() and warehouses.is_empty():
		return
	var live: Dictionary = workstations.stations[instance_id]
	var held: Dictionary = live.get("cargo", {})
	# Unload first (sinks), then load (sources), so a cell with both beside it
	# empties the cart before refilling it.
	var unloaded: Dictionary = {}
	for warehouse_id: String in warehouses:
		for item_id: String in held.keys():
			var put := workstations.container_put(warehouse_id, item_id, int(held[item_id]))
			if not put.get("ok", false):
				continue
			var moved := int(put.details.moved)
			held[item_id] = int(held[item_id]) - moved
			if int(held[item_id]) <= 0:
				held.erase(item_id)
			unloaded[item_id] = int(unloaded.get(item_id, 0)) + moved
	var loaded: Dictionary = {}
	for bin_id: String in bins:
		for stack in workstations.container_slots(bin_id):
			var item_id := str(stack.get("item_id", ""))
			var room := CART_CARGO - _total(held)
			if item_id.is_empty() or room <= 0:
				continue
			var take := workstations.container_take(bin_id, item_id, mini(room, int(stack.get("count", 0))))
			if not take.get("ok", false):
				continue
			var moved := int(take.details.moved)
			held[item_id] = int(held.get(item_id, 0)) + moved
			loaded[item_id] = int(loaded.get(item_id, 0)) + moved
	if unloaded.is_empty() and loaded.is_empty():
		return
	live["cargo"] = held
	rider.last_dock = cell
	if not unloaded.is_empty():
		cargo_changed.emit(instance_id, unloaded, false, cell)
	if not loaded.is_empty():
		cargo_changed.emit(instance_id, loaded, true, cell)


func _total(counts: Dictionary) -> int:
	var total := 0
	for value in counts.values():
		total += int(value)
	return total


## The next cell for a cart at `current` (see the header); the previous cell
## when nothing else joins (turn around), `current` on a one-cell chain.
func _choose_next(chain: Dictionary, tracks: Dictionary, current: Vector3i, rider: Dictionary) -> Vector3i:
	var previous: Vector3i = rider.get("previous", Vector3i.MAX)
	var visited: Dictionary = rider.get("visited", {})
	var joined: Array = chain.get(current, [])
	var candidates: Array[Vector3i] = []
	var here: Dictionary = tracks.get(current, {})
	if CoasterRails.has_second_curve(here):
		# A crossing's shared cell: keep to the track the cart arrived on.
		var pair := CoasterRails.pair_for(here, previous, str(rider.get("track", "a")))
		rider.track = str(pair.pair)
		var partner := CoasterRails.pair_partner(pair, previous)
		if partner != Vector3i.MAX and joined.has(partner):
			return partner
	else:
		rider.track = "a"
	for cell in joined:
		if cell is Vector3i and cell != previous:
			candidates.append(cell)
	if candidates.is_empty():
		if previous != Vector3i.MAX and chain.has(previous):
			rider.visited = {}
			return previous
		return current
	var arrival := Vector3.ZERO
	if previous != Vector3i.MAX:
		arrival = Vector3(current - previous).normalized()
	var best := candidates[0]
	var best_score := INF
	for cell in candidates:
		var direction := Vector3(cell - current).normalized()
		var score := 0.0
		if arrival != Vector3.ZERO:
			score = rad_to_deg(acos(clampf(arrival.dot(direction), -1.0, 1.0)))
		if _is_curved(chain, tracks, cell):
			if visited.has(cell):
				score += LOOP_PENALTY
			elif score <= 90.0:
				score -= LOOP_BONUS
		if score < best_score:
			best_score = score
			best = cell
	return best


## True when any cell joined to `cell` is part of a loop's circle.
func _beside_curve(chain: Dictionary, tracks: Dictionary, cell: Vector3i) -> bool:
	for joined in chain.get(cell, []):
		if joined is Vector3i and _is_curved(chain, tracks, joined):
			return true
	return false


func _is_loop(tracks: Dictionary, cell: Vector3i) -> bool:
	var record: Dictionary = tracks.get(cell, {})
	return str(record.get("entity_id", "")) == CoasterRails.LOOP


## A loop piece with a joint on another level: part of the circle itself,
## unlike the flat lead-in, bottom row, top row and exit pieces.
func _is_curved(chain: Dictionary, tracks: Dictionary, cell: Vector3i) -> bool:
	if not _is_loop(tracks, cell):
		return false
	var joined: Array = chain.get(cell, [])
	for other in joined:
		if other is Vector3i and other.y != cell.y:
			return true
	return false


## Where the cart's wheels rest in `cell`: on the rail top of flats and
## slopes, at a loop piece's centre nudged along the cart's up vector.
func _ride_point(tracks: Dictionary, cell: Vector3i, up: Vector3, neighbour: Vector3i = Vector3i.MAX, track: String = "a") -> Vector3:
	var record: Dictionary = tracks.get(cell, {"anchor": cell, "entity_id": CoasterRails.FLAT})
	if CoasterRails.has_second_curve(record):
		record = CoasterRails.pair_for(record, neighbour, track)
	var point := CoasterRails.ride_point(record)
	if _is_loop(tracks, cell):
		point += up * 0.05
	return point


## The cart's up vector leaving `cell`: straight up on flats and slopes; on a
## loop piece the curvature normal (departure minus arrival direction), so the
## cart leans into the circle and hangs upside down over the top.
func _up_at(tracks: Dictionary, cell: Vector3i, previous: Vector3i, next: Vector3i, fallback: Vector3, track: String = "a") -> Vector3:
	if not _is_loop(tracks, cell):
		return Vector3.UP
	# A loop with a known centre: lean straight at it (owner 2026-09-20: the
	# cell-quantised curvature normal flipped on stair-step cells and rolled
	# the rider's view); the point toward the centre is the inward normal.
	var record: Dictionary = tracks.get(cell, {})
	if CoasterRails.has_second_curve(record):
		record = CoasterRails.pair_for(record, previous, track)
	if record.has("curve"):
		return TrackCurve.up_at(record.get("curve", {}), TrackCurve.piece_t(record))
	var lean := CoasterRails.lean_center(record)
	if lean != Vector3.INF:
		var toward := lean - _ride_point(tracks, cell, fallback)
		if toward.length() > 0.05:
			return toward.normalized()
	if previous == Vector3i.MAX or next == cell:
		return fallback
	var arrival := Vector3(cell - previous).normalized()
	var departure := Vector3(next - cell).normalized()
	var normal := departure - arrival
	if normal.length() < 0.05:
		return fallback
	return normal.normalized()
