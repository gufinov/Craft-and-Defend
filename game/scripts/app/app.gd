class_name CraftAndDefendApp
extends Node

enum AppState { MAIN_MENU, LOADING, PLAYING, PAUSED, INVENTORY, SAVING, ERROR }

const DISPLAY_CONFIRM_SECONDS := 10.0
const PRINT_SCREEN_FOCUS_WINDOW_MSEC := 2000
const SCREENSHOT_CLICK_GUARD_SECONDS := 0.20
const BINDING_GROUPS: Array[Dictionary] = [
	{"title": "MOVEMENT", "actions": ["move_forward", "move_backward", "strafe_left", "strafe_right", "sprint", "crouch", "jump"]},
	{"title": "WORLD & MENUS", "actions": ["primary", "secondary", "interact", "inventory", "pause"]},
	{"title": "HOTBAR", "actions": ["hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8", "hotbar_9"]},
]

var state := AppState.MAIN_MENU
var data_root := ""
var settings: SettingsStore
var saves: SaveCoordinator
var session: GameSession

var menu_panel: Control
var pause_panel: Control
var keybind_panel: Control
var settings_panel: Control
var inventory_panel: Control
var display_confirm_panel: Control
var loading_panel: Control
var hud_layer: Control
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
var status_label: Label
var hud_label: Label
var feedback_label: Label
var inventory_contents_label: Label
var keybind_search: LineEdit
var binding_rows: Dictionary = {}
var binding_reset_buttons: Dictionary = {}
var inventory_slot_buttons: Array[Button] = []
var inventory_context_label: Label
var inventory_message: Label
var recipe_list: VBoxContainer
var _inventory_station_id := ""
var _inventory_station_type := "hand"
var _inventory_move_source := -1
var sensitivity_slider: HSlider
var sensitivity_value_label: Label
var invert_check: CheckButton
var volume_slider: HSlider
var volume_value_label: Label
var window_mode_option: OptionButton
var resolution_option: OptionButton
var windowed_resolution_row: HBoxContainer
var fullscreen_resolution_row: HBoxContainer
var fullscreen_resolution_value_label: Label
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	data_root = _resolve_data_root()
	DirAccess.make_dir_recursive_absolute(data_root)
	settings = SettingsStore.new(data_root)
	settings.load_and_apply()
	saves = SaveCoordinator.new(data_root)
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


func _process(delta: float) -> void:
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
	_build_hud(canvas)
	_build_display_confirmation(canvas)


func _build_main_menu(canvas: CanvasLayer) -> void:
	menu_panel = _full_panel(Color("17222c"))
	canvas.add_child(menu_panel)
	var menu := _centered_box(menu_panel, Vector2(700, 570))
	var title := _title("CRAFT AND DEFEND", 34)
	menu.add_child(title)
	var subtitle := _centered_label("F3 persistence hardening · development build")
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
	var pause_box := _centered_box(pause_panel, Vector2(700, 520))
	pause_box.add_child(_title("PAUSED", 30))
	pause_box.add_child(_button("Resume", _resume_game))
	pause_box.add_child(_button("Settings", _show_settings))
	pause_box.add_child(_button("Keybinds", _show_keybinds))
	pause_box.add_child(_button("Save and Exit to Menu", _save_and_exit_to_menu))
	pause_box.add_child(_button("Save and Quit", _save_and_quit))


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
	var box := _centered_box(settings_panel, Vector2(760, 590))
	box.add_child(_title("SETTINGS", 28))

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
	settings_message = _centered_label("")
	settings_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_message.custom_minimum_size = Vector2(650, 24)
	box.add_child(settings_message)
	box.add_child(_button("Back", _close_settings, Vector2(360, 42)))
	sensitivity_slider.value_changed.connect(_on_sensitivity_value_changed)
	volume_slider.value_changed.connect(_on_volume_value_changed)
	window_mode_option.item_selected.connect(_on_window_mode_selected)


