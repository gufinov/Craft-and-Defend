class_name CraftAndDefendApp
extends Node

enum AppState { MAIN_MENU, LOADING, PLAYING, PAUSED, INVENTORY, CRAFTING, SAVING, ERROR }

const DISPLAY_CONFIRM_SECONDS := 10.0
const PRINT_SCREEN_FOCUS_WINDOW_MSEC := 2000
const SCREENSHOT_CLICK_GUARD_SECONDS := 0.20
const RECIPE_PAGE_SIZE := 12
## Tab-inventory tiles share the crafting inventory's square anatomy.
const INVENTORY_TILE_SIZE := Vector2(96, 92)
const INVENTORY_TILE_GAP := 8
## Gap between in-game hotbar tiles and the canvas-pixel margin kept below them.
const GAMEPLAY_HOTBAR_GAP := 5
const GAMEPLAY_HOTBAR_BOTTOM_MARGIN := 14
const INVENTORY_FILTERS: Array[Dictionary] = [
	{"id": "all", "label": "All"},
	{"id": "resource", "label": "Resources"},
	{"id": "building", "label": "Building"},
	{"id": "tool", "label": "Tools"},
	{"id": "station", "label": "Stations"},
	{"id": "food", "label": "Food"},
]
const BINDING_GROUPS: Array[Dictionary] = [
	{"title": "MOVEMENT", "actions": ["move_forward", "move_backward", "strafe_left", "strafe_right", "sprint", "crouch", "jump"]},
	{"title": "WORLD & MENUS", "actions": ["primary", "secondary", "interact", "inventory", "build", "rotate_build_clockwise", "rotate_build_counterclockwise", "pause", "capture_screenshot"]},
	{"title": "HOTBAR", "actions": ["hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8", "hotbar_9"]},
]

var state := AppState.MAIN_MENU
## True when any --*-automation= argument selected a diagnostic run.
var automation_active := false
var data_root := ""
var settings: SettingsStore
var saves: SaveCoordinator
var screenshots: GameplayScreenshotService
var session: GameSession

var menu_panel: Control
var pause_panel: Control
## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): pause-menu toggle.
var hero_armor_button: Button
var track_auto_clear_button: Button
var keybind_panel: Control
var settings_panel: Control
var inventory_panel: Control
var crafting_panel: Control
var display_confirm_panel: Control
var loading_panel: Control
var hud_layer: Control
var minimap: MinimapOverlay
var continue_button: Button
var start_button: Button
var slot_option: OptionButton
var slot_status_label: Label
var loading_back_button: Button
var loading_retry_button: Button
var loading_return_button: Button
var forward_binding_label: Label
var keybind_message: Label
var settings_message: Label
var settings_scroll: ScrollContainer
var status_label: Label
var hud_text_column: VBoxContainer
var hud_label: Label
var feedback_label: Label
var navigation_label: Label
var defense_label: Label
var gameplay_hotbar: HBoxContainer
var gameplay_hotbar_slots: Array[GameplayHotbarSlot] = []
var inventory_contents_label: Label
var keybind_search: LineEdit
var binding_rows: Dictionary = {}
var binding_reset_buttons: Dictionary = {}
var inventory_slot_buttons: Array[InventoryItemSlot] = []
var inventory_carried_grid: GridContainer
var inventory_hotbar_grid: GridContainer
var inventory_left_column: VBoxContainer
var inventory_armor_card: PanelContainer
var inventory_armor_slot_buttons: Array[Button] = []
var inventory_silhouette: ArmorSilhouette
var inventory_filter_buttons: Dictionary = {}
var inventory_filter_empty_label: Label
var inventory_message: Label
var crafting_title_label: Label
var crafting_context_label: Label
var crafting_inventory_grid: GridContainer
var crafting_inventory_help: Label
var crafting_inventory_slots: Array[CraftingItemSlot] = []
var crafting_recipe_list: GridContainer
var crafting_recipe_search: LineEdit
var crafting_recipe_previous: Button
var crafting_recipe_next: Button
var crafting_recipe_page_label: Label
var crafting_grid: GridContainer
var crafting_grid_slots: Array[CraftingItemSlot] = []
var crafting_grid_help: Label
var crafting_output_label: Label
var furnace_controls: VBoxContainer
var furnace_auto_load_label: Label
var furnace_auto_load_slider: HSlider
var furnace_progress_bar: ProgressBar
var furnace_progress_label: Label
var crafting_message: Label
var craft_selected_button: Button
var crafting_clear_button: Button
## P4a-2: the modal's middle/right cards swap by station type. The crafting
## grid + recipe book serve hand/workbench/furnace; a siege weapon shows the
## weapon panel + munition legend; a Chest shows its 3 x 3 container grid.
var crafting_grid_card: PanelContainer
var crafting_grid_column: VBoxContainer
var crafting_recipe_card: PanelContainer
var siege_card: PanelContainer
var siege_column: VBoxContainer
var siege_panel: SiegeWeaponPanel
var siege_legend_card: PanelContainer
var siege_legend_list: VBoxContainer
var chest_card: PanelContainer
var chest_column: VBoxContainer
var chest_panel: ChestPanel
var cursor_stack_panel: PanelContainer
var cursor_stack_icon: TextureRect
var cursor_stack_count: Label
const CRAFTING_STATION_TYPES: Array[String] = ["workbench", "furnace", "siege", "chest"]
var _crafting_station_id := ""
var _crafting_station_type := "hand"
var _selected_recipe_id := ""
var _craft_grid_items: Array[String] = []
## Red placeholders (owner 2026-09-19): when a recipe is clicked with some
## ingredients missing, the missing ones sit in the grid as ghosts keyed by
## cell index so the player sees exactly what to gather.
var _craft_grid_ghosts: Dictionary = {}
var _crafting_selected_inventory_item := ""
var _crafting_recipe_page := 0
var _inventory_move_source := -1
var _inventory_filter := "all"
var _right_drag_visited: Dictionary = {}
var _furnace_slider_refreshing := false
var sensitivity_slider: HSlider
var sensitivity_value_label: Label
var invert_check: CheckButton
var volume_slider: HSlider
var volume_value_label: Label
var window_mode_option: OptionButton
var resolution_option: OptionButton
var msaa_option: OptionButton
var view_distance_option: OptionButton
var vsync_check: CheckButton
var windowed_resolution_row: HBoxContainer
var fullscreen_resolution_row: HBoxContainer
var fullscreen_resolution_value_label: Label
var world_settings_toggle: Button
var world_settings_content: VBoxContainer
var world_time_input: LineEdit
var world_cycle_check: CheckButton
var world_apply_button: Button
var world_settings_message: Label
var display_confirm_label: Label
var binding_labels: Dictionary = {}
var capture_action := ""
var capture_forward := false
var _overlay_return_state := AppState.MAIN_MENU
var _display_confirm_remaining := 0.0
var _print_screen_pressed_msec := -PRINT_SCREEN_FOCUS_WINDOW_MSEC
var _screenshot_focus_suspended := false
var _screenshot_resume_generation := 0
var _failed_save_quit_after := false
var _hud_state_text := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	data_root = _resolve_data_root()
	DirAccess.make_dir_recursive_absolute(data_root)
	settings = SettingsStore.new(data_root)
	settings.load_and_apply()
	_apply_runtime_graphics()
	saves = SaveCoordinator.new(data_root)
	screenshots = GameplayScreenshotService.new(data_root)
	_build_interface()
	_show_main_menu()
	print("DATA_ROOT %s" % data_root)
	var f0_mode := _argument_value("--f0-automation=")
	if not f0_mode.is_empty():
		var f0_automation := F0Automation.new()
		add_child(f0_automation)
		f0_automation.call_deferred("run", self, f0_mode)
	var f1_mode := _argument_value("--f1-automation=")
	if not f1_mode.is_empty():
		var f1_automation := F1Automation.new()
		add_child(f1_automation)
		f1_automation.call_deferred("run", self, f1_mode)
	var f2_mode := _argument_value("--f2-automation=")
	if not f2_mode.is_empty():
		var f2_automation := F2Automation.new()
		add_child(f2_automation)
		f2_automation.call_deferred("run", self, f2_mode)
	var f3_mode := _argument_value("--f3-automation=")
	if not f3_mode.is_empty():
		var f3_automation := F3Automation.new()
		add_child(f3_automation)
		f3_automation.call_deferred("run", self, f3_mode)
	var f4_mode := _argument_value("--f4-automation=")
	if not f4_mode.is_empty():
		var f4_automation := F4Automation.new()
		add_child(f4_automation)
		f4_automation.call_deferred("run", self, f4_mode)
	var f5_mode := _argument_value("--f5-automation=")
	if not f5_mode.is_empty():
		var f5_automation := F5Automation.new()
		add_child(f5_automation)
		f5_automation.call_deferred("run", self, f5_mode)
	var p1_mode := _argument_value("--p1-automation=")
	if not p1_mode.is_empty():
		var p1_automation := P1Automation.new()
		add_child(p1_automation)
		p1_automation.call_deferred("run", self, p1_mode)
	var p3k_mode := _argument_value("--p3k-blueprint-automation=")
	if not p3k_mode.is_empty():
		var p3k_automation := P3KBlueprintAutomation.new()
		add_child(p3k_automation)
		p3k_automation.call_deferred("run", self, p3k_mode)
	var castle_mode := _argument_value("--castle-kit-automation=")
	if not castle_mode.is_empty():
		var castle_automation := CastleKitAutomation.new()
		add_child(castle_automation)
		castle_automation.call_deferred("run", self, castle_mode)
	var p2_navigation_mode := _argument_value("--p2-navigation-automation=")
	if not p2_navigation_mode.is_empty():
		var p2_navigation_automation := P2NavigationAutomation.new()
		add_child(p2_navigation_automation)
		p2_navigation_automation.call_deferred("run", self, p2_navigation_mode)
	var p3_defense_mode := _argument_value("--p3-defense-automation=")
	if not p3_defense_mode.is_empty():
		var p3_defense_automation := P3DefenseAutomation.new()
		add_child(p3_defense_automation)
		p3_defense_automation.call_deferred("run", self, p3_defense_mode)
	var p3b_core_mode := _argument_value("--p3b-core-defense-automation=")
	if not p3b_core_mode.is_empty():
		var p3b_core_automation := P3BCoreDefenseAutomation.new()
		add_child(p3b_core_automation)
		p3b_core_automation.call_deferred("run", self, p3b_core_mode)
	var p3c_mode := _argument_value("--p3c-player-defense-automation=")
	if not p3c_mode.is_empty():
		var p3c_automation := P3CPlayerDefenseAutomation.new()
		add_child(p3c_automation)
		p3c_automation.call_deferred("run", self, p3c_mode)
	var p3d_mode := _argument_value("--p3d-usability-automation=")
	if not p3d_mode.is_empty():
		var p3d_automation := P3DUsabilityAutomation.new()
		add_child(p3d_automation)
		p3d_automation.call_deferred("run", self, p3d_mode)
	var p3e_mode := _argument_value("--p3e-container-automation=")
	if not p3e_mode.is_empty():
		var p3e_automation := P3EContainerAutomation.new()
		add_child(p3e_automation)
		p3e_automation.call_deferred("run", self, p3e_mode)
	var p3f_mode := _argument_value("--p3f-presentation-automation=")
	if not p3f_mode.is_empty():
		var p3f_automation := P3FPresentationAutomation.new()
		add_child(p3f_automation)
		p3f_automation.call_deferred("run", self, p3f_mode)
	var p3g_mode := _argument_value("--p3g-furnace-usability-automation=")
	if not p3g_mode.is_empty():
		var p3g_automation := P3GFurnaceUsabilityAutomation.new()
		add_child(p3g_automation)
		p3g_automation.call_deferred("run", self, p3g_mode)
	var p3h_mode := _argument_value("--p3h-balance-controls-automation=")
	if not p3h_mode.is_empty():
		var p3h_automation := P3HBalanceAndControlsAutomation.new()
		add_child(p3h_automation)
		p3h_automation.call_deferred("run", self, p3h_mode)
	var p4_weapon_panel_mode := _argument_value("--p4-weapon-panel-automation=")
	if not p4_weapon_panel_mode.is_empty():
		var p4_weapon_panel_automation := P4WeaponPanelAutomation.new()
		add_child(p4_weapon_panel_automation)
		p4_weapon_panel_automation.call_deferred("run", self, p4_weapon_panel_mode)
	var p4_siege_units_mode := _argument_value("--p4-siege-units-automation=")
	if not p4_siege_units_mode.is_empty():
		var p4_siege_units_automation := P4SiegeUnitsAutomation.new()
		add_child(p4_siege_units_automation)
		p4_siege_units_automation.call_deferred("run", self, p4_siege_units_mode)
	var p4_enemy_units_mode := _argument_value("--p4-enemy-units-automation=")
	if not p4_enemy_units_mode.is_empty():
		var p4_enemy_units_automation := P4EnemyUnitsAutomation.new()
		add_child(p4_enemy_units_automation)
		p4_enemy_units_automation.call_deferred("run", self, p4_enemy_units_mode)
	var p4_assets_mode := _argument_value("--p4-assets-automation=")
	if not p4_assets_mode.is_empty():
		var p4_assets_automation := P4AssetsAutomation.new()
		add_child(p4_assets_automation)
		p4_assets_automation.call_deferred("run", self, p4_assets_mode)
	var p4_resources_mode := _argument_value("--p4-resources-automation=")
	if not p4_resources_mode.is_empty():
		var p4_resources_automation := P4ResourcesAutomation.new()
		add_child(p4_resources_automation)
		p4_resources_automation.call_deferred("run", self, p4_resources_mode)
	if OS.get_cmdline_user_args().has("--coaster-sandbox"):
		# Owner sandbox: premade coaster track + infinite stock (not a diagnostic).
		var coaster_sandbox := CoasterSandbox.new()
		add_child(coaster_sandbox)
		coaster_sandbox.call_deferred("run", self)
	var coaster_rails_mode := _argument_value("--coaster-rails-automation=")
	if not coaster_rails_mode.is_empty():
		var coaster_rails_automation := CoasterRailsAutomation.new()
		add_child(coaster_rails_automation)
		coaster_rails_automation.call_deferred("run", self, coaster_rails_mode)
	var coaster_car_mode := _argument_value("--coaster-car-automation=")
	if not coaster_car_mode.is_empty():
		var coaster_car_automation := CoasterCarAutomation.new()
		add_child(coaster_car_automation)
		coaster_car_automation.call_deferred("run", self, coaster_car_mode)


func _input(event: InputEvent) -> void:
	# GUI controls such as the Furnace recipe search can consume Escape before
	# _unhandled_input sees it. Recovery is intentionally handled at the earliest
	# input stage so one physical press always closes the top overlay.
	if not _is_escape_press(event):
		return
	if capture_action.is_empty() and state == AppState.MAIN_MENU \
		and not keybind_panel.visible and not settings_panel.visible and not display_confirm_panel.visible:
		return
	get_viewport().set_input_as_handled()
	if not capture_action.is_empty():
		capture_action = ""
		capture_forward = false
		keybind_message.text = "Key capture cancelled; no binding changed."
		return
	_handle_escape_recovery()


func _process(delta: float) -> void:
	_update_cursor_stack_visual()
	if state == AppState.CRAFTING and _crafting_station_type == "furnace" and session != null and session.workstations != null:
		var completed := session.workstations.advance(delta, false)
		if completed.is_empty():
			_refresh_furnace_live_status()
		else:
			_refresh_crafting_panel()
	elif state == AppState.CRAFTING and _crafting_station_type == "siege" and session != null and session.workstations != null:
		# P4a-2: ammo, cooldown and supply change while the panel is open (the
		# weapon fires or auto-reloads), so the weapon column refreshes live.
		_refresh_siege_panel_state()
	if not display_confirm_panel.visible:
		return
	_display_confirm_remaining = maxf(0.0, _display_confirm_remaining - delta)
	display_confirm_label.text = "Keep these display settings?\nReverting automatically in %d seconds." % ceili(_display_confirm_remaining)
	if _display_confirm_remaining <= 0.0:
		_rollback_display_preview("Display settings reverted automatically.")


func _resolve_data_root() -> String:
	var requested := _argument_value("--f0-data-root=")
	if not requested.is_empty():
		return requested.replace("\\", "/")
	return ProjectSettings.globalize_path("user://")


func _argument_value(prefix: String) -> String:
	if prefix.ends_with("-automation="):
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with(prefix):
				automation_active = true
				if saves != null:
					saves.random_world_seed = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)
	_build_main_menu(canvas)
	_build_loading(canvas)
	_build_pause(canvas)
	_build_keybinds(canvas)
	_build_settings(canvas)
	_build_inventory(canvas)
	_build_crafting(canvas)
	_build_hud(canvas)
	_build_display_confirmation(canvas)
	_build_cursor_stack(canvas)


func _build_cursor_stack(canvas: CanvasLayer) -> void:
	cursor_stack_panel = PanelContainer.new()
	cursor_stack_panel.custom_minimum_size = Vector2(74, 64)
	cursor_stack_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_stack_panel.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("132733e8"), Color("ffe08a"), 7, 6))
	canvas.add_child(cursor_stack_panel)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(62, 52)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_stack_panel.add_child(holder)
	cursor_stack_icon = TextureRect.new()
	cursor_stack_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cursor_stack_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_stack_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor_stack_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cursor_stack_icon)
	cursor_stack_count = Label.new()
	cursor_stack_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cursor_stack_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cursor_stack_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cursor_stack_count.add_theme_font_size_override("font_size", 16)
	cursor_stack_count.add_theme_constant_override("outline_size", 4)
	cursor_stack_count.add_theme_color_override("font_outline_color", Color("071016"))
	cursor_stack_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cursor_stack_count)
	cursor_stack_panel.hide()


