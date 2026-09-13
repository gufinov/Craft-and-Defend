class_name InventoryItemSlot
extends Button

signal item_dropped(source_index: int, target_index: int)

var slot_index := -1
var item_id := ""
var _drag_label := "Empty"
var _icon: TextureRect
var _slot_label: Label
var _count_label: Label
var _name_label: Label


func _ready() -> void:
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_slot_label = Label.new()
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.add_theme_font_size_override("font_size", 11)
	_slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_slot_label)
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(42, 38)
	icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon_holder)
	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_icon)
	_count_label = Label.new()
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_constant_override("outline_size", 3)
	_count_label.add_theme_color_override("font_outline_color", Color("071016"))
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_count_label)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_name_label)


func configure(index: int, stable_item_id: String) -> void:
	slot_index = index
	item_id = stable_item_id
	mouse_default_cursor_shape = Control.CURSOR_DRAG if not item_id.is_empty() else Control.CURSOR_ARROW


func set_presentation(slot_label: String, display_name: String, count: int, marker: String = "") -> void:
	_drag_label = "%s %s ×%d" % [slot_label, display_name, count] if not item_id.is_empty() else "%s Empty" % slot_label
	if _icon == null:
		return
	_slot_label.text = "%s%s" % [marker, slot_label]
	_slot_label.add_theme_color_override("font_color", Color("ffe08a") if marker.contains("▶") else Color("b8cad1"))
	_icon.texture = ItemIconCatalog.texture_for(item_id)
	_icon.visible = not item_id.is_empty() and _icon.texture != null
	_count_label.text = "×%d" % count if not item_id.is_empty() else ""
	_name_label.text = display_name if not item_id.is_empty() else "Empty"


func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_index < 0 or item_id.is_empty():
		return null
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(150, 48)
	preview.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("18303c"), Color("78cbe0"), 7, 9))
	var label := Label.new()
	label.text = _drag_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": "inventory_slot", "source_index": slot_index, "item_id": item_id}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return slot_index >= 0 and data is Dictionary and str(data.get("kind", "")) == "inventory_slot" and int(data.get("source_index", -1)) >= 0


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(int(data.get("source_index", -1)), slot_index)
