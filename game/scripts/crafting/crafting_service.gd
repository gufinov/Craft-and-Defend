class_name CraftingService
extends RefCounted

var registry: ContentRegistry
var inventory: F0Inventory


func _init(content_registry: ContentRegistry, player_inventory: F0Inventory) -> void:
	registry = content_registry
	inventory = player_inventory


func check_recipe(recipe_id: String, station: String, batches: int = 1) -> Dictionary:
	if batches < 1:
		return {"ok": false, "reason": "INVALID_BATCH_COUNT"}
	var recipe := registry.recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": "UNKNOWN_RECIPE"}
	if str(recipe.get("station", "")) != station:
		return {"ok": false, "reason": "WRONG_WORKSTATION"}
	if float(recipe.get("duration_seconds", 0.0)) > 0.0:
		return {"ok": false, "reason": "TIMED_RECIPE"}
	var inputs := _scaled_counts(recipe.get("inputs", {}), batches)
	var outputs := _scaled_counts(recipe.get("outputs", {}), batches)
	var transaction := inventory._simulate(inputs, outputs)
	if not transaction.get("ok", false):
		return {"ok": false, "reason": transaction.get("reason", "CRAFT_FAILED"), "item_id": transaction.get("item_id", "")}
	return {"ok": true, "reason": "READY", "recipe": recipe, "batches": batches, "inputs": inputs, "outputs": outputs}


func try_craft(recipe_id: String, station: String) -> Dictionary:
	return try_craft_many(recipe_id, station, 1)


func try_craft_many(recipe_id: String, station: String, batches: int) -> Dictionary:
	var checked := check_recipe(recipe_id, station, batches)
	if not checked.get("ok", false):
		return checked
	var committed := inventory.try_transaction(checked.inputs, checked.outputs)
	if not committed.get("ok", false):
		return committed
	return {"ok": true, "reason": "OK", "recipe_id": recipe_id, "batches": batches, "outputs": checked.outputs.duplicate(true), "inventory_revision": inventory.revision}


func _scaled_counts(counts: Dictionary, batches: int) -> Dictionary:
	var scaled: Dictionary = {}
	for item_id: String in counts:
		scaled[item_id] = int(counts[item_id]) * batches
	return scaled