func _build_main_menu(canvas: CanvasLayer) -> void:
	menu_panel = _full_panel(Color("17222c"))
	canvas.add_child(menu_panel)
	var menu := _centered_box(menu_panel, Vector2(700, 570))
	var title := _title("CRAFT AND DEFEND", 34)
	menu.add_child(title)
	var subtitle := _centered_label("P3B core and breach prototype · castle-building foundation")
	menu.add_child(subtitle)
	menu.add_child(_spacer(12))
	var slot_row := _settings_row("Save slot")
	slot_option = OptionButton.new()
	slot_option.custom_minimum_size = Vector2(260, 42)
	for available_slot in SaveCoordinator.SLOT_IDS:
		slot_option.add_item("Slot %s" % available_slot.to_upper())
		slot_option.set_item_metadata(slot_option.item_count - 1, available_slot)
	slot_option.item_selected.connect(_on_slot_selected)
	slot_row.add_child(slot_option)
	menu.add_child(slot_row)
	slot_status_label = _centered_label("")
	slot_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_status_label.add_theme_color_override("font_color", Color("9fd8e8"))
	menu.add_child(slot_status_label)
	start_button = _button("Start", _on_start_pressed)
	menu.add_child(start_button)
	continue_button = _button("Continue", _on_continue_pressed)
	menu.add_child(continue_button)
	menu.add_child(_button("Settings", _show_settings))
	menu.add_child(_button("Keybinds", _show_keybinds))
	menu.add_child(_button("Quit", _on_quit_pressed))
	var root_hint := _centered_label("Local saves: %s" % data_root)
	root_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_hint.custom_minimum_size = Vector2(620, 0)
	menu.add_child(root_hint)


func _build_loading(canvas: CanvasLayer) -> void:
	loading_panel = _full_panel(Color("17222c"))
	canvas.add_child(loading_panel)
	var loading_box := _centered_box(loading_panel, Vector2(660, 360))
	loading_box.add_child(_title("Loading finite world…", 26))
	status_label = _centered_label("Preparing terrain and collision")
	status_label.custom_minimum_size = Vector2(600, 0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loading_box.add_child(status_label)
	loading_back_button = _button("Back to Main Menu", _show_main_menu)
	loading_back_button.hide()
	loading_box.add_child(loading_back_button)
	loading_retry_button = _button("Retry Save", _retry_failed_save)
	loading_retry_button.hide()
	loading_box.add_child(loading_retry_button)
	loading_return_button = _button("Return to Paused Game", _return_from_save_error)
	loading_return_button.hide()
	loading_box.add_child(loading_return_button)


func _build_pause(canvas: CanvasLayer) -> void:
	pause_panel = _full_panel(Color(0.04, 0.06, 0.08, 0.92))
	canvas.add_child(pause_panel)
	# Two columns (owner 2026-09-20: the single column had grown off the
	# bottom of the screen): the game on the left, the drills on the right.
	var pause_box := _centered_box(pause_panel, Vector2(1000, 480))
	pause_box.add_child(_title("PAUSED", 30))
	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 40)
	pause_box.add_child(columns)
	var game_column := VBoxContainer.new()
	game_column.add_theme_constant_override("separation", 10)
	columns.add_child(game_column)
	game_column.add_child(_button("Resume", _resume_game))
	game_column.add_child(_button("Settings", _show_settings))
	game_column.add_child(_button("Keybinds", _show_keybinds))
	hero_armor_button = _button("Hero: Armour off", _toggle_hero_armor)
	game_column.add_child(hero_armor_button)
	track_auto_clear_button = _button("Track auto-clear: off", _toggle_track_auto_clear)
	game_column.add_child(track_auto_clear_button)
	game_column.add_child(_button("Save and Exit to Menu", _save_and_exit_to_menu))
	game_column.add_child(_button("Save and Quit", _save_and_quit))
	var drill_column := VBoxContainer.new()
	drill_column.add_theme_constant_override("separation", 10)
	columns.add_child(drill_column)
	drill_column.add_child(_title("DRILLS", 18))
	drill_column.add_child(_button("Start Defense Drill", _start_defense_drill, Vector2(520, 44)))
	drill_column.add_child(_button("Start Attack from the Enemy Base (far)", _start_far_attack, Vector2(520, 44)))
	drill_column.add_child(_button("Start Drill (NEAR): single raider", _start_core_defense_prototype, Vector2(520, 44)))
	drill_column.add_child(_button("Start Wave Drill (4 orcs + 1 brute + 1 troll, far spawn)", _start_wave_drill, Vector2(520, 44)))
	drill_column.add_child(_button("Start Siege Drill (6 orcs + 3 brutes + 3 trolls, farthest spawn)", _start_siege_drill, Vector2(520, 44)))


func _build_keybinds(canvas: CanvasLayer) -> void:
	keybind_panel = _full_panel(Color("0d1821"))
	canvas.add_child(keybind_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	keybind_panel.add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)
	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(980, 650)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := _title("KEYBINDS", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_button("Back", _close_keybinds, Vector2(150, 42)))
	var help := _centered_label("Physical-key ESDF defaults · click Change, then press one keyboard key or mouse button")
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(help)
	keybind_search = LineEdit.new()
	keybind_search.placeholder_text = "Find an action or assigned key…"
	keybind_search.clear_button_enabled = true
	keybind_search.text_changed.connect(_on_keybind_search_changed)
	layout.add_child(keybind_search)
	keybind_message = _centered_label("Escape always cancels capture and remains the recovery path. Conflicting assignments are rejected with an explanation.")
	keybind_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	keybind_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keybind_message.add_theme_color_override("font_color", Color("9fd8e8"))
	layout.add_child(keybind_message)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for group in BINDING_GROUPS:
		var group_title := Label.new()
		group_title.text = str(group.title)
		group_title.add_theme_font_size_override("font_size", 15)
		group_title.add_theme_color_override("font_color", Color("7fcde2"))
		list.add_child(group_title)
		for action in group.actions:
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101e28"), Color("2f4756"), 6, 8))
			list.add_child(card)
			var row := HBoxContainer.new()
			card.add_child(row)
			var action_label := Label.new()
			action_label.text = settings.get_action_label(action)
			action_label.custom_minimum_size = Vector2(270, 38)
			action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(action_label)
			var current_label := Label.new()
			current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			current_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			current_label.custom_minimum_size = Vector2(160, 38)
			binding_labels[action] = current_label
			row.add_child(current_label)
			var change_button := _button("Change", _capture_binding.bind(action), Vector2(130, 38))
			change_button.tooltip_text = "Rebind %s" % settings.get_action_label(action)
			row.add_child(change_button)
			var reset_button := _button("Reset", _reset_binding.bind(action), Vector2(110, 38))
			reset_button.tooltip_text = "Restore only %s to its ESDF default" % settings.get_action_label(action)
			binding_reset_buttons[action] = reset_button
			row.add_child(reset_button)
			binding_rows[action] = card
			if action == "move_forward":
				forward_binding_label = current_label
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_child(_button("Reset All Defaults", _reset_bindings, Vector2(240, 44)))
	layout.add_child(actions)
	_refresh_binding_labels()


func _build_settings(canvas: CanvasLayer) -> void:
	settings_panel = _full_panel(Color("17222c"))
	canvas.add_child(settings_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	settings_panel.add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)
	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(820, 620)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(layout)
	layout.add_child(_title("SETTINGS", 28))
	settings_scroll = ScrollContainer.new()
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.follow_focus = true
	layout.add_child(settings_scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(780, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(box)

	var input_title := _centered_label("INPUT AND AUDIO")
	input_title.add_theme_font_size_override("font_size", 18)
	box.add_child(input_title)
	var sensitivity_row := _settings_row("Mouse sensitivity")
	sensitivity_slider = HSlider.new()
	sensitivity_slider.min_value = SettingsStore.MIN_MOUSE_SENSITIVITY
	sensitivity_slider.max_value = SettingsStore.MAX_MOUSE_SENSITIVITY
	sensitivity_slider.step = 0.0001
	sensitivity_slider.custom_minimum_size = Vector2(280, 30)
	sensitivity_row.add_child(sensitivity_slider)
	sensitivity_value_label = Label.new()
	sensitivity_value_label.custom_minimum_size = Vector2(70, 30)
	sensitivity_row.add_child(sensitivity_value_label)
	box.add_child(sensitivity_row)

	var invert_row := _settings_row("Invert vertical look")
	invert_check = CheckButton.new()
	invert_check.text = "Enabled"
	invert_row.add_child(invert_check)
	box.add_child(invert_row)

	var volume_row := _settings_row("Master volume")
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.custom_minimum_size = Vector2(280, 30)
	volume_row.add_child(volume_slider)
	volume_value_label = Label.new()
	volume_value_label.custom_minimum_size = Vector2(70, 30)
	volume_row.add_child(volume_value_label)
	box.add_child(volume_row)
	box.add_child(_button("Save Input and Audio", _save_input_audio, Vector2(360, 42)))

	var display_title := _centered_label("DISPLAY")
	display_title.add_theme_font_size_override("font_size", 18)
	box.add_child(display_title)
	var mode_row := _settings_row("Window mode")
	window_mode_option = OptionButton.new()
	window_mode_option.add_item("Windowed")
	window_mode_option.add_item("Fullscreen")
	window_mode_option.custom_minimum_size = Vector2(350, 36)
	mode_row.add_child(window_mode_option)
	box.add_child(mode_row)
	windowed_resolution_row = _settings_row("Windowed resolution")
	resolution_option = OptionButton.new()
	for option in SettingsStore.RESOLUTION_OPTIONS:
		resolution_option.add_item("%d × %d" % [option.x, option.y])
	resolution_option.custom_minimum_size = Vector2(350, 36)
	windowed_resolution_row.add_child(resolution_option)
	box.add_child(windowed_resolution_row)
	fullscreen_resolution_row = _settings_row("Fullscreen resolution")
	fullscreen_resolution_value_label = Label.new()
	fullscreen_resolution_value_label.custom_minimum_size = Vector2(350, 36)
	fullscreen_resolution_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fullscreen_resolution_row.add_child(fullscreen_resolution_value_label)
	box.add_child(fullscreen_resolution_row)
	box.add_child(_button("Preview Display Changes", _preview_display_changes, Vector2(360, 42)))

	var graphics_title := _centered_label("GRAPHICS QUALITY")
	graphics_title.add_theme_font_size_override("font_size", 18)
	box.add_child(graphics_title)
	var msaa_row := _settings_row("3D edge smoothing")
	msaa_option = OptionButton.new()
	for label in ["Off", "2× MSAA", "4× MSAA (Recommended)", "8× MSAA"]:
		msaa_option.add_item(label)
	msaa_option.custom_minimum_size = Vector2(350, 36)
	msaa_option.tooltip_text = "Smooths moving block and silhouette edges; 4× is the default quality setting"
	msaa_row.add_child(msaa_option)
	box.add_child(msaa_row)
	var view_row := _settings_row("Terrain view distance")
	view_distance_option = OptionButton.new()
	for blocks in SettingsStore.VIEW_DISTANCE_OPTIONS:
		view_distance_option.add_item("%d blocks%s" % [blocks, " (Recommended)" if blocks == SettingsStore.DEFAULT_VIEW_DISTANCE else ""])
	view_distance_option.custom_minimum_size = Vector2(350, 36)
	view_distance_option.tooltip_text = "How far terrain streams in around you; higher values load more chunks and cost CPU while they build"
	view_row.add_child(view_distance_option)
	box.add_child(view_row)
	var vsync_row := _settings_row("Vertical synchronization")
	vsync_check = CheckButton.new()
	vsync_check.text = "Enabled"
	vsync_check.tooltip_text = "Matches frame presentation to the monitor to avoid visible tearing"
	vsync_row.add_child(vsync_check)
	box.add_child(vsync_row)
	var graphics_help := _centered_label("Physics interpolation and stabilized sunlight are always enabled. These options control edge smoothing and screen presentation.")
	graphics_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	graphics_help.add_theme_color_override("font_color", Color("9fd8e8"))
	box.add_child(graphics_help)
	box.add_child(_button("Apply Graphics Quality", _save_graphics, Vector2(360, 42)))

	world_settings_toggle = _button("WORLD SETTINGS  ▸", _toggle_world_settings, Vector2(360, 42))
	world_settings_toggle.tooltip_text = "Show or hide settings for the active save slot"
	box.add_child(world_settings_toggle)
	world_settings_content = VBoxContainer.new()
	world_settings_content.add_theme_constant_override("separation", 8)
	box.add_child(world_settings_content)
	var time_row := _settings_row("Time (24-hour HHMM)")
	world_time_input = LineEdit.new()
	world_time_input.placeholder_text = "0800"
	world_time_input.max_length = 5
	world_time_input.custom_minimum_size = Vector2(350, 38)
	world_time_input.tooltip_text = "Enter 0000 through 2359; 08:00 is also accepted"
	time_row.add_child(world_time_input)
	world_settings_content.add_child(time_row)
	var cycle_row := _settings_row("Day/Night cycle")
	world_cycle_check = CheckButton.new()
	world_cycle_check.text = "Enabled"
	world_cycle_check.tooltip_text = "When disabled, the current world time and lighting remain fixed"
	cycle_row.add_child(world_cycle_check)
	world_settings_content.add_child(cycle_row)
	var world_help := _centered_label("Time and cycle state belong to the active save slot. Rain controls will appear when weather exists.")
	world_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_help.add_theme_color_override("font_color", Color("9fd8e8"))
	world_settings_content.add_child(world_help)
	world_apply_button = _button("Apply World Settings", _apply_world_settings, Vector2(360, 42))
	world_settings_content.add_child(world_apply_button)
	world_settings_message = _centered_label("")
	world_settings_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_settings_message.custom_minimum_size = Vector2(650, 24)
	world_settings_content.add_child(world_settings_message)
	world_settings_content.hide()

	settings_message = _centered_label("")
	settings_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_message.custom_minimum_size = Vector2(650, 24)
	box.add_child(settings_message)
	layout.add_child(_button("Back", _close_settings, Vector2(360, 42)))
	sensitivity_slider.value_changed.connect(_on_sensitivity_value_changed)
	volume_slider.value_changed.connect(_on_volume_value_changed)
	window_mode_option.item_selected.connect(_on_window_mode_selected)


func _build_inventory(canvas: CanvasLayer) -> void:
	inventory_panel = _full_panel(Color(0.035, 0.06, 0.078, 0.98))
	canvas.add_child(inventory_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	inventory_panel.add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _title("INVENTORY", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Back to Game", _close_inventory, Vector2(190, 44)))
	var context := Label.new()
	context.text = "TAB CLOSES  ·  DRAG TO REPOSITION  ·  CLICK TWO SLOTS TO MOVE OR SWAP"
	context.add_theme_color_override("font_color", Color("85d5ea"))
	root.add_child(context)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	inventory_left_column = VBoxContainer.new()
	inventory_left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_left_column.size_flags_stretch_ratio = 1.65
	body.add_child(inventory_left_column)

	var carried_card := PanelContainer.new()
	carried_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carried_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	carried_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 14))
	inventory_left_column.add_child(carried_card)
	var carried_column := VBoxContainer.new()
	carried_card.add_child(carried_column)
	var carried_heading := Label.new()
	carried_heading.text = "CARRIED INVENTORY  ·  18 FIXED SLOTS"
	carried_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	carried_column.add_child(carried_heading)
	var carried_help := Label.new()
	carried_help.text = "Drag to reposition · filters change this view only · All shows empty drop targets"
	carried_help.add_theme_font_size_override("font_size", 13)
	carried_help.add_theme_color_override("font_color", Color("8fa5af"))
	carried_column.add_child(carried_help)
	var filter_row := HFlowContainer.new()
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_theme_constant_override("h_separation", 6)
	filter_row.add_theme_constant_override("v_separation", 6)
	carried_column.add_child(filter_row)
	for filter_definition in INVENTORY_FILTERS:
		var filter_id := str(filter_definition.id)
		var filter_button := _button(str(filter_definition.label), _set_inventory_filter.bind(filter_id), Vector2(76, 34))
		filter_button.toggle_mode = true
		filter_button.add_theme_font_size_override("font_size", 13)
		inventory_filter_buttons[filter_id] = filter_button
		filter_row.add_child(filter_button)
	var sort_button := _button("Sort Carried by Type", _sort_carried_inventory, Vector2(158, 34))
	sort_button.add_theme_font_size_override("font_size", 13)
	sort_button.tooltip_text = "Reorder only the 18 carried slots by category and item name; the hotbar is unchanged"
	filter_row.add_child(sort_button)
	inventory_carried_grid = GridContainer.new()
	inventory_carried_grid.columns = 6
	inventory_carried_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inventory_carried_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	inventory_carried_grid.add_theme_constant_override("h_separation", INVENTORY_TILE_GAP)
	inventory_carried_grid.add_theme_constant_override("v_separation", INVENTORY_TILE_GAP)
	carried_column.add_child(inventory_carried_grid)
	inventory_filter_empty_label = Label.new()
	inventory_filter_empty_label.text = "No carried items match this filter. Choose All to show every slot."
	inventory_filter_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inventory_filter_empty_label.add_theme_color_override("font_color", Color("8fa5af"))
	inventory_filter_empty_label.hide()
	carried_column.add_child(inventory_filter_empty_label)

	var hotbar_card := PanelContainer.new()
	hotbar_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hotbar_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("4b7180"), 8, 12))
	inventory_left_column.add_child(hotbar_card)
	var hotbar_column := VBoxContainer.new()
	hotbar_card.add_child(hotbar_column)
	var hotbar_heading := Label.new()
	hotbar_heading.text = "HOTBAR LOADOUT  ·  EQUIPPED KEYS 1–9"
	hotbar_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	hotbar_column.add_child(hotbar_heading)
	inventory_hotbar_grid = GridContainer.new()
	inventory_hotbar_grid.columns = F0Inventory.HOTBAR_COUNT
	inventory_hotbar_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inventory_hotbar_grid.add_theme_constant_override("h_separation", INVENTORY_TILE_GAP)
	hotbar_column.add_child(inventory_hotbar_grid)

	for index in range(F0Inventory.SLOT_COUNT):
		var slot_button := InventoryItemSlot.new()
		# Square tiles matching the crafting inventory; no horizontal stretch so a
		# wide card cannot flatten them into strips.
		slot_button.custom_minimum_size = INVENTORY_TILE_SIZE
		slot_button.pressed.connect(_select_inventory_slot.bind(index))
		slot_button.item_dropped.connect(_on_inventory_item_dropped)
		slot_button.stack_gesture.connect(_on_inventory_stack_gesture)
		slot_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_button.add_theme_font_size_override("font_size", 13)
		slot_button.clip_text = true
		slot_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slot_button.tooltip_text = "Hotbar key %d" % (index + 1) if index < F0Inventory.HOTBAR_COUNT else "Carried slot %d" % (index - F0Inventory.HOTBAR_COUNT + 1)
		inventory_slot_buttons.append(slot_button)
		if index < F0Inventory.HOTBAR_COUNT:
			inventory_hotbar_grid.add_child(slot_button)
		else:
			inventory_carried_grid.add_child(slot_button)

	inventory_armor_card = PanelContainer.new()
	inventory_armor_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_armor_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_armor_card.size_flags_stretch_ratio = 1.0
	inventory_armor_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("4b7180"), 8, 14))
	body.add_child(inventory_armor_card)
	var armor_column := VBoxContainer.new()
	inventory_armor_card.add_child(armor_column)
	var armor_heading := Label.new()
	armor_heading.text = "ARMOR LOADOUT"
	armor_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	armor_column.add_child(armor_heading)
	var armor_help := Label.new()
	armor_help.text = "Character equipment layout · gear interaction arrives with the combat slice"
	armor_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	armor_help.add_theme_font_size_override("font_size", 13)
	armor_help.add_theme_color_override("font_color", Color("8fa5af"))
	armor_column.add_child(armor_help)
	var armor_body := HBoxContainer.new()
	armor_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armor_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	armor_column.add_child(armor_body)
	inventory_silhouette = ArmorSilhouette.new()
	inventory_silhouette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_silhouette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	armor_body.add_child(inventory_silhouette)
	var equipment_column := VBoxContainer.new()
	equipment_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_column.alignment = BoxContainer.ALIGNMENT_CENTER
	armor_body.add_child(equipment_column)
	for equipment_name in ["Helmet", "Breastplate", "Gauntlets", "Leggings", "Boots", "Shield"]:
		var equipment_slot := Button.new()
		equipment_slot.text = "%s\nEmpty" % equipment_name
		equipment_slot.custom_minimum_size = Vector2(145, 54)
		equipment_slot.disabled = true
		equipment_slot.tooltip_text = "%s equipment slot; armor items are not implemented yet" % equipment_name
		inventory_armor_slot_buttons.append(equipment_slot)
		equipment_column.add_child(equipment_slot)

	inventory_contents_label = Label.new()
	inventory_contents_label.visible = false
	root.add_child(inventory_contents_label)
	# Owner playtest 2026-09-18: the message used to sit below the panels and
	# fell off the bottom of the window. It now replaces the header hint line.
	inventory_message = context
	inventory_message.add_theme_color_override("font_color", Color("ffd488"))


