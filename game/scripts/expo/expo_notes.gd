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
##
## `export_markdown()` is the table the `--expo-notes-export` switch and the
## Directory panel's Export button write to `artifacts/expo_notes.md`.

## The statuses the owner asked for, in the order the panel shows them.
const STATUSES: Array[String] = ["untested", "verified", "working", "broken", "approved"]
const DEFAULT_STATUS := "untested"

## subject_id -> {label, kind, status, entries: Array[{at, status, remark}]}
var _subjects: Dictionary = {}
## The newest `added_in` value the owner has dismissed in the What's new list.
var _last_seen_added_in := ""
## Bumped on every change so a panel can tell whether it must redraw.
var revision := 0


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
	return {"ok": true, "subject": subject_id, "status": wanted, "entry": entry}


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
