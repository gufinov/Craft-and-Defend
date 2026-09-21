class_name MinerService
extends Node

## Industry wave 1 (docs/INDUSTRY.md): miners. Every MINER_SECONDS each placed
## `miner` station looks for the nearest ore voxel (any block whose drop is
## an ore or coal item) within RADIUS cells on the same level, LEVELS above
## or below; mines it (the voxel becomes stone) and puts the drop into an
## adjacent `ore_bin` (the four cells beside the miner first, else any bin
## within one cell). No bin, or a full bin: the miner idles with a status.
## Per-miner state lives in the station record under "miner" so it saves
## with `WorkstationService.snapshot()`:
##   {"cooldown": seconds to the next tick, "mined": ore mined so far,
##    "status": "drilling …" | "no ore" | "no bin" | "bin full"}
## Miners need no fuel in wave 1 (wave 2: power).

signal mined(instance_id: String, cell: Vector3i, item_id: String, bin_id: String)

const MINER_ENTITY := "miner"
const BIN_ENTITY := "ore_bin"
const MINER_SECONDS := 8.0
const RADIUS := 3
const LEVELS := 2
const STONE := 3
const STATUS_NO_ORE := "no ore"
const STATUS_NO_BIN := "no bin"
const STATUS_BIN_FULL := "bin full"
const SIDE_NEIGHBOURS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
## Drop items that count as ore for a miner.
const ORE_ITEMS: Array[String] = ["iron_ore", "gold_ore", "coal"]

var world: WorldAdapter
var workstations: WorkstationService
var registry: ContentRegistry
## voxel id -> drop item id, for every block whose drop is in ORE_ITEMS.
var ore_voxels: Dictionary = {}


func initialize(world_adapter: WorldAdapter, station_service: WorkstationService, content: ContentRegistry) -> void:
	world = world_adapter
	workstations = station_service
	registry = content
	ore_voxels.clear()
	for voxel_id: int in registry.blocks_by_voxel.keys():
		var drop := str(registry.blocks_by_voxel[voxel_id].get("drop", ""))
		if drop in ORE_ITEMS:
			ore_voxels[voxel_id] = drop


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0 or workstations == null or world == null:
		return
	for instance_id: String in workstations.stations.keys():
		var record: Dictionary = workstations.stations[instance_id]
		if str(record.get("entity_id", "")) != MINER_ENTITY:
			continue
		var state := miner_state(instance_id)
		state["cooldown"] = float(state.get("cooldown", MINER_SECONDS)) - delta
		if float(state.cooldown) > 0.0:
			record["miner"] = state
			continue
		state["cooldown"] = MINER_SECONDS
		record["miner"] = state
		_tick(instance_id, record)


## The miner's saved state (a fresh default for a miner that never ticked).
func miner_state(instance_id: String) -> Dictionary:
	var record: Dictionary = workstations.stations.get(instance_id, {})
	var raw: Variant = record.get("miner", {})
	var state: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	if not state.has("cooldown"):
		state["cooldown"] = MINER_SECONDS
	if not state.has("mined"):
		state["mined"] = 0
	if not state.has("status"):
		state["status"] = STATUS_NO_ORE
	return state


func is_working(instance_id: String) -> bool:
	var state := miner_state(instance_id)
	return str(state.get("status", "")).begins_with("drilling")


## One mining tick: find the nearest ore, find a bin with room, mine.
func _tick(instance_id: String, record: Dictionary) -> void:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var state: Dictionary = record["miner"]
	var target := nearest_ore(anchor)
	if target.is_empty():
		state["status"] = STATUS_NO_ORE
		return
	var bins := bins_beside(anchor)
	if bins.is_empty():
		state["status"] = STATUS_NO_BIN
		return
	var item_id := str(target.item_id)
	var bin_id := ""
	for candidate: String in bins:
		if workstations.container_room(candidate, item_id) > 0:
			bin_id = candidate
			break
	if bin_id.is_empty():
		state["status"] = STATUS_BIN_FULL
		return
	var cell: Vector3i = target.cell
	if not world.set_cell(cell, STONE):
		state["status"] = STATUS_NO_ORE
		return
	var inserted := workstations.container_insert(bin_id, item_id, 1)
	if not inserted.get("ok", false):
		# The room check passed a moment ago; keep the ore rather than lose it.
		world.set_cell(cell, int(target.voxel_id))
		state["status"] = STATUS_BIN_FULL
		return
	state["mined"] = int(state.get("mined", 0)) + 1
	state["status"] = "drilling %s %d m away" % [registry.display_name(item_id).to_lower(), int(target.distance)]
	mined.emit(instance_id, cell, item_id, bin_id)


## The nearest ore voxel in the search box around `anchor`:
## {"cell", "voxel_id", "item_id", "distance"} or {} when there is none.
func nearest_ore(anchor: Vector3i) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for dy in range(-LEVELS, LEVELS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			for dz in range(-RADIUS, RADIUS + 1):
				var cell := anchor + Vector3i(dx, dy, dz)
				var query := world.query_cell(cell)
				if query.get("state") != "LOADED":
					continue
				var voxel_id := int(query.get("voxel_id", 0))
				if not ore_voxels.has(voxel_id):
					continue
				var distance := Vector3(dx, dy, dz).length()
				if distance < best_distance:
					best_distance = distance
					best = {"cell": cell, "voxel_id": voxel_id, "item_id": str(ore_voxels[voxel_id]), "distance": maxi(1, roundi(distance))}
	return best


## Ore bins the miner can fill: the four cells beside it first, then any bin
## whose footprint lies within one cell of the miner (diagonals, above, below).
func bins_beside(anchor: Vector3i) -> Array[String]:
	var found: Array[String] = []
	for side: Vector3i in SIDE_NEIGHBOURS:
		var owner_id := workstations.station_at_cell(anchor + side)
		if _is_bin(owner_id) and owner_id not in found:
			found.append(owner_id)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var owner_id := workstations.station_at_cell(anchor + Vector3i(dx, dy, dz))
				if _is_bin(owner_id) and owner_id not in found:
					found.append(owner_id)
	return found


func _is_bin(instance_id: String) -> bool:
	if instance_id.is_empty():
		return false
	return str(workstations.stations.get(instance_id, {}).get("entity_id", "")) == BIN_ENTITY


## "Miner: 3 ore mined, drilling iron ore 2 m away" for the right-click line.
func status_text(instance_id: String) -> String:
	var state := miner_state(instance_id)
	return "Miner: %d ore mined, %s" % [int(state.get("mined", 0)), str(state.get("status", STATUS_NO_ORE))]
