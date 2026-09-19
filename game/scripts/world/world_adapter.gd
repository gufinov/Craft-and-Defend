class_name WorldAdapter
extends Node3D

signal spawn_area_ready
signal status_changed(message: String)
signal cell_changed(cell: Vector3i, previous_voxel_id: int, new_voxel_id: int, revision: int)

## Bounds come from data/world.json (min_cell / size) at initialize(); these
## are the P4E defaults and stay readable as WorldAdapter.WORLD_MIN/SIZE.
static var WORLD_MIN := Vector3i(-160, -16, -192)
static var WORLD_SIZE := Vector3i(320, 48, 384)
const SPAWN_FEET := Vector3(0.5, 2.0, 40.5)
const CHANNEL := VoxelBuffer.CHANNEL_TYPE
const WORLD_CONFIG_PATH := "res://data/world.json"
const LEGACY_GENERATOR_VERSION := "flat_fixture_1"
const P1_GENERATOR_VERSION := "terrain_p1_1"
const DEFAULT_WORLD_SEED := 41026

const BLOCK_NAMES := [
	"air", "grass", "dirt", "stone", "log", "planks",
	"coal_ore", "iron_ore", "castle_stone", "bedrock", "leaves",
	"gold_ore", "water",
]
const BLOCK_COLORS := [
	Color(0, 0, 0, 0), Color("74a65a"), Color("8b5f3c"), Color("777b82"),
	Color("9b6a3d"), Color("b88954"), Color("34383f"), Color("a65b42"),
	Color("8b929d"), Color("25282d"), Color("4f873c"),
	Color("c9a640"), Color(0.25, 0.55, 0.95, 0.55),
]
## Non-solid blocks: no collision, bodies and rays pass through.
const PASSABLE_BLOCKS := ["water"]

var terrain: VoxelTerrain
var stream: VoxelStreamSQLite
var voxel_tool: VoxelTool
var working_database_path := ""
var revision := 0
var generator_version := P1_GENERATOR_VERSION
var world_seed := DEFAULT_WORLD_SEED
var _spawn_ready_emitted := false
var _ready_feet := SPAWN_FEET


func initialize(database_path: String, ready_feet: Vector3 = SPAWN_FEET, world_snapshot: Dictionary = {}) -> Dictionary:
	working_database_path = database_path
	_ready_feet = ready_feet
	var world_config_result := _load_world_config()
	if not world_config_result.get("ok", false):
		return world_config_result
	var generation_result := resolve_generation(world_snapshot, world_config_result.get("config", {}))
	if not generation_result.get("ok", false):
		return generation_result
	generator_version = str(generation_result.get("generator_version", P1_GENERATOR_VERSION))
	world_seed = int(generation_result.get("seed", DEFAULT_WORLD_SEED))
	var config: Dictionary = world_config_result.get("config", {})
	var config_min: Variant = config.get("min_cell", [])
	var config_size: Variant = config.get("size", [])
	if config_min is Array and config_min.size() == 3 and config_size is Array and config_size.size() == 3:
		WORLD_MIN = Vector3i(int(config_min[0]), int(config_min[1]), int(config_min[2]))
		WORLD_SIZE = Vector3i(int(config_size[0]), int(config_size[1]), int(config_size[2]))
	var parent_dir := database_path.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(parent_dir)
	if mkdir_error != OK:
		return {"ok": false, "reason": "WORKING_DIRECTORY_FAILED", "error": mkdir_error}

	terrain = VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.bounds = AABB(Vector3(WORLD_MIN), Vector3(WORLD_SIZE))
	terrain.mesh_block_size = 16
	terrain.max_view_distance = 64
	terrain.generate_collisions = true
	terrain.collision_layer = 1
	terrain.collision_mask = 1
	if generator_version == LEGACY_GENERATOR_VERSION:
		terrain.generator = FlatWorldGenerator.new()
	else:
		var terrain_settings: Dictionary = generation_result.get("terrain", {}).duplicate(true)
		terrain_settings["bounds_min"] = [WORLD_MIN.x, WORLD_MIN.y, WORLD_MIN.z]
		terrain_settings["bounds_size"] = [WORLD_SIZE.x, WORLD_SIZE.y, WORLD_SIZE.z]
		terrain.generator = P1TerrainGenerator.new(world_seed, terrain_settings)

	var library := VoxelBlockyLibrary.new()
	library.add_model(VoxelBlockyModelEmpty.new())
	for block_id in range(1, BLOCK_NAMES.size()):
		var model := VoxelBlockyModelCube.new()
		model.resource_name = BLOCK_NAMES[block_id]
		# Every block currently owns one complete face texture, not a shared atlas.
		# Declaring the 1x1 tile geometry is required so Voxel Tools emits UVs for
		# the full texture instead of sampling only an atlas-sized corner.
		model.atlas_size_in_tiles = Vector2i.ONE
		model.color = BLOCK_COLORS[block_id]
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		var texture_path := "res://assets/blocks/%s.svg" % BLOCK_NAMES[block_id]
		if ResourceLoader.exists(texture_path):
			material.albedo_texture = load(texture_path)
		if BLOCK_NAMES[block_id] in PASSABLE_BLOCKS:
			# Water: translucent, no collision, drawn only against non-water.
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(1.0, 1.0, 1.0, 0.6)
			material.roughness = 0.2
			model.collision_mask = 0
			model.collision_aabbs = []
			model.transparency_index = 1
			model.culls_neighbors = false
		model.set_material_override(0, material)
		library.add_model(model)
	library.bake()

	var mesher := VoxelMesherBlocky.new()
	mesher.library = library
	mesher.occlusion_enabled = true
	terrain.mesher = mesher

	stream = VoxelStreamSQLite.new()
	stream.database_path = database_path
	stream.set_key_cache_enabled(true)
	terrain.stream = stream
	add_child(terrain)
	voxel_tool = terrain.get_voxel_tool()
	voxel_tool.channel = CHANNEL
	set_process(true)
	status_changed.emit("Loading collision-ready voxel terrain…")
	return {"ok": true}


