class_name ExpoLayout
extends RefCounted

## Development Expo layout engine (docs/DEVELOPMENT_EXPO.md, handoff sections
## 6, 11 and 12). Reads the manifest (`data/development_expo.json`, mirror of
## `contracts/development_expo.json`) and turns it into parcels, avenues,
## expansion corridors and the canonical world bounds. Pure data in, pure data
## out: the same manifest always yields the same layout, so the Expo builder,
## the diagnostics and the Python validator agree cell for cell.
##
## Nothing here touches the world. `ExpoBuilder` applies the layout.

const MANIFEST_PATH := "res://data/development_expo.json"

var manifest: Dictionary = {}
var load_error := ""
## District id -> record, in manifest order.
var _districts: Dictionary = {}
var _district_order: PackedStringArray = PackedStringArray()
## Exhibit id -> record.
var _exhibits: Dictionary = {}
var _exhibit_order: PackedStringArray = PackedStringArray()
## Exhibit id -> {"origin": Vector3i, "size": Vector3i, "orientation": String,
## "district": String, "nested": bool}.
var _parcels: Dictionary = {}
## District id -> the avenue rectangles that join it to the plaza.
var _avenues: Dictionary = {}
var _world_min := Vector3i.ZERO
var _world_size := Vector3i.ZERO


