class_name DefenseService
extends Node3D

signal state_changed(text: String)
signal feedback(message: String)

const IDLE := "idle"
const WARNING := "warning"
const ROUTING := "routing"
const ATTACKING := "attacking"
const COMPLETE := "complete"
const FAILED := "failed"
const WALL_MAX_INTEGRITY := 24
const REPAIR_AMOUNT := 6
const WARNING_SECONDS := 5.0
const RAIDER_MAX_HEALTH := 20
const BALLISTA_DAMAGE := 5
const BALLISTA_STARTING_BOLTS := 4
const BALLISTA_INTERVAL := 1.0
const RAIDER_DAMAGE := 6
const RAIDER_ATTACK_INTERVAL := 1.4
const PLANK_VOXEL_ID := 5
const ARENA_CANDIDATES: Array[Vector3i] = [
	Vector3i(6, 0, 38),
	Vector3i(-6, 0, 38),
	Vector3i(0, 0, 38),
	Vector3i(10, 0, 40),
	Vector3i(-10, 0, 40),
	Vector3i(0, 0, 50),
]

var world: WorldAdapter
var inventory: F0Inventory
var registry: ContentRegistry
var workstations: WorkstationService
var state := IDLE
var arena_center := Vector3i.ZERO
var warning_remaining := 0.0
var wall_integrity := WALL_MAX_INTEGRITY
var ballista_bolts := 0
var raider_health := 0
var attack_timer := 0.0
var ballista_timer := 0.0
var ballista_armed := false
var wall_cells: Array[Vector3i] = []
var navigation_snapshot: NavigationSnapshot
var navigation_revision := 0
var exact_invalidations := 0
var last_route_reason := ""
var raider: BasicRaider
var _wall_root: Node3D
var _ballista_root: Node3D
var _wall_material: StandardMaterial3D
var _pending_restore: Dictionary = {}


func initialize(world_adapter: WorldAdapter, player_inventory: F0Inventory, content_registry: ContentRegistry, station_service: WorkstationService, saved: Dictionary = {}) -> void:
	world = world_adapter
	inventory = player_inventory
	registry = content_registry
	workstations = station_service
	_pending_restore = saved.duplicate(true)
	world.cell_changed.connect(_on_world_cell_changed)
	set_process(false)


func restore_after_world_ready() -> Dictionary:
	if _pending_restore.is_empty():
		_emit_state()
		return {"ok": true, "reason": "OK"}
	var saved := _pending_restore
	_pending_restore = {}
	var restored_state := str(saved.get("state", IDLE))
	if restored_state not in [IDLE, WARNING, ROUTING, ATTACKING, COMPLETE, FAILED]:
		return {"ok": false, "reason": "INVALID_DEFENSE_SNAPSHOT"}
	state = restored_state
	if state == IDLE:
		_emit_state()
		return {"ok": true, "reason": "OK"}
	var center_value: Variant = saved.get("arena_center", [])
	if not center_value is Array or center_value.size() != 3:
		return {"ok": false, "reason": "INVALID_DEFENSE_SNAPSHOT"}
	arena_center = Vector3i(int(center_value[0]), int(center_value[1]), int(center_value[2]))
	if not _arena_is_available(arena_center):
		return {"ok": false, "reason": "DEFENSE_ARENA_BLOCKED"}
	warning_remaining = maxf(0.0, float(saved.get("warning_remaining", 0.0)))
	wall_integrity = clampi(int(saved.get("wall_integrity", WALL_MAX_INTEGRITY)), 0, WALL_MAX_INTEGRITY)
	ballista_bolts = clampi(int(saved.get("ballista_bolts", 0)), 0, BALLISTA_STARTING_BOLTS)
	raider_health = clampi(int(saved.get("raider_health", 0)), 0, RAIDER_MAX_HEALTH)
	ballista_armed = bool(saved.get("ballista_armed", false))
	navigation_revision = maxi(0, int(saved.get("navigation_revision", 0)))
	_build_fixture()
	if state in [ROUTING, ATTACKING] and raider_health > 0:
		var saved_position := _vector3_from_array(saved.get("raider_position", []), _start_position())
		_spawn_raider(saved_position)
		_plan_from_raider()
	_emit_state()
	return {"ok": true, "reason": "OK"}