func _build_crafting(canvas: CanvasLayer) -> void:
	crafting_panel = _full_panel(Color(0.01, 0.018, 0.025, 0.88))
	canvas.add_child(crafting_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crafting_panel.add_child(center)
	var modal := PanelContainer.new()
	modal.custom_minimum_size = Vector2(1220, 680)
	modal.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("0d1a23"), Color("4e8294"), 12, 22))
	center.add_child(modal)
	var root := VBoxContainer.new()
	modal.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	crafting_title_label = _title("FIELD BUILD", 28)
	crafting_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	crafting_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(crafting_title_label)
	header.add_child(_button("Back to Game", _close_crafting, Vector2(180, 42)))
	crafting_context_label = Label.new()
	crafting_context_label.add_theme_color_override("font_color", Color("85d5ea"))
	root.add_child(crafting_context_label)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)

	var inventory_card := PanelContainer.new()
	inventory_card.custom_minimum_size.x = 250
	inventory_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 14))
	columns.add_child(inventory_card)
	var inventory_column := VBoxContainer.new()
	inventory_card.add_child(inventory_column)
	var inventory_heading := Label.new()
	inventory_heading.text = "INVENTORY"
	inventory_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	inventory_column.add_child(inventory_heading)
	crafting_inventory_help = Label.new()
	crafting_inventory_help.text = "Drag into the grid, or select then choose a cell"
	crafting_inventory_help.add_theme_font_size_override("font_size", 13)
	crafting_inventory_help.add_theme_color_override("font_color", Color("8fa5af"))
	inventory_column.add_child(crafting_inventory_help)
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_scroll.follow_focus = true
	inventory_column.add_child(inventory_scroll)
	crafting_inventory_grid = GridContainer.new()
	crafting_inventory_grid.columns = 3
	crafting_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.add_child(crafting_inventory_grid)
	for index in range(F0Inventory.SLOT_COUNT):
		var inventory_slot := CraftingItemSlot.new()
		inventory_slot.custom_minimum_size = Vector2(68, 54)
		inventory_slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
		inventory_slot.tooltip_text = "Drag to the crafting grid, or select and then choose a grid cell"
		inventory_slot.pressed.connect(_select_crafting_inventory_slot.bind(index))
		inventory_slot.item_dropped.connect(_on_crafting_item_dropped)
		inventory_slot.stack_gesture.connect(_on_crafting_stack_gesture)
		inventory_slot.configure_target("inventory", index)
		crafting_inventory_slots.append(inventory_slot)
		crafting_inventory_grid.add_child(inventory_slot)

	var grid_card := PanelContainer.new()
	grid_card.custom_minimum_size.x = 330
	grid_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 14))
	columns.add_child(grid_card)
	crafting_grid_card = grid_card
	var grid_column := VBoxContainer.new()
	grid_card.add_child(grid_column)
	crafting_grid_column = grid_column
	var grid_heading := Label.new()
	grid_heading.text = "CRAFTING GRID"
	grid_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	grid_column.add_child(grid_heading)
	crafting_grid_help = Label.new()
	crafting_grid_help.text = "Staged pattern — manual discovery works without the recipe book"
	crafting_grid_help.add_theme_font_size_override("font_size", 12)
	crafting_grid_help.add_theme_color_override("font_color", Color("8fa5af"))
	crafting_grid_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crafting_grid_help.max_lines_visible = 2
	crafting_grid_help.mouse_filter = Control.MOUSE_FILTER_STOP
	grid_column.add_child(crafting_grid_help)
	crafting_grid = GridContainer.new()
	crafting_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crafting_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_column.add_child(crafting_grid)
	furnace_controls = VBoxContainer.new()
	furnace_controls.add_theme_constant_override("separation", 4)
	grid_column.add_child(furnace_controls)
	# Round 3: the middle column must fit 720 canvas units with the message
	# visible, so the auto-load help lives in tooltips and labels cap at two lines.
	furnace_auto_load_label = Label.new()
	furnace_auto_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	furnace_auto_load_label.add_theme_font_size_override("font_size", 14)
	furnace_auto_load_label.add_theme_color_override("font_color", Color("9fd8e8"))
	furnace_auto_load_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	furnace_auto_load_label.max_lines_visible = 2
	furnace_auto_load_label.mouse_filter = Control.MOUSE_FILTER_STOP
	furnace_auto_load_label.tooltip_text = "Auto-load target / limit. One Coal funds three items; the burning Coal stays in Fuel until its last item finishes."
	furnace_controls.add_child(furnace_auto_load_label)
	furnace_auto_load_slider = HSlider.new()
	furnace_auto_load_slider.min_value = 0.0
	furnace_auto_load_slider.max_value = 64.0
	furnace_auto_load_slider.step = 1.0
	furnace_auto_load_slider.tooltip_text = "Set how many batches to load. Auto-loads input plus the counted Coal needed; limited ingredients load as far as available. Drag and Shift+Click remain available."
	furnace_auto_load_slider.value_changed.connect(_on_furnace_auto_load_changed)
	furnace_controls.add_child(furnace_auto_load_slider)
	furnace_progress_bar = ProgressBar.new()
	furnace_progress_bar.min_value = 0.0
	furnace_progress_bar.max_value = 100.0
	furnace_progress_bar.show_percentage = false
	furnace_progress_bar.custom_minimum_size.y = 16
	furnace_controls.add_child(furnace_progress_bar)
	furnace_progress_label = Label.new()
	furnace_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	furnace_progress_label.add_theme_font_size_override("font_size", 12)
	furnace_progress_label.add_theme_color_override("font_color", Color("ffd488"))
	furnace_progress_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	furnace_controls.add_child(furnace_progress_label)
	crafting_output_label = Label.new()
	crafting_output_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crafting_output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crafting_output_label.max_lines_visible = 2
	crafting_output_label.custom_minimum_size = Vector2(330, 44)
	crafting_output_label.add_theme_font_size_override("font_size", 14)
	crafting_output_label.add_theme_color_override("font_color", Color("c9f4ff"))
	grid_column.add_child(crafting_output_label)
	craft_selected_button = _button("Craft", _craft_selected_recipe, Vector2(330, 40))
	craft_selected_button.tooltip_text = "Click to craft one batch. Hold Shift while clicking to craft exactly five batches atomically."
	grid_column.add_child(craft_selected_button)
	crafting_clear_button = _button("Clear Grid", _clear_crafting_grid, Vector2(330, 36))
	grid_column.add_child(crafting_clear_button)
	crafting_message = Label.new()
	crafting_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crafting_message.max_lines_visible = 2
	crafting_message.custom_minimum_size = Vector2(330, 40)
	crafting_message.add_theme_font_size_override("font_size", 13)
	crafting_message.add_theme_color_override("font_color", Color("ffd488"))
	crafting_message.mouse_filter = Control.MOUSE_FILTER_STOP
	grid_column.add_child(crafting_message)

	# P4a-2 cards: weapon column (middle) + munition legend (right) for siege
	# weapons, chest column (middle) for Chests. Hidden unless that station
	# type is open; the message label moves into the visible middle column.
	siege_card = PanelContainer.new()
	siege_card.custom_minimum_size.x = 330
	siege_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 14))
	siege_card.hide()
	columns.add_child(siege_card)
	siege_column = VBoxContainer.new()
	siege_card.add_child(siege_column)
	siege_panel = SiegeWeaponPanel.new()
	siege_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	siege_panel.unload_requested.connect(_on_siege_unload_pressed)
	siege_panel.stance_requested.connect(_on_siege_stance_requested)
	siege_panel.target_filter_requested.connect(_on_siege_target_filter_requested)
	siege_panel.ammo_slot.pressed.connect(_on_siege_ammo_slot_pressed)
	siege_panel.ammo_slot.item_dropped.connect(_on_crafting_item_dropped)
	siege_panel.ammo_slot.stack_gesture.connect(_on_crafting_stack_gesture)
	siege_column.add_child(siege_panel)
	chest_card = PanelContainer.new()
	chest_card.custom_minimum_size.x = 330
	chest_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chest_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 14))
	chest_card.hide()
	columns.add_child(chest_card)
	chest_column = VBoxContainer.new()
	chest_card.add_child(chest_column)
	chest_panel = ChestPanel.new()
	chest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chest_column.add_child(chest_panel)

	var recipe_card := PanelContainer.new()
	recipe_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 14))
	recipe_card.gui_input.connect(_on_crafting_recipe_book_gui_input.bind(recipe_card))
	columns.add_child(recipe_card)
	crafting_recipe_card = recipe_card
	var recipe_column := VBoxContainer.new()
	recipe_card.add_child(recipe_column)
	var recipe_heading := Label.new()
	recipe_heading.text = "RECIPE BOOK"
	recipe_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	recipe_column.add_child(recipe_heading)
	crafting_recipe_search = LineEdit.new()
	crafting_recipe_search.placeholder_text = "Search recipes or ingredients…"
	crafting_recipe_search.clear_button_enabled = true
	crafting_recipe_search.tooltip_text = "Press Enter to load the first matching recipe when ingredients are available"
	crafting_recipe_search.text_changed.connect(_on_crafting_recipe_search_changed)
	crafting_recipe_search.text_submitted.connect(_on_crafting_recipe_search_submitted)
	recipe_column.add_child(crafting_recipe_search)
	crafting_recipe_list = GridContainer.new()
	crafting_recipe_list.columns = 4
	crafting_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crafting_recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	crafting_recipe_list.add_theme_constant_override("h_separation", 6)
	crafting_recipe_list.add_theme_constant_override("v_separation", 6)
	recipe_column.add_child(crafting_recipe_list)
	var page_row := HBoxContainer.new()
	page_row.alignment = BoxContainer.ALIGNMENT_CENTER
	page_row.add_theme_constant_override("separation", 10)
	recipe_column.add_child(page_row)
	crafting_recipe_previous = _button("‹ Previous", _change_recipe_page.bind(-1), Vector2(118, 36))
	page_row.add_child(crafting_recipe_previous)
	crafting_recipe_page_label = _centered_label("Page 1 / 1")
	crafting_recipe_page_label.custom_minimum_size = Vector2(100, 36)
	page_row.add_child(crafting_recipe_page_label)
	crafting_recipe_next = _button("Next ›", _change_recipe_page.bind(1), Vector2(118, 36))
	page_row.add_child(crafting_recipe_next)
	siege_legend_card = PanelContainer.new()
	siege_legend_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	siege_legend_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 14))
	siege_legend_card.hide()
	columns.add_child(siege_legend_card)
	var legend_column := VBoxContainer.new()
	legend_column.add_theme_constant_override("separation", 8)
	siege_legend_card.add_child(legend_column)
	var legend_heading := Label.new()
	legend_heading.text = "MUNITIONS"
	legend_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	legend_column.add_child(legend_heading)
	var legend_help := Label.new()
	legend_help.text = "What this weapon can fire. One munition type is loaded at a time; unload to switch."
	legend_help.add_theme_font_size_override("font_size", 12)
	legend_help.add_theme_color_override("font_color", Color("8fa5af"))
	legend_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_help.max_lines_visible = 2
	legend_column.add_child(legend_help)
	siege_legend_list = VBoxContainer.new()
	siege_legend_list.add_theme_constant_override("separation", 8)
	legend_column.add_child(siege_legend_list)


## One wrapping HUD text line in the top-left column.
func _hud_text_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.05, 0.9))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_text_column.add_child(label)
	return label


## The HUD text column is as wide as the space left of the minimap.
func _layout_hud_text() -> void:
	if hud_text_column == null:
		return
	var width := get_viewport().get_visible_rect().size.x - hud_text_column.position.x - MinimapOverlay.MINI_SIZE - MinimapOverlay.MARGIN * 2.0
	hud_text_column.custom_minimum_size = Vector2(maxf(320.0, width), 0.0)
	hud_text_column.size = Vector2(maxf(320.0, width), 0.0)


func _build_hud(canvas: CanvasLayer) -> void:
	hud_layer = Control.new()
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_layer)
	minimap = MinimapOverlay.new()
	minimap.name = "Minimap"
	minimap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(minimap)
	# Owner 2026-09-19: the text block hugs the top-left and wraps inside the
	# width left of the minimap (top-right corner), so the two never meet.
	hud_text_column = VBoxContainer.new()
	hud_text_column.name = "HudText"
	hud_text_column.position = Vector2(20, 18)
	hud_text_column.add_theme_constant_override("separation", 4)
	hud_text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_text_column)
	hud_label = _hud_text_label(18, Color.WHITE)
	navigation_label = _hud_text_label(15, Color("9fd8e8"))
	defense_label = _hud_text_label(15, Color("ffd166"))
	feedback_label = _hud_text_label(16, Color("ffe08a"))
	_layout_hud_text()
	get_viewport().size_changed.connect(_layout_hud_text)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-7, -16)
	hud_layer.add_child(crosshair)
	# Owner playtest 2026-09-18 (ultrawide): the hotbar must stay fully visible
	# with a small gap below it on every aspect ratio. It is anchored to the
	# bottom-centre with GAMEPLAY_HOTBAR_BOTTOM_MARGIN below the square tiles
	# and is exactly as wide as its nine tiles, so it never grows downward.
	gameplay_hotbar = HBoxContainer.new()
	gameplay_hotbar.name = "HeldHotbar"
	var hotbar_width := GameplayHotbarSlot.TILE_SIZE.x * F0Inventory.HOTBAR_COUNT + GAMEPLAY_HOTBAR_GAP * (F0Inventory.HOTBAR_COUNT - 1)
	gameplay_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	gameplay_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gameplay_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	gameplay_hotbar.offset_left = -hotbar_width / 2.0
	gameplay_hotbar.offset_right = hotbar_width / 2.0
	gameplay_hotbar.offset_top = -(GameplayHotbarSlot.TILE_SIZE.y + GAMEPLAY_HOTBAR_BOTTOM_MARGIN)
	gameplay_hotbar.offset_bottom = -GAMEPLAY_HOTBAR_BOTTOM_MARGIN
	gameplay_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	gameplay_hotbar.add_theme_constant_override("separation", GAMEPLAY_HOTBAR_GAP)
	gameplay_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(gameplay_hotbar)
	for index in range(F0Inventory.HOTBAR_COUNT):
		var slot := GameplayHotbarSlot.new()
		gameplay_hotbar_slots.append(slot)
		gameplay_hotbar.add_child(slot)
		slot.set_slot(index, "", "Empty", 0, index == 0)


func _build_display_confirmation(canvas: CanvasLayer) -> void:
	display_confirm_panel = _full_panel(Color(0.02, 0.03, 0.04, 0.96))
	canvas.add_child(display_confirm_panel)
	var box := _centered_box(display_confirm_panel, Vector2(620, 360))
	box.add_child(_title("CONFIRM DISPLAY", 28))
	display_confirm_label = _centered_label("")
	display_confirm_label.add_theme_font_size_override("font_size", 20)
	box.add_child(display_confirm_label)
	box.add_child(_button("Keep Changes", _confirm_display_preview))
	box.add_child(_button("Revert Now", _rollback_display_preview))


func _show_main_menu() -> void:
	state = AppState.MAIN_MENU
	get_tree().paused = false
	_hide_all_panels()
	menu_panel.show()
	_refresh_slot_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_slot_selected(index: int) -> void:
	if slot_option == null or index < 0 or index >= slot_option.item_count:
		return
	saves.select_slot(str(slot_option.get_item_metadata(index)))
	_refresh_slot_ui()


