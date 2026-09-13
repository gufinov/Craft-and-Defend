class_name CoreDefenseService
extends Node3D

signal state_changed(text: String)
signal feedback(message: String)

const IDLE := "idle"
const WARNING := "warning"
const ROUTING := "routing"
const ATTACKING_STRUCTURE := "attacking_structure"
const ATTACKING_CORE := "attacking_core"
const FAILED := "failed"
const WARNING_SECONDS := 20.0
const CORE_MAX_INTEGRITY := 30
const RAIDER_MAX_HEALTH := 20
const RAIDER_DAMAGE := 6
const RAIDER_ATTACK_INTERVAL := 1.4
const ARENA_CANDIDATES: Array[Vector3i] = [
	Vector3i(6, 0, 38),
	Vector3i(-6, 0, 38),
	Vector3i(0, 0, 38),
	Vector3i(10, 0, 40),
	Vector3i(-10, 0, 40),
]

var world: WorldAdapter
var registry: ContentRegistry
var workstations: WorkstationService
var state := IDLE
var arena_center := Vector3i.ZERO
var warning_remaining := 0.0
var core_integrity := CORE_MAX_INTEGRITY
var raider_health := RAIDER_MAX_HEALTH
var attack_timer := 0.0
var active_target_type := ""
var active_target_id := ""
var active_target_cell := Vector3i.ZERO
var last_route_reason := ""
var navigation_revision := 0
var exact_invalidations := 0
var navigation_snapshot: NavigationSnapshot
var raider: BasicRaider
var _core_root: StaticBody3D
var _core_material: StandardMaterial3D
var _pending_restore: Dictionary = {}
var _replan_queued := false


func initialize(world_adapter: WorldAdapter, content_registry: ContentRegistry, station_service: WorkstationService, saved: Dictionary = {}) -> void:
	world = world_adapter
	registry = content_registry
	workstations = station_service
	_pending_restore = saved.duplicate(true)
	world.cell_changed.connect(_on_world_cell_changed)


func is_active() -> bool:
	return state in [WARNING, ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE]


func clear_for_other_mode() -> void:
	_clear_fixture()
	state = IDLE
	warning_remaining = 0.0
	active_target_type = ""
	active_target_id = ""
	_emit_state()


func restore_after_world_ready() -> Dictionary:
	if _pending_restore.is_empty():
		_emit_state()
		return {"ok": true, "reason": "OK"}
	var saved := _pending_restore
	_pending_restore = {}
	var restored_state := str(saved.get("state", IDLE))
	if restored_state not in [IDLE, WARNING, ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE, FAILED]:
		return {"ok": false, "reason": "INVALID_CORE_DEFENSE_SNAPSHOT"}
	state = restored_state
	if state == IDLE:
		_emit_state()
		return {"ok": true, "reason": "OK"}
	var center_value: Variant = saved.get("arena_center", [])
	if not center_value is Array or center_value.size() != 3:
		return {"ok": false, "reason": "INVALID_CORE_DEFENSE_SNAPSHOT"}
	arena_center = Vector3i(int(center_value[0]), int(center_value[1]), int(center_value[2]))
	if not _arena_is_available(arena_center):
		return {"ok": false, "reason": "CORE_ARENA_BLOCKED"}
	warning_remaining = maxf(0.0, float(saved.get("warning_remaining", 0.0)))
	core_integrity = clampi(int(saved.get("core_integrity", CORE_MAX_INTEGRITY)), 0, CORE_MAX_INTEGRITY)
	raider_health = clampi(int(saved.get("raider_health", RAIDER_MAX_HEALTH)), 0, RAIDER_MAX_HEALTH)
	navigation_revision = maxi(0, int(saved.get("navigation_revision", 0)))
	active_target_type = str(saved.get("active_target_type", ""))
	active_target_id = str(saved.get("active_target_id", ""))
	active_target_cell = _vector3i_from_array(saved.get("active_target_cell", []), Vector3i.ZERO)
	_build_core_visual()
	if state in [ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE] and raider_health > 0 and core_integrity > 0:
		var saved_position := _vector3_from_array(saved.get("raider_position", []), _start_position())
		_spawn_raider(saved_position)
		_plan_from_raider()
	_emit_state()
	return {"ok": true, "reason": "OK"}