func _build_inventory(canvas: CanvasLayer) -> void:
	inventory_panel = _full_panel(Color(0.035, 0.06, 0.078, 0.98))
	canvas.add_child(inventory_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	inventory_panel.add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _title("INVENTORY & CRAFTING", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Back to Game", _close_inventory, Vector2(190, 44)))
	inventory_context_label = Label.new()
	inventory_context_label.add_theme_color_override("font_color", Color("85d5ea"))
	root.add_child(inventory_context_label)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	root.add_child(columns)
	var inventory_card := PanelContainer.new()
	inventory_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 18))
	columns.add_child(inventory_card)
	var inventory_column := VBoxContainer.new()
	inventory_card.add_child(inventory_column)
	var inventory_heading := Label.new()
	inventory_heading.text = "27 SLOTS  ·  FIRST 9 ARE THE HOTBAR"
	inventory_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	inventory_column.add_child(inventory_heading)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_column.add_child(grid)
	for index in range(F0Inventory.SLOT_COUNT):
		var slot_button := _button("", _select_inventory_slot.bind(index), Vector2(180, 45))
		slot_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot_button.tooltip_text = "Select hotbar slot %d" % (index + 1) if index < F0Inventory.HOTBAR_COUNT else "Storage slot %d" % (index + 1)
		inventory_slot_buttons.append(slot_button)
		grid.add_child(slot_button)
	inventory_contents_label = Label.new()
	inventory_contents_label.visible = false
	inventory_column.add_child(inventory_contents_label)
	var recipe_card := PanelContainer.new()
	recipe_card.custom_minimum_size.x = 520
	recipe_card.add_theme_stylebox_override("panel", FoundationTheme.panel(Color("101a23"), Color("344c5a"), 8, 18))
	columns.add_child(recipe_card)
	var recipe_column := VBoxContainer.new()
	recipe_card.add_child(recipe_column)
	var recipe_heading := Label.new()
	recipe_heading.text = "AVAILABLE RECIPES"
	recipe_heading.add_theme_color_override("font_color", Color("9fd8e8"))
	recipe_column.add_child(recipe_heading)
	var recipe_scroll := ScrollContainer.new()
	recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_column.add_child(recipe_scroll)
	recipe_list = VBoxContainer.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_scroll.add_child(recipe_list)
	inventory_message = Label.new()
	inventory_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_message.add_theme_color_override("font_color", Color("ffd488"))
	recipe_column.add_child(inventory_message)


func _build_hud(canvas: CanvasLayer) -> void:
	hud_layer = Control.new()
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_layer)
	hud_label = Label.new()
	hud_label.position = Vector2(20, 18)
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_layer.add_child(hud_label)
	feedback_label = Label.new()
	feedback_label.position = Vector2(20, 52)
	feedback_label.custom_minimum_size = Vector2(760, 30)
	feedback_label.add_theme_color_override("font_color", Color("ffe08a"))
	hud_layer.add_child(feedback_label)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-7, -16)
	hud_layer.add_child(crosshair)


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
	session.name = "GameSession"
	add_child(session)
	session.ready_for_play.connect(_on_session_ready)
	session.status_changed.connect(_set_status)
	session.hud_changed.connect(_set_hud)
	session.feedback_changed.connect(_set_feedback)
	session.inventory_changed.connect(_on_session_inventory_changed)
	session.workstation_requested.connect(_show_workstation)
	var initialize_result := session.initialize(open_result)
	if not initialize_result.get("ok", false):
		_show_error(initialize_result.get("reason", "SESSION_INITIALIZE_FAILED"))
		return
	session.apply_input_settings(settings)


func _on_session_ready() -> void:
	state = AppState.PLAYING
	loading_panel.hide()
	hud_layer.show()
	feedback_label.text = ""


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


func _show_inventory(station_id: String = "", station_type: String = "hand") -> void:
	if state != AppState.PLAYING or session == null:
		return
	_inventory_station_id = station_id
	_inventory_station_type = station_type if station_type in ["workbench", "furnace"] else "hand"
	_inventory_move_source = -1
	state = AppState.INVENTORY
	session.pause_game(true)
	get_tree().paused = true
	hud_layer.hide()
	_refresh_inventory_panel()
	inventory_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_workstation(instance_id: String, station_type: String) -> void:
	_show_inventory(instance_id, station_type)


func _close_inventory() -> void:
	if state != AppState.INVENTORY:
		return
	inventory_panel.hide()
	hud_layer.show()
	get_tree().paused = false
	session.pause_game(false)
	state = AppState.PLAYING
	_inventory_station_id = ""
	_inventory_station_type = "hand"
	_inventory_move_source = -1


func _on_session_inventory_changed(_snapshot: Dictionary) -> void:
	if inventory_panel != null and inventory_panel.visible:
		_refresh_inventory_panel()