func _refresh_slot_ui() -> void:
	if slot_option == null:
		return
	for index in range(slot_option.item_count):
		if str(slot_option.get_item_metadata(index)) == saves.slot_id:
			slot_option.select(index)
			break
	var slot_status := saves.checkpoint_status()
	var label := "Slot %s" % saves.slot_id.to_upper()
	start_button.text = "Start New — %s" % label
	continue_button.text = "Continue — %s" % label
	continue_button.disabled = not slot_status.get("ok", false)
	if slot_status.get("ok", false):
		slot_status_label.text = "%s · checkpoint %d ready" % [label, int(slot_status.get("revision", 0))]
		continue_button.tooltip_text = "Resume the last complete checkpoint in %s" % label
	else:
		var reason := str(slot_status.get("reason", "NO_VALID_CHECKPOINT"))
		slot_status_label.text = "%s · %s" % [label, _save_reason_text(reason)]
		continue_button.tooltip_text = _save_reason_text(reason)
	if saves.migration_report.get("migrated", false) and saves.slot_id == SaveCoordinator.DEFAULT_SLOT:
		slot_status_label.text += " · previous default save copied safely"


func _on_start_pressed() -> void:
	_open_session(false)


func _on_continue_pressed() -> void:
	_open_session(true)


func _open_session(continue_existing: bool) -> void:
	if state != AppState.MAIN_MENU:
		return
	state = AppState.LOADING
	menu_panel.hide()
	loading_panel.show()
	loading_back_button.hide()
	loading_retry_button.hide()
	loading_return_button.hide()
	status_label.text = "Opening checkpoint…" if continue_existing else "Creating working session…"
	var open_result := saves.open_session(continue_existing)
	if not open_result.get("ok", false):
		_show_error(open_result.get("reason", "OPEN_FAILED"))
		return
	session = GameSession.new()
	session.settings_view_distance = settings.view_distance
	session.hero_armored = settings.hero_armored
	session.track_auto_clear = settings.track_auto_clear
	_refresh_hero_armor_button()
	_refresh_track_auto_clear_button()
	session.name = "GameSession"
	add_child(session)
	session.ready_for_play.connect(_on_session_ready)
	session.status_changed.connect(_set_status)
	session.hud_changed.connect(_set_hud)
	session.navigation_changed.connect(_set_navigation)
	session.defense_changed.connect(_set_defense)
	session.feedback_changed.connect(_set_feedback)
	session.inventory_changed.connect(_on_session_inventory_changed)
	session.workstation_requested.connect(_show_workstation)
	var initialize_result := session.initialize(open_result)
	if not initialize_result.get("ok", false):
		_show_error(initialize_result.get("reason", "SESSION_INITIALIZE_FAILED"))
		return
	session.apply_input_settings(settings)


func _on_session_ready() -> void:
	if minimap != null and session != null and session.world != null and session.world.terrain != null and session.world.terrain.generator is P1TerrainGenerator:
		minimap.configure(session.world.terrain.generator, session.player, session.workstations)
	state = AppState.PLAYING
	loading_panel.hide()
	hud_layer.show()
	feedback_label.text = ""
	_refresh_gameplay_hotbar(session.inventory_snapshot())


func _pause_game() -> void:
	if state != AppState.PLAYING:
		return
	state = AppState.PAUSED
	session.pause_game(true)
	get_tree().paused = true
	hud_layer.hide()
	pause_panel.show()


func _resume_game() -> void:
	if state != AppState.PAUSED:
		return
	pause_panel.hide()
	hud_layer.show()
	get_tree().paused = false
	session.pause_game(false)
	state = AppState.PLAYING


## Pause menu: the hero wears plate (persisted in settings.cfg as [hero] armored).
func _toggle_hero_armor() -> void:
	var result := settings.set_hero_armored(not settings.hero_armored)
	if not result.get("ok", false):
		_set_status("Hero armour could not be saved: %s" % str(result.get("reason", "UNKNOWN")))
	_refresh_hero_armor_button()
	if session != null:
		session.set_hero_armored(settings.hero_armored)


func _refresh_hero_armor_button() -> void:
	if hero_armor_button != null and settings != null:
		hero_armor_button.text = "Hero: Armour %s" % ("on" if settings.hero_armored else "off")


## Pause menu: track tools clear natural terrain in their way (persisted in
## settings.cfg as [track] auto_clear; docs/COASTER_RAILS.md).
func _toggle_track_auto_clear() -> void:
	var result := settings.set_track_auto_clear(not settings.track_auto_clear)
	if not result.get("ok", false):
		_set_status("Track auto-clear could not be saved: %s" % str(result.get("reason", "UNKNOWN")))
	_refresh_track_auto_clear_button()
	if session != null:
		session.set_track_auto_clear(settings.track_auto_clear)


func _refresh_track_auto_clear_button() -> void:
	if track_auto_clear_button != null and settings != null:
		track_auto_clear_button.text = "Track auto-clear: %s" % ("on" if settings.track_auto_clear else "off")


func _start_defense_drill() -> void:
	if state != AppState.PAUSED or session == null:
		return
	var result := session.start_defense_drill()
	if result.get("ok", false):
		_resume_game()


func _start_core_defense_prototype() -> void:
	if state != AppState.PAUSED or session == null:
		return
	var result := session.start_core_defense_prototype()
	if result.get("ok", false):
		_resume_game()


## P4E: the real thing — a wave marches from the enemy base across the map.
func _start_far_attack() -> void:
	if state != AppState.PAUSED or session == null:
		return
	var result := session.start_core_defense_prototype({"raiders": 8, "brutes": 2, "trolls": 2, "from_enemy_base": true})
	if result.get("ok", false):
		_resume_game()


## P4D wave drill: the core-defense arena with a bigger, farther wave.
func _start_wave_drill() -> void:
	if state != AppState.PAUSED or session == null:
		return
	var result := session.start_core_defense_prototype({"raiders": 6, "brutes": 1, "trolls": 1, "spawn_distance": 22})
	if result.get("ok", false):
		_resume_game()


func _start_siege_drill() -> void:
	if state != AppState.PAUSED or session == null:
		return
	var result := session.start_core_defense_prototype({"raiders": 12, "brutes": 3, "trolls": 3, "spawn_distance": 28})
	if result.get("ok", false):
		_resume_game()


func _show_inventory() -> void:
	if state != AppState.PLAYING or session == null:
		return
	_inventory_move_source = -1
	_inventory_filter = "all"
	state = AppState.INVENTORY
	session.pause_game(true)
	get_tree().paused = true
	hud_layer.hide()
	_refresh_inventory_panel()
	inventory_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_workstation(instance_id: String, station_type: String) -> void:
	# The session may pass the entity id (catapult, chest); resolve the real
	# station type from the service so siege weapons and Chests open their
	# own panels instead of falling back to hand crafting.
	var resolved := station_type
	if resolved not in CRAFTING_STATION_TYPES and session != null and session.workstations != null:
		var service_type: String = session.workstations.station_type(instance_id)
		if service_type in CRAFTING_STATION_TYPES:
			resolved = service_type
	_show_crafting(instance_id, resolved)


func _show_crafting(station_id: String = "", station_type: String = "hand") -> void:
	if state != AppState.PLAYING or session == null:
		return
	_crafting_station_id = station_id
	_crafting_station_type = station_type if station_type in CRAFTING_STATION_TYPES else "hand"
	_selected_recipe_id = ""
	_craft_grid_items.clear()
	_craft_grid_ghosts.clear()
	_crafting_selected_inventory_item = ""
	_crafting_recipe_page = 0
	crafting_recipe_search.clear()
	state = AppState.CRAFTING
	session.pause_game(true)
	get_tree().paused = true
	hud_layer.hide()
	crafting_message.text = ""
	_refresh_crafting_panel()
	crafting_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_inventory() -> void:
	if state != AppState.INVENTORY:
		return
	if not _return_cursor_before_close(inventory_message):
		return
	inventory_panel.hide()
	hud_layer.show()
	get_tree().paused = false
	session.pause_game(false)
	state = AppState.PLAYING
	_inventory_move_source = -1


func _close_crafting() -> void:
	if state != AppState.CRAFTING:
		return
	if not _return_cursor_before_close(crafting_message):
		return
	crafting_panel.hide()
	hud_layer.show()
	get_tree().paused = false
	session.pause_game(false)
	state = AppState.PLAYING
	_crafting_station_id = ""
	_crafting_station_type = "hand"
	_selected_recipe_id = ""
	_craft_grid_items.clear()
	_crafting_selected_inventory_item = ""


func _on_session_inventory_changed(snapshot: Dictionary) -> void:
	_refresh_gameplay_hotbar(snapshot)
	if inventory_panel != null and inventory_panel.visible:
		_refresh_inventory_panel()
	if crafting_panel != null and crafting_panel.visible:
		_refresh_crafting_panel()


func _refresh_gameplay_hotbar(snapshot: Dictionary = {}) -> void:
	if session == null or gameplay_hotbar_slots.is_empty():
		return
	var current := snapshot if not snapshot.is_empty() else session.inventory_snapshot()
	var slots: Array = current.get("slots", [])
	var selected_index := int(current.get("selected_hotbar", 0))
	for index in range(gameplay_hotbar_slots.size()):
		var slot: Dictionary = slots[index] if index < slots.size() else {"item_id": "", "count": 0}
		var item_id := str(slot.get("item_id", ""))
		var display_name := "Empty" if item_id.is_empty() else session.registry.display_name(item_id)
		gameplay_hotbar_slots[index].set_slot(index, item_id, display_name, int(slot.get("count", 0)), index == selected_index)


func _select_inventory_slot(index: int) -> void:
	if session == null:
		return
	if not str(session.inventory.cursor_stack.get("item_id", "")).is_empty():
		var deposited := session.inventory.cursor_deposit_slot(index, false)
		inventory_message.text = "Placed the held stack." if deposited.get("ok", false) else _stack_reason_text(str(deposited.get("reason", "MOVE_FAILED")))
		_refresh_inventory_panel()
		return
	var slot: Dictionary = session.inventory.slots[index]
	if _inventory_move_source < 0:
		if index < F0Inventory.HOTBAR_COUNT:
			session.select_hotbar(index)
		if str(slot.get("item_id", "")).is_empty():
			inventory_message.text = "Slot %d is empty." % (index + 1)
		else:
			_inventory_move_source = index
			inventory_message.text = "%s selected. Choose another slot to move or swap it." % session.registry.display_name(str(slot.item_id))
	else:
		var source := _inventory_move_source
		_inventory_move_source = -1
		var result := session.inventory.swap_slots(source, index)
		if index < F0Inventory.HOTBAR_COUNT:
			session.select_hotbar(index)
		inventory_message.text = "Slots %d and %d swapped." % [source + 1, index + 1] if result.get("ok", false) else "Move failed: %s" % result.get("reason", "UNKNOWN")
	_refresh_inventory_panel()


func _on_inventory_item_dropped(source_index: int, target_index: int) -> void:
	if session == null:
		return
	if not str(session.inventory.cursor_stack.get("item_id", "")).is_empty():
		inventory_message.text = "Place the held stack before dragging another item."
		return
	_inventory_move_source = -1
	var result := session.inventory.swap_slots(source_index, target_index)
	if result.get("ok", false):
		inventory_message.text = "Moved slot %d to slot %d." % [source_index + 1, target_index + 1] if result.get("reason") != "UNCHANGED" else "That item is already in this slot."
	else:
		inventory_message.text = "Move failed: %s" % result.get("reason", "UNKNOWN")
	_refresh_inventory_panel()


func _on_inventory_stack_gesture(_source_kind: String, source_index: int, mouse_button: int, double_click: bool, dragging: bool, shift_pressed: bool) -> void:
	if session == null or state != AppState.INVENTORY:
		return
	if shift_pressed and mouse_button == MOUSE_BUTTON_LEFT and not dragging and str(session.inventory.cursor_stack.get("item_id", "")).is_empty():
		var moved := session.inventory.quick_move_between_sections(source_index)
		inventory_message.text = "Moved %d item%s between Carried Inventory and Hotbar." % [int(moved.get("count", 0)), "s" if int(moved.get("count", 0)) != 1 else ""] if moved.get("ok", false) else _stack_reason_text(str(moved.get("reason", "MOVE_FAILED")))
		_refresh_inventory_panel()
		return
	_handle_inventory_cursor_gesture(source_index, mouse_button, double_click, dragging, inventory_message)


func _handle_inventory_cursor_gesture(source_index: int, mouse_button: int, double_click: bool, dragging: bool, message_label: Label) -> void:
	if source_index < 0 or source_index >= session.inventory.slots.size():
		return
	var cursor_has_item := not str(session.inventory.cursor_stack.get("item_id", "")).is_empty()
	if dragging:
		if not cursor_has_item or _right_drag_visited.has(source_index):
			return
		_right_drag_visited[source_index] = true
		var spread := session.inventory.cursor_deposit_slot(source_index, true)
		if spread.get("ok", false):
			message_label.text = "Placed one item in slot %d." % (source_index + 1)
		return
	var result: Dictionary
	if cursor_has_item:
		result = session.inventory.cursor_deposit_slot(source_index, mouse_button == MOUSE_BUTTON_RIGHT)
		message_label.text = "Placed %s." % ("one item" if mouse_button == MOUSE_BUTTON_RIGHT else "the held stack") if result.get("ok", false) else _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	else:
		result = session.inventory.cursor_pick_slot(source_index, mouse_button == MOUSE_BUTTON_RIGHT and not double_click)
		if result.get("ok", false):
			message_label.text = "Holding %s ×%d — left-click deposits all; right-click deposits one; right-drag spreads one per slot." % [session.registry.display_name(str(result.get("item_id", ""))), int(result.get("count", 0))]
		else:
			message_label.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_right_drag_visited.clear()
	_refresh_inventory_panel()


func _return_cursor_before_close(message_label: Label) -> bool:
	if session == null or str(session.inventory.cursor_stack.get("item_id", "")).is_empty():
		return true
	var returned := session.inventory.return_cursor_to_inventory()
	if returned.get("ok", false):
		return true
	message_label.text = "Place the held stack before closing; inventory has no room to return it."
	return false


func _update_cursor_stack_visual() -> void:
	if cursor_stack_panel == null or session == null or state not in [AppState.INVENTORY, AppState.CRAFTING]:
		if cursor_stack_panel != null:
			cursor_stack_panel.hide()
		return
	var stack: Dictionary = session.inventory.cursor_stack
	var item_id := str(stack.get("item_id", ""))
	if item_id.is_empty() or int(stack.get("count", 0)) <= 0:
		cursor_stack_panel.hide()
		return
	cursor_stack_icon.texture = ItemIconCatalog.texture_for(item_id)
	cursor_stack_count.text = "×%d" % int(stack.get("count", 0))
	cursor_stack_panel.position = get_viewport().get_mouse_position() + Vector2(18, 18)
	cursor_stack_panel.show()


func _stack_reason_text(reason: String) -> String:
	match reason:
		"CURSOR_EMPTY", "EMPTY_SLOT":
			return "That slot is empty."
		"CURSOR_OCCUPIED":
			return "Place the held stack first."
		"STACK_FULL":
			return "That stack is full."
		"SLOT_OCCUPIED":
			return "That slot contains a different item."
		"INVENTORY_FULL":
			return "Inventory has no room."
		"INVALID_FURNACE_INPUT":
			return "That item does not belong in this Furnace slot."
		"OUTPUT_TAKE_ONLY":
			return "The Output slot only releases finished items."
		"WRONG_AMMUNITION":
			return "That is not ammunition this weapon can fire."
		"AMMO_TYPE_LOADED":
			return "Unload the loaded munition before switching to another type."
		"WEAPON_FULL":
			return "The weapon is fully loaded."
		"WEAPON_EMPTY":
			return "The weapon is empty — nothing to unload."
		"NO_RESOURCE":
			return "None of that item is left to move."
		"CONTAINER_FULL":
			return "The chest has no room for that."
		"NOT_CONTAINER", "NOT_SIEGE", "NO_ENTITY":
			return "That station is no longer available."
		_:
			return reason.replace("_", " ").capitalize()


func _set_inventory_filter(filter_id: String) -> void:
	if not INVENTORY_FILTERS.any(func(definition: Dictionary) -> bool: return str(definition.id) == filter_id):
		return
	_inventory_filter = filter_id
	_inventory_move_source = -1
	inventory_message.text = "Showing all carried slots." if filter_id == "all" else "Showing carried %s only. Choose All to expose empty drop targets." % filter_id
	_refresh_inventory_panel()


func _sort_carried_inventory() -> void:
	if session == null:
		return
	if not str(session.inventory.cursor_stack.get("item_id", "")).is_empty():
		inventory_message.text = "Place the held stack before sorting."
		return
	_inventory_move_source = -1
	var result := session.inventory.sort_carried_by_type()
	inventory_message.text = "Carried inventory sorted by type; hotbar unchanged." if result.get("reason") == "OK" else "Carried inventory is already sorted."
	_refresh_inventory_panel()


