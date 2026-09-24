class_name TrapService
extends Node3D

## Traps (docs/TRAPS.md). A trap is a placed entity carrying a `trap`
## attribute block; this service is the whole of trap behaviour and knows
## nothing about any particular trap. Modelled on FireService: a map of
## `instance_id -> trap state`, ticked on a fixed interval from
## `GameSession._process` and frozen with the simulation.
##
## The owner's rules (docs/TRAPS.md):
## 1. A trap is undetected. A raider that still has a route never selects one
##    as a target and never damages one in passing. That rule lives in
##    `LocalGridPathfinder` (and the `trap` flag on the navigation cell
##    `WorkstationService` publishes), not here.
## 2. A trap is persistent, not consumable: it fires, disarms, and re-arms
##    itself after `reset_seconds`. There are no charges.
## 3. A raider with no route at all attacks the weakest obstacle it can
##    reach, and a trap is an ordinary damageable station while it does.
##
## Triggering is arithmetic over the raider bodies' feet cells: no collision
## layer and no Area3D (the repo has neither and this card adds neither).

signal trap_fired(instance_id: String, cell: Vector3i, hits: int)
signal trap_armed(instance_id: String, cell: Vector3i)
signal feedback(message: String)

## The simulation tick. Fast enough that a raider walking at 2.8 m/s cannot
## cross a one-cell trap between two ticks (0.28 m of travel per tick).
const TICK_SECONDS := 0.1
## How fast a trap's moving part travels between rest and sprung, in m/s.
const ACTION_SPEED := 6.0
## How far below a ceiling trap it reaches when the block does not say.
const DEFAULT_CEILING_REACH := 3

var workstations: WorkstationService
var registry: ContentRegistry
## `(cell, amount, source) -> hits`: CoreDefenseService.damage_raiders_in_cell.
var damage_cell: Callable
## `(point, radius, amount, source, provoker) -> hits`: damage_raiders_within.
var damage_area: Callable
## `() -> Array[BasicRaider]`: CoreDefenseService.raider_nodes.
var raiders: Callable
## `() -> Node3D`: the player body, for a trap whose block says
## `affects_player`. Anything with `feet_cell()` and `global_position` will
## do; the service never asks what kind of body it caught.
var player_body: Callable
## `(cell, munition_id, radius) -> lit`: FireService.ignite through the
## session, for a trap whose block carries an `ignite` sub-block. Fire stays
## one system; a trap only names a munition that already exists.
var ignite_cells: Callable
## instance_id -> {cell, cells, entity_id, tuning, armed, reset_seconds_left,
## fire_seconds_left, fired_count}
var traps: Dictionary = {}
var fired_total := 0
var _visuals: Dictionary = {}
var _tick_left := TICK_SECONDS
var _dirty := true
## instance_id -> saved clocks waiting for their station to be restored.
var _pending_restore: Dictionary = {}


func initialize(station_service: WorkstationService, content_registry: ContentRegistry, cell_damage: Callable, area_damage: Callable, raider_source: Callable, saved: Variant = [], player_source: Callable = Callable(), ignite_source: Callable = Callable()) -> void:
	workstations = station_service
	registry = content_registry
	damage_cell = cell_damage
	damage_area = area_damage
	raiders = raider_source
	player_body = player_source
	ignite_cells = ignite_source
	if workstations != null and not workstations.station_changed.is_connected(_on_station_changed):
		workstations.station_changed.connect(_on_station_changed)
	_sync()
	restore(saved)


## True for any entity whose content sheet carries a `trap` block. Nothing
## else in the codebase decides what a trap is.
func is_trap_entity(entity_id: String) -> bool:
	return registry != null and not registry.entity(entity_id).get("trap", {}).is_empty()


## Every cell owned by a standing trap -> its instance id. The diagnostics and
## the Expo read it; the planner does not need it (a trap cell already says
## `trap: true` in the navigation snapshot).
func trap_cells() -> Dictionary:
	if _dirty:
		_sync()
	var cells: Dictionary = {}
	for instance_id: String in traps:
		for cell: Vector3i in traps[instance_id].get("cells", []):
			cells[cell] = instance_id
	return cells


