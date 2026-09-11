class_name SaveCoordinator
extends RefCounted

const SAVE_SCHEMA := 1
const CONTENT_VERSION := "foundation-1"
const CHECKPOINT_TIMEOUT_MS := 15000

var data_root: String
var slots_root: String
var runtime_root: String
var current_pointer_path: String


func _init(root_path: String) -> void:
	data_root = root_path
	slots_root = data_root.path_join("slots/default/checkpoints")
	runtime_root = data_root.path_join("runtime")
	current_pointer_path = data_root.path_join("slots/default/current.json")
	DirAccess.make_dir_recursive_absolute(slots_root)
	DirAccess.make_dir_recursive_absolute(runtime_root)


func has_checkpoint() -> bool:
	return _read_current_checkpoint().get("ok", false)


func open_session(continue_existing: bool) -> Dictionary:
	var session_id := "%s_%s" % [Time.get_unix_time_from_system(), randi()]
	var working_dir := runtime_root.path_join(session_id)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(working_dir)
	if mkdir_error != OK:
		return {"ok": false, "reason": "RUNTIME_DIRECTORY_FAILED", "error": mkdir_error}
	var working_database := working_dir.path_join("world.sqlite")
	var snapshot := _default_snapshot()
	if continue_existing:
		var checkpoint := _read_current_checkpoint()
		if not checkpoint.get("ok", false):
			return checkpoint
		var copy_error := DirAccess.copy_absolute(checkpoint.database_path, working_database)
		if copy_error != OK:
			return {"ok": false, "reason": "CHECKPOINT_COPY_FAILED", "error": copy_error}
		snapshot = checkpoint.snapshot
	return {
		"ok": true,
		"session_id": session_id,
		"working_dir": working_dir,
		"working_database": working_database,
		"snapshot": snapshot,
		"continued": continue_existing,
	}


func save_session(session: GameSession) -> Dictionary:
	if session == null or session.world == null:
		return {"ok": false, "reason": "NO_ACTIVE_SESSION"}
	session.freeze_for_save()
	session.world.freeze_streaming_for_save()
	var tracker: VoxelSaveCompletionTracker = session.world.terrain.save_modified_blocks()
	if tracker == null:
		return {"ok": false, "reason": "SAVE_TRACKER_MISSING"}
	var started := Time.get_ticks_msec()
	while not tracker.is_complete():
		if tracker.is_aborted():
			return {"ok": false, "reason": "VOXEL_SAVE_ABORTED"}
		if Time.get_ticks_msec() - started > CHECKPOINT_TIMEOUT_MS:
			return {"ok": false, "reason": "VOXEL_SAVE_TIMEOUT", "remaining": tracker.get_remaining_tasks()}
		await session.get_tree().process_frame

	var drain_result := await _wait_for_streaming_idle(session.get_tree())
	if not drain_result.get("ok", false):
		return drain_result
	session.world.detach_and_close_stream()
	var close_result := await _wait_for_streaming_idle(session.get_tree())
	if not close_result.get("ok", false):
		return close_result

	var source_database := session.world.working_database_path
	if not FileAccess.file_exists(source_database):
		return {"ok": false, "reason": "WORKING_DATABASE_MISSING", "path": source_database}

	var previous := _read_json(current_pointer_path)
	var revision := int(previous.get("revision", 0)) + 1
	var checkpoint_name := "checkpoint_%06d" % revision
	var final_dir := slots_root.path_join(checkpoint_name)
	var pending_dir := slots_root.path_join(".pending_%s_%s" % [revision, Time.get_ticks_msec()])
	var mkdir_error := DirAccess.make_dir_recursive_absolute(pending_dir)
	if mkdir_error != OK:
		return {"ok": false, "reason": "CHECKPOINT_DIRECTORY_FAILED", "error": mkdir_error}

	var database_destination := pending_dir.path_join("world.sqlite")
	var copy_error := DirAccess.copy_absolute(source_database, database_destination)
	if copy_error != OK:
		return {"ok": false, "reason": "DATABASE_SNAPSHOT_FAILED", "error": copy_error}
	var snapshot := session.snapshot()
	snapshot["checkpoint_revision"] = revision
	var snapshot_path := pending_dir.path_join("gameplay.json")
	var snapshot_write := _write_json(snapshot_path, snapshot)
	if snapshot_write != OK:
		return {"ok": false, "reason": "GAMEPLAY_SNAPSHOT_FAILED", "error": snapshot_write}

	var manifest := {
		"schema_version": SAVE_SCHEMA,
		"content_version": CONTENT_VERSION,
		"checkpoint_revision": revision,
		"database_sha256": FileAccess.get_sha256(database_destination),
		"gameplay_sha256": FileAccess.get_sha256(snapshot_path),
		"created_unix": Time.get_unix_time_from_system(),
	}
	var manifest_write := _write_json(pending_dir.path_join("manifest.json"), manifest)
	if manifest_write != OK:
		return {"ok": false, "reason": "MANIFEST_WRITE_FAILED", "error": manifest_write}
	var publish_error := DirAccess.rename_absolute(pending_dir, final_dir)
	if publish_error != OK:
		return {"ok": false, "reason": "CHECKPOINT_PUBLISH_FAILED", "error": publish_error}

	var pointer := {"schema_version": SAVE_SCHEMA, "revision": revision, "checkpoint": checkpoint_name}
	var pointer_tmp := current_pointer_path + ".tmp"
	var pointer_write := _write_json(pointer_tmp, pointer)
	if pointer_write != OK:
		return {"ok": false, "reason": "POINTER_WRITE_FAILED", "error": pointer_write}
	var pointer_publish := DirAccess.rename_absolute(pointer_tmp, current_pointer_path)
	if pointer_publish != OK:
		return {"ok": false, "reason": "POINTER_PUBLISH_FAILED", "error": pointer_publish}
	return {
		"ok": true,
		"reason": "OK",
		"revision": revision,
		"checkpoint_dir": final_dir,
		"database_sha256": manifest.database_sha256,
		"gameplay_sha256": manifest.gameplay_sha256,
		"tracker_tasks": tracker.get_total_tasks(),
	}


