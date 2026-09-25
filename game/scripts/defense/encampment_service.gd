class_name EncampmentService
extends Node3D

## Minion encampments — the game's first ambient pressure (docs/ENCAMPMENTS.md).
##
## Owner (2026-09-25): "The evil presence has minion encampments spreading
## through the land. They roam radius zones. If they discover something, they
## disrupt or destroy, depending on what they encounter. For example, a mine
## rail — destroy a track and leave, it stops the rail. Or a tower — attack it
## until destroyed, then continue patrols. Encampments sit at a fire at night,
## but in the day patrol a radius zone."
##
## Nothing here is a second AI. A camp is a **campfire station** (the existing
## entity) plus a garrison of ordinary `BasicRaider` bodies; they walk with the
## body's own physics over routes from `LocalGridPathfinder` across a
## `NavigationSnapshot` read through `CoreDefenseService.world_navigation_cell`,
## so patrols obey exactly the breach rules a wave does. Damage to what they
## find goes through `WorkstationService.try_damage`. Day and night come from
## `DayNightClock`. The garrison is registered with `CoreDefenseService` through
## its `foreign_damage` / `foreign_nodes` seam, so the player's sword, traps and
## siege splash kill them through the one damage API — but they never count
## towards a drill's WON.
##
## Every difficulty knob (patrol radius, sight radius, garrison, timings, the
## sabotage table) is the `encampments` block of `contracts/content.json`.

signal feedback(message: String)
## A camp changed state (spawned, patrolling, camping, cleared). Diagnostics.
signal camp_changed(camp_id: String, state: String)

const SNAPSHOT_VERSION := 1
## Chebyshev distance from the fire a camper stands at.
const FIRE_RING := 2
## A re-plan reuses a capture younger than this many seconds.
const CAPTURE_SECONDS := 2.0
## Vertical half-height of the navigation capture around a camp.
const CAPTURE_DEPTH := 8
const CAPTURE_HEIGHT := 22
## A patrol leg or a walk to a target is abandoned after this long without
## arriving, so nothing can hold a minion away from its camp for ever.
const LEG_LIMIT_SECONDS := 40.0
## How near a target cell a body must stand before it starts hitting it.
const STRIKE_REACH := 2.6
## How often the service looks for camp sites whose ground has streamed in.
const MATERIALISE_SECONDS := 2.0
## Verbs the sabotage table may name.
const VERB_BREAK_ONE := "break_one"
const VERB_DESTROY := "destroy"
const VERB_IGNORE := "ignore"
const COMPASS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
## The entity a camp's fire is built from: the existing campfire, which already
## lights and flickers. Breaking it is breaking the camp.
const FIRE_ENTITY := "campfire"

var world: WorldAdapter
var registry: ContentRegistry
var workstations: WorkstationService
var core_defense: CoreDefenseService
var clock: DayNightClock
var player: Node3D

## The `encampments` block of content.json, already defaulted.
var rules: Dictionary = {}
## Placed camp records, keyed by camp id.
var camps: Dictionary = {}
## World-generated ambient pressure runs only in a normal game: Development and
## CoasterCraft carry authored camps only, and those stay inert until started.
var ambient := true
var enabled := true
## Set by `GameSession` once the world is ready; until then nothing is placed.
var world_ready := false
## Counters the gates read.
var sabotage_events := 0
var camps_cleared := 0

var _sites_resolved := false
var _materialise_timer := 0.0
var _pending_restore: Dictionary = {}
var _planner := LocalGridPathfinder.new()
var _rng := RandomNumberGenerator.new()
var _next_camp := 1


func initialize(world_adapter: WorldAdapter, content_registry: ContentRegistry, station_service: WorkstationService, defense: CoreDefenseService, day_clock: DayNightClock, saved: Dictionary = {}) -> void:
	world = world_adapter
	registry = content_registry
	workstations = station_service
	core_defense = defense
	clock = day_clock
	rules = _resolved_rules()
	enabled = bool(rules.get("enabled", true))
	_rng.seed = 0x5EED1A3
	if saved is Dictionary and not (saved as Dictionary).is_empty():
		restore(saved)
	if core_defense != null:
		core_defense.foreign_damage = damage_body
		core_defense.foreign_nodes = garrison_nodes


## Content defaults live here so a missing block never crashes a mode.
func _resolved_rules() -> Dictionary:
	var sheet: Dictionary = registry.encampments.duplicate(true) if registry != null else {}
	var defaults := {
		"enabled": true, "patrol_radius": 14, "sight_radius": 10, "notice_range": 80.0,
		"patrol_leg_seconds": 18.0, "patrol_interval_seconds": 6.0,
		"sabotage_cooldown_seconds": 45.0, "attack_interval_seconds": 1.4,
	}
	for key: String in defaults.keys():
		if not sheet.has(key):
			sheet[key] = defaults[key]
	if not sheet.has("garrison"):
		sheet["garrison"] = [{"kind": BasicRaider.KIND_RAIDER, "count": 2}, {"kind": BasicRaider.KIND_BRUTE, "count": 1}]
	if not sheet.has("sabotage"):
		sheet["sabotage"] = {}
	if not sheet.has("world"):
		sheet["world"] = {}
	return sheet


