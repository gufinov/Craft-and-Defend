class_name SiegeDefenseService
extends Node3D

signal state_changed(message: String)
signal feedback(message: String)

const ARC_SEGMENTS := 18
## Turntable turn rate toward the target, radians per second.
const TURN_RATE := 2.4
## Catapult arm angles about the axle (radians about x on "CatapultArm").
const ARM_REST := -0.40
const ARM_THROWN := -1.95
const ARM_THROW_SECONDS := 0.16
## Ballista slider travel along the stock (local z on "BallistaSlider"):
## drawn (loaded, rest) versus released after a shot.
const SLIDER_DRAWN_Z := 0.55
const SLIDER_RELEASED_Z := -0.15
## Kettle pot tilt about x when dumping ("KettlePot").
const POT_DUMP_TILT := -1.35
const POT_DUMP_SECONDS := 0.35
## Cannon barrel recoil distance along its local +z.
const CANNON_RECOIL := 0.32
const RAIL_STEPS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var workstations: WorkstationService
var core_defense: CoreDefenseService
var fire: FireService
var world: WorldAdapter
var visual_bodies: Dictionary = {}
var _blocked_reported: Dictionary = {}
var _reload_timers: Dictionary = {}
## Impact resolutions in flight: [{at, instance_id, munition, point, target}].
var _pending_impacts: Array[Dictionary] = []
## Rail riders (kettles): instance_id -> {cell: current rail cell, path: [cells]}.
var _rail_riders: Dictionary = {}

## Seconds between auto-reload attempts for an empty weapon.
const RELOAD_POLL_SECONDS := 1.0


func initialize(station_service: WorkstationService, core_service: CoreDefenseService, fire_service: FireService = null, world_adapter: WorldAdapter = null) -> void:
	workstations = station_service
	core_defense = core_service
	fire = fire_service
	world = world_adapter


func register_visual(instance_id: String, body: CollisionObject3D) -> void:
	visual_bodies[instance_id] = body


func unregister_visual(instance_id: String) -> void:
	visual_bodies.erase(instance_id)
	_blocked_reported.erase(instance_id)
	_rail_riders.erase(instance_id)


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0 or workstations == null or core_defense == null:
		return
	workstations.advance_siege_cooldowns(delta)
	_resolve_due_impacts(delta)
	var any_target := core_defense.living_raider_count() > 0
	for instance_id: String in workstations.stations.keys():
		var status := workstations.siege_status(instance_id)
		if not status.get("ok", false):
			continue
		var details: Dictionary = status.get("details", {})
		_present_loaded_state(instance_id, details)
		var target := _target_for(instance_id, details) if any_target else Vector3.INF
		var has_target := target.is_finite()
		var rides_rails := float(details.get("definition", {}).get("rail_speed", 0.0)) > 0.0
		if int(details.get("ammo", 0)) <= 0:
			_poll_auto_reload(instance_id, delta)
			if rides_rails:
				_ride_rails(instance_id, details, Vector3.INF, delta)
			continue
		if not has_target or str(details.get("stance", "fire_at_will")) == "hold":
			if rides_rails:
				_ride_rails(instance_id, details, Vector3.INF, delta)
			continue
		if rides_rails:
			_ride_rails(instance_id, details, target, delta)
		_turn_toward(instance_id, target, delta)
		if float(details.get("cooldown", 0.0)) > 0.0:
			continue
		_attempt_fire(instance_id, details)


## An empty weapon asks the nearest supplying chest for munitions once per
## RELOAD_POLL_SECONDS (P4a-3 auto-reload).
func _poll_auto_reload(instance_id: String, delta: float) -> void:
	var timer := float(_reload_timers.get(instance_id, 0.0)) - delta
	if timer > 0.0:
		_reload_timers[instance_id] = timer
		return
	_reload_timers[instance_id] = RELOAD_POLL_SECONDS
	var reloaded := workstations.siege_auto_reload(instance_id)
	if reloaded.get("ok", false):
		var details: Dictionary = reloaded.get("details", {})
		feedback.emit("%s reloaded %d %s from a nearby chest." % [_display(instance_id), int(details.get("moved", 0)), str(details.get("item_id", "")).replace("_", " ")])


