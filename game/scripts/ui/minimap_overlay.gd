class_name MinimapOverlay
extends Control

## P4E minimap: a top-right map of the generated terrain around the player,
## coloured by height (water, grass shades, rock), with the player heading,
## the home clearing, the placed Core of Power and the enemy base. M toggles
## a full-map view. Heights come from the generator (topology of the
## generated world; player edits are not drawn) and are cached per column,
## so the image is rebuilt in row slices across frames without hitching.

const MINI_BLOCKS := 176
const MINI_SIZE := 220.0
const ROWS_PER_FRAME := 24
const REBUILD_SECONDS := 0.5
const MARGIN := 18.0

var generator: P1TerrainGenerator
var player: Node3D
var workstations: WorkstationService
var full_map := false
## CoasterCraft hides the enemy base (no raids in that mode).
var show_enemy_base := true

var _heights: Dictionary = {}
var _texture_rect: TextureRect
var _marker_layer: Control
var _frame: Panel
var _title: Label
var _image: Image
var _texture: ImageTexture
var _origin := Vector2i.ZERO
var _blocks := MINI_BLOCKS
var _next_row := 0
var _rebuild_timer := 0.0
var _full_built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.11, 0.78)
	style.border_color = Color("9fd8e8")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	_texture_rect = TextureRect.new()
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.add_child(_texture_rect)
	_marker_layer = Control.new()
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.draw.connect(_draw_markers)
	_frame.add_child(_marker_layer)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", Color("9fd8e8"))
	_frame.add_child(_title)
	_layout()
	# Re-lay when the window is resized or maximised (the ultrawide screenshot
	# had the map floating where the 1280-wide corner used to be).
	get_viewport().size_changed.connect(_layout)


func configure(terrain_generator: P1TerrainGenerator, player_node: Node3D, station_service: WorkstationService) -> void:
	generator = terrain_generator
	player = player_node
	workstations = station_service
	_heights.clear()
	_full_built = false
	_start_rebuild()


func toggle_full_map() -> void:
	full_map = not full_map
	_layout()
	_start_rebuild()


func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	if full_map:
		var side := minf(viewport_size.y - 60.0, viewport_size.x - 60.0)
		_frame.size = Vector2(side, side)
		_frame.position = (viewport_size - _frame.size) * 0.5
		_title.text = "WORLD MAP · M closes"
	else:
		_frame.size = Vector2(MINI_SIZE, MINI_SIZE)
		# Top-right corner (owner 2026-09-19); the HUD text wraps left of it.
		_frame.position = Vector2(viewport_size.x - MINI_SIZE - MARGIN, MARGIN)
		_title.text = "MAP · M for the world map"
	_texture_rect.position = Vector2(4, 4)
	_texture_rect.size = _frame.size - Vector2(8, 8)
	_marker_layer.position = _texture_rect.position
	_marker_layer.size = _texture_rect.size
	_title.position = Vector2(8, _frame.size.y - 20.0)


func _start_rebuild() -> void:
	if generator == null:
		return
	if full_map:
		_blocks = maxi(generator.bounds_size.x, generator.bounds_size.z)
		_origin = Vector2i(generator.bounds_min.x, generator.bounds_min.z)
	else:
		_blocks = MINI_BLOCKS
		var centre := _player_column()
		_origin = Vector2i(centre.x - MINI_BLOCKS / 2, centre.y - MINI_BLOCKS / 2)
	if _image == null or _image.get_width() != _blocks:
		_image = Image.create(_blocks, _blocks, false, Image.FORMAT_RGBA8)
		_image.fill(Color(0.05, 0.08, 0.11, 1.0))
		_texture = ImageTexture.create_from_image(_image)
		_texture_rect.texture = _texture
	_next_row = 0


func _player_column() -> Vector2i:
	if not is_instance_valid(player):
		return Vector2i.ZERO
	return Vector2i(floori(player.global_position.x), floori(player.global_position.z))


