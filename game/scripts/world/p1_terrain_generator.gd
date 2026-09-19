class_name P1TerrainGenerator
extends VoxelGeneratorScript

const CHANNEL := VoxelBuffer.CHANNEL_TYPE
const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const LOG := 4
const COAL_ORE := 6
const IRON_ORE := 7
const BEDROCK := 9
const LEAVES := 10
const GOLD_ORE := 11
const DEFAULT_SEED := 41026
## Ore rows are read from `terrain.ores` in world.json (see
## docs/P4B_RESOURCE_DISTRIBUTION.md). This fallback mirrors the shipped table
## so a generator built without settings still produces the same layout.
const DEFAULT_ORES := [
	{"block": "iron_ore", "min_depth": 6, "max_depth": 32, "cluster_per_thousand": 18, "cluster_size": 2},
	{"block": "coal_ore", "min_depth": 3, "max_depth": 32, "cluster_per_thousand": 37, "cluster_size": 2},
	{"block": "gold_ore", "min_depth": 12, "max_depth": 32, "cluster_per_thousand": 5, "cluster_size": 2},
]

var world_seed := DEFAULT_SEED
var settings: Dictionary = {}
var _height_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
## Compiled once in _init and never mutated afterwards: worker threads only read it.
var _ores: Array[Dictionary] = []


func _init(candidate_seed: int = DEFAULT_SEED, candidate_settings: Dictionary = {}) -> void:
	world_seed = candidate_seed
	settings = candidate_settings.duplicate(true)
	_height_noise = FastNoiseLite.new()
	_height_noise.seed = world_seed
	_height_noise.frequency = float(settings.get("height_frequency", 0.032))
	_height_noise.fractal_octaves = 3
	_height_noise.fractal_gain = 0.48
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = world_seed ^ 0x5f3759df
	_detail_noise.frequency = float(settings.get("detail_frequency", 0.085))
	_detail_noise.fractal_octaves = 2
	_detail_noise.fractal_gain = 0.42
	_ores = compile_ores(settings.get("ores", DEFAULT_ORES))


## Resolves an ore table (block ids as strings) into voxel ids and cumulative
## roll bands. Rows are ordered as written; each row owns the band
## [start, start + cluster_per_thousand) of a per-cluster roll in [0, 1000).
## Rows sharing a cluster_size share the same roll, so their bands never overlap.
static func compile_ores(rows: Variant) -> Array[Dictionary]:
	var compiled: Array[Dictionary] = []
	if not rows is Array:
		return compiled
	var band_start := 0
	for row in rows:
		if not row is Dictionary:
			continue
		var voxel_id := WorldAdapter.BLOCK_NAMES.find(str(row.get("block", "")))
		var width: int = maxi(int(row.get("cluster_per_thousand", 0)), 0)
		if voxel_id <= AIR or width == 0:
			band_start += width
			continue
		compiled.append({
			"block": str(row.get("block", "")),
			"voxel_id": voxel_id,
			"min_depth": int(row.get("min_depth", 3)),
			"max_depth": int(row.get("max_depth", 40)),
			"cluster_size": maxi(int(row.get("cluster_size", 2)), 1),
			"band_start": band_start,
			"band_end": band_start + width,
		})
		band_start += width
	return compiled


func ore_table() -> Array[Dictionary]:
	return _ores.duplicate(true)


func _get_used_channels_mask() -> int:
	return 1 << CHANNEL


func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod != 0:
		return
	var size := buffer.get_size()
	for local_z in range(size.z):
		var world_z := origin.z + local_z
		for local_x in range(size.x):
			var world_x := origin.x + local_x
			var surface := surface_height(world_x, world_z)
			for local_y in range(size.y):
				var world_y := origin.y + local_y
				buffer.set_voxel(sample_voxel(world_x, world_y, world_z, surface), local_x, local_y, local_z, CHANNEL)


func surface_height(x: int, z: int) -> int:
	var broad := _height_noise.get_noise_2d(float(x), float(z)) * 4.2
	var detail := _detail_noise.get_noise_2d(float(x), float(z)) * 1.4
	var candidate := clampi(roundi(-1.0 + broad + detail), int(settings.get("min_surface_y", -4)), int(settings.get("max_surface_y", 5)))
	var clearing_center_data: Array = settings.get("safe_clearing_center", [0, 40])
	var center := Vector2(float(clearing_center_data[0]), float(clearing_center_data[1]))
	var half_size_data: Array = settings.get("safe_clearing_half_size", [12, 9])
	var half_size := Vector2(float(half_size_data[0]), float(half_size_data[1]))
	var outside := Vector2(maxf(absf(float(x) - center.x) - half_size.x, 0.0), maxf(absf(float(z) - center.y) - half_size.y, 0.0))
	var edge_distance := outside.length()
	if edge_distance <= 0.0:
		return -1
	var blend_distance := float(settings.get("safe_clearing_blend", 8.0))
	if edge_distance < blend_distance:
		return roundi(lerpf(-1.0, float(candidate), edge_distance / blend_distance))
	return candidate