func is_armed(instance_id: String) -> bool:
	return bool(traps.get(instance_id, {}).get("armed", false))


func state_of(instance_id: String) -> Dictionary:
	return (traps.get(instance_id, {}) as Dictionary).duplicate(true)


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0:
		return
	if _dirty:
		_sync()
	if not traps.is_empty():
		_tick_left -= delta
		while _tick_left <= 0.0:
			_tick_left += TICK_SECONDS
			_step(TICK_SECONDS)
	_animate(delta)


## One fixed tick: reset clocks run down, armed traps look for a victim.
func _step(dt: float) -> void:
	var feet := _raider_feet()
	for instance_id: String in traps.keys():
		var trap: Dictionary = traps[instance_id]
		trap.fire_seconds_left = maxf(0.0, float(trap.fire_seconds_left) - dt)
		if not bool(trap.armed):
			trap.reset_seconds_left = maxf(0.0, float(trap.reset_seconds_left) - dt)
			if float(trap.reset_seconds_left) <= 0.0:
				trap.armed = true
				traps[instance_id] = trap
				trap_armed.emit(instance_id, trap.cell)
				continue
			traps[instance_id] = trap
			continue
		traps[instance_id] = trap
		var caught := _triggered_by(trap, feet)
		if not caught.is_empty():
			_fire(instance_id, caught)


## The raider bodies that are standing in this trap's trigger volume right
## now. `feet` is the pre-computed feet cell of every living raider.
func _triggered_by(trap: Dictionary, feet: Array) -> Array:
	var tuning: Dictionary = trap.tuning
	var player_too := bool(tuning.get("affects_player", false))
	var caught: Array = []
	match str(tuning.get("trigger", "pressure")):
		"proximity":
			var centre := Vector3(trap.cell) + Vector3(0.5, 0.5, 0.5)
			var reach := maxf(float(tuning.get("radius", 0.0)), 1.0)
			for entry in feet:
				if bool(entry.get("player", false)) and not player_too:
					continue
				var point: Vector3 = entry["position"]
				if Vector2(point.x - centre.x, point.z - centre.z).length() <= reach and absf(point.y - centre.y) <= 2.0:
					caught.append(entry["node"])
		_:
			var cells: Dictionary = trap.trigger_cells
			for entry in feet:
				if bool(entry.get("player", false)) and not player_too:
					continue
				if cells.has(entry["cell"]):
					caught.append(entry["node"])
	return caught


## The trap springs: it applies its effect, disarms, and starts its own reset
## clock. Nothing is consumed - a trap is permanent furniture (rule 2).
func _fire(instance_id: String, caught: Array) -> void:
	var trap: Dictionary = traps[instance_id]
	var tuning: Dictionary = trap.tuning
	trap.armed = false
	trap.reset_seconds_left = maxf(0.1, float(tuning.get("reset_seconds", 6.0)))
	trap.fire_seconds_left = maxf(0.1, float(tuning.get("fire_seconds", 1.0)))
	trap.fired_count = int(trap.fired_count) + 1
	traps[instance_id] = trap
	fired_total += 1
	var hits := _apply_effect(trap, caught)
	_apply_ignition(trap)
	trap_fired.emit(instance_id, trap.cell, hits)
	feedback.emit("%s sprang on %d attacker%s and resets in %d s." % [
		registry.display_name(str(trap.entity_id)), hits, "" if hits == 1 else "s",
		ceili(float(trap.reset_seconds_left))])