## Reads the manifest from disk. Returns {} and sets `load_error` on failure.
static func read_manifest(path: String = MANIFEST_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


## Loads and solves the layout. `source` empty reads MANIFEST_PATH.
func load_layout(source: Dictionary = {}) -> Dictionary:
	manifest = source if not source.is_empty() else read_manifest()
	load_error = ""
	_districts.clear()
	_district_order = PackedStringArray()
	_exhibits.clear()
	_exhibit_order = PackedStringArray()
	_parcels.clear()
	_avenues.clear()
	if manifest.is_empty():
		load_error = "EXPO_MANIFEST_MISSING"
		return {"ok": false, "reason": load_error}
	if int(manifest.get("schema_version", 0)) != 1:
		load_error = "EXPO_MANIFEST_SCHEMA"
		return {"ok": false, "reason": load_error}
	var districts: Variant = manifest.get("districts", [])
	if not districts is Array or (districts as Array).is_empty():
		load_error = "EXPO_MANIFEST_EMPTY"
		return {"ok": false, "reason": load_error}
	for entry: Variant in districts as Array:
		if not entry is Dictionary:
			load_error = "EXPO_DISTRICT_INVALID"
			return {"ok": false, "reason": load_error}
		var district: Dictionary = entry
		var district_id := str(district.get("id", ""))
		if district_id.is_empty() or _districts.has(district_id):
			load_error = "EXPO_DISTRICT_ID"
			return {"ok": false, "reason": load_error}
		_districts[district_id] = district
		_district_order.append(district_id)
		var packed := _pack_district(district)
		if not packed.get("ok", false):
			load_error = str(packed.get("reason", "EXPO_PACK_FAILED"))
			return packed
	_solve_avenues()
	_solve_world_bounds()
	return {"ok": true}


func ground_y() -> int:
	return int(manifest.get("ground_y", -1))


func local_path_width() -> int:
	return maxi(1, int(manifest.get("local_path_width", 3)))


func avenue_width() -> int:
	return maxi(3, int(manifest.get("avenue_width", 7)))


func clear_height() -> int:
	return maxi(4, int(manifest.get("clear_height", 12)))


func fill_bottom() -> int:
	return int(manifest.get("fill_bottom", -8))


func spawn_feet() -> Vector3:
	var value: Variant = manifest.get("spawn_feet", [])
	if value is Array and (value as Array).size() == 3:
		var raw: Array = value
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return WorldAdapter.SPAWN_FEET


func district_ids() -> PackedStringArray:
	return _district_order.duplicate()


func district(district_id: String) -> Dictionary:
	var record: Variant = _districts.get(district_id, {})
	return record if record is Dictionary else {}


## {origin: Vector3i, size: Vector3i} of the district volume, empty when unknown.
func district_bounds(district_id: String) -> Dictionary:
	var record := district(district_id)
	if record.is_empty():
		return {}
	return {"origin": _cell(record.get("origin", [])), "size": _cell(record.get("size", []))}


func district_corridor(district_id: String) -> Dictionary:
	var record := district(district_id)
	if record.is_empty():
		return {}
	var corridor: Variant = record.get("expansion_corridor", {})
	if not corridor is Dictionary:
		return {}
	var box: Dictionary = corridor
	return {"origin": _cell(box.get("origin", [])), "size": _cell(box.get("size", []))}


## The avenue rectangles (ground-level paths) joining a district to the plaza.
func district_avenue(district_id: String) -> Array[Dictionary]:
	var stored: Variant = _avenues.get(district_id, [])
	var result: Array[Dictionary] = []
	if stored is Array:
		for entry: Variant in stored as Array:
			if entry is Dictionary:
				result.append(entry)
	return result


func exhibit_ids(district_id: String = "") -> PackedStringArray:
	if district_id.is_empty():
		return _exhibit_order.duplicate()
	var result := PackedStringArray()
	for exhibit_id: String in _exhibit_order:
		if str(_parcels.get(exhibit_id, {}).get("district", "")) == district_id:
			result.append(exhibit_id)
	return result


func exhibit(exhibit_id: String) -> Dictionary:
	var record: Variant = _exhibits.get(exhibit_id, {})
	return record if record is Dictionary else {}


## {origin: Vector3i, size: Vector3i, orientation: String, district: String,
## nested: bool}; empty when the id is unknown.
func parcel_for(exhibit_id: String) -> Dictionary:
	var record: Variant = _parcels.get(exhibit_id, {})
	return (record as Dictionary).duplicate() if record is Dictionary else {}


## Every parcel that must stay empty (the signed future-expansion areas).
func reserved_parcels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for exhibit_id: String in _exhibit_order:
		if str(exhibit(exhibit_id).get("kind", "")) == "reserved":
			var parcel := parcel_for(exhibit_id)
			parcel["id"] = exhibit_id
			result.append(parcel)
	return result


## The canonical world bounds: every district, corridor and avenue plus the
## expansion margin, rounded outward to whole chunks. The floor stays at the
## manifest's `floor_y` so the generator keeps its bedrock layer.
func world_bounds() -> Dictionary:
	return {"min": _world_min, "size": _world_size}


## The sign request for a district or exhibit ({} when it carries none).
func sign_data(owner_id: String) -> Dictionary:
	var record := exhibit(owner_id)
	if record.is_empty():
		record = district(owner_id)
	var sign: Variant = record.get("sign", {})
	return sign if sign is Dictionary else {}


## Non-fatal layout findings (overlaps, districts without a corridor, a missing
## reserved parcel). Empty on a healthy manifest; T213 asserts that.
func report() -> Dictionary:
	var overlaps: Array[String] = []
	var boxes: Array[Dictionary] = []
	for district_id: String in _district_order:
		var bounds := district_bounds(district_id)
		bounds["label"] = district_id
		boxes.append(bounds)
		var corridor := district_corridor(district_id)
		corridor["label"] = district_id + " corridor"
		boxes.append(corridor)
	for first in range(boxes.size()):
		for second in range(first + 1, boxes.size()):
			if _overlaps(boxes[first], boxes[second]):
				overlaps.append("%s / %s" % [boxes[first]["label"], boxes[second]["label"]])
	var parcels: Array[Dictionary] = []
	for exhibit_id: String in _exhibit_order:
		var parcel := parcel_for(exhibit_id)
		if bool(parcel.get("nested", false)):
			continue
		parcel["label"] = exhibit_id
		parcels.append(parcel)
	for first in range(parcels.size()):
		for second in range(first + 1, parcels.size()):
			if _overlaps(parcels[first], parcels[second]):
				overlaps.append("%s / %s" % [parcels[first]["label"], parcels[second]["label"]])
	var without_corridor: Array[String] = []
	var outside: Array[String] = []
	for district_id: String in _district_order:
		var corridor := district_corridor(district_id)
		if corridor.is_empty() or not _touches(district_bounds(district_id), corridor):
			without_corridor.append(district_id)
		if not _contains(world_bounds(), district_bounds(district_id)):
			outside.append(district_id)
	for exhibit_id: String in _exhibit_order:
		if not _contains(world_bounds(), parcel_for(exhibit_id)):
			outside.append(exhibit_id)
	return {
		"overlaps": overlaps,
		"without_corridor": without_corridor,
		"outside_world_bounds": outside,
		"reserved_parcels": reserved_parcels().size(),
		"districts": _district_order.size(),
		"exhibits": _exhibit_order.size(),
	}


## A stable fingerprint of the solved layout: two loads of the same manifest
## must produce the same string (T213's determinism check).
func fingerprint() -> String:
	var parts := PackedStringArray()
	parts.append("%s %s" % [_world_min, _world_size])
	for exhibit_id: String in _exhibit_order:
		var parcel := parcel_for(exhibit_id)
		parts.append("%s %s %s %s" % [exhibit_id, parcel.get("origin", Vector3i.ZERO), parcel.get("size", Vector3i.ZERO), parcel.get("orientation", "")])
	for district_id: String in _district_order:
		var avenue := district_avenue(district_id)
		for rectangle: Dictionary in avenue:
			parts.append("%s %s %s" % [district_id, rectangle.get("origin", Vector3i.ZERO), rectangle.get("size", Vector3i.ZERO)])
	return "\n".join(parts)


## Shelf packing inside one district, in manifest order (see the Python oracle
## `expo_parcels` in tools/validate_foundation.py - the two must agree):
## an exhibit with an explicit `offset` is anchored there, the rest fill rows
## along +x inside the district's usable rectangle, each with its clearance
## around it, wrapping to a new row past the deepest cell of the previous one.
func _pack_district(record: Dictionary) -> Dictionary:
	var district_id := str(record.get("id", ""))
	var origin := _cell(record.get("origin", []))
	var size := _cell(record.get("size", []))
	var path := local_path_width()
	var usable_origin := Vector2i(origin.x + path, origin.z + path)
	var usable_size := Vector2i(size.x - 2 * path, size.z - 2 * path)
	var cursor := usable_origin
	var row_depth := 0
	var exhibits: Variant = record.get("exhibits", [])
	if not exhibits is Array:
		return {"ok": false, "reason": "EXPO_EXHIBITS_INVALID"}
	for entry: Variant in exhibits as Array:
		if not entry is Dictionary:
			return {"ok": false, "reason": "EXPO_EXHIBIT_INVALID"}
		var exhibit_record: Dictionary = entry
		var exhibit_id := str(exhibit_record.get("id", ""))
		if exhibit_id.is_empty() or _exhibits.has(exhibit_id):
			return {"ok": false, "reason": "EXPO_EXHIBIT_ID"}
		_exhibits[exhibit_id] = exhibit_record
		_exhibit_order.append(exhibit_id)
		var footprint := _cell(exhibit_record.get("footprint", []))
		var clearance := int(exhibit_record.get("clearance", 0))
		var orientation := str(exhibit_record.get("orientation", "north"))
		var nested := bool(exhibit_record.get("nested", false))
		if exhibit_record.has("offset"):
			var offset := _cell(exhibit_record.get("offset", []))
			_parcels[exhibit_id] = {"origin": origin + offset, "size": footprint, "orientation": orientation, "district": district_id, "nested": nested}
			continue
		var cell_size := Vector2i(footprint.x + 2 * clearance, footprint.z + 2 * clearance)
		if cursor.x + cell_size.x > usable_origin.x + usable_size.x:
			cursor = Vector2i(usable_origin.x, cursor.y + row_depth + path)
			row_depth = 0
		if cursor.y + cell_size.y > usable_origin.y + usable_size.y:
			return {"ok": false, "reason": "EXPO_DISTRICT_FULL", "district": district_id, "exhibit": exhibit_id}
		_parcels[exhibit_id] = {"origin": Vector3i(cursor.x + clearance, origin.y + 1, cursor.y + clearance), "size": footprint, "orientation": orientation, "district": district_id, "nested": nested}
		cursor.x += cell_size.x + path
		row_depth = maxi(row_depth, cell_size.y)
	return {"ok": true}


## One L-shaped avenue per district: a run along x from the plaza's entrance,
## then a run along z to the district's entrance, both `avenue_width` wide at
## ground level. The plaza itself gets none.
func _solve_avenues() -> void:
	if _district_order.is_empty():
		return
	var plaza_id := _district_order[0]
	var plaza := district_bounds(plaza_id)
	if plaza.is_empty():
		return
	var plaza_origin: Vector3i = plaza["origin"]
	var plaza_size: Vector3i = plaza["size"]
	var hub := Vector3i(plaza_origin.x + plaza_size.x / 2, plaza_origin.y, plaza_origin.z + plaza_size.z / 2)
	var width := avenue_width()
	var half := width / 2
	for district_id: String in _district_order:
		if district_id == plaza_id:
			continue
		var entrance := _cell(district(district_id).get("entrance", []))
		var rectangles: Array[Dictionary] = []
		var x_from := mini(hub.x, entrance.x)
		var x_to := maxi(hub.x, entrance.x)
		if x_to > x_from:
			rectangles.append({"origin": Vector3i(x_from, ground_y(), hub.z - half), "size": Vector3i(x_to - x_from + 1, 1, width)})
		var z_from := mini(hub.z, entrance.z)
		var z_to := maxi(hub.z, entrance.z)
		if z_to > z_from:
			rectangles.append({"origin": Vector3i(entrance.x - half, ground_y(), z_from), "size": Vector3i(width, 1, z_to - z_from + 1)})
		_avenues[district_id] = rectangles


func _solve_world_bounds() -> void:
	var chunk := maxi(1, int(manifest.get("chunk_size", 16)))
	var margin := maxi(0, int(manifest.get("expansion_margin", 0)))
	var vertical := maxi(0, int(manifest.get("vertical_margin", 0)))
	var low := Vector3i.MAX
	var high := Vector3i.MIN
	var boxes: Array[Dictionary] = []
	for district_id: String in _district_order:
		boxes.append(district_bounds(district_id))
		boxes.append(district_corridor(district_id))
		for rectangle: Dictionary in district_avenue(district_id):
			boxes.append(rectangle)
	for box: Dictionary in boxes:
		if box.is_empty():
			continue
		var origin: Vector3i = box["origin"]
		var size: Vector3i = box["size"]
		low = Vector3i(mini(low.x, origin.x), mini(low.y, origin.y), mini(low.z, origin.z))
		high = Vector3i(maxi(high.x, origin.x + size.x), maxi(high.y, origin.y + size.y), maxi(high.z, origin.z + size.z))
	var floor_y := int(manifest.get("floor_y", -16))
	var minimum := Vector3i(_floor_to(low.x - margin, chunk), _floor_to(mini(floor_y, low.y), chunk), _floor_to(low.z - margin, chunk))
	var maximum := Vector3i(_ceil_to(high.x + margin, chunk), _ceil_to(high.y + vertical, chunk), _ceil_to(high.z + margin, chunk))
	_world_min = minimum
	_world_size = maximum - minimum


static func _floor_to(value: int, chunk: int) -> int:
	return chunk * int(floor(float(value) / float(chunk)))


static func _ceil_to(value: int, chunk: int) -> int:
	return chunk * int(ceil(float(value) / float(chunk)))


static func _cell(value: Variant) -> Vector3i:
	if value is Array and (value as Array).size() == 3:
		var raw: Array = value
		return Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	return Vector3i.ZERO


static func _overlaps(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	var first_origin: Vector3i = first.get("origin", Vector3i.ZERO)
	var first_size: Vector3i = first.get("size", Vector3i.ZERO)
	var second_origin: Vector3i = second.get("origin", Vector3i.ZERO)
	var second_size: Vector3i = second.get("size", Vector3i.ZERO)
	return first_origin.x < second_origin.x + second_size.x and second_origin.x < first_origin.x + first_size.x \
		and first_origin.y < second_origin.y + second_size.y and second_origin.y < first_origin.y + first_size.y \
		and first_origin.z < second_origin.z + second_size.z and second_origin.z < first_origin.z + first_size.z


static func _touches(box: Dictionary, other: Dictionary) -> bool:
	if box.is_empty() or other.is_empty():
		return false
	var origin: Vector3i = box.get("origin", Vector3i.ZERO)
	var size: Vector3i = box.get("size", Vector3i.ZERO)
	var other_origin: Vector3i = other.get("origin", Vector3i.ZERO)
	var other_size: Vector3i = other.get("size", Vector3i.ZERO)
	var flush_x: bool = other_origin.x + other_size.x == origin.x or origin.x + size.x == other_origin.x
	var flush_z: bool = other_origin.z + other_size.z == origin.z or origin.z + size.z == other_origin.z
	var span_x: bool = other_origin.x < origin.x + size.x and origin.x < other_origin.x + other_size.x
	var span_z: bool = other_origin.z < origin.z + size.z and origin.z < other_origin.z + other_size.z
	return (flush_x and span_z) or (flush_z and span_x)


static func _contains(outer: Dictionary, inner: Dictionary) -> bool:
	if outer.is_empty() or inner.is_empty():
		return false
	var outer_origin: Vector3i = outer.get("min", outer.get("origin", Vector3i.ZERO))
	var outer_size: Vector3i = outer.get("size", Vector3i.ZERO)
	var inner_origin: Vector3i = inner.get("origin", Vector3i.ZERO)
	var inner_size: Vector3i = inner.get("size", Vector3i.ZERO)
	return inner_origin.x >= outer_origin.x and inner_origin.y >= outer_origin.y and inner_origin.z >= outer_origin.z \
		and inner_origin.x + inner_size.x <= outer_origin.x + outer_size.x \
		and inner_origin.y + inner_size.y <= outer_origin.y + outer_size.y \
		and inner_origin.z + inner_size.z <= outer_origin.z + outer_size.z