func _process(delta: float) -> void:
	if generator == null or not visible:
		return
	if _next_row < _blocks:
		_fill_rows()
	elif full_map:
		_full_built = true
	_rebuild_timer -= delta
	if _rebuild_timer <= 0.0 and not full_map:
		_rebuild_timer = REBUILD_SECONDS
		var centre := _player_column()
		var wanted := Vector2i(centre.x - MINI_BLOCKS / 2, centre.y - MINI_BLOCKS / 2)
		if (wanted - _origin).length() >= 4.0:
			_start_rebuild()
	_marker_layer.queue_redraw()


func _fill_rows() -> void:
	var last := mini(_blocks, _next_row + ROWS_PER_FRAME)
	for row in range(_next_row, last):
		var z := _origin.y + row
		for column in range(_blocks):
			var x := _origin.x + column
			_image.set_pixel(column, row, _colour_at(x, z))
	_next_row = last
	_texture.update(_image)


func _height_at(x: int, z: int) -> int:
	var key := Vector2i(x, z)
	if _heights.has(key):
		return int(_heights[key])
	var value := generator.surface_height(x, z)
	_heights[key] = value
	return value


func _colour_at(x: int, z: int) -> Color:
	var minimum := generator.bounds_min
	var maximum := generator.bounds_min + generator.bounds_size
	if x < minimum.x or x >= maximum.x or z < minimum.z or z >= maximum.z:
		return Color(0.05, 0.08, 0.11, 1.0)
	var height := _height_at(x, z)
	if generator.is_water_column(x, z):
		return Color(0.20, 0.42, 0.85).darkened(clampf(float(-1 - height) * 0.08, 0.0, 0.4))
	var rock_surface := int(generator.settings.get("rock_surface_y", 12))
	if height >= rock_surface:
		var snow := clampf(float(height - rock_surface) / 12.0, 0.0, 1.0)
		return Color(0.48, 0.50, 0.54).lerp(Color(0.92, 0.94, 0.96), snow)
	var shade := clampf((float(height) + 2.0) / float(rock_surface + 2), 0.0, 1.0)
	var grass := Color(0.26, 0.52, 0.22).lerp(Color(0.62, 0.72, 0.30), shade)
	# Contour lines every 4 blocks help the eye read slopes.
	if posmod(height, 4) == 0:
		grass = grass.darkened(0.12)
	return grass


func _to_map(column: Vector2i) -> Vector2:
	var scale := _texture_rect.size.x / float(_blocks)
	return Vector2(float(column.x - _origin.x) + 0.5, float(column.y - _origin.y) + 0.5) * scale


func _draw_markers() -> void:
	if generator == null or not is_instance_valid(player):
		return
	var scale := _texture_rect.size.x / float(_blocks)
	# Home clearing.
	var home_data: Array = generator.settings.get("safe_clearing_center", [0, 40])
	var home := _to_map(Vector2i(int(home_data[0]), int(home_data[1])))
	_marker_layer.draw_circle(home, maxf(3.0, scale * 2.0), Color("9fd8e8"))
	# Enemy base.
	if show_enemy_base:
		var base := _to_map(Vector2i(generator.enemy_base.x, generator.enemy_base.y))
		_marker_layer.draw_circle(base, maxf(4.0, scale * 3.0), Color("ff3030"))
	# Placed cores.
	if workstations != null:
		for record: Dictionary in workstations.stations.values():
			var entity_id := str(record.get("entity_id", ""))
			if entity_id == "core_of_power" or entity_id == "enemy_core":
				var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
				_marker_layer.draw_circle(_to_map(Vector2i(anchor.x + 1, anchor.z + 1)), maxf(4.0, scale * 3.0), Color("4c9dff") if entity_id == "core_of_power" else Color("ff3030"))
	# Player arrow along its heading (yaw about y; forward is -z).
	var position := _to_map(_player_column())
	var yaw := player.rotation.y
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	var tip := position + forward * 9.0
	var left := position - forward * 5.0 + side * 5.0
	var right := position - forward * 5.0 - side * 5.0
	_marker_layer.draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1.0, 1.0, 1.0, 0.95))
	_marker_layer.draw_polyline(PackedVector2Array([tip, left, right, tip]), Color(0.1, 0.1, 0.1, 0.9), 1.0)
