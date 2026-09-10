extends SceneTree

const REQUIRED_CLASSES := [
	"VoxelTerrain",
	"VoxelMesherBlocky",
	"VoxelBlockyLibrary",
	"VoxelStreamSQLite",
	"VoxelSaveCompletionTracker",
]


func _initialize() -> void:
	var missing: Array[String] = []
	for required_class in REQUIRED_CLASSES:
		var available := ClassDB.class_exists(required_class)
		print("CLASS %s %s" % [required_class, "PASS" if available else "MISSING"])
		if not available:
			missing.append(required_class)

	if ClassDB.class_exists("VoxelEngine"):
		print("VOXEL_VERSION %s.%s.%s %s %s" % [
			VoxelEngine.get_version_major(),
			VoxelEngine.get_version_minor(),
			VoxelEngine.get_version_patch(),
			VoxelEngine.get_version_edition(),
			VoxelEngine.get_version_git_hash(),
		])
	else:
		missing.append("VoxelEngine")

	print("GODOT_VERSION %s" % Engine.get_version_info().get("string", "unknown"))
	print("RENDERING_METHOD %s" % RenderingServer.get_current_rendering_method())
	quit(0 if missing.is_empty() else 2)
