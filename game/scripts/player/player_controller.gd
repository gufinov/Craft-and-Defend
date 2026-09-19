class_name PlayerController
extends CharacterBody3D

signal interaction_feedback(message: String)
## P4H: the player can be hurt by raiders. health_changed carries the new
## value; died fires once when it reaches zero (the session respawns).
signal health_changed(health: int, max_health: int)
signal died
const MAX_HEALTH := 100
const HEALTH_REGEN_PER_SECOND := 2.0
const REGEN_DELAY_SECONDS := 6.0
var health := MAX_HEALTH
var _regen_delay := 0.0
var _regen_accumulator := 0.0


func take_damage(amount: int, source: String = "raider") -> Dictionary:
	if amount <= 0 or health <= 0:
		return {"ok": false, "reason": "NO_DAMAGE"}
	health = maxi(0, health - amount)
	_regen_delay = REGEN_DELAY_SECONDS
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0:
		died.emit()
	return {"ok": true, "reason": "PLAYER_HIT", "health": health, "source": source}


func restore_health() -> void:
	health = MAX_HEALTH
	_regen_delay = 0.0
	health_changed.emit(health, MAX_HEALTH)


## Slow regeneration once no damage landed for REGEN_DELAY_SECONDS.
func advance_health(delta: float) -> void:
	if health <= 0 or health >= MAX_HEALTH:
		return
	if _regen_delay > 0.0:
		_regen_delay = maxf(0.0, _regen_delay - delta)
		return
	_regen_accumulator += HEALTH_REGEN_PER_SECOND * delta
	if _regen_accumulator >= 1.0:
		var gained := int(_regen_accumulator)
		_regen_accumulator -= float(gained)
		health = mini(MAX_HEALTH, health + gained)
		health_changed.emit(health, MAX_HEALTH)
signal boundary_feedback(message: String)

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 5.0
const GRAVITY := 14.0
const MAX_STEP_HEIGHT := 0.55
## Holding the primary button repeats the strike at this interval (owner
## request 2026-09-18: hold to harvest). Melee keeps its own cooldown.
const PRIMARY_REPEAT_SECONDS := 0.28
var _primary_repeat_timer := 0.0
const STEP_FLOOR_PROBE := 0.08

var camera: Camera3D
var collision_shape: CollisionShape3D
var interaction: InteractionService
var primary_action: Callable
var active := false
var look_pitch := 0.0
var mouse_sensitivity := SettingsStore.DEFAULT_MOUSE_SENSITIVITY
var invert_y := false
var _last_boundary_notice_msec := -1000


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
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
	if Input.is_action_pressed("primary") and interaction != null and not interaction.drag_active():
		_primary_repeat_timer -= delta
		if _primary_repeat_timer <= 0.0:
			_primary_repeat_timer = PRIMARY_REPEAT_SECONDS
			_perform_primary()
	else:
		_primary_repeat_timer = 0.0
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
	var normal_floor_snap := floor_snap_length
	if _try_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta):
		floor_snap_length = MAX_STEP_HEIGHT + STEP_FLOOR_PROBE
	move_and_slide()
	floor_snap_length = normal_floor_snap
	_position_inside_world()


func _try_step_up(horizontal_motion: Vector3) -> bool:
	if not is_on_floor() or velocity.y > 0.0 or horizontal_motion.length_squared() <= 0.000001:
		return false
	if not test_move(global_transform, horizontal_motion):
		return false
	var upward_motion := Vector3.UP * MAX_STEP_HEIGHT
	if test_move(global_transform, upward_motion):
		return false
	var raised_transform := global_transform.translated(upward_motion)
	if test_move(raised_transform, horizontal_motion):
		return false
	var advanced_transform := raised_transform.translated(horizontal_motion)
	if not test_move(advanced_transform, Vector3.DOWN * (MAX_STEP_HEIGHT + STEP_FLOOR_PROBE)):
		return false
	global_position += upward_motion
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_look(event.relative)
	elif event.is_action_pressed("primary") and interaction != null and interaction.drag_active():
		# P3J: a left-press while a right-drag is held cancels it; nothing is built.
		_report(interaction.cancel_drag_place())
	elif event.is_action_pressed("primary") and interaction != null:
		_primary_repeat_timer = PRIMARY_REPEAT_SECONDS
		_perform_primary()
	elif event.is_action_pressed("secondary") and interaction != null:
		var pressed := interaction.secondary_press_from_view(camera.global_position, -camera.global_basis.z)
		if str(pressed.get("reason", "")) != "DRAG_STARTED":
			_report(pressed)
	elif event.is_action_released("secondary") and interaction != null and interaction.drag_active():
		_report(interaction.secondary_release_from_view(camera.global_position, -camera.global_basis.z))
	elif event.is_action_pressed("interact") and interaction != null and interaction.drag_active():
		pass  # Shift while dragging switches the plan to vertical; no interact.
	elif event.is_action_pressed("interact") and interaction != null:
		_report(interaction.interact_from_view(camera.global_position, -camera.global_basis.z))


func _perform_primary() -> void:
	if primary_action.is_valid():
		var primary_result: Dictionary = primary_action.call(camera.global_position, -camera.global_basis.z)
		if primary_result.get("handled", false):
			_report(primary_result)
			return
	_report(interaction.break_from_view(camera.global_position, -camera.global_basis.z))


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