func _refresh_inventory_panel() -> void:
	if session == null:
		return
	var snapshot := session.inventory_snapshot()
	var slots: Array = snapshot.get("slots", [])
	for index in range(inventory_slot_buttons.size()):
		var slot: Dictionary = slots[index] if index < slots.size() else {"item_id": "", "count": 0}
		var item_id := str(slot.get("item_id", ""))
		# Captions carry only the item name; hotbar tiles show their key in the
		# top-left corner and carried tiles show no index (slot numbers live in
		# the tooltip only).
		var slot_label := "%d" % (index + 1) if index < F0Inventory.HOTBAR_COUNT else ""
		var marker := "↔" if index == _inventory_move_source else ("▶" if index == int(snapshot.get("selected_hotbar", 0)) and index < F0Inventory.HOTBAR_COUNT else "")
		var display_name := "Empty" if item_id.is_empty() else session.registry.display_name(item_id)
		var item_text := "Empty" if item_id.is_empty() else "%s ×%d" % [display_name, int(slot.get("count", 0))]
		inventory_slot_buttons[index].tooltip_text = ("Hotbar key %d" % (index + 1) if index < F0Inventory.HOTBAR_COUNT else "Carried slot %d" % (index - F0Inventory.HOTBAR_COUNT + 1)) + " · " + item_text
		inventory_slot_buttons[index].disabled = false
		inventory_slot_buttons[index].configure(index, item_id)
		inventory_slot_buttons[index].set_cursor_active(not str(session.inventory.cursor_stack.get("item_id", "")).is_empty())
		inventory_slot_buttons[index].set_presentation(slot_label, display_name, int(slot.get("count", 0)), marker)
		if index >= F0Inventory.HOTBAR_COUNT:
			inventory_slot_buttons[index].visible = _inventory_filter == "all" or (not item_id.is_empty() and session.registry.item_category(item_id) == _inventory_filter)
	var visible_carried := 0
	for index in range(F0Inventory.HOTBAR_COUNT, inventory_slot_buttons.size()):
		if inventory_slot_buttons[index].visible:
			visible_carried += 1
	inventory_filter_empty_label.visible = _inventory_filter != "all" and visible_carried == 0
	for filter_definition in INVENTORY_FILTERS:
		var filter_id := str(filter_definition.id)
		var count := 0
		for index in range(F0Inventory.HOTBAR_COUNT, slots.size()):
			var filtered_item_id := str(slots[index].get("item_id", ""))
			if not filtered_item_id.is_empty() and (filter_id == "all" or session.registry.item_category(filtered_item_id) == filter_id):
				count += 1
		var filter_button: Button = inventory_filter_buttons.get(filter_id)
		filter_button.text = "%s %d" % [str(filter_definition.label), count]
		filter_button.set_pressed_no_signal(filter_id == _inventory_filter)


func _refresh_crafting_panel() -> void:
	if session == null:
		return
	_apply_crafting_card_layout()
	if _crafting_station_type == "siege":
		_refresh_crafting_inventory()
		var siege_status := session.workstations.siege_status(_crafting_station_id)
		var siege_details: Dictionary = siege_status.get("details", {})
		var siege_definition: Dictionary = siege_details.get("definition", {})
		crafting_title_label.text = session.registry.display_name(str(siege_details.get("entity_id", "weapon"))).to_upper()
		crafting_context_label.text = "AMMUNITION  ·  STANCE  ·  TARGET FILTER  ·  RELOADS FROM CHESTS WITHIN %.0f BLOCKS  ·  ESC CLOSES" % float(siege_definition.get("supply_radius", 8.0))
		_refresh_siege_legend(siege_definition)
		_refresh_siege_panel_state()
		return
	if _crafting_station_type == "chest":
		_refresh_crafting_inventory()
		crafting_title_label.text = "CHEST"
		crafting_context_label.text = "STORE AND TAKE ITEMS  ·  SIEGE WEAPONS IN SUPPLY RANGE RELOAD FROM HERE  ·  ESC CLOSES"
		_refresh_chest_panel_state()
		return
	var recipes := _available_crafting_recipes()
	var grid_size := 2
	var grid_capacity := 4
	crafting_title_label.text = "FIELD BUILD"
	crafting_context_label.text = "2 × 2 HAND CRAFTING  ·  MANUAL PATTERNS OR RECIPE BOOK  ·  B CLOSES"
	crafting_grid_help.text = "Staged pattern — manual discovery works without the recipe book"
	crafting_grid_help.tooltip_text = "Arrange ingredients by hand; a matching recipe is recognized automatically."
	if _crafting_station_type == "workbench":
		grid_size = 3
		grid_capacity = 9
		crafting_title_label.text = "WORKBENCH"
		crafting_context_label.text = "3 × 3 CRAFTING  ·  BASIC + ADVANCED RECIPES  ·  RIGHT-CLICK ACCESS ONLY"
	elif _crafting_station_type == "furnace":
		grid_size = 3
		grid_capacity = 3
		crafting_title_label.text = "FURNACE"
		crafting_context_label.text = "INPUT + FUEL → RETAINED OUTPUT  ·  SHIFT+CLICK MOVES ALL  ·  RIGHT-CLICK SPLITS"
		crafting_grid_help.text = "Click ore or Coal, then Raw Input / Fuel adds 1 (Shift+Click 5)"
		crafting_grid_help.tooltip_text = "Real Furnace storage: input, fuel and finished output persist with this placed Furnace. Drag, double-click and right-click gestures also work."
	furnace_controls.visible = _crafting_station_type == "furnace"
	_ensure_crafting_grid_capacity(grid_capacity)
	crafting_grid.columns = grid_size
	for child in crafting_grid.get_children():
		crafting_grid.remove_child(child)
		child.queue_free()
	crafting_grid_slots.clear()
	_refresh_crafting_inventory()
	for child in crafting_recipe_list.get_children():
		crafting_recipe_list.remove_child(child)
		child.queue_free()
	var recipe_query := crafting_recipe_search.text.strip_edges().to_lower()
	var filtered_recipes: Array[Dictionary] = []
	for recipe in recipes:
		if not recipe_query.is_empty() and not _recipe_search_text(recipe).contains(recipe_query):
			continue
		filtered_recipes.append(recipe)
	var page_count := maxi(1, ceili(float(filtered_recipes.size()) / float(RECIPE_PAGE_SIZE)))
	_crafting_recipe_page = clampi(_crafting_recipe_page, 0, page_count - 1)
	var first_index := _crafting_recipe_page * RECIPE_PAGE_SIZE
	var last_index := mini(first_index + RECIPE_PAGE_SIZE, filtered_recipes.size())
	for index in range(first_index, last_index):
		var recipe: Dictionary = filtered_recipes[index]
		_add_recipe_card(recipe, _recipe_status(recipe), str(recipe.id) == _selected_recipe_id)
	if filtered_recipes.is_empty():
		var no_matches := Label.new()
		no_matches.text = "No recipes match this search."
		no_matches.add_theme_color_override("font_color", Color("8fa5af"))
		crafting_recipe_list.add_child(no_matches)
	crafting_recipe_page_label.text = "Page %d / %d" % [_crafting_recipe_page + 1, page_count]
	crafting_recipe_previous.disabled = _crafting_recipe_page <= 0
	crafting_recipe_next.disabled = _crafting_recipe_page >= page_count - 1
	for index in range(grid_capacity):
		var cell := CraftingItemSlot.new()
		cell.custom_minimum_size = Vector2(94, 74)
		cell.add_theme_stylebox_override("normal", FoundationTheme.panel(Color("0a141b"), Color("365363"), 5, 7))
		cell.add_theme_stylebox_override("hover", FoundationTheme.panel(Color("132733"), Color("78cbe0"), 5, 7))
		var item_id := _craft_grid_items[index]
		var item_count := 0
		var empty_label := "Empty"
		if _crafting_station_type == "furnace":
			var slot_name: String = ["input", "fuel", "output"][index]
			var furnace_stack: Dictionary = session.workstations.furnace_slots(_crafting_station_id).get(slot_name, {"item_id": "", "count": 0})
			item_id = str(furnace_stack.get("item_id", ""))
			item_count = int(furnace_stack.get("count", 0))
			empty_label = ["Raw Input", "Fuel", "Output"][index]
			cell.tooltip_text = "%s · click with a selected item adds one, Shift+Click adds five; double-click collects; right-click picks half or deposits one" % empty_label
			cell.configure_source("furnace", index, item_id)
			cell.configure_target("furnace", index)
		else:
			cell.tooltip_text = "Drop an inventory item here" if item_id.is_empty() else "Drag to another cell or click to clear"
			if item_id.is_empty() and _craft_grid_ghosts.has(index):
				# Red placeholder for a missing ingredient.
				var ghost_id := str(_craft_grid_ghosts[index])
				cell.add_theme_stylebox_override("normal", FoundationTheme.panel(Color("2a1014"), Color("c8404a"), 5, 7))
				cell.modulate = Color(1.0, 0.62, 0.62)
				cell.tooltip_text = "Missing ingredient — gather %s" % session.registry.display_name(ghost_id)
				cell.configure_source("grid", index, ghost_id)
				cell.configure_target("grid", index)
				cell.set_presentation("MISSING %s" % session.registry.display_name(ghost_id), 0)
				cell.set_cursor_active(not str(session.inventory.cursor_stack.get("item_id", "")).is_empty())
				cell.item_dropped.connect(_on_crafting_item_dropped)
				cell.stack_gesture.connect(_on_crafting_stack_gesture)
				cell.pressed.connect(_on_crafting_grid_slot_pressed.bind(index))
				crafting_grid_slots.append(cell)
				crafting_grid.add_child(cell)
				continue
			cell.configure_source("grid", index, item_id)
			cell.configure_target("grid", index)
		cell.set_presentation(empty_label if item_id.is_empty() else session.registry.display_name(item_id), item_count)
		cell.set_cursor_active(not str(session.inventory.cursor_stack.get("item_id", "")).is_empty())
		cell.item_dropped.connect(_on_crafting_item_dropped)
		cell.stack_gesture.connect(_on_crafting_stack_gesture)
		cell.pressed.connect(_on_crafting_grid_slot_pressed.bind(index))
		crafting_grid_slots.append(cell)
		crafting_grid.add_child(cell)
	craft_selected_button.text = "Load ×1  ·  Shift+Click ×5" if _crafting_station_type == "furnace" else "Craft ×1  ·  Shift+Click ×5"
	crafting_clear_button.text = "Return Input + Fuel" if _crafting_station_type == "furnace" else "Clear Grid"
	var selected_recipe := session.registry.recipe(_selected_recipe_id)
	if _crafting_station_type == "furnace":
		if selected_recipe.is_empty():
			_recognize_furnace_recipe()
			selected_recipe = session.registry.recipe(_selected_recipe_id)
		_refresh_furnace_panel_state(selected_recipe)
		return
	if selected_recipe.is_empty() or not _grid_matches_recipe(selected_recipe):
		crafting_output_label.text = "No matching recipe — arrange a pattern by hand or pick one from the recipe book"
		craft_selected_button.disabled = true
		return
	var selected_status := session.workstations.check_furnace_recipe(_crafting_station_id, _selected_recipe_id) if _crafting_station_type == "furnace" else _recipe_status(selected_recipe)
	var outputs: PackedStringArray = PackedStringArray()
	for item_id: String in selected_recipe.outputs:
		outputs.append("%d %s" % [int(selected_recipe.outputs[item_id]), session.registry.display_name(item_id)])
	crafting_output_label.text = "OUTPUT  →  %s\n%s" % [" + ".join(outputs), "READY" if selected_status.get("ok", false) else _craft_reason_text(str(selected_status.get("reason", "UNAVAILABLE")), str(selected_status.get("item_id", "")))]
	craft_selected_button.disabled = not selected_status.get("ok", false)


# ---------------------------------------------------------------------------
# P4a-2: siege weapon panel and Chest panel inside the crafting modal shell.
# ---------------------------------------------------------------------------

## Shows the cards that belong to the open station type and parks the shared
## message label at the bottom of the visible middle column.
func _apply_crafting_card_layout() -> void:
	var siege := _crafting_station_type == "siege"
	var chest := _crafting_station_type == "chest"
	if siege:
		crafting_inventory_help.text = "Drag a munition onto the slot, or select then click it"
	elif chest:
		crafting_inventory_help.text = "Drag onto the chest, or select then click a chest tile"
	else:
		crafting_inventory_help.text = "Drag into the grid, or select then choose a cell"
	crafting_grid_card.visible = not siege and not chest
	crafting_recipe_card.visible = not siege and not chest
	siege_card.visible = siege
	siege_legend_card.visible = siege
	chest_card.visible = chest
	var message_parent: Container = crafting_grid_column
	if siege:
		message_parent = siege_column
	elif chest:
		message_parent = chest_column
	if crafting_message.get_parent() != message_parent:
		crafting_message.reparent(message_parent, false)


func _cursor_holds_item() -> bool:
	return session != null and not str(session.inventory.cursor_stack.get("item_id", "")).is_empty()


func _refresh_siege_panel_state() -> void:
	if session == null or siege_panel == null or _crafting_station_type != "siege" or _crafting_station_id.is_empty():
		return
	var status := session.workstations.siege_status(_crafting_station_id)
	if not status.get("ok", false):
		return
	var supply: Array = session.workstations.siege_supply(_crafting_station_id)
	siege_panel.refresh(status.get("details", {}), supply, session.registry, _crafting_selected_inventory_item, _cursor_holds_item())


func _siege_effect_text(munition: Dictionary) -> String:
	if str(munition.get("effect", "impact")) == "fire":
		return "fire — burns %.0f s, spreads on wood" % float(munition.get("burn_seconds", 0.0))
	return "impact"


## Right column: one row per munition the weapon accepts (icon, name, damage,
## splash, effect) so the player can pick a shot type without leaving the panel.
func _refresh_siege_legend(definition: Dictionary) -> void:
	for child in siege_legend_list.get_children():
		siege_legend_list.remove_child(child)
		child.queue_free()
	var allowed: Array = definition.get("ammo_items", [definition.get("ammo_item", "")])
	for entry in allowed:
		var item_id := str(entry)
		var munition := session.registry.munition(item_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon_holder := PanelContainer.new()
		icon_holder.custom_minimum_size = Vector2(56, 56)
		icon_holder.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("0a141b"), Color("365363"), 5, 6))
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = ItemIconCatalog.texture_for(item_id)
		icon_holder.add_child(icon)
		row.add_child(icon_holder)
		var text := Label.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.max_lines_visible = 3
		text.add_theme_font_size_override("font_size", 13)
		text.add_theme_color_override("font_color", Color("c9f4ff"))
		var splash := float(munition.get("splash_radius", 0.0))
		text.text = "%s  ·  carrying %d\nDamage %d  ·  Splash %s\nEffect: %s" % [session.registry.display_name(item_id), session.inventory.count(item_id), int(munition.get("damage", 0)), "%.1f" % splash if splash > 0.0 else "none", _siege_effect_text(munition)]
		row.add_child(text)
		siege_legend_list.add_child(row)


func _siege_capacity() -> int:
	var status := session.workstations.siege_status(_crafting_station_id)
	return int(status.get("details", {}).get("capacity", 1))


func _load_siege_ammo(item_id: String, amount: int) -> void:
	if session == null or _crafting_station_type != "siege" or item_id.is_empty():
		return
	var result := session.workstations.siege_load(_crafting_station_id, item_id, amount)
	if result.get("ok", false):
		var details: Dictionary = result.get("details", {})
		crafting_message.text = "Loaded %d %s — %d / %d in the weapon." % [int(details.get("moved", amount)), session.registry.display_name(item_id), int(details.get("ammo", 0)), _siege_capacity()]
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_crafting_panel()


func _on_siege_ammo_slot_pressed() -> void:
	if session == null or _crafting_station_type != "siege":
		return
	if _cursor_holds_item():
		_load_siege_ammo_from_cursor(false)
		return
	if _crafting_selected_inventory_item.is_empty():
		crafting_message.text = "Select a munition tile in the inventory, then click the Ammunition slot to load 1 (Shift+Click 5)."
		return
	_load_siege_ammo(_crafting_selected_inventory_item, 1)


## The held (cursor) stack goes into the weapon; refusals keep it held.
func _load_siege_ammo_from_cursor(one: bool) -> void:
	var result := session.workstations.siege_load_from_cursor(_crafting_station_id, one)
	if result.get("ok", false):
		var details: Dictionary = result.get("details", {})
		crafting_message.text = "Loaded %d %s — %d / %d in the weapon." % [int(details.get("moved", 0)), session.registry.display_name(str(details.get("item_id", ""))), int(details.get("ammo", 0)), _siege_capacity()]
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_crafting_panel()


func _on_siege_unload_pressed() -> void:
	if session == null or _crafting_station_type != "siege":
		return
	var result := session.workstations.siege_unload(_crafting_station_id)
	if result.get("ok", false):
		var details: Dictionary = result.get("details", {})
		crafting_message.text = "Returned %d %s to the inventory." % [int(details.get("moved", 0)), session.registry.display_name(str(details.get("item_id", "")))]
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_crafting_panel()


func _on_siege_stance_requested(stance: String) -> void:
	if session == null or _crafting_station_type != "siege":
		return
	var result := session.workstations.siege_set_stance(_crafting_station_id, stance)
	if result.get("ok", false):
		match stance:
			"hold":
				crafting_message.text = "Holding fire — the weapon tracks targets but will not shoot."
			"patrol":
				crafting_message.text = "Patrolling — the kettle slides along its rails and fires at will."
			_:
				crafting_message.text = "Fire at will — shoots the first matching target in range."
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_siege_panel_state()


func _on_siege_target_filter_requested(target_filter: String) -> void:
	if session == null or _crafting_station_type != "siege":
		return
	var result := session.workstations.siege_set_target_filter(_crafting_station_id, target_filter)
	if result.get("ok", false):
		crafting_message.text = "Target filter: %s." % str(SiegeWeaponPanel.TARGET_FILTER_LABELS.get(target_filter, target_filter))
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_siege_panel_state()


func _on_siege_stack_gesture(source_kind: String, source_index: int, mouse_button: int, double_click: bool, dragging: bool, shift_pressed: bool) -> void:
	var cursor_has_item := _cursor_holds_item()
	if dragging:
		var visit_key := "%s:%d" % [source_kind, source_index]
		if source_kind != "inventory" or not cursor_has_item or _right_drag_visited.has(visit_key):
			return
		_right_drag_visited[visit_key] = true
		if session.inventory.cursor_deposit_slot(source_index, true).get("ok", false):
			crafting_message.text = "Distributed one item."
		_refresh_crafting_panel()
		return
	if source_kind == "inventory":
		var item_id := str(session.inventory.slots[source_index].get("item_id", ""))
		if cursor_has_item or item_id.is_empty() or mouse_button != MOUSE_BUTTON_LEFT or not (double_click or shift_pressed):
			_handle_inventory_cursor_gesture(source_index, mouse_button, double_click, false, crafting_message)
			return
		_crafting_selected_inventory_item = item_id
		# Double-click loads as many as fit; Shift+click loads five.
		_load_siege_ammo(item_id, _siege_capacity() if double_click else 5)
		return
	if source_kind == "siege_ammo":
		if cursor_has_item:
			# A picked-up stack loads into the weapon: right-click one, else all.
			_load_siege_ammo_from_cursor(mouse_button == MOUSE_BUTTON_RIGHT)
			return
		if shift_pressed and mouse_button == MOUSE_BUTTON_LEFT and not _crafting_selected_inventory_item.is_empty():
			_load_siege_ammo(_crafting_selected_inventory_item, 5)
		elif shift_pressed or double_click:
			_on_siege_unload_pressed()


