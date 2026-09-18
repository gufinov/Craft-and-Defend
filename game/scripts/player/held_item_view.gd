class_name HeldItemView
extends Node3D

const TOOL_BASE_POSITION := Vector3(0.78, -0.48, -0.82)
const TOOL_BASE_ROTATION := Vector3(0.03, 0.0, -0.24)
const TOOL_PIXEL_SIZE := 0.00340
const LOW_BASE_POSITION := Vector3(0.78, -0.48, -0.90)
const LOW_BASE_ROTATION := Vector3(-0.05, 0.0, 0.02)
const LOW_PIXEL_SIZE := 0.00340
const TOOL_SWING_ARC_RADIANS := 1.45
const TOOL_SWING_TRAVEL := Vector3(-0.18, 0.11, -0.14)
const PLACE_NUDGE_TRAVEL := Vector3(-0.03, 0.05, -0.10)

var registry: ContentRegistry
var model_root: Node3D
var current_item_id := ""
var _base_position := Vector3.ZERO
var _base_rotation := Vector3.ZERO
var _raised := false
var _use_tween: Tween


func _init(content_registry: ContentRegistry) -> void:
	registry = content_registry


func _ready() -> void:
	model_root = Node3D.new()
	model_root.name = "HeldModel"
	add_child(model_root)
	hide()


func present(item_id: String) -> void:
	if item_id == current_item_id:
		return
	current_item_id = item_id
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
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
	model_root.position = _base_position
	model_root.rotation = _base_rotation
	show()


func set_gameplay_visible(gameplay_visible: bool) -> void:
	visible = gameplay_visible and not current_item_id.is_empty()


func play_use() -> void:
	if not visible or model_root == null:
		return
	if _use_tween != null and _use_tween.is_valid():
		_use_tween.kill()
	model_root.position = _base_position
	model_root.rotation = _base_rotation
	_use_tween = create_tween()
	if _raised:
		_use_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_use_tween.tween_property(model_root, "rotation:z", _base_rotation.z + TOOL_SWING_ARC_RADIANS, 0.14)
		_use_tween.parallel().tween_property(model_root, "position", _base_position + TOOL_SWING_TRAVEL, 0.14)
		_use_tween.set_ease(Tween.EASE_IN_OUT)
		_use_tween.tween_property(model_root, "rotation:z", _base_rotation.z, 0.18)
		_use_tween.parallel().tween_property(model_root, "position", _base_position, 0.18)
	else:
		_use_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_use_tween.tween_property(model_root, "position", _base_position + PLACE_NUDGE_TRAVEL, 0.08)
		_use_tween.set_ease(Tween.EASE_IN_OUT)
		_use_tween.tween_property(model_root, "position", _base_position, 0.12)


func _build_reference_item(item_id: String, raised: bool) -> void:
	_base_position = TOOL_BASE_POSITION if raised else LOW_BASE_POSITION
	_base_rotation = TOOL_BASE_ROTATION if raised else LOW_BASE_ROTATION
	var sprite := Sprite3D.new()
	sprite.texture = ItemIconCatalog.world_reference_texture_for(item_id)
	sprite.pixel_size = TOOL_PIXEL_SIZE if raised else LOW_PIXEL_SIZE
	sprite.no_depth_test = true
	sprite.shaded = false
	# Source tools point toward the outer-right edge. Mirroring every raised item
	# gives the shared first-person frame an inward-facing blade/head while keeping
	# the handle seated at the lower-right screen edge.
	sprite.flip_h = raised
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	model_root.add_child(sprite)


func debug_presentation() -> Dictionary:
	return {
		"raised": _raised,
		"tool_position": TOOL_BASE_POSITION,
		"tool_pixel_size": TOOL_PIXEL_SIZE,
		"low_position": LOW_BASE_POSITION,
		"low_pixel_size": LOW_PIXEL_SIZE,
		"tool_swing_arc_radians": TOOL_SWING_ARC_RADIANS,
		"raised_flip_h": true,
	}
