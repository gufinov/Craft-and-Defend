class_name BasicRaider
extends CharacterBody3D

signal route_finished

const MOVE_SPEED := 2.8
const GRAVITY := 14.0

var route: Array[Vector3i] = []
var route_index := 0
var active := false


func _ready() -> void:
	name = "BasicRaider"
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	collision.shape = capsule
	add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.34
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d95a4e")
	material.roughness = 0.85
	mesh.material = material
	mesh_instance.mesh = mesh
	add_child(mesh_instance)


func set_route(cells: Array) -> void:
	route.clear()
	for value in cells:
		if value is Vector3i:
			route.append(value)
	route_index = 1 if route.size() > 1 else route.size()
	active = route_index < route.size()
	if route.size() == 1:
		route_finished.emit()


func feet_cell() -> Vector3i:
	# The capsule origin sits 0.9 m above its logical feet cell. Subtracting the
	# full value can cross an integer boundary through floating-point rounding.
	return Vector3i(floori(global_position.x), floori(global_position.y - 0.5), floori(global_position.z))


func _physics_process(delta: float) -> void:
	if not active or route_index >= route.size():
		velocity = Vector3.ZERO
		return
	var target_cell := route[route_index]
	var target := Vector3(target_cell) + Vector3(0.5, 0.9, 0.5)
	var offset := target - global_position
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	if horizontal.length() <= 0.08 and absf(offset.y) <= 0.6:
		global_position = target
		route_index += 1
		if route_index >= route.size():
			active = false
			velocity = Vector3.ZERO
			route_finished.emit()
		return
	var direction := horizontal.normalized()
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	if is_on_floor():
		velocity.y = clampf(offset.y * 6.0, -2.0, 5.0)
	else:
		velocity.y -= GRAVITY * delta
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP)
	move_and_slide()
