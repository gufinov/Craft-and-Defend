class_name HeldItemView
extends Node3D

## First-person held-item presentation.
##
## Model (owner direction, 2026-09-18): treat the item art as a square whose
## bottom-left corner is the hand. Tools are drawn pointing north-east from that
## corner. The corner is the hinge; a strike rotates the whole square
## counter-clockwise about it so the head sweeps left toward the crosshair.
## The hinge sits in the lower-right of the view. Sprite size is normalised from
## the measured art region, so atlases of different resolution share one scale.

## Height of the tallest raised tool, in camera units at HELD_DEPTH.
const TOOL_HEIGHT := 0.62
## Height of low-held items (blocks, materials, stations, ammunition).
const LOW_HEIGHT := 0.46
const HELD_DEPTH := 0.90
## Hinge placement as fractions of the visible half-extents at HELD_DEPTH.
## X is clamped so the swing still reaches the crosshair on ultrawide displays.
## Owner ultrawide playtest 2026-09-18: the first values (0.58 / 0.50 / 0.95)
## put the hand about one block too far right; these sit it one block inward.
const HINGE_RIGHT_FRACTION := 0.48
const HINGE_RIGHT_MIN := 0.45
const HINGE_RIGHT_MAX := 0.78
## Tools seat their handle at the screen base (owner sketch); low-held items
## stay above the hotbar as accepted in P3H.2.
const TOOL_HINGE_DOWN_FRACTION := 0.92
const LOW_HINGE_DOWN_FRACTION := 0.70
## Rest tilt of raised tools (radians, counter-clockwise). Art already points NE.
const TOOL_REST_ROTATION := 0.0
const LOW_REST_ROTATION := 0.0
## Strike (owner direction, round 3): a keyframed path, not a spin about the
## hinge. From rest the tool snaps toward the crosshair but stops short so the
## view stays clear, whips down and left, vanishes behind the hotbar left of
## centre, then rises back to rest. Offsets are fractions of the visible
## half-extents at HELD_DEPTH (x right, y up) added to the rest hinge position;
## rotations are counter-clockwise radians about the hinge.
const TOOL_SWING_KEYS: Array[Dictionary] = [
	{"seconds": 0.05, "offset": Vector2(-0.22, 0.42), "rotation": 0.55},
	{"seconds": 0.09, "offset": Vector2(-0.95, -1.05), "rotation": 2.2},
	{"seconds": 0.16, "offset": Vector2(0.0, 0.0), "rotation": 0.0},
]
## Largest rotation reached during the strike; reported for diagnostics.
const TOOL_SWING_ARC_RADIANS := 2.2
const PLACE_NUDGE_TRAVEL := Vector3(-0.03, 0.05, -0.10)

var registry: ContentRegistry
## The hinge. Its origin is the hand; the sprite hangs from it.
var model_root: Node3D
var current_item_id := ""
var _raised := false
var _use_tween: Tween
var _sprite: Sprite3D
var _hinge_position := Vector3.ZERO
var _rest_rotation := 0.0


func _init(content_registry: ContentRegistry) -> void:
	registry = content_registry


func _ready() -> void:
	model_root = Node3D.new()
	model_root.name = "HeldHinge"
	add_child(model_root)
	get_viewport().size_changed.connect(_update_hinge)
	hide()


func present(item_id: String) -> void:
	if item_id == current_item_id:
		return
	current_item_id = item_id
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	_sprite = null
	if item_id.is_empty():
		hide()
		return
	var item := registry.item(item_id)
	if item.is_empty():
		hide()
		return
	_raised = str(item.get("tool_kind", "")) == "axe" \
		or int(item.get("pick_tier", 0)) > 0 \
		or str(item.get("weapon", {}).get("kind", "")) == "melee"
	_build_reference_item(item_id, _raised)
	_update_hinge()
	show()


func set_gameplay_visible(gameplay_visible: bool) -> void:
	visible = gameplay_visible and not current_item_id.is_empty()


