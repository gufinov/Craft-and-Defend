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
const WATER := 12
const DEFAULT_SEED := 41026
## Sea level: lake floors dug below it fill with water up to it.
const SEA_LEVEL := 0
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
var _mountain_noise: FastNoiseLite
var _lake_noise: FastNoiseLite
## World bounds (from world.json via the adapter) and the enemy base, derived
## from the seed once in _init so every thread and service agrees on it.
var bounds_min := Vector3i(-160, -16, -192)
var bounds_size := Vector3i(320, 48, 384)
var enemy_base := Vector2i(0, -140)
var _surface_ores: Array[Dictionary] = []
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
	_mountain_noise = FastNoiseLite.new()
	_mountain_noise.seed = world_seed ^ 0x2545F491
	_mountain_noise.frequency = float(settings.get("mountain_frequency", 0.0075))
	_mountain_noise.fractal_octaves = 3
	_mountain_noise.fractal_gain = 0.5
	_lake_noise = FastNoiseLite.new()
	_lake_noise.seed = world_seed ^ 0x1B873593
	_lake_noise.frequency = float(settings.get("lake_frequency", 0.014))
	_lake_noise.fractal_octaves = 2
	_ores = compile_ores(settings.get("ores", DEFAULT_ORES))
	_surface_ores = compile_ores(settings.get("surface_ores", []))
	var minimum: Variant = settings.get("bounds_min", [])
	var size: Variant = settings.get("bounds_size", [])
	if minimum is Array and minimum.size() == 3 and size is Array and size.size() == 3:
		bounds_min = Vector3i(int(minimum[0]), int(minimum[1]), int(minimum[2]))
		bounds_size = Vector3i(int(size[0]), int(size[1]), int(size[2]))
	enemy_base = _pick_enemy_base()


## The enemy base sits on a ring 150-200 cells from the home clearing at a
## seed-chosen bearing, inside the bounds by `margin`; its ground is flattened
## like the home clearing (see surface_height).
func _pick_enemy_base() -> Vector2i:
	var rules: Dictionary = settings.get("enemy_base", {})
	var minimum := float(rules.get("min_distance", 150))
	var maximum := float(rules.get("max_distance", 200))
	var margin := int(rules.get("margin", 24))
	var home := _home_center()
	var best := Vector2i(int(home.x), int(home.y) - int(maximum))
	var best_distance := -1.0
	for attempt in range(24):
		var angle := float(_roll_2d(attempt, 0, 41, 3600)) / 3600.0 * TAU
		var distance := lerpf(minimum, maximum, float(_roll_2d(attempt, 1, 43, 1000)) / 1000.0)
		var candidate := Vector2(home.x + cos(angle) * distance, home.y + sin(angle) * distance)
		var clamped := Vector2i(
			clampi(roundi(candidate.x), bounds_min.x + margin, bounds_min.x + bounds_size.x - margin - 1),
			clampi(roundi(candidate.y), bounds_min.z + margin, bounds_min.z + bounds_size.z - margin - 1))
		var actual := Vector2(clamped).distance_to(home)
		if actual >= minimum and actual <= maximum:
			return clamped
		if actual > best_distance:
			best_distance = actual
			best = clamped
	return best


func _home_center() -> Vector2:
	var clearing_center_data: Array = settings.get("safe_clearing_center", [0, 40])
	return Vector2(float(clearing_center_data[0]), float(clearing_center_data[1]))


func enemy_base_cell() -> Vector3i:
	return Vector3i(enemy_base.x, surface_height(enemy_base.x, enemy_base.y) + 1, enemy_base.y)


## 0 outside lakes, else how deep into the lake mask the column sits (0..1].
func _lake_dip(x: int, z: int) -> float:
	var lake := _lake_noise.get_noise_2d(float(x), float(z))
	var lake_threshold := float(settings.get("lake_threshold", 0.42))
	if lake <= lake_threshold:
		return 0.0
	return (lake - lake_threshold) / maxf(0.05, 1.0 - lake_threshold)


