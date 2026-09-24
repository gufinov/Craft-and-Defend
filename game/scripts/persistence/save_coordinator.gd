class_name SaveCoordinator
extends RefCounted

const SAVE_SCHEMA := 1
const CONTENT_VERSION := "foundation-1"
const CHECKPOINT_TIMEOUT_MS := 60000
const SLOT_IDS: Array[String] = ["a", "b"]
const DEFAULT_SLOT := "a"
const CHECKPOINTS_TO_KEEP := 2
const DEFAULT_GENERATOR_VERSION := "terrain_p1_1"
const DEFAULT_WORLD_SEED := 41026

## New games draw a fresh world seed (owner 2026-09-19: "the world generates
## the same seed over and over"); diagnostics keep the fixed default seed so
## their fixtures stay deterministic (the app clears this under automation).
var random_world_seed := true
var data_root: String
var slots_base_root: String
var runtime_root: String
var slot_id := DEFAULT_SLOT
var slot_root: String
var slots_root: String
var current_pointer_path: String
var migration_report: Dictionary = {"ok": true, "migrated": false}
var test_failure_point := ""


func _init(root_path: String, requested_slot: String = DEFAULT_SLOT) -> void:
	data_root = root_path
	slots_base_root = data_root.path_join("slots")
	runtime_root = data_root.path_join("runtime")
	DirAccess.make_dir_recursive_absolute(slots_base_root)
	DirAccess.make_dir_recursive_absolute(runtime_root)
	migration_report = _migrate_legacy_default_if_needed()
	select_slot(requested_slot)


func select_slot(requested_slot: String) -> Dictionary:
	var normalized := requested_slot.to_lower()
	if normalized not in SLOT_IDS:
		return {"ok": false, "reason": "INVALID_SLOT_ID", "slot_id": requested_slot}
	slot_id = normalized
	slot_root = slots_base_root.path_join(slot_id)
	slots_root = slot_root.path_join("checkpoints")
	current_pointer_path = slot_root.path_join("current.json")
	DirAccess.make_dir_recursive_absolute(slots_root)
	return {"ok": true, "reason": "OK", "slot_id": slot_id, "status": checkpoint_status()}


func checkpoint_status(requested_slot: String = "") -> Dictionary:
	var checked_slot := slot_id if requested_slot.is_empty() else requested_slot.to_lower()
	if checked_slot not in SLOT_IDS:
		return {"ok": false, "reason": "INVALID_SLOT_ID", "slot_id": checked_slot}
	var checked_root := slots_base_root.path_join(checked_slot)
	var result := _read_current_checkpoint_paths(checked_root.path_join("current.json"), checked_root.path_join("checkpoints"))
	result["slot_id"] = checked_slot
	return result


func has_checkpoint() -> bool:
	return checkpoint_status().get("ok", false)


## The current checkpoint's snapshot without opening a session: what the
## `--expo-notes-export` switch reads out of the development save.
func read_checkpoint() -> Dictionary:
	return _read_current_checkpoint()


func set_test_failure(point: String) -> void:
	test_failure_point = point


func open_session(continue_existing: bool) -> Dictionary:
	var snapshot := _default_snapshot()
	if not continue_existing and random_world_seed:
		# Every player starts with their Core of Power (owner 2026-09-19).
		# Diagnostics (fixed seed) keep the empty pack their fixtures assume.
		snapshot["inventory"] = {"dirt": 0, "revision": 0, "grant": {"core_of_power": 1}}
	if random_world_seed and not continue_existing:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		snapshot["world"]["seed"] = int(rng.randi_range(1, 2147483646))
	var checkpoint: Dictionary = {}
	if continue_existing:
		checkpoint = _read_current_checkpoint()
		if not checkpoint.get("ok", false):
			return checkpoint
		snapshot = checkpoint.snapshot
	var session_id := "%s_%s_%s" % [slot_id, Time.get_unix_time_from_system(), randi()]
	var working_dir := runtime_root.path_join(session_id)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(working_dir)
	if mkdir_error != OK:
		return {"ok": false, "reason": "RUNTIME_DIRECTORY_FAILED", "error": mkdir_error}
	var working_database := working_dir.path_join("world.sqlite")
	if continue_existing:
		var copy_error := DirAccess.copy_absolute(checkpoint.database_path, working_database)
		if copy_error != OK:
			return {"ok": false, "reason": "CHECKPOINT_COPY_FAILED", "error": copy_error}
	return {"ok": true, "session_id": session_id, "slot_id": slot_id, "working_dir": working_dir, "working_database": working_database, "snapshot": snapshot, "continued": continue_existing}