func _refresh_chest_panel_state() -> void:
	if session == null or chest_panel == null or _crafting_station_type != "chest" or _crafting_station_id.is_empty():
		return
	var container_slots: Array = session.workstations.container_slots(_crafting_station_id)
	chest_panel.ensure_slots(container_slots.size(), _connect_chest_tile)
	chest_panel.refresh(container_slots, session.registry, _cursor_holds_item())


func _connect_chest_tile(tile: CraftingItemSlot, index: int) -> void:
	tile.pressed.connect(_on_chest_slot_pressed.bind(index))
	tile.item_dropped.connect(_on_crafting_item_dropped)
	tile.stack_gesture.connect(_on_crafting_stack_gesture)


func _chest_stack(index: int) -> Dictionary:
	var container_slots: Array = session.workstations.container_slots(_crafting_station_id)
	if index < 0 or index >= container_slots.size():
		return {"item_id": "", "count": 0}
	return container_slots[index]


func _deposit_to_chest(item_id: String, amount: int) -> void:
	if session == null or _crafting_station_type != "chest" or item_id.is_empty():
		return
	var result := session.workstations.container_deposit(_crafting_station_id, item_id, amount)
	if result.get("ok", false):
		crafting_message.text = "Stored %d %s in the chest." % [int(result.get("details", {}).get("moved", amount)), session.registry.display_name(item_id)]
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_crafting_panel()


func _withdraw_from_chest(item_id: String, amount: int) -> void:
	if session == null or _crafting_station_type != "chest" or item_id.is_empty():
		return
	var result := session.workstations.container_withdraw(_crafting_station_id, item_id, amount)
	if result.get("ok", false):
		crafting_message.text = "Took %d %s from the chest." % [int(result.get("details", {}).get("moved", amount)), session.registry.display_name(item_id)]
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_crafting_panel()


## Plain click on a chest tile: with a selected inventory item it stores one;
func _deposit_cursor_to_chest(one: bool) -> void:
	var result := session.workstations.container_deposit_from_cursor(_crafting_station_id, one)
	if result.get("ok", false):
		var details: Dictionary = result.get("details", {})
		crafting_message.text = "Stored %d %s in the chest." % [int(details.get("moved", 0)), session.registry.display_name(str(details.get("item_id", "")))]
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_crafting_panel()


## otherwise it takes one of whatever the tile holds.
func _on_chest_slot_pressed(index: int) -> void:
	if session == null or _crafting_station_type != "chest":
		return
	if _cursor_holds_item():
		_deposit_cursor_to_chest(false)
		return
	if not _crafting_selected_inventory_item.is_empty():
		_deposit_to_chest(_crafting_selected_inventory_item, 1)
		return
	var stack := _chest_stack(index)
	var item_id := str(stack.get("item_id", ""))
	if item_id.is_empty():
		crafting_message.text = "Chest slot %d is empty. Select an inventory tile, then click here to store it." % (index + 1)
		return
	_withdraw_from_chest(item_id, 1)


func _on_chest_stack_gesture(source_kind: String, source_index: int, mouse_button: int, double_click: bool, dragging: bool, shift_pressed: bool) -> void:
	var cursor_has_item := _cursor_holds_item()
	if dragging:
		var visit_key := "%s:%d" % [source_kind, source_index]
		if source_kind != "inventory" or not cursor_has_item or _right_drag_visited.has(visit_key):
			return
		_right_drag_visited[visit_key] = true
		if session.inventory.cursor_deposit_slot(source_index, true).get("ok", false):
			crafting_message.text = "Distributed one item."
		_refresh_crafting_panel()
		return
	if source_kind == "inventory":
		var slot: Dictionary = session.inventory.slots[source_index]
		var item_id := str(slot.get("item_id", ""))
		if cursor_has_item or item_id.is_empty() or mouse_button != MOUSE_BUTTON_LEFT or not (double_click or shift_pressed):
			_handle_inventory_cursor_gesture(source_index, mouse_button, double_click, false, crafting_message)
			return
		_crafting_selected_inventory_item = item_id
		# Double-click stores the whole stack; Shift+click stores five.
		_deposit_to_chest(item_id, int(slot.get("count", 0)) if double_click else 5)
		return
	if source_kind == "chest":
		if cursor_has_item:
			_deposit_cursor_to_chest(mouse_button == MOUSE_BUTTON_RIGHT)
			return
		var stack := _chest_stack(source_index)
		var item_id := str(stack.get("item_id", ""))
		if mouse_button == MOUSE_BUTTON_LEFT and not _crafting_selected_inventory_item.is_empty() and (shift_pressed or double_click):
			_deposit_to_chest(_crafting_selected_inventory_item, int(session.inventory.count(_crafting_selected_inventory_item)) if double_click else 5)
			return
		if item_id.is_empty():
			crafting_message.text = "Chest slot %d is empty." % (source_index + 1)
			return
		if shift_pressed or double_click:
			_withdraw_from_chest(item_id, int(stack.get("count", 0)))
		elif mouse_button == MOUSE_BUTTON_RIGHT:
			_withdraw_from_chest(item_id, 1)


## Round 3: the Furnace panel works without the recipe book. The recipe is
## inferred (running job, staged input, selected ore, or the only furnace
## recipe) and the Load button is enabled whenever one more batch can come
## from the inventory (additive Load ×1 / ×5, see try_load_furnace_batches).
func _refresh_furnace_panel_state(selected_recipe: Dictionary) -> void:
	var furnace_slots: Dictionary = session.workstations.furnace_slots(_crafting_station_id)
	var output_stack: Dictionary = furnace_slots.get("output", {"item_id": "", "count": 0})
	var retained_text := "Empty" if str(output_stack.get("item_id", "")).is_empty() else "%s ×%d — double-click to collect" % [session.registry.display_name(str(output_stack.item_id)), int(output_stack.count)]
	if selected_recipe.is_empty():
		crafting_output_label.text = "OUTPUT: %s\nClick an ore or Coal, then Raw Input / Fuel — or choose a recipe" % retained_text
		craft_selected_button.disabled = true
		_refresh_furnace_live_status()
		return
	var outputs: PackedStringArray = PackedStringArray()
	for item_id: String in selected_recipe.outputs:
		outputs.append("%d %s" % [int(selected_recipe.outputs[item_id]), session.registry.display_name(item_id)])
	var can_load: bool = session.workstations.can_load_furnace_batch(_crafting_station_id, _selected_recipe_id)
	var staged := session.workstations.check_furnace_recipe(_crafting_station_id, _selected_recipe_id)
	var status_text := "READY — runs automatically" if staged.get("ok", false) else _craft_reason_text(str(staged.get("reason", "UNAVAILABLE")), str(staged.get("item_id", "")))
	if not staged.get("ok", false) and can_load:
		status_text = "Load ×1 stages one batch from inventory"
	crafting_output_label.text = "OUTPUT → %s · retained: %s\n%s" % [" + ".join(outputs), retained_text, status_text]
	craft_selected_button.disabled = not can_load
	_refresh_furnace_live_status()


func _refresh_furnace_live_status() -> void:
	if session == null or furnace_controls == null or _crafting_station_type != "furnace" or _crafting_station_id.is_empty():
		return
	var job := session.workstations.furnace_job_status(_crafting_station_id)
	if bool(job.get("active", false)):
		_selected_recipe_id = str(job.get("recipe_id", _selected_recipe_id))
	var autoload := session.workstations.furnace_autoload_status(_crafting_station_id, _selected_recipe_id)
	var auto_details: Dictionary = autoload.get("details", {})
	var auto_limit := int(auto_details.get("limit", 0)) if autoload.get("ok", false) else 0
	var auto_current := int(auto_details.get("current", 0)) if autoload.get("ok", false) else 0
	var fuel_status := session.workstations.furnace_fuel_status(_crafting_station_id)
	var fuel_details: Dictionary = fuel_status.get("details", {})
	var fuel_item_name := session.registry.display_name(str(fuel_details.get("fuel_item", "coal")))
	var operations_per_fuel := int(fuel_details.get("operations_per_fuel", 1))
	var stored_operations := int(fuel_details.get("stored_operations", 0))
	_furnace_slider_refreshing = true
	furnace_auto_load_slider.max_value = float(maxi(1, auto_limit))
	furnace_auto_load_slider.set_value_no_signal(float(clampi(auto_current, 0, auto_limit)))
	furnace_auto_load_slider.editable = autoload.get("ok", false) and auto_limit > 0
	_furnace_slider_refreshing = false
	var fuel_text := "%s burning: %d of %d left" % [fuel_item_name, stored_operations, operations_per_fuel] if bool(fuel_details.get("burning", false)) else "1 %s = %d items" % [fuel_item_name, operations_per_fuel]
	furnace_auto_load_label.text = "AUTO-LOAD %d / %d  ·  %s" % [auto_current, auto_limit, fuel_text] if autoload.get("ok", false) else "AUTO-LOAD — click an ore or Coal, or choose a recipe"
	var progress := clampf(float(job.get("progress", 0.0)), 0.0, 1.0)
	furnace_progress_bar.value = progress * 100.0
	if bool(job.get("active", false)):
		var recipe := session.registry.recipe(str(job.get("recipe_id", "")))
		var output_name := "Item"
		if not recipe.is_empty() and not recipe.get("outputs", {}).is_empty():
			output_name = session.registry.display_name(str(recipe.outputs.keys()[0]))
		furnace_progress_label.text = "%s  ·  %d%%  ·  %.1fs remaining" % [output_name, roundi(progress * 100.0), float(job.get("remaining_seconds", 0.0))]
		var output_stack: Dictionary = session.workstations.furnace_slots(_crafting_station_id).get("output", {"item_id": "", "count": 0})
		var retained_text := "Empty" if str(output_stack.get("item_id", "")).is_empty() else "%s ×%d — double-click to collect" % [session.registry.display_name(str(output_stack.item_id)), int(output_stack.count)]
		crafting_output_label.text = "OUTPUT: %s\nPROCESSING %s — %d%%" % [retained_text, output_name, roundi(progress * 100.0)]
		craft_selected_button.text = "Processing…"
		craft_selected_button.disabled = true
	else:
		furnace_progress_label.text = "IDLE · runs automatically once input + fuel are loaded" if not _selected_recipe_id.is_empty() else "IDLE · add ore + Coal, or choose a recipe"
		craft_selected_button.text = "Load ×1  ·  Shift+Click ×5"


func _on_furnace_auto_load_changed(value: float) -> void:
	if _furnace_slider_refreshing or session == null or state != AppState.CRAFTING or _crafting_station_type != "furnace" or _selected_recipe_id.is_empty():
		return
	var result := session.workstations.try_set_furnace_autoload_target(_crafting_station_id, _selected_recipe_id, roundi(value))
	crafting_message.text = "Furnace auto-load target set to %d." % int(result.get("details", {}).get("requested", roundi(value))) if result.get("ok", false) else _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_refresh_crafting_panel()


func _select_crafting_recipe(recipe_id: String) -> void:
	_selected_recipe_id = recipe_id
	var recipe := session.registry.recipe(recipe_id)
	if _crafting_station_type == "furnace":
		var loaded := session.load_furnace_recipe(_crafting_station_id, recipe_id)
		crafting_message.text = "%s loaded into the Furnace input and fuel slots." % session.registry.display_name(recipe_id) if loaded.get("ok", false) else _craft_reason_text(str(loaded.get("reason", "INSUFFICIENT_INPUT")), str(loaded.get("item_id", "")))
		_refresh_crafting_panel()
		return
	var filled := _fill_grid_from_recipe(recipe)
	if filled.get("complete", false):
		crafting_message.text = "%s loaded from available inventory." % session.registry.display_name(recipe_id)
	else:
		var missing: Dictionary = filled.get("missing", {})
		var parts: PackedStringArray = PackedStringArray()
		for item_id: String in missing:
			parts.append("%d %s" % [int(missing[item_id]), session.registry.display_name(item_id)])
		crafting_message.text = "Missing %s — shown in red in the grid." % ", ".join(parts) if not parts.is_empty() else _craft_reason_text(str(_recipe_status(recipe).get("reason", "INSUFFICIENT_INPUT")))
	_refresh_crafting_panel()


func _craft_selected_recipe() -> void:
	var batches := 1
	if _crafting_station_type != "furnace" and Input.is_key_pressed(KEY_SHIFT):
		batches = 5
	_craft_selected_recipe_batches(batches)


func _craft_selected_recipe_batches(batches: int) -> void:
	if session == null:
		return
	if _crafting_station_type == "furnace" and _selected_recipe_id.is_empty():
		_recognize_furnace_recipe()
	var recipe := session.registry.recipe(_selected_recipe_id)
	if recipe.is_empty() or (_crafting_station_type != "furnace" and not _grid_matches_recipe(recipe)):
		crafting_message.text = "Click an ore or Coal in the inventory, or choose a recipe." if _crafting_station_type == "furnace" else "The staged grid does not match a recipe."
		_refresh_crafting_panel()
		return
	var recipe_station := str(recipe.get("station", ""))
	var station_id := "" if recipe_station == "hand" else _crafting_station_id
	# P3I: the furnace button loads one more batch of input plus the Coal it
	# needs (Shift+click: five) through the auto-load target; the Furnace itself
	# starts processing on the next simulation tick.
	var result: Dictionary
	if _crafting_station_type == "furnace":
		# Round 3: Load x1 / x5 is additive: it adds that many inputs plus the
		# Coal owed to the staged input; it never returns items to the inventory.
		var load_batches := 5 if Input.is_key_pressed(KEY_SHIFT) else 1
		result = session.workstations.try_load_furnace_batches(station_id, _selected_recipe_id, load_batches)
	else:
		result = session.try_craft(_selected_recipe_id, recipe_station, station_id, batches)
	if result.get("ok", false) and _crafting_station_type == "furnace":
		var moved: Dictionary = result.get("details", {}).get("moved", {})
		var parts: PackedStringArray = PackedStringArray()
		for moved_item: String in moved:
			parts.append("%d %s" % [int(moved[moved_item]), session.registry.display_name(moved_item)])
		crafting_message.text = "Loaded %s. Runs automatically; Output stays in the Furnace until collected." % " + ".join(parts)
	elif result.get("ok", false):
		crafting_message.text = "%s crafted%s." % [session.registry.display_name(_selected_recipe_id), " × %d batches" % batches if batches > 1 else ""]
	else:
		crafting_message.text = _craft_reason_text(str(result.get("reason", "CRAFT_FAILED")), str(result.get("item_id", "")))
	if result.get("ok", false) and _crafting_station_type != "furnace" and not bool(_fill_grid_from_recipe(recipe).get("complete", false)):
		_clear_crafting_grid(false, false)
	_refresh_crafting_panel()


func _available_crafting_recipes() -> Array[Dictionary]:
	var recipes: Array[Dictionary] = session.recipes_for(_crafting_station_type)
	if _crafting_station_type == "workbench":
		recipes.append_array(session.recipes_for("hand"))
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order_a := int(a.get("recipe_book_order", 2147483647))
		var order_b := int(b.get("recipe_book_order", 2147483647))
		if order_a != order_b:
			return order_a < order_b
		return session.registry.display_name(str(a.id)) < session.registry.display_name(str(b.id))
	)
	return recipes


func _recipe_status(recipe: Dictionary) -> Dictionary:
	if recipe.is_empty():
		return {"ok": false, "reason": "UNKNOWN_RECIPE"}
	var recipe_station := str(recipe.get("station", ""))
	var station_id := "" if recipe_station == "hand" else _crafting_station_id
	return session.recipe_status(str(recipe.id), recipe_station, station_id)


func _ensure_crafting_grid_capacity(capacity: int) -> void:
	if _craft_grid_items.size() == capacity:
		return
	_craft_grid_items.clear()
	_craft_grid_ghosts.clear()
	for _index in range(capacity):
		_craft_grid_items.append("")


func _refresh_crafting_inventory() -> void:
	var snapshot := session.inventory_snapshot()
	var slots: Array = snapshot.get("slots", [])
	for index in range(crafting_inventory_slots.size()):
		var slot: Dictionary = slots[index] if index < slots.size() else {"item_id": "", "count": 0}
		var item_id := str(slot.get("item_id", ""))
		var count := int(slot.get("count", 0))
		var selected := item_id == _crafting_selected_inventory_item and not item_id.is_empty()
		var marker := "▶ " if selected else ""
		crafting_inventory_slots[index].set_selected(selected)
		crafting_inventory_slots[index].disabled = false
		crafting_inventory_slots[index].configure_source("inventory", index, item_id)
		crafting_inventory_slots[index].set_cursor_active(not str(session.inventory.cursor_stack.get("item_id", "")).is_empty())
		crafting_inventory_slots[index].tooltip_text = "Slot %d · Drag to the crafting grid, or select and then choose a grid cell" % (index + 1)
		crafting_inventory_slots[index].set_presentation("Empty" if item_id.is_empty() else session.registry.display_name(item_id), count, marker)


func _select_crafting_inventory_slot(index: int) -> void:
	if index < 0 or index >= session.inventory.slots.size():
		return
	if not str(session.inventory.cursor_stack.get("item_id", "")).is_empty():
		var deposited := session.inventory.cursor_deposit_slot(index, false)
		crafting_message.text = "Placed the held stack in inventory." if deposited.get("ok", false) else _stack_reason_text(str(deposited.get("reason", "MOVE_FAILED")))
		_refresh_crafting_panel()
		return
	var item_id := str(session.inventory.slots[index].get("item_id", ""))
	if item_id.is_empty():
		return
	_crafting_selected_inventory_item = item_id
	crafting_message.text = _selection_message(item_id)
	_refresh_crafting_panel()


