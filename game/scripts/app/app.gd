class_name CraftAndDefendApp
extends Node

enum AppState { MAIN_MENU, LOADING, PLAYING, PAUSED, INVENTORY, SAVING, ERROR }

const DISPLAY_CONFIRM_SECONDS := 10.0

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
var forward_binding_label: Label
var keybind_message: Label
var settings_message: Label
var status_label: Label
var hud_label: Label
var feedback_label: Label
var inventory_contents_label: Label
var sensitivity_slider: HSlider
var sensitivity_value_label: Label
var invert_check: CheckButton
var volume_slider: HSlider
var volume_value_label: Label
var window_mode_option: OptionButton
var resolution_option: OptionButton
var display_confirm_label: Label
var binding_labels: Dictionary = {}
var capture_action := ""
var capture_forward := false
var _overlay_return_state := AppState.MAIN_MENU
var _display_confirm_remaining := 0.0


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
	var menu := _centered_box(menu_panel, Vector2(700, 500))
	var title := _title("CRAFT AND DEFEND", 34)
	menu.add_child(title)
	var subtitle := _centered_label("F1 interaction hardening · development build")
	menu.add_child(subtitle)
	menu.add_child(_spacer(12))
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
	keybind_panel = _full_panel(Color("17222c"))
	canvas.add_child(keybind_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	keybind_panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	layout.add_child(_title("KEYBINDS", 28))
	layout.add_child(_centered_label("Physical-key ESDF defaults · select Change, then press a keyboard key or mouse button"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	center.add_child(grid)
	for action in SettingsStore.BINDING_ACTIONS:
		var action_label := Label.new()
		action_label.text = settings.get_action_label(action)
		action_label.custom_minimum_size = Vector2(210, 36)
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(action_label)
		var current_label := Label.new()
		current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		current_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		current_label.custom_minimum_size = Vector2(170, 36)
		binding_labels[action] = current_label
		grid.add_child(current_label)
		var change_button := _button("Change", _capture_binding.bind(action), Vector2(150, 36))
		change_button.tooltip_text = "Change %s" % settings.get_action_label(action)
		grid.add_child(change_button)
		if action == "move_forward":
			forward_binding_label = current_label

	keybind_message = _centered_label("Escape always cancels capture and remains the recovery path.")
	keybind_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keybind_message.custom_minimum_size = Vector2(700, 24)
	layout.add_child(keybind_message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	actions.add_child(_button("Reset Defaults", _reset_bindings, Vector2(220, 42)))
	actions.add_child(_button("Back", _close_keybinds, Vector2(220, 42)))
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
	var resolution_row := _settings_row("Windowed resolution")
	resolution_option = OptionButton.new()
	for option in SettingsStore.RESOLUTION_OPTIONS:
		resolution_option.add_item("%d × %d" % [option.x, option.y])
	resolution_option.custom_minimum_size = Vector2(350, 36)
	resolution_row.add_child(resolution_option)
	box.add_child(resolution_row)
	box.add_child(_button("Preview Display Changes", _preview_display_changes, Vector2(360, 42)))
	settings_message = _centered_label("")
	settings_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_message.custom_minimum_size = Vector2(650, 24)
	box.add_child(settings_message)
	box.add_child(_button("Back", _close_settings, Vector2(360, 42)))
	sensitivity_slider.value_changed.connect(_on_sensitivity_value_changed)
	volume_slider.value_changed.connect(_on_volume_value_changed)


func _build_inventory(canvas: CanvasLayer) -> void:
	inventory_panel = _full_panel(Color(0.04, 0.06, 0.08, 0.95))
	canvas.add_child(inventory_panel)
	var box := _centered_box(inventory_panel, Vector2(700, 460))
	box.add_child(_title("INVENTORY", 30))
	box.add_child(_centered_label("Foundation inventory overlay · world input is paused and blocked"))
	inventory_contents_label = _centered_label("Dirt\n0 / 64")
	inventory_contents_label.add_theme_font_size_override("font_size", 24)
	inventory_contents_label.custom_minimum_size = Vector2(320, 140)
	box.add_child(inventory_contents_label)
	box.add_child(_centered_label("Slots, tools, and hotbar item selection arrive in F2."))
	box.add_child(_button("Close Inventory", _close_inventory))


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
	continue_button.disabled = not saves.has_checkpoint()
	continue_button.tooltip_text = "" if not continue_button.disabled else "No valid checkpoint yet"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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


func _show_inventory() -> void:
	if state != AppState.PLAYING or session == null:
		return
	state = AppState.INVENTORY
	session.pause_game(true)
	get_tree().paused = true
	hud_layer.hide()
	inventory_contents_label.text = session.inventory_text()
	inventory_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_inventory() -> void:
	if state != AppState.INVENTORY:
		return
	inventory_panel.hide()
	hud_layer.show()
	get_tree().paused = false
	session.pause_game(false)
	state = AppState.PLAYING


func _show_keybinds() -> void:
	capture_action = ""
	capture_forward = false
	_overlay_return_state = state
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


func _refresh_binding_labels() -> void:
	for action in binding_labels:
		binding_labels[action].text = settings.get_binding_label(action)


func _refresh_binding_label() -> void:
	_refresh_binding_labels()


func _show_settings() -> void:
	_overlay_return_state = state
	menu_panel.hide()
	pause_panel.hide()
	_refresh_settings_controls()
	settings_message.text = "Display changes require confirmation and automatically roll back."
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
		_show_error("Save failed: %s" % result.get("reason", "UNKNOWN"))
		return
	print("CHECKPOINT %s" % JSON.stringify(result))
	session.queue_free()
	session = null
	if quit_after:
		get_tree().quit(0)
	else:
		_show_main_menu()


func _show_error(message: String) -> void:
	state = AppState.ERROR
	get_tree().paused = false
	_hide_all_panels()
	loading_panel.show()
	status_label.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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


func _handle_focus_lost() -> void:
	if state == AppState.PLAYING:
		_pause_game()
		_set_feedback("Paused because the application lost focus. Resume explicitly when ready.")


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