## The verb the table names for an entity kind. Anything the table does not
## name is ignored, which is the rule the card asks for.
func sabotage_verb(entity_id: String) -> String:
	var table: Dictionary = rules.get("sabotage", {})
	var verb := str(table.get(entity_id, VERB_IGNORE))
	if verb not in [VERB_BREAK_ONE, VERB_DESTROY, VERB_IGNORE]:
		return VERB_IGNORE
	return verb


func patrol_radius() -> int:
	return maxi(3, int(rules.get("patrol_radius", 14)))


func sight_radius() -> float:
	return maxf(1.0, float(rules.get("sight_radius", 10)))


func clear_for_other_mode() -> void:
	for camp_id: String in camps.keys():
		_despawn(camps[camp_id])
	camps.clear()
	_sites_resolved = false
	_pending_restore = {}
	sabotage_events = 0
	camps_cleared = 0


## ------------------------------------------------------------- world sites

## The camp sites a seed produces, in the distance band the world contract
## names. Deterministic: the same seed always yields the same camps, exactly
## like the enemy base (docs/P4E_WORLD_AND_ENEMY_BASE.md).
func world_sites() -> Array[Vector3i]:
	var sites: Array[Vector3i] = []
	var generator := _generator()
	if generator == null:
		return sites
	# The content block carries the defaults; `terrain.encampments` in
	# world.json overrides them, because where camps stand is world generation.
	var placement: Dictionary = (rules.get("world", {}) as Dictionary).duplicate(true)
	var configured: Variant = generator.settings.get("encampments", {})
	if configured is Dictionary:
		for key: String in (configured as Dictionary).keys():
			placement[key] = (configured as Dictionary)[key]
	var count := maxi(0, int(placement.get("count", 3)))
	var minimum := float(placement.get("min_distance", 70))
	var maximum := float(placement.get("max_distance", 140))
	var separation := float(placement.get("min_separation", 48))
	var margin := int(placement.get("margin", 24))
	var home_clear := float(placement.get("home_clear_radius", 40))
	var home := Vector2(generator.enemy_base)
	var settings: Dictionary = generator.settings
	var centre: Array = settings.get("safe_clearing_center", [0, 40])
	var home_centre := Vector2(float(centre[0]), float(centre[1]))
	var rng := RandomNumberGenerator.new()
	rng.seed = generator.world_seed ^ 0x51ED270B
	var bounds_min: Vector3i = generator.bounds_min
	var bounds_size: Vector3i = generator.bounds_size
	var attempts := 0
	while sites.size() < count and attempts < 400:
		attempts += 1
		var angle := rng.randf() * TAU
		var distance := lerpf(minimum, maximum, rng.randf())
		var candidate := Vector2i(
			clampi(roundi(home_centre.x + cos(angle) * distance), bounds_min.x + margin, bounds_min.x + bounds_size.x - margin - 1),
			clampi(roundi(home_centre.y + sin(angle) * distance), bounds_min.z + margin, bounds_min.z + bounds_size.z - margin - 1))
		if Vector2(candidate).distance_to(home_centre) < home_clear:
			continue
		if Vector2(candidate).distance_to(home) < separation:
			continue
		var clashes := false
		for placed in sites:
			if Vector2(float(placed.x), float(placed.z)).distance_to(Vector2(candidate)) < separation:
				clashes = true
				break
		if clashes:
			continue
		if generator.is_water_column(candidate.x, candidate.y):
			continue
		sites.append(Vector3i(candidate.x, generator.surface_height(candidate.x, candidate.y) + 1, candidate.y))
	return sites


func _generator() -> P1TerrainGenerator:
	if world == null or world.terrain == null:
		return null
	var generator: Variant = world.terrain.generator
	return generator if generator is P1TerrainGenerator else null


## ------------------------------------------------------------- camp records

## Registers an authored camp (the Development Expo's Frontier exhibit). It is
## inert — no fire lit, no garrison — until `start_camp` is called, because
## Development mode carries no ambient pressure (T211).
func register_camp(camp_id: String, cell: Vector3i, options: Dictionary = {}) -> Dictionary:
	if camps.has(camp_id):
		return {"ok": false, "reason": "CAMP_EXISTS", "camp_id": camp_id}
	var record := _new_camp(camp_id, cell, true)
	record["radius"] = maxi(3, int(options.get("patrol_radius", patrol_radius())))
	record["sight"] = maxf(1.0, float(options.get("sight_radius", sight_radius())))
	if options.has("garrison"):
		record["garrison_plan"] = options["garrison"]
	camps[camp_id] = record
	return {"ok": true, "camp_id": camp_id, "cell": cell}


func _new_camp(camp_id: String, cell: Vector3i, scripted: bool) -> Dictionary:
	return {
		"id": camp_id,
		"cell": cell,
		"radius": patrol_radius(),
		"sight": sight_radius(),
		"scripted": scripted,
		"started": not scripted,
		"cleared": false,
		"spawned": false,
		"fire_id": "",
		"state": "camping",
		"members": [],
		"cooldowns": {},
		"snapshot": [],
		"capture": null,
		"capture_age": 0.0,
		"garrison_plan": rules.get("garrison", []),
	}