static func resolve_generation(world_snapshot: Dictionary, world_config: Dictionary) -> Dictionary:
	# Foundation saves predate generator metadata. They must retain the terrain they
	# were created against so untouched SQLite chunks never regenerate differently.
	var version := str(world_snapshot.get("generator_version", LEGACY_GENERATOR_VERSION))
	var seed := int(world_snapshot.get("seed", world_config.get("seed", DEFAULT_WORLD_SEED)))
	if version == LEGACY_GENERATOR_VERSION:
		return {"ok": true, "generator_version": version, "seed": seed, "terrain": {}}
	if version == P1_GENERATOR_VERSION:
		return {"ok": true, "generator_version": version, "seed": seed, "terrain": world_config.get("terrain", {})}
	return {"ok": false, "reason": "UNSUPPORTED_GENERATOR_VERSION", "found": version, "supported": [LEGACY_GENERATOR_VERSION, P1_GENERATOR_VERSION]}


func _load_world_config() -> Dictionary:
	var file := FileAccess.open(WORLD_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "WORLD_CONFIG_READ_FAILED", "error": FileAccess.get_open_error()}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "reason": "WORLD_CONFIG_INVALID"}
	return {"ok": true, "config": parsed}


func _process(_delta: float) -> void:
	if _spawn_ready_emitted or terrain == null or voxel_tool == null:
		return
	var spawn_area := AABB(_ready_feet + Vector3(-1.0, -3.0, -1.0), Vector3(2.0, 5.0, 2.0))
	if terrain.is_area_meshed(spawn_area) and voxel_tool.is_area_editable(spawn_area):
		_spawn_ready_emitted = true
		status_changed.emit("Terrain ready")
		spawn_area_ready.emit()


func is_in_bounds(cell: Vector3i) -> bool:
	var maximum := WORLD_MIN + WORLD_SIZE
	return cell.x >= WORLD_MIN.x and cell.y >= WORLD_MIN.y and cell.z >= WORLD_MIN.z \
		and cell.x < maximum.x and cell.y < maximum.y and cell.z < maximum.z


func query_cell(cell: Vector3i) -> Dictionary:
	if not is_in_bounds(cell):
		return {"state": "OUT_OF_BOUNDS"}
	var area := AABB(Vector3(cell), Vector3.ONE)
	if voxel_tool == null or not voxel_tool.is_area_editable(area):
		return {"state": "UNLOADED"}
	return {"state": "LOADED", "voxel_id": voxel_tool.get_voxel(cell)}


func set_cell(cell: Vector3i, voxel_id: int) -> bool:
	var query := query_cell(cell)
	if query.get("state") != "LOADED":
		return false
	var previous_voxel_id := int(query.get("voxel_id", 0))
	if previous_voxel_id == voxel_id:
		return true
	voxel_tool.set_voxel(cell, voxel_id)
	if voxel_tool.get_voxel(cell) != voxel_id:
		return false
	revision += 1
	cell_changed.emit(cell, previous_voxel_id, voxel_id, revision)
	return true


func raycast(origin: Vector3, direction: Vector3, distance: float = 5.0) -> VoxelRaycastResult:
	if voxel_tool == null:
		return null
	return voxel_tool.raycast(origin, direction.normalized(), distance)


func freeze_streaming_for_save() -> void:
	set_process(false)
	if terrain != null:
		terrain.automatic_loading_enabled = false


func detach_and_close_stream() -> void:
	if terrain != null:
		terrain.stream = null
	if stream != null:
		stream.database_path = ""


func resume_streaming_after_failed_save() -> void:
	if terrain == null:
		return
	if stream == null or stream.database_path.is_empty():
		stream = VoxelStreamSQLite.new()
		stream.database_path = working_database_path
		stream.set_key_cache_enabled(true)
	terrain.stream = stream
	terrain.automatic_loading_enabled = true
	set_process(true)


func snapshot() -> Dictionary:
	return {
		"revision": revision,
		"generator_version": generator_version,
		"seed": world_seed,
		"bounds_min": [WORLD_MIN.x, WORLD_MIN.y, WORLD_MIN.z],
		"bounds_size": [WORLD_SIZE.x, WORLD_SIZE.y, WORLD_SIZE.z],
		"database_path": working_database_path,
	}
