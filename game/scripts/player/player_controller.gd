class_name PlayerController
extends CharacterBody3D

signal interaction_feedback(message: String)
signal boundary_feedback(message: String)

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 5.0
const GRAVITY := 14.0

var camera: Camera3D
var collision_shape: CollisionShape3D
var interaction: InteractionService
var active := false
var look_pitch := 0.0
var mouse_sensitivity := SettingsStore.DEFAULT_MOUSE_SENSITIVITY
var invert_y := false
var _last_boundary_notice_msec := -1000


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision_shape.shape = capsule
	collision_shape.position.y = 0.9
	add_child(collision_shape)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position.y = 1.6
	camera.current = true
	add_child(camera)
	set_physics_process(false)


func activate(capture_pointer: bool = true) -> void:
	active = true
	reset_physics_interpolation()
	set_physics_process(true)
	if capture_pointer:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func deactivate() -> void:
	active = false
	velocity = Vector3.ZERO
	set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func configure_input(sensitivity: float, inverted: bool) -> void:
	mouse_sensitivity = clampf(sensitivity, SettingsStore.MIN_MOUSE_SENSITIVITY, SettingsStore.MAX_MOUSE_SENSITIVITY)
	invert_y = inverted


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_vector := Input.get_vector("strafe_left", "strafe_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var speed := WALK_SPEED
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	elif Input.is_action_pressed("crouch"):
		speed = CROUCH_SPEED
		camera.position.y = 1.15
	else:
		camera.position.y = 1.6
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	_position_inside_world()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_look(event.relative)
	elif event.is_action_pressed("primary") and interaction != null:
		_report(interaction.break_from_view(camera.global_position, -camera.global_basis.z))
	elif event.is_action_pressed("secondary") and interaction != null:
		_report(interaction.secondary_from_view(camera.global_position, -camera.global_basis.z))
	elif event.is_action_pressed("interact") and interaction != null:
		_report(interaction.interact_from_view(camera.global_position, -camera.global_basis.z))


func get_body_aabb() -> AABB:
	return AABB(global_position + Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 1.8, 0.7))


func apply_mouse_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	var vertical_direction := -1.0 if invert_y else 1.0
	look_pitch = clampf(look_pitch - relative.y * mouse_sensitivity * vertical_direction, -1.5, 1.5)
	camera.rotation.x = look_pitch


func snapshot() -> Dictionary:
	return {
		"position": [position.x, position.y, position.z],
		"yaw": rotation.y,
		"pitch": look_pitch,
	}


func restore(data: Dictionary) -> bool:
	var position_data: Array = data.get("position", [])
	if position_data.size() != 3:
		return false
	position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
	rotation.y = float(data.get("yaw", 0.0))
	look_pitch = clampf(float(data.get("pitch", 0.0)), -1.5, 1.5)
	if camera != null:
		camera.rotation.x = look_pitch
	reset_physics_interpolation()
	return true


func _position_inside_world() -> void:
	var before := position
	position.x = clampf(position.x, -31.65, 31.65)
	position.z = clampf(position.z, -63.65, 63.65)
	if not position.is_equal_approx(before):
		var now := Time.get_ticks_msec()
		if now - _last_boundary_notice_msec >= 800:
			_last_boundary_notice_msec = now
			boundary_feedback.emit("World boundary — the finite F1 test world ends here.")


func _report(result: Dictionary) -> void:
	interaction_feedback.emit(result.get("reason", "UNKNOWN"))