func camp(camp_id: String) -> Dictionary:
	return camps.get(camp_id, {})


func camp_ids() -> Array[String]:
	var ids: Array[String] = []
	for camp_id: String in camps.keys():
		ids.append(camp_id)
	ids.sort()
	return ids


func living_camps() -> int:
	var total := 0
	for camp_id: String in camps.keys():
		if not bool(camps[camp_id].get("cleared", false)):
			total += 1
	return total


## Lights an authored camp's fire and musters its garrison. This is the only
## thing that starts a scripted camp — the Expo pedestal's START.
func start_camp(camp_id: String) -> Dictionary:
	if not camps.has(camp_id):
		return {"ok": false, "reason": "NO_CAMP", "camp_id": camp_id}
	var record: Dictionary = camps[camp_id]
	if bool(record.get("cleared", false)):
		return {"ok": false, "reason": "CAMP_CLEARED", "camp_id": camp_id}
	record["started"] = true
	record["cooldowns"] = {}
	if not _materialise(record):
		return {"ok": false, "reason": "CAMP_GROUND_NOT_READY", "camp_id": camp_id}
	_retask(record, true)
	return {"ok": true, "camp_id": camp_id, "members": (record["members"] as Array).size()}


## Puts an authored camp back to the state its fixture opens in: garrison gone,
## fire gone, cooldowns cleared, inert again.
func stop_camp(camp_id: String) -> Dictionary:
	if not camps.has(camp_id):
		return {"ok": false, "reason": "NO_CAMP", "camp_id": camp_id}
	var record: Dictionary = camps[camp_id]
	_despawn(record)
	record["started"] = false
	record["cleared"] = false
	record["cooldowns"] = {}
	record["state"] = "camping"
	record["capture"] = null
	camp_changed.emit(camp_id, "inert")
	return {"ok": true, "camp_id": camp_id}


## Every camp whose boundary box contains `cell` is stopped. The Expo's reset
## groups call this so RESET FRONTIER makes the exhibit inert again.
func stop_camps_within(box_origin: Vector3i, box_size: Vector3i) -> int:
	var stopped := 0
	for camp_id: String in camps.keys():
		var cell: Vector3i = camps[camp_id].get("cell", Vector3i.ZERO)
		if cell.x >= box_origin.x and cell.x < box_origin.x + box_size.x \
			and cell.z >= box_origin.z and cell.z < box_origin.z + box_size.z:
			stop_camp(camp_id)
			stopped += 1
	return stopped


## ------------------------------------------------------------------- ticking

func advance(delta: float, paused: bool = false) -> void:
	if paused or not enabled or delta <= 0.0 or world == null or workstations == null:
		return
	_resolve_world_sites()
	_materialise_timer -= delta
	if _materialise_timer <= 0.0:
		_materialise_timer = MATERIALISE_SECONDS
		for camp_id: String in camps.keys():
			var record: Dictionary = camps[camp_id]
			if bool(record.get("started", false)) and not bool(record.get("cleared", false)) and not bool(record.get("spawned", false)):
				_materialise(record)
	var daylight := is_day()
	for camp_id: String in camps.keys():
		_advance_camp(camps[camp_id], delta, daylight)


func is_day() -> bool:
	if clock == null:
		return true
	var minutes := clock.current_minutes()
	return minutes >= DayNightClock.SUNRISE_MINUTES and minutes < DayNightClock.SUNSET_MINUTES


func _resolve_world_sites() -> void:
	if _sites_resolved or not world_ready:
		return
	_sites_resolved = true
	var restored: Array = _pending_restore.get("camps", [])
	if not restored.is_empty():
		_apply_restore(restored)
		return
	if not ambient:
		return
	var index := 0
	for site in world_sites():
		index += 1
		var camp_id := "camp_%04d" % index
		if camps.has(camp_id):
			continue
		camps[camp_id] = _new_camp(camp_id, site, false)
	_next_camp = index + 1


func _apply_restore(rows: Array) -> void:
	for value in rows:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var camp_id := str(row.get("id", ""))
		if camp_id.is_empty():
			continue
		var cell := _vector3i_from(row.get("cell", []), Vector3i.ZERO)
		var record: Dictionary = camps.get(camp_id, _new_camp(camp_id, cell, bool(row.get("scripted", false))))
		record["cell"] = cell
		record["cleared"] = bool(row.get("cleared", false))
		record["started"] = bool(row.get("started", not bool(row.get("scripted", false))))
		record["fire_id"] = str(row.get("fire_id", ""))
		record["radius"] = maxi(3, int(row.get("radius", patrol_radius())))
		record["sight"] = maxf(1.0, float(row.get("sight", sight_radius())))
		record["state"] = str(row.get("state", "camping"))
		record["snapshot"] = row.get("garrison", [])
		record["spawned"] = false
		camps[camp_id] = record
	_pending_restore = {}


