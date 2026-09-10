class_name CraftAndDefendApp
extends Node

enum AppState { MAIN_MENU, LOADING, PLAYING, PAUSED, SAVING, ERROR }

var state := AppState.MAIN_MENU
var data_root := ""
var settings: SettingsStore
var saves: SaveCoordinator
var session: GameSession

var menu_panel: Control
var pause_panel: Control
var keybind_panel: Control
var loading_panel: Control
var hud_layer: Control
var continue_button: Button
var start_button: Button
var forward_binding_label: Label
var keybind_message: Label
var status_label: Label
var hud_label: Label
var capture_forward := false


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
	var automation_mode := _argument_value("--f0-automation=")
	if not automation_mode.is_empty():
		var automation := F0Automation.new()
		add_child(automation)
		automation.call_deferred("run", self, automation_mode)


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

	menu_panel = _full_panel(Color("17222c"))
	canvas.add_child(menu_panel)
	var menu := _centered_box(menu_panel)
	var title := Label.new()
	title.text = "CRAFT AND DEFEND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	menu.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "F0 finite voxel-world integration spike"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(subtitle)
	menu.add_child(_spacer(12))
	start_button = _button("Start", _on_start_pressed)
	menu.add_child(start_button)
	continue_button = _button("Continue", _on_continue_pressed)
	menu.add_child(continue_button)
	menu.add_child(_button("Keybinds", _show_keybinds))
	menu.add_child(_button("Quit", _on_quit_pressed))
	var root_hint := Label.new()
	root_hint.text = "Local saves: %s" % data_root
	root_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_hint.custom_minimum_size = Vector2(620, 0)
	menu.add_child(root_hint)

	loading_panel = _full_panel(Color("17222c"))
	canvas.add_child(loading_panel)
	var loading_box := _centered_box(loading_panel)
	var loading_title := Label.new()
	loading_title.text = "Loading finite world…"
	loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_title.add_theme_font_size_override("font_size", 26)
	loading_box.add_child(loading_title)
	status_label = Label.new()
	status_label.text = "Preparing terrain and collision"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(600, 0)
	loading_box.add_child(status_label)

	pause_panel = _full_panel(Color(0.04, 0.06, 0.08, 0.92))
	canvas.add_child(pause_panel)
	var pause_box := _centered_box(pause_panel)
	var paused_title := Label.new()
	paused_title.text = "PAUSED"
	paused_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_title.add_theme_font_size_override("font_size", 30)
	pause_box.add_child(paused_title)
	pause_box.add_child(_button("Resume", _resume_game))
	pause_box.add_child(_button("Keybinds", _show_keybinds))
	pause_box.add_child(_button("Save and Exit to Menu", _save_and_exit_to_menu))
	pause_box.add_child(_button("Save and Quit", _save_and_quit))

	keybind_panel = _full_panel(Color("17222c"))
	canvas.add_child(keybind_panel)
	var key_box := _centered_box(keybind_panel)
	var key_title := Label.new()
	key_title.text = "KEYBINDS"
	key_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_title.add_theme_font_size_override("font_size", 28)
	key_box.add_child(key_title)
	var defaults := Label.new()
	defaults.text = "ESDF move · A sprint · Z crouch · Space jump\nShift interact · Tab inventory · Escape pause · 1–9 hotbar"
	defaults.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_box.add_child(defaults)
	forward_binding_label = Label.new()
	forward_binding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_box.add_child(forward_binding_label)
	key_box.add_child(_button("Change Forward Key", _capture_forward_key))
	key_box.add_child(_button("Reset Defaults", _reset_bindings))
	key_box.add_child(_button("Back", _close_keybinds))
	keybind_message = Label.new()
	keybind_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keybind_message.custom_minimum_size = Vector2(560, 0)
	key_box.add_child(keybind_message)

	hud_layer = Control.new()
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_layer)
	hud_label = Label.new()
	hud_label.position = Vector2(20, 18)
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_layer.add_child(hud_label)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-7, -16)
	hud_layer.add_child(crosshair)


func _show_main_menu() -> void:
	state = AppState.MAIN_MENU
	get_tree().paused = false
	menu_panel.show()
	pause_panel.hide()
	keybind_panel.hide()
	loading_panel.hide()
	hud_layer.hide()
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
	var initialize_result := session.initialize(open_result)
	if not initialize_result.get("ok", false):
		_show_error(initialize_result.get("reason", "SESSION_INITIALIZE_FAILED"))


func _on_session_ready() -> void:
	state = AppState.PLAYING
	loading_panel.hide()
	hud_layer.show()


func _pause_game() -> void:
	if state != AppState.PLAYING:
		return
	state = AppState.PAUSED
	session.pause_game(true)
	get_tree().paused = true
	pause_panel.show()
	hud_layer.hide()


func _resume_game() -> void:
	if state != AppState.PAUSED:
		return
	pause_panel.hide()
	hud_layer.show()
	get_tree().paused = false
	session.pause_game(false)
	state = AppState.PLAYING


func _show_keybinds() -> void:
	capture_forward = false
	keybind_message.text = "Escape always cancels key capture and remains the recovery path."
	_refresh_binding_label()
	menu_panel.hide()
	pause_panel.hide()
	keybind_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_keybinds() -> void:
	capture_forward = false
	keybind_panel.hide()
	if state == AppState.MAIN_MENU:
		menu_panel.show()
	elif state == AppState.PAUSED:
		pause_panel.show()


func _capture_forward_key() -> void:
	capture_forward = true
	keybind_message.text = "Press a new physical key for Forward. Escape cancels."


func _reset_bindings() -> void:
	var result := settings.reset_defaults()
	keybind_message.text = "Defaults restored." if result.get("ok", false) else "Reset failed: %s" % result.get("reason", "UNKNOWN")
	_refresh_binding_label()


func _refresh_binding_label() -> void:
	forward_binding_label.text = "Forward: %s" % settings.get_key_label("move_forward")


func _unhandled_input(event: InputEvent) -> void:
	if capture_forward and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			capture_forward = false
			keybind_message.text = "Key capture cancelled."
			return
		var code: int = event.physical_keycode if event.physical_keycode > 0 else event.keycode
		var result := settings.rebind_key("move_forward", code)
		capture_forward = false
		keybind_message.text = "Forward binding saved." if result.get("ok", false) else "Rejected: %s" % result.get("reason", "UNKNOWN")
		_refresh_binding_label()
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if keybind_panel.visible:
			_close_keybinds()
		elif state == AppState.PLAYING:
			_pause_game()
		elif state == AppState.PAUSED:
			_resume_game()


func _save_and_exit_to_menu() -> void:
	_save_then(false)


func _save_and_quit() -> void:
	_save_then(true)


func _save_then(quit_after: bool) -> void:
	if session == null or state == AppState.SAVING:
		return
	state = AppState.SAVING
	get_tree().paused = false
	pause_panel.hide()
	hud_layer.hide()
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
	loading_panel.show()
	status_label.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
	print("STATUS %s" % message)


func _set_hud(text: String) -> void:
	hud_label.text = text


func _on_quit_pressed() -> void:
	get_tree().quit(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		call_deferred("_handle_close_request")


func _handle_close_request() -> void:
	if session != null and state in [AppState.PLAYING, AppState.PAUSED]:
		_save_then(true)
	elif state != AppState.SAVING:
		get_tree().quit(0)


func _full_panel(color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel


func _centered_box(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-330, -210)
	box.size = Vector2(660, 420)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	return box


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 44)
	button.pressed.connect(callback)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer
