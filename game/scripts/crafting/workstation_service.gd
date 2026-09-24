class_name WorkstationService
extends RefCounted

signal station_changed(result: Dictionary)
signal job_completed(result: Dictionary)

## Sign (docs/SIGNS.md, Development Expo section 9): a placed sign carries one
## `sign` block of stable ids and text - a display mode, two text fields and up
## to eight item ids. It is saved with the station record and never stores a
## label or a scene path.
const SIGN_ENTITY := "sign"
## The wide board (signs card 2): the same sign two cells across, its own item
## and recipe so the placement rules stay one entity = one footprint. Both
## entities carry the identical `sign` block and the identical editor.
const SIGN_BOARD_ENTITY := "sign_board"
const SIGN_ENTITIES: Array[String] = [SIGN_ENTITY, SIGN_BOARD_ENTITY]
## Defence sets (docs/DEFENSE_SETS.md): the gate leaf that hangs in a gate
## frame's opening. Right-click toggles it; closed it is solid to pathing and
## breachable like the rest of the castle kit, open it is a hole in the wall.
const GATE_ENTITY := "gate"
## Gates card 2 (owner 2026-09-24): "There need to be more than 1 type of gate.
## We need big gates too. Very big, so a catapult can fit through easily 4
## blocks wide." Three sizes, ONE behaviour - every rule below reads the leaf's
## own footprint instead of the 1 x 2 the first gate happened to be, so a size
## is content (a row in `contracts/content.json`), not code.
const DOUBLE_GATE_ENTITY := "double_gate"
const GREAT_GATE_ENTITY := "great_gate"
const GATE_ENTITIES: Array[String] = [GATE_ENTITY, DOUBLE_GATE_ENTITY, GREAT_GATE_ENTITY]
## The frame each size hangs in. Its jambs are half a leaf thick, so an open
## leaf slides entirely inside the frame's own footprint however wide it is.
const GATE_FRAME_ENTITIES: Array[String] = ["gate_frame", "double_gate_frame", "great_gate_frame"]
## How long the leaf takes to slide clear (presentation only; the pathing
## change is immediate, as a pulled lever would be).
const GATE_SLIDE_SECONDS := 0.55
const SIGN_MODES: Array[String] = ["text", "split", "items", "header_items"]
const SIGN_ITEM_SLOTS := 8
## What a stored text field may hold. It is longer than what the editor's own
## line lets the player type because an authored sign (the Expo's district and
## exhibit boards, docs/DEVELOPMENT_EXPO.md) carries the manifest's whole body
## paragraph in one field; the board autowraps it.
const SIGN_TEXT_LIMIT := 256
## What the SIGN editor's own text line accepts, so a hand-typed sign stays a
## readable heading rather than a wall of text.
const SIGN_EDITOR_TEXT_LIMIT := 64

var registry: ContentRegistry
var inventory: F0Inventory
var footprints := EntityFootprintService.new()
var stations: Dictionary = {}
var jobs: Dictionary = {}
## Creative sandbox: a dismantled entity the full pack cannot take is simply
## gone instead of refusing the removal (the stock is infinite anyway).
var creative := false
var _next_instance := 1
var _next_job := 1


func _init(content_registry: ContentRegistry, player_inventory: F0Inventory) -> void:
	registry = content_registry
	inventory = player_inventory


func preview_placement(entity_id: String, anchor: Vector3i, rotation_quarters: int, world_query: Callable, player_aabb: AABB) -> Dictionary:
	var definition := registry.entity(entity_id)
	if definition.is_empty():
		return _result(false, "UNKNOWN_ENTITY")
	var wall_side := _wall_side(definition, anchor, world_query)
	if wall_side != Vector3i.ZERO:
		rotation_quarters = _rotation_facing_away(wall_side)
	else:
		rotation_quarters = _socket_aligned_rotation(definition, anchor, rotation_quarters, world_query)
	var validated := footprints.validate_placement("preview", anchor, _vector_list(definition.get("occupied_offsets", [])), rotation_quarters, world_query, player_aabb, [] if wall_side != Vector3i.ZERO else _vector_list(definition.get("support_offsets", [])))
	if not validated.get("ok", false):
		return validated
	if not _gate_frame_opening_clear(entity_id, anchor, rotation_quarters, world_query):
		return _result(false, "OPENING_BLOCKED")
	if wall_side != Vector3i.ZERO:
		return _result(true, "OK", {"mount": "wall", "wall_side": wall_side, "rotation_quarters": rotation_quarters})
	return _validate_mount(definition, anchor, rotation_quarters, world_query)


## Wall mounting (P4G lanterns/torches, owner 2026-09-19): an entity whose
## mount allows "wall" may hang on the side of a solid block. Returns the
## direction of that block from the anchor, or ZERO when not wall-mountable
## here (no solid side neighbour, or the entity prefers the ground it has).
func _wall_side(definition: Dictionary, anchor: Vector3i, world_query: Callable) -> Vector3i:
	var allowed: Array = definition.get("mount", {}).get("allowed", [])
	if not allowed.has("wall"):
		return Vector3i.ZERO
	if allowed.has("ground"):
		# Prefer standing on the ground when there is ground.
		var below: Dictionary = world_query.call(anchor + Vector3i.DOWN)
		if str(below.get("state", "")) == "LOADED" and int(below.get("voxel_id", 0)) != 0:
			return Vector3i.ZERO
		if not footprints.owner_at(anchor + Vector3i.DOWN).is_empty():
			return Vector3i.ZERO
	for side in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var query: Dictionary = world_query.call(anchor + side)
		if str(query.get("state", "")) == "LOADED" and int(query.get("voxel_id", 0)) != 0:
			return side
	return Vector3i.ZERO


## Defence sets: a piece that seats itself in another piece's socket
## (`rotation_from_mount`, today the gate leaf in a gate frame's opening) has
## only one sensible orientation - the one whose supports reach the frame's
## jambs. Rather than make the player find it with W/R, the first quarter turn
## from the one they hold that validates is used; when none does, their own
## rotation is kept so the refusal they see is the real one.
func _socket_aligned_rotation(definition: Dictionary, anchor: Vector3i, rotation_quarters: int, world_query: Callable) -> int:
	if not bool(definition.get("rotation_from_mount", false)):
		return rotation_quarters
	for turn in range(4):
		var candidate := posmod(rotation_quarters + turn, 4)
		if _validate_mount(definition, anchor, candidate, world_query).get("ok", false):
			return candidate
	return rotation_quarters


## Quarter turns so the model's bracket side (local -x; body yaw is
## -q * PI/2) touches the wall in `wall_side`.
func _rotation_facing_away(wall_side: Vector3i) -> int:
	if wall_side == Vector3i(-1, 0, 0):
		return 0
	if wall_side == Vector3i(0, 0, -1):
		return 1
	if wall_side == Vector3i(1, 0, 0):
		return 2
	return 3


## `extra` (coaster rails side project): additional JSON-safe record fields,
## e.g. a loop piece's `coaster_joints`; never overrides the standard fields.
func try_place(entity_id: String, anchor: Vector3i, world_query: Callable, player_aabb: AABB, rotation_quarters: int = 0, extra: Dictionary = {}) -> Dictionary:
	var definition := registry.entity(entity_id)
	if definition.is_empty():
		return _result(false, "UNKNOWN_ENTITY")
	# `_free` (the loop element, paid by one Rail Loop): no item is consumed.
	var free := bool(extra.get("_free", false))
	if not free and inventory.count(entity_id) < 1:
		return _result(false, "NO_RESOURCE")
	if bool(definition.get("linear", false)):
		rotation_quarters = _aligned_rotation(entity_id, anchor, rotation_quarters)
	var wall_side := _wall_side(definition, anchor, world_query)
	var mount_result: Dictionary
	if wall_side != Vector3i.ZERO:
		rotation_quarters = _rotation_facing_away(wall_side)
		mount_result = _result(true, "OK", {"mount": "wall"})
	else:
		rotation_quarters = _socket_aligned_rotation(definition, anchor, rotation_quarters, world_query)
		mount_result = _validate_mount(definition, anchor, rotation_quarters, world_query)
	if not mount_result.get("ok", false):
		return mount_result
	if not _gate_frame_opening_clear(entity_id, anchor, rotation_quarters, world_query):
		return _result(false, "OPENING_BLOCKED")
	var instance_id := "%s_%04d" % [entity_id, _next_instance]
	var reserved := footprints.try_reserve(instance_id, anchor, _vector_list(definition.get("occupied_offsets", [])), rotation_quarters, world_query, player_aabb, [] if wall_side != Vector3i.ZERO else _vector_list(definition.get("support_offsets", [])))
	if not reserved.get("ok", false):
		return reserved
	if not free:
		var consumed := inventory.try_transaction({entity_id: 1}, {})
		if not consumed.get("ok", false):
			footprints.release_at(anchor)
			return _result(false, consumed.get("reason", "INVENTORY_COMMIT_FAILED"))
	_next_instance += 1
	var record := {"instance_id": instance_id, "entity_id": entity_id, "anchor": anchor, "rotation_quarters": posmod(rotation_quarters, 4)}
	for extra_key: String in extra.keys():
		if not record.has(extra_key) and not extra_key.begins_with("_"):
			record[extra_key] = extra[extra_key]
	if entity_id == "furnace":
		record["furnace_slots"] = _empty_furnace_slots()
		record["furnace_fuel_operations"] = 0
		record["furnace_fuel_burning"] = false
		record["fuel_model"] = 2
	if entity_id == "foundry":
		# Storage network card (docs/INDUSTRY.md): the foundry smelts from its
		# own three slots, fed from the storage beside it.
		record["foundry_slots"] = _empty_foundry_slots()
	if wall_side != Vector3i.ZERO:
		# A wall-mounted entity hangs on the side of a block and has no ground
		# under it; the record remembers that so restore does not ask for the
		# support the placement never needed.
		record["mount"] = "wall"
	if is_sign(entity_id):
		record["sign"] = default_sign()
	if is_gate_entity(entity_id):
		# A gate is hung closed, whatever its size: the wall it completes is a
		# wall until the owner opens it.
		record["gate_open"] = false
	var defense_definition: Dictionary = definition.get("defense", {})
	if not defense_definition.is_empty():
		record["integrity"] = maxi(1, int(defense_definition.get("max_integrity", 1)))
	var siege_definition: Dictionary = definition.get("siege", {})
	if not siege_definition.is_empty():
		record["siege_ammo"] = maxi(0, int(siege_definition.get("starting_ammo", 0)))
		record["siege_cooldown"] = 0.0
		record["siege_ammo_item"] = str(siege_definition.get("ammo_item", ""))
		record["siege_stance"] = "fire_at_will"
		record["siege_target_filter"] = "any"
	if int(definition.get("container_slots", 0)) > 0:
		var slots: Array = []
		for _slot in range(int(definition.get("container_slots", 0))):
			slots.append(_empty_stack())
		record["container_slots"] = slots
	stations[instance_id] = record
	var result := _result(true, "OK", {"station": stations[instance_id].duplicate(true), "consumed_item": entity_id, "occupied_cells": reserved.get("details", {}).get("cells", []).duplicate(), "mount": str(mount_result.get("details", {}).get("mount", "ground"))})
	station_changed.emit(result)
	return result


