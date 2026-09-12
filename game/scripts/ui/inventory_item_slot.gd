class_name InventoryItemSlot
extends Button

signal item_dropped(source_index: int, target_index: int)

var slot_index := -1
var item_id := ""


func configure(index: int, stable_item_id: String) -> void:
	slot_index = index
	item_id = stable_item_id
	mouse_default_cursor_shape = Control.CURSOR_DRAG if not item_id.is_empty() else Control.CURSOR_ARROW


func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_index < 0 or item_id.is_empty():
		return null
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(150, 48)
	preview.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("18303c"), Color("78cbe0"), 7, 9))
	var label := Label.new()
	label.text = text.replace("\n", "  ").strip_edges()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": "inventory_slot", "source_index": slot_index, "item_id": item_id}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return slot_index >= 0 and data is Dictionary and str(data.get("kind", "")) == "inventory_slot" and int(data.get("source_index", -1)) >= 0


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(int(data.get("source_index", -1)), slot_index)