## ------------------------------------------------------------ materialising

## Lights the camp's fire and musters its garrison once the ground under it has
## streamed in — the pattern `GameSession._ensure_enemy_core` uses for the
## enemy core. Returns true when the camp is standing.
func _materialise(record: Dictionary) -> bool:
	if bool(record.get("spawned", false)) or bool(record.get("cleared", false)) or not bool(record.get("started", false)):
		return bool(record.get("spawned", false))
	var cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var anchor := cell - Vector3i(1, 0, 1)
	for x in range(3):
		for z in range(3):
			var probe := anchor + Vector3i(x, 0, z)
			if str(world.query_cell(probe).get("state", "")) != "LOADED" or str(world.query_cell(probe + Vector3i.DOWN).get("state", "")) != "LOADED":
				return false
	if str(record.get("fire_id", "")).is_empty() or not workstations.stations.has(str(record.get("fire_id", ""))):
		record["fire_id"] = _light_fire(anchor)
	if str(record.get("fire_id", "")).is_empty():
		return false
	var restored: Array = record.get("snapshot", [])
	record["members"] = []
	if restored.is_empty():
		for value in record.get("garrison_plan", []):
			if not value is Dictionary:
				continue
			var row: Dictionary = value
			var kind := str(row.get("kind", BasicRaider.KIND_RAIDER))
			for _index in range(maxi(0, int(row.get("count", 1)))):
				_spawn_member(record, kind, Vector3.INF, -1)
	else:
		for value in restored:
			if not value is Dictionary:
				continue
			var row: Dictionary = value
			var health := int(row.get("health", -1))
			if health == 0:
				continue
			_spawn_member(record, str(row.get("kind", BasicRaider.KIND_RAIDER)), _vector3_from(row.get("position", []), Vector3.INF), health)
		record["snapshot"] = []
	record["spawned"] = true
	_retask(record, is_day())
	camp_changed.emit(str(record.get("id", "")), str(record.get("state", "camping")))
	return true


## The fire is the existing campfire entity, placed through the ordinary
## station path with `_free` (authored placement, no item cost).
func _light_fire(anchor: Vector3i) -> String:
	if registry.entity(FIRE_ENTITY).is_empty():
		return ""
	var standing := workstations.station_at_cell(anchor)
	if not standing.is_empty():
		var record: Dictionary = workstations.station(standing)
		if str(record.get("entity_id", "")) == FIRE_ENTITY:
			return standing
		return ""
	for x in range(3):
		for z in range(3):
			var pad := anchor + Vector3i(x, 0, z)
			world.set_cell(pad + Vector3i.DOWN, WorldAdapter.BLOCK_NAMES.find("dirt"))
			for y in range(4):
				world.set_cell(pad + Vector3i(0, y, 0), 0)
	var placed := workstations.try_place(FIRE_ENTITY, anchor, world.query_cell, AABB(), 0, {"_free": true})
	if not placed.get("ok", false):
		return ""
	return str(placed.get("details", {}).get("station", {}).get("instance_id", ""))


func _spawn_member(record: Dictionary, kind: String, at: Vector3 = Vector3.INF, health: int = -1) -> Dictionary:
	var node := BasicRaider.new()
	node.configure(kind)
	add_child(node)
	var cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var seat := at
	if not seat.is_finite():
		var ring := (record["members"] as Array).size()
		var angle := float(ring) * TAU / 5.0
		seat = Vector3(cell) + Vector3(0.5 + cos(angle) * 2.0, 0.9, 0.5 + sin(angle) * 2.0)
	node.global_position = seat
	var max_health := CoreDefenseService.RAIDER_MAX_HEALTH
	var damage := CoreDefenseService.RAIDER_DAMAGE
	if kind == BasicRaider.KIND_BRUTE:
		max_health = CoreDefenseService.BRUTE_MAX_HEALTH
		damage = CoreDefenseService.BRUTE_DAMAGE
	elif kind == BasicRaider.KIND_TROLL:
		max_health = CoreDefenseService.TROLL_MAX_HEALTH
		damage = CoreDefenseService.TROLL_DAMAGE
	var entry := {
		"node": node,
		"kind": kind,
		"camp": str(record.get("id", "")),
		"health": max_health if health < 0 else clampi(health, 1, max_health),
		"max_health": max_health,
		"damage": damage,
		"phase": "camping",
		"target_id": "",
		"target_entity": "",
		"verb": VERB_IGNORE,
		"target_cell": Vector3i.ZERO,
		"attack_timer": 0.0,
		"leg_timer": 0.0,
		"scan_timer": 0.0,
	}
	var members: Array = record["members"]
	members.append(entry)
	node.route_finished.connect(_on_route_finished.bind(entry))
	node.stuck.connect(_on_body_stuck.bind(entry))
	return entry


