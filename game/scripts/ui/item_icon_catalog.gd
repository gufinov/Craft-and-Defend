class_name ItemIconCatalog
extends RefCounted

const ATLAS_PATH := "res://assets/ui/item_icon_atlas_p3d.png"
const WORLD_REFERENCE_PATH := "res://assets/ui/world_item_reference_p3e.png"
const CELL_SIZE := Vector2(256, 256)
const WORLD_REFERENCE_CELL_SIZE := Vector2(543, 724)
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
	texture.atlas = _atlas
	texture.region = Rect2(Vector2(index % 6, index / 6) * CELL_SIZE, CELL_SIZE)
	_textures[item_id] = texture
	return texture


static func recipe_texture(recipe: Dictionary) -> Texture2D:
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.is_empty():
		return null
	return texture_for(str(outputs.keys()[0]))


static func world_reference_texture_for(item_id: String) -> Texture2D:
	var cells := {"workbench": 0, "furnace": 1, "stone_pick": 2, "wood_axe": 3}
	if not cells.has(item_id):
		return null
	if _world_reference_textures.has(item_id):
		return _world_reference_textures[item_id]
	if _world_reference == null:
		_world_reference = load(WORLD_REFERENCE_PATH) as Texture2D
	if _world_reference == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = _world_reference
	texture.region = Rect2(Vector2(int(cells[item_id]), 0) * WORLD_REFERENCE_CELL_SIZE, WORLD_REFERENCE_CELL_SIZE)
	_world_reference_textures[item_id] = texture
	return texture


static func missing_item_ids(item_ids: Array) -> Array[String]:
	var missing: Array[String] = []
	for value in item_ids:
		var item_id := str(value)
		if texture_for(item_id) == null:
			missing.append(item_id)
	return missing
