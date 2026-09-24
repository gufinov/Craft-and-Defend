class_name ExpoNotes
extends RefCounted

## The Expo's test notes (docs/DEVELOPMENT_EXPO.md, card D1). The owner walks
## up to an exhibit or a station, opens its Notes editor and leaves a remark
## with a status. Notes are:
##
##   * keyed by **subject id** - an exhibit id (`cy_wall_kit`) or a station's
##     instance id for a placed fixture;
##   * **appended**, never overwritten: every remark and every status change is
##     a timestamped entry, so the log reads as a history;
##   * stored in the **development save's own namespace** (`GameSession`
##     writes `snapshot()["expo_notes"]` only while `development` is true), so
##     they survive save / load and no normal or CoasterCraft save is touched.
##   * **written through to disk the moment they are saved** (card D2): the
##     store keeps its own journal, `<data root>/development/expo_notes.json`,
##     outside the world checkpoint. A note is QA evidence, and losing it to a
##     crash or a Quit-without-save is the worst failure this tool has; the
##     world checkpoint is megabytes of voxels and is written when the owner
##     says so, the journal is a few kilobytes and is written on every change.
##
## `export_markdown()` is the table the `--expo-notes-export` switch and the
## Directory panel's Export button write to `artifacts/expo_notes.md`.

## The statuses the owner asked for, in the order the panel shows them.
const STATUSES: Array[String] = ["untested", "verified", "working", "broken", "approved"]
const DEFAULT_STATUS := "untested"
## The journal's file name inside the development data root.
const STORE_FILE := "expo_notes.json"
## The journal's own schema, independent of the save schema.
const STORE_SCHEMA := 1

## subject_id -> {label, kind, status, entries: Array[{at, status, remark}]}
var _subjects: Dictionary = {}
## The newest `added_in` value the owner has dismissed in the What's new list.
var _last_seen_added_in := ""
## Bumped on every change so a panel can tell whether it must redraw.
var revision := 0
## The journal this store writes through to ("" until `bind_store`).
var _store_path := ""
## Suspends the write-through while the store is itself being loaded.
var _loading := false
## What the last write-through did: {ok, reason, path, at}. The panel reads it
## so it can tell the owner the note is on disk (or why it is not).
var last_write: Dictionary = {"ok": false, "reason": "UNBOUND", "path": ""}


static func is_status(value: String) -> bool:
	return STATUSES.has(value)


static func status_label(status: String) -> String:
	return status.capitalize()


## One remark with the status it was left at. An empty remark is allowed: that
## is the "change the status without retyping the remark" case.
func add_note(subject_id: String, remark: String, status: String = DEFAULT_STATUS, label: String = "", kind: String = "") -> Dictionary:
	if subject_id.is_empty():
		return {"ok": false, "reason": "NO_SUBJECT"}
	var wanted := status if is_status(status) else DEFAULT_STATUS
	var record := _subject(subject_id, label, kind)
	var entry := {"at": int(Time.get_unix_time_from_system()), "status": wanted, "remark": remark.strip_edges()}
	var entries: Array = record["entries"]
	entries.append(entry)
	record["status"] = wanted
	if not label.is_empty():
		record["label"] = label
	if not kind.is_empty():
		record["kind"] = kind
	revision += 1
	# Through to disk now, not at the next world save: this is the whole point
	# of the journal (card D2).
	var written := flush()
	return {"ok": true, "subject": subject_id, "status": wanted, "entry": entry,
		"stored": bool(written.get("ok", false)), "store_path": str(written.get("path", "")),
		"store_reason": str(written.get("reason", ""))}


## Changes a subject's status and keeps its newest remark: the status change
## is still appended to the history, with no remark of its own.
func set_status(subject_id: String, status: String, label: String = "", kind: String = "") -> Dictionary:
	if not is_status(status):
		return {"ok": false, "reason": "INVALID_STATUS"}
	return add_note(subject_id, "", status, label, kind)


func has_subject(subject_id: String) -> bool:
	return _subjects.has(subject_id)


func status_of(subject_id: String) -> String:
	var record: Dictionary = _subjects.get(subject_id, {})
	return str(record.get("status", DEFAULT_STATUS))


func label_of(subject_id: String) -> String:
	var record: Dictionary = _subjects.get(subject_id, {})
	return str(record.get("label", ""))


