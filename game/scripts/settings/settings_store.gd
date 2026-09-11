class_name SettingsStore
extends RefCounted

const SETTINGS_SCHEMA := 2
const MIN_MOUSE_SENSITIVITY := 0.0005
const MAX_MOUSE_SENSITIVITY := 0.01
const DEFAULT_MOUSE_SENSITIVITY := 0.0025
const DEFAULT_MASTER_VOLUME := 1.0
const DEFAULT_WINDOW_MODE := "windowed"
const DEFAULT_RESOLUTION := Vector2i(1280, 720)

const BINDING_ACTIONS: Array[String] = [
	"move_forward", "move_backward", "strafe_left", "strafe_right",
	"sprint", "crouch", "jump", "interact", "inventory", "pause",
	"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5",
	"hotbar_6", "hotbar_7", "hotbar_8", "hotbar_9", "primary", "secondary",
]

const ACTION_LABELS := {
	"move_forward": "Move Forward", "move_backward": "Move Backward",
	"strafe_left": "Strafe Left", "strafe_right": "Strafe Right",
	"sprint": "Sprint", "crouch": "Crouch", "jump": "Jump",
	"interact": "Interact", "inventory": "Inventory", "pause": "Pause",
	"hotbar_1": "Hotbar 1", "hotbar_2": "Hotbar 2", "hotbar_3": "Hotbar 3",
	"hotbar_4": "Hotbar 4", "hotbar_5": "Hotbar 5", "hotbar_6": "Hotbar 6",
	"hotbar_7": "Hotbar 7", "hotbar_8": "Hotbar 8", "hotbar_9": "Hotbar 9",
	"primary": "Break / Primary", "secondary": "Place / Secondary",
}

const ACTION_CONTEXTS := {
	"move_forward": "gameplay", "move_backward": "gameplay",
	"strafe_left": "gameplay", "strafe_right": "gameplay",
	"sprint": "gameplay", "crouch": "gameplay", "jump": "gameplay",
	"interact": "gameplay", "inventory": "gameplay", "pause": "system",
	"hotbar_1": "gameplay", "hotbar_2": "gameplay", "hotbar_3": "gameplay",
	"hotbar_4": "gameplay", "hotbar_5": "gameplay", "hotbar_6": "gameplay",
	"hotbar_7": "gameplay", "hotbar_8": "gameplay", "hotbar_9": "gameplay",
	"primary": "gameplay", "secondary": "gameplay",
}

const DEFAULT_BINDINGS := {
	"move_forward": {"kind": "key", "code": KEY_E},
	"move_backward": {"kind": "key", "code": KEY_D},
	"strafe_left": {"kind": "key", "code": KEY_S},
	"strafe_right": {"kind": "key", "code": KEY_F},
	"sprint": {"kind": "key", "code": KEY_A},
	"crouch": {"kind": "key", "code": KEY_Z},
	"jump": {"kind": "key", "code": KEY_SPACE},
	"interact": {"kind": "key", "code": KEY_SHIFT},
	"inventory": {"kind": "key", "code": KEY_TAB},
	"pause": {"kind": "key", "code": KEY_ESCAPE},
	"hotbar_1": {"kind": "key", "code": KEY_1},
	"hotbar_2": {"kind": "key", "code": KEY_2},
	"hotbar_3": {"kind": "key", "code": KEY_3},
	"hotbar_4": {"kind": "key", "code": KEY_4},
	"hotbar_5": {"kind": "key", "code": KEY_5},
	"hotbar_6": {"kind": "key", "code": KEY_6},
	"hotbar_7": {"kind": "key", "code": KEY_7},
	"hotbar_8": {"kind": "key", "code": KEY_8},
	"hotbar_9": {"kind": "key", "code": KEY_9},
	"primary": {"kind": "mouse", "code": MOUSE_BUTTON_LEFT},
	"secondary": {"kind": "mouse", "code": MOUSE_BUTTON_RIGHT},
}

