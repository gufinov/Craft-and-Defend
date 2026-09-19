class_name ItemIconCatalog
extends RefCounted

## Resolves item art from the generated UI atlases.
##
## Regions come from `data/item_atlas_regions.json`, produced by
## `tools/measure_item_atlas.py` from each atlas's alpha channel. A region is the
## tight bounds of one object, so card icons centre on the art itself and the
## held view can hinge tools at the handle end. Re-run the tool after replacing
## an atlas; the nominal grid below only remains as a fallback.

const ATLAS_PATH := "res://assets/ui/item_atlas_p3h2.png"
const WORLD_REFERENCE_PATH := ATLAS_PATH
const AMMUNITION_ATLAS_PATH := "res://assets/ui/ammunition_atlas_p3h3.png"
## P4b gold placeholders derived from the iron art (tools/make_gold_atlas_p4.py).
const GOLD_ATLAS_PATH := "res://assets/ui/gold_atlas_p4.png"
const REGIONS_PATH := "res://data/item_atlas_regions.json"
const CELL_SIZE := Vector2(256, 256)
const SAFE_THIRD_ROW_HEIGHT := 224.0
const SAFE_BOTTOM_ROW_START := 736.0
const SAFE_BOTTOM_ROW_HEIGHT := 288.0
## Card icons are padded to a square this much larger than the object's longest
## side so every item reads at a consistent size inside its slot.
const CARD_FRAME_SCALE := 1.12
const ITEM_CELLS := {
	"dirt": 0,
	"stone": 1,
	"log": 2,
	"planks": 3,
	"castle_stone": 4,
	"stick": 5,
	"coal": 6,
	"iron_ore": 7,
	"iron_ingot": 8,
	"wood_pick": 9,
	"stone_pick": 10,
	"iron_pick": 11,
	"workbench": 12,
	"furnace": 13,
	"stone_stair": 14,
	"wall_walk_slab": 15,
	"parapet_merlon": 16,
	"tower_platform": 17,
	"gate_frame": 18,
	"wood_barricade": 19,
	"iron_sword": 20,
	"wood_axe": 21,
	"ballista": 22,
	"catapult": 23,
}
const AMMUNITION_REGIONS := {
	"ballista_bolt": Rect2(0.0, 0.0, 887.0, 887.0),
	"stone_shot": Rect2(887.0, 0.0, 887.0, 887.0),
}
## Nominal fallback cells for the gold atlas: two centred 256x256 cells.
const GOLD_REGIONS := {
	"gold_ore": Rect2(0.0, 0.0, 256.0, 256.0),
	"gold_ingot": Rect2(256.0, 0.0, 256.0, 256.0),
}
const ATLAS_PATHS := {
	"item": ATLAS_PATH,
	"ammunition": AMMUNITION_ATLAS_PATH,
	"gold": GOLD_ATLAS_PATH,
}

static var _atlases: Dictionary = {}
static var _textures: Dictionary = {}
static var _world_reference_textures: Dictionary = {}
static var _measured_regions: Dictionary = {}
static var _regions_loaded := false


static func has_item(item_id: String) -> bool:
	return not item_id.is_empty() and (ITEM_CELLS.has(item_id) or AMMUNITION_REGIONS.has(item_id) or GOLD_REGIONS.has(item_id))


## Card/slot texture: the measured object padded to a centred square.
static func texture_for(item_id: String) -> Texture2D:
	if not has_item(item_id):
		return null
	if _textures.has(item_id):
		return _textures[item_id]
	var texture := _atlas_texture(item_id)
	if texture == null:
		return null
	var region := texture.region
	var side := maxf(region.size.x, region.size.y) * CARD_FRAME_SCALE
	var pad := (Vector2(side, side) - region.size) * 0.5
	texture.margin = Rect2(pad, pad * 2.0)
	_textures[item_id] = texture
	return texture


static func recipe_texture(recipe: Dictionary) -> Texture2D:
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.is_empty():
		return null
	return texture_for(str(outputs.keys()[0]))


