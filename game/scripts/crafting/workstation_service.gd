class_name WorkstationService
extends RefCounted

signal station_changed(result: Dictionary)
signal job_completed(result: Dictionary)

var registry: ContentRegistry
var inventory: F0Inventory
var footprints := EntityFootprintService.new()
var stations: Dictionary = {}
var jobs: Dictionary = {}
var _next_instance := 1
var _next_job := 1


func _init(content_registry: ContentRegistry, player_inventory: F0Inventory) -> void:
	registry = content_registry
	inventory = player_inventory


func preview_placement(entity_id: String, anchor: Vector3i, rotation_quarters: int, world_query: Callable, player_aabb: AABB) -> Dictionary:
	var definition := registry.entity(entity_id)
	if definition.is_empty():
		return _result(false, "UNKNOWN_ENTITY")
	var validated := footprints.validate_placement("preview", anchor, _vector_list(definition.get("occupied_offsets", [])), rotation_quarters, world_query, player_aabb, _vector_list(definition.get("support_offsets", [])))
	if not validated.get("ok", false):
		return validated
	return _validate_mount(definition, anchor, rotation_quarters, world_query)


func try_place(entity_id: String, anchor: Vector3i, world_query: Callable, player_aabb: AABB, rotation_quarters: int = 0) -> Dictionary:
	var definition := registry.entity(entity_id)
	if definition.is_empty():
		return _result(false, "UNKNOWN_ENTITY")
	if inventory.count(entity_id) < 1:
		return _result(false, "NO_RESOURCE")
	var mount_result := _validate_mount(definition, anchor, rotation_quarters, world_query)
	if not mount_result.get("ok", false):
		return mount_result
	var instance_id := "%s_%04d" % [entity_id, _next_instance]
	var reserved := footprints.try_reserve(instance_id, anchor, _vector_list(definition.get("occupied_offsets", [])), rotation_quarters, world_query, player_aabb, _vector_list(definition.get("support_offsets", [])))
	if not reserved.get("ok", false):
		return reserved
	var consumed := inventory.try_transaction({entity_id: 1}, {})
	if not consumed.get("ok", false):
		footprints.release_at(anchor)
		return _result(false, consumed.get("reason", "INVENTORY_COMMIT_FAILED"))
	_next_instance += 1
	var record := {"instance_id": instance_id, "entity_id": entity_id, "anchor": anchor, "rotation_quarters": posmod(rotation_quarters, 4)}
	if entity_id == "furnace":
		record["furnace_slots"] = _empty_furnace_slots()
	var defense_definition: Dictionary = definition.get("defense", {})
	if not defense_definition.is_empty():
		record["integrity"] = maxi(1, int(defense_definition.get("max_integrity", 1)))
	var siege_definition: Dictionary = definition.get("siege", {})
	if not siege_definition.is_empty():
		record["siege_ammo"] = maxi(0, int(siege_definition.get("starting_ammo", 0)))
		record["siege_cooldown"] = 0.0
	stations[instance_id] = record
	var result := _result(true, "OK", {"station": stations[instance_id].duplicate(true), "consumed_item": entity_id, "occupied_cells": reserved.get("details", {}).get("cells", []).duplicate()})
	station_changed.emit(result)
	return result


func try_dismantle(instance_id: String, world_query: Callable, player_aabb: AABB) -> Dictionary:
	if not stations.has(instance_id):
		return _result(false, "NO_ENTITY")
	if jobs.has(instance_id):
		return _result(false, "STATION_BUSY")
	var record: Dictionary = stations[instance_id]
	if str(record.get("entity_id", "")) == "furnace" and not _furnace_is_empty(record):
		return _result(false, "STATION_NOT_EMPTY")
	var item_id := str(record.entity_id)
	if not inventory.can_transaction({}, {item_id: 1}):
		return _result(false, "INVENTORY_FULL")
	var released := footprints.release_at(record.anchor)
	if not released.get("ok", false):
		return released
	var granted := inventory.try_transaction({}, {item_id: 1})
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
		var taken := _take_from_stack(slots.get(role, _empty_stack()), int(recipe.inputs[item_id]))
		if not taken.get("ok", false):
			return taken
		slots[role] = taken.stack
	stations[instance_id]["furnace_slots"] = slots
	_next_job += 1
	jobs[instance_id] = {"job_id": job_id, "recipe_id": recipe_id, "remaining_seconds": float(recipe.duration_seconds), "duration_seconds": float(recipe.duration_seconds), "completed": false}
	var result := _result(true, "JOB_STARTED", {"instance_id": instance_id, "job": jobs[instance_id].duplicate(true), "furnace_slots": slots.duplicate(true)})
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
		var missing := maxi(0, int(recipe.inputs[item_id]) - int(stack.get("count", 0)))
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
		var missing := maxi(0, int(recipe.inputs[item_id]) - int(stack.get("count", 0)))
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


