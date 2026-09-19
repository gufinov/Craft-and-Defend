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
const WON := "won"
const WARNING_SECONDS := 20.0
const CORE_MAX_INTEGRITY := 30
const RAIDER_MAX_HEALTH := 20
const RAIDER_DAMAGE := 6
const RAIDER_ATTACK_INTERVAL := 1.4
const BRUTE_MAX_HEALTH := 40
const BRUTE_DAMAGE := 10
## P4F trolls: ranged crossbow units that stop within TROLL_RANGE cells of
## their target and shoot every TROLL_ATTACK_INTERVAL seconds.
const TROLL_MAX_HEALTH := 28
const TROLL_DAMAGE := 5
const TROLL_RANGE := 9.0
const TROLL_ATTACK_INTERVAL := 2.0
const TROLL_BOLT_SECONDS := 0.3
## Default spawn line (cells from the arena centre toward the field side) and
## the farthest a wave may start from.
const SPAWN_DISTANCE := 8
const MAX_SPAWN_DISTANCE := 28
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
var warning_seconds := WARNING_SECONDS
var core_max_integrity := CORE_MAX_INTEGRITY
var raider_max_health := RAIDER_MAX_HEALTH
var raider_damage := RAIDER_DAMAGE
var raider_attack_interval := RAIDER_ATTACK_INTERVAL
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
var brute_max_health := BRUTE_MAX_HEALTH
var brute_damage := BRUTE_DAMAGE
var troll_max_health := TROLL_MAX_HEALTH
var troll_damage := TROLL_DAMAGE
var troll_range := TROLL_RANGE
var troll_attack_interval := TROLL_ATTACK_INTERVAL
## Bolts fired by trolls in this drill (diagnostics read it).
var ranged_shots := 0
## P4D waves: the spawn line for the current drill and the extra raiders
## beyond the primary one. Each entry: {node, health, max_health, kind,
## damage, ranged, range, attack_interval, target_type, target_id,
## target_cell, attack_timer, route_reason, phase}.
var spawn_distance := SPAWN_DISTANCE
var wave_size := 1
var extra_raiders: Array[Dictionary] = []
var _core_root: StaticBody3D
var _core_material: StandardMaterial3D
var _pending_restore: Dictionary = {}
var _replan_queued := false
var _pending_brutes := 0
var _pending_trolls := 0
var _capture_reason := "OK"
var _stall_retry_pending := false
const STALL_RETRY_SECONDS := 2.0
const BRUTE_SMASH_RADIUS := 2.6
const WAVE_SPREAD := 4
## Far waves (P4E): raiders march from the enemy base over the generated
## surface and hand over to the local planner MARCH_HANDOVER cells from the
## arena; the local capture then covers LOCAL_RADIUS around the arena.
const MARCH_HANDOVER := 18
const LOCAL_RADIUS := 20
var far_mode := false
## P4H aggro (owner 2026-09-19): "if an enemy gets attacked by something it
## tries to destroy that as long as it is in range and attention, otherwise
## drive to the core." A provoked raider chases its attacker (the player or
## the machine that shot it) for ATTENTION_SECONDS within ATTENTION_RANGE,
## hits it when in reach, then resumes its route.
const ATTENTION_SECONDS := 8.0
const ATTENTION_RANGE := 14.0
const MELEE_REACH := 2.0
const CHASE_REPLAN_SECONDS := 0.4
var player: Node3D
var player_hits := 0
var _primary_chase: Dictionary = {}
## P4G: when the player has placed a Core of Power, the drill defends that
## station (its integrity is the core's integrity) instead of the prototype
## core cell; "" means the legacy prototype core at arena_center + (0, 0, 5).
var core_station_id := ""
const CORE_ENTITY := "core_of_power"
var _march_router: SurfaceRouter
var _wave_rng := RandomNumberGenerator.new()
var _capture_retries := 0
const CAPTURE_RETRY_LIMIT := 40
const CAPTURE_RETRY_SECONDS := 0.5


