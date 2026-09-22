extends Node

const REQUIRED_CLASSES := [
	"VoxelTerrain",
	"VoxelMesherBlocky",
	"VoxelBlockyLibrary",
	"VoxelStreamSQLite",
	"VoxelSaveCompletionTracker",
]


func _ready() -> void:
	var missing: Array[String] = []
	for required_class in REQUIRED_CLASSES:
		if not ClassDB.class_exists(required_class):
			missing.append(required_class)
	if missing.is_empty():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/app/app.tscn")
		return

	var message := "WRONG ENGINE BUILD\n\nCraft and Defend F0 requires the pinned Godot 4.6 + Voxel Tools 1.6 Module editor/export template.\nMissing classes: %s\n\nRun START.cmd or follow docs/WINDOWS_SETUP.md." % ", ".join(missing)
	push_error("FATAL_TOOLCHAIN_MISMATCH: %s" % message.replace("\n", " "))
	var background := ColorRect.new()
	background.color = Color("17222c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 80)
	label.add_theme_font_size_override("font_size", 22)
	background.add_child(label)