## The effect vocabulary a `trap` block may ask for. A new trap fills in the
## block; nothing here is specific to one trap.
func _apply_effect(trap: Dictionary, caught: Array) -> int:
	var tuning: Dictionary = trap.tuning
	match str(tuning.get("effect", "damage")):
		"damage":
			var amount := int(tuning.get("damage", 0))
			if amount <= 0:
				return 0
			var radius := float(tuning.get("radius", 0.0))
			if radius > 0.0 and damage_area.is_valid():
				return int(damage_area.call(Vector3(trap.cell) + Vector3(0.5, 0.5, 0.5), radius, amount, "trap", ""))
			if not damage_cell.is_valid():
				return 0
			# Once per body, not once per trigger cell: a trap whose trigger
			# volume is several cells tall (a ceiling trap reaching down, a
			# wall trap catching head and feet) must not hit the same raider
			# once per cell - `damage_raiders_in_cell` already forgives a
			# cell of vertical slack, so the cells would overlap.
			var hits := 0
			var struck: Dictionary = {}
			for node in caught:
				if node is BasicRaider:
					struck[node.feet_cell()] = true
			for cell: Vector3i in struck.keys():
				hits += int(damage_cell.call(cell, amount, "trap"))
			# A body that is not a raider (the player, when the block says
			# `affects_player`) is hurt through its own method: the cell
			# damage above only reaches the wave.
			for node in caught:
				if not node is BasicRaider and node.has_method("take_damage"):
					node.take_damage(amount, "trap")
					hits += 1
			return hits
		"slow":
			# Tar and its relatives: the body keeps its route and loses its
			# speed for a while.
			var factor := clampf(float(tuning.get("slow_factor", 0.5)), 0.05, 0.99)
			var seconds := maxf(0.1, float(tuning.get("slow_seconds", 3.0)))
			var slowed := 0
			for node in caught:
				if node.has_method("apply_slow"):
					node.apply_slow(factor, seconds)
					slowed += 1
			return slowed
		"push":
			# The Spring Plate: one impulse along the trap's own facing, up
			# and out. Whoever answers `apply_push` is thrown - a raider or
			# the player - and the service never asks which it caught.
			var impulse := _push_impulse(trap)
			var thrown := 0
			for node in caught:
				if node.has_method("apply_push"):
					node.apply_push(impulse)
					thrown += 1
			return thrown
	push_warning("TrapService: unknown trap effect '%s' on %s" % [str(tuning.get("effect", "")), str(trap.entity_id)])
	return 0


## Every body a trap could catch this tick, with its feet cell and position:
## the living raiders always, and the player as well while any standing trap
## says `affects_player`. Computed once a tick for every trap.
func _raider_feet() -> Array:
	var feet: Array = []
	if raiders.is_valid():
		var nodes: Variant = raiders.call()
		if nodes is Array:
			for value in nodes:
				if value is BasicRaider and is_instance_valid(value) and not value.dead:
					feet.append({"node": value, "cell": value.feet_cell(), "position": value.global_position})
	if _catches_player() and player_body.is_valid():
		var player: Variant = player_body.call()
		if player is Node3D and is_instance_valid(player) and player.has_method("feet_cell"):
			feet.append({"node": player, "cell": player.feet_cell(), "position": player.global_position, "player": true})
	return feet


## True while any standing trap's block asks to catch the player too. It is
## an attribute, so no trap is named here.
func _catches_player() -> bool:
	for instance_id: String in traps:
		if bool((traps[instance_id].tuning as Dictionary).get("affects_player", false)):
			return true
	return false


func _on_station_changed(_result: Dictionary) -> void:
	_dirty = true


## Re-reads the standing stations now (the session calls this once the saved
## world and its stations are back, so restored trap clocks land).
func sync() -> void:
	_sync()


## Brings the trap map in line with what stands in the world: a newly placed
## trap arrives armed, a destroyed one leaves. Existing state is preserved.
func _sync() -> void:
	_dirty = false
	if workstations == null or registry == null:
		return
	var seen: Dictionary = {}
	for instance_id: String in workstations.stations.keys():
		var record: Dictionary = workstations.stations[instance_id]
		var entity_id := str(record.get("entity_id", ""))
		var tuning: Dictionary = registry.entity(entity_id).get("trap", {})
		if tuning.is_empty():
			continue
		seen[instance_id] = true
		if traps.has(instance_id):
			continue
		var cell: Vector3i = record.get("anchor", Vector3i.ZERO)
		traps[instance_id] = {
			"cell": cell,
			"entity_id": entity_id,
			"rotation_quarters": int(record.get("rotation_quarters", 0)),
			"mount": str(record.get("mount", "ground")),
			"cells": _occupied_cells(record, entity_id),
			"trigger_cells": _trigger_cells(record, entity_id, tuning),
			"tuning": tuning.duplicate(true),
			"armed": true,
			"reset_seconds_left": 0.0,
			"fire_seconds_left": 0.0,
			"fired_count": 0,
		}
		if _pending_restore.has(instance_id):
			_apply_saved(instance_id, _pending_restore[instance_id])
			_pending_restore.erase(instance_id)
	for instance_id: String in traps.keys():
		if not seen.has(instance_id):
			traps.erase(instance_id)
			_forget_visual(instance_id)


