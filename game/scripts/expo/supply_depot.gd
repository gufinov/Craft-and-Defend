class_name SupplyDepot
extends RefCounted

## Development Expo Supply Depot generator (docs/DEVELOPMENT_EXPO.md, handoff
## sections 8 and 9). Pure data in, pure data out: it reads the content
## registry and returns the catalog of chests the builder then places, so the
## same build always produces the same chests holding the same items in the
## same order. `tools/validate_foundation.py` holds the Python oracle of these
## same rules (`supply_catalog`) - change one and you must change the other.
##
## The rules, verbatim from the commission:
##   * every non-hidden player-visible item of the registry appears, eight
##     units of it, exactly once in the whole catalog;
##   * a chest carries at most eight distinct item types;
##   * a chest carries one category only, because its sign's header is that
##     category's label and its grid lists the chest's own ids;
##   * a chest fills at most eight of its nine slots, so the ninth stays
##     visibly empty. An item that does not stack (a pick, a Core) therefore
##     needs eight slots and fills a chest by itself - which is why the rule is
##     "at most eight types", not "always eight";
##   * ordering is category order, then registry order inside a category, so
##     contents never shuffle between runs;
##   * a hidden id (`enemy_core`) is out unless the manifest whitelists it as a
##     development asset;
##   * a category the game has no items for yet (Future Food, Future Armour)
##     gets reserved signage and no chest. No fake items, ever.

## Units of every item type the depot stocks.
const DEFAULT_UNITS := 8
## Distinct item types one chest may carry.
const DEFAULT_TYPES_PER_CHEST := 8
## Slots of the chest's nine the depot may fill; the ninth stays empty.
const DEFAULT_SLOTS_PER_CHEST := 8
## Categories that exist as signage only until the game has items for them.
const RESERVED_CATEGORIES: Array[String] = ["future_food", "future_armor"]

## Depot geometry inside its parcel. Each stand is a chest with a two-cell
## stone plinth behind it carrying the sign, so the board stands above the
## chest (handoff section 9) and the aisle in front of the chest stays clear.
##   plinth z = parcel back edge - (row + 1) * ROW_PITCH, chest one cell nearer
##   the visitor, the remaining two cells of the pitch are the aisle.
## Row 0 is the row nearest the entrance, so the first category is the first
## one a visitor reads.
const COLUMN_STRIDE := 4
const ROW_PITCH := 4
## Cells kept clear at the parcel's -x edge (the exhibit's own sign stands there).
const EDGE_INSET := 1
## Cells of the plinth under the sign.
const PLINTH_HEIGHT := 2


## The catalog the builder places and the diagnostics assert.
##
## `config` accepts the manifest's `supply` block: `units_per_item`,
## `types_per_chest`, `slots_per_chest` and `hidden_whitelist`.
##
## Returns `{ok, units, items, chests, reserved, unassigned}` where `chests` is
## `[{category, label, part, parts, items, slots}]` in placement order and
## `unassigned` names every visible item with no Expo category. `ok` is false
## when anything is unassigned: the depot never invents a bucket for it.
static func catalog(registry: ContentRegistry, config: Dictionary = {}) -> Dictionary:
	var units: int = maxi(1, int(config.get("units_per_item", DEFAULT_UNITS)))
	var types_per_chest: int = maxi(1, int(config.get("types_per_chest", DEFAULT_TYPES_PER_CHEST)))
	var slots_per_chest: int = maxi(1, int(config.get("slots_per_chest", DEFAULT_SLOTS_PER_CHEST)))
	var whitelist: Array[String] = []
	var raw_whitelist: Variant = config.get("hidden_whitelist", [])
	if raw_whitelist is Array:
		for value: Variant in raw_whitelist as Array:
			whitelist.append(str(value))
	var visible := visible_items(registry, whitelist)
	var by_category: Dictionary = {}
	var unassigned: Array[String] = []
	for item_id: String in visible:
		var category := ItemCategories.classify(item_id)
		if category == ItemCategories.UNASSIGNED:
			unassigned.append(item_id)
			continue
		if not by_category.has(category):
			var bucket: Array[String] = []
			by_category[category] = bucket
		var members: Array[String] = by_category[category]
		members.append(item_id)
	var chests: Array[Dictionary] = []
	var reserved: Array[Dictionary] = []
	var stocked: Array[String] = []
	for category: String in ItemCategories.category_ids():
		if category == ItemCategories.UNASSIGNED:
			continue
		var members: Array[String] = []
		if by_category.has(category):
			members = by_category[category]
		if members.is_empty():
			if category in RESERVED_CATEGORIES:
				reserved.append({"category": category, "label": ItemCategories.label_of(category)})
			continue
		var groups := chunk(registry, members, units, types_per_chest, slots_per_chest)
		for index in range(groups.size()):
			var group: Dictionary = groups[index]
			var members_in_chest: Array[String] = group["items"]
			chests.append({
				"category": category,
				"label": ItemCategories.label_of(category),
				"part": index + 1,
				"parts": groups.size(),
				"items": members_in_chest,
				"slots": int(group["slots"]),
			})
			stocked.append_array(members_in_chest)
	return {
		"ok": unassigned.is_empty(),
		"units": units,
		"items": stocked,
		"chests": chests,
		"reserved": reserved,
		"unassigned": unassigned,
	}