func play_use() -> void:
	if not visible or model_root == null:
		return
	if _use_tween != null and _use_tween.is_valid():
		_use_tween.kill()
	model_root.position = _hinge_position
	model_root.rotation = Vector3(0.0, 0.0, _rest_rotation)
	_use_tween = create_tween()
	if _raised:
		var extents := _view_half_extents()
		for index in range(TOOL_SWING_KEYS.size()):
			var key := TOOL_SWING_KEYS[index]
			var offset: Vector2 = key.offset
			var target := _hinge_position + Vector3(offset.x * extents.x, offset.y * extents.y, 0.0)
			var last := index == TOOL_SWING_KEYS.size() - 1
			_use_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT if last else Tween.EASE_OUT)
			_use_tween.tween_property(model_root, "position", target, float(key.seconds))
			_use_tween.parallel().tween_property(model_root, "rotation:z", _rest_rotation + float(key.rotation), float(key.seconds))
	else:
		_use_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_use_tween.tween_property(model_root, "position", _hinge_position + PLACE_NUDGE_TRAVEL, 0.08)
		_use_tween.set_ease(Tween.EASE_IN_OUT)
		_use_tween.tween_property(model_root, "position", _hinge_position, 0.12)


func _build_reference_item(item_id: String, raised: bool) -> void:
	var texture := ItemIconCatalog.world_reference_texture_for(item_id)
	if texture == null:
		return
	var region_size := texture.get_size()
	if region_size.x <= 0.0 or region_size.y <= 0.0:
		return
	var target_height := TOOL_HEIGHT if raised else LOW_HEIGHT
	var pixel_size := target_height / region_size.y
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = pixel_size
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# Sprite3D centres on its origin; offset it so the art's bottom-left corner
	# lies on the hinge origin. Rotating the hinge then swings about the hand.
	sprite.position = Vector3(region_size.x * pixel_size * 0.5, region_size.y * pixel_size * 0.5, 0.0)
	model_root.add_child(sprite)
	_sprite = sprite
	_rest_rotation = TOOL_REST_ROTATION if raised else LOW_REST_ROTATION


## Visible half-width and half-height at HELD_DEPTH for the current camera/viewport.
func _view_half_extents() -> Vector2:
	var camera := get_parent() as Camera3D
	var half_height := 0.5
	var aspect := 16.0 / 9.0
	if camera != null:
		half_height = HELD_DEPTH * tan(deg_to_rad(camera.fov) * 0.5)
		var view_size := get_viewport().get_visible_rect().size
		if view_size.y > 0.0:
			aspect = view_size.x / view_size.y
	return Vector2(half_height * aspect, half_height)


## Places the hinge in the lower-right of the current view at HELD_DEPTH.
func _update_hinge() -> void:
	var extents := _view_half_extents()
	var half_width := extents.x
	var half_height := extents.y
	var right := clampf(half_width * HINGE_RIGHT_FRACTION, HINGE_RIGHT_MIN, HINGE_RIGHT_MAX)
	var down := TOOL_HINGE_DOWN_FRACTION if _raised else LOW_HINGE_DOWN_FRACTION
	_hinge_position = Vector3(right, -half_height * down, -HELD_DEPTH)
	if _use_tween != null and _use_tween.is_valid():
		_use_tween.kill()
	model_root.position = _hinge_position
	model_root.rotation = Vector3(0.0, 0.0, _rest_rotation)


func debug_presentation() -> Dictionary:
	var sprite_size := Vector2.ZERO
	if _sprite != null and _sprite.texture != null:
		sprite_size = _sprite.texture.get_size() * _sprite.pixel_size
	return {
		"hinge_model": true,
		"raised": _raised,
		"hinge_position": _hinge_position,
		"sprite_size": sprite_size,
		"tool_height": TOOL_HEIGHT,
		"low_height": LOW_HEIGHT,
		"tool_swing_arc_radians": TOOL_SWING_ARC_RADIANS,
		"measured_region": ItemIconCatalog.is_measured(current_item_id),
	}
