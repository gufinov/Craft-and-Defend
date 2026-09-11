class_name WorldAdapter
extends Node3D

signal spawn_area_ready
signal status_changed(message: String)

const WORLD_MIN := Vector3i(-32, -16, -64)
const WORLD_SIZE := Vector3i(64, 32, 128)
const SPAWN_FEET := Vector3(0.5, 2.0, 40.5)
const CHANNEL := VoxelBuffer.CHANNEL_TYPE

const BLOCK_NAMES := [
	"air", "grass", "dirt", "stone", "log", "planks",
	"coal_ore", "iron_ore", "castle_stone", "bedrock",
]
const BLOCK_COLORS := [
	Color(0, 0, 0, 0), Color("74a65a"), Color("8b5f3c"), Color("777b82"),
	Color("9b6a3d"), Color("b88954"), Color("34383f"), Color("a65b42"),
	Color("8b929d"), Color("25282d"),
]

var terrain: VoxelTerrain
var stream: VoxelStreamSQLite
var voxel_tool: VoxelTool
var working_database_path := ""
var revision := 0
var _spawn_ready_emitted := false
var _ready_feet := SPAWN_FEET


func initialize(database_path: String, ready_feet: Vector3 = SPAWN_FEET) -> Dictionary:
	working_database_path = database_path
	_ready_feet = ready_feet
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
	terrain.generator = FlatWorldGenerator.new()

	var library := VoxelBlockyLibrary.new()
	library.add_model(VoxelBlockyModelEmpty.new())
	for block_id in range(1, BLOCK_NAMES.size()):
		var model := VoxelBlockyModelCube.new()
		model.resource_name = BLOCK_NAMES[block_id]
		model.color = BLOCK_COLORS[block_id]
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		var texture_path := "res://assets/blocks/%s.svg" % BLOCK_NAMES[block_id]
		if ResourceLoader.exists(texture_path):
			material.albedo_texture = load(texture_path)
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
	voxel_tool.set_voxel(cell, voxel_id)
	if voxel_tool.get_voxel(cell) != voxel_id:
		return false
	revision += 1
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


func snapshot() -> Dictionary:
	return {
		"revision": revision,
		"bounds_min": [WORLD_MIN.x, WORLD_MIN.y, WORLD_MIN.z],
		"bounds_size": [WORLD_SIZE.x, WORLD_SIZE.y, WORLD_SIZE.z],
		"database_path": working_database_path,
	}
