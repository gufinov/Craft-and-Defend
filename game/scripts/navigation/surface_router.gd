class_name SurfaceRouter
extends RefCounted

## P4E long-range routing over the generated surface. Raiders marching from
## the enemy base (150-200 cells away) cannot use the local voxel planner:
## its captured region would be enormous and most of the ground is not even
## loaded. This router walks the generator's column heights instead: A* over
## (x, z) columns with 4-neighbours, a step of at most one block up or down,
## no water and no tree trunks. It returns route cells (x, surface + 1, z) that
## BasicRaider follows like any other route (ghost-walking where the terrain
## is not loaded). Player-built structures are ignored: the local planner takes
## over once the march reaches the defended area.

const STEP_LIMIT := 1
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var generator: P1TerrainGenerator
var _heights: Dictionary = {}
var _walkable: Dictionary = {}


func _init(terrain_generator: P1TerrainGenerator) -> void:
	generator = terrain_generator


func height(column: Vector2i) -> int:
	if _heights.has(column):
		return int(_heights[column])
	var value := generator.surface_height(column.x, column.y)
	_heights[column] = value
	return value


func walkable(column: Vector2i) -> bool:
	if _walkable.has(column):
		return bool(_walkable[column])
	var minimum := generator.bounds_min
	var maximum := generator.bounds_min + generator.bounds_size
	var ok := column.x > minimum.x and column.x < maximum.x - 1 and column.y > minimum.z and column.y < maximum.z - 1
	if ok:
		ok = not generator.is_water_column(column.x, column.y) and not generator.is_procedural_tree_root(column.x, column.y)
	_walkable[column] = ok
	return ok


## Shortest walkable column path from `from` to within `goal_radius` of `to`.
## When the node budget runs out the path to the closest column found is
## returned instead (the caller re-routes from there); an empty array means
## the start itself is unusable.
func route(from: Vector2i, to: Vector2i, goal_radius: int = 1, node_budget: int = 60000) -> Array[Vector3i]:
	var open := _Heap.new()
	var came_from: Dictionary = {}
	var cost: Dictionary = {from: 0.0}
	var best := from
	var best_estimate := _estimate(from, to)
	open.push(best_estimate, from)
	var expanded := 0
	while not open.is_empty() and expanded < node_budget:
		var current: Vector2i = open.pop()
		expanded += 1
		var remaining := _estimate(current, to)
		if remaining < best_estimate:
			best_estimate = remaining
			best = current
		if remaining <= float(goal_radius):
			best = current
			break
		var current_cost := float(cost[current])
		var current_height := height(current)
		for offset in NEIGHBOURS:
			var next := current + offset
			if not walkable(next):
				continue
			var next_height := height(next)
			var climb := absi(next_height - current_height)
			if climb > STEP_LIMIT:
				continue
			var next_cost := current_cost + 1.0 + float(climb) * 0.6
			if cost.has(next) and float(cost[next]) <= next_cost:
				continue
			cost[next] = next_cost
			came_from[next] = current
			open.push(next_cost + _estimate(next, to), next)
	return _unwind(came_from, best)


func _unwind(came_from: Dictionary, goal: Vector2i) -> Array[Vector3i]:
	var columns: Array[Vector2i] = [goal]
	var cursor := goal
	while came_from.has(cursor):
		cursor = came_from[cursor]
		columns.append(cursor)
	columns.reverse()
	var cells: Array[Vector3i] = []
	for column in columns:
		cells.append(Vector3i(column.x, height(column) + 1, column.y))
	return cells


func _estimate(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))


## Minimal binary min-heap of (priority, column) pairs.
class _Heap:
	var _keys: Array[float] = []
	var _values: Array[Vector2i] = []

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(key: float, value: Vector2i) -> void:
		_keys.append(key)
		_values.append(value)
		var index := _keys.size() - 1
		while index > 0:
			var parent := (index - 1) / 2
			if _keys[parent] <= _keys[index]:
				break
			_swap(index, parent)
			index = parent

	func pop() -> Vector2i:
		var top := _values[0]
		var last := _keys.size() - 1
		_swap(0, last)
		_keys.remove_at(last)
		_values.remove_at(last)
		var index := 0
		var size := _keys.size()
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < size and _keys[left] < _keys[smallest]:
				smallest = left
			if right < size and _keys[right] < _keys[smallest]:
				smallest = right
			if smallest == index:
				break
			_swap(index, smallest)
			index = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
		var value := _values[a]
		_values[a] = _values[b]
		_values[b] = value
