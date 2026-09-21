class_name FoundryService
extends RefCounted

## Industry wave 1 (docs/INDUSTRY.md): a Foundry smelts on its own from its
## three slots (ore, fuel, output - `foundry_slots` in the station record,
## 64 each like a Furnace). Every advance it first PULLS from the storage
## network beside it (StorageNetwork: the warehouse it touches, the chests
## beside that warehouse, daisy-chained warehouses): Coal into the fuel slot
## and the target's ore into the ore slot, each up to a full stack - whatever
## does not fit stays in storage. Then it smelts one ingot per job (the
## furnace recipe's duration, FOUNDRY_JOB_SECONDS when the recipe has none)
## consuming 1 ore + 1 Coal into the output slot, and PUSHES the output slot
## into the network whenever there is room. The chosen ingot, the count made,
## the job timer and the status line live in the record under "foundry", so
## the workstation snapshot saves and restores everything; this service holds
## no state of its own. Advanced from GameSession._process, paused with the
## simulation. It also feeds Furnaces from their network (pull only).

signal foundry_changed(instance_id: String, state: Dictionary)

## Job length when the furnace recipe carries no duration_seconds.
const FOUNDRY_JOB_SECONDS := 6.0
const SLOT_MAX := 64
const TARGET_ANY := "any"
const INGOT_SUFFIX := "_ingot"
const STATUS_NO_STORAGE := "no storage"
const STATUS_NO_FUEL := "no fuel"
const STATUS_NO_ORE := "no ore"
const STATUS_OUTPUT_FULL := "output full"
## Kept for callers of the first foundry (T194): the lone-foundry status.
const STATUS_NO_WAREHOUSE := STATUS_NO_STORAGE

var workstations: WorkstationService
var registry: ContentRegistry
var network: StorageNetwork


func _init(service: WorkstationService, content_registry: ContentRegistry) -> void:
	workstations = service
	registry = content_registry
	network = StorageNetwork.new(service)


## The furnace recipes that make an ingot (output id ends in INGOT_SUFFIX:
## Hot Oil stays a hand-loaded Furnace job), in book order (iron before gold):
## "any" takes the first whose ore the storage holds.
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


## The three slots as {ore, fuel, output} stacks ({} for a non-foundry).
func slots(instance_id: String) -> Dictionary:
	if not is_foundry(instance_id):
		return {}
	var record: Dictionary = workstations.stations.get(instance_id, {})
	var raw: Variant = record.get("foundry_slots", null)
	if not raw is Dictionary:
		raw = WorkstationService._empty_foundry_slots()
		record["foundry_slots"] = raw
	var live: Dictionary = raw
	for slot_name in ["ore", "fuel", "output"]:
		if not live.get(slot_name, null) is Dictionary:
			live[slot_name] = WorkstationService._empty_stack()
	return live


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


## The storage network beside the foundry (containers touching its footprint
## and everything they chain to), nearest first.
func network_for(instance_id: String) -> Array[String]:
	return network.network_of(instance_id)


## The first container beside the foundry, or "" (the first foundry's API).
func warehouse_for(instance_id: String) -> String:
	var found := network_for(instance_id)
	return found[0] if not found.is_empty() else ""


## Seconds one ingot of `recipe` takes: the recipe's duration, else the default.
func job_seconds(recipe: Dictionary) -> float:
	var duration := float(recipe.get("duration_seconds", 0.0))
	return duration if duration > 0.0 else FOUNDRY_JOB_SECONDS


## The recipe the foundry would run now: the one whose ore sits in the ore
## slot (the slot decides once it holds a kind), else the target's recipe, or
## for "any" the first recipe (book order) whose ore the storage holds. {}
## when none.
func recipe_for(instance_id: String, storage: Array[String]) -> Dictionary:
	var target := str(_ensure_state(instance_id).get("target", TARGET_ANY))
	var ore_stack: Dictionary = slots(instance_id).get("ore", {})
	var held_ore := str(ore_stack.get("item_id", "")) if int(ore_stack.get("count", 0)) > 0 else ""
	for recipe in recipes():
		if target != TARGET_ANY and str(recipe.id) != target:
			continue
		var ore_id := _ore_of(recipe)
		if not held_ore.is_empty():
			if ore_id == held_ore:
				return recipe
			continue
		if network.count(storage, ore_id) > 0:
			return recipe
	if target != TARGET_ANY:
		# A fixed target is the recipe even with nothing to feed it (status
		# "no ore"); "any" with nothing to go on has no recipe.
		return registry.recipe(target)
	return {}