func _select_inventory_slot(index: int) -> void:
	if session == null:
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


func _refresh_inventory_panel() -> void:
	if session == null:
		return
	var snapshot := session.inventory_snapshot()
	var slots: Array = snapshot.get("slots", [])
	for index in range(inventory_slot_buttons.size()):
		var slot: Dictionary = slots[index] if index < slots.size() else {"item_id": "", "count": 0}
		var item_id := str(slot.get("item_id", ""))
		var prefix := "%d  " % (index + 1) if index < F0Inventory.HOTBAR_COUNT else "%02d  " % (index + 1)
		var marker := "↔ " if index == _inventory_move_source else ("▶ " if index == int(snapshot.get("selected_hotbar", 0)) and index < F0Inventory.HOTBAR_COUNT else "  ")
		inventory_slot_buttons[index].text = marker + prefix + ("Empty" if item_id.is_empty() else "%s  ×%d" % [session.registry.display_name(item_id), int(slot.get("count", 0))])
		inventory_slot_buttons[index].disabled = false
	inventory_context_label.text = ("HAND CRAFTING  ·  Tab closes" if _inventory_station_type == "hand" else "%s  ·  Shift opens while targeted" % session.registry.display_name(_inventory_station_type).to_upper())
	for child in recipe_list.get_children():
		child.queue_free()
	for recipe in session.recipes_for(_inventory_station_type):
		var status := session.recipe_status(str(recipe.id), _inventory_station_type, _inventory_station_id)
		var button := _button(_recipe_button_text(recipe, status), _craft_recipe.bind(str(recipe.id)), Vector2(460, 62))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not status.get("ok", false)
		button.tooltip_text = "Ready" if status.get("ok", false) else _craft_reason_text(str(status.get("reason", "UNAVAILABLE")), str(status.get("item_id", "")))
		recipe_list.add_child(button)


func _craft_recipe(recipe_id: String) -> void:
	if session == null:
		return
	var result := session.try_craft(recipe_id, _inventory_station_type, _inventory_station_id)
	inventory_message.text = "%s crafted." % session.registry.display_name(recipe_id) if result.get("ok", false) else _craft_reason_text(str(result.get("reason", "CRAFT_FAILED")), str(result.get("item_id", "")))
	_refresh_inventory_panel()


func _recipe_button_text(recipe: Dictionary, status: Dictionary) -> String:
	var inputs: PackedStringArray = PackedStringArray()
	for item_id: String in recipe.inputs:
		inputs.append("%d %s" % [int(recipe.inputs[item_id]), session.registry.display_name(item_id)])
	var outputs: PackedStringArray = PackedStringArray()
	for item_id: String in recipe.outputs:
		outputs.append("%d %s" % [int(recipe.outputs[item_id]), session.registry.display_name(item_id)])
	var suffix := "READY" if status.get("ok", false) else _craft_reason_text(str(status.get("reason", "UNAVAILABLE")), str(status.get("item_id", ""))).to_upper()
	return "%s\n%s  →  %s   ·   %s" % [session.registry.display_name(str(recipe.id)), " + ".join(inputs), " + ".join(outputs), suffix]


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


func _refresh_binding_label() -> void:
	_refresh_binding_labels()


func _show_settings() -> void:
	_overlay_return_state = state
	menu_panel.hide()
	pause_panel.hide()
	_refresh_settings_controls()
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
	_refresh_display_mode_controls(window_mode_option.selected)
	_on_sensitivity_value_changed(sensitivity_slider.value)
	_on_volume_value_changed(volume_slider.value)


func _save_input_audio() -> void:
	var result := settings.set_input_audio_preferences(float(sensitivity_slider.value), invert_check.button_pressed, float(volume_slider.value) / 100.0)
	if session != null:
		session.apply_input_settings(settings)
	settings_message.text = "Input and audio settings saved." if result.get("ok", false) else "Settings failed: %s" % result.get("reason", "UNKNOWN")


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
	hud_label.text = text


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
	if session != null and state in [AppState.PLAYING, AppState.PAUSED, AppState.INVENTORY]:
		_save_then(true)
	elif state != AppState.SAVING:
		get_tree().quit(0)


func _hide_all_panels() -> void:
	for panel in [menu_panel, pause_panel, keybind_panel, settings_panel, inventory_panel, display_confirm_panel, loading_panel, hud_layer]:
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