## `refund` false (undo): the piece goes without handing its item back - the
## undo refunds what the lay actually cost.
func try_dismantle(instance_id: String, world_query: Callable, player_aabb: AABB, refund: bool = true) -> Dictionary:
	if not stations.has(instance_id):
		return _result(false, "NO_ENTITY")
	if jobs.has(instance_id):
		return _result(false, "STATION_BUSY")
	var record: Dictionary = stations[instance_id]
	if str(record.get("entity_id", "")) == "furnace" and not _furnace_is_empty(record):
		return _result(false, "STATION_NOT_EMPTY")
	var item_id := str(record.entity_id)
	var refund_fits := refund and inventory.can_transaction({}, {item_id: 1})
	if refund and not refund_fits and not creative:
		return _result(false, "INVENTORY_FULL")
	var released := footprints.release_at(record.anchor)
	if not released.get("ok", false):
		return released
	var granted := inventory.try_transaction({}, {item_id: 1}) if refund_fits else {"ok": true}
	if not granted.get("ok", false):
		var definition := registry.entity(item_id)
		footprints.try_reserve(instance_id, record.anchor, _vector_list(definition.occupied_offsets), int(record.rotation_quarters), world_query, player_aabb, _vector_list(definition.support_offsets))
		return _result(false, "INVENTORY_COMMIT_FAILED")
	stations.erase(instance_id)
	var result := _result(true, "OK", {"instance_id": instance_id, "returned_item": item_id, "anchor": record.anchor, "occupied_cells": released.get("details", {}).get("released_cells", []).duplicate()})
	station_changed.emit(result)
	return result


func try_start_furnace(instance_id: String, recipe_id: String) -> Dictionary:
	if not stations.has(instance_id) or str(stations[instance_id].entity_id) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	if jobs.has(instance_id):
		return _result(false, "STATION_BUSY")
	var recipe := registry.recipe(recipe_id)
	if recipe.is_empty() or str(recipe.get("station", "")) != "furnace" or float(recipe.get("duration_seconds", 0.0)) <= 0.0:
		return _result(false, "WRONG_WORKSTATION")
	var checked := check_furnace_recipe(instance_id, recipe_id)
	if not checked.get("ok", false):
		return checked
	var job_id := "job_%04d" % _next_job
	var slots: Dictionary = stations[instance_id].get("furnace_slots", _empty_furnace_slots()).duplicate(true)
	for item_id: String in recipe.inputs:
		var role := _furnace_role_for_item(item_id)
		if role == "fuel":
			continue
		var taken := _take_from_stack(slots.get(role, _empty_stack()), int(recipe.inputs[item_id]))
		if not taken.get("ok", false):
			return taken
		slots[role] = taken.stack
	stations[instance_id]["furnace_slots"] = slots
	_consume_furnace_operation(instance_id)
	_next_job += 1
	jobs[instance_id] = {"job_id": job_id, "recipe_id": recipe_id, "remaining_seconds": float(recipe.duration_seconds), "duration_seconds": float(recipe.duration_seconds), "completed": false}
	var result := _result(true, "JOB_STARTED", {"instance_id": instance_id, "job": jobs[instance_id].duplicate(true), "furnace_slots": furnace_slots(instance_id), "fuel": furnace_fuel_status(instance_id).get("details", {})})
	station_changed.emit(result)
	return result


func check_furnace_recipe(instance_id: String, recipe_id: String) -> Dictionary:
	if not stations.has(instance_id) or str(stations[instance_id].get("entity_id", "")) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	if jobs.has(instance_id):
		return _result(false, "STATION_BUSY")
	var recipe := registry.recipe(recipe_id)
	if recipe.is_empty() or str(recipe.get("station", "")) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	var slots: Dictionary = stations[instance_id].get("furnace_slots", _empty_furnace_slots())
	for item_id: String in recipe.inputs:
		var role := _furnace_role_for_item(item_id)
		var stack: Dictionary = slots.get(role, _empty_stack())
		if role == "fuel" and _furnace_available_operations(instance_id) >= int(recipe.inputs[item_id]):
			continue
		if str(stack.get("item_id", "")) != item_id or int(stack.get("count", 0)) < int(recipe.inputs[item_id]):
			return {"ok": false, "reason": "INSUFFICIENT_INPUT", "item_id": item_id}
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.size() != 1:
		return _result(false, "INVALID_FURNACE_RECIPE")
	var output_id := str(outputs.keys()[0])
	var output_count := int(outputs[output_id])
	var output: Dictionary = slots.get("output", _empty_stack())
	if not str(output.get("item_id", "")).is_empty() and str(output.get("item_id", "")) != output_id:
		return _result(false, "OUTPUT_BLOCKED")
	if int(output.get("count", 0)) + output_count > registry.max_stack(output_id):
		return _result(false, "OUTPUT_BLOCKED")
	return _result(true, "OK", {"inputs": recipe.inputs.duplicate(true), "outputs": outputs.duplicate(true)})


func furnace_recipe_availability(instance_id: String, recipe_id: String) -> Dictionary:
	var direct := check_furnace_recipe(instance_id, recipe_id)
	if direct.get("ok", false) or str(direct.get("reason", "")) != "INSUFFICIENT_INPUT":
		return direct
	var recipe := registry.recipe(recipe_id)
	var slots := furnace_slots(instance_id)
	for item_id: String in recipe.get("inputs", {}):
		var role := _furnace_role_for_item(item_id)
		var stack: Dictionary = slots.get(role, _empty_stack())
		var stack_id := str(stack.get("item_id", ""))
		if not stack_id.is_empty() and stack_id != item_id:
			return _result(false, "SLOT_OCCUPIED")
		var staged := _furnace_available_operations(instance_id) if role == "fuel" else int(stack.get("count", 0))
		var missing := maxi(0, int(recipe.inputs[item_id]) - staged)
		if inventory.count(item_id) < missing:
			return {"ok": false, "reason": "INSUFFICIENT_INPUT", "item_id": item_id}
	return _result(true, "READY_TO_LOAD")


func try_load_furnace_recipe(instance_id: String, recipe_id: String) -> Dictionary:
	var available := furnace_recipe_availability(instance_id, recipe_id)
	if not available.get("ok", false):
		return available
	var direct := check_furnace_recipe(instance_id, recipe_id)
	if direct.get("ok", false):
		return _result(true, "UNCHANGED", {"instance_id": instance_id, "furnace_slots": furnace_slots(instance_id)})
	var recipe := registry.recipe(recipe_id)
	var slots := furnace_slots(instance_id)
	var removals: Dictionary = {}
	for item_id: String in recipe.inputs:
		var role := _furnace_role_for_item(item_id)
		var stack: Dictionary = slots.get(role, _empty_stack())
		var staged := _furnace_available_operations(instance_id) if role == "fuel" else int(stack.get("count", 0))
		var missing := maxi(0, int(recipe.inputs[item_id]) - staged)
		if missing > 0:
			removals[item_id] = missing
	var removed := inventory.try_transaction(removals, {})
	if not removed.get("ok", false):
		return removed
	for item_id: String in removals:
		_add_to_furnace_unchecked(instance_id, _furnace_role_for_item(item_id), item_id, int(removals[item_id]))
	var result := _result(true, "RECIPE_LOADED", {"instance_id": instance_id, "recipe_id": recipe_id, "furnace_slots": furnace_slots(instance_id)})
	station_changed.emit(result)
	return result