func start_drill() -> Dictionary:
	if state in [WARNING, ROUTING, ATTACKING]:
		return {"ok": false, "reason": "DEFENSE_ALREADY_ACTIVE"}
	var found := _find_available_arena()
	if not found.get("ok", false):
		return found
	_clear_fixture()
	arena_center = found.center
	state = WARNING
	warning_remaining = WARNING_SECONDS
	wall_integrity = WALL_MAX_INTEGRITY
	ballista_bolts = BALLISTA_STARTING_BOLTS
	raider_health = RAIDER_MAX_HEALTH
	attack_timer = RAIDER_ATTACK_INTERVAL
	ballista_timer = BALLISTA_INTERVAL
	ballista_armed = false
	exact_invalidations = 0
	last_route_reason = ""
	_build_fixture()
	feedback.emit("Defense drill armed: one raider in 5 seconds. Shift-use the damaged wall with Planks to repair it.")
	_emit_state()
	return {"ok": true, "reason": "OK", "center": arena_center}


func try_repair(structure_id: String) -> Dictionary:
	if structure_id != "training_wall" or wall_integrity <= 0:
		return {"handled": false}
	if wall_integrity >= WALL_MAX_INTEGRITY:
		return {"handled": true, "ok": false, "reason": "NO_REPAIR_NEEDED"}
	if inventory.count("planks") < 1:
		return {"handled": true, "ok": false, "reason": "MISSING_REPAIR_MATERIAL"}
	var committed := inventory.try_transaction({"planks": 1}, {})
	if not committed.get("ok", false):
		return {"handled": true, "ok": false, "reason": str(committed.get("reason", "REPAIR_FAILED"))}
	var before := wall_integrity
	wall_integrity = mini(WALL_MAX_INTEGRITY, wall_integrity + REPAIR_AMOUNT)
	_update_wall_presentation()
	_emit_state()
	return {"handled": true, "ok": true, "reason": "REPAIRED", "changes": {"structure_id": structure_id, "before": before, "after": wall_integrity, "consumed": {"planks": 1}}}


func notify_placed_entity_cells(changed_cells: Array) -> void:
	_refresh_navigation(changed_cells)


func snapshot() -> Dictionary:
	return {
		"state": state,
		"arena_center": [arena_center.x, arena_center.y, arena_center.z],
		"warning_remaining": warning_remaining,
		"wall_integrity": wall_integrity,
		"ballista_bolts": ballista_bolts,
		"raider_health": raider_health,
		"ballista_armed": ballista_armed,
		"raider_position": _vector3_to_array(raider.global_position) if is_instance_valid(raider) else [],
		"navigation_revision": navigation_revision,
	}


func hud_text() -> String:
	match state:
		IDLE:
			return "DEFENSE DRILL · Pause and choose Start Defense Drill"
		WARNING:
			return "⚠ RAID WARNING · one raider in %d · wall %d/%d · ballista %d bolts" % [ceili(warning_remaining), wall_integrity, WALL_MAX_INTEGRITY, ballista_bolts]
		ROUTING:
			return "RAIDER APPROACHING · HP %d/%d · wall %d/%d · ballista %d bolts" % [raider_health, RAIDER_MAX_HEALTH, wall_integrity, WALL_MAX_INTEGRITY, ballista_bolts]
		ATTACKING:
			return "WALL UNDER ATTACK · HP %d/%d · wall %d/%d · ballista %d bolts · Shift-use wall with Planks" % [raider_health, RAIDER_MAX_HEALTH, wall_integrity, WALL_MAX_INTEGRITY, ballista_bolts]
		COMPLETE:
			return "DEFENSE WON · wall %d/%d · Shift-use damaged wall with Planks to repair" % [wall_integrity, WALL_MAX_INTEGRITY]
		FAILED:
			return "DEFENSE FAILED · barricade breached · restart the drill from Pause"
	return "DEFENSE DRILL"


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0:
		return
	if state == WARNING:
		warning_remaining = maxf(0.0, warning_remaining - delta)
		_emit_state()
		if warning_remaining <= 0.0:
			_begin_wave()
	elif state == ATTACKING:
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_timer += RAIDER_ATTACK_INTERVAL
			_raider_attack()
		if ballista_armed and ballista_bolts > 0 and raider_health > 0:
			ballista_timer -= delta
			if ballista_timer <= 0.0:
				ballista_timer += BALLISTA_INTERVAL
				_ballista_fire()


func _begin_wave() -> void:
	state = ROUTING
	_spawn_raider(_start_position())
	_plan_from_raider()
	feedback.emit("Raider sighted. The practice ballista will engage after the first wall strike.")
	_emit_state()


func _plan_from_raider() -> void:
	_capture_navigation()
	if navigation_snapshot == null or not is_instance_valid(raider):
		_fail("NAVIGATION_CAPTURE_FAILED")
		return
	var start := raider.feet_cell()
	var goal := _goal_cell()
	var capability := {"max_step_up": 1, "max_drop_down": 1, "damage_per_hit": {"earth": 6, "wood": 6}}
	var planner := LocalGridPathfinder.new()
	var plan := planner.plan_next(navigation_snapshot, start, goal, capability)
	last_route_reason = str(plan.get("reason", "NO_ROUTE"))
	if plan.get("reason") == "OK":
		state = ROUTING
		raider.set_route(plan.get("path", []))
		return
	if plan.get("reason") == "ATTACK_OBSTRUCTION":
		var action: Dictionary = plan.get("action", {})
		var route := planner.find_route(navigation_snapshot, start, action.get("from", start), capability)
		if not route.get("ok", false):
			_fail("NO_APPROACH_ROUTE")
			return
		state = ROUTING
		raider.set_route(route.get("path", []))
		return
	_fail(last_route_reason)


