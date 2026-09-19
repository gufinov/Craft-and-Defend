class_name ArmorSilhouette
extends Control

## Original code-drawn character guide for the inventory armor loadout. It is a
## presentation aid only; authoritative equipment state belongs to Inventory.

const GUIDE_COLOR := Color("365c6a")
const FIGURE_COLOR := Color("91d8e8")
const ACCENT_COLOR := Color("d8f6ff")


func _init() -> void:
	custom_minimum_size = Vector2(170, 390)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.48)
	var scale_factor := minf(size.x / 190.0, size.y / 430.0)
	var head_center := center + Vector2(0, -135) * scale_factor
	var head_radius := 24.0 * scale_factor
	var shoulder_y := center.y - 92.0 * scale_factor
	var hip_y := center.y + 42.0 * scale_factor
	var hand_y := center.y + 35.0 * scale_factor
	var foot_y := center.y + 172.0 * scale_factor

	draw_circle(center, 88.0 * scale_factor, Color(GUIDE_COLOR, 0.12))
	draw_arc(center, 88.0 * scale_factor, 0.0, TAU, 64, Color(GUIDE_COLOR, 0.65), 2.0 * scale_factor, true)
	draw_line(Vector2(center.x, head_center.y - head_radius - 12.0), Vector2(center.x, foot_y + 12.0), Color(GUIDE_COLOR, 0.45), 1.0, true)

	draw_circle(head_center, head_radius, FIGURE_COLOR)
	var torso := PackedVector2Array([
		Vector2(center.x - 38.0 * scale_factor, shoulder_y),
		Vector2(center.x + 38.0 * scale_factor, shoulder_y),
		Vector2(center.x + 28.0 * scale_factor, hip_y),
		Vector2(center.x - 28.0 * scale_factor, hip_y),
	])
	draw_colored_polygon(torso, FIGURE_COLOR)

	var left_shoulder := Vector2(center.x - 31.0 * scale_factor, shoulder_y + 8.0 * scale_factor)
	var right_shoulder := Vector2(center.x + 31.0 * scale_factor, shoulder_y + 8.0 * scale_factor)
	var left_hand := Vector2(center.x - 78.0 * scale_factor, hand_y)
	var right_hand := Vector2(center.x + 78.0 * scale_factor, hand_y)
	draw_line(left_shoulder, left_hand, FIGURE_COLOR, 15.0 * scale_factor, true)
	draw_line(right_shoulder, right_hand, FIGURE_COLOR, 15.0 * scale_factor, true)
	draw_circle(left_hand, 8.0 * scale_factor, ACCENT_COLOR)
	draw_circle(right_hand, 8.0 * scale_factor, ACCENT_COLOR)

	var left_hip := Vector2(center.x - 18.0 * scale_factor, hip_y - 2.0 * scale_factor)
	var right_hip := Vector2(center.x + 18.0 * scale_factor, hip_y - 2.0 * scale_factor)
	var left_foot := Vector2(center.x - 45.0 * scale_factor, foot_y)
	var right_foot := Vector2(center.x + 45.0 * scale_factor, foot_y)
	draw_line(left_hip, left_foot, FIGURE_COLOR, 18.0 * scale_factor, true)
	draw_line(right_hip, right_foot, FIGURE_COLOR, 18.0 * scale_factor, true)
	draw_line(left_foot + Vector2(-12.0, 0.0) * scale_factor, left_foot + Vector2(10.0, 0.0) * scale_factor, ACCENT_COLOR, 7.0 * scale_factor, true)
	draw_line(right_foot + Vector2(-10.0, 0.0) * scale_factor, right_foot + Vector2(12.0, 0.0) * scale_factor, ACCENT_COLOR, 7.0 * scale_factor, true)

	var chest_center := Vector2(center.x, center.y - 36.0 * scale_factor)
	draw_arc(chest_center, 25.0 * scale_factor, PI * 0.12, PI * 0.88, 20, ACCENT_COLOR, 2.0 * scale_factor, true)
	draw_string(ThemeDB.fallback_font, Vector2(center.x - 42.0 * scale_factor, size.y - 8.0), "CHARACTER", HORIZONTAL_ALIGNMENT_CENTER, 84.0 * scale_factor, 12.0 * scale_factor, Color("6f9daa"))
