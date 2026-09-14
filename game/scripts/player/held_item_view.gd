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
	if item.has("places_block"):
		_build_block(int(item.places_block))
	elif item_id in ["workbench", "furnace", "stone_pick", "wood_axe"]:
		_build_reference_item(item_id, item_id in ["stone_pick", "wood_axe"])
	elif str(item.get("tool_kind", "")) == "axe":
		_build_axe()
	elif int(item.get("pick_tier", 0)) > 0:
		_build_pick(item_id)
	elif str(item.get("weapon", {}).get("kind", "")) == "melee":
		_build_sword()
	else:
		_build_carried_item(item_id)
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


func _build_block(voxel_id: int) -> void:
	_base_position = Vector3(0.46, -0.48, -0.88)
	_base_rotation = Vector3(-0.18, 0.45, 0.08)
	var texture_path := ""
	if voxel_id > 0 and voxel_id < WorldAdapter.BLOCK_NAMES.size():
		texture_path = "res://assets/blocks/%s.svg" % WorldAdapter.BLOCK_NAMES[voxel_id]
	var color: Color = WorldAdapter.BLOCK_COLORS[voxel_id] if voxel_id >= 0 and voxel_id < WorldAdapter.BLOCK_COLORS.size() else Color("b88954")
	_add_box(Vector3(0.34, 0.34, 0.34), Vector3.ZERO, color, texture_path)


func _build_pick(item_id: String) -> void:
	_base_position = Vector3(0.43, -0.28, -0.72)
	_base_rotation = Vector3(0.18, 0.08, -0.42)
	_add_box(Vector3(0.08, 0.72, 0.08), Vector3(0.0, -0.08, 0.0), Color("8b5a32"))
	var head_color := Color("b7bdc4")
	if item_id == "wood_pick":
		head_color = Color("a87142")
	elif item_id == "iron_pick":
		head_color = Color("d9e0e5")
	_add_box(Vector3(0.58, 0.10, 0.10), Vector3(0.0, 0.28, 0.0), head_color)


func _build_axe() -> void:
	_base_position = Vector3(0.44, -0.29, -0.72)
	_base_rotation = Vector3(0.16, 0.06, -0.38)
	_add_box(Vector3(0.08, 0.72, 0.08), Vector3(0.0, -0.08, 0.0), Color("8b5a32"))
	_add_box(Vector3(0.34, 0.24, 0.10), Vector3(-0.10, 0.25, 0.0), Color("b8bec4"))
	_add_box(Vector3(0.12, 0.34, 0.12), Vector3(-0.22, 0.22, 0.0), Color("d2d7db"))


func _build_sword() -> void:
	_base_position = Vector3(0.43, -0.24, -0.70)
	_base_rotation = Vector3(0.12, 0.04, -0.32)
	_add_box(Vector3(0.09, 0.30, 0.09), Vector3(0.0, -0.27, 0.0), Color("7a4a2a"))
	_add_box(Vector3(0.42, 0.07, 0.10), Vector3(0.0, -0.08, 0.0), Color("d4a63f"))
	_add_box(Vector3(0.10, 0.78, 0.06), Vector3(0.0, 0.34, 0.0), Color("dce8ed"))


func _build_carried_item(item_id: String) -> void:
	_base_position = Vector3(0.46, -0.46, -0.86)
	_base_rotation = Vector3(-0.12, 0.35, 0.04)
	var sprite := Sprite3D.new()
	sprite.texture = ItemIconCatalog.texture_for(item_id)
	sprite.pixel_size = 0.00135
	sprite.no_depth_test = true
	sprite.shaded = false
	model_root.add_child(sprite)


func _build_reference_item(item_id: String, raised: bool) -> void:
	_base_position = Vector3(0.43, -0.28, -0.78) if raised else Vector3(0.46, -0.47, -0.90)
	_base_rotation = Vector3(0.05, 0.0, -0.16) if raised else Vector3(-0.08, 0.0, 0.02)
	var sprite := Sprite3D.new()
	sprite.texture = ItemIconCatalog.world_reference_texture_for(item_id)
	sprite.pixel_size = 0.00105 if raised else 0.00082
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	model_root.add_child(sprite)


func _add_box(size: Vector3, offset: Vector3, color: Color, texture_path: String = "") -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.no_depth_test = true
	material.render_priority = 1
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model_root.add_child(mesh_instance)