const RESOLUTION_OPTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3440, 1440),
]

var _settings_path: String
var _bindings: Dictionary = {}
var _display_backup: Dictionary = {}
var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var invert_y := false
var master_volume := DEFAULT_MASTER_VOLUME
var window_mode := DEFAULT_WINDOW_MODE
var resolution := DEFAULT_RESOLUTION


func _init(data_root: String) -> void:
	_settings_path = data_root.path_join("settings.cfg")


func load_and_apply() -> Dictionary:
	_bindings = DEFAULT_BINDINGS.duplicate(true)
	var bindings_recovered := false
	var config := ConfigFile.new()
	var load_error := config.load(_settings_path)
	if load_error == OK:
		for action in BINDING_ACTIONS:
			var fallback: Dictionary = DEFAULT_BINDINGS[action]
			var kind := str(config.get_value("binding_types", action, fallback.kind))
			var code := int(config.get_value("bindings", action, fallback.code))
			if _binding_is_valid(kind, code):
				_bindings[action] = {"kind": kind, "code": code}
		mouse_sensitivity = clampf(float(config.get_value("input", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)), MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
		invert_y = bool(config.get_value("input", "invert_y", false))
		master_volume = clampf(float(config.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)), 0.0, 1.0)
		window_mode = str(config.get_value("display", "window_mode", DEFAULT_WINDOW_MODE))
		var width := int(config.get_value("display", "width", DEFAULT_RESOLUTION.x))
		var height := int(config.get_value("display", "height", DEFAULT_RESOLUTION.y))
		var candidate_resolution := Vector2i(width, height)
		if RESOLUTION_OPTIONS.has(candidate_resolution):
			resolution = candidate_resolution
		if window_mode not in ["windowed", "fullscreen"]:
			window_mode = DEFAULT_WINDOW_MODE
		if not _bindings_are_safe():
			_bindings = DEFAULT_BINDINGS.duplicate(true)
			bindings_recovered = true
	_apply_all_bindings()
	_apply_non_display_settings()
	_apply_display(window_mode, resolution)
	return {"ok": true, "path": _settings_path, "loaded": load_error == OK, "bindings_recovered": bindings_recovered}


func rebind_key(action: String, physical_keycode: int) -> Dictionary:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = physical_keycode
	return rebind_event(action, event)


func rebind_event(action: String, event: InputEvent) -> Dictionary:
	if not DEFAULT_BINDINGS.has(action):
		return {"ok": false, "reason": "UNKNOWN_ACTION"}
	var candidate := _binding_from_event(event)
	if candidate.is_empty():
		return {"ok": false, "reason": "UNSUPPORTED_INPUT"}
	if candidate.kind == "key" and int(candidate.code) == KEY_ESCAPE:
		return {"ok": false, "reason": "ESCAPE_RESERVED"}
	for other_action in BINDING_ACTIONS:
		if other_action == action or not _contexts_overlap(action, other_action):
			continue
		var other: Dictionary = _bindings[other_action]
		if other.kind == candidate.kind and int(other.code) == int(candidate.code):
			return {"ok": false, "reason": "CONFLICT", "conflict": other_action}
	var previous: Dictionary = _bindings[action].duplicate(true)
	_bindings[action] = candidate
	_apply_binding(action, candidate)
	var save_error := _save()
	if save_error != OK:
		_bindings[action] = previous
		_apply_binding(action, previous)
		return {"ok": false, "reason": "SAVE_FAILED", "error": save_error}
	return {"ok": true, "reason": "OK", "action": action, "binding": get_binding_label(action)}


func reset_defaults() -> Dictionary:
	var previous := _bindings.duplicate(true)
	_bindings = DEFAULT_BINDINGS.duplicate(true)
	_apply_all_bindings()
	var save_error := _save()
	if save_error != OK:
		_bindings = previous
		_apply_all_bindings()
		return {"ok": false, "reason": "SAVE_FAILED", "error": save_error}
	return {"ok": true, "reason": "OK"}