func _despawn(record: Dictionary) -> void:
	for value in record.get("members", []):
		var entry: Dictionary = value
		var node: Variant = entry.get("node")
		if node is BasicRaider and is_instance_valid(node):
			(node as BasicRaider).queue_free()
	record["members"] = []
	record["spawned"] = false
	var fire_id := str(record.get("fire_id", ""))
	if not fire_id.is_empty() and workstations.stations.has(fire_id):
		workstations.try_damage(fire_id, 99999)
	record["fire_id"] = ""


## ----------------------------------------------------------------- one camp

func _advance_camp(record: Dictionary, delta: float, daylight: bool) -> void:
	if bool(record.get("cleared", false)) or not bool(record.get("spawned", false)):
		return
	var cooldowns: Dictionary = record.get("cooldowns", {})
	for key: String in cooldowns.keys():
		cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
	record["capture_age"] = float(record.get("capture_age", 0.0)) + delta
	var wanted := "patrolling" if daylight else "camping"
	if str(record.get("state", "")) != wanted:
		record["state"] = wanted
		_retask(record, daylight)
		camp_changed.emit(str(record.get("id", "")), wanted)
	var alive := 0
	for value in record.get("members", []):
		var entry: Dictionary = value
		if int(entry.get("health", 0)) <= 0:
			continue
		alive += 1
		_advance_member(record, entry, delta, daylight)
	var fire_id := str(record.get("fire_id", ""))
	var fire_standing := not fire_id.is_empty() and workstations.stations.has(fire_id)
	if alive == 0 and not fire_standing:
		record["cleared"] = true
		record["spawned"] = false
		record["members"] = []
		record["fire_id"] = ""
		camps_cleared += 1
		camp_changed.emit(str(record.get("id", "")), "cleared")
		feedback.emit("The encampment is cleared — its fire is out and nothing is left to patrol.")


## Every member is put back on the job the camp's state asks for.
func _retask(record: Dictionary, daylight: bool) -> void:
	record["state"] = "patrolling" if daylight else "camping"
	for value in record.get("members", []):
		var entry: Dictionary = value
		if int(entry.get("health", 0)) <= 0:
			continue
		entry["phase"] = "patrolling" if daylight else "camping"
		entry["leg_timer"] = 0.0
		entry["scan_timer"] = 0.0
		entry["target_id"] = ""
		var node: BasicRaider = entry.get("node")
		if is_instance_valid(node):
			node.set_route([])
			node.clear_goal()
			node.active = false


func _advance_member(record: Dictionary, entry: Dictionary, delta: float, daylight: bool) -> void:
	var node: BasicRaider = entry.get("node")
	if not is_instance_valid(node) or node.dead:
		entry["health"] = 0
		return
	entry["leg_timer"] = float(entry.get("leg_timer", 0.0)) - delta
	match str(entry.get("phase", "camping")):
		"camping":
			_tick_camping(record, entry, node)
		"patrolling":
			_tick_patrolling(record, entry, node, delta, daylight)
		"travelling":
			_tick_travelling(record, entry, node)
		"sabotaging":
			_tick_sabotaging(record, entry, node, delta)
		_:
			entry["phase"] = "patrolling" if daylight else "camping"


## Night: the garrison sits at the fire. A body that wandered off walks back;
## one already at the fire stands and faces it.
func _tick_camping(record: Dictionary, entry: Dictionary, node: BasicRaider) -> void:
	var fire := Vector3(record.get("cell", Vector3i.ZERO)) + Vector3(0.5, 0.0, 0.5)
	var distance := Vector2(node.global_position.x - fire.x, node.global_position.z - fire.z).length()
	if distance <= float(FIRE_RING) + 0.6:
		node.active = false
		node.set_route([])
		node.clear_goal()
		node.face_point(fire)
		return
	if node.active or float(entry.get("leg_timer", 0.0)) > 0.0:
		return
	entry["leg_timer"] = LEG_LIMIT_SECONDS
	_route_to(record, entry, node, _seat_cell(record, entry))


## Day: a loop inside the camp's radius, with a look around for anything the
## player built on the way.
func _tick_patrolling(record: Dictionary, entry: Dictionary, node: BasicRaider, delta: float, _daylight: bool) -> void:
	entry["scan_timer"] = float(entry.get("scan_timer", 0.0)) - delta
	if float(entry["scan_timer"]) <= 0.0:
		entry["scan_timer"] = maxf(0.5, float(rules.get("patrol_interval_seconds", 6.0)))
		if _discover(record, entry, node):
			return
	if node.active and float(entry.get("leg_timer", 0.0)) > 0.0:
		return
	entry["leg_timer"] = maxf(2.0, float(rules.get("patrol_leg_seconds", 18.0)))
	_route_to(record, entry, node, _patrol_cell(record))


## Walking to the thing it found. Arrival is by distance, not by the route
## finishing, so a body that cannot reach the very last cell still strikes.
func _tick_travelling(record: Dictionary, entry: Dictionary, node: BasicRaider) -> void:
	var target_id := str(entry.get("target_id", ""))
	if target_id.is_empty() or not workstations.stations.has(target_id):
		_return_to_patrol(record, entry, node)
		return
	var target := Vector3(entry.get("target_cell", Vector3i.ZERO)) + Vector3(0.5, 0.0, 0.5)
	if node.global_position.distance_to(target) <= STRIKE_REACH:
		entry["phase"] = "sabotaging"
		entry["attack_timer"] = 0.2
		node.active = false
		node.set_route([])
		node.clear_goal()
		node.face_point(target)
		return
	if float(entry.get("leg_timer", 0.0)) <= 0.0:
		_return_to_patrol(record, entry, node)


