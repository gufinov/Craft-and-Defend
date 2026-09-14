class_name RecipeCatalogCard
extends Button

var recipe_id := ""
var _icon: TextureRect
var _name_label: Label
var _status_label: Label
var _recipe: Dictionary = {}
var _display_name := ""
var _available := false
var _selected := false
var _detail := ""


func _ready() -> void:
	custom_minimum_size = Vector2(118, 128)
	clip_contents = true
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 1)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(74, 78)
	_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.clip_contents = true
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_icon)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_name_label)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_status_label)
	_apply_configuration()


func configure(recipe: Dictionary, display_name: String, available: bool, selected: bool, detail: String) -> void:
	recipe_id = str(recipe.get("id", ""))
	_recipe = recipe.duplicate(true)
	_display_name = display_name
	_available = available
	_selected = selected
	_detail = detail
	_apply_configuration()


func is_populated() -> bool:
	return _icon != null and _icon.texture != null and _name_label != null and not _name_label.text.is_empty()


func _apply_configuration() -> void:
	if _icon == null:
		return
	_icon.texture = ItemIconCatalog.recipe_texture(_recipe)
	_name_label.text = _display_name
	_status_label.text = "● READY" if _available else "○ LOCKED"
	_status_label.add_theme_color_override("font_color", Color("75e2a1") if _available else Color("94a5ad"))
	var background := Color("18303c") if _selected else Color("101a23")
	var border := Color("ffe08a") if _selected else (Color("5fa8bd") if _available else Color("344c5a"))
	add_theme_stylebox_override("normal", FoundationTheme.panel(background, border, 7, 7))
	add_theme_stylebox_override("hover", FoundationTheme.panel(Color("1c3845"), Color("78cbe0"), 7, 7))
	add_theme_stylebox_override("pressed", FoundationTheme.panel(Color("203f4d"), Color("ffe08a"), 7, 7))
	tooltip_text = _detail