func _wait_for_streaming_idle(tree: SceneTree) -> Dictionary:
	var started := Time.get_ticks_msec()
	var stable_frames := 0
	while stable_frames < 3:
		var stats: Dictionary = VoxelEngine.get_stats()
		var tasks: Dictionary = stats.get("tasks", {})
		if int(tasks.get("streaming", -1)) == 0:
			stable_frames += 1
		else:
			stable_frames = 0
		if Time.get_ticks_msec() - started > CHECKPOINT_TIMEOUT_MS:
			return {"ok": false, "reason": "STREAM_DRAIN_TIMEOUT", "stats": stats}
		await tree.process_frame
	return {"ok": true}


func _read_current_checkpoint() -> Dictionary:
	var pointer := _read_json(current_pointer_path)
	if int(pointer.get("schema_version", -1)) != SAVE_SCHEMA:
		return {"ok": false, "reason": "NO_VALID_CHECKPOINT"}
	var checkpoint_name := str(pointer.get("checkpoint", ""))
	if checkpoint_name.is_empty() or checkpoint_name.contains("/") or checkpoint_name.contains("\\"):
		return {"ok": false, "reason": "INVALID_CHECKPOINT_POINTER"}
	var checkpoint_dir := slots_root.path_join(checkpoint_name)
	var manifest_path := checkpoint_dir.path_join("manifest.json")
	var snapshot_path := checkpoint_dir.path_join("gameplay.json")
	var database_path := checkpoint_dir.path_join("world.sqlite")
	var manifest := _read_json(manifest_path)
	var snapshot := _read_json(snapshot_path)
	if int(manifest.get("schema_version", -1)) != SAVE_SCHEMA:
		return {"ok": false, "reason": "UNSUPPORTED_SAVE_SCHEMA"}
	if str(manifest.get("content_version", "")) != CONTENT_VERSION:
		return {"ok": false, "reason": "MISSING_CONTENT_VERSION"}
	if not FileAccess.file_exists(database_path) or snapshot.is_empty():
		return {"ok": false, "reason": "INCOMPLETE_CHECKPOINT"}
	if FileAccess.get_sha256(database_path) != str(manifest.get("database_sha256", "")):
		return {"ok": false, "reason": "DATABASE_HASH_MISMATCH"}
	if FileAccess.get_sha256(snapshot_path) != str(manifest.get("gameplay_sha256", "")):
		return {"ok": false, "reason": "GAMEPLAY_HASH_MISMATCH"}
	return {"ok": true, "snapshot": snapshot, "database_path": database_path, "checkpoint_dir": checkpoint_dir}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	file.close()
	return OK


func _default_snapshot() -> Dictionary:
	return {
		"schema_version": SAVE_SCHEMA,
		"content_version": CONTENT_VERSION,
		"world": {"revision": 0},
		"inventory": {"dirt": 0, "revision": 0},
		"workstations": {"stations": [], "jobs": {}, "next_instance": 1, "next_job": 1},
		"player": {"position": [0.5, 2.0, 40.5], "yaw": 0.0, "pitch": 0.0},
	}