## Hitting it, through the ordinary structure damage rules. `break_one` leaves
## the moment the one piece is gone; `destroy` finishes what it started and
## then goes back on patrol either way.
func _tick_sabotaging(record: Dictionary, entry: Dictionary, node: BasicRaider, delta: float) -> void:
	var target_id := str(entry.get("target_id", ""))
	if target_id.is_empty() or not workstations.stations.has(target_id):
		_return_to_patrol(record, entry, node)
		return
	entry["attack_timer"] = float(entry.get("attack_timer", 0.0)) - delta
	if float(entry["attack_timer"]) > 0.0:
		return
	entry["attack_timer"] = maxf(0.2, float(rules.get("attack_interval_seconds", 1.4)))
	node.play_attack()
	var entity_id := str(entry.get("target_entity", ""))
	var result := workstations.try_damage(target_id, maxi(1, int(entry.get("damage", 6))))
	if not result.get("ok", false):
		_return_to_patrol(record, entry, node)
		return
	if str(result.get("reason", "")) != "DESTROYED":
		return
	sabotage_events += 1
	_notice(entry, entity_id, true)
	if str(entry.get("verb", VERB_IGNORE)) == VERB_BREAK_ONE:
		# "Destroy a track and leave": this camp lets that kind alone for a
		# while, so one patrol does not unpick a whole line in one afternoon.
		var cooldowns: Dictionary = record.get("cooldowns", {})
		cooldowns[entity_id] = maxf(0.0, float(rules.get("sabotage_cooldown_seconds", 45.0)))
		record["cooldowns"] = cooldowns
	_return_to_patrol(record, entry, node)


func _return_to_patrol(record: Dictionary, entry: Dictionary, node: BasicRaider) -> void:
	entry["target_id"] = ""
	entry["target_entity"] = ""
	entry["verb"] = VERB_IGNORE
	entry["phase"] = "patrolling" if is_day() else "camping"
	entry["leg_timer"] = 0.0
	entry["scan_timer"] = maxf(0.5, float(rules.get("patrol_interval_seconds", 6.0)))
	if is_instance_valid(node):
		node.active = false
		node.set_route([])
		node.clear_goal()


## ---------------------------------------------------------------- discovery

## Line of sight is deliberately not required on this card: a minion notices a
## player-built thing inside its sight radius whose cells are loaded, and the
## sabotage table decides what happens to it.
func _discover(record: Dictionary, entry: Dictionary, node: BasicRaider) -> bool:
	var found := find_target(record, node.global_position)
	if found.is_empty():
		return false
	entry["target_id"] = str(found["instance_id"])
	entry["target_entity"] = str(found["entity_id"])
	entry["verb"] = str(found["verb"])
	entry["target_cell"] = found["cell"]
	entry["phase"] = "travelling"
	entry["leg_timer"] = LEG_LIMIT_SECONDS
	_notice(entry, str(found["entity_id"]), false)
	_route_to(record, entry, node, _approach_cell(found["cell"], node.feet_cell()))
	return true


## The nearest sabotage target of this camp within `from`'s sight radius: a
## placed station the table names, with a `defense` sheet, whose cells are
## loaded, which is not the camp's own fire. {} when there is nothing.
func find_target(record: Dictionary, from: Vector3) -> Dictionary:
	var reach: float = float(record.get("sight", sight_radius()))
	var cooldowns: Dictionary = record.get("cooldowns", {})
	var fire_id := str(record.get("fire_id", ""))
	var best: Dictionary = {}
	var best_distance := INF
	for instance_id: String in workstations.stations.keys():
		if instance_id == fire_id:
			continue
		var station: Dictionary = workstations.stations[instance_id]
		var entity_id := str(station.get("entity_id", ""))
		var verb := sabotage_verb(entity_id)
		if verb == VERB_IGNORE:
			continue
		if float(cooldowns.get(entity_id, 0.0)) > 0.0:
			continue
		if _owned_by_a_camp(instance_id):
			continue
		if not workstations.defense_status(instance_id).get("ok", false):
			continue
		var anchor: Vector3i = station.get("anchor", Vector3i.ZERO)
		if str(world.query_cell(anchor).get("state", "")) != "LOADED":
			continue
		var centre := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
		var distance := from.distance_to(centre)
		if distance > reach or distance >= best_distance:
			continue
		best_distance = distance
		best = {"instance_id": instance_id, "entity_id": entity_id, "verb": verb, "cell": anchor, "distance": distance}
	return best


func _owned_by_a_camp(instance_id: String) -> bool:
	for camp_id: String in camps.keys():
		if str(camps[camp_id].get("fire_id", "")) == instance_id:
			return true
	return false


## ------------------------------------------------------------------ routing

