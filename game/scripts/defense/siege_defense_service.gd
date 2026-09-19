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

var workstations: WorkstationService
var core_defense: CoreDefenseService
var visual_bodies: Dictionary = {}
var _blocked_reported: Dictionary = {}


func initialize(station_service: WorkstationService, core_service: CoreDefenseService) -> void:
	workstations = station_service
	core_defense = core_service


func register_visual(instance_id: String, body: CollisionObject3D) -> void:
	visual_bodies[instance_id] = body


func unregister_visual(instance_id: String) -> void:
	visual_bodies.erase(instance_id)
	_blocked_reported.erase(instance_id)


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0 or workstations == null or core_defense == null:
		return
	workstations.advance_siege_cooldowns(delta)
	var has_target := core_defense.is_active() and is_instance_valid(core_defense.raider)
	var target := core_defense.raider_target_position() if has_target else Vector3.INF
	for instance_id: String in workstations.stations.keys():
		var status := workstations.siege_status(instance_id)
		if not status.get("ok", false):
			continue
		var details: Dictionary = status.get("details", {})
		_present_loaded_state(instance_id, details)
		if not has_target:
			continue
		_turn_toward(instance_id, target, delta)
		if int(details.get("ammo", 0)) <= 0 or float(details.get("cooldown", 0.0)) > 0.0:
			continue
		_attempt_fire(instance_id, details)


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
	var arm: Node3D = turret.find_child("CatapultArm", true, false)
	if arm != null and not arm.has_meta("throwing"):
		var cooldown := float(details.get("cooldown", 0.0))
		var total := float(details.get("definition", {}).get("cooldown_seconds", 1.0))
		var wound := 1.0 - clampf(cooldown / maxf(total, 0.05), 0.0, 1.0)
		arm.rotation.x = lerpf(ARM_THROWN, ARM_REST, wound)


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
	tween.finished.connect(func() -> void: arm.remove_meta("throwing"))


func _turret(instance_id: String) -> Node3D:
	var body: Variant = visual_bodies.get(instance_id)
	if body is Node3D and is_instance_valid(body):
		return body.get_node_or_null("SiegeTurret")
	return null


func hud_suffix() -> String:
	if workstations == null:
		return ""
	var ballista_count := 0
	var ballista_ammo := 0
	var catapult_count := 0
	var catapult_ammo := 0
	for instance_id: String in workstations.stations:
		var status := workstations.siege_status(instance_id)
		if not status.get("ok", false):
			continue
		var details: Dictionary = status.get("details", {})
		if str(details.get("entity_id", "")) == "ballista":
			ballista_count += 1
			ballista_ammo += int(details.get("ammo", 0))
		elif str(details.get("entity_id", "")) == "catapult":
			catapult_count += 1
			catapult_ammo += int(details.get("ammo", 0))
	if ballista_count + catapult_count == 0:
		return ""
	return " · ballista %d/%d bolts · catapult %d/%d shot" % [ballista_count, ballista_ammo, catapult_count, catapult_ammo]


func trajectory_result(instance_id: String, target: Vector3) -> Dictionary:
	var status := workstations.siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var siege: Dictionary = details.get("definition", {})
	var origin := _muzzle_position(details)
	var distance := origin.distance_to(target)
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
	return {"ok": false, "reason": "UNKNOWN_FIRE_MODE"}


func _attempt_fire(instance_id: String, details: Dictionary) -> Dictionary:
	var target := core_defense.raider_target_position()
	if not target.is_finite():
		return {"ok": false, "reason": "NO_RAIDER"}
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
	var damage := int(siege.get("damage", 0))
	var damage_result := core_defense.try_damage_raider(damage, str(details.get("entity_id", "siege_weapon")))
	var points: Array = trajectory.get("points", [])
	if str(siege.get("fire_mode", "")) == "ballistic":
		_animate_throw(instance_id)
		_spawn_catapult_shot(points)
	else:
		_spawn_ballista_bolt(trajectory.get("origin", Vector3.ZERO), target)
	state_changed.emit("")
	return {"ok": damage_result.get("ok", false), "reason": damage_result.get("reason", "SHOT_FAILED"), "committed": committed, "damage": damage_result, "trajectory": trajectory}


func _direct_trajectory(instance_id: String, origin: Vector3, target: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1)
	query.exclude = _excluded_rids(instance_id)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") == core_defense.raider:
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
		if not hit.is_empty() and hit.get("collider") != core_defense.raider:
			return {"ok": false, "reason": "ARC_BLOCKED", "origin": origin, "target": target, "blocked_segment": index, "points": points}
	return {"ok": true, "reason": "CLEAR", "origin": origin, "target": target, "points": points}


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


func _spawn_ballista_bolt(origin: Vector3, target: Vector3) -> void:
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
	tween.tween_property(bolt, "global_position", target, clampf(origin.distance_to(target) / 34.0, 0.15, 0.65))
	tween.finished.connect(bolt.queue_free)


func _spawn_catapult_shot(points: Array) -> void:
	if points.size() < 2:
		return
	var shot := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	shot.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("596169")
	shot.material_override = material
	add_child(shot)
	shot.global_position = points[0]
	var tween := create_tween()
	for index in range(1, points.size()):
		tween.tween_property(shot, "global_position", points[index], 0.055)
	tween.finished.connect(shot.queue_free)
