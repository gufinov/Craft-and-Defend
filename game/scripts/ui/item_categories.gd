class_name ItemCategories
extends RefCounted

## Expo item categories (docs/DEVELOPMENT_EXPO_HANDOFF.md section 8).
##
## One shared classification for every icon-first catalog that groups items:
## the Sign editor's item picker today, the Supply Depot generator next. The
## map is explicit per item id so the order and grouping stay deterministic
## between runs; an id with no entry falls back to its content `category`
## field, and anything that field cannot place lands in `unassigned` so the
## next feature author classifies it instead of the item disappearing.
##
## The Supply Depot card (Expo card G) owns the depot mapping and may extend
## CATEGORIES / ITEM_CATEGORY here; keep existing ids and their order.

const UNASSIGNED := "unassigned"

## Display order of the catalog strip. `id` is stable and saved nowhere; it is
## a UI grouping, never part of a sign record (signs store item ids only).
const CATEGORIES: Array[Dictionary] = [
	{"id": "natural_resources", "label": "Natural Resources"},
	{"id": "ores_and_fuel", "label": "Ores & Fuel"},
	{"id": "processed_materials", "label": "Processed Materials"},
	{"id": "ammunition", "label": "Ammunition"},
	{"id": "tools_and_weapons", "label": "Tools & Weapons"},
	{"id": "construction", "label": "Construction"},
	{"id": "workstations_and_industry", "label": "Workstations & Industry"},
	{"id": "siege_and_defense", "label": "Siege & Defense"},
	{"id": "rail_and_coaster", "label": "Rail & Coaster"},
	{"id": "lighting_and_utility", "label": "Lighting & Utility"},
	{"id": "special_core", "label": "Special / Core"},
	{"id": "future_food", "label": "Future Food"},
	{"id": "future_armor", "label": "Future Armor"},
	{"id": UNASSIGNED, "label": "Unassigned"},
]

const ITEM_CATEGORY := {
	"dirt": "natural_resources",
	"stone": "natural_resources",
	"log": "natural_resources",
	"stick": "natural_resources",
	"coal": "ores_and_fuel",
	"iron_ore": "ores_and_fuel",
	"gold_ore": "ores_and_fuel",
	"planks": "processed_materials",
	"castle_stone": "processed_materials",
	"iron_ingot": "processed_materials",
	"gold_ingot": "processed_materials",
	"ballista_bolt": "ammunition",
	"stone_shot": "ammunition",
	"flame_shot": "ammunition",
	"cannonball": "ammunition",
	"hot_oil": "ammunition",
	"wood_pick": "tools_and_weapons",
	"stone_pick": "tools_and_weapons",
	"iron_pick": "tools_and_weapons",
	"wood_axe": "tools_and_weapons",
	"iron_sword": "tools_and_weapons",
	"stone_stair": "construction",
	"wall_walk_slab": "construction",
	"parapet_merlon": "construction",
	"tower_platform": "construction",
	"gate_frame": "construction",
	"wood_barricade": "construction",
	"sign": "construction",
	"workbench": "workstations_and_industry",
	"furnace": "workstations_and_industry",
	"chest": "workstations_and_industry",
	"miner": "workstations_and_industry",
	"ore_bin": "workstations_and_industry",
	"warehouse": "workstations_and_industry",
	"foundry": "workstations_and_industry",
	"coastercraft_shop": "workstations_and_industry",
	"ballista": "siege_and_defense",
	"catapult": "siege_and_defense",
	"turret_catapult": "siege_and_defense",
	"turret_catapult_mk2": "siege_and_defense",
	"cannon": "siege_and_defense",
	"kettle": "siege_and_defense",
	"rail": "rail_and_coaster",
	"rail_slope": "rail_and_coaster",
	"rail_loop": "rail_and_coaster",
	"rail_switch": "rail_and_coaster",
	"rail_cross": "rail_and_coaster",
	"rail_curve": "rail_and_coaster",
	"rail_climb": "rail_and_coaster",
	"mine_cart": "rail_and_coaster",
	"coaster_car": "rail_and_coaster",
	"torch": "lighting_and_utility",
	"wall_lantern": "lighting_and_utility",
	"post_lantern": "lighting_and_utility",
	"campfire": "lighting_and_utility",
	"light_block_blue": "lighting_and_utility",
	"light_block_red": "lighting_and_utility",
	"core_of_power": "special_core",
	"enemy_core": "special_core",
}

## Fallback for an item the map does not name yet: its content `category`.
const CONTENT_CATEGORY_FALLBACK := {
	"resource": "natural_resources",
	"building": "construction",
	"tool": "tools_and_weapons",
	"station": "workstations_and_industry",
	"food": "future_food",
}


static func category_of(item_id: String, content_category: String = "") -> String:
	if ITEM_CATEGORY.has(item_id):
		return str(ITEM_CATEGORY[item_id])
	if CONTENT_CATEGORY_FALLBACK.has(content_category):
		return str(CONTENT_CATEGORY_FALLBACK[content_category])
	return UNASSIGNED


static func label_of(category_id: String) -> String:
	for category: Dictionary in CATEGORIES:
		if str(category.id) == category_id:
			return str(category.label)
	return "Unassigned"


## Every visible item id grouped by category, in CATEGORIES order and, inside
## a category, in registry order. `registry` is a ContentRegistry; hidden items
## (the enemy core) stay out unless `include_hidden`.
static func grouped(registry: ContentRegistry, include_hidden: bool = false) -> Dictionary:
	var groups: Dictionary = {}
	for category: Dictionary in CATEGORIES:
		var empty: Array[String] = []
		groups[str(category.id)] = empty
	for item_id: String in registry.items.keys():
		var item: Dictionary = registry.items[item_id]
		if bool(item.get("hidden", false)) and not include_hidden:
			continue
		var group: Array[String] = groups.get(category_of(item_id, str(item.get("category", ""))), groups[UNASSIGNED])
		group.append(item_id)
	return groups