func _route_to(record: Dictionary, entry: Dictionary, node: BasicRaider, goal: Vector3i) -> bool:
	var snapshot := _capture(record)
	if snapshot == null:
		node.active = false
		return false
	var start := node.feet_cell()
	if start == goal:
		return false
	var capability := core_defense.raider_capability(str(entry.get("kind", BasicRaider.KIND_RAIDER))) if core_defense != null \
		else {"max_step_up": 1, "max_drop_down": 1, "damage_per_hit": {"breachable_wood": 6}, "prefer_weakest": true}
	var route := _planner.find_route(snapshot, start, goal, capability)
	if not route.get("ok", false):
		node.active = false
		node.set_route([])
		return false
	node.set_route(route.get("path", []))
	node.set_goal(Vector3(goal) + Vector3(0.5, 0.0, 0.5))
	return true


func _capture(record: Dictionary) -> NavigationSnapshot:
	var cached: Variant = record.get("capture")
	if cached is NavigationSnapshot and float(record.get("capture_age", 0.0)) < CAPTURE_SECONDS:
		return cached
	var cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var reach: int = int(record.get("radius", patrol_radius())) + 4
	var snapshot := NavigationSnapshot.new()
	var region := AABB(
		Vector3(cell + Vector3i(-reach, -CAPTURE_DEPTH, -reach)),
		Vector3(float(reach * 2 + 1), float(CAPTURE_HEIGHT), float(reach * 2 + 1)))
	var result := snapshot.capture(region, core_defense.world_navigation_cell, world.revision)
	record["capture_age"] = 0.0
	if not result.get("ok", false):
		record["capture"] = null
		return null
	record["capture"] = snapshot
	return snapshot


## A standable cell inside the camp's radius, chosen deterministically from the
## camp's own RNG so a patrol loop is different from run to run but replayable.
func _patrol_cell(record: Dictionary) -> Vector3i:
	var cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var reach: int = int(record.get("radius", patrol_radius()))
	var snapshot: Variant = record.get("capture")
	for _attempt in range(24):
		var angle := _rng.randf() * TAU
		var distance := lerpf(float(reach) * 0.4, float(reach), _rng.randf())
		var candidate := Vector3i(cell.x + roundi(cos(angle) * distance), cell.y, cell.z + roundi(sin(angle) * distance))
		if snapshot is NavigationSnapshot:
			candidate = _settle(snapshot, candidate)
			if candidate == Vector3i.MAX:
				continue
		return candidate
	return cell


## The seat a camper takes at the fire: a ring cell beside it.
func _seat_cell(record: Dictionary, entry: Dictionary) -> Vector3i:
	var cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var members: Array = record.get("members", [])
	var index := maxi(0, members.find(entry))
	var angle := float(index) * TAU / maxf(1.0, float(members.size()))
	var seat := Vector3i(cell.x + roundi(cos(angle) * float(FIRE_RING)), cell.y, cell.z + roundi(sin(angle) * float(FIRE_RING)))
	var snapshot: Variant = record.get("capture")
	if snapshot is NavigationSnapshot:
		var settled := _settle(snapshot, seat)
		if settled != Vector3i.MAX:
			return settled
	return seat


## A cell beside `target` a body can stand in, nearest `from`.
func _approach_cell(target: Vector3i, from: Vector3i) -> Vector3i:
	var best := target
	var best_distance := INF
	for offset: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1)]:
		var candidate := target + offset
		var distance := Vector3(candidate).distance_to(Vector3(from))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Drops a column onto the nearest standable cell within three levels, or
## Vector3i.MAX when the column offers none.
func _settle(snapshot: NavigationSnapshot, cell: Vector3i) -> Vector3i:
	for step in [0, -1, 1, -2, 2, -3, 3]:
		var candidate := cell + Vector3i(0, step, 0)
		var feet := snapshot.query_cell(candidate)
		var head := snapshot.query_cell(candidate + Vector3i.UP)
		var floor_cell := snapshot.query_cell(candidate + Vector3i.DOWN)
		if str(feet.get("state", "")) != "LOADED" or str(floor_cell.get("state", "")) != "LOADED":
			continue
		if bool(feet.get("solid", true)) or bool(head.get("solid", true)) or not bool(floor_cell.get("solid", false)):
			continue
		return candidate
	return Vector3i.MAX


func _on_route_finished(entry: Dictionary) -> void:
	var node: Variant = entry.get("node")
	if node is BasicRaider:
		(node as BasicRaider).active = false
	if str(entry.get("phase", "")) == "patrolling":
		entry["leg_timer"] = 0.0


func _on_body_stuck(entry: Dictionary) -> void:
	# The camp's answer to a stuck body is the plain one: stop this leg and
	# plan a new one next tick. The drill's sidestep/hop ladder belongs to a
	# wave with a core to reach; a patrol simply walks somewhere else.
	entry["leg_timer"] = 0.0
	var node: Variant = entry.get("node")
	if node is BasicRaider:
		(node as BasicRaider).active = false


## -------------------------------------------------------------------- damage