## First-person reference texture: the tight measured object with no padding,
## so the sprite's bounds are the art's bounds.
static func world_reference_texture_for(item_id: String) -> Texture2D:
	if not has_item(item_id):
		return null
	if _world_reference_textures.has(item_id):
		return _world_reference_textures[item_id]
	var texture := _atlas_texture(item_id)
	if texture == null:
		return null
	_world_reference_textures[item_id] = texture
	return texture


## Measured tight region for an item in atlas pixels, or the nominal grid cell
## when the measurement file lacks it.
static func region_for(item_id: String) -> Rect2:
	_ensure_regions()
	if _measured_regions.has(item_id):
		return _measured_regions[item_id].rect
	if AMMUNITION_REGIONS.has(item_id):
		return AMMUNITION_REGIONS[item_id]
	if GOLD_REGIONS.has(item_id):
		return GOLD_REGIONS[item_id]
	if ITEM_CELLS.has(item_id):
		return region_for_index(int(ITEM_CELLS[item_id]))
	return Rect2()


static func is_measured(item_id: String) -> bool:
	_ensure_regions()
	return _measured_regions.has(item_id)


static func atlas_key_for(item_id: String) -> String:
	_ensure_regions()
	if _measured_regions.has(item_id):
		return str(_measured_regions[item_id].atlas)
	if AMMUNITION_REGIONS.has(item_id):
		return "ammunition"
	return "gold" if GOLD_REGIONS.has(item_id) else "item"


## Nominal grid cell. Retained for diagnostics and as the fallback layout.
static func region_for_index(index: int) -> Rect2:
	var column := index % 6
	var row := index / 6
	if row == 2:
		return Rect2(Vector2(column * CELL_SIZE.x, CELL_SIZE.y * 2.0), Vector2(CELL_SIZE.x, SAFE_THIRD_ROW_HEIGHT))
	if row == 3:
		return Rect2(Vector2(column * CELL_SIZE.x, SAFE_BOTTOM_ROW_START), Vector2(CELL_SIZE.x, SAFE_BOTTOM_ROW_HEIGHT))
	return Rect2(Vector2(column * CELL_SIZE.x, row * CELL_SIZE.y), CELL_SIZE)


static func missing_item_ids(item_ids: Array) -> Array[String]:
	var missing: Array[String] = []
	for value in item_ids:
		var item_id := str(value)
		if texture_for(item_id) == null:
			missing.append(item_id)
	return missing


static func missing_world_reference_item_ids(item_ids: Array) -> Array[String]:
	var missing: Array[String] = []
	for value in item_ids:
		var item_id := str(value)
		if world_reference_texture_for(item_id) == null:
			missing.append(item_id)
	return missing


static func _atlas_texture(item_id: String) -> AtlasTexture:
	var atlas := _atlas(atlas_key_for(item_id))
	if atlas == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region_for(item_id)
	texture.filter_clip = true
	return texture


static func _atlas(key: String) -> Texture2D:
	if _atlases.has(key):
		return _atlases[key]
	var atlas := load(str(ATLAS_PATHS.get(key, ATLAS_PATH))) as Texture2D
	_atlases[key] = atlas
	return atlas


static func _ensure_regions() -> void:
	if _regions_loaded:
		return
	_regions_loaded = true
	if not FileAccess.file_exists(REGIONS_PATH):
		push_warning("ItemIconCatalog: %s missing; falling back to nominal grid cells." % REGIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGIONS_PATH))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		push_warning("ItemIconCatalog: %s unreadable; falling back to nominal grid cells." % REGIONS_PATH)
		return
	var regions: Dictionary = parsed.get("regions", {})
	for item_id in regions.keys():
		var entry: Dictionary = regions[item_id]
		var rect: Array = entry.get("rect", [])
		if rect.size() != 4:
			continue
		_measured_regions[str(item_id)] = {
			"atlas": str(entry.get("atlas", "item")),
			"rect": Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])),
		}