## A lake column: its floor lies below the water line (SEA_LEVEL - 1) and the
## clearings never flood.
func is_water_column(x: int, z: int) -> bool:
	return _lake_dip(x, z) > 0.0 and surface_height(x, z) < SEA_LEVEL - 1


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
		var width: int = maxi(int(row.get("cluster_per_thousand", row.get("per_thousand", 0))), 0)
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
			# Per-column facts computed once: the water flag and the exposed
			# ore both cost noise samples, and a column has 16 voxels here.
			var water := _lake_dip(world_x, world_z) > 0.0 and surface < SEA_LEVEL - 1
			var exposed := _surface_ore_at(world_x, world_z)
			var roots := _nearby_tree_roots(world_x, world_z)
			for local_y in range(size.y):
				var world_y := origin.y + local_y
				buffer.set_voxel(_column_voxel(world_x, world_y, world_z, surface, water, exposed, roots), local_x, local_y, local_z, CHANNEL)


func surface_height(x: int, z: int) -> int:
	var broad := _height_noise.get_noise_2d(float(x), float(z)) * 4.2
	var detail := _detail_noise.get_noise_2d(float(x), float(z)) * 1.4
	# Rolling ground never dips below the sea line on its own; only lakes do.
	var rolling := maxf(-1.0 + broad + detail, float(SEA_LEVEL) - 1.0)
	# Mountains: where the slow mask exceeds its threshold the ground rises
	# toward mountain_height (foothills first, then peaks).
	var mask := _mountain_noise.get_noise_2d(float(x), float(z))
	var threshold := float(settings.get("mountain_threshold", 0.30))
	if mask > threshold:
		var ramp := (mask - threshold) / 0.35
		rolling += ramp * (1.2 + ramp) * float(settings.get("mountain_height", 20)) * _mountain_allowance(x, z)
	# Lakes: where the lake mask exceeds its threshold the ground dips below
	# sea level; sample_voxel fills the dip with water.
	var dip := _lake_dip(x, z)
	if dip > 0.0 and mask <= threshold:
		rolling = minf(rolling, float(SEA_LEVEL) - 2.0 - dip * float(settings.get("lake_depth", 4)))
	var candidate := clampi(roundi(rolling), int(settings.get("min_surface_y", -4)) - int(settings.get("lake_depth", 4)), int(settings.get("max_surface_y", 26)))
	var half_size_data: Array = settings.get("safe_clearing_half_size", [12, 9])
	var half_size := Vector2(float(half_size_data[0]), float(half_size_data[1]))
	var home := _home_center()
	var outside := Vector2(maxf(absf(float(x) - home.x) - half_size.x, 0.0), maxf(absf(float(z) - home.y) - half_size.y, 0.0))
	var edge_distance := outside.length()
	var blend_distance := float(settings.get("safe_clearing_blend", 8.0))
	if edge_distance <= 0.0:
		return -1
	if edge_distance < blend_distance:
		return roundi(lerpf(-1.0, float(candidate), edge_distance / blend_distance))
	# Enemy base: a round flat clearing at the surface level of its centre.
	var rules: Dictionary = settings.get("enemy_base", {})
	var radius := float(rules.get("clearing_radius", 10))
	var blend := float(rules.get("blend", 10))
	var base_distance := Vector2(float(x), float(z)).distance_to(Vector2(enemy_base))
	if base_distance <= radius + blend:
		var base_level := _enemy_base_level()
		if base_distance <= radius:
			return base_level
		return roundi(lerpf(float(base_level), float(candidate), (base_distance - radius) / blend))
	return candidate


## Mountains stay off the home surroundings and off a corridor between the
## home clearing and the enemy base, so raiders (one step up/down) always
## have a way in and the player is never walled in by peaks (owner 2026-09-19).
func _mountain_allowance(x: int, z: int) -> float:
	var point := Vector2(float(x), float(z))
	var home := _home_center()
	var home_distance := point.distance_to(home)
	var allowance := clampf((home_distance - 30.0) / 25.0, 0.0, 1.0)
	var base := Vector2(enemy_base)
	var segment := base - home
	var t := clampf((point - home).dot(segment) / maxf(segment.length_squared(), 1.0), 0.0, 1.0)
	var corridor_distance := point.distance_to(home + segment * t)
	allowance = minf(allowance, clampf((corridor_distance - 8.0) / 12.0, 0.0, 1.0))
	return allowance