## The job progress for the panel: {active, progress, remaining_seconds,
## duration_seconds, recipe_id}.
func job_status(instance_id: String) -> Dictionary:
	var foundry_state := _ensure_state(instance_id)
	var recipe := registry.recipe(str(foundry_state.get("recipe_id", "")))
	var working: bool = bool(foundry_state.get("working", false))
	if recipe.is_empty() or not working:
		return {"active": false, "progress": 0.0, "remaining_seconds": 0.0, "duration_seconds": 0.0, "recipe_id": ""}
	var duration := job_seconds(recipe)
	var elapsed := clampf(float(foundry_state.get("elapsed", 0.0)), 0.0, duration)
	return {"active": true, "progress": clampf(elapsed / duration, 0.0, 1.0), "remaining_seconds": duration - elapsed, "duration_seconds": duration, "recipe_id": str(recipe.id)}


## One simulation step. Returns one event per ingot smelted
## ({instance_id, warehouse_id, recipe_id, outputs, count}).
func advance(delta: float, paused: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if paused or delta <= 0.0 or workstations == null:
		return events
	for instance_id: String in workstations.stations.keys():
		var entity_id := str(workstations.stations[instance_id].get("entity_id", ""))
		if entity_id == "furnace":
			_feed_furnace(instance_id)
			continue
		if entity_id != "foundry":
			continue
		var foundry_state := _ensure_state(instance_id)
		var before := str(foundry_state.get("status", ""))
		var storage := network_for(instance_id)
		_pull(instance_id, storage)
		_push(instance_id, storage)
		var recipe := recipe_for(instance_id, storage)
		var can_run := not recipe.is_empty() and _inputs_staged(instance_id, recipe) and _output_has_room(instance_id, recipe)
		var made_now := false
		if not can_run:
			foundry_state["elapsed"] = 0.0
			foundry_state["recipe_id"] = ""
		else:
			# One ingot per step at most: a long absence does not empty the slots
			# in one frame (the time over the job length carries, capped).
			var duration := job_seconds(recipe)
			if str(foundry_state.get("recipe_id", "")) != str(recipe.id):
				foundry_state["elapsed"] = 0.0
				foundry_state["recipe_id"] = str(recipe.id)
			foundry_state["elapsed"] = float(foundry_state.get("elapsed", 0.0)) + delta
			if float(foundry_state.elapsed) >= duration:
				foundry_state["elapsed"] = minf(float(foundry_state.elapsed) - duration, duration)
				var smelted := _smelt(instance_id, recipe)
				if not smelted.is_empty():
					foundry_state["made"] = int(foundry_state.get("made", 0)) + int(smelted.get("count", 0))
					smelted["warehouse_id"] = storage[0] if not storage.is_empty() else ""
					events.append(smelted)
					made_now = true
					_push(instance_id, storage)
		_refresh_status(instance_id, foundry_state)
		if str(foundry_state.status) != before or made_now:
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
	foundry_state["elapsed"] = maxf(0.0, float(foundry_state.get("elapsed", 0.0)))
	foundry_state["recipe_id"] = str(foundry_state.get("recipe_id", ""))
	if not foundry_state.has("status"):
		foundry_state["status"] = STATUS_NO_STORAGE
	slots(instance_id)
	return foundry_state


## The non-fuel input of a furnace recipe (its ore).
func _ore_of(recipe: Dictionary) -> String:
	var fuel_id := _fuel_item()
	for item_id: Variant in recipe.get("inputs", {}).keys():
		if str(item_id) != fuel_id:
			return str(item_id)
	return ""


func _fuel_item() -> String:
	return registry.balance_string("furnace.fuel_item", "coal")


## Tops up a slot from the network: only when it is empty or already holds
## `item_id`, up to SLOT_MAX. Returns the amount moved.
func _top_up(storage: Array[String], slot: Dictionary, item_id: String) -> int:
	if item_id.is_empty() or storage.is_empty():
		return 0
	var held_id := str(slot.get("item_id", ""))
	var held := int(slot.get("count", 0))
	if held > 0 and held_id != item_id:
		return 0
	var limit := mini(SLOT_MAX, registry.max_stack(item_id))
	var wanted := limit - (held if held > 0 else 0)
	if wanted <= 0:
		return 0
	var available := network.count(storage, item_id)
	if available <= 0:
		return 0
	var moved := network.take(storage, item_id, mini(wanted, available))
	if moved > 0:
		slot["item_id"] = item_id
		slot["count"] = (held if held > 0 else 0) + moved
	return moved


## Fuel and ore from the storage into the foundry's slots.
func _pull(instance_id: String, storage: Array[String]) -> void:
	if storage.is_empty():
		return
	var live := slots(instance_id)
	var fuel_stack: Dictionary = live["fuel"]
	_top_up(storage, fuel_stack, _fuel_item())
	var ore_stack: Dictionary = live["ore"]
	var ore_id := str(ore_stack.get("item_id", "")) if int(ore_stack.get("count", 0)) > 0 else ""
	if ore_id.is_empty():
		var target := str(_ensure_state(instance_id).get("target", TARGET_ANY))
		var candidates: Array[String] = []
		for recipe in recipes():
			if target == TARGET_ANY or str(recipe.id) == target:
				candidates.append(_ore_of(recipe))
		ore_id = network.first_present(storage, candidates)
	_top_up(storage, ore_stack, ore_id)


## The output slot into the storage, whatever fits.
func _push(instance_id: String, storage: Array[String]) -> void:
	if storage.is_empty():
		return
	var live := slots(instance_id)
	var output: Dictionary = live["output"]
	var item_id := str(output.get("item_id", ""))
	var held := int(output.get("count", 0))
	if item_id.is_empty() or held <= 0:
		return
	var remaining := network.put(storage, item_id, held)
	if remaining < held:
		if remaining > 0:
			output["count"] = remaining
		else:
			output["item_id"] = ""
			output["count"] = 0
		workstations.station_changed.emit({"ok": true, "reason": "FOUNDRY_PUSHED", "details": {"instance_id": instance_id, "item_id": item_id, "moved": held - remaining}})


func _inputs_staged(instance_id: String, recipe: Dictionary) -> bool:
	var live := slots(instance_id)
	var fuel: Dictionary = live["fuel"]
	var ore: Dictionary = live["ore"]
	if str(fuel.get("item_id", "")) != _fuel_item() or int(fuel.get("count", 0)) < int(recipe.get("inputs", {}).get(_fuel_item(), 1)):
		return false
	var ore_id := _ore_of(recipe)
	return str(ore.get("item_id", "")) == ore_id and int(ore.get("count", 0)) >= int(recipe.get("inputs", {}).get(ore_id, 1))


func _output_has_room(instance_id: String, recipe: Dictionary) -> bool:
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.is_empty():
		return false
	var item_id := str(outputs.keys()[0])
	var live := slots(instance_id)
	var output: Dictionary = live["output"]
	var held_id := str(output.get("item_id", ""))
	var held := int(output.get("count", 0))
	if held > 0 and held_id != item_id:
		return false
	return (held if held > 0 else 0) + int(outputs[item_id]) <= mini(SLOT_MAX, registry.max_stack(item_id))


## Takes the recipe's inputs out of the slots and puts its output in the
## output slot. {} when the slots changed under us (nothing is taken then).
func _smelt(instance_id: String, recipe: Dictionary) -> Dictionary:
	if not _inputs_staged(instance_id, recipe) or not _output_has_room(instance_id, recipe):
		return {}
	var live := slots(instance_id)
	var inputs: Dictionary = recipe.get("inputs", {})
	var fuel_id := _fuel_item()
	for item_id: Variant in inputs.keys():
		var slot: Dictionary = live["fuel"] if str(item_id) == fuel_id else live["ore"]
		slot["count"] = int(slot.get("count", 0)) - int(inputs[item_id])
		if int(slot.count) <= 0:
			slot["item_id"] = ""
			slot["count"] = 0
	var outputs: Dictionary = recipe.get("outputs", {})
	var output_id := str(outputs.keys()[0])
	var count := int(outputs[output_id])
	var output: Dictionary = live["output"]
	output["item_id"] = output_id
	output["count"] = int(output.get("count", 0)) + count
	workstations.station_changed.emit({"ok": true, "reason": "FOUNDRY_SMELTED", "details": {"instance_id": instance_id, "item_id": output_id, "count": count}})
	return {"instance_id": instance_id, "recipe_id": str(recipe.id), "outputs": outputs.duplicate(true), "count": count}


## The status line: what the foundry is doing, for the modal and the glow.
func _refresh_status(instance_id: String, foundry_state: Dictionary) -> void:
	var storage := network_for(instance_id)
	var live := slots(instance_id)
	var fuel_stack: Dictionary = live["fuel"]
	var ore_stack: Dictionary = live["ore"]
	var recipe := recipe_for(instance_id, storage)
	foundry_state["working"] = false
	if recipe.is_empty():
		foundry_state["status"] = STATUS_NO_STORAGE if storage.is_empty() and _slots_empty(live) else STATUS_NO_ORE
		return
	if int(fuel_stack.get("count", 0)) <= 0:
		foundry_state["status"] = STATUS_NO_STORAGE if storage.is_empty() and _slots_empty(live) else STATUS_NO_FUEL
		return
	if int(ore_stack.get("count", 0)) <= 0 or str(ore_stack.get("item_id", "")) != _ore_of(recipe):
		foundry_state["status"] = STATUS_NO_ORE
		return
	if not _output_has_room(instance_id, recipe):
		foundry_state["status"] = STATUS_OUTPUT_FULL
		return
	var output_id := str(recipe.get("outputs", {}).keys()[0]) if not recipe.get("outputs", {}).is_empty() else str(recipe.id)
	var left := ceili(job_seconds(recipe) - float(foundry_state.get("elapsed", 0.0)))
	foundry_state["status"] = "smelting %s · %d s" % [registry.display_name(output_id), maxi(1, left)]
	foundry_state["working"] = true


func _slots_empty(live: Dictionary) -> bool:
	for stack: Dictionary in live.values():
		if int(stack.get("count", 0)) > 0:
			return false
	return true


## A Furnace beside storage pulls fuel and ore into its slots the way the
## foundry does (only into an empty slot or one holding the same item); its
## output stays in the Furnace (the owner did not ask for a push here). The
## ore is the first furnace-recipe input the storage holds, book order.
func _feed_furnace(instance_id: String) -> void:
	var storage := network.network_of(instance_id)
	if storage.is_empty():
		return
	var live := workstations.furnace_slots(instance_id)
	var fuel_stack: Dictionary = live["fuel"]
	var moved := 0
	moved += _top_up(storage, fuel_stack, _fuel_item())
	var input_stack: Dictionary = live["input"]
	var ore_id := str(input_stack.get("item_id", "")) if int(input_stack.get("count", 0)) > 0 else ""
	if ore_id.is_empty():
		var candidates: Array[String] = []
		for recipe in registry.recipes_for("furnace"):
			var candidate := _ore_of(recipe)
			if not candidate.is_empty() and candidate not in candidates:
				candidates.append(candidate)
		ore_id = network.first_present(storage, candidates)
	moved += _top_up(storage, input_stack, ore_id)
	if moved > 0:
		workstations._write_furnace_slots(instance_id, live)
		workstations.station_changed.emit({"ok": true, "reason": "FURNACE_FED", "details": {"instance_id": instance_id, "furnace_slots": workstations.furnace_slots(instance_id)}})
