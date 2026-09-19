class_name BasicRaider
extends CharacterBody3D

signal route_finished

const MOVE_SPEED := 2.8
const GRAVITY := 14.0

## Raider kinds (P4D waves): a "raider" is the basic capsule; a "brute" is
## bigger, slower and hits harder (health/damage live in CoreDefenseService).
const KIND_RAIDER := "raider"
const KIND_BRUTE := "brute"

var route: Array[Vector3i] = []
var route_index := 0
var active := false
var kind := KIND_RAIDER
var move_speed := MOVE_SPEED
## Set by die(): the body topples, stays a few seconds, then frees itself.
var dead := false
var _death_tween: Tween
const CORPSE_SECONDS := 6.0


func _ready() -> void:
	name = "BasicRaider" if kind == KIND_RAIDER else "BruteRaider"
	var brute := kind == KIND_BRUTE
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34 if not brute else 0.42
	capsule.height = 1.8
	collision.shape = capsule
	add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = capsule.radius
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d95a4e") if not brute else Color("7a2f5e")
	material.roughness = 0.85
	mesh.material = material
	mesh_instance.mesh = mesh
	add_child(mesh_instance)
	if brute:
		var pauldron := MeshInstance3D.new()
		var pauldron_mesh := BoxMesh.new()
		pauldron_mesh.size = Vector3(1.1, 0.24, 0.6)
		pauldron.mesh = pauldron_mesh
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color("4a5158")
		pauldron.material_override = iron
		pauldron.position = Vector3(0.0, 0.55, 0.0)
		add_child(pauldron)
		move_speed = MOVE_SPEED * 0.7


## Sets the kind before the node enters the tree.
func configure(raider_kind: String) -> void:
	kind = raider_kind


## Diagnostics re-arm a defeated raider: cancel the fall and stand it up.
func revive() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
	dead = false
	rotation.z = 0.0
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", false)


## Death: stop, topple sideways, sink slightly, then remove the body.
func die() -> void:
	if dead:
		return
	dead = true
	active = false
	velocity = Vector3.ZERO
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	_death_tween = create_tween()
	var tween := _death_tween
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:z", PI / 2.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", position.y - 0.45, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_interval(CORPSE_SECONDS)
	tween.chain().tween_callback(queue_free)


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
	if dead:
		return
	if not active or route_index >= route.size():
		# Idle bodies still settle onto the ground (restored or shoved raiders).
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= GRAVITY * delta
			move_and_slide()
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
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if is_on_floor():
		velocity.y = clampf(offset.y * 6.0, -2.0, 5.0)
	else:
		velocity.y -= GRAVITY * delta
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP)
	move_and_slide()