## The newest entry that actually carries a remark ({} when there is none).
func latest_remark(subject_id: String) -> Dictionary:
	var entries := history(subject_id)
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		if not str(entry.get("remark", "")).is_empty():
			return entry
	return {}


func latest_entry(subject_id: String) -> Dictionary:
	var entries := history(subject_id)
	return entries.back() if not entries.is_empty() else {}


## Oldest first.
func history(subject_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var record: Dictionary = _subjects.get(subject_id, {})
	for value: Variant in record.get("entries", []):
		if value is Dictionary:
			result.append(value)
	return result


func note_count(subject_id: String) -> int:
	return history(subject_id).size()


func subject_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _subjects.keys():
		ids.append(key)
	ids.sort()
	return ids


## Subjects with at least one entry, newest activity first.
func subjects() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for subject_id: String in subject_ids():
		var record: Dictionary = _subjects[subject_id]
		var entries: Array = record.get("entries", [])
		if entries.is_empty():
			continue
		var newest: Dictionary = entries.back()
		rows.append({"id": subject_id, "label": str(record.get("label", "")), "kind": str(record.get("kind", "")),
			"status": str(record.get("status", DEFAULT_STATUS)), "at": int(newest.get("at", 0)),
			"remark": str(latest_remark(subject_id).get("remark", "")), "notes": entries.size()})
	rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first.at) > int(second.at))
	return rows


func last_seen_added_in() -> String:
	return _last_seen_added_in


func set_last_seen_added_in(value: String) -> void:
	_last_seen_added_in = value
	revision += 1
	flush()


func clear() -> void:
	_subjects.clear()
	_last_seen_added_in = ""
	revision += 1


func _subject(subject_id: String, label: String, kind: String) -> Dictionary:
	if not _subjects.has(subject_id):
		var entries: Array[Dictionary] = []
		_subjects[subject_id] = {"label": label, "kind": kind, "status": DEFAULT_STATUS, "entries": entries}
	return _subjects[subject_id]


# --- Persistence --------------------------------------------------------------


func snapshot() -> Dictionary:
	var saved: Dictionary = {}
	for subject_id: String in subject_ids():
		var record: Dictionary = _subjects[subject_id]
		var entries: Array = []
		for value: Variant in record.get("entries", []):
			if not value is Dictionary:
				continue
			var entry: Dictionary = value
			entries.append({"at": int(entry.get("at", 0)), "status": str(entry.get("status", DEFAULT_STATUS)), "remark": str(entry.get("remark", ""))})
		saved[subject_id] = {"label": str(record.get("label", "")), "kind": str(record.get("kind", "")),
			"status": str(record.get("status", DEFAULT_STATUS)), "entries": entries}
	return {"subjects": saved, "last_seen_added_in": _last_seen_added_in}


## A malformed record is dropped rather than failing the load: a note is
## bookkeeping, and the world behind it must always open.
func restore(data: Dictionary) -> void:
	clear()
	var saved: Variant = data.get("subjects", {})
	if saved is Dictionary:
		for key: Variant in (saved as Dictionary).keys():
			var subject_id := str(key)
			var value: Variant = (saved as Dictionary)[key]
			if subject_id.is_empty() or not value is Dictionary:
				continue
			var record: Dictionary = value
			var entries: Array[Dictionary] = []
			for raw: Variant in record.get("entries", []):
				if not raw is Dictionary:
					continue
				var entry: Dictionary = raw
				var status := str(entry.get("status", DEFAULT_STATUS))
				entries.append({"at": int(entry.get("at", 0)), "status": status if is_status(status) else DEFAULT_STATUS,
					"remark": str(entry.get("remark", ""))})
			if entries.is_empty():
				continue
			var current := str(record.get("status", DEFAULT_STATUS))
			_subjects[subject_id] = {"label": str(record.get("label", "")), "kind": str(record.get("kind", "")),
				"status": current if is_status(current) else DEFAULT_STATUS, "entries": entries}
	_last_seen_added_in = str(data.get("last_seen_added_in", ""))
	revision += 1


# --- The journal on disk ------------------------------------------------------


## `<data root>/development/expo_notes.json` for a development data root.
static func store_path_for(data_root: String) -> String:
	return data_root.path_join(STORE_FILE) if not data_root.is_empty() else ""


