class_name LocalGridPathfinder
extends RefCounted

const DIRECTIONS: Array[Vector3i] = [
	Vector3i(-1, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(0, 0, -1),
	Vector3i(0, 0, 1),
]


func find_route(snapshot: NavigationSnapshot, start: Vector3i, goal: Vector3i, capability: Dictionary = {}) -> Dictionary:
	var started := Time.get_ticks_usec()
	var max_step_up := maxi(0, int(capability.get("max_step_up", 1)))
	var max_drop_down := maxi(0, int(capability.get("max_drop_down", 1)))
	var standable_cache: Dictionary = {}
	if not _is_standable(snapshot, start, standable_cache) or not _is_standable(snapshot, goal, standable_cache):
		return _finish(false, "INVALID_ENDPOINT", [], [], started)

	var open: Array[Vector3i] = [start]
	var closed: Dictionary = {}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}
	var visited: Array[Vector3i] = []
	while not open.is_empty():
		var current_index := _lowest_score_index(open, f_score)
		var current: Vector3i = open[current_index]
		open.remove_at(current_index)
		if closed.has(current):
			continue
		closed[current] = true
		visited.append(current)
		if current == goal:
			return _finish(true, "OK", _reconstruct(came_from, current), visited, started)
		for neighbor: Vector3i in _neighbors(snapshot, current, max_step_up, max_drop_down, standable_cache):
			if closed.has(neighbor):
				continue
			var height_cost := 0.25 * absf(float(neighbor.y - current.y))
			var tentative := float(g_score.get(current, INF)) + 1.0 + height_cost
			if tentative >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _heuristic(neighbor, goal)
			if not open.has(neighbor):
				open.append(neighbor)
	return _finish(false, "NO_ROUTE", [], visited, started)


func plan_next(snapshot: NavigationSnapshot, start: Vector3i, goal: Vector3i, capability: Dictionary = {}) -> Dictionary:
	var route := find_route(snapshot, start, goal, capability)
	if route.get("ok", false):
		return route
	if str(route.get("reason", "")) not in ["NO_ROUTE", "INVALID_ENDPOINT"]:
		return route
	var action := _best_attack_action(snapshot, route.get("visited", []), goal, capability)
	if action.is_empty():
		return route
	return {
		"ok": true,
		"reason": "ATTACK_OBSTRUCTION",
		"path": [],
		"visited": route.get("visited", []),
		"elapsed_usec": route.get("elapsed_usec", 0),
		"action": action,
	}


func validate_route(snapshot: NavigationSnapshot, path: Array, capability: Dictionary = {}) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "reason": "EMPTY_PATH", "stuck_index": 0}
	var max_step_up := maxi(0, int(capability.get("max_step_up", 1)))
	var max_drop_down := maxi(0, int(capability.get("max_drop_down", 1)))
	var standable_cache: Dictionary = {}
	for index in range(path.size()):
		var cell: Vector3i = path[index]
		if not _is_standable(snapshot, cell, standable_cache):
			return {"ok": false, "reason": "BLOCKED_CELL", "stuck_index": index, "cell": cell}
		if index == 0:
			continue
		var previous: Vector3i = path[index - 1]
		var horizontal := absi(cell.x - previous.x) + absi(cell.z - previous.z)
		var vertical := cell.y - previous.y
		if horizontal != 1 or vertical > max_step_up or -vertical > max_drop_down:
			return {"ok": false, "reason": "INVALID_TRANSITION", "stuck_index": index, "cell": cell}
	return {"ok": true, "reason": "OK", "steps": path.size() - 1, "stuck_cases": 0}