func initialize(world_adapter: WorldAdapter, content_registry: ContentRegistry, station_service: WorkstationService, saved: Dictionary = {}) -> void:
	world = world_adapter
	registry = content_registry
	workstations = station_service
	warning_seconds = maxf(0.1, registry.balance_number("core_defense.warning_seconds", WARNING_SECONDS))
	core_max_integrity = maxi(1, registry.balance_integer("core_defense.core_integrity", CORE_MAX_INTEGRITY))
	raider_max_health = maxi(1, registry.balance_integer("core_defense.raider_health", RAIDER_MAX_HEALTH))
	raider_damage = maxi(1, registry.balance_integer("core_defense.raider_damage", RAIDER_DAMAGE))
	raider_attack_interval = maxf(0.05, registry.balance_number("core_defense.raider_attack_interval_seconds", RAIDER_ATTACK_INTERVAL))
	brute_max_health = maxi(1, registry.balance_integer("core_defense.brute_health", BRUTE_MAX_HEALTH))
	brute_damage = maxi(1, registry.balance_integer("core_defense.brute_damage", BRUTE_DAMAGE))
	troll_max_health = maxi(1, registry.balance_integer("core_defense.troll_health", TROLL_MAX_HEALTH))
	troll_damage = maxi(1, registry.balance_integer("core_defense.troll_damage", TROLL_DAMAGE))
	troll_range = maxf(1.0, registry.balance_number("core_defense.troll_range", TROLL_RANGE))
	troll_attack_interval = maxf(0.05, registry.balance_number("core_defense.troll_attack_interval_seconds", TROLL_ATTACK_INTERVAL))
	core_integrity = core_max_integrity
	raider_health = raider_max_health
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
	if restored_state not in [IDLE, WARNING, ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE, FAILED, WON]:
		return {"ok": false, "reason": "INVALID_CORE_DEFENSE_SNAPSHOT"}
	state = restored_state
	if state == IDLE:
		_emit_state()
		return {"ok": true, "reason": "OK"}
	var center_value: Variant = saved.get("arena_center", [])
	if not center_value is Array or center_value.size() != 3:
		return {"ok": false, "reason": "INVALID_CORE_DEFENSE_SNAPSHOT"}
	arena_center = Vector3i(int(center_value[0]), int(center_value[1]), int(center_value[2]))
	if str(saved.get("core_station_id", "")).is_empty() and not _arena_is_available(arena_center):
		return {"ok": false, "reason": "CORE_ARENA_BLOCKED"}
	warning_remaining = maxf(0.0, float(saved.get("warning_remaining", 0.0)))
	core_integrity = clampi(int(saved.get("core_integrity", core_max_integrity)), 0, core_max_integrity)
	raider_health = clampi(int(saved.get("raider_health", raider_max_health)), 0, raider_max_health)
	navigation_revision = maxi(0, int(saved.get("navigation_revision", 0)))
	active_target_type = str(saved.get("active_target_type", ""))
	active_target_id = str(saved.get("active_target_id", ""))
	active_target_cell = _vector3i_from_array(saved.get("active_target_cell", []), Vector3i.ZERO)
	spawn_distance = clampi(int(saved.get("spawn_distance", SPAWN_DISTANCE)), SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
	wave_size = maxi(1, int(saved.get("wave_size", 1)))
	far_mode = bool(saved.get("far_mode", false)) and _terrain_generator() != null
	core_station_id = str(saved.get("core_station_id", ""))
	if not core_station_id.is_empty() and not workstations.stations.has(core_station_id):
		# The defended core no longer exists (destroyed before the save, or the
		# record is gone): the drill is over, never a reason to refuse the save.
		core_station_id = ""
		core_integrity = 0
		state = FAILED
		feedback.emit("Your Core of Power is gone; the last defense counts as lost. Place a new core to defend again.")
		_emit_state()
		return {"ok": true, "reason": "CORE_STATION_MISSING_RESOLVED"}
	_sync_core_from_station()
	_build_core_visual()
	if state in [ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE] and raider_health > 0 and core_integrity > 0:
		var saved_position := _vector3_from_array(saved.get("raider_position", []), _start_position())
		_spawn_raider(_settled_position(saved_position))
		if far_mode and not _within_local_area(raider):
			last_route_reason = "MARCHING"
			active_target_type = ""
			_remarch(raider)
		else:
			_plan_from_raider()
	if state in [ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE] and core_integrity > 0:
		var saved_extras: Variant = saved.get("extra_raiders", [])
		if saved_extras is Array:
			for value in saved_extras:
				if not value is Dictionary or int(value.get("health", 0)) <= 0:
					continue
				var entry := _spawn_extra_raider(_settled_position(_vector3_from_array(value.get("position", []), _start_position())), str(value.get("kind", BasicRaider.KIND_RAIDER)))
				entry.health = clampi(int(value.get("health", entry.max_health)), 1, int(entry.max_health))
				if far_mode and not _within_local_area(entry.node):
					entry.phase = "marching"
					_remarch(entry.node)
				else:
					_plan_extra(entry)
	_emit_state()
	return {"ok": true, "reason": "OK"}


## Starts the drill. Options (P4D/P4F): "raiders" (wave size, default 1),
## "brutes" (how many of them are brutes, default 0), "trolls" (how many are
## ranged trolls, default 0; the primary raider is always a melee orc) and
## "spawn_distance" (cells from the arena centre to the field-side spawn
## line, 8..28).
func start_prototype(options: Dictionary = {}) -> Dictionary:
	if is_active():
		return {"ok": false, "reason": "DEFENSE_ALREADY_ACTIVE"}
	var requested_far := bool(options.get("from_enemy_base", false)) and _terrain_generator() != null
	var requested_distance := clampi(int(options.get("spawn_distance", SPAWN_DISTANCE)), SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
	var found := _find_available_arena(SPAWN_DISTANCE if requested_far else requested_distance)
	if not found.get("ok", false):
		return found
	_clear_fixture()
	arena_center = found.get("center", Vector3i.ZERO)
	core_station_id = str(found.get("core_station_id", ""))
	far_mode = requested_far
	spawn_distance = requested_distance
	_wave_rng.randomize()
	wave_size = maxi(1, int(options.get("raiders", 1)))
	_pending_brutes = clampi(int(options.get("brutes", 0)), 0, wave_size)
	_pending_trolls = clampi(int(options.get("trolls", 0)), 0, wave_size)
	ranged_shots = 0
	state = WARNING
	warning_remaining = warning_seconds
	core_integrity = core_max_integrity
	_sync_core_from_station()
	raider_health = raider_max_health
	attack_timer = raider_attack_interval
	active_target_type = ""
	active_target_id = ""
	active_target_cell = Vector3i.ZERO
	last_route_reason = ""
	navigation_revision = 0
	exact_invalidations = 0
	_build_core_visual()
	if far_mode:
		var base := _terrain_generator().enemy_base_cell()
		feedback.emit("The enemy base at %d, %d is sending %d raiders (%d cells away). They arrive in about %d seconds; build around your core." % [base.x, base.z, wave_size, int(Vector2(float(base.x - arena_center.x), float(base.z - arena_center.z)).length()), ceili(warning_seconds) + int(Vector2(float(base.x - arena_center.x), float(base.z - arena_center.z)).length() / BasicRaider.MOVE_SPEED)])
	elif wave_size > 1:
		feedback.emit("Wave setup: %d raiders will enter from %d cells out in %d seconds. Build across the field-side approach." % [wave_size, spawn_distance, ceili(warning_seconds)])
	else:
		feedback.emit("Core-defense setup: 20 seconds. Place wooden barricades across the field-side approach; any opening will be used.")
	_emit_state()
	return {"ok": true, "reason": "OK", "center": arena_center, "core_cell": _core_cell(), "spawn_distance": spawn_distance, "raiders": wave_size}


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
			attack_timer += raider_attack_interval
			if state == ATTACKING_STRUCTURE:
				_attack_structure()
			else:
				_attack_core()
	if is_active():
		if not _primary_chase.is_empty() and is_instance_valid(raider):
			if not _advance_chase(raider, _primary_chase, raider_damage, raider_attack_interval, false, delta):
				_primary_chase = {}
				_queue_replan()
		_advance_extras(delta)


## Extra raiders (P4D) run their own attack timers against whatever they
## reached; the drill state machine still follows the primary raider.
func _advance_extras(delta: float) -> void:
	for entry in extra_raiders:
		if int(entry.health) <= 0 or not is_instance_valid(entry.node):
			continue
		var phase := str(entry.get("phase", "routing"))
		if phase == "marching":
			continue
		if phase == "chasing":
			if not _advance_chase(entry.node, entry.chase, int(entry.damage), float(entry.get("attack_interval", raider_attack_interval)), bool(entry.get("ranged", false)), delta):
				entry.erase("chase")
				_plan_extra(entry)
			continue
		if phase == "routing":
			if str(entry.kind) == BasicRaider.KIND_BRUTE:
				_brute_smashes_nearby(entry, delta)
			# Ranged units stop as soon as their target is within range and
			# shoot from there; melee units walk on until the route ends.
			if bool(entry.get("ranged", false)) and _ranged_target_in_range(entry):
				_engage_ranged(entry)
			continue
		entry.attack_timer = float(entry.attack_timer) - delta
		if float(entry.attack_timer) > 0.0:
			continue
		if phase == "stalled":
			_plan_extra(entry)
			continue
		entry.attack_timer = float(entry.attack_timer) + float(entry.get("attack_interval", raider_attack_interval))
		if bool(entry.get("ranged", false)):
			_fire_ranged(entry)
		elif is_instance_valid(entry.node):
			entry.node.play_attack()
		if phase == "attacking_core":
			_extra_attacks_core(entry)
		elif phase == "attacking_structure":
			if is_instance_valid(entry.node):
				entry.node.play_attack()
			if str(entry.target_type) == "voxel":
				var stone_damage: int = int(entry.damage) if str(entry.kind) == BasicRaider.KIND_BRUTE else maxi(1, int(entry.damage) / 3)
				if _hit_voxel(entry.target_cell, stone_damage):
					_plan_extra(entry)
				continue
			var result := workstations.try_damage(str(entry.target_id), int(entry.damage))
			if not result.get("ok", false) or result.get("reason") == "DESTROYED":
				_plan_extra(entry)


## Hybrid rule (owner direction 2026-09-19): raiders rush the core, but a
## brute passing within BRUTE_SMASH_RADIUS of a player-built breachable
## structure (machine, chest, rail, kettle, barricade) turns on it and smashes
## it before continuing. Checked once per second per brute.
func _brute_smashes_nearby(entry: Dictionary, delta: float) -> void:
	entry.divert_timer = float(entry.get("divert_timer", 1.0)) - delta
	if float(entry.divert_timer) > 0.0:
		return
	entry.divert_timer = 1.0
	var node: BasicRaider = entry.node
	var nearest := ""
	var best := BRUTE_SMASH_RADIUS
	for instance_id: String in workstations.stations.keys():
		var record: Dictionary = workstations.stations[instance_id]
		if not workstations.defense_status(instance_id).get("ok", false):
			continue
		var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
		var distance := Vector2(anchor.x + 0.5 - node.global_position.x, anchor.z + 0.5 - node.global_position.z).length()
		if distance < best and absf(float(anchor.y) - (node.global_position.y - 0.9)) <= 1.5:
			best = distance
			nearest = instance_id
	if nearest.is_empty():
		return
	entry.target_type = "structure"
	entry.target_id = nearest
	entry.target_cell = workstations.stations[nearest].get("anchor", Vector3i.ZERO)
	entry.phase = "attacking_structure"
	entry.attack_timer = 0.3
	node.active = false
	feedback.emit("A brute turns on your %s." % registry.display_name(str(workstations.stations[nearest].get("entity_id", "structure"))))
## The centre of whatever an extra raider is heading for (core or structure).
func _extra_target_point(entry: Dictionary) -> Vector3:
	var cell: Vector3i = entry.get("target_cell", Vector3i.ZERO)
	if str(entry.get("target_type", "")) == "core":
		return Vector3(cell) + Vector3(0.5, 1.3, 0.5)
	return Vector3(cell) + Vector3(0.5, 0.6, 0.5)


func _ranged_target_in_range(entry: Dictionary) -> bool:
	if str(entry.get("target_type", "")).is_empty() or not is_instance_valid(entry.node):
		return false
	var node: BasicRaider = entry.node
	var cell: Vector3i = entry.get("target_cell", Vector3i.ZERO)
	var target := Vector3(cell) + Vector3(0.5, 0.9, 0.5)
	return node.global_position.distance_to(target) <= float(entry.get("range", troll_range))


## A ranged unit whose target came within range stops, turns and starts its
## shooting timer (line of sight is not required in this slice).
func _engage_ranged(entry: Dictionary) -> void:
	var node: BasicRaider = entry.node
	node.active = false
	node.velocity = Vector3.ZERO
	node.face_point(_extra_target_point(entry))
	entry.attack_timer = 0.3
	if str(entry.target_type) == "core":
		entry.phase = "attacking_core"
	elif str(entry.target_type) == "structure" and workstations.defense_status(str(entry.target_id)).get("ok", false):
		entry.phase = "attacking_structure"
	else:
		_plan_extra(entry)


## A troll shot: the crossbow kicks and a bolt flies to the target over
## TROLL_BOLT_SECONDS. The damage lands with the timer (see _advance_extras),
## not with the bolt.
func _fire_ranged(entry: Dictionary) -> void:
	var node: BasicRaider = entry.node
	if not is_instance_valid(node):
		return
	var target := _extra_target_point(entry)
	node.face_point(target)
	node.play_attack()
	_spawn_troll_bolt(node.muzzle_position(), target)
	ranged_shots += 1


func _spawn_troll_bolt(origin: Vector3, target: Vector3) -> void:
	var bolt := MeshInstance3D.new()
	bolt.name = "TrollBolt"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.03
	mesh.height = 0.6
	mesh.radial_segments = 6
	bolt.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8a5a2b")
	bolt.material_override = material
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.045
	tip_mesh.height = 0.12
	tip_mesh.radial_segments = 6
	tip.mesh = tip_mesh
	var tip_material := StandardMaterial3D.new()
	tip_material.albedo_color = Color("5a6169")
	tip_material.metallic = 0.5
	tip.material_override = tip_material
	tip.position = Vector3(0.0, 0.36, 0.0)
	bolt.add_child(tip)
	add_child(bolt)
	bolt.global_position = origin
	if origin.distance_squared_to(target) > 0.0001:
		bolt.look_at(target, Vector3.UP)
	bolt.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	var tween := create_tween()
	tween.tween_property(bolt, "global_position", target, TROLL_BOLT_SECONDS)
	tween.finished.connect(bolt.queue_free)


func _extra_attacks_core(entry: Dictionary) -> void:
	if core_integrity <= 0:
		return
	_damage_core(int(entry.damage))
	feedback.emit("%s %s your core for %d. Core integrity: %d/%d." % [str(entry.kind).capitalize(), "shot" if bool(entry.get("ranged", false)) else "hit", int(entry.damage), core_integrity, core_max_integrity])
	if core_integrity <= 0:
		state = FAILED
		_halt_all_raiders()
		feedback.emit("Your Core of Power was destroyed." if _uses_placed_core() else "Core-defense prototype failed: the strategic core was destroyed.")
	_emit_state()


func _halt_all_raiders() -> void:
	if is_instance_valid(raider):
		raider.active = false
	for entry in extra_raiders:
		if is_instance_valid(entry.node):
			entry.node.active = false


## The placed core's record changed (damage from any raider path): mirror it
## and fail the drill when it is gone.
func notify_core_station_changed(details: Dictionary) -> void:
	if not is_active() or core_station_id.is_empty() or str(details.get("instance_id", "")) != core_station_id:
		return
	if bool(details.get("destroyed", false)):
		core_integrity = 0
		state = FAILED
		_halt_all_raiders()
		feedback.emit("Your Core of Power was destroyed.")
	else:
		core_integrity = int(details.get("integrity", core_integrity))
	_emit_state()


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
		"spawn_distance": spawn_distance,
		"wave_size": wave_size,
		"far_mode": far_mode,
		"core_station_id": core_station_id,
		"extra_raiders": _extras_snapshot(),
	}


func _extras_snapshot() -> Array:
	var entries: Array = []
	for entry in extra_raiders:
		if int(entry.health) <= 0 or not is_instance_valid(entry.node):
			continue
		entries.append({"kind": str(entry.kind), "health": int(entry.health), "position": _vector3_to_array(entry.node.global_position)})
	return entries


func try_damage_raider(amount: int, source: String = "player") -> Dictionary:
	if amount <= 0:
		return {"ok": false, "reason": "INVALID_DAMAGE"}
	if not (is_active() or state == FAILED) or not is_instance_valid(raider) or raider_health <= 0:
		return {"ok": false, "reason": "NO_RAIDER"}
	var before := raider_health
	raider_health = maxi(0, raider_health - amount)
	if raider_health <= 0:
		raider.die()
		if living_raider_count() == 0 and state != FAILED:
			state = WON
			feedback.emit("Defense won: %s defeated the %s." % [source.replace("_", " ").capitalize(), "raider" if wave_size <= 1 else "last raider"])
		else:
			feedback.emit("%s defeated a raider. %d left." % [source.replace("_", " ").capitalize(), living_raider_count()])
	else:
		feedback.emit("%s hit the raider for %d. Raider health: %d/%d." % [source.replace("_", " ").capitalize(), amount, raider_health, raider_max_health])
	_emit_state()
	return {"ok": true, "reason": "RAIDER_DEFEATED" if raider_health <= 0 else "RAIDER_DAMAGED", "handled": true, "changes": {"health_before": before, "health": raider_health, "damage": amount, "source": source}}


## Damages a specific raider body (primary or extra).
func try_damage_raider_node(node: Node, amount: int, source: String = "player") -> Dictionary:
	if node == raider:
		return try_damage_raider(amount, source)
	for entry in extra_raiders:
		if entry.node != node:
			continue
		if int(entry.health) <= 0 or not (is_active() or state == FAILED):
			return {"ok": false, "reason": "NO_RAIDER"}
		var before := int(entry.health)
		entry.health = maxi(0, int(entry.health) - amount)
		if int(entry.health) <= 0:
			entry.node.die()
			if living_raider_count() == 0 and state != FAILED:
				state = WON
				feedback.emit("Defense won: %s defeated the last raider." % source.replace("_", " ").capitalize())
			else:
				feedback.emit("%s defeated a %s. %d left." % [source.replace("_", " ").capitalize(), str(entry.kind), living_raider_count()])
		_emit_state()
		return {"ok": true, "reason": "RAIDER_DEFEATED" if int(entry.health) <= 0 else "RAIDER_DAMAGED", "handled": true, "changes": {"health_before": before, "health": int(entry.health), "damage": amount, "source": source}}
	return {"ok": false, "reason": "NO_RAIDER"}


## A raider was hurt by `source` ("player" or a station instance id): it
## turns on that attacker if it is within ATTENTION_RANGE.
func notify_raider_provoked(node: Node, source: String) -> void:
	if not is_active() or not is_raider_node(node):
		return
	var attacker := _attacker_point(source)
	if not attacker.is_finite() or attacker.distance_to(node.global_position) > ATTENTION_RANGE:
		return
	var chase := {"kind": "player" if source == "player" else "structure", "id": source, "until": Time.get_ticks_msec() + int(ATTENTION_SECONDS * 1000.0), "replan": 0.0, "attack_timer": 0.4}
	if node == raider:
		if far_mode and last_route_reason == "MARCHING":
			return
		_primary_chase = chase
		raider.active = false
		return
	for entry in extra_raiders:
		if entry.node == node and str(entry.get("phase", "")) != "marching":
			entry.chase = chase
			entry.phase = "chasing"
			node.active = false
			return


func provoke_raiders_within(point: Vector3, radius: float, source: String) -> void:
	for node in raider_nodes():
		var position := node.global_position + Vector3.UP * 0.65
		if Vector2(position.x - point.x, position.z - point.z).length() <= radius:
			notify_raider_provoked(node, source)


## Where the attacker is: the player's body or a station's anchor centre.
func _attacker_point(source: String) -> Vector3:
	if source == "player":
		return player.global_position if is_instance_valid(player) else Vector3.INF
	if workstations == null or not workstations.stations.has(source):
		return Vector3.INF
	var anchor: Vector3i = workstations.stations[source].get("anchor", Vector3i.ZERO)
	return Vector3(anchor) + Vector3(0.5, 0.9, 0.5)


## Drives one chase for `node`. Returns false when the chase is over.
func _advance_chase(node: BasicRaider, chase: Dictionary, damage: int, interval: float, ranged: bool, delta: float) -> bool:
	if not is_instance_valid(node) or node.dead:
		return false
	var source := str(chase.id)
	var target := _attacker_point(source)
	if Time.get_ticks_msec() > int(chase.until) or not target.is_finite() or target.distance_to(node.global_position) > ATTENTION_RANGE:
		return false
	if str(chase.kind) == "structure" and not workstations.defense_status(source).get("ok", false):
		return false
	var reach := float(entry_range(ranged)) if ranged else MELEE_REACH
	var distance := Vector2(target.x - node.global_position.x, target.z - node.global_position.z).length()
	chase.attack_timer = float(chase.attack_timer) - delta
	if distance <= reach:
		node.active = false
		node.velocity = Vector3.ZERO
		node.face_point(target)
		if float(chase.attack_timer) <= 0.0:
			chase.attack_timer = interval
			node.play_attack()
			if ranged:
				_spawn_troll_bolt(node.muzzle_position(), target)
			if str(chase.kind) == "player":
				if is_instance_valid(player) and player.has_method("take_damage"):
					var hit: Dictionary = player.take_damage(damage, str(node.kind))
					if hit.get("ok", false):
						player_hits += 1
						feedback.emit("A %s hit you for %d. Health %d/100." % [str(node.kind), damage, int(hit.get("health", 0))])
			else:
				var result := workstations.try_damage(source, damage)
				if result.get("reason") == "DESTROYED":
					return false
		return true
	chase.replan = float(chase.replan) - delta
	if float(chase.replan) <= 0.0:
		chase.replan = CHASE_REPLAN_SECONDS
		var feet := node.feet_cell()
		var goal := Vector3i(floori(target.x), feet.y, floori(target.z))
		node.set_route([feet, goal])
	return true


func entry_range(ranged: bool) -> float:
	return troll_range if ranged else MELEE_REACH


## Splash: damages every living raider within `radius` (horizontal) of
## `point`. Returns the number of raiders hit.
func damage_raiders_within(point: Vector3, radius: float, amount: int, source: String = "siege", provoker: String = "") -> int:
	var hits := 0
	for node in raider_nodes():
		var position := node.global_position + Vector3.UP * 0.65
		if Vector2(position.x - point.x, position.z - point.z).length() <= radius and absf(position.y - point.y) <= 3.0:
			if try_damage_raider_node(node, amount, source).get("ok", false):
				hits += 1
				if not provoker.is_empty():
					notify_raider_provoked(node, provoker)
	return hits


## Fire: damages raiders whose feet stand in `cell` (or a cell above/below it).
func damage_raiders_in_cell(cell: Vector3i, amount: int, source: String = "fire") -> int:
	var hits := 0
	for node in raider_nodes():
		var position := node.global_position
		var feet := Vector3i(floori(position.x), floori(position.y - 0.5), floori(position.z))
		if feet == cell or feet == cell + Vector3i(0, 1, 0) or feet == cell - Vector3i(0, 1, 0):
			if try_damage_raider_node(node, amount, source).get("ok", false):
				hits += 1
	return hits


## Every living raider body, primary first.
func raider_nodes() -> Array[BasicRaider]:
	var nodes: Array[BasicRaider] = []
	var bodies_live := is_active() or state == FAILED
	if bodies_live and is_instance_valid(raider) and raider_health > 0 and not raider.dead:
		nodes.append(raider)
	for entry in extra_raiders:
		if int(entry.health) > 0 and is_instance_valid(entry.node) and not entry.node.dead and bodies_live:
			nodes.append(entry.node)
	return nodes


func is_raider_node(value: Variant) -> bool:
	if value == null or not value is BasicRaider:
		return false
	if value == raider:
		return true
	for entry in extra_raiders:
		if entry.node == value:
			return true
	return false


func living_raider_count() -> int:
	return raider_nodes().size()


func raider_kind_of(node: Node) -> String:
	return str(node.kind) if node is BasicRaider else ""


func raider_target_position() -> Vector3:
	return raider.global_position + Vector3.UP * 0.65 if is_active() and is_instance_valid(raider) and raider_health > 0 else Vector3.INF


## The aim point of the living raider nearest `from` that passes `filter`
## ("any", "raider", "brute" or "troll"), or Vector3.INF when none.
func nearest_raider_position(from: Vector3, filter: String = "any") -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	for node in raider_nodes():
		if filter != "any" and filter != str(node.kind):
			continue
		var position := node.global_position + Vector3.UP * 0.65
		var distance := from.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best = position
	return best


func hud_text() -> String:
	match state:
		IDLE:
			return "CORE DEFENSE · Pause and choose Start Core Defense Prototype"
		WARNING:
			return "⚠ CORE SETUP · raider in %d · build across the field-side approach · core %d/%d" % [ceili(warning_remaining), core_integrity, core_max_integrity]
		ROUTING:
			if far_mode and last_route_reason == "MARCHING" and is_instance_valid(raider):
				var away := Vector2(float(raider.global_position.x - arena_center.x), float(raider.global_position.z - arena_center.z)).length()
				return "WAVE MARCHING FROM THE ENEMY BASE · %d/%d raiders · lead %d m out · core %d/%d" % [living_raider_count(), wave_size, int(away), core_integrity, core_max_integrity]
			if last_route_reason in ["NO_PERMITTED_ROUTE", "NO_PERMITTED_BREACH", "NO_APPROACH_ROUTE"]:
				return "RAIDERS PROBING FOR A WAY IN · %d/%d left · no route they can breach yet · core %d/%d" % [living_raider_count(), wave_size, core_integrity, core_max_integrity]
			if wave_size > 1:
				return "WAVE ROUTING TO CORE · %d/%d raiders left · lead HP %d/%d · core %d/%d" % [living_raider_count(), wave_size, raider_health, raider_max_health, core_integrity, core_max_integrity]
			return "RAIDER ROUTING TO CORE · HP %d/%d · open path preferred · core %d/%d" % [raider_health, raider_max_health, core_integrity, core_max_integrity]
		ATTACKING_STRUCTURE:
			var status := workstations.defense_status(active_target_id)
			var details: Dictionary = status.get("details", {})
			return "BREACHING %s · raider %d/%d · wall %d/%d · core %d/%d" % [registry.display_name(str(details.get("entity_id", "wood_barricade"))), raider_health, raider_max_health, int(details.get("integrity", 0)), int(details.get("max_integrity", 0)), core_integrity, core_max_integrity]
		ATTACKING_CORE:
			return "CORE UNDER ATTACK · %d/%d raiders · core %d/%d" % [living_raider_count(), wave_size, core_integrity, core_max_integrity]
		WON:
			return "DEFENSE WON · core %d/%d · raider defeated" % [core_integrity, core_max_integrity]
		FAILED:
			return "CORE DEFENSE FAILED · prototype core destroyed"
	return "CORE DEFENSE PROTOTYPE"


func _begin_attack() -> void:
	state = ROUTING
	if far_mode:
		_begin_far_attack()
		return
	# Bodies only enter once the terrain under the spawn line is loaded and
	# captured; a body spawned over unloaded ground falls through it.
	_capture_navigation()
	if navigation_snapshot == null:
		if _capture_reason == "UNLOADED" and _capture_retries < CAPTURE_RETRY_LIMIT:
			_capture_retries += 1
			last_route_reason = "WAITING_FOR_TERRAIN"
			get_tree().create_timer(CAPTURE_RETRY_SECONDS).timeout.connect(_begin_attack)
			_emit_state()
			return
		_fail("NAVIGATION_CAPTURE_FAILED")
		return
	_capture_retries = 0
	_spawn_raider(_start_position())
	_plan_from_raider()
	var brutes_left := _pending_brutes
	var trolls_left := _pending_trolls
	for index in range(1, wave_size):
		var kind := BasicRaider.KIND_RAIDER
		if brutes_left > 0:
			kind = BasicRaider.KIND_BRUTE
			brutes_left -= 1
		elif trolls_left > 0:
			kind = BasicRaider.KIND_TROLL
			trolls_left -= 1
		var offset := _wave_offset(index, kind)
		var column := _start_cell() + Vector3i(int(offset.x), 0, int(offset.z))
		var surface := _surface_cell(column) if spawn_distance > SPAWN_DISTANCE else column
		var spawn_cell := surface if surface != Vector3i.MAX else _start_cell()
		var entry := _spawn_extra_raider(Vector3(spawn_cell) + Vector3(0.5, 0.9, 0.5), kind)
		_plan_extra(entry)
	if wave_size > 1:
		feedback.emit("A wave of %d entered from %d cells out with the strategic core as its destination." % [wave_size, spawn_distance])
	else:
		feedback.emit("Raider entered from the field side with the strategic core as its destination.")
	_emit_state()


## Far attack: the wave spawns around the enemy base and marches the surface
## route toward the arena; the local planner takes over on arrival.
func _begin_far_attack() -> void:
	var generator := _terrain_generator()
	_march_router = SurfaceRouter.new(generator)
	var base := generator.enemy_base_cell()
	var march := _march_router.route(Vector2i(base.x, base.z), Vector2i(arena_center.x, arena_center.z), MARCH_HANDOVER)
	_spawn_raider(Vector3(base) + Vector3(0.5, 0.9, 0.5))
	_start_march(raider, march)
	active_target_type = ""
	last_route_reason = "MARCHING"
	var brutes_left := _pending_brutes
	var trolls_left := _pending_trolls
	for index in range(1, wave_size):
		var kind := BasicRaider.KIND_RAIDER
		if brutes_left > 0:
			kind = BasicRaider.KIND_BRUTE
			brutes_left -= 1
		elif trolls_left > 0:
			kind = BasicRaider.KIND_TROLL
			trolls_left -= 1
		var offset := _wave_offset(index, kind)
		var column := Vector2i(base.x + int(offset.x), base.z + int(offset.z))
		var spawn_cell := Vector3i(column.x, generator.surface_height(column.x, column.y) + 1, column.y)
		var entry := _spawn_extra_raider(Vector3(spawn_cell) + Vector3(0.5, 0.9, 0.5), kind)
		entry.phase = "marching"
		_start_march(entry.node, march)
	feedback.emit("A wave of %d left the enemy base and is marching on your core." % wave_size)
	_emit_state()


func _start_march(node: BasicRaider, march: Array[Vector3i]) -> void:
	if march.is_empty():
		return
	node.ground_loaded = _ground_loaded
	var cells: Array = []
	for cell in march:
		cells.append(cell)
	node.set_route(cells)


func _ground_loaded(cell: Vector3i) -> bool:
	return str(world.query_cell(cell).get("state", "UNLOADED")) == "LOADED"


## Re-routes a marching body from where it stands (stuck, or restored).
func _remarch(node: BasicRaider) -> void:
	if _march_router == null:
		_march_router = SurfaceRouter.new(_terrain_generator())
	var feet := node.feet_cell()
	var march := _march_router.route(Vector2i(feet.x, feet.z), Vector2i(arena_center.x, arena_center.z), MARCH_HANDOVER)
	_start_march(node, march)


func _within_local_area(node: BasicRaider) -> bool:
	var feet := node.feet_cell()
	return absi(feet.x - arena_center.x) <= LOCAL_RADIUS - 2 and absi(feet.z - arena_center.z) <= LOCAL_RADIUS - 2


func _terrain_generator() -> P1TerrainGenerator:
	if world == null or world.terrain == null:
		return null
	var generator: Variant = world.terrain.generator
	return generator if generator is P1TerrainGenerator else null


## Spread the wave across the spawn line: a seeded random lateral spread of
## up to WAVE_SPREAD cells and up to three rows back, so no two drills line
## up the same way (owner playtest 2026-09-19: identical huddles every run).
func _wave_offset(index: int, kind: String = BasicRaider.KIND_RAIDER) -> Vector3:
	var lateral := _wave_rng.randi_range(-WAVE_SPREAD, WAVE_SPREAD)
	# Loose formation: orcs lead, brutes hold the middle, trolls hang back.
	var row_base := 0
	if kind == BasicRaider.KIND_BRUTE:
		row_base = 2
	elif kind == BasicRaider.KIND_TROLL:
		row_base = 4
	var back := -(row_base + _wave_rng.randi_range(0, 1) + index / 4)
	return Vector3(float(lateral), 0.0, float(back))


func _spawn_extra_raider(spawn_position: Vector3, kind: String) -> Dictionary:
	var node := BasicRaider.new()
	node.configure(kind)
	add_child(node)
	node.global_position = spawn_position
	var brute := kind == BasicRaider.KIND_BRUTE
	var troll := kind == BasicRaider.KIND_TROLL
	var health := raider_max_health
	var damage := raider_damage
	if brute:
		health = brute_max_health
		damage = brute_damage
	elif troll:
		health = troll_max_health
		damage = troll_damage
	var entry := {
		"node": node,
		"kind": kind,
		"health": health,
		"max_health": health,
		"damage": damage,
		"ranged": troll,
		"range": troll_range if troll else 0.0,
		"attack_interval": troll_attack_interval if troll else raider_attack_interval,
		"target_type": "",
		"target_id": "",
		"target_cell": Vector3i.ZERO,
		"attack_timer": 0.3,
		"route_reason": "",
		"phase": "routing",
	}
	extra_raiders.append(entry)
	node.route_finished.connect(_on_extra_route_finished.bind(node))
	node.stuck.connect(_on_extra_stuck.bind(node))
	return entry


## A body that stopped gaining on its next cell re-plans from where it
## actually stands (corner clipping, a tree, a fallen barricade).
func _on_raider_stuck() -> void:
	if not (is_active() and is_instance_valid(raider) and raider_health > 0):
		return
	if far_mode and last_route_reason == "MARCHING":
		_remarch(raider)
		return
	_capture_navigation()
	_plan_from_raider()


func _on_extra_stuck(node: BasicRaider) -> void:
	for entry in extra_raiders:
		if entry.node == node and int(entry.health) > 0:
			if str(entry.get("phase", "")) == "marching":
				_remarch(node)
				return
			_capture_navigation()
			_plan_extra(entry)
			return


func _plan_extra(entry: Dictionary) -> void:
	var node: BasicRaider = entry.node
	if not is_instance_valid(node) or core_integrity <= 0 or int(entry.health) <= 0:
		return
	if navigation_snapshot == null:
		_capture_navigation()
	if navigation_snapshot == null:
		return
	var start := node.feet_cell()
	var capability := _basic_raider_capability()
	capability["damage_per_hit"] = {"breachable_wood": int(entry.damage), "fortification": int(entry.damage) if str(entry.kind) == BasicRaider.KIND_BRUTE else maxi(1, int(entry.damage) / 3)}
	var planner := LocalGridPathfinder.new()
	var plan := planner.plan_next(navigation_snapshot, start, _core_approach_cell(start), capability)
	entry.route_reason = str(plan.get("reason", "NO_ROUTE"))
	entry.phase = "routing"
	if entry.route_reason == "OK":
		entry.target_type = "core"
		entry.target_id = "strategic_core_prototype"
		entry.target_cell = _core_cell()
		node.set_route(plan.get("path", []))
		return
	if entry.route_reason == "ATTACK_OBSTRUCTION":
		var action: Dictionary = plan.get("action", {})
		var instance_id := str(action.get("source_id", ""))
		var voxel_breach := str(action.get("source", "")) == "voxel"
		if not voxel_breach and (str(action.get("source", "")) != "entity" or not workstations.defense_status(instance_id).get("ok", false)):
			_stall_extra(entry)
			return
		var route := planner.find_route(navigation_snapshot, start, action.get("from", start), capability)
		if not route.get("ok", false):
			_stall_extra(entry)
			return
		entry.target_type = "voxel" if voxel_breach else "structure"
		entry.target_id = instance_id
		entry.target_cell = action.get("cell", Vector3i.ZERO)
		node.set_route(route.get("path", []))
		return
	_stall_extra(entry)


func _stall_extra(entry: Dictionary) -> void:
	entry.phase = "stalled"
	entry.attack_timer = STALL_RETRY_SECONDS
	if is_instance_valid(entry.node):
		entry.node.active = false


func _on_extra_route_finished(node: BasicRaider) -> void:
	for entry in extra_raiders:
		if entry.node != node:
			continue
		if str(entry.get("phase", "")) == "marching":
			if _within_local_area(node):
				if navigation_snapshot == null:
					_capture_navigation()
				_plan_extra(entry)
			else:
				_remarch(node)
			return
		entry.attack_timer = 0.3
		if str(entry.target_type) == "core":
			entry.phase = "attacking_core"
		elif str(entry.target_type) == "structure" and workstations.defense_status(str(entry.target_id)).get("ok", false):
			entry.phase = "attacking_structure"
		elif str(entry.target_type) == "voxel":
			entry.phase = "attacking_structure"
		else:
			_plan_extra(entry)
		return


func _plan_from_raider() -> void:
	if not is_instance_valid(raider) or core_integrity <= 0:
		return
	if far_mode and last_route_reason == "MARCHING":
		return
	if not _primary_chase.is_empty():
		return
	_capture_navigation()
	if navigation_snapshot == null:
		# Far wave lines can reach terrain the streamer has not loaded yet;
		# wait for it a few times before giving up.
		if _capture_reason == "UNLOADED" and _capture_retries < CAPTURE_RETRY_LIMIT:
			_capture_retries += 1
			last_route_reason = "WAITING_FOR_TERRAIN"
			get_tree().create_timer(CAPTURE_RETRY_SECONDS).timeout.connect(_queue_replan)
			_emit_state()
			return
		_fail("NAVIGATION_CAPTURE_FAILED")
		return
	_capture_retries = 0
	var start := raider.feet_cell()
	var capability := _basic_raider_capability()
	var planner := LocalGridPathfinder.new()
	var plan := planner.plan_next(navigation_snapshot, start, _core_approach_cell(start), capability)
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
		var voxel_breach := str(action.get("source", "")) == "voxel"
		if not voxel_breach and (str(action.get("source", "")) != "entity" or not workstations.defense_status(instance_id).get("ok", false)):
			_stall("NO_PERMITTED_BREACH")
			return
		var approach: Vector3i = action.get("from", start)
		var route := planner.find_route(navigation_snapshot, start, approach, capability)
		if not route.get("ok", false):
			_stall("NO_APPROACH_ROUTE")
			return
		active_target_type = "voxel" if voxel_breach else "structure"
		active_target_id = instance_id
		active_target_cell = action.get("cell", Vector3i.ZERO)
		state = ROUTING
		raider.set_route(route.get("path", []))
		_emit_state()
		return
	_stall("NO_PERMITTED_ROUTE")


## No permitted route right now (walled in, or blocked by something the
## raider cannot breach): the drill keeps running and the raider re-plans
## every STALL_RETRY_SECONDS — the world changes when the player builds,
## machines burn or barricades fall. The enemy never gives up.
func _stall(reason: String) -> void:
	last_route_reason = reason
	if is_instance_valid(raider):
		raider.active = false
	if not _stall_retry_pending:
		_stall_retry_pending = true
		get_tree().create_timer(STALL_RETRY_SECONDS).timeout.connect(_retry_after_stall)
	_emit_state()


func _retry_after_stall() -> void:
	_stall_retry_pending = false
	if is_active() and core_integrity > 0 and not (far_mode and last_route_reason == "MARCHING"):
		_queue_replan()


func _on_raider_route_finished() -> void:
	if not is_instance_valid(raider):
		return
	if far_mode and last_route_reason == "MARCHING":
		# The march ended: inside the local area the voxel planner takes over,
		# otherwise (budget-limited partial path) keep marching.
		if _within_local_area(raider):
			last_route_reason = ""
			_capture_navigation()
			_plan_from_raider()
		else:
			_remarch(raider)
		return
	attack_timer = 0.3
	if active_target_type == "core":
		state = ATTACKING_CORE
		feedback.emit("Raider reached the strategic core because an open route remained.")
	elif active_target_type == "structure" and workstations.defense_status(active_target_id).get("ok", false):
		state = ATTACKING_STRUCTURE
		feedback.emit("No open route remains. Raider is breaching one permitted wooden barricade.")
	elif active_target_type == "voxel":
		state = ATTACKING_STRUCTURE
		feedback.emit("No way through. Raider is breaking down your wall.")
	else:
		_queue_replan()
	_emit_state()


func _attack_structure() -> void:
	if is_instance_valid(raider):
		raider.play_attack()
	if active_target_type == "voxel":
		if _hit_voxel(active_target_cell, maxi(1, raider_damage / 3)):
			feedback.emit("Your wall was breached. The raider is replanning toward the core.")
			_queue_replan()
		_emit_state()
		return
	var result := workstations.try_damage(active_target_id, raider_damage)
	if not result.get("ok", false):
		_queue_replan()
		return
	var details: Dictionary = result.get("details", {})
	if result.get("reason") == "DESTROYED":
		feedback.emit("Wooden barricade breached. The raider is replanning toward the core.")
		_queue_replan()
	else:
		feedback.emit("Raider hit %s for %d. Integrity: %d/%d." % [registry.display_name(str(details.get("entity_id", "wood_barricade"))), raider_damage, int(details.get("integrity", 0)), int(details.get("max_integrity", 0))])
	_emit_state()


func _attack_core() -> void:
	if core_integrity <= 0:
		return
	if is_instance_valid(raider):
		raider.play_attack()
	_damage_core(raider_damage)
	feedback.emit("Raider hit your core for %d. Core integrity: %d/%d." % [raider_damage, core_integrity, core_max_integrity])
	if core_integrity <= 0:
		state = FAILED
		_halt_all_raiders()
		feedback.emit("Your Core of Power was destroyed." if _uses_placed_core() else "Core-defense prototype failed: the strategic core was destroyed.")
	_emit_state()


## Raiders breach wood at full damage and, when no other way exists, chew
## through player-built stone slowly (owner 2026-09-19: "if no way exists,
## break it down"). Brutes hit stone at full strength.
func _basic_raider_capability() -> Dictionary:
	return {"max_step_up": 1, "max_drop_down": 1, "damage_per_hit": {"breachable_wood": raider_damage, "fortification": maxi(1, raider_damage / 3)}}


## Damage taken by a breached voxel accumulates here until it breaks:
## cell -> damage so far (voxels carry no integrity of their own).
var _voxel_damage: Dictionary = {}


## Hits a voxel obstruction (castle stone etc.): the cell breaks once its
## navigation integrity is spent. Returns true when it broke.
func _hit_voxel(cell: Vector3i, damage: int) -> bool:
	var data := _query_navigation_cell(cell)
	if not bool(data.get("solid", false)) or bool(data.get("protected", false)) or str(data.get("source", "")) != "voxel":
		return true
	var total := int(_voxel_damage.get(cell, 0)) + damage
	if total >= int(data.get("integrity", 60)):
		_voxel_damage.erase(cell)
		world.set_cell(cell, 0)
		return true
	_voxel_damage[cell] = total
	return false


func _capture_navigation() -> void:
	navigation_snapshot = NavigationSnapshot.new()
	var half_width := 5 if spawn_distance <= SPAWN_DISTANCE else 7
	var depth := 2 if spawn_distance <= SPAWN_DISTANCE else 8
	var height := 5 if spawn_distance <= SPAWN_DISTANCE else 26
	var region := AABB(Vector3(arena_center + Vector3i(-half_width, -depth, -spawn_distance - 6)), Vector3(half_width * 2 + 1, height, spawn_distance + 13))
	if far_mode:
		# Raiders arrive from any bearing: a square around the arena.
		region = AABB(Vector3(arena_center + Vector3i(-LOCAL_RADIUS, -8, -LOCAL_RADIUS)), Vector3(LOCAL_RADIUS * 2 + 1, 24, LOCAL_RADIUS * 2 + 1))
	var result := navigation_snapshot.capture(region, _query_navigation_cell, world.revision + navigation_revision)
	_capture_reason = str(result.get("reason", "OK"))
	if not result.get("ok", false):
		navigation_snapshot = null


func _query_navigation_cell(cell: Vector3i) -> Dictionary:
	if cell == _core_cell() and not _uses_placed_core():
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
	if material_id == "water":
		# Raiders do not wade: water is an impassable, unbreakable cell.
		return {"state": "LOADED", "solid": true, "voxel_id": voxel_id, "material_id": material_id, "source": "voxel", "source_id": material_id, "tags": [], "integrity": 999, "protected": true}
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
	for entry in extra_raiders:
		if int(entry.health) > 0 and str(entry.get("phase", "routing")) not in ["attacking_core", "marching", "chasing"]:
			_plan_extra(entry)


func _on_world_cell_changed(cell: Vector3i, _previous: int, _next: int, _revision: int) -> void:
	if _refresh_navigation([cell]) and is_active():
		_queue_replan()


func _find_available_arena(distance: int = SPAWN_DISTANCE) -> Dictionary:
	var placed := _placed_core_id()
	if not placed.is_empty():
		# The arena is laid out so the legacy core offset lands on the core's
		# centre column: arena_center + (0, 0, 5) == anchor + (1, 0, 1).
		var anchor: Vector3i = workstations.stations[placed].get("anchor", Vector3i.ZERO)
		return {"ok": true, "reason": "OK", "center": anchor + Vector3i(1, 0, 1) - Vector3i(0, 0, 5), "core_station_id": placed}
	for candidate: Vector3i in ARENA_CANDIDATES:
		if _arena_is_available(candidate, distance):
			return {"ok": true, "reason": "OK", "center": candidate}
	return {"ok": false, "reason": "CORE_ARENA_BLOCKED"}


func _arena_is_available(center: Vector3i, distance: int = SPAWN_DISTANCE) -> bool:
	if not _placed_core_id().is_empty():
		return true
	if distance > SPAWN_DISTANCE and _surface_cell(center + Vector3i(0, 0, -distance)) == Vector3i.MAX:
		return false
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
	if core_integrity <= 0 or _uses_placed_core():
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
	var ratio := float(core_integrity) / float(core_max_integrity)
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
	raider.stuck.connect(_on_raider_stuck)


func _clear_fixture() -> void:
	for value in [_core_root, raider]:
		if is_instance_valid(value):
			value.queue_free()
	for entry in extra_raiders:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	extra_raiders.clear()
	_primary_chase = {}
	_core_root = null
	_core_material = null
	raider = null
	navigation_snapshot = null
	_replan_queued = false


func _start_position() -> Vector3:
	return Vector3(_start_cell()) + Vector3(0.5, 0.9, 0.5)


## The spawn cell sits on the terrain surface of the spawn column: far spawn
## lines cross natural ground outside the flat clearing.
func _start_cell() -> Vector3i:
	var column := arena_center + Vector3i(0, 0, -spawn_distance)
	if spawn_distance <= SPAWN_DISTANCE:
		return column
	var surface := _surface_cell(column)
	return surface if surface != Vector3i.MAX else column


## A restored body must stand on the ground of its column, never inside it
## (terrain under a saved position can differ once the world reloads).
func _settled_position(saved_position: Vector3) -> Vector3:
	var column := Vector3i(floori(saved_position.x), floori(saved_position.y - 0.5), floori(saved_position.z))
	var surface := _surface_cell(column)
	if surface == Vector3i.MAX:
		var generator := _terrain_generator()
		if generator != null:
			return Vector3(float(column.x) + 0.5, float(generator.surface_height(column.x, column.z)) + 1.9, float(column.z) + 0.5)
		return saved_position
	return Vector3(surface) + Vector3(0.5, 0.9, 0.5)


## The ground cell of a column: scanning upward from 10 below the arena
## level, the first air cell (with a clear head cell) above a solid cell.
## Scanning upward finds the ground under a tree canopy rather than its top.
## Vector3i.MAX when the column is unloaded or has no such cell.
func _surface_cell(column: Vector3i) -> Vector3i:
	for y in range(column.y - 10, column.y + 12):
		var cell := Vector3i(column.x, y, column.z)
		var floor_query := world.query_cell(cell + Vector3i.DOWN)
		if str(floor_query.get("state", "UNLOADED")) != "LOADED":
			return Vector3i.MAX
		if int(floor_query.get("voxel_id", 0)) == 0:
			continue
		var feet := world.query_cell(cell)
		var head := world.query_cell(cell + Vector3i.UP)
		if str(feet.get("state", "")) != "LOADED" or str(head.get("state", "")) != "LOADED":
			return Vector3i.MAX
		if int(feet.get("voxel_id", 0)) == 0 and int(head.get("voxel_id", 0)) == 0:
			return cell
	return Vector3i.MAX


## The Core of Power station the drill defends, or "" (prototype core).
func _placed_core_id() -> String:
	if workstations == null:
		return ""
	for instance_id: String in workstations.stations.keys():
		if str(workstations.stations[instance_id].get("entity_id", "")) == CORE_ENTITY:
			return instance_id
	return ""


func _uses_placed_core() -> bool:
	return not core_station_id.is_empty() and workstations != null and workstations.stations.has(core_station_id)


## Reads the placed core's integrity into the drill (and its maximum).
func _sync_core_from_station() -> void:
	if not _uses_placed_core():
		return
	var status := workstations.defense_status(core_station_id)
	if status.get("ok", false):
		core_max_integrity = int(status.get("details", {}).get("max_integrity", core_max_integrity))
		core_integrity = int(status.get("details", {}).get("integrity", core_integrity))


## Damages the core: the placed station through the workstation service (so
## its visual and save record follow), else the prototype counter.
func _damage_core(amount: int) -> void:
	if _uses_placed_core():
		var result := workstations.try_damage(core_station_id, amount)
		if result.get("reason") == "DESTROYED":
			core_integrity = 0
		elif result.get("ok", false):
			core_integrity = int(result.get("details", {}).get("integrity", core_integrity))
		return
	core_integrity = maxi(0, core_integrity - amount)
	_update_core_presentation()


## Raiders walk to a free cell beside the core: with a placed 3x3 core the
## side nearest the raider, else the legacy approach cell.
func _core_approach_cell(from: Vector3i = Vector3i.MAX) -> Vector3i:
	if not _uses_placed_core():
		return arena_center + Vector3i(0, 0, 4)
	var centre := _core_cell()
	var candidates: Array[Vector3i] = [centre + Vector3i(0, 0, 2), centre + Vector3i(0, 0, -2), centre + Vector3i(2, 0, 0), centre + Vector3i(-2, 0, 0)]
	var best := candidates[0]
	var best_distance := INF
	for candidate in candidates:
		var feet := world.query_cell(candidate)
		var head := world.query_cell(candidate + Vector3i.UP)
		var open := str(feet.get("state", "")) == "LOADED" and int(feet.get("voxel_id", 0)) == 0 and str(head.get("state", "")) == "LOADED" and int(head.get("voxel_id", 0)) == 0 and workstations.station_at_cell(candidate).is_empty()
		if not open:
			continue
		var distance := INF if from == Vector3i.MAX else float((candidate - from).length_squared())
		if distance < best_distance or best_distance == INF:
			best_distance = distance
			best = candidate
	return best


func _core_cell() -> Vector3i:
	return arena_center + Vector3i(0, 0, 5)


func _emit_state() -> void:
	state_changed.emit(hud_text())


func _fail(reason: String) -> void:
	state = FAILED
	last_route_reason = reason
	_halt_all_raiders()
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