func _display(instance_id: String) -> String:
	return str(workstations.station(instance_id).get("entity_id", "siege weapon")).replace("_", " ").capitalize()


## Rotates the machine's turntable so its throw direction (local -z) faces the
## target, at TURN_RATE. Occupancy and collision never move.
func _turn_toward(instance_id: String, target: Vector3, delta: float) -> void:
	var turret := _turret(instance_id)
	if turret == null:
		return
	var to_target := target - turret.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	var desired := atan2(-to_target.x, -to_target.z)
	var body: Node3D = turret.get_parent()
	var desired_local := desired - body.global_rotation.y
	turret.rotation.y = rotate_toward(turret.rotation.y, wrapf(desired_local, -PI, PI), TURN_RATE * delta)


## Instantly turns the machine to face `target` (diagnostics and restore).
func face_target_now(instance_id: String, target: Vector3) -> void:
	_turn_toward(instance_id, target, 1000.0)


## True while the machine's throw direction is within `tolerance` of the target.
func facing_target(instance_id: String, target: Vector3, tolerance: float = 0.12) -> bool:
	var turret := _turret(instance_id)
	if turret == null:
		return true
	var forward := -turret.global_transform.basis.z
	var to_target := target - turret.global_position
	forward.y = 0.0
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return true
	return forward.normalized().angle_to(to_target.normalized()) <= tolerance


## Shows the loaded stone only while the catapult holds ammunition and has
## finished winding back; the arm winds back over the reload cooldown.
func _present_loaded_state(instance_id: String, details: Dictionary) -> void:
	var turret := _turret(instance_id)
	if turret == null:
		return
	var stone: Node3D = turret.find_child("CatapultStone", true, false)
	if stone != null:
		stone.visible = int(details.get("ammo", 0)) > 0 and float(details.get("cooldown", 0.0)) <= 0.0
	var cooldown := float(details.get("cooldown", 0.0))
	var total := float(details.get("definition", {}).get("cooldown_seconds", 1.0))
	var wound := 1.0 - clampf(cooldown / maxf(total, 0.05), 0.0, 1.0)
	var loaded := int(details.get("ammo", 0)) > 0 and cooldown <= 0.0
	var arm: Node3D = turret.find_child("CatapultArm", true, false)
	if arm != null and not arm.has_meta("throwing"):
		arm.rotation.x = lerpf(ARM_THROWN, ARM_REST, wound)
	var slider: Node3D = turret.find_child("BallistaSlider", true, false)
	if slider != null:
		if not slider.has_meta("releasing"):
			slider.position.z = lerpf(SLIDER_RELEASED_Z, SLIDER_DRAWN_Z, wound)
		var bolt: Node3D = slider.find_child("BallistaBolt", true, false)
		if bolt != null:
			bolt.visible = loaded
		_lay_ballista_strings(turret, slider)
	var ball: Node3D = turret.find_child("CannonBall", true, false)
	if ball != null:
		ball.visible = loaded
	var oil: Node3D = turret.find_child("KettleOil", true, false)
	if oil != null:
		oil.visible = int(details.get("ammo", 0)) > 0


## Each bow string runs from its arm tip to the slider nock: the pivot at the
## tip looks at the nock and its unit-length box is scaled to the distance.
func _lay_ballista_strings(turret: Node3D, slider: Node3D) -> void:
	var nock := slider.global_position + slider.global_transform.basis.y * 0.08 + slider.global_transform.basis.z * 0.10
	for side in ["L", "R"]:
		var pivot: Node3D = turret.find_child("BallistaString_%s" % side, true, false)
		if pivot == null:
			continue
		var distance := pivot.global_position.distance_to(nock)
		if distance < 0.05:
			continue
		pivot.look_at(nock, Vector3.UP)
		# look_at points the pivot's -z at the nock, so the strand extends along -z.
		var strand: Node3D = pivot.get_child(0) if pivot.get_child_count() > 0 else null
		if strand != null:
			strand.scale = Vector3(1.0, 1.0, distance)
			strand.position = Vector3(0.0, 0.0, -distance * 0.5)