func _on_raider_route_finished() -> void:
	if not is_instance_valid(raider):
		return
	if wall_integrity <= 0:
		state = FAILED
		feedback.emit("Defense failed: the raider crossed the breached barricade.")
	else:
		state = ATTACKING
		attack_timer = 0.25
		ballista_timer = 0.65
		feedback.emit("Wall under attack. Shift-use the wall while holding Planks to repair it.")
	_emit_state()


func _raider_attack() -> void:
	if wall_integrity <= 0:
		return
	wall_integrity = maxi(0, wall_integrity - RAIDER_DAMAGE)
	ballista_armed = true
	_update_wall_presentation()
	feedback.emit("Raider hit the barricade for %d. Wall integrity: %d/%d." % [RAIDER_DAMAGE, wall_integrity, WALL_MAX_INTEGRITY])
	_emit_state()
	if wall_integrity <= 0:
		_break_wall()


func _ballista_fire() -> void:
	ballista_bolts -= 1
	raider_health = maxi(0, raider_health - BALLISTA_DAMAGE)
	feedback.emit("Ballista fired: raider HP %d/%d; %d bolts remain." % [raider_health, RAIDER_MAX_HEALTH, ballista_bolts])
	_emit_state()
	if raider_health <= 0:
		state = COMPLETE
		if is_instance_valid(raider):
			raider.queue_free()
		raider = null
		feedback.emit("Defense won. Repair any remaining wall damage with Shift + Planks.")
		_emit_state()


func _break_wall() -> void:
	var changed: Array[Vector3i] = wall_cells.duplicate()
	if is_instance_valid(_wall_root):
		_wall_root.queue_free()
	_wall_root = null
	_refresh_navigation(changed)
	state = ROUTING
	_plan_from_raider()


func _capture_navigation() -> void:
	navigation_snapshot = NavigationSnapshot.new()
	var region := AABB(Vector3(arena_center + Vector3i(-2, -2, -4)), Vector3(5, 5, 10))
	var result := navigation_snapshot.capture(region, _query_navigation_cell, world.revision + navigation_revision)
	if not result.get("ok", false):
		navigation_snapshot = null


func _query_navigation_cell(cell: Vector3i) -> Dictionary:
	if wall_integrity > 0 and wall_cells.has(cell):
		return {"state": "LOADED", "solid": true, "voxel_id": -1, "material_id": "planks", "source": "defense_structure", "source_id": "training_wall", "tags": ["wood"], "integrity": wall_integrity, "protected": false}
	var station_id := workstations.station_at_cell(cell)
	if not station_id.is_empty():
		return {"state": "LOADED", "solid": true, "voxel_id": -1, "material_id": "castle_stone", "source": "entity", "source_id": station_id, "tags": ["stone", "fortification"], "integrity": 90, "protected": false}
	var query := world.query_cell(cell)
	if str(query.get("state", "UNLOADED")) != "LOADED":
		return {"state": str(query.get("state", "UNLOADED")), "solid": true}
	var voxel_id := int(query.get("voxel_id", 0))
	if voxel_id == 0:
		return {"state": "LOADED", "solid": false, "voxel_id": 0, "material_id": "air", "source": "voxel", "tags": [], "integrity": 0, "protected": false}
	var block := registry.block_for_voxel(voxel_id)
	var material_id := str(block.get("id", "unknown"))
	var tags: Array = []
	var integrity := 1
	match material_id:
		"grass", "dirt":
			tags = ["earth"]
			integrity = 18
		"log", "planks":
			tags = ["wood"]
			integrity = 24
		"castle_stone":
			tags = ["stone", "fortification"]
			integrity = 90
		_:
			tags = ["stone"]
			integrity = 60
	return {"state": "LOADED", "solid": bool(block.get("solid", true)), "voxel_id": voxel_id, "material_id": material_id, "source": "voxel", "source_id": material_id, "tags": tags, "integrity": integrity, "protected": bool(block.get("protected", false))}


func _refresh_navigation(changed_cells: Array) -> void:
	if navigation_snapshot == null:
		return
	var relevant: Array[Vector3i] = []
	for value in changed_cells:
		if value is Vector3i and navigation_snapshot.contains(value):
			relevant.append(value)
	if relevant.is_empty():
		return
	navigation_revision += 1
	exact_invalidations += relevant.size()
	navigation_snapshot.refresh_cells(relevant, _query_navigation_cell, world.revision + navigation_revision)