## Every item the depot must stock, in registry order: not hidden, or hidden
## and named by the manifest's development-asset whitelist.
static func visible_items(registry: ContentRegistry, whitelist: Array[String] = []) -> Array[String]:
	var result: Array[String] = []
	for item_id: String in registry.items.keys():
		var item: Dictionary = registry.items[item_id]
		if bool(item.get("hidden", false)) and item_id not in whitelist:
			continue
		result.append(item_id)
	return result


## Slots `units` of one item type occupies in a chest: one per stack, rounded
## up, so eight picks (which do not stack) need eight slots.
static func slots_for(registry: ContentRegistry, item_id: String, units: int) -> int:
	var stack: int = maxi(1, registry.max_stack(item_id))
	return int(ceil(float(units) / float(stack)))


## Next-fit chunking of one category's items, in registry order: a chest takes
## items until the next one would exceed the type or slot budget, then a new
## chest starts. Returns `[{items, slots}]`.
static func chunk(registry: ContentRegistry, members: Array[String], units: int, types_per_chest: int, slots_per_chest: int) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var current: Array[String] = []
	var used := 0
	for item_id: String in members:
		var slots: int = mini(slots_for(registry, item_id, units), slots_per_chest)
		if not current.is_empty() and (current.size() >= types_per_chest or used + slots > slots_per_chest):
			groups.append({"items": current, "slots": used})
			current = []
			used = 0
		current.append(item_id)
		used += slots
	if not current.is_empty():
		groups.append({"items": current, "slots": used})
	return groups


## Chest stands that fit along one row of a parcel of `size`.
static func columns_per_row(size: Vector3i) -> int:
	# A chest is two cells wide, so its second cell must still be in the parcel.
	var span := size.x - EDGE_INSET - 2
	return 0 if span < 0 else span / COLUMN_STRIDE + 1


static func rows_in(size: Vector3i) -> int:
	return maxi(0, size.z / ROW_PITCH)


## How many chests plus reserved sign posts the parcel can hold.
static func stand_capacity(size: Vector3i) -> int:
	return columns_per_row(size) * rows_in(size)


## The cells of stand `index`: its chest anchor and the base of the stone
## plinth behind it whose top carries the sign.
static func stand_at(origin: Vector3i, size: Vector3i, index: int) -> Dictionary:
	var per_row := columns_per_row(size)
	if per_row <= 0 or index < 0:
		return {}
	var row := index / per_row
	var column := index % per_row
	var plinth_z := origin.z + size.z - (row + 1) * ROW_PITCH
	var x := origin.x + EDGE_INSET + column * COLUMN_STRIDE
	return {
		"row": row,
		"column": column,
		"plinth": Vector3i(x, origin.y, plinth_z),
		"chest": Vector3i(x, origin.y, plinth_z + 1),
	}


## The sign block of one supply chest: Header + Item Grid, the category label
## over the exact ids in that chest (handoff section 9).
static func chest_sign(chest: Dictionary) -> Dictionary:
	var label := str(chest.get("label", ""))
	var title: String = label if int(chest.get("parts", 1)) <= 1 else "%s  %d/%d" % [label, int(chest.get("part", 1)), int(chest.get("parts", 1))]
	var items: Array[String] = []
	if chest.has("items"):
		items = chest["items"]
	# The wide board (signs card 2): a chest is two cells across, and so is the
	# board over it, so the 4 x 2 grid of icons and names reads from the aisle.
	return {"title": title, "items": items, "board": "wide"}


## The sign block of a category the game has no items for yet.
static func reserved_sign(reserved: Dictionary, units: int) -> Dictionary:
	return {"title": str(reserved.get("label", "")).to_upper() + " — RESERVED",
		"lines": ["No such item exists yet.", "This stand stays empty until one does.",
			"A new item joins the depot with %d units of its own." % units],
		"board": "wide"}
