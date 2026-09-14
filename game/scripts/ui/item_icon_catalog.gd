class_name ItemIconCatalog
extends RefCounted

const ATLAS_PATH := "res://assets/ui/item_icon_atlas_p3h1.png"
const WORLD_REFERENCE_PATH := "res://assets/ui/held_item_atlas_p3h1.png"
const CELL_SIZE := Vector2(256, 256)
const SAFE_THIRD_ROW_HEIGHT := 224.0
const SAFE_BOTTOM_ROW_START := 736.0
const SAFE_BOTTOM_ROW_HEIGHT := 288.0
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
	"ballista_bolt": 5,
	"stone_shot": 1,
}

static var _atlas: Texture2D
static var _textures: Dictionary = {}
static var _world_reference: Texture2D
static var _world_reference_textures: Dictionary = {}


static func texture_for(item_id: String) -> Texture2D:
	if item_id.is_empty() or not ITEM_CELLS.has(item_id):
		return null
	if _textures.has(item_id):
		return _textures[item_id]
	if _atlas == null:
		_atlas = load(ATLAS_PATH) as Texture2D
	if _atlas == null:
		return null
	var index := int(ITEM_CELLS[item_id])
	var texture := AtlasTexture.new()
	# The final six silhouettes are deliberately allowed a taller source window so
	# long weapons and gate towers remain complete. Their transparent atlas keeps
	# that recovery band from importing a neighboring card background.
	if index >= 18:
		if _world_reference == null:
			_world_reference = load(WORLD_REFERENCE_PATH) as Texture2D
		if _world_reference == null:
			return null
		texture.atlas = _world_reference
	else:
		texture.atlas = _atlas
	texture.region = region_for_index(index)
	texture.filter_clip = true
	_textures[item_id] = texture
	return texture


static func recipe_texture(recipe: Dictionary) -> Texture2D:
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.is_empty():
		return null
	return texture_for(str(outputs.keys()[0]))


static func world_reference_texture_for(item_id: String) -> Texture2D:
	if item_id.is_empty() or not ITEM_CELLS.has(item_id):
		return null
	if _world_reference_textures.has(item_id):
		return _world_reference_textures[item_id]
	if _world_reference == null:
		_world_reference = load(WORLD_REFERENCE_PATH) as Texture2D
	if _world_reference == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = _world_reference
	var index := int(ITEM_CELLS[item_id])
	texture.region = region_for_index(index)
	texture.filter_clip = true
	_world_reference_textures[item_id] = texture
	return texture


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