func start_prototype() -> Dictionary:
	if is_active():
		return {"ok": false, "reason": "DEFENSE_ALREADY_ACTIVE"}
	var found := _find_available_arena()
	if not found.get("ok", false):
		return found
	_clear_fixture()
	arena_center = found.get("center", Vector3i.ZERO)
	state = WARNING
	warning_remaining = WARNING_SECONDS
	core_integrity = CORE_MAX_INTEGRITY
	raider_health = RAIDER_MAX_HEALTH
	attack_timer = RAIDER_ATTACK_INTERVAL
	active_target_type = ""
	active_target_id = ""
	active_target_cell = Vector3i.ZERO
	last_route_reason = ""
	navigation_revision = 0
	exact_invalidations = 0
	_build_core_visual()
	feedback.emit("Core-defense setup: 20 seconds. Place wooden barricades across the field-side approach; any opening will be used.")
	_emit_state()
	return {"ok": true, "reason": "OK", "center": arena_center, "core_cell": _core_cell()}


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0:
		return
	if state == WARNING:
		warning_remaining = maxf(0.0, warning_remaining - delta)
		_emit_state()
		if warning_remaining <= 0.0:
			_begin_attack()
	elif state in [ATTACKING_STRUCTURE, ATTACKING_CORE]:
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_timer += RAIDER_ATTACK_INTERVAL
			if state == ATTACKING_STRUCTURE:
				_attack_structure()
			else:
				_attack_core()


func notify_placed_entity_cells(changed_cells: Array) -> void:
	if _refresh_navigation(changed_cells) and is_instance_valid(raider) and state in [ROUTING, ATTACKING_STRUCTURE]:
		_queue_replan()


func snapshot() -> Dictionary:
	return {
		"state": state,
		"arena_center": _vector3i_to_array(arena_center),
		"warning_remaining": warning_remaining,
		"core_integrity": core_integrity,
		"raider_health": raider_health,
		"raider_position": _vector3_to_array(raider.global_position) if is_instance_valid(raider) else [],
		"active_target_type": active_target_type,
		"active_target_id": active_target_id,
		"active_target_cell": _vector3i_to_array(active_target_cell),
		"last_route_reason": last_route_reason,
		"navigation_revision": navigation_revision,
	}


func hud_text() -> String:
	match state:
		IDLE:
			return "CORE DEFENSE · Pause and choose Start Core Defense Prototype"
		WARNING:
			return "⚠ CORE SETUP · raider in %d · build across the field-side approach · core %d/%d" % [ceili(warning_remaining), core_integrity, CORE_MAX_INTEGRITY]
		ROUTING:
			return "RAIDER ROUTING TO CORE · open path preferred · core %d/%d" % [core_integrity, CORE_MAX_INTEGRITY]
		ATTACKING_STRUCTURE:
			var status := workstations.defense_status(active_target_id)
			var details: Dictionary = status.get("details", {})
			return "BREACHING %s · %d/%d · core %d/%d" % [registry.display_name(str(details.get("entity_id", "wood_barricade"))), int(details.get("integrity", 0)), int(details.get("max_integrity", 0)), core_integrity, CORE_MAX_INTEGRITY]
		ATTACKING_CORE:
			return "CORE UNDER ATTACK · %d/%d · no open defense remains" % [core_integrity, CORE_MAX_INTEGRITY]
		FAILED:
			return "CORE DEFENSE FAILED · prototype core destroyed"
	return "CORE DEFENSE PROTOTYPE"


func _begin_attack() -> void:
	state = ROUTING
	_spawn_raider(_start_position())
	_plan_from_raider()
	feedback.emit("Raider entered from the field side with the strategic core as its destination.")
	_emit_state()


func _plan_from_raider() -> void:
	if not is_instance_valid(raider) or core_integrity <= 0:
		return
	_capture_navigation()
	if navigation_snapshot == null:
		_fail("NAVIGATION_CAPTURE_FAILED")
		return
	var start := raider.feet_cell()
	var capability := _basic_raider_capability()
	var planner := LocalGridPathfinder.new()
	var plan := planner.plan_next(navigation_snapshot, start, _core_approach_cell(), capability)
	last_route_reason = str(plan.get("reason", "NO_ROUTE"))
	if last_route_reason == "OK":
		active_target_type = "core"
		active_target_id = "strategic_core_prototype"
		active_target_cell = _core_cell()
		state = ROUTING
		raider.set_route(plan.get("path", []))
		_emit_state()
		return
	if last_route_reason == "ATTACK_OBSTRUCTION":
		var action: Dictionary = plan.get("action", {})
		var instance_id := str(action.get("source_id", ""))
		if str(action.get("source", "")) != "entity" or not workstations.defense_status(instance_id).get("ok", false):
			_fail("NO_PERMITTED_BREACH")
			return
		var approach: Vector3i = action.get("from", start)
		var route := planner.find_route(navigation_snapshot, start, approach, capability)
		if not route.get("ok", false):
			_fail("NO_APPROACH_ROUTE")
			return
		active_target_type = "structure"
		active_target_id = instance_id
		active_target_cell = action.get("cell", Vector3i.ZERO)
		state = ROUTING
		raider.set_route(route.get("path", []))
		_emit_state()
		return
	_fail("NO_PERMITTED_ROUTE")