func _selection_message(item_id: String) -> String:
	var display_name := session.registry.display_name(item_id)
	if _crafting_station_type == "siege":
		var definition: Dictionary = session.workstations.siege_status(_crafting_station_id).get("details", {}).get("definition", {})
		var allowed: Array = definition.get("ammo_items", [definition.get("ammo_item", "")])
		if item_id in allowed:
			return "%s selected — click the Ammunition slot to load 1, Shift+Click loads 5" % display_name
		var names: PackedStringArray = PackedStringArray()
		for allowed_item in allowed:
			names.append(session.registry.display_name(str(allowed_item)))
		return "%s is not ammunition for this weapon. Select %s." % [display_name, " or ".join(names)]
	if _crafting_station_type == "chest":
		return "%s selected — click a chest tile to store 1, Shift+Click stores 5, double-click stores all" % display_name
	if _crafting_station_type != "furnace":
		return "%s selected. Choose a crafting-grid cell." % display_name
	var role := session.workstations._furnace_role_for_item(item_id)
	if role.is_empty():
		return "%s cannot go into a Furnace. Select an ore or Coal." % display_name
	return "%s selected — click %s to add 1, Shift+Click adds 5" % [display_name, "Raw Input" if role == "input" else "Fuel"]


func _on_crafting_grid_slot_pressed(index: int) -> void:
	if _crafting_station_type == "furnace":
		# P3I.1: select an ore or Coal in the inventory, then click Raw Input /
		# Fuel to add one at a time (Shift+click adds five via the gesture path).
		if index in [0, 1] and not _crafting_selected_inventory_item.is_empty():
			_add_selected_item_to_furnace(index, 1)
		return
	if not _crafting_selected_inventory_item.is_empty():
		_stage_item_in_grid(index, _crafting_selected_inventory_item)
	else:
		_clear_crafting_grid_slot(index)


func _on_crafting_item_dropped(target_kind: String, target_index: int, payload: Dictionary) -> void:
	var source_kind := str(payload.get("source_kind", ""))
	var source_index := int(payload.get("source_index", -1))
	var item_id := str(payload.get("item_id", ""))
	if _crafting_station_type in ["siege", "chest"]:
		if source_kind == "inventory" and target_kind == "inventory":
			if source_index != target_index:
				var swapped := session.inventory.swap_slots(source_index, target_index)
				crafting_message.text = "Inventory slots rearranged." if swapped.get("ok", false) else "Inventory move failed."
				_refresh_crafting_panel()
		elif _crafting_station_type == "siege" and source_kind == "inventory" and target_kind == "siege_ammo":
			_load_siege_ammo(item_id, _siege_capacity())
		elif _crafting_station_type == "siege" and source_kind == "siege_ammo" and target_kind == "inventory":
			_on_siege_unload_pressed()
		elif _crafting_station_type == "chest" and source_kind == "inventory" and target_kind == "chest":
			_deposit_to_chest(item_id, int(session.inventory.slots[source_index].get("count", 0)) if source_index >= 0 else 1)
		elif _crafting_station_type == "chest" and source_kind == "chest" and target_kind == "inventory":
			var stack := _chest_stack(source_index)
			_withdraw_from_chest(str(stack.get("item_id", "")), int(stack.get("count", 0)))
		return
	if _crafting_station_type == "furnace":
		var furnace_result: Dictionary = {"ok": false, "reason": "INVALID_SLOT"}
		if source_kind == "inventory" and target_kind == "furnace" and target_index in [0, 1]:
			furnace_result = session.transfer_inventory_stack_to_furnace(_crafting_station_id, source_index)
		elif source_kind == "furnace" and target_kind == "inventory":
			furnace_result = session.collect_furnace_stack(_crafting_station_id, ["input", "fuel", "output"][source_index])
		crafting_message.text = "Stack transferred." if furnace_result.get("ok", false) else _stack_reason_text(str(furnace_result.get("reason", "MOVE_FAILED")))
		_recognize_furnace_recipe()
		_refresh_crafting_panel()
		return
	if target_kind == "grid":
		if source_kind == "grid" and source_index >= 0 and source_index < _craft_grid_items.size():
			var held := _craft_grid_items[target_index]
			_craft_grid_items[target_index] = _craft_grid_items[source_index]
			_craft_grid_items[source_index] = held
			_after_manual_grid_change()
		elif source_kind == "inventory":
			_stage_item_in_grid(target_index, item_id)
	elif target_kind == "inventory":
		if source_kind == "grid":
			_clear_crafting_grid_slot(source_index)
		elif source_kind == "inventory" and source_index != target_index:
			var result := session.inventory.swap_slots(source_index, target_index)
			crafting_message.text = "Inventory slots rearranged." if result.get("ok", false) else "Inventory move failed."
			_refresh_crafting_panel()


func _on_crafting_stack_gesture(source_kind: String, source_index: int, mouse_button: int, double_click: bool, dragging: bool, shift_pressed: bool) -> void:
	if session == null or state != AppState.CRAFTING:
		return
	if _crafting_station_type == "siege":
		_on_siege_stack_gesture(source_kind, source_index, mouse_button, double_click, dragging, shift_pressed)
		return
	if _crafting_station_type == "chest":
		_on_chest_stack_gesture(source_kind, source_index, mouse_button, double_click, dragging, shift_pressed)
		return
	if _crafting_station_type != "furnace":
		if source_kind == "inventory":
			crafting_message.text = "Workbench cells are a one-item pattern. Drag or click ingredients to arrange a recipe manually."
		return
	var cursor_has_item := not str(session.inventory.cursor_stack.get("item_id", "")).is_empty()
	var visit_key := "%s:%d" % [source_kind, source_index]
	if dragging:
		if not cursor_has_item or _right_drag_visited.has(visit_key):
			return
		_right_drag_visited[visit_key] = true
		var spread: Dictionary
		if source_kind == "inventory":
			spread = session.inventory.cursor_deposit_slot(source_index, true)
		elif source_kind == "furnace" and source_index in [0, 1]:
			spread = session.workstations.cursor_deposit_furnace_stack(_crafting_station_id, ["input", "fuel"][source_index], true)
		else:
			return
		if spread.get("ok", false):
			crafting_message.text = "Distributed one item."
		_refresh_crafting_panel()
		return
	var result: Dictionary
	if source_kind == "inventory":
		if double_click and not cursor_has_item:
			result = session.transfer_inventory_stack_to_furnace(_crafting_station_id, source_index)
		elif shift_pressed and mouse_button == MOUSE_BUTTON_LEFT and not cursor_has_item:
			var shift_item := str(session.inventory.slots[source_index].get("item_id", ""))
			_crafting_selected_inventory_item = shift_item
			result = session.workstations.try_transfer_inventory_item_to_furnace(_crafting_station_id, shift_item, 5)
		else:
			_handle_inventory_cursor_gesture(source_index, mouse_button, double_click, false, crafting_message)
			return
	elif source_kind == "furnace" and source_index in [0, 1, 2]:
		var slot_name: String = ["input", "fuel", "output"][source_index]
		if shift_pressed and mouse_button == MOUSE_BUTTON_LEFT and not cursor_has_item and source_index in [0, 1] and not _crafting_selected_inventory_item.is_empty():
			_add_selected_item_to_furnace(source_index, 5)
			return
		elif (shift_pressed or double_click) and not cursor_has_item:
			result = session.collect_furnace_stack(_crafting_station_id, slot_name)
		elif cursor_has_item:
			result = session.workstations.cursor_deposit_furnace_stack(_crafting_station_id, slot_name, mouse_button == MOUSE_BUTTON_RIGHT)
		else:
			result = session.workstations.cursor_pick_furnace_stack(_crafting_station_id, slot_name, mouse_button == MOUSE_BUTTON_RIGHT)
	else:
		return
	crafting_message.text = "Stack transferred." if result.get("ok", false) else _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_right_drag_visited.clear()
	_recognize_furnace_recipe()
	_refresh_crafting_panel()


## Adds `amount` of the selected inventory item to the clicked Furnace slot when
## the item belongs there (ore → Raw Input, Coal → Fuel).
func _add_selected_item_to_furnace(slot_index: int, amount: int) -> void:
	var item_id := _crafting_selected_inventory_item
	var slot_name: String = ["input", "fuel"][slot_index]
	var role := session.workstations._furnace_role_for_item(item_id)
	if role != slot_name:
		crafting_message.text = "%s belongs in the %s slot." % [session.registry.display_name(item_id), "Raw Input" if role == "input" else "Fuel"] if not role.is_empty() else "%s cannot go into a Furnace." % session.registry.display_name(item_id)
		return
	var result := session.workstations.try_transfer_inventory_item_to_furnace(_crafting_station_id, item_id, amount)
	if result.get("ok", false):
		crafting_message.text = "Added %d %s. Click again for more; Shift+Click adds five." % [int(result.get("details", {}).get("moved", amount)), session.registry.display_name(item_id)]
	else:
		crafting_message.text = _stack_reason_text(str(result.get("reason", "MOVE_FAILED")))
	_recognize_furnace_recipe()
	_refresh_crafting_panel()


func _stage_item_in_grid(index: int, item_id: String) -> void:
	if index < 0 or index >= _craft_grid_items.size() or item_id.is_empty():
		return
	var candidate := _craft_grid_items.duplicate()
	candidate[index] = item_id
	var candidate_counts := _grid_counts(candidate)
	if int(candidate_counts.get(item_id, 0)) > session.inventory.count(item_id):
		crafting_message.text = "No additional %s is available." % session.registry.display_name(item_id)
		return
	_craft_grid_items[index] = item_id
	_crafting_selected_inventory_item = ""
	_after_manual_grid_change()


func _clear_crafting_grid_slot(index: int) -> void:
	if index < 0 or index >= _craft_grid_items.size():
		return
	_craft_grid_items[index] = ""
	_after_manual_grid_change()


func _clear_crafting_grid(refresh: bool = true, announce: bool = true) -> void:
	if _crafting_station_type == "furnace" and session != null:
		var returned_any := false
		for slot_name in ["input", "fuel"]:
			var result := session.collect_furnace_stack(_crafting_station_id, slot_name)
			returned_any = returned_any or result.get("ok", false)
		_selected_recipe_id = ""
		crafting_message.text = "Input and fuel returned to inventory." if returned_any else "No input or fuel could be returned."
		if refresh:
			_refresh_crafting_panel()
		return
	for index in range(_craft_grid_items.size()):
		_craft_grid_items[index] = ""
	_selected_recipe_id = ""
	_crafting_selected_inventory_item = ""
	if announce:
		crafting_message.text = "Crafting grid cleared."
	if refresh:
		_refresh_crafting_panel()


func _after_manual_grid_change() -> void:
	_craft_grid_ghosts.clear()
	_selected_recipe_id = ""
	for recipe in _available_crafting_recipes():
		if _grid_matches_recipe(recipe):
			_selected_recipe_id = str(recipe.id)
			break
	crafting_message.text = "Recipe recognized: %s." % session.registry.display_name(_selected_recipe_id) if not _selected_recipe_id.is_empty() else "Arrange ingredients or select a recipe."
	_refresh_crafting_panel()


func _recognize_furnace_recipe() -> void:
	if _crafting_station_type != "furnace" or session == null:
		return
	_selected_recipe_id = ""
	var job := session.workstations.furnace_job_status(_crafting_station_id)
	if bool(job.get("active", false)):
		_selected_recipe_id = str(job.get("recipe_id", ""))
		return
	for recipe in session.recipes_for("furnace"):
		if session.workstations.check_furnace_recipe(_crafting_station_id, str(recipe.id)).get("ok", false):
			_selected_recipe_id = str(recipe.id)
			return
	# Round 3: infer the recipe without the recipe book — from the staged Raw
	# Input, then the selected inventory ore, then the only furnace recipe.
	var input_stack: Dictionary = session.workstations.furnace_slots(_crafting_station_id).get("input", {"item_id": "", "count": 0})
	var inferred := session.workstations.furnace_recipe_for_input(str(input_stack.get("item_id", "")))
	if inferred.is_empty() and not _crafting_selected_inventory_item.is_empty():
		inferred = session.workstations.furnace_recipe_for_input(_crafting_selected_inventory_item)
	if inferred.is_empty():
		var furnace_recipes: Array[Dictionary] = session.recipes_for("furnace")
		if furnace_recipes.size() == 1:
			inferred = str(furnace_recipes[0].get("id", ""))
	_selected_recipe_id = inferred


## Stages a recipe: carried ingredients go into the grid, the ones the pack
## lacks become red ghosts. Returns {complete, missing: {item: count}}.
func _fill_grid_from_recipe(recipe: Dictionary) -> Dictionary:
	if recipe.is_empty():
		return {"complete": false, "missing": {}}
	if str(recipe.get("station", "")) == "furnace":
		return {"complete": bool(session.load_furnace_recipe(_crafting_station_id, str(recipe.id)).get("ok", false)), "missing": {}}
	var input_cells: Array[String] = []
	var ghost_cells: Array[bool] = []
	var missing: Dictionary = {}
	for raw_item_id in recipe.inputs.keys():
		var item_id := str(raw_item_id)
		var available := session.inventory.count(item_id)
		for count in range(int(recipe.inputs[item_id])):
			input_cells.append(item_id)
			var ghost := count >= available
			ghost_cells.append(ghost)
			if ghost:
				missing[item_id] = int(missing.get(item_id, 0)) + 1
	if input_cells.size() > _craft_grid_items.size():
		return {"complete": false, "missing": missing}
	_craft_grid_ghosts.clear()
	for index in range(_craft_grid_items.size()):
		if index < input_cells.size() and ghost_cells[index]:
			_craft_grid_items[index] = ""
			_craft_grid_ghosts[index] = input_cells[index]
		else:
			_craft_grid_items[index] = input_cells[index] if index < input_cells.size() else ""
	return {"complete": missing.is_empty(), "missing": missing}