func save_session(session: GameSession) -> Dictionary:
	var save_started := Time.get_ticks_msec()
	if session == null or session.world == null:
		return {"ok": false, "reason": "NO_ACTIVE_SESSION"}
	session.freeze_for_save()
	session.world.freeze_streaming_for_save()
	if _consume_failure("denied_write"):
		return _save_failure(session, "INJECTED_DENIED_WRITE")
	var tracker: VoxelSaveCompletionTracker = session.world.terrain.save_modified_blocks()
	if tracker == null:
		return _save_failure(session, "SAVE_TRACKER_MISSING")
	var started := Time.get_ticks_msec()
	while not tracker.is_complete():
		if tracker.is_aborted():
			return _save_failure(session, "VOXEL_SAVE_ABORTED")
		if Time.get_ticks_msec() - started > CHECKPOINT_TIMEOUT_MS:
			return _save_failure(session, "VOXEL_SAVE_TIMEOUT", {"remaining": tracker.get_remaining_tasks()})
		await session.get_tree().process_frame
	var drain_result := await _wait_for_streaming_idle(session.get_tree())
	if not drain_result.get("ok", false):
		return _save_failure(session, str(drain_result.get("reason", "STREAM_DRAIN_FAILED")), drain_result)
	session.world.detach_and_close_stream()
	var close_result := await _wait_for_streaming_idle(session.get_tree())
	if not close_result.get("ok", false):
		return _save_failure(session, str(close_result.get("reason", "STREAM_CLOSE_FAILED")), close_result)
	var source_database := session.world.working_database_path
	if not FileAccess.file_exists(source_database):
		return _save_failure(session, "WORKING_DATABASE_MISSING", {"path": source_database})
	var previous := _read_pointer_with_fallback(current_pointer_path)
	var revision := int(previous.get("data", {}).get("revision", 0)) + 1
	var checkpoint_name := "checkpoint_%06d_%d" % [revision, Time.get_ticks_msec()]
	var final_dir := slots_root.path_join(checkpoint_name)
	var pending_dir := slots_root.path_join(".pending_%s" % checkpoint_name)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(pending_dir)
	if mkdir_error != OK:
		return _save_failure(session, "CHECKPOINT_DIRECTORY_FAILED", {"error": mkdir_error})
	var database_destination := pending_dir.path_join("world.sqlite")
	var copy_error := DirAccess.copy_absolute(source_database, database_destination)
	if copy_error != OK:
		return _save_failure(session, "DATABASE_SNAPSHOT_FAILED", {"error": copy_error})
	if _consume_failure("disk_full"):
		return _save_failure(session, "INJECTED_DISK_FULL", {"pending_dir": pending_dir})
	var snapshot := session.snapshot()
	snapshot["checkpoint_revision"] = revision
	snapshot["slot_id"] = slot_id
	var snapshot_path := pending_dir.path_join("gameplay.json")
	var snapshot_write := _write_json(snapshot_path, snapshot)
	if snapshot_write != OK:
		return _save_failure(session, "GAMEPLAY_SNAPSHOT_FAILED", {"error": snapshot_write})
	var manifest := {"schema_version": SAVE_SCHEMA, "content_version": CONTENT_VERSION, "checkpoint_revision": revision, "slot_id": slot_id, "database_sha256": FileAccess.get_sha256(database_destination), "gameplay_sha256": FileAccess.get_sha256(snapshot_path), "created_unix": Time.get_unix_time_from_system()}
	var manifest_write := _write_json(pending_dir.path_join("manifest.json"), manifest)
	if manifest_write != OK:
		return _save_failure(session, "MANIFEST_WRITE_FAILED", {"error": manifest_write})
	if _consume_failure("before_checkpoint_publish"):
		return _save_failure(session, "INJECTED_BEFORE_CHECKPOINT_PUBLISH", {"pending_dir": pending_dir})
	var publish_error := DirAccess.rename_absolute(pending_dir, final_dir)
	if publish_error != OK:
		return _save_failure(session, "CHECKPOINT_PUBLISH_FAILED", {"error": publish_error})
	if _consume_failure("after_checkpoint_publish"):
		return _save_failure(session, "INJECTED_AFTER_CHECKPOINT_PUBLISH", {"orphan_checkpoint": final_dir})
	var pointer := {"schema_version": SAVE_SCHEMA, "revision": revision, "checkpoint": checkpoint_name, "slot_id": slot_id}
	var pointer_result := _publish_pointer(pointer)
	if not pointer_result.get("ok", false):
		return _save_failure(session, str(pointer_result.get("reason", "POINTER_PUBLISH_FAILED")), pointer_result)
	_prune_completed_checkpoints(checkpoint_name)
	return {"ok": true, "reason": "OK", "slot_id": slot_id, "revision": revision, "checkpoint_dir": final_dir, "database_sha256": manifest.database_sha256, "gameplay_sha256": manifest.gameplay_sha256, "checkpoint_bytes": _directory_size(final_dir), "save_msec": Time.get_ticks_msec() - save_started, "tracker_tasks": tracker.get_total_tasks()}


