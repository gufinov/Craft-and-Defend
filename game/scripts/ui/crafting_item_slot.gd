class_name CraftingItemSlot
extends Button

signal item_dropped(target_kind: String, target_index: int, payload: Dictionary)

var source_kind := ""
var source_index := -1
var item_id := ""
var target_kind := ""
var target_index := -1


func configure_source(kind: String, index: int, stable_item_id: String) -> void:
	source_kind = kind
	source_index = index
	item_id = stable_item_id


func configure_target(kind: String, index: int) -> void:
	target_kind = kind
	target_index = index


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty():
		return null
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(140, 42)
	preview.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("18303c"), Color("78cbe0"), 7, 9))
	var label := Label.new()
	label.text = text.strip_edges()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": "crafting_item", "source_kind": source_kind, "source_index": source_index, "item_id": item_id}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and str(data.get("kind", "")) == "crafting_item" and not target_kind.is_empty()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(target_kind, target_index, data)