## The three hand-loadable slots of a Furnace - or of a Foundry, whose record
## keeps them under `foundry_slots` as {ore, fuel, output}; here the ore slot
## reads as "input" so the furnace slot gestures (collect, cursor pick and
## deposit, inventory transfer) serve both stations unchanged.
func furnace_slots(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	var entity_id := str(record.get("entity_id", ""))
	if entity_id == "foundry":
		var raw: Variant = record.get("foundry_slots", null)
		var foundry_slots: Dictionary = raw if raw is Dictionary else _empty_foundry_slots()
		return {"input": foundry_slots.get("ore", _empty_stack()).duplicate(true), "fuel": foundry_slots.get("fuel", _empty_stack()).duplicate(true), "output": foundry_slots.get("output", _empty_stack()).duplicate(true)}
	if entity_id != "furnace":
		return _empty_furnace_slots()
	return record.get("furnace_slots", _empty_furnace_slots()).duplicate(true)


## Writes slots read through `furnace_slots` back to the station record.
func _write_furnace_slots(instance_id: String, slots: Dictionary) -> void:
	var record: Dictionary = stations.get(instance_id, {})
	if str(record.get("entity_id", "")) == "foundry":
		record["foundry_slots"] = {"ore": slots.get("input", _empty_stack()), "fuel": slots.get("fuel", _empty_stack()), "output": slots.get("output", _empty_stack())}
		return
	record["furnace_slots"] = slots


func _has_furnace_slots(instance_id: String) -> bool:
	return str(stations.get(instance_id, {}).get("entity_id", "")) in ["furnace", "foundry"]


func furnace_fuel_status(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	if str(record.get("entity_id", "")) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	var operations_per_fuel := _furnace_operations_per_fuel()
	var remaining := clampi(int(record.get("furnace_fuel_operations", 0)), 0, operations_per_fuel - 1)
	return _result(true, "OK", {
		"fuel_item": _furnace_fuel_item(),
		"operations_per_fuel": operations_per_fuel,
		"stored_operations": remaining,
		"burning": _furnace_fuel_burning(record),
		"available_operations": _furnace_available_operations(instance_id),
	})


func furnace_job_status(instance_id: String) -> Dictionary:
	var job: Dictionary = jobs.get(instance_id, {})
	if job.is_empty():
		return {"active": false, "progress": 0.0, "remaining_seconds": 0.0, "duration_seconds": 0.0, "recipe_id": ""}
	var duration := maxf(0.001, float(job.get("duration_seconds", 0.0)))
	var remaining := clampf(float(job.get("remaining_seconds", 0.0)), 0.0, duration)
	return {
		"active": true,
		"progress": clampf(1.0 - remaining / duration, 0.0, 1.0),
		"remaining_seconds": remaining,
		"duration_seconds": duration,
		"recipe_id": str(job.get("recipe_id", "")),
	}


func furnace_autoload_status(instance_id: String, recipe_id: String) -> Dictionary:
	var recipe := registry.recipe(recipe_id)
	if not stations.has(instance_id) or str(stations[instance_id].get("entity_id", "")) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	if recipe.is_empty() or str(recipe.get("station", "")) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	var slots := furnace_slots(instance_id)
	var limit := 64
	var current := 64
	var active_batches := 1 if str(jobs.get(instance_id, {}).get("recipe_id", "")) == recipe_id else 0
	var used_roles: Dictionary = {}
	for item_id: String in recipe.inputs:
		var role := _furnace_role_for_item(item_id)
		if used_roles.has(role):
			return _result(false, "UNSUPPORTED_FURNACE_RECIPE")
		used_roles[role] = true
		var required := maxi(1, int(recipe.inputs[item_id]))
		var stack: Dictionary = slots.get(role, _empty_stack())
		var stack_count := int(stack.get("count", 0)) if str(stack.get("item_id", "")) == item_id else 0
		var available_batches := 0
		var staged_batches := 0
		if role == "fuel":
			var stored_operations := int(stations[instance_id].get("furnace_fuel_operations", 0))
			var burning := _furnace_fuel_burning(stations[instance_id])
			var available_fuel_count := mini(stack_count + inventory.count(item_id), registry.max_stack(item_id))
			available_batches = floori(float(_fuel_operations_for(available_fuel_count, stored_operations, burning)) / float(required))
			staged_batches = floori(float(_fuel_operations_for(stack_count, stored_operations, burning)) / float(required))
		else:
			var available := stack_count + inventory.count(item_id)
			available_batches = floori(float(mini(available, registry.max_stack(item_id))) / float(required))
			staged_batches = floori(float(stack_count) / float(required))
		limit = mini(limit, mini(64, active_batches + available_batches))
		current = mini(current, active_batches + staged_batches)
	if used_roles.is_empty():
		limit = 0
		current = 0
	return _result(true, "OK", {"limit": limit, "current": mini(current, limit), "slots": slots})


func try_set_furnace_autoload_target(instance_id: String, recipe_id: String, requested_batches: int) -> Dictionary:
	var status := furnace_autoload_status(instance_id, recipe_id)
	if not status.get("ok", false):
		return status
	var recipe := registry.recipe(recipe_id)
	var slots := furnace_slots(instance_id)
	var removals: Dictionary = {}
	var additions: Dictionary = {}
	var desired_by_role: Dictionary = {}
	var requested := clampi(requested_batches, 0, 64)
	var active_batches := 1 if str(jobs.get(instance_id, {}).get("recipe_id", "")) == recipe_id else 0
	for item_id: String in recipe.inputs:
		var role := _furnace_role_for_item(item_id)
		var stack: Dictionary = slots.get(role, _empty_stack())
		var stack_id := str(stack.get("item_id", ""))
		if not stack_id.is_empty() and stack_id != item_id:
			return _result(false, "SLOT_OCCUPIED")
		var current := int(stack.get("count", 0))
		var total := current + inventory.count(item_id)
		var desired_operations := maxi(0, requested - active_batches) * maxi(1, int(recipe.inputs[item_id]))
		var desired := 0
		if role == "fuel":
			desired = _fuel_count_for_operations(desired_operations, int(stations[instance_id].get("furnace_fuel_operations", 0)), _furnace_fuel_burning(stations[instance_id]))
		else:
			desired = desired_operations
		desired = mini(desired, mini(total, registry.max_stack(item_id)))
		desired_by_role[role] = {"item_id": item_id, "count": desired}
		if desired > current:
			removals[item_id] = desired - current
		elif desired < current:
			additions[item_id] = current - desired
	var moved := inventory.try_transaction(removals, additions)
	if not moved.get("ok", false):
		return moved
	for role: String in desired_by_role:
		var desired_stack: Dictionary = desired_by_role[role]
		slots[role] = desired_stack if int(desired_stack.count) > 0 else _empty_stack()
	stations[instance_id]["furnace_slots"] = slots
	var refreshed := furnace_autoload_status(instance_id, recipe_id)
	var details: Dictionary = refreshed.get("details", {})
	details["requested"] = requested
	details["furnace_slots"] = slots.duplicate(true)
	var result := _result(true, "AUTOLOAD_UPDATED", details)
	station_changed.emit(result)
	return result


## Round 3: the panel's Load button. Adds up to `batches` recipe inputs from
## the inventory to Raw Input, then tops up Fuel so every staged input is
## funded. Purely additive (never returns items) and moves what is available.
func try_load_furnace_batches(instance_id: String, recipe_id: String, batches: int) -> Dictionary:
	var plan := _furnace_load_plan(instance_id, recipe_id, batches)
	if not plan.get("ok", false):
		return plan
	var details: Dictionary = plan.get("details", {})
	var input_item := str(details.get("input_item", ""))
	var moved: Dictionary = {}
	var failure := "NO_RESOURCE"
	if int(details.get("input_amount", 0)) > 0:
		var transfer := try_transfer_inventory_item_to_furnace(instance_id, input_item, int(details.input_amount))
		if transfer.get("ok", false):
			moved[input_item] = int(transfer.get("details", {}).get("moved", 0))
		else:
			failure = str(transfer.get("reason", failure))
	elif inventory.count(input_item) <= 0:
		failure = "NO_RESOURCE"
	else:
		failure = "STACK_FULL"
	var fuel_item := _furnace_fuel_item()
	var fuel_needed := _furnace_fuel_top_up(instance_id, recipe_id)
	if fuel_needed > 0:
		var fuel_transfer := try_transfer_inventory_item_to_furnace(instance_id, fuel_item, fuel_needed)
		if fuel_transfer.get("ok", false):
			moved[fuel_item] = int(fuel_transfer.get("details", {}).get("moved", 0))
	if moved.is_empty():
		return _result(false, failure, {"item_id": input_item})
	var result := _result(true, "BATCH_LOADED", {"instance_id": instance_id, "recipe_id": recipe_id, "moved": moved, "furnace_slots": furnace_slots(instance_id)})
	station_changed.emit(result)
	return result


## True when Load x1 would move at least one item (input or the Coal owed to
## the staged input) from the inventory.
func can_load_furnace_batch(instance_id: String, recipe_id: String) -> bool:
	var plan := _furnace_load_plan(instance_id, recipe_id, 1)
	if not plan.get("ok", false):
		return false
	var details: Dictionary = plan.get("details", {})
	if int(details.get("input_amount", 0)) > 0:
		return true
	var fuel_needed := _furnace_fuel_top_up(instance_id, recipe_id)
	if fuel_needed <= 0 or inventory.count(_furnace_fuel_item()) <= 0:
		return false
	var fuel_stack: Dictionary = furnace_slots(instance_id).get("fuel", _empty_stack())
	return int(fuel_stack.get("count", 0)) < registry.max_stack(_furnace_fuel_item())


func _furnace_load_plan(instance_id: String, recipe_id: String, batches: int) -> Dictionary:
	if not stations.has(instance_id) or str(stations[instance_id].get("entity_id", "")) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	var recipe := registry.recipe(recipe_id)
	if recipe.is_empty() or str(recipe.get("station", "")) != "furnace":
		return _result(false, "WRONG_WORKSTATION")
	var input_item := ""
	var input_required := 1
	for item_id: String in recipe.inputs:
		if _furnace_role_for_item(item_id) == "fuel":
			continue
		if not input_item.is_empty():
			return _result(false, "UNSUPPORTED_FURNACE_RECIPE")
		input_item = item_id
		input_required = maxi(1, int(recipe.inputs[item_id]))
	if input_item.is_empty():
		return _result(false, "UNSUPPORTED_FURNACE_RECIPE")
	var input_stack: Dictionary = furnace_slots(instance_id).get("input", _empty_stack())
	var staged_id := str(input_stack.get("item_id", ""))
	if not staged_id.is_empty() and staged_id != input_item:
		return _result(false, "SLOT_OCCUPIED", {"item_id": staged_id})
	var room := registry.max_stack(input_item) - int(input_stack.get("count", 0))
	var wanted := mini(maxi(0, batches) * input_required, mini(room, inventory.count(input_item)))
	return _result(true, "OK", {"input_item": input_item, "input_required": input_required, "input_amount": maxi(0, wanted)})


## Coal count that still has to join the Fuel slot so every staged input item
## is funded (0 when the staged Coal already covers it).
func _furnace_fuel_top_up(instance_id: String, recipe_id: String) -> int:
	var recipe := registry.recipe(recipe_id)
	var fuel_item := _furnace_fuel_item()
	var per_batch := maxi(0, int(recipe.get("inputs", {}).get(fuel_item, 0)))
	if per_batch <= 0:
		return 0
	var input_required := 1
	for item_id: String in recipe.inputs:
		if _furnace_role_for_item(item_id) != "fuel":
			input_required = maxi(1, int(recipe.inputs[item_id]))
	var input_stack: Dictionary = furnace_slots(instance_id).get("input", _empty_stack())
	var staged_batches := floori(float(int(input_stack.get("count", 0))) / float(input_required))
	var deficit := staged_batches * per_batch - _furnace_available_operations(instance_id)
	if deficit <= 0:
		return 0
	return ceili(float(deficit) / float(_furnace_operations_per_fuel()))


## Moves up to `amount` of `item_id` from the inventory into its Furnace role
## slot (input for ore, fuel for Coal). Used by click (+1) and Shift+click (+5).
func try_transfer_inventory_item_to_furnace(instance_id: String, item_id: String, amount: int) -> Dictionary:
	var role := _furnace_role_for_item(item_id)
	if role.is_empty():
		return _result(false, "INVALID_FURNACE_INPUT")
	var moved := mini(amount, inventory.count(item_id))
	if moved <= 0:
		return _result(false, "NO_RESOURCE")
	var target: Dictionary = furnace_slots(instance_id).get(role, _empty_stack())
	moved = mini(moved, registry.max_stack(item_id) - int(target.get("count", 0)))
	if moved <= 0:
		return _result(false, "STACK_FULL")
	var allowed := _can_add_to_furnace(instance_id, role, item_id, moved)
	if not allowed.get("ok", false):
		return allowed
	var removed := inventory.try_transaction({item_id: moved}, {})
	if not removed.get("ok", false):
		return removed
	_add_to_furnace_unchecked(instance_id, role, item_id, moved)
	var result := _result(true, "STACK_TRANSFERRED", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "furnace_slots": furnace_slots(instance_id)})
	station_changed.emit(result)
	return result


func try_transfer_inventory_stack_to_furnace(instance_id: String, inventory_index: int) -> Dictionary:
	if inventory_index < 0 or inventory_index >= inventory.slots.size():
		return _result(false, "INVALID_SLOT")
	var source: Dictionary = inventory.slots[inventory_index]
	var item_id := str(source.get("item_id", ""))
	var amount := int(source.get("count", 0))
	var role := _furnace_role_for_item(item_id)
	if role.is_empty():
		return _result(false, "INVALID_FURNACE_INPUT")
	var target: Dictionary = furnace_slots(instance_id).get(role, _empty_stack())
	var target_id := str(target.get("item_id", ""))
	if not target_id.is_empty() and target_id != item_id:
		return _result(false, "SLOT_OCCUPIED")
	amount = mini(amount, maxi(0, registry.max_stack(item_id) - int(target.get("count", 0))))
	if amount <= 0:
		return _result(false, "STACK_FULL")
	var accepted := _can_add_to_furnace(instance_id, role, item_id, amount)
	if not accepted.get("ok", false):
		return accepted
	var taken := inventory.take_from_slot(inventory_index, amount)
	if not taken.get("ok", false):
		return taken
	_add_to_furnace_unchecked(instance_id, role, item_id, amount)
	var result := _result(true, "STACK_TRANSFERRED", {"instance_id": instance_id, "slot": role, "item_id": item_id, "count": amount})
	station_changed.emit(result)
	return result


func try_collect_furnace_stack(instance_id: String, slot_name: String) -> Dictionary:
	if slot_name not in ["input", "fuel", "output"]:
		return _result(false, "INVALID_SLOT")
	var slots := furnace_slots(instance_id)
	var stack: Dictionary = slots.get(slot_name, _empty_stack())
	var item_id := str(stack.get("item_id", ""))
	var amount := int(stack.get("count", 0))
	if item_id.is_empty() or amount <= 0:
		return _result(false, "EMPTY_SLOT")
	var transferable := amount
	while transferable > 0 and not inventory.can_transaction({}, {item_id: transferable}):
		transferable -= 1
	if transferable <= 0:
		return _result(false, "INVENTORY_FULL")
	var added := inventory.try_transaction({}, {item_id: transferable})
	if not added.get("ok", false):
		return added
	var remaining := amount - transferable
	slots[slot_name] = {"item_id": item_id, "count": remaining} if remaining > 0 else _empty_stack()
	_write_furnace_slots(instance_id, slots)
	var result := _result(true, "STACK_COLLECTED", {"instance_id": instance_id, "slot": slot_name, "item_id": item_id, "count": transferable})
	station_changed.emit(result)
	return result


func cursor_pick_furnace_stack(instance_id: String, slot_name: String, half: bool = false) -> Dictionary:
	if slot_name not in ["input", "fuel", "output"]:
		return _result(false, "INVALID_SLOT")
	var slots := furnace_slots(instance_id)
	var stack: Dictionary = slots.get(slot_name, _empty_stack())
	var item_id := str(stack.get("item_id", ""))
	var stack_count := int(stack.get("count", 0))
	if item_id.is_empty() or stack_count <= 0:
		return _result(false, "EMPTY_SLOT")
	var amount := ceili(float(stack_count) / 2.0) if half else stack_count
	var received := inventory.cursor_receive(item_id, amount)
	if not received.get("ok", false):
		return received
	var remaining := stack_count - amount
	slots[slot_name] = {"item_id": item_id, "count": remaining} if remaining > 0 else _empty_stack()
	_write_furnace_slots(instance_id, slots)
	var result := _result(true, "CURSOR_PICKED", {"instance_id": instance_id, "slot": slot_name, "item_id": item_id, "count": amount})
	station_changed.emit(result)
	return result


func cursor_deposit_furnace_stack(instance_id: String, slot_name: String, one: bool = false) -> Dictionary:
	if slot_name not in ["input", "fuel"]:
		return _result(false, "OUTPUT_TAKE_ONLY")
	var item_id := str(inventory.cursor_stack.get("item_id", ""))
	var held_count := int(inventory.cursor_stack.get("count", 0))
	if item_id.is_empty() or held_count <= 0:
		return _result(false, "CURSOR_EMPTY")
	if _furnace_role_for_item(item_id) != slot_name:
		return _result(false, "INVALID_FURNACE_INPUT")
	var amount := 1 if one else held_count
	var accepted := _can_add_to_furnace(instance_id, slot_name, item_id, amount)
	if not accepted.get("ok", false):
		return accepted
	var consumed := inventory.cursor_consume(amount)
	if not consumed.get("ok", false):
		return consumed
	_add_to_furnace_unchecked(instance_id, slot_name, item_id, amount)
	var result := _result(true, "CURSOR_DEPOSITED", {"instance_id": instance_id, "slot": slot_name, "item_id": item_id, "count": amount})
	station_changed.emit(result)
	return result


func advance(delta: float, paused: bool = false) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	if paused or delta <= 0.0:
		return completed
	_auto_start_idle_furnaces()
	for instance_id: String in jobs.keys():
		# Time left over when a job completes carries into the job it chains, so
		# a large step (a long absence, a diagnostic) finishes as many items as the
		# elapsed time funds instead of one per call. Bounded for safety.
		var budget := delta
		var chained := 0
		while jobs.has(instance_id) and budget > 0.0 and chained < 256:
			var job: Dictionary = jobs[instance_id]
			var remaining := float(job.remaining_seconds) - budget
			if remaining > 0.0:
				job.remaining_seconds = remaining
				jobs[instance_id] = job
				break
			budget = -remaining
			job.remaining_seconds = 0.0
			jobs[instance_id] = job
			var recipe := registry.recipe(str(job.recipe_id))
			var outputs: Dictionary = recipe.get("outputs", {}).duplicate(true)
			if inventory.reservations.has(str(job.job_id)):
				var legacy := inventory.claim_reservation(str(job.job_id))
				if not legacy.get("ok", false):
					break
				outputs = legacy.outputs
			var stored := _store_furnace_outputs(instance_id, outputs)
			if not stored.get("ok", false):
				break
			jobs.erase(instance_id)
			# Fuel model 2 (round 3): the Coal that funded this job leaves the Fuel
			# slot only now, when its last job completes, never when a job starts.
			_release_exhausted_fuel(instance_id)
			var result := _result(true, "JOB_COMPLETED", {"instance_id": instance_id, "job_id": job.job_id, "recipe_id": job.recipe_id, "outputs": outputs.duplicate(true), "furnace_slots": furnace_slots(instance_id), "fuel": furnace_fuel_status(instance_id).get("details", {})})
			completed.append(result)
			job_completed.emit(result)
			# A loaded appliance continues one item at a time. Each new job resets the
			# progress bar; it stops naturally on missing input/fuel or blocked output.
			try_start_furnace(instance_id, str(job.recipe_id))
			chained += 1
	return completed


## P3I: a Furnace processes without a manual start. Any idle Furnace whose Raw
## Input matches a furnace recipe, with a stored fuel operation or fuel stack
## and room in Output, starts that recipe. Nothing else changes: the same
## try_start_furnace transaction runs, so input, fuel and output rules hold.
func _auto_start_idle_furnaces() -> void:
	for instance_id: String in stations.keys():
		if jobs.has(instance_id) or str(stations[instance_id].get("entity_id", "")) != "furnace":
			continue
		var raw: Dictionary = stations[instance_id].get("furnace_slots", _empty_furnace_slots()).get("input", _empty_stack())
		var raw_id := str(raw.get("item_id", ""))
		if raw_id.is_empty() or int(raw.get("count", 0)) <= 0:
			continue
		var recipe_id := furnace_recipe_for_input(raw_id)
		if recipe_id.is_empty():
			continue
		try_start_furnace(instance_id, recipe_id)


## The furnace recipe whose non-fuel input is `item_id`, or "" when none.
func furnace_recipe_for_input(item_id: String) -> String:
	for recipe in registry.recipes_for("furnace"):
		for input_id: String in recipe.get("inputs", {}):
			if input_id == item_id and _furnace_role_for_item(input_id) != "fuel":
				return str(recipe.get("id", ""))
	return ""


func station_at_cell(cell: Vector3i) -> String:
	return footprints.owner_at(cell)


func interactable_station_at_cell(cell: Vector3i) -> String:
	var instance_id := footprints.owner_at(cell)
	if instance_id.is_empty():
		return ""
	var record: Dictionary = stations.get(instance_id, {})
	var definition := registry.entity(str(record.get("entity_id", "")))
	return instance_id if not str(definition.get("station_type", "")).is_empty() else ""


func supported_by(cell: Vector3i) -> bool:
	for instance_id: String in stations:
		var record: Dictionary = stations[instance_id]
		var definition := registry.entity(str(record.entity_id))
		for offset in _vector_list(definition.get("support_offsets", [])):
			if record.anchor + footprints.rotate_offset(offset, int(record.rotation_quarters)) == cell:
				return true
	return false


func station(instance_id: String) -> Dictionary:
	return stations.get(instance_id, {}).duplicate(true)


func station_type(instance_id: String) -> String:
	var record: Dictionary = stations.get(instance_id, {})
	return str(registry.entity(str(record.get("entity_id", ""))).get("station_type", ""))


## True for either sign entity (the one-cell sign and the wide board): both
## carry the same `sign` block, the same editor and the same API.
static func is_sign(entity_id: String) -> bool:
	return entity_id in SIGN_ENTITIES


## An empty sign: one text line, no items.
static func default_sign() -> Dictionary:
	var items: Array[String] = []
	return {"mode": "text", "text_a": "", "text_b": "", "items": items}


## The sign block of a placed sign ({} when the station is not a sign).
func sign_data(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	if not is_sign(str(record.get("entity_id", ""))):
		return {}
	var data: Variant = record.get("sign", default_sign())
	return sanitized_sign(data if data is Dictionary else {})


## Writes the sign's content. `data` may carry any subset of mode / text_a /
## text_b / items; whatever it omits keeps its current value. Unknown modes,
## over-long text, unknown item ids and a ninth item are rejected, so a caller
## (the editor panel, an authored Expo fixture) cannot store a record the
## renderer or the save cannot read back.
func configure_sign(instance_id: String, data: Dictionary) -> Dictionary:
	if not stations.has(instance_id):
		return _result(false, "NO_ENTITY")
	var record: Dictionary = stations[instance_id]
	if not is_sign(str(record.get("entity_id", ""))):
		return _result(false, "NOT_A_SIGN")
	var current := sign_data(instance_id)
	var merged := current.duplicate(true)
	if data.has("mode"):
		var mode := str(data.get("mode", ""))
		if mode not in SIGN_MODES:
			return _result(false, "INVALID_SIGN_MODE")
		merged["mode"] = mode
	for field: String in ["text_a", "text_b"]:
		if data.has(field):
			merged[field] = str(data[field])
	if data.has("items"):
		var raw: Variant = data["items"]
		if not raw is Array:
			return _result(false, "INVALID_SIGN_ITEMS")
		var raw_items: Array = raw
		if raw_items.size() > SIGN_ITEM_SLOTS:
			return _result(false, "INVALID_SIGN_ITEMS")
		var clean_items: Array[String] = []
		for value: Variant in raw_items:
			var item_id := str(value)
			if item_id.is_empty():
				continue
			if not registry.items.has(item_id):
				return _result(false, "UNKNOWN_SIGN_ITEM")
			clean_items.append(item_id)
		merged["items"] = clean_items
	record["sign"] = sanitized_sign(merged)
	stations[instance_id] = record
	var result := _result(true, "OK", {"instance_id": instance_id, "sign": sign_data(instance_id)})
	station_changed.emit(result)
	return result


## Normalizes a sign block read from a save, a fixture or the editor: a known
## mode, trimmed text within the limit and at most eight known item ids.
func sanitized_sign(data: Dictionary) -> Dictionary:
	var clean := default_sign()
	var mode := str(data.get("mode", "text"))
	clean["mode"] = mode if mode in SIGN_MODES else "text"
	for field: String in ["text_a", "text_b"]:
		var text := str(data.get(field, ""))
		clean[field] = text.substr(0, SIGN_TEXT_LIMIT)
	var raw: Variant = data.get("items", [])
	var clean_items: Array[String] = []
	if raw is Array:
		for value: Variant in raw as Array:
			var item_id := str(value)
			if item_id.is_empty() or not registry.items.has(item_id) or clean_items.size() >= SIGN_ITEM_SLOTS:
				continue
			clean_items.append(item_id)
	clean["items"] = clean_items
	return clean


## "wall" for a sign hanging on a block's side, "ground" for one on a post.
func sign_mount(instance_id: String) -> String:
	return str(stations.get(instance_id, {}).get("mount", "ground"))


func siege_status(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	if record.is_empty():
		return _result(false, "NO_ENTITY")
	var definition := registry.entity(str(record.get("entity_id", "")))
	var siege: Dictionary = definition.get("siege", {})
	if siege.is_empty():
		return _result(false, "NOT_SIEGE")
	return _result(true, "OK", {
		"instance_id": instance_id,
		"entity_id": str(record.get("entity_id", "")),
		"anchor": record.get("anchor", Vector3i.ZERO),
		"rotation_quarters": int(record.get("rotation_quarters", 0)),
		"ammo": maxi(0, int(record.get("siege_ammo", siege.get("starting_ammo", 0)))),
		"ammo_item": str(record.get("siege_ammo_item", siege.get("ammo_item", ""))),
		"capacity": maxi(1, int(siege.get("capacity", siege.get("starting_ammo", 1)))),
		"stance": str(record.get("siege_stance", "fire_at_will")),
		"target_filter": str(record.get("siege_target_filter", "any")),
		"cooldown": maxf(0.0, float(record.get("siege_cooldown", 0.0))),
		"munition": registry.munition(str(record.get("siege_ammo_item", siege.get("ammo_item", "")))),
		"definition": siege.duplicate(true),
	})


# ---------------------------------------------------------------------------
# P4a-2/3: weapon controls, loading and supply. A weapon holds one munition
# type at a time (siege_ammo_item / siege_ammo up to capacity). The player
# loads it from the inventory; an empty weapon auto-reloads from the nearest
# Chest within supply_radius that holds a compatible munition.
# ---------------------------------------------------------------------------

func siege_set_stance(instance_id: String, stance: String) -> Dictionary:
	if not siege_status(instance_id).get("ok", false):
		return _result(false, "NOT_SIEGE")
	if stance not in ["fire_at_will", "hold", "patrol"]:
		return _result(false, "INVALID_STANCE")
	if stance == "patrol" and float(siege_status(instance_id).get("details", {}).get("definition", {}).get("rail_speed", 0.0)) <= 0.0:
		return _result(false, "NOT_A_RAIL_WEAPON")
	stations[instance_id]["siege_stance"] = stance
	var result := _result(true, "STANCE_SET", {"instance_id": instance_id, "stance": stance})
	station_changed.emit(result)
	return result


func siege_set_target_filter(instance_id: String, target_filter: String) -> Dictionary:
	if not siege_status(instance_id).get("ok", false):
		return _result(false, "NOT_SIEGE")
	if target_filter not in ["any", "raider", "brute", "troll", "structure"]:
		return _result(false, "INVALID_TARGET_FILTER")
	stations[instance_id]["siege_target_filter"] = target_filter
	var result := _result(true, "TARGET_FILTER_SET", {"instance_id": instance_id, "target_filter": target_filter})
	station_changed.emit(result)
	return result


## Loads up to `amount` of `item_id` from the inventory into the weapon.
## Switching munition type is allowed only when the weapon is empty.
func siege_load(instance_id: String, item_id: String, amount: int) -> Dictionary:
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var allowed: Array = details.get("definition", {}).get("ammo_items", [details.get("definition", {}).get("ammo_item", "")])
	if item_id not in allowed:
		return _result(false, "WRONG_AMMUNITION", {"item_id": item_id})
	var loaded := int(details.get("ammo", 0))
	if loaded > 0 and str(details.get("ammo_item", "")) != item_id:
		return _result(false, "AMMO_TYPE_LOADED", {"loaded": str(details.get("ammo_item", ""))})
	var room := int(details.get("capacity", 1)) - loaded
	var moved := mini(amount, mini(room, inventory.count(item_id)))
	if moved <= 0:
		return _result(false, "WEAPON_FULL" if room <= 0 else "NO_RESOURCE")
	var removed := inventory.try_transaction({item_id: moved}, {})
	if not removed.get("ok", false):
		return removed
	stations[instance_id]["siege_ammo_item"] = item_id
	stations[instance_id]["siege_ammo"] = loaded + moved
	var result := _result(true, "AMMO_LOADED", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "ammo": loaded + moved})
	station_changed.emit(result)
	return result


## Storage network card: ammunition that arrived from adjacent storage (no
## inventory involved). Same munition rules as siege_load; returns
## AMMO_RELOADED with the amount, capped at the weapon's capacity.
func siege_receive_ammo(instance_id: String, item_id: String, amount: int) -> Dictionary:
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var allowed: Array = details.get("definition", {}).get("ammo_items", [details.get("definition", {}).get("ammo_item", "")])
	if item_id not in allowed:
		return _result(false, "WRONG_AMMUNITION", {"item_id": item_id})
	var loaded := int(details.get("ammo", 0))
	if loaded > 0 and str(details.get("ammo_item", "")) != item_id:
		return _result(false, "AMMO_TYPE_LOADED", {"loaded": str(details.get("ammo_item", ""))})
	var moved := mini(amount, int(details.get("capacity", 1)) - loaded)
	if moved <= 0:
		return _result(false, "WEAPON_FULL")
	stations[instance_id]["siege_ammo_item"] = item_id
	stations[instance_id]["siege_ammo"] = loaded + moved
	var result := _result(true, "AMMO_RELOADED", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "ammo": loaded + moved, "from": "storage"})
	station_changed.emit(result)
	return result


## Loads the cursor stack (a stack picked up from an inventory tile) into the
## weapon: the whole stack, or one with `one`. Refusals leave the stack held.
func siege_load_from_cursor(instance_id: String, one: bool = false) -> Dictionary:
	var item_id := str(inventory.cursor_stack.get("item_id", ""))
	var held_count := int(inventory.cursor_stack.get("count", 0))
	if item_id.is_empty() or held_count <= 0:
		return _result(false, "CURSOR_EMPTY")
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var allowed: Array = details.get("definition", {}).get("ammo_items", [details.get("definition", {}).get("ammo_item", "")])
	if item_id not in allowed:
		return _result(false, "WRONG_AMMUNITION", {"item_id": item_id})
	var loaded := int(details.get("ammo", 0))
	if loaded > 0 and str(details.get("ammo_item", "")) != item_id:
		return _result(false, "AMMO_TYPE_LOADED", {"loaded": str(details.get("ammo_item", ""))})
	var room := int(details.get("capacity", 1)) - loaded
	var moved := mini(1 if one else held_count, room)
	if moved <= 0:
		return _result(false, "WEAPON_FULL")
	var consumed := inventory.cursor_consume(moved)
	if not consumed.get("ok", false):
		return consumed
	stations[instance_id]["siege_ammo_item"] = item_id
	stations[instance_id]["siege_ammo"] = loaded + moved
	var result := _result(true, "AMMO_LOADED", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "ammo": loaded + moved, "from_cursor": true})
	station_changed.emit(result)
	return result