func _publish_pointer(pointer: Dictionary) -> Dictionary:
	var pointer_tmp := current_pointer_path + ".tmp"
	var pointer_backup := current_pointer_path + ".backup"
	_remove_file_if_present(pointer_tmp)
	var pointer_write := _write_json(pointer_tmp, pointer)
	if pointer_write != OK:
		return {"ok": false, "reason": "POINTER_WRITE_FAILED", "error": pointer_write}
	if _consume_failure("before_pointer_publish"):
		return {"ok": false, "reason": "INJECTED_BEFORE_POINTER_PUBLISH"}
	_remove_file_if_present(pointer_backup)
	var had_current := FileAccess.file_exists(current_pointer_path)
	if had_current:
		var backup_error := DirAccess.rename_absolute(current_pointer_path, pointer_backup)
		if backup_error != OK:
			return {"ok": false, "reason": "POINTER_BACKUP_FAILED", "error": backup_error}
	if _consume_failure("during_pointer_publish"):
		return {"ok": false, "reason": "INJECTED_DURING_POINTER_PUBLISH", "backup_available": had_current}
	var publish_error := DirAccess.rename_absolute(pointer_tmp, current_pointer_path)
	if publish_error != OK:
		if had_current and FileAccess.file_exists(pointer_backup):
			DirAccess.rename_absolute(pointer_backup, current_pointer_path)
		return {"ok": false, "reason": "POINTER_PUBLISH_FAILED", "error": publish_error}
	_remove_file_if_present(pointer_backup)
	return {"ok": true, "reason": "OK"}


func _save_failure(session: GameSession, reason: String, details: Dictionary = {}) -> Dictionary:
	session.recover_from_failed_save()
	var result := details.duplicate(true)
	result["ok"] = false
	result["reason"] = reason
	return result


func _consume_failure(point: String) -> bool:
	if test_failure_point != point:
		return false
	test_failure_point = ""
	return true


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
	return _read_current_checkpoint_paths(current_pointer_path, slots_root)