func _on_raider_route_finished() -> void:
	if not is_instance_valid(raider):
		return
	attack_timer = 0.3
	if active_target_type == "core":
		state = ATTACKING_CORE
		feedback.emit("Raider reached the strategic core because an open route remained.")
	elif active_target_type == "structure" and workstations.defense_status(active_target_id).get("ok", false):
		state = ATTACKING_STRUCTURE
		feedback.emit("No open route remains. Raider is breaching one permitted wooden barricade.")
	else:
		_queue_replan()
	_emit_state()


func _attack_structure() -> void:
	var result := workstations.try_damage(active_target_id, RAIDER_DAMAGE)
	if not result.get("ok", false):
		_queue_replan()
		return
	var details: Dictionary = result.get("details", {})
	if result.get("reason") == "DESTROYED":
		feedback.emit("Wooden barricade breached. The raider is replanning toward the core.")
		_queue_replan()
	else:
		feedback.emit("Raider hit %s for %d. Integrity: %d/%d." % [registry.display_name(str(details.get("entity_id", "wood_barricade"))), RAIDER_DAMAGE, int(details.get("integrity", 0)), int(details.get("max_integrity", 0))])
	_emit_state()


func _attack_core() -> void:
	if core_integrity <= 0:
		return
	core_integrity = maxi(0, core_integrity - RAIDER_DAMAGE)
	_update_core_presentation()
	feedback.emit("Raider hit the strategic core for %d. Core integrity: %d/%d." % [RAIDER_DAMAGE, core_integrity, CORE_MAX_INTEGRITY])
	if core_integrity <= 0:
		state = FAILED
		if is_instance_valid(raider):
			raider.active = false
		feedback.emit("Core-defense prototype failed: the strategic core was destroyed.")
	_emit_state()


func _basic_raider_capability() -> Dictionary:
	return {"max_step_up": 1, "max_drop_down": 1, "damage_per_hit": {"breachable_wood": RAIDER_DAMAGE}}


func _capture_navigation() -> void:
	navigation_snapshot = NavigationSnapshot.new()
	var region := AABB(Vector3(arena_center + Vector3i(-5, -2, -9)), Vector3(11, 5, 16))
	var result := navigation_snapshot.capture(region, _query_navigation_cell, world.revision + navigation_revision)
	if not result.get("ok", false):
		navigation_snapshot = null


func _query_navigation_cell(cell: Vector3i) -> Dictionary:
	if cell == _core_cell():
		return {"state": "LOADED", "solid": true, "voxel_id": -1, "material_id": "strategic_core_prototype", "source": "core", "source_id": "strategic_core_prototype", "tags": [], "integrity": core_integrity, "protected": true}
	var instance_id := workstations.station_at_cell(cell)
	if not instance_id.is_empty():
		return workstations.navigation_cell_data(instance_id)
	var query := world.query_cell(cell)
	if str(query.get("state", "UNLOADED")) != "LOADED":
		return {"state": str(query.get("state", "UNLOADED")), "solid": true}
	var voxel_id := int(query.get("voxel_id", 0))
	if voxel_id == 0:
		return {"state": "LOADED", "solid": false, "voxel_id": 0, "material_id": "air", "source": "voxel", "tags": [], "integrity": 0, "protected": false}
	var block := registry.block_for_voxel(voxel_id)
	var material_id := str(block.get("id", "unknown"))
	var tags: Array = ["stone"]
	var integrity := 60
	if material_id in ["grass", "dirt"]:
		tags = ["earth"]
		integrity = 18
	elif material_id in ["log", "planks"]:
		tags = ["wood"]
		integrity = 24
	elif material_id == "castle_stone":
		tags = ["stone", "fortification"]
		integrity = 90
	return {"state": "LOADED", "solid": bool(block.get("solid", true)), "voxel_id": voxel_id, "material_id": material_id, "source": "voxel", "source_id": material_id, "tags": tags, "integrity": integrity, "protected": bool(block.get("protected", false))}


func _refresh_navigation(changed_cells: Array) -> bool:
	if navigation_snapshot == null:
		return false
	var relevant: Array[Vector3i] = []
	for value in changed_cells:
		if value is Vector3i and navigation_snapshot.contains(value):
			relevant.append(value)
	if relevant.is_empty():
		return false
	navigation_revision += 1
	exact_invalidations += relevant.size()
	navigation_snapshot.refresh_cells(relevant, _query_navigation_cell, world.revision + navigation_revision)
	return true


func _queue_replan() -> void:
	if _replan_queued or not is_instance_valid(raider):
		return
	_replan_queued = true
	call_deferred("_run_queued_replan")


