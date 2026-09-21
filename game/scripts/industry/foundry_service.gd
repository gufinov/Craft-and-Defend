class_name FoundryService
extends RefCounted

## Industry wave 1 (docs/INDUSTRY.md): a Foundry standing against a Warehouse
## smelts on its own. Every FOUNDRY_SECONDS it takes one furnace recipe's
## inputs (ore + Coal, read from the registry) out of the warehouse and puts
## the ingot back in. The chosen ingot, the count made, the cycle timer and
## the status line live in the station record under "foundry", so the
## workstation snapshot saves and restores everything; this service holds no
## state of its own. Advanced from GameSession._process, paused with the
## simulation.

signal foundry_changed(instance_id: String, state: Dictionary)

const FOUNDRY_SECONDS := 10.0
const TARGET_ANY := "any"
const INGOT_SUFFIX := "_ingot"
const STATUS_NO_WAREHOUSE := "no warehouse"
const STATUS_WAREHOUSE_FULL := "warehouse full"
## Cells around the footprint, on its level: the warehouse must touch a side.
const SIDE_STEPS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var workstations: WorkstationService
var registry: ContentRegistry


func _init(service: WorkstationService, content_registry: ContentRegistry) -> void:
	workstations = service
	registry = content_registry


## The furnace recipes that make an ingot (output id ends in INGOT_SUFFIX:
## Hot Oil stays a hand-loaded Furnace job), in book order (iron before gold):
## "any" takes the first whose inputs the warehouse holds.
func recipes() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for recipe in registry.recipes_for("furnace"):
		var makes_ingot := false
		for output_id: Variant in recipe.get("outputs", {}).keys():
			makes_ingot = makes_ingot or str(output_id).ends_with(INGOT_SUFFIX)
		if makes_ingot:
			found.append(recipe)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order_a := int(a.get("recipe_book_order", 0))
		var order_b := int(b.get("recipe_book_order", 0))
		return order_a < order_b if order_a != order_b else str(a.id) < str(b.id))
	return found


## Target ids the modal offers: "any" then one per furnace recipe.
func targets() -> Array[String]:
	var ids: Array[String] = [TARGET_ANY]
	for recipe in recipes():
		ids.append(str(recipe.id))
	return ids


func is_foundry(instance_id: String) -> bool:
	return str(workstations.station(instance_id).get("entity_id", "")) == "foundry"


## The foundry's record state ({} for anything that is not a foundry).
func state(instance_id: String) -> Dictionary:
	if not is_foundry(instance_id):
		return {}
	return _ensure_state(instance_id).duplicate(true)


func set_target(instance_id: String, target: String) -> Dictionary:
	if not is_foundry(instance_id):
		return {"ok": false, "reason": "NOT_FOUNDRY"}
	if target not in targets():
		return {"ok": false, "reason": "UNKNOWN_TARGET"}
	var foundry_state := _ensure_state(instance_id)
	foundry_state["target"] = target
	foundry_state["elapsed"] = 0.0
	_refresh_status(instance_id, foundry_state)
	foundry_changed.emit(instance_id, foundry_state.duplicate(true))
	return {"ok": true, "reason": "TARGET_SET", "target": target}


## The warehouse touching the foundry's footprint (a side neighbour of any
## footprint cell, on the same level), or "".
func warehouse_for(instance_id: String) -> String:
	var record := workstations.station(instance_id)
	if record.is_empty():
		return ""
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var rotation := int(record.get("rotation_quarters", 0))
	var cells: Array[Vector3i] = []
	for offset in registry.entity(str(record.get("entity_id", ""))).get("occupied_offsets", []):
		if offset is Array and offset.size() == 3:
			cells.append(anchor + workstations.footprints.rotate_offset(Vector3i(int(offset[0]), int(offset[1]), int(offset[2])), rotation))
	for cell: Vector3i in cells:
		for step: Vector3i in SIDE_STEPS:
			var neighbour := cell + step
			if cells.has(neighbour):
				continue
			var owner := workstations.footprints.owner_at(neighbour)
			if not owner.is_empty() and str(workstations.station(owner).get("entity_id", "")) == "warehouse":
				return owner
	return ""


## True when the warehouse holds every input of `recipe`.
func inputs_present(warehouse_id: String, recipe: Dictionary) -> bool:
	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id: Variant in inputs.keys():
		if workstations.container_count(warehouse_id, str(item_id)) < int(inputs[item_id]):
			return false
	return true


## The recipe the foundry would run now: the target, or for "any" the first
## recipe (book order) whose inputs the warehouse holds. {} when none.
func recipe_for(instance_id: String, warehouse_id: String) -> Dictionary:
	var target := str(_ensure_state(instance_id).get("target", TARGET_ANY))
	for recipe in recipes():
		if target != TARGET_ANY and str(recipe.id) != target:
			continue
		if inputs_present(warehouse_id, recipe):
			return recipe
	return {}


