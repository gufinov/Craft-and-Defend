class_name StorageNetwork
extends RefCounted

## Industry wave 1 (docs/INDUSTRY.md, "Storage network"): every container
## station (chest, ore_bin, warehouse - anything with `container_slots`)
## that touches a set of cells joins one pool, and containers that touch each
## other join the same pool (chests beside a warehouse, warehouses daisy
## chained). Users and producers (foundry, furnace, miner, siege weapons,
## carts) read and write the pool instead of one named container.
##
## "Touches" = a footprint cell is a side neighbour (four sides) of one of the
## cells, on the same level or one level above or below. Order is
## deterministic: seeds nearest the cells first, then the flood, ties by
## instance id. A helper over WorkstationService with no state of its own but
## a per-frame cache keyed by the query, dropped on `station_changed`.

const SIDE_STEPS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const LEVEL_STEPS: Array[Vector3i] = [Vector3i.ZERO, Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

var workstations: WorkstationService
var _cache: Dictionary = {}
var _cache_frame := -1


func _init(service: WorkstationService) -> void:
	workstations = service
	if workstations != null:
		workstations.station_changed.connect(func(_result: Dictionary) -> void: _cache.clear())


## The footprint cells of a placed station (anchor + rotated offsets).
func station_cells(instance_id: String) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var record: Dictionary = workstations.stations.get(instance_id, {})
	if record.is_empty():
		return cells
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var rotation := int(record.get("rotation_quarters", 0))
	for offset in workstations.registry.entity(str(record.get("entity_id", ""))).get("occupied_offsets", []):
		if offset is Array and offset.size() == 3:
			cells.append(anchor + workstations.footprints.rotate_offset(Vector3i(int(offset[0]), int(offset[1]), int(offset[2])), rotation))
	if cells.is_empty():
		cells.append(anchor)
	return cells


## The containers touching any of `cells` (excluding stations that own those
## cells) plus everything they chain to, nearest first.
func network_for(cells: Array[Vector3i]) -> Array[String]:
	var frame := Engine.get_process_frames()
	if frame != _cache_frame:
		_cache.clear()
		_cache_frame = frame
	var key := ""
	for cell: Vector3i in cells:
		key += "%d,%d,%d;" % [cell.x, cell.y, cell.z]
	if _cache.has(key):
		var cached: Array[String] = []
		cached.assign(_cache[key])
		return cached
	var origin := Vector3.ZERO
	for cell: Vector3i in cells:
		origin += Vector3(cell)
	if not cells.is_empty():
		origin /= float(cells.size())
	var own: Dictionary = {}
	for cell: Vector3i in cells:
		var owner := workstations.footprints.owner_at(cell)
		if not owner.is_empty():
			own[owner] = true
	var found: Array[String] = []
	var queue: Array[String] = _sorted(_touching(cells, own), origin)
	while not queue.is_empty():
		var container_id: String = queue.pop_front()
		if found.has(container_id):
			continue
		found.append(container_id)
		var skip: Dictionary = own.duplicate()
		for known: String in found:
			skip[known] = true
		for next_id: String in _sorted(_touching(station_cells(container_id), skip), origin):
			if not found.has(next_id) and not queue.has(next_id):
				queue.append(next_id)
	_cache[key] = found.duplicate()
	return found


## The network around one station's own footprint.
func network_of(instance_id: String) -> Array[String]:
	return network_for(station_cells(instance_id))


func count(network: Array[String], item_id: String) -> int:
	var total := 0
	for container_id: String in network:
		total += workstations.container_count(container_id, item_id)
	return total


func room(network: Array[String], item_id: String) -> int:
	var total := 0
	for container_id: String in network:
		total += workstations.container_room(container_id, item_id)
	return total


## Takes up to `amount` of `item_id` across the network, nearest first.
## Returns the amount actually taken.
func take(network: Array[String], item_id: String, amount: int) -> int:
	var taken := 0
	for container_id: String in network:
		if taken >= amount:
			break
		var held := workstations.container_count(container_id, item_id)
		if held <= 0:
			continue
		var result := workstations.container_take(container_id, item_id, mini(amount - taken, held))
		taken += int(result.get("details", {}).get("moved", 0))
	return taken


## Puts up to `amount` of `item_id` into the network, nearest first (a full
## container overflows into the next). Returns what did not fit.
func put(network: Array[String], item_id: String, amount: int) -> int:
	var remaining := amount
	for container_id: String in network:
		if remaining <= 0:
			break
		if workstations.container_room(container_id, item_id) <= 0:
			continue
		var result := workstations.container_put(container_id, item_id, remaining)
		remaining -= int(result.get("details", {}).get("moved", 0))
	return maxi(0, remaining)


## The first item id in the network among `candidates` (book order of the
## candidates, then nearest container), or "".
func first_present(network: Array[String], candidates: Array[String]) -> String:
	for item_id: String in candidates:
		if count(network, item_id) > 0:
			return item_id
	return ""


func _touching(cells: Array[Vector3i], skip: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for cell: Vector3i in cells:
		for side: Vector3i in SIDE_STEPS:
			for level: Vector3i in LEVEL_STEPS:
				var owner := workstations.footprints.owner_at(cell + side + level)
				if owner.is_empty() or skip.has(owner) or found.has(owner):
					continue
				if workstations.is_container(owner):
					found.append(owner)
	return found


func _sorted(ids: Array[String], origin: Vector3) -> Array[String]:
	var sorted: Array[String] = []
	sorted.assign(ids)
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var distance_a := origin.distance_to(Vector3(workstations.stations.get(a, {}).get("anchor", Vector3i.ZERO)))
		var distance_b := origin.distance_to(Vector3(workstations.stations.get(b, {}).get("anchor", Vector3i.ZERO)))
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		return a < b)
	return sorted
