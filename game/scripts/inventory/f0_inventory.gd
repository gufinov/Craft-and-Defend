class_name F0Inventory
extends RefCounted
## Foundation inventory. The historical class name remains so F0/F1 diagnostics
## continue to exercise the same runtime object after the F2 expansion.

signal changed(snapshot: Dictionary)

const SLOT_COUNT := 27
const HOTBAR_COUNT := 9
const MAX_DIRT := SLOT_COUNT * 64

var registry: ContentRegistry
var slots: Array[Dictionary] = []
var selected_hotbar := 0
var revision := 0
var reservations: Dictionary = {}
var dirt: int:
	get:
		return count("dirt")


func _init(content_registry: ContentRegistry = null) -> void:
	registry = content_registry if content_registry != null else ContentRegistry.new()
	for _index in range(SLOT_COUNT):
		slots.append(_empty_slot())


func count(item_id: String) -> int:
	return count_in(slots, item_id)


func active_item_id() -> String:
	if selected_hotbar < 0 or selected_hotbar >= HOTBAR_COUNT:
		return ""
	return str(slots[selected_hotbar].get("item_id", ""))


func active_pick_tier() -> int:
	return int(registry.item(active_item_id()).get("pick_tier", 0))


func select_hotbar(index: int) -> Dictionary:
	if index < 0 or index >= HOTBAR_COUNT:
		return {"ok": false, "reason": "INVALID_HOTBAR_SLOT"}
	selected_hotbar = index
	changed.emit(snapshot())
	return {"ok": true, "reason": "OK", "slot": index, "item_id": active_item_id()}


func swap_slots(first: int, second: int) -> Dictionary:
	if first < 0 or second < 0 or first >= SLOT_COUNT or second >= SLOT_COUNT:
		return {"ok": false, "reason": "INVALID_SLOT"}
	if first == second:
		return {"ok": true, "reason": "UNCHANGED"}
	var held := slots[first]
	slots[first] = slots[second]
	slots[second] = held
	revision += 1
	changed.emit(snapshot())
	return {"ok": true, "reason": "OK", "revision": revision}


func can_transaction(removals: Dictionary, additions: Dictionary) -> bool:
	return _simulate(removals, additions).get("ok", false)


func try_transaction(removals: Dictionary, additions: Dictionary) -> Dictionary:
	var simulated := _simulate(removals, additions)
	if not simulated.get("ok", false):
		return simulated
	slots = simulated.slots
	revision += 1
	changed.emit(snapshot())
	return {"ok": true, "reason": "OK", "revision": revision}


func try_reserve_and_remove(token: String, removals: Dictionary, outputs: Dictionary) -> Dictionary:
	if token.is_empty() or reservations.has(token):
		return {"ok": false, "reason": "DUPLICATE_RESERVATION"}
	var candidate := _remove_from_copy(slots.duplicate(true), removals)
	if not candidate.get("ok", false):
		return candidate
	var capacity_probe: Array[Dictionary] = candidate.slots.duplicate(true)
	for reserved: Dictionary in reservations.values():
		if not _add_to_slots(capacity_probe, reserved).get("ok", false):
			return {"ok": false, "reason": "INVENTORY_FULL"}
	if not _add_to_slots(capacity_probe, outputs).get("ok", false):
		return {"ok": false, "reason": "INVENTORY_FULL"}
	slots = candidate.slots
	reservations[token] = _normalized_counts(outputs)
	revision += 1
	changed.emit(snapshot())
	return {"ok": true, "reason": "OK", "reservation": token, "revision": revision}


func commit_reservation(token: String) -> Dictionary:
	if not reservations.has(token):
		return {"ok": false, "reason": "NO_RESERVATION"}
	var outputs: Dictionary = reservations[token]
	var candidate: Array[Dictionary] = slots.duplicate(true)
	if not _add_to_slots(candidate, outputs).get("ok", false):
		return {"ok": false, "reason": "RESERVED_OUTPUT_BLOCKED"}
	reservations.erase(token)
	slots = candidate
	revision += 1
	changed.emit(snapshot())
	return {"ok": true, "reason": "OK", "revision": revision, "outputs": outputs.duplicate(true)}


func can_add_dirt(amount: int) -> bool:
	return amount > 0 and can_transaction({}, {"dirt": amount})


func can_remove_dirt(amount: int) -> bool:
	return amount > 0 and count("dirt") >= amount


func add_dirt(amount: int) -> bool:
	return amount > 0 and try_transaction({}, {"dirt": amount}).get("ok", false)


func remove_dirt(amount: int) -> bool:
	return amount > 0 and try_transaction({"dirt": amount}, {}).get("ok", false)