func _run_queued_replan() -> void:
	_replan_queued = false
	if is_instance_valid(raider) and core_integrity > 0:
		_plan_from_raider()


func _on_world_cell_changed(cell: Vector3i, _previous: int, _next: int, _revision: int) -> void:
	if _refresh_navigation([cell]) and is_active():
		_queue_replan()


func _find_available_arena() -> Dictionary:
	for candidate: Vector3i in ARENA_CANDIDATES:
		if _arena_is_available(candidate):
			return {"ok": true, "reason": "OK", "center": candidate}
	return {"ok": false, "reason": "CORE_ARENA_BLOCKED"}


func _arena_is_available(center: Vector3i) -> bool:
	for cell: Vector3i in [center + Vector3i(0, 0, -8), center + Vector3i(0, 0, 4), center + Vector3i(0, 0, 5)]:
		var floor_query := world.query_cell(cell + Vector3i.DOWN)
		var feet_query := world.query_cell(cell)
		var head_query := world.query_cell(cell + Vector3i.UP)
		if str(floor_query.get("state", "UNLOADED")) != "LOADED" or int(floor_query.get("voxel_id", 0)) == 0:
			return false
		if str(feet_query.get("state", "UNLOADED")) != "LOADED" or int(feet_query.get("voxel_id", 0)) != 0:
			return false
		if str(head_query.get("state", "UNLOADED")) != "LOADED" or int(head_query.get("voxel_id", 0)) != 0:
			return false
		if not workstations.station_at_cell(cell).is_empty() or not workstations.station_at_cell(cell + Vector3i.UP).is_empty():
			return false
	return true


func _build_core_visual() -> void:
	if core_integrity <= 0:
		return
	_core_root = StaticBody3D.new()
	_core_root.name = "StrategicCorePrototype"
	_core_root.position = Vector3(_core_cell()) + Vector3(0.5, 0.5, 0.5)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.0, 0.8)
	collision.shape = shape
	_core_root.add_child(collision)
	_core_material = StandardMaterial3D.new()
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_material.emission_enabled = true
	_core_material.emission_energy_multiplier = 2.2
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.72, 1.45, 0.72)
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 1.15
	mesh_instance.rotation = Vector3(0.0, PI / 4.0, PI / 4.0)
	mesh_instance.material_override = _core_material
	_core_root.add_child(mesh_instance)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.65
	base_mesh.bottom_radius = 0.8
	base_mesh.height = 0.35
	base.mesh = base_mesh
	base.position.y = -0.32
	base.material_override = _core_material
	_core_root.add_child(base)
	var label := Label3D.new()
	label.text = "STRATEGIC CORE PROTOTYPE"
	label.position = Vector3(0.0, 2.75, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 0.008
	label.outline_size = 8
	_core_root.add_child(label)
	add_child(_core_root)
	_update_core_presentation()


func _update_core_presentation() -> void:
	if _core_material == null:
		return
	var ratio := float(core_integrity) / float(CORE_MAX_INTEGRITY)
	var color := Color("52e5ff").lerp(Color("ff4d6d"), 1.0 - ratio)
	_core_material.albedo_color = color
	_core_material.emission = color


func _spawn_raider(spawn_position: Vector3) -> void:
	if is_instance_valid(raider):
		raider.queue_free()
	raider = BasicRaider.new()
	add_child(raider)
	raider.global_position = spawn_position
	raider.route_finished.connect(_on_raider_route_finished)


func _clear_fixture() -> void:
	for value in [_core_root, raider]:
		if is_instance_valid(value):
			value.queue_free()
	_core_root = null
	_core_material = null
	raider = null
	navigation_snapshot = null
	_replan_queued = false


func _start_position() -> Vector3:
	return Vector3(_start_cell()) + Vector3(0.5, 0.9, 0.5)


func _start_cell() -> Vector3i:
	return arena_center + Vector3i(0, 0, -8)


func _core_approach_cell() -> Vector3i:
	return arena_center + Vector3i(0, 0, 4)


func _core_cell() -> Vector3i:
	return arena_center + Vector3i(0, 0, 5)


func _emit_state() -> void:
	state_changed.emit(hud_text())


func _fail(reason: String) -> void:
	state = FAILED
	last_route_reason = reason
	if is_instance_valid(raider):
		raider.active = false
	feedback.emit("Core-defense prototype stopped: %s." % reason.replace("_", " ").capitalize())
	_emit_state()


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _vector3i_to_array(value: Vector3i) -> Array:
	return [value.x, value.y, value.z]


func _vector3i_from_array(value: Variant, fallback: Vector3i) -> Vector3i:
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return fallback
