class_name InventoryItemSlot
extends Button

signal item_dropped(source_index: int, target_index: int)
signal stack_gesture(source_kind: String, source_index: int, mouse_button: int, double_click: bool, dragging: bool, shift_pressed: bool)

var slot_index := -1
var item_id := ""
var cursor_active := false
var _drag_label := "Empty"
var _icon: TextureRect
var _key_label: Label
var _count_label: Label
var _name_label: Label
var _presentation_slot := ""
var _presentation_name := "Empty"
var _presentation_count := 0
var _presentation_marker := ""


func _ready() -> void:
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	# P3H.5: same tile anatomy as CraftingItemSlot — a large centred icon with
	# the count in its corner and one item-name caption beneath. Hotbar tiles
	# additionally show their key (1–9) in the top-left corner; no slot index
	# appears in any caption (owner correction 2026-09-18).
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(38, 36)
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
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_constant_override("outline_size", 3)
	_count_label.add_theme_color_override("font_outline_color", Color("071016"))
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_count_label)
	_key_label = Label.new()
	_key_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_key_label.add_theme_font_size_override("font_size", 11)
	_key_label.add_theme_color_override("font_color", Color("9fd8e8"))
	_key_label.add_theme_constant_override("outline_size", 3)
	_key_label.add_theme_color_override("font_outline_color", Color("071016"))
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_key_label)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_name_label)
	_apply_presentation()


func configure(index: int, stable_item_id: String) -> void:
	slot_index = index
	item_id = stable_item_id
	mouse_default_cursor_shape = Control.CURSOR_DRAG if not item_id.is_empty() else Control.CURSOR_ARROW


func set_cursor_active(active: bool) -> void:
	cursor_active = active


## `key_label` is the hotbar key shown in the tile corner ("1".."9"); pass ""
## for carried slots. The caption is the item name only.
func set_presentation(key_label: String, display_name: String, count: int, marker: String = "") -> void:
	_presentation_slot = key_label
	_presentation_name = display_name
	_presentation_count = count
	_presentation_marker = marker
	var key_prefix := "Key %s · " % key_label if not key_label.is_empty() else ""
	_drag_label = "%s%s ×%d" % [key_prefix, display_name, count] if not item_id.is_empty() else "%sEmpty" % key_prefix
	if _icon == null:
		return
	_apply_presentation()


func _apply_presentation() -> void:
	_icon.texture = ItemIconCatalog.texture_for(item_id)
	_icon.visible = not item_id.is_empty() and _icon.texture != null
	_count_label.text = "×%d" % _presentation_count if not item_id.is_empty() else ""
	_key_label.text = _presentation_slot
	_key_label.visible = not _presentation_slot.is_empty()
	var caption := _presentation_name if not item_id.is_empty() else "Empty"
	_name_label.text = caption if _presentation_marker.is_empty() else "%s %s" % [_presentation_marker, caption]
	_name_label.add_theme_color_override("font_color", Color("ffe08a") if _presentation_marker.contains("▶") else Color("d5e2e8"))


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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and (event.double_click or cursor_active or event.shift_pressed)):
			stack_gesture.emit("inventory", slot_index, int(event.button_index), bool(event.double_click), false, bool(event.shift_pressed))
			accept_event()
	elif event is InputEventMouseMotion and bool(event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		stack_gesture.emit("inventory", slot_index, MOUSE_BUTTON_RIGHT, false, true, bool(event.shift_pressed))
