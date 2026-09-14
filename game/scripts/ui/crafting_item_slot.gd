class_name CraftingItemSlot
extends Button

signal item_dropped(target_kind: String, target_index: int, payload: Dictionary)
signal stack_gesture(source_kind: String, source_index: int, mouse_button: int, double_click: bool, dragging: bool)

var source_kind := ""
var source_index := -1
var item_id := ""
var target_kind := ""
var target_index := -1
var cursor_active := false
var _drag_label := ""
var _icon: TextureRect
var _count_label: Label
var _name_label: Label
var _presentation_name := "Empty"
var _presentation_count := 0
var _presentation_marker := ""


func _ready() -> void:
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
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
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_name_label)
	_apply_presentation()


func configure_source(kind: String, index: int, stable_item_id: String) -> void:
	source_kind = kind
	source_index = index
	item_id = stable_item_id


func set_presentation(display_name: String, count: int = 0, marker: String = "") -> void:
	_presentation_name = display_name
	_presentation_count = count
	_presentation_marker = marker
	_drag_label = "%s%s%s" % [marker, display_name, " ×%d" % count if count > 0 else ""]
	if _icon == null:
		return
	_apply_presentation()


func _apply_presentation() -> void:
	_icon.texture = ItemIconCatalog.texture_for(item_id)
	_icon.visible = not item_id.is_empty() and _icon.texture != null
	_count_label.text = "×%d" % _presentation_count if _presentation_count > 0 else ""
	_name_label.text = "%s%s" % [_presentation_marker, _presentation_name]


func configure_target(kind: String, index: int) -> void:
	target_kind = kind
	target_index = index


func set_cursor_active(active: bool) -> void:
	cursor_active = active


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty():
		return null
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(140, 42)
	preview.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("18303c"), Color("78cbe0"), 7, 9))
	var label := Label.new()
	label.text = _drag_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": "crafting_item", "source_kind": source_kind, "source_index": source_index, "item_id": item_id}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and str(data.get("kind", "")) == "crafting_item" and not target_kind.is_empty()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(target_kind, target_index, data)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and (event.double_click or cursor_active)):
			stack_gesture.emit(source_kind, source_index, int(event.button_index), bool(event.double_click), false)
			accept_event()
	elif event is InputEventMouseMotion and bool(event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		stack_gesture.emit(source_kind, source_index, MOUSE_BUTTON_RIGHT, false, true)
