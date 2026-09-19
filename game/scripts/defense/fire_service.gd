class_name FireService
extends Node3D

## P4a-4 fire: burning cells lit by flame munitions. A fire on non-flammable
## ground burns for `burn_seconds` and goes out. A fire on flammable material
## (blocks tagged flammable, or wood entities) consumes it after
## `fuel_seconds`, keeps burning, and each second may spread to flammable
## neighbours with `spread_chance`. Raiders standing in fire take
## `fire_damage_per_second`. Fires are simulation state; the visual (a lit
## flame mesh plus an OmniLight3D) is a projection of it.

signal cell_burnt(cell: Vector3i)
signal feedback(message: String)

const FLAMMABLE_BLOCKS := ["log", "planks", "leaves"]
const NEIGHBOURS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const MAX_FIRES := 160

var world: WorldAdapter
var workstations: WorkstationService
var damage_target: Callable
## cell -> {remaining, fuel, spread_chance, damage, spread_timer, flammable}
var fires: Dictionary = {}
var _visuals: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func initialize(world_adapter: WorldAdapter, station_service: WorkstationService, raider_damage: Callable, seed_value: int = 41026) -> void:
	world = world_adapter
	workstations = station_service
	damage_target = raider_damage
	_rng.seed = seed_value


## Lights the cell (and, for splash, its ring) per the munition definition.
func ignite(center: Vector3i, munition: Dictionary, radius: float = 0.0) -> int:
	var lit := 0
	var reach := int(floor(radius))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			if Vector2(dx, dz).length() > maxf(radius, 0.0):
				continue
			var cell := _ground_cell(center + Vector3i(dx, 0, dz))
			if _light(cell, munition):
				lit += 1
	return lit


func _light(cell: Vector3i, munition: Dictionary) -> bool:
	if fires.size() >= MAX_FIRES or fires.has(cell):
		return false
	var query := world.query_cell(cell)
	if query.get("state") != "LOADED":
		return false
	var flammable := _is_flammable(cell)
	fires[cell] = {
		"remaining": float(munition.get("burn_seconds", 8.0)),
		"fuel": float(munition.get("fuel_seconds", 5.0)) if flammable else 0.0,
		"spread_chance": float(munition.get("spread_chance", 0.3)),
		"damage": int(munition.get("fire_damage_per_second", 2)),
		"spread_timer": 1.0,
		"flammable": flammable,
		"munition": munition.duplicate(true),
	}
	_show(cell)
	return true


func advance(delta: float, paused: bool = false) -> void:
	if paused or delta <= 0.0 or fires.is_empty():
		return
	var spent: Array[Vector3i] = []
	var to_spread: Array[Vector3i] = []
	for cell: Vector3i in fires.keys():
		var fire: Dictionary = fires[cell]
		if bool(fire.flammable):
			fire.fuel = float(fire.fuel) - delta
			if float(fire.fuel) <= 0.0:
				_consume(cell)
				fire.flammable = false
				fire.remaining = float(fire.munition.get("burn_seconds", 8.0))
		else:
			fire.remaining = float(fire.remaining) - delta
		fire.spread_timer = float(fire.spread_timer) - delta
		if float(fire.spread_timer) <= 0.0:
			fire.spread_timer = 1.0
			if damage_target.is_valid():
				damage_target.call(cell, int(fire.damage))
			if bool(fire.flammable) or float(fire.remaining) > 2.0:
				to_spread.append(cell)
		fires[cell] = fire
		if not bool(fire.flammable) and float(fire.remaining) <= 0.0:
			spent.append(cell)
	for cell in to_spread:
		_try_spread(cell)
	for cell in spent:
		fires.erase(cell)
		_hide(cell)


func burning_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for cell: Vector3i in fires.keys():
		cells.append(cell)
	return cells


func is_burning(cell: Vector3i) -> bool:
	return fires.has(cell)


func extinguish_all() -> void:
	for cell: Vector3i in fires.keys():
		_hide(cell)
	fires.clear()


func _try_spread(cell: Vector3i) -> void:
	var fire: Dictionary = fires[cell]
	for offset in NEIGHBOURS:
		var neighbour := cell + offset
		if fires.has(neighbour) or not _is_flammable(neighbour):
			continue
		if _rng.randf() < float(fire.spread_chance):
			_light(neighbour, fire.munition)


## A cell is flammable when it is a flammable voxel or belongs to a wood
## entity (barricade, gate frame, chest...).
func _is_flammable(cell: Vector3i) -> bool:
	var query := world.query_cell(cell)
	if query.get("state") != "LOADED":
		return false
	var voxel_id := int(query.get("voxel_id", 0))
	if voxel_id > 0 and voxel_id < WorldAdapter.BLOCK_NAMES.size() and WorldAdapter.BLOCK_NAMES[voxel_id] in FLAMMABLE_BLOCKS:
		return true
	if workstations != null:
		var owner_id := workstations.station_at_cell(cell)
		if not owner_id.is_empty():
			var definition := workstations.registry.entity(str(workstations.station(owner_id).get("entity_id", "")))
			var tags: Array = definition.get("navigation", {}).get("material_tags", [])
			return "wood" in tags
	return false


## Burns the fuel away: a flammable voxel becomes air; a wood entity takes
## heavy damage through the existing defense path (destroyed when it runs out).
func _consume(cell: Vector3i) -> void:
	var query := world.query_cell(cell)
	var voxel_id := int(query.get("voxel_id", 0))
	if voxel_id > 0 and voxel_id < WorldAdapter.BLOCK_NAMES.size() and WorldAdapter.BLOCK_NAMES[voxel_id] in FLAMMABLE_BLOCKS:
		world.set_cell(cell, 0)
		cell_burnt.emit(cell)
		return
	if workstations != null:
		var owner_id := workstations.station_at_cell(cell)
		if not owner_id.is_empty():
			var status := workstations.defense_status(owner_id)
			if status.get("ok", false):
				workstations.try_damage(owner_id, int(status.get("details", {}).get("max_integrity", 30)))
			cell_burnt.emit(cell)


## Fire sits on the first loaded solid cell at or below the hit; a shot
## landing on open ground burns the ground cell's air cell above it.
func _ground_cell(cell: Vector3i) -> Vector3i:
	var probe := cell
	for _step in range(6):
		var query := world.query_cell(probe)
		if query.get("state") == "LOADED" and int(query.get("voxel_id", 0)) != 0:
			return probe + Vector3i(0, 1, 0) if not _is_flammable(probe) else probe
		probe += Vector3i(0, -1, 0)
	return cell


func _show(cell: Vector3i) -> void:
	if _visuals.has(cell):
		return
	var flame := Node3D.new()
	flame.name = "Fire_%d_%d_%d" % [cell.x, cell.y, cell.z]
	flame.position = Vector3(cell) + Vector3(0.5, 0.15, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.1)
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in range(3):
		var tongue := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.22 - index * 0.05
		mesh.height = 0.7 - index * 0.12
		mesh.radial_segments = 6
		tongue.mesh = mesh
		tongue.material_override = material
		tongue.position = Vector3(index * 0.18 - 0.18, mesh.height * 0.5, index * 0.12 - 0.12)
		flame.add_child(tongue)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(0.0, 0.6, 0.0)
	flame.add_child(light)
	add_child(flame)
	_visuals[cell] = flame


func _hide(cell: Vector3i) -> void:
	if _visuals.has(cell):
		_visuals[cell].queue_free()
		_visuals.erase(cell)
