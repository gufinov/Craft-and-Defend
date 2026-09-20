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
## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): a cart registered
## `parked` (the `coaster_car`) stands still until `set_parked(id, false)`;
## `set_speed(id, cells_per_second)` overrides the entity's `rail_speed` for
## one cart (the rider's 1-9 keys). `cart_rig(id)` / `travel_direction(id)` feed
## the ride camera.

## Turn-score bonus for an unvisited loop piece and penalty for a visited one,
## in degrees of turn (a straight flat exit scores 0, a 45-degree climb 45).
const LOOP_BONUS := 150.0
const LOOP_PENALTY := 60.0
const REACH_EPSILON := 0.02
const DEFAULT_SPEED := 3.0

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
	var desired := _ride_point(tracks, target, up)
	var travel := desired - rig.global_position
	var moved := rig.global_position.move_toward(desired, speed * delta)
	rig.global_position = moved
	if travel.length() > 0.001:
		var forward := travel.normalized()
		_directions[instance_id] = forward
		var basis_up := up
		if absf(forward.dot(basis_up)) > 0.98:
			basis_up = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		rig.global_basis = Basis.looking_at(forward, basis_up)
	if moved.distance_to(desired) < REACH_EPSILON and target != current:
		rider.previous = current
		current = target
		rider.trail[current] = true
		if _is_curved(chain, tracks, current):
			rider.visited[current] = true
		elif not rider.visited.is_empty() and not _beside_curve(chain, tracks, current):
			# Clear of the loop on flat track: forget it, so a closed circuit
			# takes the loop again on the next lap (owner sandbox 2026-09-20).
			rider.visited = {}
		var next := _choose_next(chain, tracks, current, rider)
		rider.target = next
		rider.up = _up_at(tracks, current, rider.previous, next, up)
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


## The next cell for a cart at `current` (see the header); the previous cell
## when nothing else joins (turn around), `current` on a one-cell chain.
func _choose_next(chain: Dictionary, tracks: Dictionary, current: Vector3i, rider: Dictionary) -> Vector3i:
	var previous: Vector3i = rider.get("previous", Vector3i.MAX)
	var visited: Dictionary = rider.get("visited", {})
	var joined: Array = chain.get(current, [])
	var candidates: Array[Vector3i] = []
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
func _ride_point(tracks: Dictionary, cell: Vector3i, up: Vector3) -> Vector3:
	var record: Dictionary = tracks.get(cell, {"anchor": cell, "entity_id": CoasterRails.FLAT})
	var point := CoasterRails.ride_point(record)
	if _is_loop(tracks, cell):
		point += up * 0.05
	return point


## The cart's up vector leaving `cell`: straight up on flats and slopes; on a
## loop piece the curvature normal (departure minus arrival direction), so the
## cart leans into the circle and hangs upside down over the top.
func _up_at(tracks: Dictionary, cell: Vector3i, previous: Vector3i, next: Vector3i, fallback: Vector3) -> Vector3:
	if not _is_loop(tracks, cell):
		return Vector3.UP
	if previous == Vector3i.MAX or next == cell:
		return fallback
	var arrival := Vector3(cell - previous).normalized()
	var departure := Vector3(next - cell).normalized()
	var normal := departure - arrival
	if normal.length() < 0.05:
		return fallback
	return normal.normalized()
