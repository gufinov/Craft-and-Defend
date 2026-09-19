class_name SiegeWeaponPanel
extends VBoxContainer

## P4a-2: the middle column of the crafting modal when a placed siege weapon
## (Ballista, Catapult) is opened. Pure presentation: it shows `siege_status`
## details and emits control requests; the app routes them to the
## WorkstationService (UI never mutates game state directly).

signal unload_requested
signal stance_requested(stance: String)
signal target_filter_requested(target_filter: String)

const TARGET_FILTERS: Array[String] = ["any", "raider", "brute", "structure"]
const TARGET_FILTER_LABELS: Dictionary = {"any": "Any target", "raider": "Raiders", "brute": "Brutes", "structure": "Structures"}

var heading: Label
var name_label: Label
var stats_label: Label
var ammo_heading: Label
var ammo_slot: CraftingItemSlot
var ammo_help: Label
var unload_button: Button
var fire_button: Button
var hold_button: Button
var filter_option: OptionButton
var supply_heading: Label
var supply_label: Label
var _filter_refreshing := false


func _init() -> void:
	add_theme_constant_override("separation", 4)
	heading = Label.new()
	heading.text = "WEAPON"
	heading.add_theme_color_override("font_color", Color("9fd8e8"))
	add_child(heading)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color("ffe08a"))
	add_child(name_label)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color("c9f4ff"))
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.max_lines_visible = 4
	stats_label.custom_minimum_size = Vector2(330, 0)
	stats_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(stats_label)
	ammo_heading = Label.new()
	ammo_heading.text = "AMMUNITION"
	ammo_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	add_child(ammo_heading)
	var ammo_row := HBoxContainer.new()
	ammo_row.add_theme_constant_override("separation", 10)
	add_child(ammo_row)
	ammo_slot = CraftingItemSlot.new()
	ammo_slot.custom_minimum_size = Vector2(94, 74)
	ammo_slot.add_theme_stylebox_override("normal", FoundationTheme.panel(Color("0a141b"), Color("365363"), 5, 7))
	ammo_slot.add_theme_stylebox_override("hover", FoundationTheme.panel(Color("132733"), Color("78cbe0"), 5, 7))
	ammo_slot.tooltip_text = "Ammunition · select a munition tile then click adds 1 (Shift+Click 5); drag or double-click a tile loads as many as fit; double-click here unloads"
	ammo_slot.configure_source("siege_ammo", 0, "")
	ammo_slot.configure_target("siege_ammo", 0)
	ammo_row.add_child(ammo_slot)
	var ammo_column := VBoxContainer.new()
	ammo_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ammo_column.add_theme_constant_override("separation", 4)
	ammo_row.add_child(ammo_column)
	ammo_help = Label.new()
	ammo_help.add_theme_font_size_override("font_size", 12)
	ammo_help.add_theme_color_override("font_color", Color("8fa5af"))
	ammo_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ammo_help.max_lines_visible = 3
	ammo_help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ammo_help.mouse_filter = Control.MOUSE_FILTER_STOP
	ammo_column.add_child(ammo_help)
	unload_button = Button.new()
	unload_button.text = "Unload"
	unload_button.custom_minimum_size = Vector2(120, 34)
	unload_button.tooltip_text = "Return every loaded munition to the inventory"
	unload_button.pressed.connect(func() -> void: unload_requested.emit())
	ammo_column.add_child(unload_button)
	var stance_heading := Label.new()
	stance_heading.text = "STANCE"
	stance_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	add_child(stance_heading)
	var stance_row := HBoxContainer.new()
	stance_row.add_theme_constant_override("separation", 8)
	add_child(stance_row)
	fire_button = Button.new()
	fire_button.text = "Fire at will"
	fire_button.toggle_mode = true
	fire_button.custom_minimum_size = Vector2(160, 36)
	fire_button.tooltip_text = "Fires at the first matching target in range"
	fire_button.pressed.connect(func() -> void: stance_requested.emit("fire_at_will"))
	stance_row.add_child(fire_button)
	hold_button = Button.new()
	hold_button.text = "Hold"
	hold_button.toggle_mode = true
	hold_button.custom_minimum_size = Vector2(160, 36)
	hold_button.tooltip_text = "Holds fire; the weapon still turns to face targets"
	hold_button.pressed.connect(func() -> void: stance_requested.emit("hold"))
	stance_row.add_child(hold_button)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	add_child(filter_row)
	var filter_label := Label.new()
	filter_label.text = "Target"
	filter_label.custom_minimum_size = Vector2(70, 36)
	filter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filter_row.add_child(filter_label)
	filter_option = OptionButton.new()
	filter_option.custom_minimum_size = Vector2(250, 36)
	filter_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(TARGET_FILTERS.size()):
		filter_option.add_item(str(TARGET_FILTER_LABELS[TARGET_FILTERS[index]]), index)
	filter_option.item_selected.connect(_on_filter_selected)
	filter_row.add_child(filter_option)
	supply_heading = Label.new()
	supply_heading.text = "SUPPLY"
	supply_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	add_child(supply_heading)
	supply_label = Label.new()
	supply_label.add_theme_font_size_override("font_size", 13)
	supply_label.add_theme_color_override("font_color", Color("c9f4ff"))
	supply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	supply_label.max_lines_visible = 3
	supply_label.custom_minimum_size = Vector2(330, 54)
	supply_label.mouse_filter = Control.MOUSE_FILTER_STOP
	supply_label.tooltip_text = "Chests within the supply radius holding a compatible munition; an empty weapon reloads from the nearest one"
	add_child(supply_label)