func _read_current_checkpoint_paths(pointer_path: String, checkpoints_path: String) -> Dictionary:
	var pointer_result := _read_pointer_with_fallback(pointer_path)
	if not pointer_result.get("ok", false):
		return pointer_result
	var pointer: Dictionary = pointer_result.data
	var pointer_schema := int(pointer.get("schema_version", -1))
	if pointer_schema != SAVE_SCHEMA:
		return {"ok": false, "reason": "UNSUPPORTED_SAVE_SCHEMA", "found": pointer_schema, "supported": SAVE_SCHEMA}
	var checkpoint_name := str(pointer.get("checkpoint", ""))
	if checkpoint_name.is_empty() or checkpoint_name.contains("/") or checkpoint_name.contains("\\"):
		return {"ok": false, "reason": "INVALID_CHECKPOINT_POINTER"}
	var checkpoint_dir := checkpoints_path.path_join(checkpoint_name)
	var manifest_result := _read_json_checked(checkpoint_dir.path_join("manifest.json"), "MANIFEST")
	if not manifest_result.get("ok", false):
		return manifest_result
	var snapshot_result := _read_json_checked(checkpoint_dir.path_join("gameplay.json"), "GAMEPLAY")
	if not snapshot_result.get("ok", false):
		return snapshot_result
	var manifest: Dictionary = manifest_result.data
	var snapshot: Dictionary = snapshot_result.data
	var manifest_schema := int(manifest.get("schema_version", -1))
	if manifest_schema != SAVE_SCHEMA:
		return {"ok": false, "reason": "UNSUPPORTED_SAVE_SCHEMA", "found": manifest_schema, "supported": SAVE_SCHEMA}
	if str(manifest.get("content_version", "")) != CONTENT_VERSION or str(snapshot.get("content_version", "")) != CONTENT_VERSION:
		return {"ok": false, "reason": "MISSING_CONTENT_VERSION", "required": CONTENT_VERSION}
	var database_path := checkpoint_dir.path_join("world.sqlite")
	var snapshot_path := checkpoint_dir.path_join("gameplay.json")
	if not FileAccess.file_exists(database_path):
		return {"ok": false, "reason": "INCOMPLETE_CHECKPOINT"}
	if FileAccess.get_sha256(database_path) != str(manifest.get("database_sha256", "")):
		return {"ok": false, "reason": "DATABASE_HASH_MISMATCH"}
	if FileAccess.get_sha256(snapshot_path) != str(manifest.get("gameplay_sha256", "")):
		return {"ok": false, "reason": "GAMEPLAY_HASH_MISMATCH"}
	return {"ok": true, "snapshot": snapshot, "database_path": database_path, "checkpoint_dir": checkpoint_dir, "revision": int(pointer.get("revision", 0)), "recovered_pointer": pointer_result.get("recovered", false)}


func _read_pointer_with_fallback(pointer_path: String) -> Dictionary:
	var primary := _read_json_checked(pointer_path, "POINTER")
	if primary.get("ok", false):
		return primary
	var backup := _read_json_checked(pointer_path + ".backup", "POINTER")
	if backup.get("ok", false):
		backup["recovered"] = true
		if not FileAccess.file_exists(pointer_path):
			DirAccess.copy_absolute(pointer_path + ".backup", pointer_path)
		return backup
	return primary