func _occupied_cells(record: Dictionary, entity_id: String) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var quarters := int(record.get("rotation_quarters", 0))
	for value in registry.entity(entity_id).get("occupied_offsets", []):
		var offset := _vector3i(value)
		cells.append(anchor + workstations.footprints.rotate_offset(offset, quarters))
	if cells.is_empty():
		cells.append(anchor)
	return cells


## Where the trap can catch somebody, from its `mount` (and an explicit
## `trigger_offsets` list when a future trap wants one). A floor trap catches
## whoever stands in its own cells; a floor trap that blocks movement catches
## whoever stands on top of it; a ceiling trap reaches down; a wall trap
## catches the cells it faces.
func _trigger_cells(record: Dictionary, entity_id: String, tuning: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	var occupied := _occupied_cells(record, entity_id)
	var explicit: Array = tuning.get("trigger_offsets", [])
	if not explicit.is_empty():
		var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
		var quarters := int(record.get("rotation_quarters", 0))
		for value in explicit:
			cells[anchor + workstations.footprints.rotate_offset(_vector3i(value), quarters)] = true
		return cells
	match str(tuning.get("mount", "floor")):
		"ceiling":
			var reach := maxi(1, int(tuning.get("reach", DEFAULT_CEILING_REACH)))
			for cell: Vector3i in occupied:
				for step in range(1, reach + 1):
					cells[cell - Vector3i(0, step, 0)] = true
		"wall":
			# A wall mount faces away from the block it hangs on (placement
			# turns it there), so it catches the cells directly in front of
			# it - and the cell under each of those, so a trap hung a block
			# above the floor still reaches the feet walking past beneath it.
			var quarters := int(record.get("rotation_quarters", 0))
			var facing := workstations.footprints.rotate_offset(Vector3i(1, 0, 0), quarters)
			for cell: Vector3i in occupied:
				var front := cell + facing
				if occupied.has(front):
					continue
				cells[front] = true
				cells[front + Vector3i(0, -1, 0)] = true
		_:
			for cell: Vector3i in occupied:
				cells[cell + Vector3i(0, 1, 0) if bool(tuning.get("blocks_movement", false)) else cell] = true
	return cells


func snapshot() -> Array:
	var saved: Array = []
	for instance_id: String in traps:
		var trap: Dictionary = traps[instance_id]
		saved.append({
			"instance_id": instance_id,
			"armed": bool(trap.armed),
			"reset_seconds_left": snappedf(float(trap.reset_seconds_left), 0.01),
			"fire_seconds_left": snappedf(float(trap.fire_seconds_left), 0.01),
			"fired_count": int(trap.fired_count),
		})
	return saved


## Puts saved trap clocks back. The stations themselves are restored later,
## when the spawn area is ready, so the record waits here until its trap
## appears; a trap the save does not mention opens armed.
func restore(saved: Variant) -> void:
	if not saved is Array:
		return
	for value in saved:
		if not value is Dictionary:
			continue
		var instance_id := str(value.get("instance_id", ""))
		if instance_id.is_empty():
			continue
		if traps.has(instance_id):
			_apply_saved(instance_id, value)
		else:
			_pending_restore[instance_id] = (value as Dictionary).duplicate(true)
	if not _pending_restore.is_empty():
		_sync()


func _apply_saved(instance_id: String, saved: Dictionary) -> void:
	var trap: Dictionary = traps[instance_id]
	trap.armed = bool(saved.get("armed", true))
	trap.reset_seconds_left = float(saved.get("reset_seconds_left", 0.0))
	trap.fire_seconds_left = float(saved.get("fire_seconds_left", 0.0))
	trap.fired_count = int(saved.get("fired_count", 0))
	traps[instance_id] = trap
	_apply_visual_state(instance_id, true)


## The presentation layer hands the trap's placed body over so the service can
## drive it. The moving part is any child named `TrapAction`; the armed lamp
## is any child named `TrapLamp`. A trap visual without them still works.
func register_visual(instance_id: String, body: Node3D) -> void:
	if body == null:
		return
	var action := body.get_node_or_null("TrapAction")
	_visuals[instance_id] = {
		"body": body,
		"action": action,
		"rest": action.position if action != null else Vector3.ZERO,
		"lamp": body.get_node_or_null("TrapLamp"),
	}
	_apply_visual_state(instance_id, true)


func _forget_visual(instance_id: String) -> void:
	_visuals.erase(instance_id)


## Armed / fired / resetting, shown on the body: the moving part travels out
## while the trap is sprung and retracts once its fire window closes, and the
## lamp is lit only while the trap is armed and dangerous.
func _animate(delta: float) -> void:
	for instance_id: String in _visuals.keys():
		var visual: Dictionary = _visuals[instance_id]
		var action: Node3D = visual.get("action")
		if action == null or not is_instance_valid(action):
			continue
		if not traps.has(instance_id):
			continue
		var trap: Dictionary = traps[instance_id]
		var target: Vector3 = visual.rest
		if float(trap.fire_seconds_left) > 0.0:
			target = Vector3(visual.rest) + _travel(trap)
		action.position = action.position.move_toward(target, ACTION_SPEED * delta)
		_apply_visual_state(instance_id, false)


func _apply_visual_state(instance_id: String, snap: bool) -> void:
	var visual: Dictionary = _visuals.get(instance_id, {})
	if visual.is_empty() or not traps.has(instance_id):
		return
	var trap: Dictionary = traps[instance_id]
	var action: Node3D = visual.get("action")
	if snap and action != null and is_instance_valid(action):
		action.position = Vector3(visual.rest) + (_travel(trap) if float(trap.fire_seconds_left) > 0.0 else Vector3.ZERO)
	var lamp: Node3D = visual.get("lamp")
	if lamp != null and is_instance_valid(lamp):
		lamp.visible = bool(trap.armed)


## The impulse a `push` trap gives, in world space: `push_speed` along the
## trap's facing (its own local +x, turned by its rotation) plus `push_lift`
## straight up, so the body is thrown clear instead of skidding.
func _push_impulse(trap: Dictionary) -> Vector3:
	var tuning: Dictionary = trap.tuning
	var facing: Vector3i = workstations.footprints.rotate_offset(Vector3i(1, 0, 0), int(trap.get("rotation_quarters", 0)))
	var speed := maxf(0.0, float(tuning.get("push_speed", 0.0)))
	var lift := maxf(0.0, float(tuning.get("push_lift", 0.0)))
	return Vector3(facing.x, 0.0, facing.z).normalized() * speed + Vector3.UP * lift


## The optional `ignite` sub-block: the trap lights its trigger cells through
## the one fire system there is (FireService), by the id of a fire munition
## that already exists. Nothing about fire is re-implemented here.
func _apply_ignition(trap: Dictionary) -> void:
	var ignite: Dictionary = (trap.tuning as Dictionary).get("ignite", {})
	if ignite.is_empty() or not ignite_cells.is_valid():
		return
	var munition_id := str(ignite.get("munition", ""))
	var radius := float(ignite.get("radius", 0.0))
	if munition_id.is_empty():
		return
	for cell: Vector3i in trap.trigger_cells.keys():
		ignite_cells.call(cell, munition_id, radius)


func _travel(trap: Dictionary) -> Vector3:
	var tuning: Dictionary = trap.tuning
	var value: Variant = tuning.get("action_travel", [])
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(0.0, 0.55, 0.0)


func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and (value as Array).size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