## `CoreDefenseService.foreign_nodes`: the bodies the player's weapons may hit.
func garrison_nodes() -> Array:
	var nodes: Array = []
	for camp_id: String in camps.keys():
		for value in camps[camp_id].get("members", []):
			var entry: Dictionary = value
			var node: Variant = entry.get("node")
			if int(entry.get("health", 0)) > 0 and node is BasicRaider and is_instance_valid(node) and not (node as BasicRaider).dead:
				nodes.append(node)
	return nodes


## `CoreDefenseService.foreign_damage`: a hit on a garrison body.
func damage_body(node: Node, amount: int, source: String = "player") -> Dictionary:
	if amount <= 0 or not node is BasicRaider:
		return {"ok": false, "reason": "NO_RAIDER"}
	for camp_id: String in camps.keys():
		var record: Dictionary = camps[camp_id]
		for value in record.get("members", []):
			var entry: Dictionary = value
			if entry.get("node") != node or int(entry.get("health", 0)) <= 0:
				continue
			var before := int(entry["health"])
			entry["health"] = maxi(0, before - amount)
			if int(entry["health"]) <= 0:
				(node as BasicRaider).die()
				feedback.emit("%s cut down a camp %s." % [source.replace("_", " ").capitalize(), str(entry.get("kind", "raider"))])
			return {"ok": true, "reason": "RAIDER_DEFEATED" if int(entry["health"]) <= 0 else "RAIDER_DAMAGED", "handled": true,
				"camp": camp_id, "changes": {"health_before": before, "health": int(entry["health"]), "damage": amount, "source": source}}
	return {"ok": false, "reason": "NO_RAIDER"}


## ------------------------------------------------------------------ notices

## Silent sabotage the player finds hours later is a bad first cut: every
## discovery and every break within `notice_range` of the player says what it
## was and roughly where.
func _notice(entry: Dictionary, entity_id: String, broken: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var node: Variant = entry.get("node")
	if not node is BasicRaider or not is_instance_valid(node):
		return
	var at: Vector3 = (node as BasicRaider).global_position
	var offset := at - player.global_position
	var distance := Vector2(offset.x, offset.z).length()
	if distance > float(rules.get("notice_range", 80.0)):
		return
	var name_text := registry.display_name(entity_id).to_lower() if registry != null else entity_id
	var verb := "broke" if broken else "is going for"
	feedback.emit("A %s %s your %s — %d m %s." % [str(entry.get("kind", "raider")), verb, name_text, roundi(distance), bearing_text(offset)])


static func bearing_text(offset: Vector3) -> String:
	var index := wrapi(roundi(atan2(offset.x, -offset.z) / (TAU / 8.0)), 0, 8)
	return COMPASS[index]


## ------------------------------------------------------------------ minimap

## The cells of every camp the player has actually met (its fire is standing),
## for the minimap. A camp the player has never reached is not drawn.
func known_camp_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for camp_id: String in camps.keys():
		var record: Dictionary = camps[camp_id]
		if bool(record.get("cleared", false)) or not bool(record.get("spawned", false)):
			continue
		cells.append(record.get("cell", Vector3i.ZERO))
	return cells


## --------------------------------------------------------------- persistence

func snapshot() -> Dictionary:
	var rows: Array = []
	for camp_id: String in camps.keys():
		var record: Dictionary = camps[camp_id]
		var garrison: Array = []
		for value in record.get("members", []):
			var entry: Dictionary = value
			var node: Variant = entry.get("node")
			var position := Vector3(record.get("cell", Vector3i.ZERO))
			if node is BasicRaider and is_instance_valid(node):
				position = (node as BasicRaider).global_position
			garrison.append({"kind": str(entry.get("kind", BasicRaider.KIND_RAIDER)), "health": int(entry.get("health", 0)),
				"position": [position.x, position.y, position.z]})
		if garrison.is_empty():
			garrison = record.get("snapshot", [])
		var cell: Vector3i = record.get("cell", Vector3i.ZERO)
		rows.append({
			"id": camp_id, "cell": [cell.x, cell.y, cell.z], "cleared": bool(record.get("cleared", false)),
			"scripted": bool(record.get("scripted", false)), "started": bool(record.get("started", false)),
			"fire_id": str(record.get("fire_id", "")), "radius": int(record.get("radius", patrol_radius())),
			"sight": float(record.get("sight", sight_radius())), "state": str(record.get("state", "camping")),
			"garrison": garrison,
		})
	return {"version": SNAPSHOT_VERSION, "camps": rows, "sabotage_events": sabotage_events, "camps_cleared": camps_cleared}


func restore(data: Dictionary) -> void:
	if data.is_empty():
		return
	sabotage_events = int(data.get("sabotage_events", 0))
	camps_cleared = int(data.get("camps_cleared", 0))
	_pending_restore = data.duplicate(true)
	_sites_resolved = false


static func _vector3i_from(value: Variant, fallback: Vector3i) -> Vector3i:
	if value is Array and (value as Array).size() == 3:
		var raw: Array = value
		return Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	return fallback


static func _vector3_from(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		var raw: Array = value
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback
