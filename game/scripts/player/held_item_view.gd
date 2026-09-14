class_name HeldItemView
extends Node3D

var registry: ContentRegistry
var model_root: Node3D
var current_item_id := ""
var _base_position := Vector3.ZERO
var _base_rotation := Vector3.ZERO
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
	var raised := str(item.get("tool_kind", "")) == "axe" \
		or int(item.get("pick_tier", 0)) > 0 \
		or str(item.get("weapon", {}).get("kind", "")) == "melee"
	_build_reference_item(item_id, raised)
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
	_use_tween.tween_property(model_root, "rotation:z", _base_rotation.z + 0.72, 0.09)
	_use_tween.parallel().tween_property(model_root, "position", _base_position + Vector3(-0.08, 0.04, -0.12), 0.09)
	_use_tween.tween_property(model_root, "rotation:z", _base_rotation.z, 0.13)
	_use_tween.parallel().tween_property(model_root, "position", _base_position, 0.13)


func _build_reference_item(item_id: String, raised: bool) -> void:
	_base_position = Vector3(0.43, -0.29, -0.78) if raised else Vector3(0.46, -0.49, -0.90)
	_base_rotation = Vector3(0.05, 0.0, -0.16) if raised else Vector3(-0.08, 0.0, 0.02)
	var sprite := Sprite3D.new()
	sprite.texture = ItemIconCatalog.world_reference_texture_for(item_id)
	sprite.pixel_size = 0.00225 if raised else 0.00180
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	model_root.add_child(sprite)