## Plays the machine's firing motion: catapult arm throw, ballista slider
## release, cannon barrel recoil with a muzzle flash, kettle pot tilt.
func _animate_fire(instance_id: String, siege: Dictionary) -> void:
	var turret := _turret(instance_id)
	if turret == null:
		return
	var mode := str(siege.get("fire_mode", ""))
	if mode == "ballistic":
		_animate_throw(instance_id)
		return
	if mode == "dump":
		var pot: Node3D = turret.find_child("KettlePot", true, false)
		if pot != null:
			var tween := create_tween()
			tween.tween_property(pot, "rotation:x", POT_DUMP_TILT, POT_DUMP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_interval(0.6)
			tween.tween_property(pot, "rotation:x", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
		return
	var barrel: Node3D = turret.find_child("CannonBarrel", true, false)
	if barrel != null:
		var rest := barrel.position
		var tween := create_tween()
		tween.tween_property(barrel, "position", rest + Vector3(0.0, 0.0, CANNON_RECOIL), 0.06)
		tween.tween_property(barrel, "position", rest, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var muzzle: Node3D = barrel.find_child("SiegeMuzzle", true, false)
		if muzzle != null:
			_spawn_muzzle_flash(muzzle.global_position, -barrel.global_transform.basis.z)
		return
	var slider: Node3D = turret.find_child("BallistaSlider", true, false)
	if slider != null:
		slider.set_meta("releasing", true)
		var tween := create_tween()
		tween.tween_property(slider, "position:z", SLIDER_RELEASED_Z, 0.05)
		tween.finished.connect(func() -> void:
			if is_instance_valid(slider):
				slider.remove_meta("releasing"))


func _animate_throw(instance_id: String) -> void:
	var turret := _turret(instance_id)
	if turret == null:
		return
	var arm: Node3D = turret.find_child("CatapultArm", true, false)
	if arm == null:
		return
	arm.set_meta("throwing", true)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(arm, "rotation:x", ARM_THROWN, ARM_THROW_SECONDS)
	tween.finished.connect(func() -> void:
		if is_instance_valid(arm):
			arm.remove_meta("throwing"))


func _turret(instance_id: String) -> Node3D:
	var body: Variant = visual_bodies.get(instance_id)
	if body is Node3D and is_instance_valid(body):
		return body.get_node_or_null("SiegeTurret")
	return null


func hud_suffix() -> String:
	if workstations == null:
		return ""
	var counts: Dictionary = {}
	var ammo: Dictionary = {}
	var order: Array[String] = []
	for instance_id: String in workstations.stations:
		var status := workstations.siege_status(instance_id)
		if not status.get("ok", false):
			continue
		var details: Dictionary = status.get("details", {})
		var entity_id := str(details.get("entity_id", ""))
		if not counts.has(entity_id):
			order.append(entity_id)
		counts[entity_id] = int(counts.get(entity_id, 0)) + 1
		ammo[entity_id] = int(ammo.get(entity_id, 0)) + int(details.get("ammo", 0))
	if order.is_empty():
		return ""
	var parts: Array[String] = []
	for entity_id in order:
		parts.append("%s %d/%d" % [entity_id.replace("_", " "), int(counts[entity_id]), int(ammo[entity_id])])
	return " · " + " · ".join(parts)


func trajectory_result(instance_id: String, target: Vector3) -> Dictionary:
	var status := workstations.siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var siege: Dictionary = details.get("definition", {})
	var origin := _muzzle_position(details)
	var distance := origin.distance_to(target)
	if str(siege.get("fire_mode", "")) == "dump":
		distance = Vector2(target.x - origin.x, target.z - origin.z).length()
	var minimum := float(siege.get("minimum_range", 0.0))
	var maximum := float(siege.get("maximum_range", 0.0))
	if distance < minimum:
		return {"ok": false, "reason": "TARGET_TOO_CLOSE", "distance": distance, "origin": origin}
	if distance > maximum:
		return {"ok": false, "reason": "TARGET_TOO_FAR", "distance": distance, "origin": origin}
	var mode := str(siege.get("fire_mode", ""))
	if mode == "direct":
		return _direct_trajectory(instance_id, origin, target)
	if mode == "ballistic":
		return _ballistic_trajectory(instance_id, origin, target, float(siege.get("arc_height", 7.0)))
	if mode == "dump":
		return _dump_trajectory(origin, target, maximum)
	return {"ok": false, "reason": "UNKNOWN_FIRE_MODE"}


## The living raider this weapon should engage: the nearest one passing its
## target filter ("any", "raider", "brute"; "structure" engages nothing yet).
func _target_for(instance_id: String, details: Dictionary) -> Vector3:
	var filter := str(details.get("target_filter", "any"))
	if filter == "structure":
		return Vector3.INF
	var from := _muzzle_position(details)
	if from == Vector3.ZERO:
		var turret := _turret(instance_id)
		if turret != null:
			from = turret.global_position
	return core_defense.nearest_raider_position(from, filter)


func _attempt_fire(instance_id: String, details: Dictionary, resolve_immediately: bool = false) -> Dictionary:
	var target := _target_for(instance_id, details)
	if not target.is_finite():
		return {"ok": false, "reason": "NO_RAIDER"}
	if str(details.get("stance", "fire_at_will")) == "hold":
		return {"ok": false, "reason": "STANCE_HOLD"}
	if not facing_target(instance_id, target):
		return {"ok": false, "reason": "TURNING"}
	var trajectory := trajectory_result(instance_id, target)
	if not trajectory.get("ok", false):
		var reason := str(trajectory.get("reason", "BLOCKED"))
		if reason in ["LINE_OF_SIGHT_BLOCKED", "ARC_BLOCKED"] and not _blocked_reported.has(instance_id):
			_blocked_reported[instance_id] = true
			feedback.emit("%s is holding fire: its %s is blocked." % [str(details.get("entity_id", "siege weapon")).replace("_", " ").capitalize(), "line of sight" if reason == "LINE_OF_SIGHT_BLOCKED" else "ballistic arc"])
		return trajectory
	_blocked_reported.erase(instance_id)
	var committed := workstations.commit_siege_shot(instance_id)
	if not committed.get("ok", false):
		return committed
	var siege: Dictionary = details.get("definition", {})
	var munition: Dictionary = details.get("munition", {})
	if munition.is_empty():
		munition = {"damage": int(siege.get("damage", 0)), "splash_radius": 0.0, "effect": "impact"}
	var points: Array = trajectory.get("points", [])
	var flight_seconds := 0.0
	var mode := str(siege.get("fire_mode", ""))
	_animate_fire(instance_id, siege)
	if mode == "ballistic":
		flight_seconds = _spawn_catapult_shot(points, munition)
	elif mode == "dump":
		flight_seconds = _spawn_oil_dump(points)
	elif str(details.get("ammo_item", "")) == "cannonball":
		flight_seconds = _spawn_cannonball(trajectory.get("origin", Vector3.ZERO), target)
	else:
		flight_seconds = _spawn_ballista_bolt(trajectory.get("origin", Vector3.ZERO), target)
	var impact_point: Vector3 = points[points.size() - 1] if points.size() > 0 else target
	var impact := {"at": flight_seconds, "instance_id": instance_id, "munition": munition, "point": impact_point, "target": target, "source": str(details.get("entity_id", "siege_weapon"))}
	var damage_result: Dictionary
	if resolve_immediately:
		damage_result = _resolve_impact(impact)
	else:
		_pending_impacts.append(impact)
		damage_result = {"ok": true, "reason": "SHOT_IN_FLIGHT", "seconds": flight_seconds}
	state_changed.emit("")
	return {"ok": damage_result.get("ok", false), "reason": damage_result.get("reason", "SHOT_FAILED"), "committed": committed, "damage": damage_result, "trajectory": trajectory, "impact": impact_point}


## Munitions resolve where they land (P4a-4): impact damage to every raider
## within the splash radius (the target cell itself always counts), and flame
## munitions light the ground there.
func _resolve_impact(impact: Dictionary) -> Dictionary:
	var munition: Dictionary = impact.munition
	var point: Vector3 = impact.point
	var radius := float(munition.get("splash_radius", 0.0))
	var damage := int(munition.get("damage", 0))
	var result := {"ok": false, "reason": "NO_RAIDER"}
	var hits := core_defense.damage_raiders_within(point, maxf(radius, 0.9), damage, str(impact.source), str(impact.get("instance_id", "")))
	if hits > 0:
		result = {"ok": true, "reason": "RAIDER_DAMAGED", "hits": hits}
	if str(munition.get("effect", "impact")) == "fire" and fire != null:
		var lit := fire.ignite(Vector3i(floori(point.x), floori(point.y), floori(point.z)), munition, radius)
		if lit > 0:
			feedback.emit("Flame shot burst: %d cells ablaze." % lit)
	elif radius > 0.0:
		_scorch_ground(point)
	return result


## World effect of a heavy impact: the grass under the landing point is torn
## to dirt (the first solid cell at or below the impact).
func _scorch_ground(point: Vector3) -> void:
	if world == null:
		return
	var probe := Vector3i(floori(point.x), floori(point.y), floori(point.z))
	for _step in range(4):
		var query := world.query_cell(probe)
		if query.get("state") == "LOADED" and int(query.get("voxel_id", 0)) != 0:
			if int(query.get("voxel_id", 0)) == WorldAdapter.BLOCK_NAMES.find("grass"):
				world.set_cell(probe, WorldAdapter.BLOCK_NAMES.find("dirt"))
			return
		probe += Vector3i(0, -1, 0)


func _resolve_due_impacts(delta: float) -> void:
	if _pending_impacts.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for impact in _pending_impacts:
		impact.at = float(impact.at) - delta
		if float(impact.at) <= 0.0:
			_resolve_impact(impact)
		else:
			remaining.append(impact)
	_pending_impacts = remaining


func pending_impacts() -> int:
	return _pending_impacts.size()


func _direct_trajectory(instance_id: String, origin: Vector3, target: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1)
	query.exclude = _excluded_rids(instance_id)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or core_defense.is_raider_node(hit.get("collider")):
		return {"ok": true, "reason": "CLEAR", "origin": origin, "target": target, "points": [origin, target]}
	return {"ok": false, "reason": "LINE_OF_SIGHT_BLOCKED", "origin": origin, "target": target, "collider": str(hit.get("collider"))}


func _ballistic_trajectory(instance_id: String, origin: Vector3, target: Vector3, height: float) -> Dictionary:
	var points: Array[Vector3] = []
	for index in range(ARC_SEGMENTS + 1):
		var t := float(index) / float(ARC_SEGMENTS)
		points.append(origin.lerp(target, t) + Vector3.UP * (4.0 * height * t * (1.0 - t)))
	var excluded := _excluded_rids(instance_id)
	for index in range(points.size() - 1):
		var query := PhysicsRayQueryParameters3D.create(points[index], points[index + 1], 1)
		query.exclude = excluded
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and not core_defense.is_raider_node(hit.get("collider")):
			return {"ok": false, "reason": "ARC_BLOCKED", "origin": origin, "target": target, "blocked_segment": index, "points": points}
	return {"ok": true, "reason": "CLEAR", "origin": origin, "target": target, "points": points}


## Hot oil pours straight down from the lip onto the ground beside the wall:
## the target must be below the spout and within reach horizontally.
func _dump_trajectory(origin: Vector3, target: Vector3, reach: float) -> Dictionary:
	if target.y > origin.y - 0.5:
		return {"ok": false, "reason": "TARGET_TOO_HIGH", "origin": origin, "target": target}
	var landing := Vector3(target.x, target.y - 0.9, target.z)
	var points: Array[Vector3] = []
	var steps := maxi(4, int(ceil((origin.y - landing.y) * 2.0)))
	for index in range(steps + 1):
		var t := float(index) / float(steps)
		var drop := origin.lerp(landing, t)
		drop.x = lerpf(origin.x, landing.x, minf(1.0, t * 1.6))
		drop.z = lerpf(origin.z, landing.z, minf(1.0, t * 1.6))
		points.append(drop)
	return {"ok": true, "reason": "CLEAR", "origin": origin, "target": target, "points": points, "reach": reach}


## Kettles ride their rail chain: the connected rail cells under and beside
## the kettle's own rail. With a target, the kettle moves to the chain cell
## nearest the target; without one it returns to its home rail.
func _ride_rails(instance_id: String, details: Dictionary, target: Vector3, delta: float) -> void:
	var turret := _turret(instance_id)
	if turret == null:
		return
	var anchor: Vector3i = details.get("anchor", Vector3i.ZERO)
	var home := anchor + Vector3i(0, -1, 0)
	var chain := _rail_chain(home)
	var rider: Dictionary = _rail_riders.get(instance_id, {"cell": home})
	var current: Vector3i = rider.cell
	if not chain.has(current):
		current = home
	var goal := home
	if target.is_finite():
		var best := INF
		for cell: Vector3i in chain.keys():
			var d := Vector2(target.x - (cell.x + 0.5), target.z - (cell.z + 0.5)).length()
			if d < best:
				best = d
				goal = cell
	elif str(details.get("stance", "fire_at_will")) == "patrol" and chain.size() > 1:
		# Patrol: ride to the far end of the chain, then back to the other end.
		var patrol_goal: Vector3i = rider.get("patrol_goal", Vector3i.MAX)
		if patrol_goal == Vector3i.MAX or not chain.has(patrol_goal) or patrol_goal == current:
			patrol_goal = _chain_end_farthest(chain, current)
			rider.patrol_goal = patrol_goal
		goal = patrol_goal
	var speed := float(details.get("definition", {}).get("rail_speed", 2.0))
	var body: Node3D = turret.get_parent()
	var desired_global := Vector3(current) + Vector3(0.5, 1.5, 0.5)
	if goal != current:
		var next := _rail_step(chain, current, goal)
		desired_global = Vector3(next) + Vector3(0.5, 1.5, 0.5)
		var position := turret.global_position
		var moved := position.move_toward(desired_global, speed * delta)
		turret.global_position = moved
		if moved.distance_to(desired_global) < 0.02:
			current = next
	else:
		turret.global_position = turret.global_position.move_toward(desired_global, speed * delta)
	rider.cell = current
	_rail_riders[instance_id] = rider
	if body != null:
		body.set_meta("rail_cell", current)
		# The clickable/blocking shapes ride along so the panel opens where
		# the kettle actually is.
		for child in body.get_children():
			if child is CollisionShape3D:
				if not child.has_meta("rest_position"):
					child.set_meta("rest_position", child.position)
				child.position = child.get_meta("rest_position") + turret.position
	# Idle kettles face across the rail (perpendicular to the chain), not along it.
	if not target.is_finite():
		var along := _chain_direction(chain, current)
		if along != Vector3i.ZERO:
			var across := Vector3(float(-along.z), 0.0, float(along.x))
			var desired := atan2(-across.x, -across.z)
			var body_yaw := body.global_rotation.y if body != null else 0.0
			turret.rotation.y = rotate_toward(turret.rotation.y, wrapf(desired - body_yaw, -PI, PI), TURN_RATE * delta)


## The rail direction at `cell`: the axis along which it has chain neighbours.
func _chain_direction(chain: Dictionary, cell: Vector3i) -> Vector3i:
	if chain.has(cell + Vector3i(1, 0, 0)) or chain.has(cell - Vector3i(1, 0, 0)):
		return Vector3i(1, 0, 0)
	if chain.has(cell + Vector3i(0, 0, 1)) or chain.has(cell - Vector3i(0, 0, 1)):
		return Vector3i(0, 0, 1)
	return Vector3i.ZERO


## The chain cell farthest (by chain distance) from `from`: the patrol turn point.
func _chain_end_farthest(chain: Dictionary, from: Vector3i) -> Vector3i:
	var distance: Dictionary = {from: 0}
	var queue: Array[Vector3i] = [from]
	var index := 0
	var farthest := from
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if int(distance[cell]) > int(distance[farthest]):
			farthest = cell
		for offset: Vector3i in RAIL_STEPS:
			var next: Vector3i = cell + offset
			if chain.has(next) and not distance.has(next):
				distance[next] = int(distance[cell]) + 1
				queue.append(next)
	return farthest


## Where a rider currently sits on its chain (diagnostics).
func rail_rider_cell(instance_id: String) -> Vector3i:
	var rider: Dictionary = _rail_riders.get(instance_id, {})
	return rider.get("cell", Vector3i(0, -9999, 0))


## Connected rail cells reachable from `start` through 4-neighbours on the
## same level: {cell: true}.
func _rail_chain(start: Vector3i) -> Dictionary:
	var rails: Dictionary = {}
	for record_id: String in workstations.stations.keys():
		var record: Dictionary = workstations.stations[record_id]
		if str(record.get("entity_id", "")) == "rail":
			rails[record.get("anchor", Vector3i.ZERO)] = true
	var chain: Dictionary = {}
	if not rails.has(start):
		chain[start] = true
		return chain
	var frontier: Array[Vector3i] = [start]
	chain[start] = true
	while not frontier.is_empty():
		var cell: Vector3i = frontier.pop_back()
		for offset: Vector3i in RAIL_STEPS:
			var next: Vector3i = cell + offset
			if rails.has(next) and not chain.has(next):
				chain[next] = true
				frontier.append(next)
	return chain


## Next chain cell on the shortest path from `from` to `goal` (BFS).
func _rail_step(chain: Dictionary, from: Vector3i, goal: Vector3i) -> Vector3i:
	var parents: Dictionary = {from: from}
	var queue: Array[Vector3i] = [from]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if cell == goal:
			break
		for offset: Vector3i in RAIL_STEPS:
			var next: Vector3i = cell + offset
			if chain.has(next) and not parents.has(next):
				parents[next] = cell
				queue.append(next)
	if not parents.has(goal):
		return from
	var step := goal
	while parents[step] != from:
		step = parents[step]
	return step


func _excluded_rids(instance_id: String) -> Array[RID]:
	var excluded: Array[RID] = []
	var body: Variant = visual_bodies.get(instance_id)
	if body is CollisionObject3D and is_instance_valid(body):
		excluded.append(body.get_rid())
	return excluded


func _muzzle_position(details: Dictionary) -> Vector3:
	# A turned machine launches from where its bucket actually is.
	var turret := _turret(str(details.get("instance_id", "")))
	if turret != null:
		var muzzle: Node3D = turret.find_child("SiegeMuzzle", true, false)
		if muzzle != null:
			return muzzle.global_position
		var bucket: Node3D = turret.find_child("CatapultBucket", true, false)
		if bucket != null:
			return bucket.global_position
	var anchor: Vector3i = details.get("anchor", Vector3i.ZERO)
	var siege: Dictionary = details.get("definition", {})
	var raw: Array = siege.get("muzzle_offset", [0.5, 0.8, 0.5])
	var local := Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw.size() == 3 else Vector3(0.5, 0.8, 0.5)
	var centered := local - Vector3(0.5, 0.0, 0.5)
	centered = centered.rotated(Vector3.UP, -float(int(details.get("rotation_quarters", 0))) * PI / 2.0)
	return Vector3(anchor) + Vector3(0.5, 0.0, 0.5) + centered


func _spawn_ballista_bolt(origin: Vector3, target: Vector3) -> float:
	var bolt := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = 0.75
	bolt.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f2d18b")
	material.emission_enabled = true
	material.emission = Color("eaa850")
	bolt.material_override = material
	add_child(bolt)
	bolt.global_position = origin
	bolt.look_at(target, Vector3.UP)
	bolt.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tween := create_tween()
	var seconds := clampf(origin.distance_to(target) / 34.0, 0.15, 0.65)
	tween.tween_property(bolt, "global_position", target, seconds)
	tween.finished.connect(bolt.queue_free)
	return seconds


## Cannonball: a fast dark sphere with a short smoke trail.
func _spawn_cannonball(origin: Vector3, target: Vector3) -> float:
	var shot := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.30
	shot.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("2f353b")
	shot.material_override = material
	add_child(shot)
	shot.global_position = origin
	var seconds := clampf(origin.distance_to(target) / 55.0, 0.10, 0.60)
	var tween := create_tween()
	tween.tween_property(shot, "global_position", target, seconds)
	tween.finished.connect(shot.queue_free)
	return seconds


func _spawn_muzzle_flash(origin: Vector3, direction: Vector3) -> void:
	var flash := Node3D.new()
	add_child(flash)
	flash.global_position = origin
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.35)
	light.light_energy = 4.0
	light.omni_range = 7.0
	flash.add_child(light)
	var smoke_material := StandardMaterial3D.new()
	smoke_material.albedo_color = Color(0.85, 0.85, 0.8, 0.6)
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for index in range(4):
		var puff := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.18 + index * 0.06
		mesh.height = mesh.radius * 2.0
		puff.mesh = mesh
		puff.material_override = smoke_material
		puff.position = direction.normalized() * (0.2 + index * 0.35)
		flash.add_child(puff)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.25)
	tween.parallel().tween_property(flash, "scale", Vector3(1.8, 1.8, 1.8), 0.9)
	tween.finished.connect(flash.queue_free)


## Hot oil: a string of amber blobs pouring from the lip to the ground.
func _spawn_oil_dump(points: Array) -> float:
	if points.size() < 2:
		return 0.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d98a1e")
	material.emission_enabled = true
	material.emission = Color("ff9a1e")
	material.emission_energy_multiplier = 1.5
	var per_step := 0.05
	var seconds := per_step * (points.size() - 1)
	for blob_index in range(4):
		var blob := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.24
		blob.mesh = mesh
		blob.material_override = material
		add_child(blob)
		blob.global_position = points[0]
		var tween := create_tween()
		tween.tween_interval(blob_index * 0.06)
		for index in range(1, points.size()):
			tween.tween_property(blob, "global_position", points[index], per_step)
		tween.finished.connect(blob.queue_free)
	return seconds + 0.2


func _spawn_catapult_shot(points: Array, munition: Dictionary = {}) -> float:
	if points.size() < 2:
		return 0.0
	var shot := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	shot.mesh = mesh
	var material := StandardMaterial3D.new()
	var flaming := str(munition.get("effect", "impact")) == "fire"
	material.albedo_color = Color("ff7a22") if flaming else Color("596169")
	if flaming:
		material.emission_enabled = true
		material.emission = Color("ff5a10")
		material.emission_energy_multiplier = 3.0
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.25)
		glow.light_energy = 1.2
		glow.omni_range = 5.0
		shot.add_child(glow)
	shot.material_override = material
	add_child(shot)
	shot.global_position = points[0]
	var tween := create_tween()
	for index in range(1, points.size()):
		tween.tween_property(shot, "global_position", points[index], 0.055)
	tween.finished.connect(shot.queue_free)
	return 0.055 * (points.size() - 1)