func sample_voxel(x: int, y: int, z: int, known_surface: int = 9999) -> int:
	var surface := surface_height(x, z) if known_surface == 9999 else known_surface
	if y == -16:
		return BEDROCK
	var fixed_resource := _starter_resource_at(x, y, z)
	if fixed_resource != AIR:
		return fixed_resource
	if y > surface:
		return _tree_voxel_at(x, y, z)
	if y == surface:
		return GRASS
	if y >= surface - 2:
		return DIRT
	var ore := _ore_at(x, y, z, surface)
	return ore if ore != AIR else STONE


func is_procedural_tree_root(x: int, z: int) -> bool:
	if _inside_safe_clearing(x, z) or x < -29 or x > 28 or z < -61 or z > 60:
		return false
	var grid_size := int(settings.get("tree_grid_size", 10))
	var grid_x := floori(float(x) / float(grid_size))
	var grid_z := floori(float(z) / float(grid_size))
	var candidate := _tree_candidate(grid_x, grid_z)
	if candidate != Vector2i(x, z):
		return false
	var chance := int(settings.get("tree_chance_percent", 72))
	if _roll_2d(grid_x, grid_z, 17, 100) >= chance:
		return false
	var center_height := surface_height(x, z)
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if absi(surface_height(x + offset.x, z + offset.y) - center_height) > 1:
			return false
	return true


func tree_height(x: int, z: int) -> int:
	return 4 + _roll_2d(x, z, 31, 2)


func _tree_voxel_at(x: int, y: int, z: int) -> int:
	if (x == 4 or x == 7) and z == 40 and y >= 0 and y < 4:
		return LOG
	var grid_size := int(settings.get("tree_grid_size", 10))
	var grid_x := floori(float(x) / float(grid_size))
	var grid_z := floori(float(z) / float(grid_size))
	for neighbor_z in range(grid_z - 1, grid_z + 2):
		for neighbor_x in range(grid_x - 1, grid_x + 2):
			var root := _tree_candidate(neighbor_x, neighbor_z)
			if not is_procedural_tree_root(root.x, root.y):
				continue
			var root_surface := surface_height(root.x, root.y)
			var height := tree_height(root.x, root.y)
			var top := root_surface + height
			if x == root.x and z == root.y and y >= root_surface + 1 and y <= top:
				return LOG
			var dx := absi(x - root.x)
			var dz := absi(z - root.y)
			var dy := y - top
			if dy >= -1 and dy <= 1 and dx <= 2 and dz <= 2 and dx + dz <= 3:
				return LEAVES
			if dy == 2 and dx + dz <= 1:
				return LEAVES
	return AIR


func _ore_at(x: int, y: int, z: int, surface: int) -> int:
	# Depth counts down from the surface block: depth 1 and 2 are always dirt
	# (see sample_voxel), so no ore row can reach them. Bedrock never carries ore.
	if y >= surface - 2 or y <= -16:
		return AIR
	var depth := surface - y
	for ore in _ores:
		var min_depth: int = ore["min_depth"]
		var max_depth: int = ore["max_depth"]
		if depth < min_depth or depth > max_depth:
			continue
		var size := float(ore["cluster_size"])
		var roll := _roll_3d(floori(float(x) / size), floori(float(y) / size), floori(float(z) / size), 1000)
		var band_start: int = ore["band_start"]
		var band_end: int = ore["band_end"]
		if roll >= band_start and roll < band_end:
			return int(ore["voxel_id"])
	return AIR


func _starter_resource_at(x: int, y: int, z: int) -> int:
	if x >= 8 and x < 11 and z >= 35 and z < 38 and y >= -4 and y < -2:
		return COAL_ORE
	if x >= -8 and x < -5 and z >= 35 and z < 38 and y >= -4 and y < -2:
		return IRON_ORE
	return AIR


func _inside_safe_clearing(x: int, z: int) -> bool:
	return x >= -12 and x <= 12 and z >= 31 and z <= 49


func _tree_candidate(grid_x: int, grid_z: int) -> Vector2i:
	var grid_size := int(settings.get("tree_grid_size", 10))
	var inset := 2
	var span := maxi(1, grid_size - inset * 2)
	return Vector2i(grid_x * grid_size + inset + _roll_2d(grid_x, grid_z, 3, span), grid_z * grid_size + inset + _roll_2d(grid_x, grid_z, 11, span))


func _roll_2d(x: int, z: int, salt: int, modulus: int) -> int:
	return posmod(hash(Vector3i(x + salt * 7919, world_seed + salt * 104729, z - salt * 1543)), modulus)


func _roll_3d(x: int, y: int, z: int, modulus: int) -> int:
	return posmod(hash(Vector3i(x + world_seed, y - world_seed * 3, z + world_seed * 7)), modulus)
