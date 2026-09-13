class_name NavigationSnapshot
extends RefCounted

var region := AABB()
var source_revision := 0
var capture_usec := 0
var estimated_bytes := 0
var cells: Dictionary = {}


func capture(source_region: AABB, cell_query: Callable, revision: int) -> Dictionary:
	if not cell_query.is_valid() or source_region.size.x <= 0.0 or source_region.size.y <= 0.0 or source_region.size.z <= 0.0:
		return {"ok": false, "reason": "INVALID_CAPTURE"}
	region = source_region
	source_revision = revision
	cells.clear()
	var started := Time.get_ticks_usec()
	var minimum := Vector3i(floori(region.position.x), floori(region.position.y), floori(region.position.z))
	var maximum := minimum + Vector3i(floori(region.size.x), floori(region.size.y), floori(region.size.z))
	var unloaded := 0
	for y in range(minimum.y, maximum.y):
		for z in range(minimum.z, maximum.z):
			for x in range(minimum.x, maximum.x):
				var cell := Vector3i(x, y, z)
				var value: Dictionary = cell_query.call(cell)
				if str(value.get("state", "UNLOADED")) != "LOADED":
					unloaded += 1
				cells[cell] = value.duplicate(true)
	capture_usec = Time.get_ticks_usec() - started
	# This is an explicit planning estimate, not a process-memory measurement.
	# It gives the spike a stable scale indicator while Dictionary overhead remains
	# engine/version dependent.
	estimated_bytes = cells.size() * 96
	return {
		"ok": unloaded == 0,
		"reason": "OK" if unloaded == 0 else "UNLOADED",
		"cells": cells.size(),
		"unloaded": unloaded,
		"capture_usec": capture_usec,
		"estimated_bytes": estimated_bytes,
		"source_revision": source_revision,
	}


func refresh_cells(changed_cells: Array, cell_query: Callable, revision: int) -> Dictionary:
	if not cell_query.is_valid() or revision < source_revision:
		return {"ok": false, "reason": "INVALID_REFRESH", "source_revision": source_revision}
	var started := Time.get_ticks_usec()
	var refreshed := 0
	var unique: Dictionary = {}
	for value in changed_cells:
		if value is Vector3i and cells.has(value):
			unique[value] = true
	for cell: Vector3i in unique:
		var refreshed_value: Dictionary = cell_query.call(cell)
		cells[cell] = refreshed_value.duplicate(true)
		refreshed += 1
	source_revision = revision
	return {
		"ok": true,
		"reason": "OK",
		"refreshed_cells": refreshed,
		"refresh_usec": Time.get_ticks_usec() - started,
		"source_revision": source_revision,
	}


func query_cell(cell: Vector3i) -> Dictionary:
	return cells.get(cell, {"state": "OUT_OF_BOUNDS", "solid": true})


func contains(cell: Vector3i) -> bool:
	return cells.has(cell)
