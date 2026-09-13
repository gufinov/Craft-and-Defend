class_name GameplayHotbarSlot
extends PanelContainer

var slot_index := -1
var item_id := ""
var selected := false
var _display_name := "Empty"
var _count := 0
var _key_label: Label
var _icon: TextureRect
var _fallback_icon: Label
var _count_label: Label
var _name_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(88, 78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_key_label = Label.new()
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_label.add_theme_font_size_override("font_size", 13)
	column.add_child(_key_label)
	var icon_row := HBoxContainer.new()
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.add_theme_constant_override("separation", 3)
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon_row)
	var icon_stack := Control.new()
	icon_stack.custom_minimum_size = Vector2(34, 34)
	icon_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_child(icon_stack)
	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(_icon)
	_fallback_icon = Label.new()
	_fallback_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_icon.add_theme_font_size_override("font_size", 16)
	_fallback_icon.add_theme_color_override("font_color", Color("9fd8e8"))
	_fallback_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(_fallback_icon)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 14)
	icon_row.add_child(_count_label)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 11)
	column.add_child(_name_label)
	_refresh()


func set_slot(index: int, stable_item_id: String, display_name: String, count: int, is_selected: bool) -> void:
	slot_index = index
	item_id = stable_item_id
	_display_name = display_name
	_count = count
	selected = is_selected
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	if _key_label == null:
		return
	var border := Color("ffe08a") if selected else Color("4b7180")
	var background := Color("26333a") if selected else Color(0.035, 0.06, 0.075, 0.88)
	add_theme_stylebox_override("panel", FoundationTheme.panel(background, border, 6, 5))
	_key_label.text = "%d%s" % [slot_index + 1, "  HELD" if selected else ""]
	_key_label.add_theme_color_override("font_color", Color("ffe08a") if selected else Color("d8e5ea"))
	_name_label.text = _display_name
	_count_label.text = "×%d" % _count if not item_id.is_empty() else ""
	tooltip_text = "Key %d — %s%s" % [slot_index + 1, _display_name, " ×%d" % _count if not item_id.is_empty() else ""]
	_icon.texture = ItemIconCatalog.texture_for(item_id)
	var has_texture := not item_id.is_empty() and _icon.texture != null
	_icon.visible = has_texture
	_fallback_icon.visible = not has_texture
	_fallback_icon.text = "—" if item_id.is_empty() else _initials(_display_name)


func _initials(value: String) -> String:
	var pieces := value.split(" ", false)
	if pieces.is_empty():
		return "?"
	if pieces.size() == 1:
		return pieces[0].left(2).to_upper()
	return (pieces[0].left(1) + pieces[1].left(1)).to_upper()
