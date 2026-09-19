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
## P4D waves: the spawn line for the current drill and the extra raiders
## beyond the primary one. Each entry: {node, health, max_health, kind,
## damage, target_type, target_id, target_cell, attack_timer, route_reason}.
var spawn_distance := SPAWN_DISTANCE
var wave_size := 1
var extra_raiders: Array[Dictionary] = []
var _core_root: StaticBody3D
var _core_material: StandardMaterial3D
var _pending_restore: Dictionary = {}
var _replan_queued := false
var _pending_brutes := 0
var _capture_reason := "OK"
var _stall_retry_pending := false
const STALL_RETRY_SECONDS := 2.0
const BRUTE_SMASH_RADIUS := 2.6
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
	if not _arena_is_available(arena_center):
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
	_build_core_visual()
	if state in [ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE] and raider_health > 0 and core_integrity > 0:
		var saved_position := _vector3_from_array(saved.get("raider_position", []), _start_position())
		_spawn_raider(_settled_position(saved_position))
		_plan_from_raider()
	if state in [ROUTING, ATTACKING_STRUCTURE, ATTACKING_CORE] and core_integrity > 0:
		var saved_extras: Variant = saved.get("extra_raiders", [])
		if saved_extras is Array:
			for value in saved_extras:
				if not value is Dictionary or int(value.get("health", 0)) <= 0:
					continue
				var entry := _spawn_extra_raider(_settled_position(_vector3_from_array(value.get("position", []), _start_position())), str(value.get("kind", BasicRaider.KIND_RAIDER)))
				entry.health = clampi(int(value.get("health", entry.max_health)), 1, int(entry.max_health))
				_plan_extra(entry)
	_emit_state()
	return {"ok": true, "reason": "OK"}


