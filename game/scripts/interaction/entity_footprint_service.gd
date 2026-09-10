class_name EntityFootprintService
extends RefCounted

const AIR := 0

var _cell_owners: Dictionary = {}
var _instances: Dictionary = {}


func try_reserve(
	instance_id: String,
	anchor: Vector3i,
	offsets: Array,
	rotation_quarters: int,
	world_query: Callable,
	player_aabb: AABB = AABB(),
	required_support: Array = []
) -> Dictionary:
	if instance_id.is_empty():
		return _result(false, "INVALID_INSTANCE")
	if _instances.has(instance_id):
		return _result(false, "DUPLICATE_INSTANCE")
	if offsets.is_empty() or not world_query.is_valid():
		return _result(false, "INVALID_FOOTPRINT")

	var cells: Array[Vector3i] = []
	for offset_value in offsets:
		if not offset_value is Vector3i:
			return _result(false, "INVALID_FOOTPRINT")
		var cell := anchor + rotate_offset(offset_value, rotation_quarters)
		if cells.has(cell):
			return _result(false, "INVALID_FOOTPRINT")
		cells.append(cell)

	for cell in cells:
		var query: Dictionary = world_query.call(cell)
		if query.get("state") != "LOADED":
			return _result(false, str(query.get("state", "UNLOADED")), {"cell": cell})
		if int(query.get("voxel_id", AIR)) != AIR or _cell_owners.has(cell):
			return _result(false, "OCCUPIED", {"cell": cell})
		if player_aabb.has_volume() and player_aabb.intersects(AABB(Vector3(cell), Vector3.ONE)):
			return _result(false, "PLAYER_OVERLAP", {"cell": cell})

	for support_value in required_support:
		if not support_value is Vector3i:
			return _result(false, "INVALID_SUPPORT")
		var support_cell := anchor + rotate_offset(support_value, rotation_quarters)
		var support_query: Dictionary = world_query.call(support_cell)
		if support_query.get("state") != "LOADED":
			return _result(false, str(support_query.get("state", "UNLOADED")), {"cell": support_cell})
		if int(support_query.get("voxel_id", AIR)) == AIR and not _cell_owners.has(support_cell):
			return _result(false, "UNSUPPORTED", {"cell": support_cell})

	for cell in cells:
		_cell_owners[cell] = instance_id
	_instances[instance_id] = {
		"instance_id": instance_id,
		"anchor": anchor,
		"rotation_quarters": posmod(rotation_quarters, 4),
		"cells": cells.duplicate(),
	}
	return _result(true, "OK", _instances[instance_id])


func release_at(cell: Vector3i) -> Dictionary:
	if not _cell_owners.has(cell):
		return _result(false, "NO_ENTITY")
	var instance_id := str(_cell_owners[cell])
	var record: Dictionary = _instances.get(instance_id, {})
	var cells: Array = record.get("cells", [])
	for owned_cell in cells:
		if _cell_owners.get(owned_cell) == instance_id:
			_cell_owners.erase(owned_cell)
	_instances.erase(instance_id)
	return _result(true, "OK", {"instance_id": instance_id, "released_cells": cells.duplicate(), "drop_count": 1})


func owner_at(cell: Vector3i) -> String:
	return str(_cell_owners.get(cell, ""))


func reservation_count() -> int:
	return _instances.size()


func occupied_cell_count() -> int:
	return _cell_owners.size()


func rotate_offset(offset: Vector3i, rotation_quarters: int) -> Vector3i:
	match posmod(rotation_quarters, 4):
		1:
			return Vector3i(-offset.z, offset.y, offset.x)
		2:
			return Vector3i(-offset.x, offset.y, -offset.z)
		3:
			return Vector3i(offset.z, offset.y, -offset.x)
		_:
			return offset


func _result(ok: bool, reason: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "reason": reason, "details": details}