## Returns the loaded munitions to the inventory (all-or-nothing).
func siege_unload(instance_id: String) -> Dictionary:
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var loaded := int(details.get("ammo", 0))
	var item_id := str(details.get("ammo_item", ""))
	if loaded <= 0 or item_id.is_empty():
		return _result(false, "WEAPON_EMPTY")
	var added := inventory.try_transaction({}, {item_id: loaded})
	if not added.get("ok", false):
		return added
	stations[instance_id]["siege_ammo"] = 0
	var result := _result(true, "AMMO_UNLOADED", {"instance_id": instance_id, "item_id": item_id, "moved": loaded})
	station_changed.emit(result)
	return result


## Chests within the weapon's supply radius holding a compatible munition,
## nearest first: [{instance_id, distance, item_id, count}].
func siege_supply(instance_id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return found
	var details: Dictionary = status.get("details", {})
	var siege: Dictionary = details.get("definition", {})
	var allowed: Array = siege.get("ammo_items", [siege.get("ammo_item", "")])
	var loaded_item := str(details.get("ammo_item", ""))
	var loaded := int(details.get("ammo", 0))
	var radius := float(siege.get("supply_radius", 8.0))
	var origin := Vector3(details.get("anchor", Vector3i.ZERO))
	for chest_id: String in stations.keys():
		var record: Dictionary = stations[chest_id]
		if not record.has("container_slots"):
			continue
		var distance := origin.distance_to(Vector3(record.get("anchor", Vector3i.ZERO)))
		if distance > radius:
			continue
		for stack in record.container_slots:
			var item_id := str(stack.get("item_id", ""))
			var count := int(stack.get("count", 0))
			if count <= 0 or item_id not in allowed:
				continue
			if loaded > 0 and item_id != loaded_item:
				continue
			found.append({"instance_id": chest_id, "distance": distance, "item_id": item_id, "count": count})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return found


## Fills an empty (or partly loaded, same type) weapon from the nearest
## supplying chest. Returns AMMO_RELOADED with the amount, or NO_SUPPLY.
func siege_auto_reload(instance_id: String) -> Dictionary:
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var room := int(details.get("capacity", 1)) - int(details.get("ammo", 0))
	if room <= 0:
		return _result(false, "WEAPON_FULL")
	var supply := siege_supply(instance_id)
	if supply.is_empty():
		return _result(false, "NO_SUPPLY")
	var source: Dictionary = supply[0]
	var taken := container_take(str(source.instance_id), str(source.item_id), room)
	var moved := int(taken.get("details", {}).get("moved", 0))
	if moved <= 0:
		return _result(false, "NO_SUPPLY")
	stations[instance_id]["siege_ammo_item"] = str(source.item_id)
	stations[instance_id]["siege_ammo"] = int(details.get("ammo", 0)) + moved
	var result := _result(true, "AMMO_RELOADED", {"instance_id": instance_id, "from": str(source.instance_id), "item_id": str(source.item_id), "moved": moved, "ammo": stations[instance_id]["siege_ammo"]})
	station_changed.emit(result)
	return result


# ---------------------------------------------------------------------------
# Chest containers: fixed slot list, stack rules from the registry.
# ---------------------------------------------------------------------------

func container_slots(instance_id: String) -> Array:
	var record: Dictionary = stations.get(instance_id, {})
	return record.get("container_slots", []).duplicate(true)


func is_container(instance_id: String) -> bool:
	return stations.get(instance_id, {}).has("container_slots")


## Moves `amount` of `item_id` from the inventory into the chest (merging
## into matching stacks, then empty slots). Moves what fits.
## Stores the cursor stack (whole, or one with `one`) in the container.
func container_deposit_from_cursor(instance_id: String, one: bool = false) -> Dictionary:
	if not is_container(instance_id):
		return _result(false, "NOT_CONTAINER")
	var item_id := str(inventory.cursor_stack.get("item_id", ""))
	var held_count := int(inventory.cursor_stack.get("count", 0))
	if item_id.is_empty() or held_count <= 0:
		return _result(false, "CURSOR_EMPTY")
	var slots: Array = stations[instance_id].container_slots
	var room := 0
	var max_stack := registry.max_stack(item_id)
	for stack in slots:
		if str(stack.get("item_id", "")) == item_id:
			room += max_stack - int(stack.get("count", 0))
		elif str(stack.get("item_id", "")).is_empty():
			room += max_stack
	var moved := mini(1 if one else held_count, room)
	if moved <= 0:
		return _result(false, "CONTAINER_FULL")
	var consumed := inventory.cursor_consume(moved)
	if not consumed.get("ok", false):
		return consumed
	_container_add(slots, item_id, moved, max_stack)
	var result := _result(true, "DEPOSITED", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "container_slots": container_slots(instance_id), "from_cursor": true})
	station_changed.emit(result)
	return result