func set_input_audio_preferences(sensitivity: float, inverted: bool, volume: float) -> Dictionary:
	if sensitivity < MIN_MOUSE_SENSITIVITY or sensitivity > MAX_MOUSE_SENSITIVITY:
		return {"ok": false, "reason": "INVALID_SENSITIVITY"}
	if volume < 0.0 or volume > 1.0:
		return {"ok": false, "reason": "INVALID_VOLUME"}
	var previous := {"mouse_sensitivity": mouse_sensitivity, "invert_y": invert_y, "master_volume": master_volume}
	mouse_sensitivity = sensitivity
	invert_y = inverted
	master_volume = volume
	_apply_non_display_settings()
	var save_error := _save()
	if save_error != OK:
		mouse_sensitivity = previous.mouse_sensitivity
		invert_y = previous.invert_y
		master_volume = previous.master_volume
		_apply_non_display_settings()
		return {"ok": false, "reason": "SAVE_FAILED", "error": save_error}
	return {"ok": true, "reason": "OK"}


func begin_display_preview(candidate_mode: String, candidate_resolution: Vector2i) -> Dictionary:
	if candidate_mode not in ["windowed", "fullscreen"]:
		return {"ok": false, "reason": "INVALID_WINDOW_MODE"}
	if not RESOLUTION_OPTIONS.has(candidate_resolution):
		return {"ok": false, "reason": "INVALID_RESOLUTION"}
	if not _display_backup.is_empty():
		rollback_display_preview()
	_display_backup = {"window_mode": window_mode, "resolution": resolution}
	window_mode = candidate_mode
	resolution = candidate_resolution
	_apply_display(window_mode, resolution)
	return {"ok": true, "reason": "PREVIEWING", "window_mode": window_mode, "resolution": resolution}


func confirm_display_preview() -> Dictionary:
	if _display_backup.is_empty():
		return {"ok": false, "reason": "NO_DISPLAY_PREVIEW"}
	var save_error := _save()
	if save_error != OK:
		rollback_display_preview()
		return {"ok": false, "reason": "SAVE_FAILED", "error": save_error}
	_display_backup.clear()
	return {"ok": true, "reason": "OK"}


func rollback_display_preview() -> Dictionary:
	if _display_backup.is_empty():
		return {"ok": false, "reason": "NO_DISPLAY_PREVIEW"}
	window_mode = str(_display_backup.window_mode)
	resolution = _display_backup.resolution
	_display_backup.clear()
	_apply_display(window_mode, resolution)
	return {"ok": true, "reason": "ROLLED_BACK", "window_mode": window_mode, "resolution": resolution}


func is_display_preview_active() -> bool:
	return not _display_backup.is_empty()


func get_keycode(action: String) -> int:
	var binding: Dictionary = _bindings.get(action, {})
	return int(binding.get("code", 0)) if binding.get("kind") == "key" else 0


func get_binding(action: String) -> Dictionary:
	return _bindings.get(action, {}).duplicate(true)


func get_binding_label(action: String) -> String:
	var binding: Dictionary = _bindings.get(action, {})
	if binding.get("kind") == "mouse":
		match int(binding.get("code", 0)):
			MOUSE_BUTTON_LEFT:
				return "Mouse Left"
			MOUSE_BUTTON_RIGHT:
				return "Mouse Right"
			MOUSE_BUTTON_MIDDLE:
				return "Mouse Middle"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse Back"
			MOUSE_BUTTON_XBUTTON2:
				return "Mouse Forward"
			_:
				return "Mouse %d" % int(binding.get("code", 0))
	return OS.get_keycode_string(int(binding.get("code", 0)))


func get_key_label(action: String) -> String:
	return get_binding_label(action)


func get_action_label(action: String) -> String:
	return str(ACTION_LABELS.get(action, action.replace("_", " ").capitalize()))


func get_settings_path() -> String:
	return _settings_path


func get_active_screen() -> int:
	if DisplayServer.get_name().contains("headless"):
		return 0
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		screen = DisplayServer.get_primary_screen()
	return screen


func get_active_screen_size() -> Vector2i:
	if DisplayServer.get_name().contains("headless"):
		return resolution
	return DisplayServer.screen_get_size(get_active_screen())


func _binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode > 0 else event.keycode
		return {"kind": "key", "code": code} if code > 0 else {}
	if event is InputEventMouseButton and event.pressed:
		return {"kind": "mouse", "code": int(event.button_index)}
	return {}


func _binding_is_valid(kind: String, code: int) -> bool:
	return kind in ["key", "mouse"] and code > 0


func _contexts_overlap(first: String, second: String) -> bool:
	var first_context := str(ACTION_CONTEXTS.get(first, "gameplay"))
	var second_context := str(ACTION_CONTEXTS.get(second, "gameplay"))
	return first_context == second_context or first_context == "system" or second_context == "system"


func _bindings_are_safe() -> bool:
	for action in BINDING_ACTIONS:
		var binding: Dictionary = _bindings.get(action, {})
		if not _binding_is_valid(str(binding.get("kind", "")), int(binding.get("code", 0))):
			return false
		if action != "pause" and binding.kind == "key" and int(binding.code) == KEY_ESCAPE:
			return false
	for first_index in range(BINDING_ACTIONS.size()):
		var first_action := BINDING_ACTIONS[first_index]
		var first: Dictionary = _bindings[first_action]
		for second_index in range(first_index + 1, BINDING_ACTIONS.size()):
			var second_action := BINDING_ACTIONS[second_index]
			if not _contexts_overlap(first_action, second_action):
				continue
			var second: Dictionary = _bindings[second_action]
			if first.kind == second.kind and int(first.code) == int(second.code):
				return false
	return true


func _apply_all_bindings() -> void:
	for action in BINDING_ACTIONS:
		_apply_binding(action, _bindings[action])


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)


func _apply_binding(action: String, binding: Dictionary) -> void:
	_ensure_action(action)
	if binding.kind == "mouse":
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = int(binding.code) as MouseButton
		InputMap.action_add_event(action, mouse_event)
	else:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(binding.code)
		InputMap.action_add_event(action, key_event)


func _apply_non_display_settings() -> void:
	if AudioServer.get_bus_count() > 0:
		AudioServer.set_bus_mute(0, master_volume <= 0.0)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func _apply_display(mode: String, target_resolution: Vector2i) -> void:
	if DisplayServer.get_name().contains("headless"):
		return
	var target_screen := get_active_screen()
	if mode == "fullscreen":
		DisplayServer.window_set_current_screen(target_screen)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_current_screen(target_screen)
		DisplayServer.window_set_size(target_resolution)
		_center_window_on_screen(target_screen)


func _center_window_on_screen(screen: int) -> void:
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var decorated_size := DisplayServer.window_get_size_with_decorations()
	var decorated_position := _centered_decorated_position(usable_rect, decorated_size)
	var decoration_offset := DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()
	DisplayServer.window_set_position(decorated_position + decoration_offset)


static func _centered_decorated_position(usable_rect: Rect2i, decorated_size: Vector2i) -> Vector2i:
	var free_space := usable_rect.size - decorated_size
	return usable_rect.position + Vector2i(maxi(0, free_space.x / 2), maxi(0, free_space.y / 2))


func _save() -> Error:
	DirAccess.make_dir_recursive_absolute(_settings_path.get_base_dir())
	var config := ConfigFile.new()
	config.set_value("meta", "schema_version", SETTINGS_SCHEMA)
	for action in BINDING_ACTIONS:
		var binding: Dictionary = _bindings[action]
		config.set_value("binding_types", action, binding.kind)
		config.set_value("bindings", action, int(binding.code))
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("input", "invert_y", invert_y)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "width", resolution.x)
	config.set_value("display", "height", resolution.y)
	return config.save(_settings_path)
