class_name FoundationTheme
extends RefCounted


static func panel(background: Color, border: Color = Color("344957"), radius: int = 7, padding: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", Color("e8eef1"))
	theme.set_color("font_color", "Button", Color("e8eef1"))
	theme.set_color("font_hover_color", "Button", Color("ffffff"))
	theme.set_color("font_pressed_color", "Button", Color("d8f4ff"))
	theme.set_color("font_disabled_color", "Button", Color("82919a"))
	theme.set_color("font_color", "LineEdit", Color("e8eef1"))
	theme.set_color("font_placeholder_color", "LineEdit", Color("8297a4"))
	theme.set_stylebox("panel", "PanelContainer", panel(Color("101a23")))
	theme.set_stylebox("normal", "Button", panel(Color("16242e"), Color("314653"), 6, 10))
	theme.set_stylebox("hover", "Button", panel(Color("203542"), Color("4c7b8d"), 6, 10))
	theme.set_stylebox("pressed", "Button", panel(Color("0f2f3d"), Color("58b9d3"), 6, 10))
	theme.set_stylebox("disabled", "Button", panel(Color("12191f"), Color("27323a"), 6, 10))
	var focus := panel(Color(0, 0, 0, 0), Color("64d4ef"), 6, 8)
	focus.set_border_width_all(2)
	for control_type in ["Button", "OptionButton", "LineEdit", "CheckButton", "HSlider"]:
		theme.set_stylebox("focus", control_type, focus)
	theme.set_stylebox("normal", "LineEdit", panel(Color("0b141b"), Color("344957"), 6, 10))
	theme.set_stylebox("normal", "OptionButton", panel(Color("16242e"), Color("314653"), 6, 10))
	theme.set_constant("separation", "VBoxContainer", 9)
	theme.set_constant("separation", "HBoxContainer", 10)
	return theme