func _read_json_checked(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "NO_VALID_CHECKPOINT" if label == "POINTER" else "INCOMPLETE_CHECKPOINT", "path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "%s_READ_FAILED" % label, "error": FileAccess.get_open_error()}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK or not json.data is Dictionary:
		return {"ok": false, "reason": "MALFORMED_%s" % label, "line": json.get_error_line(), "message": json.get_error_message()}
	return {"ok": true, "data": json.data}


func _write_json(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	file.close()
	return OK


func _migrate_legacy_default_if_needed() -> Dictionary:
	var legacy_root := slots_base_root.path_join("default")
	var target_root := slots_base_root.path_join(DEFAULT_SLOT)
	if DirAccess.dir_exists_absolute(target_root) or not FileAccess.file_exists(legacy_root.path_join("current.json")):
		return {"ok": true, "migrated": false}
	var pending := slots_base_root.path_join(".migration_%s_%d" % [DEFAULT_SLOT, Time.get_ticks_msec()])
	var copied := _copy_directory_recursive(legacy_root, pending)
	if not copied.get("ok", false):
		return copied
	var publish_error := DirAccess.rename_absolute(pending, target_root)
	if publish_error != OK:
		return {"ok": false, "reason": "MIGRATION_PUBLISH_FAILED", "error": publish_error}
	return {"ok": true, "migrated": true, "source": legacy_root, "destination": target_root, "source_preserved": DirAccess.dir_exists_absolute(legacy_root)}


func _copy_directory_recursive(source: String, destination: String) -> Dictionary:
	var mkdir_error := DirAccess.make_dir_recursive_absolute(destination)
	if mkdir_error != OK:
		return {"ok": false, "reason": "MIGRATION_DIRECTORY_FAILED", "error": mkdir_error}
	var directory := DirAccess.open(source)
	if directory == null:
		return {"ok": false, "reason": "MIGRATION_SOURCE_FAILED"}
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var source_path := source.path_join(name)
			var destination_path := destination.path_join(name)
			if directory.current_is_dir():
				var nested := _copy_directory_recursive(source_path, destination_path)
				if not nested.get("ok", false):
					directory.list_dir_end()
					return nested
			else:
				var copy_error := DirAccess.copy_absolute(source_path, destination_path)
				if copy_error != OK:
					directory.list_dir_end()
					return {"ok": false, "reason": "MIGRATION_COPY_FAILED", "error": copy_error, "path": source_path}
		name = directory.get_next()
	directory.list_dir_end()
	return {"ok": true}


func _prune_completed_checkpoints(current_name: String) -> void:
	var candidates: Array[Dictionary] = []
	var directory := DirAccess.open(slots_root)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if directory.current_is_dir() and name.begins_with("checkpoint_"):
			var manifest_result := _read_json_checked(slots_root.path_join(name).path_join("manifest.json"), "MANIFEST")
			if manifest_result.get("ok", false):
				candidates.append({"name": name, "revision": int(manifest_result.data.get("checkpoint_revision", 0))})
		name = directory.get_next()
	directory.list_dir_end()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.revision) > int(b.revision))
	var keep: Array[String] = [current_name]
	for candidate: Dictionary in candidates:
		var candidate_name := str(candidate.name)
		if candidate_name != current_name and keep.size() < CHECKPOINTS_TO_KEEP:
			keep.append(candidate_name)
	for candidate: Dictionary in candidates:
		var candidate_name := str(candidate.name)
		if candidate_name not in keep:
			_remove_directory_recursive(slots_root.path_join(candidate_name))


func _directory_size(path: String) -> int:
	var total := 0
	var directory := DirAccess.open(path)
	if directory == null:
		return 0
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir():
			total += _directory_size(child)
		else:
			total += FileAccess.get_file_as_bytes(child).size()
		name = directory.get_next()
	directory.list_dir_end()
	return total


func _remove_directory_recursive(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_directory_recursive(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _remove_file_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _default_snapshot() -> Dictionary:
	return {"schema_version": SAVE_SCHEMA, "content_version": CONTENT_VERSION, "world": {"revision": 0, "generator_version": DEFAULT_GENERATOR_VERSION, "seed": DEFAULT_WORLD_SEED}, "inventory": {"dirt": 0, "revision": 0}, "workstations": {"stations": [], "jobs": {}, "next_instance": 1, "next_job": 1}, "clock": {}, "player": {"position": [0.5, 2.0, 40.5], "yaw": 0.0, "pitch": 0.0}}
