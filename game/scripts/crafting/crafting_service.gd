class_name CraftingService
extends RefCounted

var registry: ContentRegistry
var inventory: F0Inventory


func _init(content_registry: ContentRegistry, player_inventory: F0Inventory) -> void:
	registry = content_registry
	inventory = player_inventory


func check_recipe(recipe_id: String, station: String) -> Dictionary:
	var recipe := registry.recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": "UNKNOWN_RECIPE"}
	if str(recipe.get("station", "")) != station:
		return {"ok": false, "reason": "WRONG_WORKSTATION"}
	if float(recipe.get("duration_seconds", 0.0)) > 0.0:
		return {"ok": false, "reason": "TIMED_RECIPE"}
	var transaction := inventory._simulate(recipe.get("inputs", {}), recipe.get("outputs", {}))
	if not transaction.get("ok", false):
		return {"ok": false, "reason": transaction.get("reason", "CRAFT_FAILED"), "item_id": transaction.get("item_id", "")}
	return {"ok": true, "reason": "READY", "recipe": recipe}


func try_craft(recipe_id: String, station: String) -> Dictionary:
	var checked := check_recipe(recipe_id, station)
	if not checked.get("ok", false):
		return checked
	var recipe: Dictionary = checked.recipe
	var committed := inventory.try_transaction(recipe.get("inputs", {}), recipe.get("outputs", {}))
	if not committed.get("ok", false):
		return committed
	return {"ok": true, "reason": "OK", "recipe_id": recipe_id, "outputs": recipe.outputs.duplicate(true), "inventory_revision": inventory.revision}