## The enemy clearing's level: the raw rolling terrain at its centre, kept
## above sea level so the base never floods.
func _enemy_base_level() -> int:
	var broad := _height_noise.get_noise_2d(float(enemy_base.x), float(enemy_base.y)) * 4.2
	var detail := _detail_noise.get_noise_2d(float(enemy_base.x), float(enemy_base.y)) * 1.4
	return clampi(roundi(-1.0 + broad + detail), SEA_LEVEL, int(settings.get("max_surface_y", 26)))


func sample_voxel(x: int, y: int, z: int, known_surface: int = 9999) -> int:
	var surface := surface_height(x, z) if known_surface == 9999 else known_surface
	return _column_voxel(x, y, z, surface, is_water_column(x, z), _surface_ore_at(x, z), _nearby_tree_roots(x, z))


## Tree roots whose trunk or canopy can reach this column, resolved once per
## column: [{root: Vector2i, surface: int, height: int}].
func _nearby_tree_roots(x: int, z: int) -> Array[Dictionary]:
	var roots: Array[Dictionary] = []
	var grid_size := int(settings.get("tree_grid_size", 10))
	var grid_x := floori(float(x) / float(grid_size))
	var grid_z := floori(float(z) / float(grid_size))
	for neighbor_z in range(grid_z - 1, grid_z + 2):
		for neighbor_x in range(grid_x - 1, grid_x + 2):
			var root := _tree_candidate(neighbor_x, neighbor_z)
			if absi(root.x - x) > 2 or absi(root.y - z) > 2:
				continue
			if not is_procedural_tree_root(root.x, root.y):
				continue
			var root_surface := surface_height(root.x, root.y)
			roots.append({"root": root, "surface": root_surface, "height": tree_height(root.x, root.y)})
	return roots


func _column_voxel(x: int, y: int, z: int, surface: int, water: bool, exposed: int, roots: Array[Dictionary]) -> int:
	if y == bounds_min.y:
		return BEDROCK
	var fixed_resource := _starter_resource_at(x, y, z)
	if fixed_resource != AIR:
		return fixed_resource
	if y > surface:
		if water and y <= SEA_LEVEL - 1:
			return WATER
		if (x == 4 or x == 7) and z == 40 and y >= 0 and y < 4:
			return LOG
		for entry in roots:
			var root: Vector2i = entry.root
			var top: int = int(entry.surface) + int(entry.height)
			if x == root.x and z == root.y and y >= int(entry.surface) + 1 and y <= top:
				return LOG
			var dx := absi(x - root.x)
			var dz := absi(z - root.y)
			var dy := y - top
			if dy >= -1 and dy <= 1 and dx <= 2 and dz <= 2 and dx + dz <= 3:
				return LEAVES
			if dy == 2 and dx + dz <= 1:
				return LEAVES
		return AIR
	var rock_surface := int(settings.get("rock_surface_y", 12))
	if y == surface:
		if exposed != AIR:
			return exposed
		if surface >= rock_surface:
			return STONE
		if water:
			return DIRT
		return GRASS
	if y >= surface - 2:
		return DIRT if surface < rock_surface else STONE
	var ore := _ore_at(x, y, z, surface)
	return ore if ore != AIR else STONE


func is_procedural_tree_root(x: int, z: int) -> bool:
	if _inside_safe_clearing(x, z) or x < bounds_min.x + 3 or x > bounds_min.x + bounds_size.x - 4 or z < bounds_min.z + 3 or z > bounds_min.z + bounds_size.z - 4:
		return false
	var root_surface := surface_height(x, z)
	if is_water_column(x, z) or root_surface >= int(settings.get("rock_surface_y", 12)):
		return false
	if Vector2(float(x), float(z)).distance_to(Vector2(enemy_base)) <= float(settings.get("enemy_base", {}).get("clearing_radius", 10)) + 1.0:
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
	if y >= surface - 2 or y <= bounds_min.y:
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


## Ore showing on the ground: a per-column roll per surface ore row, so the
## first coal and iron can be picked up without digging.
func _surface_ore_at(x: int, z: int) -> int:
	if _surface_ores.is_empty() or _inside_safe_clearing(x, z):
		return AIR
	for ore in _surface_ores:
		var size := float(ore["cluster_size"])
		var roll := _roll_2d(floori(float(x) / size), floori(float(z) / size), 53, 1000)
		if roll >= int(ore["band_start"]) and roll < int(ore["band_end"]):
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