func container_deposit(instance_id: String, item_id: String, amount: int) -> Dictionary:
	if not is_container(instance_id):
		return _result(false, "NOT_CONTAINER")
	var wanted := mini(amount, inventory.count(item_id))
	if wanted <= 0:
		return _result(false, "NO_RESOURCE")
	var slots: Array = stations[instance_id].container_slots
	var room := 0
	var max_stack := registry.max_stack(item_id)
	for stack in slots:
		if str(stack.get("item_id", "")) == item_id:
			room += max_stack - int(stack.get("count", 0))
		elif str(stack.get("item_id", "")).is_empty():
			room += max_stack
	var moved := mini(wanted, room)
	if moved <= 0:
		return _result(false, "CONTAINER_FULL")
	var removed := inventory.try_transaction({item_id: moved}, {})
	if not removed.get("ok", false):
		return removed
	_container_add(slots, item_id, moved, max_stack)
	var result := _result(true, "DEPOSITED", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "container_slots": container_slots(instance_id)})
	station_changed.emit(result)
	return result


## Room left in the container for `item_id` (matching stacks, then empty slots).
func container_room(instance_id: String, item_id: String) -> int:
	if not is_container(instance_id):
		return 0
	var room := 0
	var max_stack := registry.max_stack(item_id)
	for stack in stations[instance_id].container_slots:
		if str(stack.get("item_id", "")) == item_id:
			room += max_stack - int(stack.get("count", 0))
		elif str(stack.get("item_id", "")).is_empty():
			room += max_stack
	return room


## Alias of `container_put` (the mining card's name for it).
func container_insert(instance_id: String, item_id: String, amount: int) -> Dictionary:
	return container_put(instance_id, item_id, amount)


## Moves `amount` of `item_id` from the chest into the inventory.
func container_withdraw(instance_id: String, item_id: String, amount: int) -> Dictionary:
	if not is_container(instance_id):
		return _result(false, "NOT_CONTAINER")
	var available := container_count(instance_id, item_id)
	var moved := mini(amount, available)
	if moved <= 0:
		return _result(false, "NO_RESOURCE")
	var added := inventory.try_transaction({}, {item_id: moved})
	if not added.get("ok", false):
		return added
	_container_remove(stations[instance_id].container_slots, item_id, moved)
	var result := _result(true, "WITHDRAWN", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "container_slots": container_slots(instance_id)})
	station_changed.emit(result)
	return result


func container_count(instance_id: String, item_id: String) -> int:
	var total := 0
	for stack in stations.get(instance_id, {}).get("container_slots", []):
		if str(stack.get("item_id", "")) == item_id:
			total += int(stack.get("count", 0))
	return total


## Takes up to `amount` of `item_id` out of the chest for another consumer
## (auto-reload). Does not touch the player inventory.
func container_take(instance_id: String, item_id: String, amount: int) -> Dictionary:
	if not is_container(instance_id):
		return _result(false, "NOT_CONTAINER")
	var moved := mini(amount, container_count(instance_id, item_id))
	if moved <= 0:
		return _result(false, "NO_RESOURCE")
	_container_remove(stations[instance_id].container_slots, item_id, moved)
	var result := _result(true, "TAKEN", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "container_slots": container_slots(instance_id)})
	station_changed.emit(result)
	return result