func _on_world_cell_changed(cell: Vector3i, _previous: int, _next: int, _revision: int) -> void:
	_refresh_navigation([cell])


func _find_available_arena() -> Dictionary:
	for candidate: Vector3i in ARENA_CANDIDATES:
		if _arena_is_available(candidate):
			return {"ok": true, "reason": "OK", "center": candidate}
	return {"ok": false, "reason": "DEFENSE_ARENA_BLOCKED"}


func _arena_is_available(center: Vector3i) -> bool:
	for x in range(center.x - 2, center.x + 3):
		for z in range(center.z - 4, center.z + 6):
			var floor_query := world.query_cell(Vector3i(x, center.y - 1, z))
			if str(floor_query.get("state", "UNLOADED")) != "LOADED" or int(floor_query.get("voxel_id", 0)) == 0:
				return false
			for y in [center.y, center.y + 1]:
				var cell := Vector3i(x, y, z)
				var query := world.query_cell(cell)
				if str(query.get("state", "UNLOADED")) != "LOADED" or int(query.get("voxel_id", 0)) != 0 or not workstations.station_at_cell(cell).is_empty():
					return false
	return true


func _build_fixture() -> void:
	wall_cells.clear()
	for x in range(arena_center.x - 2, arena_center.x + 3):
		for y in [arena_center.y, arena_center.y + 1]:
			wall_cells.append(Vector3i(x, y, arena_center.z))
	if wall_integrity > 0:
		_build_wall_visual()
	_build_ballista_visual()
	_update_wall_presentation()


func _build_wall_visual() -> void:
	_wall_root = Node3D.new()
	_wall_root.name = "DefenseTrainingWall"
	_wall_material = StandardMaterial3D.new()
	_wall_material.roughness = 0.9
	for cell: Vector3i in wall_cells:
		var body := StaticBody3D.new()
		body.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		body.set_meta("defense_structure_id", "training_wall")
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE
		collision.shape = shape
		body.add_child(collision)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.98
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _wall_material
		body.add_child(mesh_instance)
		_wall_root.add_child(body)
	add_child(_wall_root)


func _build_ballista_visual() -> void:
	_ballista_root = Node3D.new()
	_ballista_root.name = "PracticeBallista"
	_ballista_root.position = Vector3(arena_center) + Vector3(1.35, 0.0, -2.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("80502c")
	wood.roughness = 0.85
	_add_box(_ballista_root, Vector3(0.0, 0.15, 0.0), Vector3(1.3, 0.3, 1.3), Color("747c86"))
	_add_box(_ballista_root, Vector3(0.0, 0.75, 0.0), Vector3(0.22, 0.9, 1.55), wood.albedo_color)
	_add_box(_ballista_root, Vector3(0.0, 0.9, 0.1), Vector3(1.8, 0.16, 0.16), wood.albedo_color)
	_add_box(_ballista_root, Vector3(0.0, 0.9, 0.75), Vector3(0.08, 0.08, 1.45), Color("c9d4dc"))
	add_child(_ballista_root)


func _add_box(parent: Node3D, offset: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	parent.add_child(mesh_instance)


func _update_wall_presentation() -> void:
	if _wall_material == null:
		return
	var ratio := float(wall_integrity) / float(WALL_MAX_INTEGRITY)
	_wall_material.albedo_color = Color("754224").lerp(Color("c64a3c"), 1.0 - ratio)


func _spawn_raider(spawn_position: Vector3) -> void:
	if is_instance_valid(raider):
		raider.queue_free()
	raider = BasicRaider.new()
	add_child(raider)
	raider.global_position = spawn_position
	raider.route_finished.connect(_on_raider_route_finished)


func _clear_fixture() -> void:
	for value in [_wall_root, _ballista_root, raider]:
		if is_instance_valid(value):
			value.queue_free()
	_wall_root = null
	_ballista_root = null
	raider = null
	wall_cells.clear()
	navigation_snapshot = null


func _start_position() -> Vector3:
	return Vector3(_start_cell()) + Vector3(0.5, 0.9, 0.5)


func _start_cell() -> Vector3i:
	return arena_center + Vector3i(0, 0, 5)


func _goal_cell() -> Vector3i:
	return arena_center + Vector3i(0, 0, -4)


func _emit_state() -> void:
	state_changed.emit(hud_text())


func _fail(reason: String) -> void:
	state = FAILED
	last_route_reason = reason
	feedback.emit("Defense drill stopped: %s." % reason.replace("_", " ").capitalize())
	_emit_state()


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
