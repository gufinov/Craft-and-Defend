class_name DayNightClock
extends RefCounted

const CONFIG_PATH := "res://data/world.json"
const DEFAULT_DAY_LENGTH_SECONDS := 1200.0
const DEFAULT_INITIAL_PHASE := 0.25

var day_length_seconds := DEFAULT_DAY_LENGTH_SECONDS
var phase := DEFAULT_INITIAL_PHASE
var day_index := 1
var load_error := ""


func _init(config_path: String = CONFIG_PATH) -> void:
	var result := load_config(config_path)
	if not result.get("ok", false):
		load_error = str(result.get("reason", "CLOCK_CONFIG_FAILED"))


func load_config(path: String = CONFIG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "CLOCK_CONFIG_MISSING", "path": path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "reason": "CLOCK_CONFIG_INVALID"}
	var configured_length := float(parsed.get("day_length_seconds", 0.0))
	var configured_phase := float(parsed.get("initial_day_phase", -1.0))
	if configured_length <= 0.0 or configured_phase < 0.0 or configured_phase >= 1.0:
		return {"ok": false, "reason": "CLOCK_CONFIG_RANGE"}
	day_length_seconds = configured_length
	phase = configured_phase
	day_index = 1
	load_error = ""
	return {"ok": true, "day_length_seconds": day_length_seconds, "phase": phase}


func restore(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return true
	var restored_phase := float(snapshot.get("phase", -1.0))
	var restored_day := int(snapshot.get("day_index", 0))
	if restored_phase < 0.0 or restored_phase >= 1.0 or restored_day < 1:
		return false
	phase = restored_phase
	day_index = restored_day
	return true


func advance(delta: float, paused: bool) -> bool:
	if paused or delta <= 0.0:
		return false
	var total_phase := phase + delta / day_length_seconds
	if total_phase >= 1.0:
		day_index += floori(total_phase)
	phase = fposmod(total_phase, 1.0)
	return true


func snapshot() -> Dictionary:
	return {"phase": phase, "day_index": day_index, "day_length_seconds": day_length_seconds}


func time_label() -> String:
	var minutes := floori(phase * 24.0 * 60.0) % (24 * 60)
	return "Day %d · %02d:%02d" % [day_index, floori(float(minutes) / 60.0), minutes % 60]


func period_label() -> String:
	if phase < 0.08:
		return "Dawn"
	if phase < 0.42:
		return "Day"
	if phase < 0.55:
		return "Dusk"
	if phase < 0.92:
		return "Night"
	return "Dawn"


func apply_visuals(environment: Environment, sun: DirectionalLight3D) -> void:
	if environment == null or sun == null:
		return
	var solar_height := sin(phase * TAU)
	var daylight := clampf((solar_height + 0.18) / 1.18, 0.0, 1.0)
	var night_color := Color("182744")
	var day_color := Color("91b8d4")
	environment.background_color = night_color.lerp(day_color, daylight)
	environment.ambient_light_color = Color("9badd0").lerp(Color("c8dded"), daylight)
	environment.ambient_light_energy = lerpf(0.58, 0.65, daylight)
	sun.rotation_degrees = Vector3(phase * 360.0 - 90.0, -35.0, 0.0)
	sun.light_color = Color("9db3df").lerp(Color.WHITE, daylight)
	sun.light_energy = lerpf(0.12, 1.1, daylight)