## Puts up to `amount` of `item_id` into the container from another producer
## (industry wave 1: the foundry's ingots, a cart's cargo). Does not touch the
## player inventory. Moves what fits; CONTAINER_FULL when nothing does.
func container_put(instance_id: String, item_id: String, amount: int) -> Dictionary:
	if not is_container(instance_id):
		return _result(false, "NOT_CONTAINER")
	if item_id.is_empty() or registry.item(item_id).is_empty():
		return _result(false, "UNKNOWN_ITEM")
	var moved := mini(amount, container_room(instance_id, item_id))
	if moved <= 0:
		return _result(false, "CONTAINER_FULL")
	_container_add(stations[instance_id].container_slots, item_id, moved, registry.max_stack(item_id))
	var result := _result(true, "PUT", {"instance_id": instance_id, "item_id": item_id, "moved": moved, "container_slots": container_slots(instance_id)})
	station_changed.emit(result)
	return result


func _container_add(slots: Array, item_id: String, amount: int, max_stack: int) -> void:
	var remaining := amount
	for stack in slots:
		if remaining <= 0:
			break
		if str(stack.get("item_id", "")) == item_id:
			var add := mini(remaining, max_stack - int(stack.get("count", 0)))
			stack["count"] = int(stack.get("count", 0)) + add
			remaining -= add
	for stack in slots:
		if remaining <= 0:
			break
		if str(stack.get("item_id", "")).is_empty():
			var add := mini(remaining, max_stack)
			stack["item_id"] = item_id
			stack["count"] = add
			remaining -= add


func _container_remove(slots: Array, item_id: String, amount: int) -> void:
	var remaining := amount
	for stack in slots:
		if remaining <= 0:
			break
		if str(stack.get("item_id", "")) != item_id:
			continue
		var take := mini(remaining, int(stack.get("count", 0)))
		stack["count"] = int(stack.get("count", 0)) - take
		remaining -= take
		if int(stack.get("count", 0)) <= 0:
			stack["item_id"] = ""
			stack["count"] = 0


func advance_siege_cooldowns(delta: float) -> void:
	if delta <= 0.0:
		return
	for instance_id: String in stations:
		var status := siege_status(instance_id)
		if not status.get("ok", false):
			continue
		stations[instance_id]["siege_cooldown"] = maxf(0.0, float(stations[instance_id].get("siege_cooldown", 0.0)) - delta)


func commit_siege_shot(instance_id: String) -> Dictionary:
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	if int(details.get("ammo", 0)) <= 0:
		return _result(false, "NO_AMMO")
	if float(details.get("cooldown", 0.0)) > 0.0:
		return _result(false, "RELOADING")
	var siege: Dictionary = details.get("definition", {})
	stations[instance_id]["siege_ammo"] = int(details.get("ammo", 0)) - 1
	stations[instance_id]["siege_cooldown"] = maxf(0.05, float(siege.get("cooldown_seconds", 1.0)))
	return _result(true, "SHOT_COMMITTED", {"instance_id": instance_id, "ammo": stations[instance_id]["siege_ammo"], "cooldown": stations[instance_id]["siege_cooldown"]})


## Defence sets: is this station a gate, and is its leaf drawn back?
func is_gate(instance_id: String) -> bool:
	return is_gate_entity(str(stations.get(instance_id, {}).get("entity_id", "")))


## Any size of leaf in the gate family (Gate, Double Gate, Great Gate).
static func is_gate_entity(entity_id: String) -> bool:
	return entity_id in GATE_ENTITIES


## Any size of gate frame.
static func is_gate_frame_entity(entity_id: String) -> bool:
	return entity_id in GATE_FRAME_ENTITIES


## A leaf's opening in cells, read from its own footprint: 1 x 2 Gate,
## 2 x 3 Double Gate, 4 x 4 Great Gate. Nothing about a size is hard-coded.
func gate_opening(entity_id: String) -> Vector2i:
	var width := 0
	var height := 0
	for offset: Vector3i in _vector_list(registry.entity(entity_id).get("occupied_offsets", [])):
		width = maxi(width, offset.x + 1)
		height = maxi(height, offset.y + 1)
	return Vector2i(maxi(1, width), maxi(1, height))


func gate_is_open(instance_id: String) -> bool:
	return bool(stations.get(instance_id, {}).get("gate_open", false))


## Every gate standing right now, open or shut (diagnostics and the HUD).
func gate_ids() -> Array[String]:
	var ids: Array[String] = []
	for instance_id: String in stations.keys():
		if is_gate(instance_id):
			ids.append(instance_id)
	return ids


## Right-click on a gate: draw the leaf back or drop it again. The result
## carries `occupied_cells` so `GameSession._on_station_changed` hands them to
## the navigation services - a gate that just opened has to invalidate the
## raiders' snapshot exactly as a destroyed barricade does, or they keep
## routing around a hole that is now there.
func toggle_gate(instance_id: String) -> Dictionary:
	if not stations.has(instance_id):
		return _result(false, "NO_ENTITY")
	if not is_gate(instance_id):
		return _result(false, "NOT_A_GATE")
	return set_gate_open(instance_id, not gate_is_open(instance_id))


func set_gate_open(instance_id: String, open: bool) -> Dictionary:
	if not stations.has(instance_id):
		return _result(false, "NO_ENTITY")
	if not is_gate(instance_id):
		return _result(false, "NOT_A_GATE")
	var record: Dictionary = stations[instance_id]
	record["gate_open"] = open
	var definition := registry.entity(str(record.get("entity_id", GATE_ENTITY)))
	var cells: Array[Vector3i] = []
	for offset: Vector3i in _vector_list(definition.get("occupied_offsets", [])):
		cells.append(record.anchor + footprints.rotate_offset(offset, int(record.rotation_quarters)))
	var result := _result(true, "GATE_OPENED" if open else "GATE_CLOSED", {
		"instance_id": instance_id,
		"entity_id": str(record.get("entity_id", GATE_ENTITY)),
		"anchor": record.anchor,
		"gate_open": open,
		"occupied_cells": cells,
	})
	station_changed.emit(result)
	return result


