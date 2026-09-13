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
	return footprints.validate_placement("preview", anchor, _vector_list(definition.get("occupied_offsets", [])), rotation_quarters, world_query, player_aabb, _vector_list(definition.get("support_offsets", [])))


func try_place(entity_id: String, anchor: Vector3i, world_query: Callable, player_aabb: AABB, rotation_quarters: int = 0) -> Dictionary:
	var definition := registry.entity(entity_id)
	if definition.is_empty():
		return _result(false, "UNKNOWN_ENTITY")
	if inventory.count(entity_id) < 1:
		return _result(false, "NO_RESOURCE")
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
	var defense_definition: Dictionary = definition.get("defense", {})
	if not defense_definition.is_empty():
		record["integrity"] = maxi(1, int(defense_definition.get("max_integrity", 1)))
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
	var job_id := "job_%04d" % _next_job
	var reservation := inventory.try_reserve_and_remove(job_id, recipe.inputs, recipe.outputs)
	if not reservation.get("ok", false):
		return reservation
	_next_job += 1
	jobs[instance_id] = {"job_id": job_id, "recipe_id": recipe_id, "remaining_seconds": float(recipe.duration_seconds), "duration_seconds": float(recipe.duration_seconds), "completed": false}
	var result := _result(true, "JOB_STARTED", {"instance_id": instance_id, "job": jobs[instance_id].duplicate(true)})
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
		var committed := inventory.commit_reservation(str(job.job_id))
		if not committed.get("ok", false):
			continue
		jobs.erase(instance_id)
		var result := _result(true, "JOB_COMPLETED", {"instance_id": instance_id, "job_id": job.job_id, "recipe_id": job.recipe_id, "outputs": committed.outputs})
		completed.append(result)
		job_completed.emit(result)
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


func _result(ok: bool, reason: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "reason": reason, "details": details}
