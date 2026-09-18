class_name ContentRegistry
extends RefCounted

const REGISTRY_PATH := "res://data/content.json"
const ITEM_CATEGORIES: Array[String] = ["resource", "building", "tool", "station", "food"]

var content_version := ""
var inventory_slots := 0
var hotbar_slots := 0
var balance: Dictionary = {}
var blocks_by_voxel: Dictionary = {}
var blocks_by_id: Dictionary = {}
var items: Dictionary = {}
var entities: Dictionary = {}
var recipes: Dictionary = {}
var load_error := ""


func _init(path: String = REGISTRY_PATH) -> void:
	var result := load_registry(path)
	if not result.get("ok", false):
		load_error = str(result.get("reason", "REGISTRY_LOAD_FAILED"))


func load_registry(path: String = REGISTRY_PATH) -> Dictionary:
	blocks_by_voxel.clear()
	blocks_by_id.clear()
	items.clear()
	entities.clear()
	recipes.clear()
	balance.clear()
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "REGISTRY_MISSING", "path": path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "reason": "REGISTRY_INVALID_JSON", "path": path}
	var document: Dictionary = parsed
	if int(document.get("schema_version", -1)) != 1:
		return {"ok": false, "reason": "REGISTRY_SCHEMA_UNSUPPORTED"}
	content_version = str(document.get("content_version", ""))
	var inventory: Dictionary = document.get("inventory", {})
	var balance_value: Variant = document.get("balance", {})
	if not balance_value is Dictionary:
		return {"ok": false, "reason": "REGISTRY_BALANCE_INVALID"}
	balance = balance_value.duplicate(true)
	inventory_slots = int(inventory.get("slots", 0))
	hotbar_slots = int(inventory.get("hotbar_slots", 0))
	if content_version.is_empty() or inventory_slots < 1 or hotbar_slots < 1 or hotbar_slots > inventory_slots:
		return {"ok": false, "reason": "REGISTRY_HEADER_INVALID"}
	for value in document.get("blocks", []):
		if not value is Dictionary:
			return {"ok": false, "reason": "REGISTRY_BLOCK_INVALID"}
		var block: Dictionary = value.duplicate(true)
		blocks_by_voxel[int(block.voxel_id)] = block
		blocks_by_id[str(block.id)] = block
	for value in document.get("items", []):
		if not value is Dictionary:
			return {"ok": false, "reason": "REGISTRY_ITEM_INVALID"}
		var item: Dictionary = value.duplicate(true)
		if str(item.get("category", "")) not in ITEM_CATEGORIES:
			return {"ok": false, "reason": "REGISTRY_ITEM_CATEGORY_INVALID", "item_id": str(item.get("id", ""))}
		items[str(item.id)] = item
	for value in document.get("entities", []):
		if not value is Dictionary:
			return {"ok": false, "reason": "REGISTRY_ENTITY_INVALID"}
		var entity: Dictionary = value.duplicate(true)
		entities[str(entity.id)] = entity
	for value in document.get("recipes", []):
		if not value is Dictionary:
			return {"ok": false, "reason": "REGISTRY_RECIPE_INVALID"}
		var recipe: Dictionary = value.duplicate(true)
		recipes[str(recipe.id)] = recipe
	if not blocks_by_voxel.has(0) or items.is_empty() or recipes.is_empty():
		return {"ok": false, "reason": "REGISTRY_CONTENT_INCOMPLETE"}
	load_error = ""
	return {"ok": true, "content_version": content_version}


func block_for_voxel(voxel_id: int) -> Dictionary:
	return blocks_by_voxel.get(voxel_id, {}).duplicate(true)


func item(item_id: String) -> Dictionary:
	return items.get(item_id, {}).duplicate(true)


func entity(entity_id: String) -> Dictionary:
	return entities.get(entity_id, {}).duplicate(true)


func recipe(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {}).duplicate(true)


func recipes_for(station: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for recipe_id: String in recipes:
		var definition: Dictionary = recipes[recipe_id]
		if str(definition.get("station", "")) == station:
			matches.append(definition.duplicate(true))
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return matches


func max_stack(item_id: String) -> int:
	return int(items.get(item_id, {}).get("max_stack", 0))


func item_category(item_id: String) -> String:
	return str(items.get(item_id, {}).get("category", ""))


func display_name(stable_id: String) -> String:
	return stable_id.replace("_", " ").capitalize()


func balance_value(path: String, fallback: Variant = null) -> Variant:
	var current: Variant = balance
	for segment in path.split(".", false):
		if not current is Dictionary or not current.has(segment):
			return fallback
		current = current[segment]
	return current


func balance_number(path: String, fallback: float) -> float:
	var value: Variant = balance_value(path, fallback)
	return float(value) if value is int or value is float else fallback


func balance_integer(path: String, fallback: int) -> int:
	var value: Variant = balance_value(path, fallback)
	return int(value) if value is int or value is float else fallback


func balance_string(path: String, fallback: String) -> String:
	var value: Variant = balance_value(path, fallback)
	return str(value) if value is String else fallback
