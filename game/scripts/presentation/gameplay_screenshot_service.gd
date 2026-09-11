class_name GameplayScreenshotService
extends RefCounted

const SCREENSHOTS_FOLDER := "screenshots"

var screenshots_root: String
var _last_timestamp := ""
var _same_timestamp_index := 0


func _init(data_root: String) -> void:
	screenshots_root = data_root.path_join(SCREENSHOTS_FOLDER)


func capture_viewport(viewport: Viewport) -> Dictionary:
	if viewport == null:
		return {"ok": false, "reason": "NO_VIEWPORT"}
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return {"ok": false, "reason": "EMPTY_FRAME"}
	var directory_error := DirAccess.make_dir_recursive_absolute(screenshots_root)
	if directory_error != OK:
		return {"ok": false, "reason": "DIRECTORY_FAILED", "error": directory_error}
	var filename := _next_filename()
	var path := screenshots_root.path_join(filename)
	var save_error := image.save_png(path)
	if save_error != OK:
		return {"ok": false, "reason": "WRITE_FAILED", "error": save_error, "path": path}
	return {
		"ok": true,
		"reason": "OK",
		"filename": filename,
		"path": path,
		"width": image.get_width(),
		"height": image.get_height(),
		"bytes": FileAccess.get_file_as_bytes(path).size(),
	}


func _next_filename() -> String:
	var timestamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	if timestamp == _last_timestamp:
		_same_timestamp_index += 1
	else:
		_last_timestamp = timestamp
		_same_timestamp_index = 0
	var stem := "CraftAndDefend_%s" % timestamp
	if _same_timestamp_index > 0:
		stem += "_%02d" % _same_timestamp_index
	var filename := stem + ".png"
	while FileAccess.file_exists(screenshots_root.path_join(filename)):
		_same_timestamp_index += 1
		filename = "%s_%02d.png" % [stem, _same_timestamp_index]
	return filename