func furnace_slots(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	if str(record.get("entity_id", "")) != "furnace":
		return _empty_furnace_slots()
	return record.get("furnace_slots", _empty_furnace_slots()).duplicate(true)


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
	var limit := 0
	var current := 0
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
		var available := stack_count + inventory.count(item_id)
		limit = maxi(limit, mini(64, active_batches + floori(float(mini(available, registry.max_stack(item_id))) / float(required))))
		current = maxi(current, active_batches + ceili(float(stack_count) / float(required)))
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
		var desired := mini(maxi(0, requested - active_batches) * maxi(1, int(recipe.inputs[item_id])), mini(total, registry.max_stack(item_id)))
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
	stations[instance_id]["furnace_slots"] = slots
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
	stations[instance_id]["furnace_slots"] = slots
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
	for instance_id: String in jobs.keys():
		var job: Dictionary = jobs[instance_id]
		job.remaining_seconds = maxf(0.0, float(job.remaining_seconds) - delta)
		jobs[instance_id] = job
		if float(job.remaining_seconds) > 0.0:
			continue
		var recipe := registry.recipe(str(job.recipe_id))
		var outputs: Dictionary = recipe.get("outputs", {}).duplicate(true)
		if inventory.reservations.has(str(job.job_id)):
			var legacy := inventory.claim_reservation(str(job.job_id))
			if not legacy.get("ok", false):
				continue
			outputs = legacy.outputs
		var stored := _store_furnace_outputs(instance_id, outputs)
		if not stored.get("ok", false):
			continue
		jobs.erase(instance_id)
		var result := _result(true, "JOB_COMPLETED", {"instance_id": instance_id, "job_id": job.job_id, "recipe_id": job.recipe_id, "outputs": outputs.duplicate(true), "furnace_slots": furnace_slots(instance_id)})
		completed.append(result)
		job_completed.emit(result)
		# A loaded appliance continues one item at a time. Each new job resets the
		# progress bar; it stops naturally on missing input/fuel or blocked output.
		try_start_furnace(instance_id, str(job.recipe_id))
	return completed


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
		"cooldown": maxf(0.0, float(record.get("siege_cooldown", 0.0))),
		"definition": siege.duplicate(true),
	})


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


func navigation_cell_data(instance_id: String) -> Dictionary:
	var record: Dictionary = stations.get(instance_id, {})
	if record.is_empty():
		return {"state": "LOADED", "solid": false}
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
	for value in data.get("stations", []):
		if not value is Dictionary or not value.get("anchor") is Array or value.anchor.size() != 3:
			return _result(false, "INVALID_STATION_SNAPSHOT")
		var record: Dictionary = value.duplicate(true)
		record.anchor = Vector3i(int(value.anchor[0]), int(value.anchor[1]), int(value.anchor[2]))
		var definition := registry.entity(str(record.get("entity_id", "")))
		if definition.is_empty():
			return _result(false, "MISSING_CONTENT")
		var defense_definition: Dictionary = definition.get("defense", {})
		if not defense_definition.is_empty():
			var maximum := maxi(1, int(defense_definition.get("max_integrity", 1)))
			var integrity := int(record.get("integrity", maximum))
			if integrity <= 0 or integrity > maximum:
				return _result(false, "INVALID_STATION_SNAPSHOT")
			record["integrity"] = integrity
		var siege_definition: Dictionary = definition.get("siege", {})
		if not siege_definition.is_empty():
			var maximum_ammo := maxi(0, int(siege_definition.get("starting_ammo", 0)))
			var siege_ammo := int(record.get("siege_ammo", maximum_ammo))
			var siege_cooldown := float(record.get("siege_cooldown", 0.0))
			if siege_ammo < 0 or siege_ammo > maximum_ammo or siege_cooldown < 0.0:
				return _result(false, "INVALID_STATION_SNAPSHOT")
			record["siege_ammo"] = siege_ammo
			record["siege_cooldown"] = siege_cooldown
		if str(record.get("entity_id", "")) == "furnace":
			var raw_slots: Variant = record.get("furnace_slots", _empty_furnace_slots())
			if not raw_slots is Dictionary:
				return _result(false, "INVALID_STATION_SNAPSHOT")
			var clean_slots := _empty_furnace_slots()
			for slot_name in ["input", "fuel", "output"]:
				var clean_stack := _validated_stack(raw_slots.get(slot_name, _empty_stack()))
				if clean_stack.is_empty():
					return _result(false, "INVALID_STATION_SNAPSHOT")
				if not str(clean_stack.get("item_id", "")).is_empty() and slot_name != "output" and _furnace_role_for_item(str(clean_stack.item_id)) != slot_name:
					return _result(false, "INVALID_STATION_SNAPSHOT")
				clean_slots[slot_name] = clean_stack
			record["furnace_slots"] = clean_slots
		var reserved := footprints.try_reserve(str(record.instance_id), record.anchor, _vector_list(definition.occupied_offsets), int(record.get("rotation_quarters", 0)), world_query, AABB(), _vector_list(definition.support_offsets))
		if not reserved.get("ok", false):
			return _result(false, "INVALID_STATION_SNAPSHOT", reserved)
		stations[str(record.instance_id)] = record
	var restored_jobs: Variant = data.get("jobs", {})
	if not restored_jobs is Dictionary:
		return _result(false, "INVALID_STATION_SNAPSHOT")
	for instance_id: String in restored_jobs:
		if not stations.has(instance_id) or not restored_jobs[instance_id] is Dictionary:
			return _result(false, "INVALID_STATION_SNAPSHOT")
		jobs[instance_id] = restored_jobs[instance_id].duplicate(true)
	_next_instance = maxi(1, int(data.get("next_instance", 1)))
	_next_job = maxi(1, int(data.get("next_job", 1)))
	return _result(true, "OK")


func _vector_list(values: Array) -> Array:
	var vectors: Array = []
	for value in values:
		if value is Array and value.size() == 3:
			vectors.append(Vector3i(int(value[0]), int(value[1]), int(value[2])))
	return vectors


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
	if item_id == "coal":
		return "fuel"
	for recipe in registry.recipes_for("furnace"):
		if recipe.get("inputs", {}).has(item_id):
			return "input"
	return ""


func _can_add_to_furnace(instance_id: String, slot_name: String, item_id: String, amount: int) -> Dictionary:
	if not stations.has(instance_id) or str(stations[instance_id].get("entity_id", "")) != "furnace":
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
	stations[instance_id]["furnace_slots"] = slots


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
