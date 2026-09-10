class_name InteractionService
extends RefCounted

signal result_reported(result: Dictionary)

const AIR := 0
const GRASS := 1
const DIRT := 2
const BEDROCK := 9

var world: WorldAdapter
var inventory: F0Inventory
var player_body_aabb: Callable


func _init(world_adapter: WorldAdapter, player_inventory: F0Inventory, body_aabb: Callable) -> void:
	world = world_adapter
	inventory = player_inventory
	player_body_aabb = body_aabb


func try_break_cell(cell: Vector3i, expected_world_revision: int = -1) -> Dictionary:
	if expected_world_revision >= 0 and expected_world_revision != world.revision:
		return _finish(false, "STALE_REVISION")
	var query := world.query_cell(cell)
	if query.get("state") != "LOADED":
		return _finish(false, query.get("state", "UNLOADED"))
	var voxel_id := int(query.get("voxel_id", AIR))
	if voxel_id == AIR:
		return _finish(false, "NO_TARGET")
	if voxel_id == BEDROCK:
		return _finish(false, "PROTECTED")
	if voxel_id != GRASS and voxel_id != DIRT:
		return _finish(false, "WRONG_TOOL")
	if not inventory.can_add_dirt(1):
		return _finish(false, "INVENTORY_FULL")
	if not world.set_cell(cell, AIR):
		return _finish(false, "WORLD_WRITE_FAILED")
	if not inventory.add_dirt(1):
		world.set_cell(cell, voxel_id)
		return _finish(false, "INVENTORY_COMMIT_FAILED")
	return _finish(true, "OK", {"cell": cell, "voxel_before": voxel_id, "voxel_after": AIR, "dirt_delta": 1})


func try_place_dirt(cell: Vector3i, expected_world_revision: int = -1) -> Dictionary:
	if expected_world_revision >= 0 and expected_world_revision != world.revision:
		return _finish(false, "STALE_REVISION")
	var query := world.query_cell(cell)
	if query.get("state") != "LOADED":
		return _finish(false, query.get("state", "UNLOADED"))
	if int(query.get("voxel_id", AIR)) != AIR:
		return _finish(false, "OCCUPIED")
	if player_body_aabb.is_valid() and player_body_aabb.call().intersects(AABB(Vector3(cell), Vector3.ONE)):
		return _finish(false, "PLAYER_OVERLAP")
	var support := world.query_cell(cell + Vector3i.DOWN)
	if support.get("state") != "LOADED":
		return _finish(false, support.get("state", "UNLOADED"))
	if int(support.get("voxel_id", AIR)) == AIR:
		return _finish(false, "UNSUPPORTED")
	if not inventory.can_remove_dirt(1):
		return _finish(false, "NO_RESOURCE")
	if not world.set_cell(cell, DIRT):
		return _finish(false, "WORLD_WRITE_FAILED")
	if not inventory.remove_dirt(1):
		world.set_cell(cell, AIR)
		return _finish(false, "INVENTORY_COMMIT_FAILED")
	return _finish(true, "OK", {"cell": cell, "voxel_before": AIR, "voxel_after": DIRT, "dirt_delta": -1})


func break_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	var hit := world.raycast(origin, direction)
	if hit == null:
		return _finish(false, "NO_TARGET")
	return try_break_cell(hit.position)


func place_from_view(origin: Vector3, direction: Vector3) -> Dictionary:
	var hit := world.raycast(origin, direction)
	if hit == null:
		return _finish(false, "NO_TARGET")
	return try_place_dirt(hit.previous_position)


func _finish(ok: bool, reason: String, changes: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": ok,
		"reason": reason,
		"changes": changes,
		"world_revision": world.revision,
		"inventory_revision": inventory.revision,
		"dirt": inventory.dirt,
	}
	result_reported.emit(result)
	return result