func restore(data: Dictionary) -> bool:
	var restored_revision := int(data.get("revision", -1))
	if restored_revision < 0:
		return false
	var candidate: Array[Dictionary] = []
	if data.get("slots") is Array:
		var raw_slots: Array = data.slots
		if raw_slots.size() != SLOT_COUNT:
			return false
		for value in raw_slots:
			if not value is Dictionary:
				return false
			var slot := _validated_slot(value)
			if slot.is_empty() and (not str(value.get("item_id", "")).is_empty() or int(value.get("count", 0)) != 0):
				return false
			candidate.append(slot if not slot.is_empty() else _empty_slot())
	else:
		for _index in range(SLOT_COUNT):
			candidate.append(_empty_slot())
		var legacy_dirt := int(data.get("dirt", -1))
		if legacy_dirt < 0:
			return false
		if legacy_dirt > 0 and not _add_to_slots(candidate, {"dirt": legacy_dirt}).get("ok", false):
			return false
	var restored_hotbar := int(data.get("selected_hotbar", 0))
	if restored_hotbar < 0 or restored_hotbar >= HOTBAR_COUNT:
		return false
	var restored_reservations: Dictionary = {}
	var raw_reservations: Variant = data.get("reservations", {})
	if not raw_reservations is Dictionary:
		return false
	for token: String in raw_reservations:
		var counts := _validate_counts(raw_reservations[token])
		if not counts.get("ok", false):
			return false
		restored_reservations[token] = counts.counts
	var probe: Array[Dictionary] = candidate.duplicate(true)
	for reserved: Dictionary in restored_reservations.values():
		if not _add_to_slots(probe, reserved).get("ok", false):
			return false
	slots = candidate
	reservations = restored_reservations
	selected_hotbar = restored_hotbar
	revision = restored_revision
	changed.emit(snapshot())
	return true


func snapshot() -> Dictionary:
	return {"slots": slots.duplicate(true), "selected_hotbar": selected_hotbar, "reservations": reservations.duplicate(true), "revision": revision, "dirt": dirt}


func _simulate(removals: Dictionary, additions: Dictionary) -> Dictionary:
	var removed := _remove_from_copy(slots.duplicate(true), removals)
	if not removed.get("ok", false):
		return removed
	var candidate: Array[Dictionary] = removed.slots
	var added := _add_to_slots(candidate, additions)
	if not added.get("ok", false):
		return added
	var capacity_probe: Array[Dictionary] = candidate.duplicate(true)
	for reserved: Dictionary in reservations.values():
		if not _add_to_slots(capacity_probe, reserved).get("ok", false):
			return {"ok": false, "reason": "INVENTORY_FULL"}
	return {"ok": true, "reason": "OK", "slots": candidate}


func _remove_from_copy(candidate: Array[Dictionary], removals: Dictionary) -> Dictionary:
	var validated := _validate_counts(removals)
	if not validated.get("ok", false):
		return validated
	for item_id: String in validated.counts:
		var remaining := int(validated.counts[item_id])
		if count_in(candidate, item_id) < remaining:
			return {"ok": false, "reason": "INSUFFICIENT_INPUT", "item_id": item_id}
		for index in range(candidate.size() - 1, -1, -1):
			if str(candidate[index].item_id) != item_id:
				continue
			var taken := mini(remaining, int(candidate[index].count))
			candidate[index].count = int(candidate[index].count) - taken
			remaining -= taken
			if int(candidate[index].count) == 0:
				candidate[index] = _empty_slot()
			if remaining == 0:
				break
	return {"ok": true, "reason": "OK", "slots": candidate}


func _add_to_slots(candidate: Array[Dictionary], additions: Dictionary) -> Dictionary:
	var validated := _validate_counts(additions)
	if not validated.get("ok", false):
		return validated
	for item_id: String in validated.counts:
		var remaining := int(validated.counts[item_id])
		var maximum := registry.max_stack(item_id)
		for index in range(candidate.size()):
			if str(candidate[index].item_id) != item_id or int(candidate[index].count) >= maximum:
				continue
			var inserted := mini(remaining, maximum - int(candidate[index].count))
			candidate[index].count = int(candidate[index].count) + inserted
			remaining -= inserted
			if remaining == 0:
				break
		while remaining > 0:
			var empty_index := _first_empty(candidate)
			if empty_index < 0:
				return {"ok": false, "reason": "INVENTORY_FULL", "item_id": item_id}
			var inserted := mini(remaining, maximum)
			candidate[empty_index] = {"item_id": item_id, "count": inserted}
			remaining -= inserted
	return {"ok": true, "reason": "OK", "slots": candidate}


func _validate_counts(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "reason": "INVALID_TRANSACTION"}
	var clean: Dictionary = {}
	for key: Variant in value:
		var item_id := str(key)
		var quantity_value: Variant = value[key]
		if typeof(quantity_value) not in [TYPE_INT, TYPE_FLOAT] or float(int(quantity_value)) != float(quantity_value) or int(quantity_value) <= 0 or registry.max_stack(item_id) <= 0:
			return {"ok": false, "reason": "INVALID_TRANSACTION", "item_id": item_id}
		clean[item_id] = int(quantity_value)
	return {"ok": true, "reason": "OK", "counts": clean}


func _normalized_counts(value: Dictionary) -> Dictionary:
	return _validate_counts(value).get("counts", {}).duplicate(true)


func _validated_slot(value: Dictionary) -> Dictionary:
	var item_id := str(value.get("item_id", ""))
	var quantity := int(value.get("count", 0))
	if item_id.is_empty() and quantity == 0:
		return _empty_slot()
	var maximum := registry.max_stack(item_id)
	if maximum <= 0 or quantity <= 0 or quantity > maximum:
		return {}
	return {"item_id": item_id, "count": quantity}


static func count_in(candidate: Array[Dictionary], item_id: String) -> int:
	var total := 0
	for slot in candidate:
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


static func _first_empty(candidate: Array[Dictionary]) -> int:
	for index in range(candidate.size()):
		if str(candidate[index].get("item_id", "")).is_empty():
			return index
	return -1


static func _empty_slot() -> Dictionary:
	return {"item_id": "", "count": 0}
