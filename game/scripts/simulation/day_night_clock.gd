class_name DayNightClock
extends RefCounted

const CONFIG_PATH := "res://data/world.json"
const DEFAULT_DAY_LENGTH_SECONDS := 1200.0
const DEFAULT_INITIAL_PHASE := 8.0 / 24.0
const MINUTES_PER_DAY := 24 * 60
const SUNRISE_MINUTES := 8 * 60
const SUNSET_MINUTES := 20 * 60

var day_length_seconds := DEFAULT_DAY_LENGTH_SECONDS
var phase := DEFAULT_INITIAL_PHASE
var day_index := 1
var cycle_enabled := true
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
	cycle_enabled = bool(snapshot.get("cycle_enabled", true))
	return true


func advance(delta: float, paused: bool) -> bool:
	if paused or not cycle_enabled or delta <= 0.0:
		return false
	var total_phase := phase + delta / day_length_seconds
	if total_phase >= 1.0:
		day_index += floori(total_phase)
	phase = fposmod(total_phase, 1.0)
	return true


func snapshot() -> Dictionary:
	return {"phase": phase, "day_index": day_index, "day_length_seconds": day_length_seconds, "cycle_enabled": cycle_enabled}


func set_time_hhmm(value: String) -> Dictionary:
	var compact := value.strip_edges().replace(":", "")
	if compact.length() != 4:
		return {"ok": false, "reason": "TIME_FORMAT", "expected": "HHMM"}
	for index in range(compact.length()):
		var codepoint := compact.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return {"ok": false, "reason": "TIME_FORMAT", "expected": "HHMM"}
	var hour := compact.substr(0, 2).to_int()
	var minute := compact.substr(2, 2).to_int()
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return {"ok": false, "reason": "TIME_RANGE", "expected": "0000–2359"}
	phase = float(hour * 60 + minute) / float(MINUTES_PER_DAY)
	return {"ok": true, "reason": "OK", "time": time_input_text(), "phase": phase}


func set_cycle_enabled(enabled: bool) -> void:
	cycle_enabled = enabled


func current_minutes() -> int:
	return floori(phase * float(MINUTES_PER_DAY)) % MINUTES_PER_DAY


func time_input_text() -> String:
	var minutes := current_minutes()
	return "%02d%02d" % [floori(float(minutes) / 60.0), minutes % 60]


func time_label() -> String:
	var minutes := current_minutes()
	return "Day %d · %02d:%02d" % [day_index, floori(float(minutes) / 60.0), minutes % 60]


func period_label() -> String:
	var minutes := current_minutes()
	if minutes >= 7 * 60 and minutes < 9 * 60:
		return "Sunrise"
	if minutes >= 9 * 60 and minutes < 18 * 60:
		return "Day"
	if minutes >= 18 * 60 and minutes < 21 * 60:
		return "Sunset"
	return "Night"


func sun_direction() -> Vector3:
	var sunrise_phase := float(SUNRISE_MINUTES) / float(MINUTES_PER_DAY)
	var solar_angle := fposmod(phase - sunrise_phase, 1.0) * TAU
	return Vector3(0.0, sin(solar_angle), -cos(solar_angle)).normalized()


func sun_is_visible() -> bool:
	return sun_direction().y >= -0.02


func apply_visuals(environment: Environment, sun: DirectionalLight3D) -> void:
	if environment == null or sun == null:
		return
	var to_sun := sun_direction()
	var solar_height := to_sun.y
	var daylight := clampf((solar_height + 0.08) / 0.58, 0.0, 1.0)
	var twilight := clampf(1.0 - absf(solar_height) / 0.30, 0.0, 1.0)
	var night_color := Color("101b36")
	var day_color := Color("82bde3")
	var twilight_color := Color("d98255") if solar_height >= 0.0 else Color("67466f")
	var sky_color := night_color.lerp(day_color, daylight)
	environment.background_color = sky_color.lerp(twilight_color, twilight * (0.60 if solar_height >= 0.0 else 0.30))
	environment.ambient_light_color = Color("9badd0").lerp(Color("c8dded"), daylight)
	environment.ambient_light_energy = lerpf(0.50, 0.72, daylight)
	var solar_angle_degrees := rad_to_deg(atan2(to_sun.y, -to_sun.z))
	sun.rotation_degrees = Vector3(solar_angle_degrees - 180.0, 0.0, 0.0)
	sun.light_color = Color("9db3df").lerp(Color.WHITE, daylight)
	sun.light_energy = lerpf(0.08, 1.15, daylight)