func store_path() -> String:
	return _store_path


func is_bound() -> bool:
	return not _store_path.is_empty()


## Names the journal without reading or writing it: what the read-only
## `--expo-notes-export` switch wants before it calls `load_store()`.
func attach_store(path: String) -> void:
	_store_path = path


## Binds the journal and folds whatever is already on disk into this store.
##
## Merge, not replace, and in this order deliberately: the world checkpoint
## has already been restored into the store by the time Development binds it,
## and the journal holds everything the owner has ever saved - including the
## notes of a session that ended without a world save. Neither is a subset of
## the other after a Reset Expo, so the union is the only honest answer. The
## merged result is written straight back, so the journal is authoritative
## again from the first frame.
func bind_store(path: String) -> Dictionary:
	_store_path = path
	if _store_path.is_empty():
		last_write = {"ok": false, "reason": "UNBOUND", "path": ""}
		return {"ok": false, "reason": "NO_STORE_PATH"}
	var loaded := load_store()
	var written := flush()
	return {"ok": bool(written.get("ok", false)), "reason": str(written.get("reason", "")), "path": _store_path,
		"merged_subjects": int(loaded.get("subjects", 0)), "merged_entries": int(loaded.get("entries", 0)),
		"existed": bool(loaded.get("existed", false))}


## Reads the journal (or the half-written temporary file a crash left behind)
## and merges it in. A malformed journal is ignored rather than fatal - the
## world behind a note must always open.
func load_store() -> Dictionary:
	if _store_path.is_empty():
		return {"ok": false, "reason": "NO_STORE_PATH", "subjects": 0, "entries": 0, "existed": false}
	var read_path := _store_path
	if not FileAccess.file_exists(read_path):
		read_path = _store_path + ".tmp"
		if not FileAccess.file_exists(read_path):
			return {"ok": true, "reason": "NO_STORE", "subjects": 0, "entries": 0, "existed": false}
	var file := FileAccess.open(read_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "READ_FAILED", "subjects": 0, "entries": 0, "existed": true}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "reason": "MALFORMED_STORE", "subjects": 0, "entries": 0, "existed": true}
	var merged := merge(parsed as Dictionary)
	merged["existed"] = true
	return merged


## Folds a `snapshot()`-shaped dictionary into this store: a subject nobody
## has yet is added whole, and a subject both sides know keeps the union of
## their entries. An entry is the same entry when its timestamp, status and
## remark all match, which is what makes loading the journal twice a no-op.
func merge(data: Dictionary) -> Dictionary:
	var was_loading := _loading
	_loading = true
	var added_subjects := 0
	var added_entries := 0
	var saved: Variant = data.get("subjects", {})
	if saved is Dictionary:
		for key: Variant in (saved as Dictionary).keys():
			var subject_id := str(key)
			var value: Variant = (saved as Dictionary)[key]
			if subject_id.is_empty() or not value is Dictionary:
				continue
			var incoming: Dictionary = value
			var known := _subjects.has(subject_id)
			var record := _subject(subject_id, str(incoming.get("label", "")), str(incoming.get("kind", "")))
			if not known:
				added_subjects += 1
			if not str(incoming.get("label", "")).is_empty():
				record["label"] = str(incoming.get("label", ""))
			if not str(incoming.get("kind", "")).is_empty():
				record["kind"] = str(incoming.get("kind", ""))
			var entries: Array = record["entries"]
			var seen: Dictionary = {}
			for existing: Variant in entries:
				if existing is Dictionary:
					seen[_entry_key(existing as Dictionary)] = true
			for raw: Variant in incoming.get("entries", []):
				if not raw is Dictionary:
					continue
				var entry: Dictionary = raw
				var status := str(entry.get("status", DEFAULT_STATUS))
				var clean := {"at": int(entry.get("at", 0)), "status": status if is_status(status) else DEFAULT_STATUS,
					"remark": str(entry.get("remark", ""))}
				var entry_key := _entry_key(clean)
				if seen.has(entry_key):
					continue
				seen[entry_key] = true
				entries.append(clean)
				added_entries += 1
			entries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first.at) < int(second.at))
			# The newest entry's status is the subject's status, whichever side
			# it came from.
			if not entries.is_empty():
				var newest: Dictionary = entries.back()
				record["status"] = str(newest.get("status", DEFAULT_STATUS))
	var incoming_seen := str(data.get("last_seen_added_in", ""))
	if incoming_seen > _last_seen_added_in:
		_last_seen_added_in = incoming_seen
	_loading = was_loading
	revision += 1
	return {"ok": true, "reason": "OK", "subjects": added_subjects, "entries": added_entries}