func _grid_matches_recipe(recipe: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	if str(recipe.get("station", "")) == "furnace":
		return session.workstations.check_furnace_recipe(_crafting_station_id, str(recipe.id)).get("ok", false)
	var staged := _grid_counts(_craft_grid_items)
	var inputs: Dictionary = recipe.get("inputs", {})
	if staged.size() != inputs.size():
		return false
	for item_id: String in inputs:
		if int(staged.get(item_id, 0)) != int(inputs[item_id]):
			return false
	return true


func _grid_counts(items: Array) -> Dictionary:
	var counts := {}
	for value in items:
		var item_id := str(value)
		if not item_id.is_empty():
			counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts


func _recipe_search_text(recipe: Dictionary) -> String:
	var terms := session.registry.display_name(str(recipe.id))
	for item_id: String in recipe.inputs:
		terms += " " + session.registry.display_name(item_id)
	for item_id: String in recipe.outputs:
		terms += " " + session.registry.display_name(item_id)
	return terms.to_lower()


func _on_crafting_recipe_search_changed(_query: String) -> void:
	_crafting_recipe_page = 0
	_refresh_crafting_panel()


func _change_recipe_page(direction: int) -> void:
	_crafting_recipe_page = maxi(0, _crafting_recipe_page + direction)
	_refresh_crafting_panel()


func _on_crafting_recipe_book_gui_input(event: InputEvent, source: Control) -> void:
	if state != AppState.CRAFTING or not event is InputEventMouseButton or not event.pressed:
		return
	if not _turn_recipe_page_from_wheel(event.button_index):
		return
	source.accept_event()


func _turn_recipe_page_from_wheel(button_index: int) -> bool:
	var direction := 1 if button_index == MOUSE_BUTTON_WHEEL_DOWN else -1 if button_index == MOUSE_BUTTON_WHEEL_UP else 0
	if direction == 0:
		return false
	_change_recipe_page(direction)
	return true


func _on_crafting_recipe_search_submitted(_query: String) -> void:
	var query := crafting_recipe_search.text.strip_edges().to_lower()
	for recipe in _available_crafting_recipes():
		if query.is_empty() or _recipe_search_text(recipe).contains(query):
			_select_crafting_recipe(str(recipe.id))
			return
	crafting_message.text = "No matching recipe."


func _add_recipe_card(recipe: Dictionary, status: Dictionary, selected: bool) -> void:
	var card := RecipeCatalogCard.new()
	card.pressed.connect(_select_crafting_recipe.bind(str(recipe.id)))
	card.gui_input.connect(_on_crafting_recipe_book_gui_input.bind(card))
	# Owner 2026-09-19: no ingredient hover; a click stages the recipe with red
	# placeholders for whatever is missing.
	var hover := "%s · %s" % [session.registry.display_name(str(recipe.id)), "READY" if status.get("ok", false) else _craft_reason_text(str(status.get("reason", "UNAVAILABLE")), str(status.get("item_id", ""))).to_upper()]
	card.configure(recipe, session.registry.display_name(str(recipe.id)), bool(status.get("ok", false)), selected, hover, str(status.get("reason", "")))
	crafting_recipe_list.add_child(card)


func _recipe_button_text(recipe: Dictionary, status: Dictionary) -> String:
	var inputs: PackedStringArray = PackedStringArray()
	for item_id: String in recipe.inputs:
		inputs.append("%d %s" % [int(recipe.inputs[item_id]), session.registry.display_name(item_id)])
	var outputs: PackedStringArray = PackedStringArray()
	for item_id: String in recipe.outputs:
		outputs.append("%d %s" % [int(recipe.outputs[item_id]), session.registry.display_name(item_id)])
	var suffix := "READY" if status.get("ok", false) else _craft_reason_text(str(status.get("reason", "UNAVAILABLE")), str(status.get("item_id", ""))).to_upper()
	return "%s\n%s  →  %s\n%s" % [session.registry.display_name(str(recipe.id)), " + ".join(inputs), " + ".join(outputs), suffix]


func _craft_reason_text(reason: String, item_id: String = "") -> String:
	match reason:
		"INSUFFICIENT_INPUT":
			return "Missing %s" % (session.registry.display_name(item_id) if not item_id.is_empty() else "materials")
		"INVENTORY_FULL":
			return "No output room"
		"WRONG_WORKSTATION":
			return "Wrong workstation"
		"STATION_BUSY":
			return "Furnace is busy"
		_:
			return reason.replace("_", " ").capitalize()


func _show_keybinds() -> void:
	capture_action = ""
	capture_forward = false
	_overlay_return_state = state
	if keybind_search != null:
		keybind_search.clear()
	keybind_message.text = "Escape always cancels capture and remains the recovery path."
	_refresh_binding_labels()
	menu_panel.hide()
	pause_panel.hide()
	keybind_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_keybinds() -> void:
	capture_action = ""
	capture_forward = false
	keybind_panel.hide()
	_restore_overlay_parent()


func _capture_binding(action: String) -> void:
	capture_action = action
	capture_forward = action == "move_forward"
	keybind_message.text = "Press a keyboard key or mouse button for %s. Escape cancels." % settings.get_action_label(action)


func _capture_forward_key() -> void:
	_capture_binding("move_forward")


func _reset_bindings() -> void:
	var result := settings.reset_defaults()
	keybind_message.text = "All bindings restored to the documented ESDF defaults." if result.get("ok", false) else "Reset failed: %s" % result.get("reason", "UNKNOWN")
	_refresh_binding_labels()


func _reset_binding(action: String) -> void:
	var result := settings.reset_action(action)
	keybind_message.text = "%s restored to %s." % [settings.get_action_label(action), settings.get_binding_label(action)] if result.get("ok", false) else _binding_error_text(result)
	_refresh_binding_labels()


func _on_keybind_search_changed(_query: String) -> void:
	_refresh_binding_labels()


func _refresh_binding_labels() -> void:
	var query := "" if keybind_search == null else keybind_search.text.strip_edges().to_lower()
	for action in binding_labels:
		binding_labels[action].text = settings.get_binding_label(action)
		if binding_reset_buttons.has(action):
			binding_reset_buttons[action].disabled = settings.is_default_binding(action)
		if binding_rows.has(action):
			var searchable := (settings.get_action_label(action) + " " + settings.get_binding_label(action)).to_lower()
			binding_rows[action].visible = query.is_empty() or searchable.contains(query)
	_refresh_hud()


func _refresh_binding_label() -> void:
	_refresh_binding_labels()


func _show_settings() -> void:
	_overlay_return_state = state
	menu_panel.hide()
	pause_panel.hide()
	_refresh_settings_controls()
	_refresh_world_settings_controls()
	settings_message.text = _display_mode_help(window_mode_option.selected)
	settings_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_settings() -> void:
	if settings.is_display_preview_active():
		settings.rollback_display_preview()
	display_confirm_panel.hide()
	settings_panel.hide()
	_restore_overlay_parent()


func _refresh_settings_controls() -> void:
	sensitivity_slider.value = settings.mouse_sensitivity
	invert_check.button_pressed = settings.invert_y
	volume_slider.value = settings.master_volume * 100.0
	window_mode_option.select(1 if settings.window_mode == "fullscreen" else 0)
	var resolution_index := SettingsStore.RESOLUTION_OPTIONS.find(settings.resolution)
	resolution_option.select(maxi(0, resolution_index))
	msaa_option.select(settings.msaa_3d)
	view_distance_option.select(maxi(0, SettingsStore.VIEW_DISTANCE_OPTIONS.find(settings.view_distance)))
	vsync_check.button_pressed = settings.vsync_enabled
	_refresh_display_mode_controls(window_mode_option.selected)
	_on_sensitivity_value_changed(sensitivity_slider.value)
	_on_volume_value_changed(volume_slider.value)


func _toggle_world_settings() -> void:
	world_settings_content.visible = not world_settings_content.visible
	world_settings_toggle.text = "WORLD SETTINGS  ▾" if world_settings_content.visible else "WORLD SETTINGS  ▸"
	if world_settings_content.visible:
		_refresh_world_settings_controls()
		world_time_input.grab_focus()
		settings_scroll.call_deferred("ensure_control_visible", world_apply_button)


func _refresh_world_settings_controls() -> void:
	var active_world := session != null and session.clock != null
	world_time_input.editable = active_world
	world_cycle_check.disabled = not active_world
	world_apply_button.disabled = not active_world
	if active_world:
		world_time_input.text = session.clock.time_input_text()
		world_cycle_check.button_pressed = session.clock.cycle_enabled
		world_settings_message.text = "Changes apply immediately to this world and persist with the next normal save."
	else:
		world_time_input.text = "0800"
		world_cycle_check.button_pressed = true
		world_settings_message.text = "Start or Continue a world, then open Settings from Pause to change its time."


func _apply_world_settings() -> void:
	if session == null:
		world_settings_message.text = "No active world. Start or Continue, pause, then open Settings."
		return
	var result := session.apply_world_settings(world_time_input.text, world_cycle_check.button_pressed)
	if not result.get("ok", false):
		var reason := str(result.get("reason", "UNKNOWN"))
		world_settings_message.text = "Not applied: enter a valid 24-hour time from 0000 to 2359." if reason in ["TIME_FORMAT", "TIME_RANGE"] else "World setting failed: %s" % reason.replace("_", " ").capitalize()
		return
	world_time_input.text = str(result.get("time", world_time_input.text))
	world_settings_message.text = "%s applied; cycle %s. Save and Exit to keep it for this slot." % [str(result.get("time_label", "Time")), "enabled" if result.get("cycle_enabled", true) else "paused"]


func _save_input_audio() -> void:
	var result := settings.set_input_audio_preferences(float(sensitivity_slider.value), invert_check.button_pressed, float(volume_slider.value) / 100.0)
	if session != null:
		session.apply_input_settings(settings)
	settings_message.text = "Input and audio settings saved." if result.get("ok", false) else "Settings failed: %s" % result.get("reason", "UNKNOWN")


func _save_graphics() -> void:
	var result := settings.set_graphics_preferences(msaa_option.selected, vsync_check.button_pressed, SettingsStore.VIEW_DISTANCE_OPTIONS[maxi(0, view_distance_option.selected)])
	if result.get("ok", false):
		_apply_runtime_graphics()
		settings_message.text = "Graphics quality saved and applied."
	else:
		settings_message.text = "Graphics settings failed: %s" % result.get("reason", "UNKNOWN")


func _apply_runtime_graphics() -> void:
	get_viewport().msaa_3d = settings.msaa_3d
	if session != null and session.world != null:
		session.world.set_view_distance(settings.view_distance)


func _preview_display_changes() -> void:
	var mode := "fullscreen" if window_mode_option.selected == 1 else "windowed"
	var selected_resolution: Vector2i = SettingsStore.RESOLUTION_OPTIONS[resolution_option.selected]
	var result := settings.begin_display_preview(mode, selected_resolution)
	if not result.get("ok", false):
		settings_message.text = "Display change rejected: %s" % result.get("reason", "UNKNOWN")
		return
	_display_confirm_remaining = DISPLAY_CONFIRM_SECONDS
	display_confirm_panel.show()


func _confirm_display_preview() -> void:
	var result := settings.confirm_display_preview()
	display_confirm_panel.hide()
	settings_message.text = "Display settings saved." if result.get("ok", false) else "Display confirmation failed: %s" % result.get("reason", "UNKNOWN")
	_refresh_settings_controls()


func _rollback_display_preview(message: String = "Display settings reverted.") -> void:
	settings.rollback_display_preview()
	display_confirm_panel.hide()
	settings_message.text = message
	_refresh_settings_controls()


func _restore_overlay_parent() -> void:
	if _overlay_return_state == AppState.PAUSED:
		pause_panel.show()
	else:
		menu_panel.show()


func _on_sensitivity_value_changed(value: float) -> void:
	if sensitivity_value_label != null:
		sensitivity_value_label.text = "%.4f" % value


func _on_volume_value_changed(value: float) -> void:
	if volume_value_label != null:
		volume_value_label.text = "%d%%" % roundi(value)


func _on_window_mode_selected(index: int) -> void:
	_refresh_display_mode_controls(index)
	if settings_message != null:
		settings_message.text = _display_mode_help(index)


func _refresh_display_mode_controls(index: int) -> void:
	var fullscreen_selected := index == 1
	resolution_option.disabled = fullscreen_selected
	windowed_resolution_row.visible = not fullscreen_selected
	fullscreen_resolution_row.visible = fullscreen_selected
	if fullscreen_selected:
		var native_size := settings.get_active_screen_size()
		fullscreen_resolution_value_label.text = "%d × %d (monitor native)" % [native_size.x, native_size.y]


func _display_mode_help(index: int) -> String:
	if index == 1:
		return "Fullscreen uses the monitor's native resolution and expands to fill the entire screen."
	return "Windowed resolution changes the app window. Display previews revert automatically unless confirmed."


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_right_drag_visited.clear()
	if not capture_action.is_empty() and ((event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)):
		get_viewport().set_input_as_handled()
		if event is InputEventKey and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
			capture_action = ""
			capture_forward = false
			keybind_message.text = "Key capture cancelled; no binding changed."
			return
		var action := capture_action
		var result := settings.rebind_event(action, event)
		capture_action = ""
		capture_forward = false
		if result.get("ok", false):
			keybind_message.text = "%s is now %s." % [settings.get_action_label(action), settings.get_binding_label(action)]
		else:
			keybind_message.text = _binding_error_text(result)
		_refresh_binding_labels()
		return

	if _is_print_screen_press(event):
		get_viewport().set_input_as_handled()
		_print_screen_pressed_msec = Time.get_ticks_msec()
		return

	if state == AppState.PLAYING and event.is_action_pressed("capture_screenshot") and not (event is InputEventKey and event.echo):
		get_viewport().set_input_as_handled()
		_capture_gameplay_screenshot()
		return
	if state == AppState.PLAYING and minimap != null and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_M or event.keycode == KEY_M):
		get_viewport().set_input_as_handled()
		minimap.toggle_full_map()
		return

	if _is_escape_press(event):
		get_viewport().set_input_as_handled()
		_handle_escape_recovery()
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_handle_escape_recovery()
		return
	if event.is_action_pressed("inventory") and state in [AppState.PLAYING, AppState.INVENTORY]:
		get_viewport().set_input_as_handled()
		if state == AppState.PLAYING:
			_show_inventory()
		else:
			_close_inventory()
		return
	if event.is_action_pressed("build") and state in [AppState.PLAYING, AppState.CRAFTING]:
		get_viewport().set_input_as_handled()
		if state == AppState.PLAYING:
			_show_crafting()
		elif _crafting_station_type == "hand":
			_close_crafting()


func _is_escape_press(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE)


func _is_print_screen_press(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.physical_keycode == KEY_PRINT or event.keycode == KEY_PRINT)


func _handle_escape_recovery() -> void:
	if display_confirm_panel.visible:
		_rollback_display_preview("Display settings reverted.")
	elif keybind_panel.visible:
		_close_keybinds()
	elif settings_panel.visible:
		_close_settings()
	elif state == AppState.INVENTORY:
		_close_inventory()
	elif state == AppState.CRAFTING:
		_close_crafting()
	elif state == AppState.PLAYING and session != null and session.is_riding():
		# Coaster car: Escape leaves the car before it ever pauses.
		_set_feedback(str(session.REASON_TEXT.get("COASTER_LEFT", "Left the coaster car.")) if session.leave_coaster_car().get("ok", false) else "")
	elif state == AppState.PLAYING:
		_pause_game()
	elif state == AppState.PAUSED:
		_resume_game()


func _binding_error_text(result: Dictionary) -> String:
	var reason := str(result.get("reason", "UNKNOWN"))
	if reason == "CONFLICT":
		var conflict := str(result.get("conflict", ""))
		return "Rejected: CONFLICT — already used by %s (%s)." % [settings.get_action_label(conflict), settings.get_binding_label(conflict)]
	if reason == "ESCAPE_RESERVED":
		return "Rejected: Escape is always reserved as the recovery and cancel key."
	return "Binding rejected: %s" % reason.replace("_", " ").capitalize()


func _save_and_exit_to_menu() -> void:
	_save_then(false)


func _save_and_quit() -> void:
	_save_then(true)


func _save_then(quit_after: bool) -> void:
	if session == null or state == AppState.SAVING:
		return
	state = AppState.SAVING
	get_tree().paused = false
	_hide_all_panels()
	loading_panel.show()
	status_label.text = "Saving coherent terrain and inventory checkpoint…"
	var result := await saves.save_session(session)
	if not result.get("ok", false):
		_failed_save_quit_after = quit_after
		_show_error("Save failed: %s" % result.get("reason", "UNKNOWN"), true)
		return
	print("CHECKPOINT %s" % JSON.stringify(result))
	session.queue_free()
	session = null
	if quit_after:
		get_tree().quit(0)
	else:
		_show_main_menu()


func _show_error(message: String, recoverable_session: bool = false) -> void:
	state = AppState.ERROR
	get_tree().paused = false
	_hide_all_panels()
	loading_panel.show()
	status_label.text = _save_reason_text(message.trim_prefix("Save failed: "))
	loading_back_button.visible = not recoverable_session
	loading_retry_button.visible = recoverable_session
	loading_return_button.visible = recoverable_session
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _retry_failed_save() -> void:
	if session != null and state == AppState.ERROR:
		_save_then(_failed_save_quit_after)


func _return_from_save_error() -> void:
	if session == null or state != AppState.ERROR:
		return
	loading_panel.hide()
	loading_retry_button.hide()
	loading_return_button.hide()
	state = AppState.PAUSED
	get_tree().paused = true
	session.pause_game(true)
	pause_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _save_reason_text(reason: String) -> String:
	match reason:
		"NO_VALID_CHECKPOINT":
			return "No complete checkpoint exists in this slot yet."
		"UNSUPPORTED_SAVE_SCHEMA":
			return "This slot was created by a newer or unsupported save format. It was not changed."
		"MISSING_CONTENT_VERSION":
			return "This slot needs content that is not available in this build. It was not changed."
		"MALFORMED_POINTER", "MALFORMED_MANIFEST", "MALFORMED_GAMEPLAY":
			return "This slot is malformed and was refused without replacing it."
		_:
			return reason.replace("_", " ").capitalize()


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
	print("STATUS %s" % message)


func _set_hud(text: String) -> void:
	_hud_state_text = text
	_refresh_hud()


func _set_navigation(text: String) -> void:
	if navigation_label != null:
		navigation_label.text = text


func _set_defense(text: String) -> void:
	if defense_label != null:
		defense_label.text = text


func _refresh_hud() -> void:
	if hud_label == null or settings == null or _hud_state_text.is_empty():
		return
	var movement := "%s%s%s%s" % [settings.get_binding_label("move_forward"), settings.get_binding_label("strafe_left"), settings.get_binding_label("move_backward"), settings.get_binding_label("strafe_right")]
	hud_label.text = "%s   |   %s move · %s sprint · %s crouch · %s interact · %s use/place · %s build · %s/%s rotate · %s inventory · %s pause · %s capture" % [
		_hud_state_text,
		movement,
		settings.get_binding_label("sprint"),
		settings.get_binding_label("crouch"),
		settings.get_binding_label("interact"),
		settings.get_binding_label("secondary"),
		settings.get_binding_label("build"),
		settings.get_binding_label("rotate_build_clockwise"),
		settings.get_binding_label("rotate_build_counterclockwise"),
		settings.get_binding_label("inventory"),
		settings.get_binding_label("pause"),
		settings.get_binding_label("capture_screenshot"),
	]


func _capture_gameplay_screenshot() -> void:
	if state != AppState.PLAYING or session == null:
		return
	var state_before := state
	var tree_paused_before := get_tree().paused
	var session_paused_before := session.simulation_paused
	var result := await screenshots.capture_viewport(get_viewport())
	if state != state_before or get_tree().paused != tree_paused_before or session == null or session.simulation_paused != session_paused_before:
		push_error("Gameplay capture changed session state unexpectedly")
	if result.get("ok", false):
		_set_feedback("Screenshot saved: %s" % result.filename)
		print("SCREENSHOT %s" % JSON.stringify(result))
	else:
		_set_feedback("Screenshot failed: %s" % str(result.get("reason", "UNKNOWN")).replace("_", " ").capitalize())
		push_error("Screenshot failed: %s" % JSON.stringify(result))


func _set_feedback(text: String) -> void:
	feedback_label.text = text


func _on_quit_pressed() -> void:
	get_tree().quit(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		call_deferred("_handle_close_request")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		call_deferred("_handle_focus_lost")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		call_deferred("_handle_focus_gained")


func _handle_focus_lost() -> void:
	# Diagnostics drive the window themselves; a focus change from the host
	# (another window opening beside the render) must not pause them.
	if automation_active:
		return
	if state == AppState.PLAYING:
		if Time.get_ticks_msec() - _print_screen_pressed_msec <= PRINT_SCREEN_FOCUS_WINDOW_MSEC:
			_print_screen_pressed_msec = -PRINT_SCREEN_FOCUS_WINDOW_MSEC
			_screenshot_focus_suspended = true
			_screenshot_resume_generation += 1
			session.pause_game(true)
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		_pause_game()
		_set_feedback("Paused because the application lost focus. Resume explicitly when ready.")


func _handle_focus_gained() -> void:
	if not _screenshot_focus_suspended:
		return
	_screenshot_resume_generation += 1
	_resume_after_screenshot_focus(_screenshot_resume_generation)


func _resume_after_screenshot_focus(generation: int) -> void:
	await get_tree().create_timer(SCREENSHOT_CLICK_GUARD_SECONDS, true).timeout
	if not _screenshot_focus_suspended or generation != _screenshot_resume_generation:
		return
	_screenshot_focus_suspended = false
	if state == AppState.PLAYING and session != null:
		get_tree().paused = false
		session.pause_game(false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _handle_close_request() -> void:
	if session != null and state in [AppState.PLAYING, AppState.PAUSED, AppState.INVENTORY, AppState.CRAFTING]:
		_save_then(true)
	elif state != AppState.SAVING:
		get_tree().quit(0)


func _hide_all_panels() -> void:
	for panel in [menu_panel, pause_panel, keybind_panel, settings_panel, inventory_panel, crafting_panel, display_confirm_panel, loading_panel, hud_layer]:
		if panel != null:
			panel.hide()


func _full_panel(color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.theme = FoundationTheme.create()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel


func _centered_box(parent: Control, box_size: Vector2 = Vector2(660, 420)) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = -box_size / 2.0
	box.size = box_size
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	parent.add_child(box)
	return box


func _settings_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 34)
	row.add_child(label)
	return row


func _title(text: String, font_size: int) -> Label:
	var label := _centered_label(text)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _centered_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _button(text: String, callback: Callable, minimum: Vector2 = Vector2(360, 44)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.pressed.connect(callback)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer
