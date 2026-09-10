class_name SettingsStore
extends RefCounted

const BINDING_ACTIONS := [
	"move_forward", "move_backward", "strafe_left", "strafe_right",
	"sprint", "crouch", "jump", "interact", "inventory", "pause",
	"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5",
	"hotbar_6", "hotbar_7", "hotbar_8", "hotbar_9", "primary", "secondary",
]

const DEFAULT_KEYS := {
	"move_forward": KEY_E,
	"move_backward": KEY_D,
	"strafe_left": KEY_S,
	"strafe_right": KEY_F,
	"sprint": KEY_A,
	"crouch": KEY_Z,
	"jump": KEY_SPACE,
	"interact": KEY_SHIFT,
	"inventory": KEY_TAB,
	"pause": KEY_ESCAPE,
	"hotbar_1": KEY_1,
	"hotbar_2": KEY_2,
	"hotbar_3": KEY_3,
	"hotbar_4": KEY_4,
	"hotbar_5": KEY_5,
	"hotbar_6": KEY_6,
	"hotbar_7": KEY_7,
	"hotbar_8": KEY_8,
	"hotbar_9": KEY_9,
}

var _settings_path: String
var _bindings: Dictionary = {}


func _init(data_root: String) -> void:
	_settings_path = data_root.path_join("settings.cfg")


func load_and_apply() -> Dictionary:
	_bindings = DEFAULT_KEYS.duplicate(true)
	var config := ConfigFile.new()
	var load_error := config.load(_settings_path)
	if load_error == OK:
		for action in DEFAULT_KEYS:
			var candidate := int(config.get_value("bindings", action, DEFAULT_KEYS[action]))
			if candidate > 0:
				_bindings[action] = candidate
	_apply_all()
	return {"ok": true, "path": _settings_path, "loaded": load_error == OK}


func rebind_key(action: String, physical_keycode: int) -> Dictionary:
	if not DEFAULT_KEYS.has(action):
		return {"ok": false, "reason": "UNKNOWN_ACTION"}
	if physical_keycode == KEY_ESCAPE:
		return {"ok": false, "reason": "ESCAPE_RESERVED"}
	for other_action in _bindings:
		if other_action != action and int(_bindings[other_action]) == physical_keycode:
			return {"ok": false, "reason": "CONFLICT", "conflict": other_action}
	_bindings[action] = physical_keycode
	_apply_key(action, physical_keycode)
	var save_error := _save()
	return {"ok": save_error == OK, "reason": "OK" if save_error == OK else "SAVE_FAILED"}


func reset_defaults() -> Dictionary:
	_bindings = DEFAULT_KEYS.duplicate(true)
	_apply_all()
	var save_error := _save()
	return {"ok": save_error == OK, "reason": "OK" if save_error == OK else "SAVE_FAILED"}


func get_keycode(action: String) -> int:
	return int(_bindings.get(action, 0))


func get_key_label(action: String) -> String:
	return OS.get_keycode_string(get_keycode(action))


func get_settings_path() -> String:
	return _settings_path


func _apply_all() -> void:
	for action in BINDING_ACTIONS:
		if action == "primary":
			_apply_mouse(action, MOUSE_BUTTON_LEFT)
		elif action == "secondary":
			_apply_mouse(action, MOUSE_BUTTON_RIGHT)
		else:
			_apply_key(action, int(_bindings[action]))


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)


func _apply_key(action: String, physical_keycode: int) -> void:
	_ensure_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, event)


func _apply_mouse(action: String, button_index: MouseButton) -> void:
	_ensure_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action, event)


func _save() -> Error:
	DirAccess.make_dir_recursive_absolute(_settings_path.get_base_dir())
	var config := ConfigFile.new()
	config.set_value("meta", "schema_version", 1)
	for action in DEFAULT_KEYS:
		config.set_value("bindings", action, int(_bindings[action]))
	return config.save(_settings_path)