## Starts the drill. Options (P4D): "raiders" (wave size, default 1),
## "brutes" (how many of them are brutes, default 0) and "spawn_distance"
## (cells from the arena centre to the field-side spawn line, 8..28).
func start_prototype(options: Dictionary = {}) -> Dictionary:
	if is_active():
		return {"ok": false, "reason": "DEFENSE_ALREADY_ACTIVE"}
	var requested_distance := clampi(int(options.get("spawn_distance", SPAWN_DISTANCE)), SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
	var found := _find_available_arena(requested_distance)
	if not found.get("ok", false):
		return found
	_clear_fixture()
	arena_center = found.get("center", Vector3i.ZERO)
	spawn_distance = requested_distance
	wave_size = maxi(1, int(options.get("raiders", 1)))
	_pending_brutes = clampi(int(options.get("brutes", 0)), 0, wave_size)
	state = WARNING
	warning_remaining = warning_seconds
	core_integrity = core_max_integrity
	raider_health = raider_max_health
	attack_timer = raider_attack_interval
	active_target_type = ""
	active_target_id = ""
	active_target_cell = Vector3i.ZERO
	last_route_reason = ""
	navigation_revision = 0
	exact_invalidations = 0
	_build_core_visual()
	if wave_size > 1:
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
		_advance_extras(delta)


## Extra raiders (P4D) run their own attack timers against whatever they
## reached; the drill state machine still follows the primary raider.
func _advance_extras(delta: float) -> void:
	for entry in extra_raiders:
		if int(entry.health) <= 0 or not is_instance_valid(entry.node):
			continue
		var phase := str(entry.get("phase", "routing"))
		if phase == "routing":
			if str(entry.kind) == BasicRaider.KIND_BRUTE:
				_brute_smashes_nearby(entry, delta)
			continue
		entry.attack_timer = float(entry.attack_timer) - delta
		if float(entry.attack_timer) > 0.0:
			continue
		if phase == "stalled":
			_plan_extra(entry)
			continue
		entry.attack_timer = float(entry.attack_timer) + raider_attack_interval
		if phase == "attacking_core":
			_extra_attacks_core(entry)
		elif phase == "attacking_structure":
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


func _extra_attacks_core(entry: Dictionary) -> void:
	if core_integrity <= 0:
		return
	core_integrity = maxi(0, core_integrity - int(entry.damage))
	_update_core_presentation()
	feedback.emit("%s hit the strategic core for %d. Core integrity: %d/%d." % [str(entry.kind).capitalize(), int(entry.damage), core_integrity, core_max_integrity])
	if core_integrity <= 0:
		state = FAILED
		_halt_all_raiders()
		feedback.emit("Core-defense prototype failed: the strategic core was destroyed.")
	_emit_state()


func _halt_all_raiders() -> void:
	if is_instance_valid(raider):
		raider.active = false
	for entry in extra_raiders:
		if is_instance_valid(entry.node):
			entry.node.active = false


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
	if not is_active() or not is_instance_valid(raider) or raider_health <= 0:
		return {"ok": false, "reason": "NO_RAIDER"}
	var before := raider_health
	raider_health = maxi(0, raider_health - amount)
	if raider_health <= 0:
		raider.die()
		if living_raider_count() == 0:
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
		if int(entry.health) <= 0 or not is_active():
			return {"ok": false, "reason": "NO_RAIDER"}
		var before := int(entry.health)
		entry.health = maxi(0, int(entry.health) - amount)
		if int(entry.health) <= 0:
			entry.node.die()
			if living_raider_count() == 0:
				state = WON
				feedback.emit("Defense won: %s defeated the last raider." % source.replace("_", " ").capitalize())
			else:
				feedback.emit("%s defeated a %s. %d left." % [source.replace("_", " ").capitalize(), str(entry.kind), living_raider_count()])
		_emit_state()
		return {"ok": true, "reason": "RAIDER_DEFEATED" if int(entry.health) <= 0 else "RAIDER_DAMAGED", "handled": true, "changes": {"health_before": before, "health": int(entry.health), "damage": amount, "source": source}}
	return {"ok": false, "reason": "NO_RAIDER"}


## Splash: damages every living raider within `radius` (horizontal) of
## `point`. Returns the number of raiders hit.
func damage_raiders_within(point: Vector3, radius: float, amount: int, source: String = "siege") -> int:
	var hits := 0
	for node in raider_nodes():
		var position := node.global_position + Vector3.UP * 0.65
		if Vector2(position.x - point.x, position.z - point.z).length() <= radius and absf(position.y - point.y) <= 3.0:
			if try_damage_raider_node(node, amount, source).get("ok", false):
				hits += 1
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
	if is_active() and is_instance_valid(raider) and raider_health > 0 and not raider.dead:
		nodes.append(raider)
	for entry in extra_raiders:
		if int(entry.health) > 0 and is_instance_valid(entry.node) and not entry.node.dead and is_active():
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
## ("any", "raider" or "brute"), or Vector3.INF when none.
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
			return "CORE UNDER ATTACK · raider %d/%d · core %d/%d · no open defense remains" % [raider_health, raider_max_health, core_integrity, core_max_integrity]
		WON:
			return "DEFENSE WON · core %d/%d · raider defeated" % [core_integrity, core_max_integrity]
		FAILED:
			return "CORE DEFENSE FAILED · prototype core destroyed"
	return "CORE DEFENSE PROTOTYPE"


func _begin_attack() -> void:
	state = ROUTING
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
	for index in range(1, wave_size):
		var kind := BasicRaider.KIND_BRUTE if brutes_left > 0 else BasicRaider.KIND_RAIDER
		if brutes_left > 0:
			brutes_left -= 1
		var offset := _wave_offset(index)
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


## Spread the wave across the spawn line: alternating left/right, one row
## back every four.
func _wave_offset(index: int) -> Vector3:
	var lateral := ((index + 1) / 2) * (1 if index % 2 == 1 else -1)
	var back := -(index / 4)
	return Vector3(float(clampi(lateral, -3, 3)), 0.0, float(back))


func _spawn_extra_raider(spawn_position: Vector3, kind: String) -> Dictionary:
	var node := BasicRaider.new()
	node.configure(kind)
	add_child(node)
	node.global_position = spawn_position
	var brute := kind == BasicRaider.KIND_BRUTE
	var entry := {
		"node": node,
		"kind": kind,
		"health": brute_max_health if brute else raider_max_health,
		"max_health": brute_max_health if brute else raider_max_health,
		"damage": brute_damage if brute else raider_damage,
		"target_type": "",
		"target_id": "",
		"target_cell": Vector3i.ZERO,
		"attack_timer": 0.3,
		"route_reason": "",
		"phase": "routing",
	}
	extra_raiders.append(entry)
	node.route_finished.connect(_on_extra_route_finished.bind(node))
	return entry


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
	capability["damage_per_hit"] = {"breachable_wood": int(entry.damage)}
	var planner := LocalGridPathfinder.new()
	var plan := planner.plan_next(navigation_snapshot, start, _core_approach_cell(), capability)
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
		if str(action.get("source", "")) != "entity" or not workstations.defense_status(instance_id).get("ok", false):
			_stall_extra(entry)
			return
		var route := planner.find_route(navigation_snapshot, start, action.get("from", start), capability)
		if not route.get("ok", false):
			_stall_extra(entry)
			return
		entry.target_type = "structure"
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
		entry.attack_timer = 0.3
		if str(entry.target_type) == "core":
			entry.phase = "attacking_core"
		elif str(entry.target_type) == "structure" and workstations.defense_status(str(entry.target_id)).get("ok", false):
			entry.phase = "attacking_structure"
		else:
			_plan_extra(entry)
		return


func _plan_from_raider() -> void:
	if not is_instance_valid(raider) or core_integrity <= 0:
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
			_stall("NO_PERMITTED_BREACH")
			return
		var approach: Vector3i = action.get("from", start)
		var route := planner.find_route(navigation_snapshot, start, approach, capability)
		if not route.get("ok", false):
			_stall("NO_APPROACH_ROUTE")
			return
		active_target_type = "structure"
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
	if is_active() and core_integrity > 0:
		_queue_replan()


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
	core_integrity = maxi(0, core_integrity - raider_damage)
	_update_core_presentation()
	feedback.emit("Raider hit the strategic core for %d. Core integrity: %d/%d." % [raider_damage, core_integrity, core_max_integrity])
	if core_integrity <= 0:
		state = FAILED
		_halt_all_raiders()
		feedback.emit("Core-defense prototype failed: the strategic core was destroyed.")
	_emit_state()


func _basic_raider_capability() -> Dictionary:
	return {"max_step_up": 1, "max_drop_down": 1, "damage_per_hit": {"breachable_wood": raider_damage}}


func _capture_navigation() -> void:
	navigation_snapshot = NavigationSnapshot.new()
	var half_width := 5 if spawn_distance <= SPAWN_DISTANCE else 7
	var depth := 2 if spawn_distance <= SPAWN_DISTANCE else 8
	var height := 5 if spawn_distance <= SPAWN_DISTANCE else 18
	var region := AABB(Vector3(arena_center + Vector3i(-half_width, -depth, -spawn_distance - 2)), Vector3(half_width * 2 + 1, height, spawn_distance + 9))
	var result := navigation_snapshot.capture(region, _query_navigation_cell, world.revision + navigation_revision)
	_capture_reason = str(result.get("reason", "OK"))
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
	for entry in extra_raiders:
		if int(entry.health) > 0 and str(entry.get("phase", "routing")) != "attacking_core":
			_plan_extra(entry)


func _on_world_cell_changed(cell: Vector3i, _previous: int, _next: int, _revision: int) -> void:
	if _refresh_navigation([cell]) and is_active():
		_queue_replan()


func _find_available_arena(distance: int = SPAWN_DISTANCE) -> Dictionary:
	for candidate: Vector3i in ARENA_CANDIDATES:
		if _arena_is_available(candidate, distance):
			return {"ok": true, "reason": "OK", "center": candidate}
	return {"ok": false, "reason": "CORE_ARENA_BLOCKED"}


func _arena_is_available(center: Vector3i, distance: int = SPAWN_DISTANCE) -> bool:
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


func _clear_fixture() -> void:
	for value in [_core_root, raider]:
		if is_instance_valid(value):
			value.queue_free()
	for entry in extra_raiders:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	extra_raiders.clear()
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


func _core_approach_cell() -> Vector3i:
	return arena_center + Vector3i(0, 0, 4)


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
