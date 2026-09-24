class_name ExpoDirectory
extends RefCounted

## The Expo Directory's model (docs/DEVELOPMENT_EXPO.md, card D1): the campus
## turned into a searchable, filterable list of rows. Pure data in, pure data
## out - it reads the solved `ExpoLayout` and the content registry and never
## touches the world, so the gate can read exactly what the panel shows.
##
## One row per district and per exhibit:
##
## | field | meaning |
## | --- | --- |
## | `id` / `kind` | the exhibit or district id; `exhibit` or `district` |
## | `name` | the sign's title, else the id read out |
## | `district` / `district_name` | which district it stands in |
## | `description` | the sign's body, which is how the owner learns what a Wall Kit is without hunting for it |
## | `icon_item` | the item whose icon the row shows (the sign's item, else the first item, else the first entity) |
## | `category` / `category_label` | `ItemCategories` grouping of `icon_item` |
## | `added_in` | the manifest's optional What's new stamp |
## | `status` / `remark` / `notes` | the newest test note for the row's subject id |
## | `search` | everything above, lowercased, for the search field |

const KIND_EXHIBIT := "exhibit"
const KIND_DISTRICT := "district"

var layout: ExpoLayout
var registry: ContentRegistry
var notes: ExpoNotes


func _init(expo_layout: ExpoLayout = null, content_registry: ContentRegistry = null, expo_notes: ExpoNotes = null) -> void:
	layout = expo_layout
	registry = content_registry
	notes = expo_notes


## Every row of the campus, districts first, then that district's exhibits in
## manifest order.
func entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if layout == null:
		return rows
	for district_id: String in layout.district_ids():
		var district := layout.district(district_id)
		rows.append(_row(district_id, KIND_DISTRICT, district, district_id, str(district.get("name", district_id))))
		for exhibit_id: String in layout.exhibit_ids(district_id):
			rows.append(_row(exhibit_id, KIND_EXHIBIT, layout.exhibit(exhibit_id), district_id, str(district.get("name", district_id))))
	return rows


func _row(id: String, kind: String, record: Dictionary, district_id: String, district_name: String) -> Dictionary:
	var sign_block: Variant = record.get("sign", {})
	var sign_data: Dictionary = sign_block if sign_block is Dictionary else {}
	var title := str(sign_data.get("title", "")).strip_edges()
	var description := _description(sign_data)
	var entity_ids: Array[String] = _string_list(record.get("entities", []))
	var item_ids: Array[String] = _string_list(record.get("items", []))
	var icon_item := str(sign_data.get("item", ""))
	if icon_item.is_empty() and not item_ids.is_empty():
		icon_item = item_ids[0]
	if icon_item.is_empty() and not entity_ids.is_empty():
		icon_item = entity_ids[0]
	var category := ItemCategories.category_of(icon_item, _content_category(icon_item)) if not icon_item.is_empty() else ""
	var row := {
		"id": id,
		"kind": kind,
		"name": title if not title.is_empty() else _read_out(id),
		"district": district_id,
		"district_name": district_name,
		"description": description,
		"icon_item": icon_item,
		"category": category,
		"category_label": ItemCategories.label_of(category) if not category.is_empty() else "",
		"added_in": str(record.get("added_in", "")),
		"exhibit_kind": str(record.get("kind", "")) if kind == KIND_EXHIBIT else "",
		"entities": entity_ids,
		"items": item_ids,
		"status": notes.status_of(id) if notes != null else ExpoNotes.DEFAULT_STATUS,
		"remark": str(notes.latest_remark(id).get("remark", "")) if notes != null else "",
		"notes": notes.note_count(id) if notes != null else 0,
	}
	row["search"] = _search_text(row)
	return row


func _content_category(item_id: String) -> String:
	if registry == null or item_id.is_empty():
		return ""
	return registry.item_category(item_id)


func _display_name(item_id: String) -> String:
	if registry == null or item_id.is_empty():
		return ""
	return registry.display_name(item_id)


## Everything a search may match: the ids, the names, the district, the sign's
## words and the display names of the content the exhibit shows.
func _search_text(row: Dictionary) -> String:
	var parts: Array[String] = [str(row.get("id", "")), str(row.get("name", "")), str(row.get("district", "")),
		str(row.get("district_name", "")), str(row.get("description", "")), str(row.get("category_label", "")),
		str(row.get("added_in", ""))]
	for list_key: String in ["entities", "items"]:
		for value: Variant in row.get(list_key, []):
			var content_id := str(value)
			parts.append(content_id)
			parts.append(_display_name(content_id))
	var icon_item := str(row.get("icon_item", ""))
	if not icon_item.is_empty():
		parts.append(_display_name(icon_item))
	return " ".join(parts).to_lower()


static func _description(sign_data: Dictionary) -> String:
	var lines: Array[String] = []
	for value: Variant in sign_data.get("lines", []):
		var line := str(value).strip_edges()
		if not line.is_empty():
			lines.append(line)
	return "  ·  ".join(lines)


static func _string_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			result.append(str(entry))
	return result


## `cy_wall_kit` -> "Cy Wall Kit": only ever a fallback for a record with no
## sign of its own.
static func _read_out(id: String) -> String:
	return id.replace("_", " ").capitalize()


# --- Filters ------------------------------------------------------------------


## The newest `added_in` stamp on the campus ("" when nothing declares one).
## Stamps are compared as strings, which is why the field is documented as an
## ISO date or a zero-padded version.
static func newest_added_in(rows: Array[Dictionary]) -> String:
	var newest := ""
	for row: Dictionary in rows:
		var stamp := str(row.get("added_in", ""))
		if stamp > newest:
			newest = stamp
	return newest


## What's new: everything stamped newer than the last list the owner
## dismissed, and - when nothing is newer than that - the newest stamp itself,
## so the filter is never silently empty.
static func is_new(row: Dictionary, newest: String, last_seen: String) -> bool:
	var stamp := str(row.get("added_in", ""))
	if stamp.is_empty():
		return false
	if not last_seen.is_empty() and newest > last_seen:
		return stamp > last_seen
	return stamp == newest


## `filters`: {query, district, category, status, whats_new}. An empty string
## (or false) means "do not narrow on this".
static func filter(rows: Array[Dictionary], filters: Dictionary, newest: String = "", last_seen: String = "") -> Array[Dictionary]:
	var query := str(filters.get("query", "")).strip_edges().to_lower()
	var district := str(filters.get("district", ""))
	var category := str(filters.get("category", ""))
	var status := str(filters.get("status", ""))
	var whats_new := bool(filters.get("whats_new", false))
	var result: Array[Dictionary] = []
	for row: Dictionary in rows:
		if not query.is_empty() and not str(row.get("search", "")).contains(query):
			continue
		if not district.is_empty() and str(row.get("district", "")) != district:
			continue
		if not category.is_empty() and str(row.get("category", "")) != category:
			continue
		if not status.is_empty() and str(row.get("status", ExpoNotes.DEFAULT_STATUS)) != status:
			continue
		if whats_new and not is_new(row, newest, last_seen):
			continue
		result.append(row)
	return result
