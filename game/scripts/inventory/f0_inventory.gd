class_name F0Inventory
extends RefCounted

signal changed(snapshot: Dictionary)

const MAX_DIRT := 64

var dirt := 0
var revision := 0


func can_add_dirt(amount: int) -> bool:
	return amount > 0 and dirt + amount <= MAX_DIRT


func can_remove_dirt(amount: int) -> bool:
	return amount > 0 and dirt >= amount


func add_dirt(amount: int) -> bool:
	if not can_add_dirt(amount):
		return false
	dirt += amount
	revision += 1
	changed.emit(snapshot())
	return true


func remove_dirt(amount: int) -> bool:
	if not can_remove_dirt(amount):
		return false
	dirt -= amount
	revision += 1
	changed.emit(snapshot())
	return true


func restore(data: Dictionary) -> bool:
	var restored_dirt := int(data.get("dirt", -1))
	var restored_revision := int(data.get("revision", -1))
	if restored_dirt < 0 or restored_dirt > MAX_DIRT or restored_revision < 0:
		return false
	dirt = restored_dirt
	revision = restored_revision
	changed.emit(snapshot())
	return true


func snapshot() -> Dictionary:
	return {"dirt": dirt, "revision": revision}