## Writes the journal. The snapshot goes to a temporary file first and is then
## moved over the real one, so a crash mid-write leaves either the old journal
## or the temporary file - `load_store` reads both.
func flush() -> Dictionary:
	if _loading:
		return {"ok": false, "reason": "LOADING", "path": _store_path}
	if _store_path.is_empty():
		last_write = {"ok": false, "reason": "UNBOUND", "path": ""}
		return last_write.duplicate()
	DirAccess.make_dir_recursive_absolute(_store_path.get_base_dir())
	var temporary := _store_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_write = {"ok": false, "reason": "WRITE_FAILED", "path": _store_path, "at": int(Time.get_unix_time_from_system())}
		return last_write.duplicate()
	var payload := snapshot()
	payload["schema"] = STORE_SCHEMA
	payload["written_at"] = int(Time.get_unix_time_from_system())
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	# Windows will not rename onto an existing file.
	if FileAccess.file_exists(_store_path):
		DirAccess.remove_absolute(_store_path)
	var moved := DirAccess.rename_absolute(temporary, _store_path)
	if moved != OK:
		last_write = {"ok": false, "reason": "MOVE_FAILED", "path": _store_path, "error": moved,
			"at": int(Time.get_unix_time_from_system())}
		return last_write.duplicate()
	last_write = {"ok": true, "reason": "OK", "path": _store_path, "at": int(Time.get_unix_time_from_system())}
	return last_write.duplicate()


static func _entry_key(entry: Dictionary) -> String:
	return "%d|%s|%s" % [int(entry.get("at", 0)), str(entry.get("status", DEFAULT_STATUS)), str(entry.get("remark", ""))]


# --- Export -------------------------------------------------------------------


static func stamp(at: int) -> String:
	if at <= 0:
		return "—"
	return Time.get_datetime_string_from_unix_time(at, true).replace("T", " ")


## The handoff table: one row per subject with its status, newest remark and
## date, then every historical remark underneath.
func export_markdown(title: String = "Development Expo — test notes") -> String:
	var rows := subjects()
	var lines: Array[String] = []
	lines.append("# %s" % title)
	lines.append("")
	lines.append("Written by the Expo Directory (`K` in Development mode) or `--expo-notes-export`.")
	lines.append("Generated %s · %d subject(s)." % [stamp(int(Time.get_unix_time_from_system())), rows.size()])
	lines.append("")
	lines.append("| Subject | Status | Newest remark | Date |")
	lines.append("| --- | --- | --- | --- |")
	for row: Dictionary in rows:
		var label := str(row.get("label", ""))
		var subject := str(row.get("id", ""))
		var shown := "%s (`%s`)" % [label, subject] if not label.is_empty() else "`%s`" % subject
		var remark := str(row.get("remark", ""))
		lines.append("| %s | %s | %s | %s |" % [shown, status_label(str(row.get("status", DEFAULT_STATUS))),
			_cell(remark) if not remark.is_empty() else "—", stamp(int(row.get("at", 0)))])
	lines.append("")
	lines.append("## History")
	lines.append("")
	if rows.is_empty():
		lines.append("No notes have been left yet.")
	for row: Dictionary in rows:
		var subject := str(row.get("id", ""))
		var label := str(row.get("label", ""))
		lines.append("### %s" % ("%s — `%s`" % [label, subject] if not label.is_empty() else subject))
		lines.append("")
		for entry: Dictionary in history(subject):
			var remark := str(entry.get("remark", ""))
			lines.append("- **%s** · %s%s" % [status_label(str(entry.get("status", DEFAULT_STATUS))),
				stamp(int(entry.get("at", 0))), "" if remark.is_empty() else " — %s" % remark])
		lines.append("")
	return "\n".join(lines) + "\n"


## A remark inside a table cell: no pipes, no newlines.
static func _cell(text: String) -> String:
	return text.replace("|", "/").replace("\n", " ").strip_edges()