## One simulation step. Returns one event per ingot batch smelted
## ({instance_id, warehouse_id, recipe_id, outputs}).
func advance(delta: float, paused: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if paused or delta <= 0.0 or workstations == null:
		return events
	for instance_id: String in workstations.stations.keys():
		if not is_foundry(instance_id):
			continue
		var foundry_state := _ensure_state(instance_id)
		var before := str(foundry_state.get("status", ""))
		var warehouse_id := warehouse_for(instance_id)
		var recipe := recipe_for(instance_id, warehouse_id) if not warehouse_id.is_empty() else {}
		var working := not recipe.is_empty() and _room_for_outputs(warehouse_id, recipe)
		if not working:
			foundry_state["elapsed"] = 0.0
		else:
			# One batch per step at most: a long absence does not empty the
			# warehouse in one frame (the time over FOUNDRY_SECONDS carries).
			foundry_state["elapsed"] = float(foundry_state.get("elapsed", 0.0)) + delta
			if float(foundry_state.elapsed) >= FOUNDRY_SECONDS:
				foundry_state["elapsed"] = minf(float(foundry_state.elapsed) - FOUNDRY_SECONDS, FOUNDRY_SECONDS)
				var smelted := _smelt(instance_id, warehouse_id, recipe)
				if not smelted.is_empty():
					foundry_state["made"] = int(foundry_state.get("made", 0)) + int(smelted.get("count", 0))
					events.append(smelted)
		_refresh_status(instance_id, foundry_state)
		if str(foundry_state.status) != before or not events.is_empty() and str(events[-1].instance_id) == instance_id:
			foundry_changed.emit(instance_id, foundry_state.duplicate(true))
	return events


func _ensure_state(instance_id: String) -> Dictionary:
	var record: Dictionary = workstations.stations.get(instance_id, {})
	var raw: Variant = record.get("foundry", null)
	if not raw is Dictionary:
		raw = {}
		record["foundry"] = raw
	var foundry_state: Dictionary = raw
	if str(foundry_state.get("target", "")) not in targets():
		foundry_state["target"] = TARGET_ANY
	foundry_state["made"] = maxi(0, int(foundry_state.get("made", 0)))
	foundry_state["elapsed"] = clampf(float(foundry_state.get("elapsed", 0.0)), 0.0, FOUNDRY_SECONDS)
	if not foundry_state.has("status"):
		foundry_state["status"] = STATUS_NO_WAREHOUSE
	return foundry_state


func _room_for_outputs(warehouse_id: String, recipe: Dictionary) -> bool:
	var outputs: Dictionary = recipe.get("outputs", {})
	for item_id: Variant in outputs.keys():
		if workstations.container_room(warehouse_id, str(item_id)) < int(outputs[item_id]):
			return false
	return true


## Takes the recipe's inputs out of the warehouse and puts its outputs in.
## {} when the warehouse changed under us (nothing is taken then).
func _smelt(instance_id: String, warehouse_id: String, recipe: Dictionary) -> Dictionary:
	if not inputs_present(warehouse_id, recipe) or not _room_for_outputs(warehouse_id, recipe):
		return {}
	var inputs: Dictionary = recipe.get("inputs", {})
	for item_id: Variant in inputs.keys():
		workstations.container_take(warehouse_id, str(item_id), int(inputs[item_id]))
	var outputs: Dictionary = recipe.get("outputs", {})
	var count := 0
	for item_id: Variant in outputs.keys():
		var put := workstations.container_put(warehouse_id, str(item_id), int(outputs[item_id]))
		count += int(put.get("details", {}).get("moved", 0))
	return {"instance_id": instance_id, "warehouse_id": warehouse_id, "recipe_id": str(recipe.id), "outputs": outputs.duplicate(true), "count": count}


## The status line: what the foundry is doing, for the modal and the glow.
func _refresh_status(instance_id: String, foundry_state: Dictionary) -> void:
	var warehouse_id := warehouse_for(instance_id)
	if warehouse_id.is_empty():
		foundry_state["status"] = STATUS_NO_WAREHOUSE
		foundry_state["working"] = false
		return
	var recipe := recipe_for(instance_id, warehouse_id)
	if recipe.is_empty():
		foundry_state["status"] = "waiting for " + _wanted_inputs_text(str(foundry_state.get("target", TARGET_ANY)))
		foundry_state["working"] = false
		return
	if not _room_for_outputs(warehouse_id, recipe):
		foundry_state["status"] = STATUS_WAREHOUSE_FULL
		foundry_state["working"] = false
		return
	var output_id := str(recipe.get("outputs", {}).keys()[0]) if not recipe.get("outputs", {}).is_empty() else str(recipe.id)
	var left := ceili(FOUNDRY_SECONDS - float(foundry_state.get("elapsed", 0.0)))
	foundry_state["status"] = "smelting %s · %d s" % [registry.display_name(output_id), maxi(1, left)]
	foundry_state["working"] = true


func _wanted_inputs_text(target: String) -> String:
	var names: Array[String] = []
	for recipe in recipes():
		if target != TARGET_ANY and str(recipe.id) != target:
			continue
		for item_id: Variant in recipe.get("inputs", {}).keys():
			var display := registry.display_name(str(item_id))
			if display not in names:
				names.append(display)
	return " + ".join(names) if not names.is_empty() else "ore and Coal"