func navigation_cell_data(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	if record.is_empty():
		return {"state": "LOADED", "solid": false}
	if bool(record.get("gate_open", false)):
		# An open gate is a doorway: the cells still belong to the gate (you
		# cannot build in them) but nothing walks into them, so to the planner
		# they read exactly like the air a destroyed barricade leaves behind.
		return {"state": "LOADED", "solid": false, "voxel_id": 0, "material_id": "air", "source": "entity", "source_id": instance_id, "tags": [], "integrity": 0, "protected": false}
	var entity_id := str(record.get("entity_id", ""))
	var definition := registry.entity(entity_id)
	var navigation: Dictionary = definition.get("navigation", {})
	var tags: Array = navigation.get("material_tags", [])
	if tags.is_empty() and registry.item_category(entity_id) == "building":
		tags = ["stone", "fortification"]
	var integrity := int(record.get("integrity", navigation.get("integrity", 1)))
	return {
		"state": "LOADED",
		"solid": true,
		"voxel_id": -1,
		"material_id": entity_id,
		"source": "entity",
		"source_id": instance_id,
		"tags": tags.duplicate(),
		"integrity": maxi(1, integrity),
		"protected": tags.is_empty(),
	}


func defense_status(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	if record.is_empty():
		return _result(false, "NO_ENTITY")
	var definition := registry.entity(str(record.get("entity_id", "")))
	var defense_definition: Dictionary = definition.get("defense", {})
	if defense_definition.is_empty():
		return _result(false, "NOT_DAMAGEABLE")
	var maximum := maxi(1, int(defense_definition.get("max_integrity", 1)))
	return _result(true, "OK", {
		"instance_id": instance_id,
		"entity_id": str(record.get("entity_id", "")),
		"integrity": clampi(int(record.get("integrity", maximum)), 1, maximum),
		"max_integrity": maximum,
		"repair_item": str(defense_definition.get("repair_item", "")),
		"repair_amount": maxi(1, int(defense_definition.get("repair_amount", 1))),
	})


func try_damage(instance_id: String, amount: int) -> Dictionary:
	if amount <= 0:
		return _result(false, "INVALID_DAMAGE")
	var status := defense_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var before := int(details.get("integrity", 1))
	var after := maxi(0, before - amount)
	if after > 0:
		stations[instance_id]["integrity"] = after
		var damaged := _result(true, "DAMAGED", {
			"instance_id": instance_id,
			"entity_id": details.get("entity_id", ""),
			"integrity_before": before,
			"integrity": after,
			"max_integrity": details.get("max_integrity", before),
		})
		station_changed.emit(damaged)
		return damaged
	var record: Dictionary = stations[instance_id]
	var released := footprints.release_at(record.anchor)
	if not released.get("ok", false):
		return released
	stations.erase(instance_id)
	jobs.erase(instance_id)
	var destroyed := _result(true, "DESTROYED", {
		"instance_id": instance_id,
		"entity_id": details.get("entity_id", ""),
		"integrity_before": before,
		"integrity": 0,
		"max_integrity": details.get("max_integrity", before),
		"destroyed": true,
		"refund": {},
		"occupied_cells": released.get("details", {}).get("released_cells", []).duplicate(),
	})
	station_changed.emit(destroyed)
	return destroyed


## Authored fixture restore (docs/DEVELOPMENT_EXPO.md, reset groups): puts a
## station back to full integrity with no item cost, because the Development
## Expo's scenarios rebuild what they own rather than being repaired by hand.
## Reports the same REPAIRED result the ordinary repair does, so the visual and
## the save record follow.
func restore_integrity(instance_id: String) -> Dictionary:
	var status := defense_status(instance_id)
	if not status.get("ok", false):
		return status
	var details: Dictionary = status.get("details", {})
	var before := int(details.get("integrity", 1))
	var maximum := int(details.get("max_integrity", before))
	if before >= maximum:
		return _result(true, "NO_REPAIR_NEEDED", {"instance_id": instance_id, "integrity": before, "max_integrity": maximum})
	stations[instance_id]["integrity"] = maximum
	var repaired := _result(true, "REPAIRED", {
		"instance_id": instance_id,
		"entity_id": details.get("entity_id", ""),
		"integrity_before": before,
		"integrity": maximum,
		"max_integrity": maximum,
	})
	station_changed.emit(repaired)
	return repaired


## Authored fixture restore: a siege weapon goes back to the clip its sheet
## opens with, in its default munition. No inventory and no storage involved.
func restore_siege_ammo(instance_id: String) -> Dictionary:
	var status := siege_status(instance_id)
	if not status.get("ok", false):
		return status
	var definition: Dictionary = status.get("details", {}).get("definition", {})
	var item_id := str(definition.get("ammo_item", ""))
	var ammo := clampi(int(definition.get("starting_ammo", 0)), 0, maxi(1, int(definition.get("capacity", 1))))
	stations[instance_id]["siege_ammo_item"] = item_id
	stations[instance_id]["siege_ammo"] = ammo
	stations[instance_id]["siege_cooldown"] = 0.0
	var result := _result(true, "AMMO_RESTORED", {"instance_id": instance_id, "item_id": item_id, "ammo": ammo})
	station_changed.emit(result)
	return result


func try_repair_structure(instance_id: String) -> Dictionary:
	var status := defense_status(instance_id)
	if not status.get("ok", false):
		return {"handled": false}
	var details: Dictionary = status.get("details", {})
	var before := int(details.get("integrity", 1))
	var maximum := int(details.get("max_integrity", before))
	if before >= maximum:
		return {"handled": true, "ok": false, "reason": "NO_REPAIR_NEEDED"}
	var repair_item := str(details.get("repair_item", ""))
	if repair_item.is_empty() or inventory.count(repair_item) < 1:
		return {"handled": true, "ok": false, "reason": "MISSING_REPAIR_MATERIAL"}
	var committed := inventory.try_transaction({repair_item: 1}, {})
	if not committed.get("ok", false):
		return {"handled": true, "ok": false, "reason": str(committed.get("reason", "REPAIR_FAILED"))}
	var after := mini(maximum, before + int(details.get("repair_amount", 1)))
	stations[instance_id]["integrity"] = after
	var repaired := _result(true, "REPAIRED", {
		"instance_id": instance_id,
		"entity_id": details.get("entity_id", ""),
		"integrity_before": before,
		"integrity": after,
		"max_integrity": maximum,
		"consumed": {repair_item: 1},
	})
	station_changed.emit(repaired)
	return {"handled": true, "ok": true, "reason": "REPAIRED", "changes": repaired.get("details", {})}


func snapshot() -> Dictionary:
	var station_list: Array[Dictionary] = []
	for record: Dictionary in stations.values():
		var clean := record.duplicate(true)
		clean.anchor = [record.anchor.x, record.anchor.y, record.anchor.z]
		station_list.append(clean)
	return {"stations": station_list, "jobs": jobs.duplicate(true), "next_instance": _next_instance, "next_job": _next_job}


func restore(data: Dictionary, world_query: Callable) -> Dictionary:
	stations.clear()
	jobs.clear()
	footprints = EntityFootprintService.new()
	# Lost-Core Continue (docs/DEVELOPMENT_EXPO.md): one unreadable station
	# record drops that station and is reported in `skipped`; it never fails
	# the whole load, which used to leave Continue on the loading screen.
	var skipped: Array[Dictionary] = []
	for value in data.get("stations", []):
		var restored := _restored_station(value, world_query)
		if not restored.get("ok", false):
			skipped.append({"reason": str(restored.get("reason", "INVALID_STATION_SNAPSHOT")), "entity_id": str(restored.get("entity_id", "")), "instance_id": str(restored.get("instance_id", ""))})
			continue
		var record: Dictionary = restored.get("record", {})
		stations[str(record.instance_id)] = record
	var restored_jobs: Variant = data.get("jobs", {})
	if not restored_jobs is Dictionary:
		return _result(false, "INVALID_STATION_SNAPSHOT")
	for instance_id: String in restored_jobs:
		if not restored_jobs[instance_id] is Dictionary:
			return _result(false, "INVALID_STATION_SNAPSHOT")
		if not stations.has(instance_id):
			# Its station was dropped above; the job goes with it.
			continue
		jobs[instance_id] = restored_jobs[instance_id].duplicate(true)
	_next_instance = maxi(1, int(data.get("next_instance", 1)))
	_next_job = maxi(1, int(data.get("next_job", 1)))
	return _result(true, "OK", {"skipped": skipped})


## One saved station record, validated and normalised. Returns {ok, reason,
## record}: `ok` false means that record is dropped (the caller records it),
## never that the save is unreadable.
func _restored_station(value: Variant, world_query: Callable) -> Dictionary:
	if not value is Dictionary or not value.get("anchor") is Array or value.anchor.size() != 3:
		return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
	var record: Dictionary = value.duplicate(true)
	record.anchor = Vector3i(int(value.anchor[0]), int(value.anchor[1]), int(value.anchor[2]))
	var definition := registry.entity(str(record.get("entity_id", "")))
	if definition.is_empty():
		return {"ok": false, "reason": "MISSING_CONTENT"}
	var defense_definition: Dictionary = definition.get("defense", {})
	if not defense_definition.is_empty():
		# A saved integrity outside the sheet's range is normalised, not fatal:
		# a station that reached 0 was erased when it was destroyed, so a
		# record like that is stale bookkeeping, never a corrupt save.
		var maximum := maxi(1, int(defense_definition.get("max_integrity", 1)))
		record["integrity"] = clampi(int(record.get("integrity", maximum)), 1, maximum)
	var siege_definition: Dictionary = definition.get("siege", {})
	if not siege_definition.is_empty():
		var maximum_ammo := maxi(0, int(siege_definition.get("starting_ammo", 0)))
		var siege_ammo := int(record.get("siege_ammo", maximum_ammo))
		var siege_cooldown := float(record.get("siege_cooldown", 0.0))
		if siege_ammo < 0 or siege_ammo > maximum_ammo or siege_cooldown < 0.0:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		record["siege_ammo"] = siege_ammo
		record["siege_cooldown"] = siege_cooldown
		var allowed_ammo: Array = siege_definition.get("ammo_items", [siege_definition.get("ammo_item", "")])
		var ammo_item := str(record.get("siege_ammo_item", siege_definition.get("ammo_item", "")))
		if ammo_item not in allowed_ammo:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		record["siege_ammo_item"] = ammo_item
		var stance := str(record.get("siege_stance", "fire_at_will"))
		# `patrol` (P4C rail weapons) was missing here, so a kettle saved while
		# patrolling came back as a dropped record; the rail turret made that
		# visible (docs/DEFENSE_SETS.md).
		if stance not in ["fire_at_will", "hold", "patrol"]:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		record["siege_stance"] = stance
		record["siege_target_filter"] = str(record.get("siege_target_filter", "any"))
	if int(definition.get("container_slots", 0)) > 0:
		var raw_container: Variant = record.get("container_slots", [])
		if not raw_container is Array:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		var clean_container: Array = []
		for raw_stack in raw_container:
			var clean_stack := _validated_stack(raw_stack)
			if clean_stack.is_empty():
				return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
			clean_container.append(clean_stack)
		while clean_container.size() < int(definition.get("container_slots", 0)):
			clean_container.append(_empty_stack())
		record["container_slots"] = clean_container
	if is_sign(str(record.get("entity_id", ""))):
		# Migration: a sign saved before the editor existed (or an authored
		# record without the block) comes back as an empty single-text sign.
		var raw_sign: Variant = record.get("sign", default_sign())
		record["sign"] = sanitized_sign(raw_sign if raw_sign is Dictionary else {})
	if is_gate_entity(str(record.get("entity_id", ""))):
		# Defence sets: a gate remembers whether it stands open. A record from
		# before the field existed comes back shut, which is the safe reading.
		record["gate_open"] = bool(record.get("gate_open", false))
	if str(record.get("entity_id", "")) == "mine_cart":
		# Hauling (docs/INDUSTRY.md): the cart's cargo, item_id -> count.
		var raw_cargo: Variant = record.get("cargo", {})
		if not raw_cargo is Dictionary:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		var clean_cargo: Dictionary = {}
		for cargo_item in raw_cargo.keys():
			var cargo_count := int(raw_cargo[cargo_item])
			if not registry.items.has(str(cargo_item)) or cargo_count < 0:
				return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
			if cargo_count > 0:
				clean_cargo[str(cargo_item)] = cargo_count
		record["cargo"] = clean_cargo
	if str(record.get("entity_id", "")) == "foundry":
		# Storage network card: a record from before the slots existed gets
		# empty ones; a present block must hold valid stacks in their roles.
		var raw_foundry: Variant = record.get("foundry_slots", _empty_foundry_slots())
		if not raw_foundry is Dictionary:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		var clean_foundry := _empty_foundry_slots()
		for slot_name in ["ore", "fuel", "output"]:
			var clean_stack := _validated_stack(raw_foundry.get(slot_name, _empty_stack()))
			if clean_stack.is_empty():
				return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
			var role := _furnace_role_for_item(str(clean_stack.get("item_id", "")))
			if not str(clean_stack.get("item_id", "")).is_empty() and slot_name != "output" and role != ("input" if slot_name == "ore" else slot_name):
				return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
			clean_foundry[slot_name] = clean_stack
		record["foundry_slots"] = clean_foundry
	if str(record.get("entity_id", "")) == "furnace":
		var raw_slots: Variant = record.get("furnace_slots", _empty_furnace_slots())
		if not raw_slots is Dictionary:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		var clean_slots := _empty_furnace_slots()
		for slot_name in ["input", "fuel", "output"]:
			var clean_stack := _validated_stack(raw_slots.get(slot_name, _empty_stack()))
			if clean_stack.is_empty():
				return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
			if not str(clean_stack.get("item_id", "")).is_empty() and slot_name != "output" and _furnace_role_for_item(str(clean_stack.item_id)) != slot_name:
				return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
			clean_slots[slot_name] = clean_stack
		record["furnace_slots"] = clean_slots
		var operations_per_fuel := _furnace_operations_per_fuel()
		var stored_operations := int(record.get("furnace_fuel_operations", 0))
		if stored_operations < 0 or stored_operations >= operations_per_fuel:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		record["furnace_fuel_operations"] = stored_operations
		# Round 3: `furnace_fuel_burning` marks the lit Coal at the top of the
		# stack. Records saved before the field existed are lit exactly when
		# operations remain on the Coal.
		var burning_value: Variant = record.get("furnace_fuel_burning", stored_operations > 0)
		if not burning_value is bool:
			return {"ok": false, "reason": "INVALID_STATION_SNAPSHOT"}
		var burning: bool = burning_value or stored_operations > 0
		var restored_fuel: Dictionary = clean_slots.get("fuel", _empty_stack())
		if str(restored_fuel.get("item_id", "")) != _furnace_fuel_item() or int(restored_fuel.get("count", 0)) <= 0:
			# No Coal in the slot: nothing is lit (legacy model-1 records get
			# their Coal back below and are re-lit there).
			burning = false
		record["furnace_fuel_burning"] = burning
		# Fuel model 1 removed the burning Coal from the slot; model 2 keeps it.
		# Put the burning Coal back for legacy records so no operations are lost.
		if int(record.get("fuel_model", 1)) < 2 and stored_operations > 0:
			var legacy_fuel: Dictionary = clean_slots.get("fuel", _empty_stack())
			var fuel_item := _furnace_fuel_item()
			if str(legacy_fuel.get("item_id", "")).is_empty():
				clean_slots["fuel"] = {"item_id": fuel_item, "count": 1}
			elif str(legacy_fuel.get("item_id", "")) == fuel_item and int(legacy_fuel.get("count", 0)) < registry.max_stack(fuel_item):
				clean_slots["fuel"] = {"item_id": fuel_item, "count": int(legacy_fuel.get("count", 0)) + 1}
			record["furnace_slots"] = clean_slots
			record["furnace_fuel_burning"] = true
		record["fuel_model"] = 2
	var offsets := _vector_list(definition.occupied_offsets)
	var rotation := int(record.get("rotation_quarters", 0))
	# A wall-mounted record (a sign, a lantern) hangs on a block's side and
	# never had ground under it, so it restores without support offsets.
	var restore_support: Array = [] if str(record.get("mount", "")) == "wall" else _vector_list(definition.support_offsets)
	var reserved := footprints.try_reserve(str(record.instance_id), record.anchor, offsets, rotation, world_query, AABB(), restore_support)
	if not reserved.get("ok", false):
		# The cells no longer pass a placement check (the ground under the
		# station was dug or blasted away, its chunk is not streamed in yet).
		# The station existed when the game was saved, so it comes back where
		# it stood; only a collision with an already restored station drops it.
		var forced := footprints.force_reserve(str(record.instance_id), record.anchor, offsets, rotation)
		if not forced.get("ok", false):
			return {"ok": false, "reason": str(forced.get("reason", "INVALID_STATION_SNAPSHOT")), "entity_id": str(record.get("entity_id", "")), "instance_id": str(record.get("instance_id", "")), "details": reserved}
	return {"ok": true, "reason": "OK", "record": record}
func _vector_list(values: Array) -> Array:
	var vectors: Array = []
	for value in values:
		if value is Array and value.size() == 3:
			vectors.append(Vector3i(int(value[0]), int(value[1]), int(value[2])))
	return vectors


## Linear pieces (rails, walkway slabs, merlons) turn to follow a neighbour
## of the same kind: a piece beside one along x lies along x, else along z.
func _aligned_rotation(entity_id: String, anchor: Vector3i, requested: int) -> int:
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]:
		var neighbour := station_at_cell(anchor + offset)
		if not neighbour.is_empty() and str(stations[neighbour].get("entity_id", "")) == entity_id:
			return 1
	for offset in [Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var neighbour := station_at_cell(anchor + offset)
		if not neighbour.is_empty() and str(stations[neighbour].get("entity_id", "")) == entity_id:
			return 0
	return requested


## A gate frame's opening: the cells between its jambs and under its lintel.
## They are deliberately NOT part of the frame - you walk through them - so
## nothing else would have stopped a player from raising a gateway around a
## boulder, or around another building, and only finding out when the leaf
## refused to hang. Gates card 2 asks placement to refuse the site instead, so
## the frame checks its own opening is clear before it goes up.
func gate_frame_opening_offsets(entity_id: String) -> Array:
	var offsets: Array = []
	if not is_gate_frame_entity(entity_id):
		return offsets
	var definition := registry.entity(entity_id)
	var sockets: Array = definition.get("mount_sockets", [])
	if sockets.is_empty():
		return offsets
	var socket_offset: Array = (sockets[0] as Dictionary).get("offset", [])
	if socket_offset.size() < 1:
		return offsets
	var jamb := int(roundf(float(socket_offset[0])))
	var width := 0
	var height := 0
	for offset: Vector3i in _vector_list(definition.get("occupied_offsets", [])):
		width = maxi(width, offset.x + 1)
		height = maxi(height, offset.y + 1)
	for x in range(jamb, width - jamb):
		for y in range(height - 1):
			offsets.append(Vector3i(x, y, 0))
	return offsets


func _gate_frame_opening_clear(entity_id: String, anchor: Vector3i, rotation_quarters: int, world_query: Callable) -> bool:
	for offset: Vector3i in gate_frame_opening_offsets(entity_id):
		var cell: Vector3i = anchor + footprints.rotate_offset(offset, rotation_quarters)
		var owner := footprints.owner_at(cell)
		# A leaf already hanging there is not a blockage: the Expo's reset
		# re-raises a fortification's frame around the gate still standing in
		# it, and a leaf can only be there because a frame was.
		if not owner.is_empty() and not is_gate(owner):
			return false
		var query: Dictionary = world_query.call(cell)
		if str(query.get("state", "")) != "LOADED" or int(query.get("voxel_id", 0)) != 0:
			return false
	return true


func _validate_mount(definition: Dictionary, anchor: Vector3i, rotation_quarters: int, world_query: Callable) -> Dictionary:
	var mount: Dictionary = definition.get("mount", {})
	if mount.is_empty():
		return _result(true, "OK")
	var allowed: Array = mount.get("allowed", [])
	var support_offsets := _vector_list(definition.get("support_offsets", []))
	var support_owners: Dictionary = {}
	var terrain_supports := 0
	for offset: Vector3i in support_offsets:
		var support_cell := anchor + footprints.rotate_offset(offset, rotation_quarters)
		var owner := footprints.owner_at(support_cell)
		if owner.is_empty():
			var query: Dictionary = world_query.call(support_cell)
			if query.get("state") == "LOADED" and int(query.get("voxel_id", 0)) != 0:
				terrain_supports += 1
		else:
			support_owners[owner] = true
	if terrain_supports == support_offsets.size() and allowed.has("ground"):
		return _result(true, "OK", {"mount": "ground"})
	if allowed.has("ground") and allowed.size() <= 2 and not allowed.has("light_siege") and not allowed.has("rail_mount") and terrain_supports + support_owners.size() >= 1 and support_offsets.size() == 1:
		# Small 1x1 pieces (torches, lights) stand on any solid top, entity or voxel.
		return _result(true, "OK", {"mount": "ground"})
	if terrain_supports == 0 and support_owners.size() == 1:
		var owner_id := str(support_owners.keys()[0])
		var owner_record: Dictionary = stations.get(owner_id, {})
		var owner_definition := registry.entity(str(owner_record.get("entity_id", "")))
		for socket_value in owner_definition.get("mount_sockets", []):
			if socket_value is Dictionary and allowed.has(str(socket_value.get("type", ""))):
				return _result(true, "OK", {"mount": str(socket_value.get("type", "")), "owner": owner_id, "socket": str(socket_value.get("id", ""))})
	return _result(false, "INVALID_MOUNT")


func _result(ok: bool, reason: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "reason": reason, "details": details}


func _furnace_role_for_item(item_id: String) -> String:
	if item_id == _furnace_fuel_item():
		return "fuel"
	for recipe in registry.recipes_for("furnace"):
		if recipe.get("inputs", {}).has(item_id):
			return "input"
	return ""


func _furnace_fuel_item() -> String:
	return registry.balance_string("furnace.fuel_item", "coal")


func _furnace_operations_per_fuel() -> int:
	return maxi(1, registry.balance_integer("furnace.operations_per_fuel", 1))


## Fuel model 2 (owner direction 2026-09-18, round 3): the burning Coal stays in
## the Fuel slot until the last job it funds COMPLETES. `furnace_fuel_operations`
## counts the operations still unspent on the Coal at the top of the stack and
## `furnace_fuel_burning` marks that Coal as lit; a lit Coal with 0 operations
## left is still funding the running job and funds nothing further. The stack
## count includes the lit Coal.
func _fuel_operations_for(stack_count: int, stored_operations: int, burning: bool) -> int:
	if stack_count <= 0:
		return 0
	if burning or stored_operations > 0:
		return maxi(0, stored_operations) + (stack_count - 1) * _furnace_operations_per_fuel()
	return stack_count * _furnace_operations_per_fuel()


## Coal count needed so that `operations` are funded, given the burning Coal.
func _fuel_count_for_operations(operations: int, stored_operations: int, burning: bool) -> int:
	var lit := burning or stored_operations > 0
	if operations <= 0:
		return 1 if lit else 0
	if lit:
		return 1 + ceili(float(maxi(0, operations - maxi(0, stored_operations))) / float(_furnace_operations_per_fuel()))
	return ceili(float(operations) / float(_furnace_operations_per_fuel()))


func _furnace_fuel_burning(record: Dictionary) -> bool:
	var burning: bool = bool(record.get("furnace_fuel_burning", false))
	return burning or int(record.get("furnace_fuel_operations", 0)) > 0


func _furnace_available_operations(instance_id: String) -> int:
	var record: Dictionary = stations.get(instance_id, {})
	var slots: Dictionary = record.get("furnace_slots", _empty_furnace_slots())
	var fuel: Dictionary = slots.get("fuel", _empty_stack())
	var fuel_count := int(fuel.get("count", 0)) if str(fuel.get("item_id", "")) == _furnace_fuel_item() else 0
	return _fuel_operations_for(fuel_count, maxi(0, int(record.get("furnace_fuel_operations", 0))), _furnace_fuel_burning(record))


## Spends one operation for a job that is starting. Lights a fresh Coal when
## none is burning; the Coal is never removed here (see _release_exhausted_fuel).
func _consume_furnace_operation(instance_id: String) -> void:
	var slots := furnace_slots(instance_id)
	var fuel: Dictionary = slots.get("fuel", _empty_stack())
	if str(fuel.get("item_id", "")) != _furnace_fuel_item() or int(fuel.get("count", 0)) <= 0:
		stations[instance_id]["furnace_fuel_operations"] = 0
		stations[instance_id]["furnace_fuel_burning"] = false
		return
	var remaining := maxi(0, int(stations[instance_id].get("furnace_fuel_operations", 0)))
	if remaining <= 0:
		if _furnace_fuel_burning(stations[instance_id]):
			# Defensive: an exhausted lit Coal that was never released leaves now.
			_release_exhausted_fuel(instance_id)
			slots = furnace_slots(instance_id)
			fuel = slots.get("fuel", _empty_stack())
			if str(fuel.get("item_id", "")) != _furnace_fuel_item() or int(fuel.get("count", 0)) <= 0:
				return
		remaining = _furnace_operations_per_fuel()
	remaining -= 1
	stations[instance_id]["furnace_fuel_operations"] = remaining
	stations[instance_id]["furnace_fuel_burning"] = true


## Removes the lit Coal once it has no operations left and the job it funded
## has completed. Called from advance() before the next job chains.
func _release_exhausted_fuel(instance_id: String) -> void:
	var record: Dictionary = stations.get(instance_id, {})
	if not _furnace_fuel_burning(record) or int(record.get("furnace_fuel_operations", 0)) > 0:
		return
	var slots := furnace_slots(instance_id)
	var fuel: Dictionary = slots.get("fuel", _empty_stack())
	if str(fuel.get("item_id", "")) == _furnace_fuel_item() and int(fuel.get("count", 0)) > 0:
		var taken := _take_from_stack(fuel, 1)
		if taken.get("ok", false):
			slots["fuel"] = taken.stack
			stations[instance_id]["furnace_slots"] = slots
	stations[instance_id]["furnace_fuel_operations"] = 0
	stations[instance_id]["furnace_fuel_burning"] = false


func _can_add_to_furnace(instance_id: String, slot_name: String, item_id: String, amount: int) -> Dictionary:
	if not _has_furnace_slots(instance_id):
		return _result(false, "WRONG_WORKSTATION")
	if amount <= 0 or slot_name not in ["input", "fuel"] or _furnace_role_for_item(item_id) != slot_name:
		return _result(false, "INVALID_FURNACE_INPUT")
	var target: Dictionary = furnace_slots(instance_id).get(slot_name, _empty_stack())
	var target_id := str(target.get("item_id", ""))
	if not target_id.is_empty() and target_id != item_id:
		return _result(false, "SLOT_OCCUPIED")
	if int(target.get("count", 0)) + amount > registry.max_stack(item_id):
		return _result(false, "STACK_FULL")
	return _result(true, "OK")


func _add_to_furnace_unchecked(instance_id: String, slot_name: String, item_id: String, amount: int) -> void:
	var slots := furnace_slots(instance_id)
	var target: Dictionary = slots.get(slot_name, _empty_stack())
	slots[slot_name] = {"item_id": item_id, "count": int(target.get("count", 0)) + amount}
	_write_furnace_slots(instance_id, slots)


func _store_furnace_outputs(instance_id: String, outputs: Dictionary) -> Dictionary:
	if outputs.size() != 1:
		return _result(false, "INVALID_FURNACE_RECIPE")
	var item_id := str(outputs.keys()[0])
	var amount := int(outputs[item_id])
	var slots := furnace_slots(instance_id)
	var output: Dictionary = slots.get("output", _empty_stack())
	if not str(output.get("item_id", "")).is_empty() and str(output.get("item_id", "")) != item_id:
		return _result(false, "OUTPUT_BLOCKED")
	if int(output.get("count", 0)) + amount > registry.max_stack(item_id):
		return _result(false, "OUTPUT_BLOCKED")
	slots["output"] = {"item_id": item_id, "count": int(output.get("count", 0)) + amount}
	stations[instance_id]["furnace_slots"] = slots
	return _result(true, "OK")


func _take_from_stack(stack: Dictionary, amount: int) -> Dictionary:
	if amount <= 0 or int(stack.get("count", 0)) < amount:
		return _result(false, "INSUFFICIENT_INPUT")
	var remaining := int(stack.get("count", 0)) - amount
	return {"ok": true, "reason": "OK", "stack": {"item_id": str(stack.get("item_id", "")), "count": remaining} if remaining > 0 else _empty_stack()}


func _furnace_is_empty(record: Dictionary) -> bool:
	var slots: Dictionary = record.get("furnace_slots", _empty_furnace_slots())
	for stack: Dictionary in slots.values():
		if not str(stack.get("item_id", "")).is_empty():
			return false
	return true


func _validated_stack(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var item_id := str(value.get("item_id", ""))
	var count := int(value.get("count", 0))
	if item_id.is_empty() and count == 0:
		return _empty_stack()
	if registry.max_stack(item_id) <= 0 or count <= 0 or count > registry.max_stack(item_id):
		return {}
	return {"item_id": item_id, "count": count}


static func _empty_stack() -> Dictionary:
	return {"item_id": "", "count": 0}


static func _empty_furnace_slots() -> Dictionary:
	return {"input": _empty_stack(), "fuel": _empty_stack(), "output": _empty_stack()}


static func _empty_foundry_slots() -> Dictionary:
	return {"ore": _empty_stack(), "fuel": _empty_stack(), "output": _empty_stack()}
