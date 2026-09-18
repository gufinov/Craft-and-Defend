class_name GameplayHotbarSlot
extends PanelContainer

## Square in-game hotbar tile. Every element is anchored inside the tile so the
## rect never grows past TILE_SIZE: key number (the keybind) across the top,
## icon centred in the middle band with the count in its corner, and the item
## name as the caption along the bottom (owner playtest 2026-09-18: no slot
## numbers in captions, tiles fully visible above the window edge).
const TILE_SIZE := Vector2(80, 80)
const PANEL_PADDING := 4
const KEY_BAND_HEIGHT := 17.0
const CAPTION_BAND_HEIGHT := 14.0
const ICON_SIZE := 34.0

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
	custom_minimum_size = TILE_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	_key_label = Label.new()
	_key_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_key_label.offset_bottom = KEY_BAND_HEIGHT
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key_label.clip_text = true
	_key_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	_key_label.add_theme_font_size_override("font_size", 12)
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_key_label)
	var icon_band := Control.new()
	icon_band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_band.offset_top = KEY_BAND_HEIGHT
	icon_band.offset_bottom = -CAPTION_BAND_HEIGHT
	icon_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(icon_band)
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_CENTER)
	_icon.offset_left = -ICON_SIZE / 2.0
	_icon.offset_top = -ICON_SIZE / 2.0
	_icon.offset_right = ICON_SIZE / 2.0
	_icon.offset_bottom = ICON_SIZE / 2.0
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_band.add_child(_icon)
	_fallback_icon = Label.new()
	_fallback_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_icon.clip_text = true
	_fallback_icon.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	_fallback_icon.add_theme_font_size_override("font_size", 16)
	_fallback_icon.add_theme_color_override("font_color", Color("9fd8e8"))
	_fallback_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_band.add_child(_fallback_icon)
	_count_label = Label.new()
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.clip_text = true
	_count_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_constant_override("outline_size", 3)
	_count_label.add_theme_color_override("font_outline_color", Color("071016"))
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_band.add_child(_count_label)
	_name_label = Label.new()
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name_label.offset_top = -CAPTION_BAND_HEIGHT
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_name_label)
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
	add_theme_stylebox_override("panel", FoundationTheme.panel(background, border, 6, PANEL_PADDING))
	_key_label.text = "%d%s" % [slot_index + 1, "  HELD" if selected else ""]
	_key_label.add_theme_color_override("font_color", Color("ffe08a") if selected else Color("d8e5ea"))
	_name_label.text = _display_name
	_name_label.add_theme_color_override("font_color", Color("ffe08a") if selected else Color("d5e2e8"))
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