func _neighbors(snapshot: NavigationSnapshot, current: Vector3i, max_step_up: int, max_drop_down: int, standable_cache: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for direction: Vector3i in DIRECTIONS:
		var heights: Array[int] = [0]
		for rise in range(1, max_step_up + 1):
			heights.append(rise)
		for drop in range(1, max_drop_down + 1):
			heights.append(-drop)
		for delta_y: int in heights:
			var candidate := current + direction + Vector3i(0, delta_y, 0)
			if _is_standable(snapshot, candidate, standable_cache):
				result.append(candidate)
				break
	return result


func _is_standable(snapshot: NavigationSnapshot, feet: Vector3i, cache: Dictionary) -> bool:
	if cache.has(feet):
		return bool(cache[feet])
	var feet_data := snapshot.query_cell(feet)
	var head_data := snapshot.query_cell(feet + Vector3i.UP)
	var floor_data := snapshot.query_cell(feet + Vector3i.DOWN)
	var result := _is_open(feet_data) and _is_open(head_data) and _is_solid(floor_data)
	cache[feet] = result
	return result


func _is_open(data: Dictionary) -> bool:
	return str(data.get("state", "UNLOADED")) == "LOADED" and not bool(data.get("solid", true))


func _is_solid(data: Dictionary) -> bool:
	return str(data.get("state", "UNLOADED")) == "LOADED" and bool(data.get("solid", false))


## The obstruction a blocked unit attacks. This runs only when no route to the
## goal exists, which is exactly the state the owner's rule 3 describes: the
## unit attacks the weakest obstacle it can reach.
##
## `capability.prefer_weakest` (docs/TRAPS.md) switches the choice from "the
## obstruction nearest the goal" to "the one with the least integrity left,
## whatever it is made of", and is also what makes **traps** eligible at all:
## a trap is undetected (rule 1) and a unit that still has a route never gets
## here. Traps are walkable cells, so they are candidates without being solid.
## The tie-breaks are the old distance score and then the cell coordinates, so
## the choice is deterministic and costs one pass over the visited frontier.
func _best_attack_action(snapshot: NavigationSnapshot, visited: Array, goal: Vector3i, capability: Dictionary) -> Dictionary:
	var damage_by_tag: Dictionary = capability.get("damage_per_hit", {})
	if damage_by_tag.is_empty():
		return {}
	var prefer_weakest := bool(capability.get("prefer_weakest", false))
	var best: Dictionary = {}
	var best_score := INF
	var best_integrity := INF
	var best_cell := Vector3i.MAX
	for value in visited:
		var from: Vector3i = value
		for direction: Vector3i in DIRECTIONS:
			for height in [0, 1]:
				var target := from + direction + Vector3i(0, height, 0)
				var block := snapshot.query_cell(target)
				var is_trap: bool = prefer_weakest and bool(block.get("trap", false))
				if not is_trap and not _is_solid(block):
					continue
				if bool(block.get("protected", false)):
					continue
				if prefer_weakest and not bool(block.get("damageable", true)):
					# A placed entity with no defence sheet cannot be beaten
					# down at all, so it is not an obstacle a blocked unit can
					# choose - however little "integrity" its cell reports.
					continue
				var damage := _damage_for(block.get("tags", []), damage_by_tag)
				if damage <= 0.0:
					continue
				var score := _heuristic(from, goal) + float(height) * 0.1
				var integrity := maxf(1.0, float(block.get("integrity", 1.0)))
				if prefer_weakest:
					if integrity > best_integrity:
						continue
					if is_equal_approx(integrity, best_integrity) and not _breaks_tie(score, best_score, target, best_cell):
						continue
				elif score >= best_score:
					continue
				best_score = score
				best_integrity = integrity
				best_cell = target
				best = {
					"type": "ATTACK_OBSTRUCTION",
					"from": from,
					"cell": target,
					"material_id": str(block.get("material_id", "unknown")),
					"source": str(block.get("source", "voxel")),
					"source_id": str(block.get("source_id", block.get("material_id", "unknown"))),
					"damage_per_hit": damage,
					"integrity": integrity,
					"estimated_hits": ceili(integrity / damage),
				}
	return best


## Two obstructions with the same integrity left: the nearer one to the goal
## wins, and if that ties too the lower cell coordinate does, so the same
## world always produces the same target.
func _breaks_tie(score: float, best_score: float, cell: Vector3i, best_cell: Vector3i) -> bool:
	if not is_equal_approx(score, best_score):
		return score < best_score
	if cell.x != best_cell.x:
		return cell.x < best_cell.x
	if cell.y != best_cell.y:
		return cell.y < best_cell.y
	return cell.z < best_cell.z


func _damage_for(tags_value: Variant, damage_by_tag: Dictionary) -> float:
	if not tags_value is Array:
		return 0.0
	var result := 0.0
	for tag in tags_value:
		result = maxf(result, float(damage_by_tag.get(str(tag), 0.0)))
	return result


func _lowest_score_index(open: Array[Vector3i], scores: Dictionary) -> int:
	var result := 0
	var best := float(scores.get(open[0], INF))
	for index in range(1, open.size()):
		var score := float(scores.get(open[index], INF))
		if score < best:
			best = score
			result = index
	return result


func _reconstruct(came_from: Dictionary, current: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


func _heuristic(a: Vector3i, b: Vector3i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z))


func _finish(ok: bool, reason: String, path: Array, visited: Array, started_usec: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"path": path,
		"visited": visited,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
	}
