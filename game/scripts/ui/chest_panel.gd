class_name ChestPanel
extends VBoxContainer

## P4a-2: the middle column of the crafting modal when a placed Chest is
## opened. Shows the container slots as a 3 x 3 tile grid; every tile is a
## CraftingItemSlot (source and target kind "chest") so the app can route
## drag-drop, select-then-click, Shift and double-click gestures exactly like
## the Furnace slots. Presentation only — the WorkstationService owns the slots.

const COLUMNS := 3

var heading: Label
var help_label: Label
var grid: GridContainer
var slots: Array[CraftingItemSlot] = []


func _init() -> void:
	add_theme_constant_override("separation", 6)
	heading = Label.new()
	heading.text = "CHEST"
	heading.add_theme_color_override("font_color", Color("9fd8e8"))
	add_child(heading)
	help_label = Label.new()
	help_label.text = "Drag or double-click an inventory tile to store it; select then click a chest tile adds 1 (Shift 5). Click a chest tile takes 1; Shift or double-click takes the stack."
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", Color("8fa5af"))
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.max_lines_visible = 3
	help_label.custom_minimum_size = Vector2(330, 0)
	help_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(help_label)
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)


## Rebuilds the tile list to `count` slots, connecting each new tile's
## signals through `connector(tile, index)`.
func ensure_slots(count: int, connector: Callable) -> void:
	if slots.size() == count:
		return
	for tile in slots:
		grid.remove_child(tile)
		tile.queue_free()
	slots.clear()
	for index in range(count):
		var tile := CraftingItemSlot.new()
		tile.custom_minimum_size = Vector2(94, 74)
		tile.add_theme_stylebox_override("normal", FoundationTheme.panel(Color("0a141b"), Color("365363"), 5, 7))
		tile.add_theme_stylebox_override("hover", FoundationTheme.panel(Color("132733"), Color("78cbe0"), 5, 7))
		tile.configure_source("chest", index, "")
		tile.configure_target("chest", index)
		connector.call(tile, index)
		slots.append(tile)
		grid.add_child(tile)


## Applies `container_slots(...)` ([{item_id, count}, ...]).
func refresh(container_slots: Array, registry: ContentRegistry, cursor_active: bool) -> void:
	var used := 0
	for index in range(slots.size()):
		var stack: Dictionary = container_slots[index] if index < container_slots.size() else {"item_id": "", "count": 0}
		var item_id := str(stack.get("item_id", ""))
		var count := int(stack.get("count", 0))
		if not item_id.is_empty() and count > 0:
			used += 1
		var tile := slots[index]
		tile.configure_source("chest", index, item_id)
		tile.set_cursor_active(cursor_active)
		tile.set_presentation("Empty" if item_id.is_empty() else registry.display_name(item_id), count)
		tile.tooltip_text = "Chest slot %d · click takes 1, Shift+Click or double-click takes the stack; with a selected inventory item click stores 1 (Shift 5)" % (index + 1)
	heading.text = "CHEST · %d/%d SLOTS USED" % [used, slots.size()]