## Applies `siege_status(...).details` and the `siege_supply` list.
func refresh(details: Dictionary, supply: Array, registry: ContentRegistry, selected_item: String, cursor_active: bool) -> void:
	var definition: Dictionary = details.get("definition", {})
	var ammo := int(details.get("ammo", 0))
	var capacity := int(details.get("capacity", 1))
	var ammo_item := str(details.get("ammo_item", ""))
	var munition: Dictionary = details.get("munition", {})
	name_label.text = registry.display_name(str(details.get("entity_id", "weapon")))
	var damage_text := "%d" % int(munition.get("damage", definition.get("damage", 0)))
	var splash := float(munition.get("splash_radius", 0.0))
	stats_label.text = "Range %.0f–%.0f blocks  ·  Damage %s%s\nReload %.1f s  ·  %s" % [
		float(definition.get("minimum_range", 0.0)), float(definition.get("maximum_range", 0.0)), damage_text,
		"  ·  Splash %.1f" % splash if splash > 0.0 else "",
		float(definition.get("cooldown_seconds", 0.0)),
		"Ready" if float(details.get("cooldown", 0.0)) <= 0.0 else "Cooling %.1f s" % float(details.get("cooldown", 0.0)),
	]
	var shown_item := ammo_item if ammo > 0 else ""
	ammo_slot.configure_source("siege_ammo", 0, shown_item)
	ammo_slot.set_cursor_active(cursor_active)
	ammo_slot.set_presentation("Empty" if shown_item.is_empty() else registry.display_name(shown_item), ammo)
	var allowed: Array = definition.get("ammo_items", [definition.get("ammo_item", "")])
	var allowed_names: PackedStringArray = PackedStringArray()
	for item_id in allowed:
		allowed_names.append(registry.display_name(str(item_id)))
	var loaded_text := "%d / %d" % [ammo, capacity]
	if not selected_item.is_empty() and str(selected_item) in allowed:
		ammo_help.text = "%s loaded · %s selected — click the slot to load 1, Shift+Click 5" % [loaded_text, registry.display_name(selected_item)]
	else:
		ammo_help.text = "%s loaded · takes %s. Click a munition tile, then the slot (or drag / double-click the tile)" % [loaded_text, " or ".join(allowed_names)]
	unload_button.disabled = ammo <= 0
	var stance := str(details.get("stance", "fire_at_will"))
	fire_button.set_pressed_no_signal(stance == "fire_at_will")
	hold_button.set_pressed_no_signal(stance == "hold")
	var target_filter := str(details.get("target_filter", "any"))
	_filter_refreshing = true
	filter_option.select(maxi(0, TARGET_FILTERS.find(target_filter)))
	_filter_refreshing = false
	var radius := float(definition.get("supply_radius", 8.0))
	if supply.is_empty():
		# A loaded weapon only reloads its own munition type, so name it.
		var wanted := registry.display_name(ammo_item) if ammo > 0 and not ammo_item.is_empty() else "munitions"
		supply_label.text = "No chest with %s within %.0f blocks" % [wanted, radius]
	else:
		var lines: PackedStringArray = PackedStringArray()
		for entry in supply:
			if lines.size() >= 3:
				break
			var source: Dictionary = entry
			lines.append("Chest %.1f m · %s ×%d" % [float(source.get("distance", 0.0)), registry.display_name(str(source.get("item_id", ""))), int(source.get("count", 0))])
		supply_label.text = "\n".join(lines)


func _on_filter_selected(index: int) -> void:
	if _filter_refreshing or index < 0 or index >= TARGET_FILTERS.size():
		return
	target_filter_requested.emit(TARGET_FILTERS[index])
