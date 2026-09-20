class_name CoasterRide
extends Node

## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): the player riding a
## `coaster_car`. GameSession owns one CoasterRide; boarding parks the player
## body (deactivated, dragged along under the car so terrain keeps streaming
## around it), seats a HeroModel on the car's "Seat" node and switches to the
## ride camera: a three-quarter chase camera behind, beside and above the car
## that follows the car's smoothed horizontal heading with world up, so loops
## never roll the view and the camera stays out of the loop's plane.
## Number keys 1-9 set the car's speed in cells per second (default 3).
## Leaving parks the car where it is and stands the player beside it.

const MIN_SPEED_LEVEL := 1
const MAX_SPEED_LEVEL := 9
const DEFAULT_SPEED_LEVEL := 3
## Three-quarter chase view: behind the car's horizontal heading, off to its
## right and above. The side offset keeps the camera out of the loop's own
## plane (a radius-3 loop would otherwise swallow a camera straight behind).
const CAMERA_BACK := 3.0
const CAMERA_SIDE := 1.8
const CAMERA_UP := 1.9
const CAMERA_LOOK_AHEAD := 0.3
const CAMERA_LOOK_UP := 0.6
const CAMERA_FOLLOW_RATE := 8.0
const FORWARD_SMOOTH_RATE := 4.0
## Where the hero's feet sit under the seat node (legs hidden by the body).
const SEAT_HERO_OFFSET := Vector3(0.0, -0.85, 0.0)
const DISMOUNT_SIDE := 1.0
## First-person seat view: the eyes in rig space (just ahead of the seated
## hero's face so his head sits behind the near plane), how far the head can
## turn, and how quickly the seat basis follows the car through a loop.
const SEAT_EYE := Vector3(0.0, 1.16, -0.06)
const SEAT_YAW_LIMIT := deg_to_rad(110.0)
const SEAT_PITCH_LIMIT := deg_to_rad(60.0)
const SEAT_BASIS_RATE := 6.0
const SEAT_NEAR := 0.08

var player: PlayerController
var carts: CoasterCartService
var car_id := ""
var speed_level := DEFAULT_SPEED_LEVEL
var armored := false
var _camera: Camera3D
var _hero: HeroModel
var _smooth_forward := Vector3.FORWARD
var _horizontal_back := Vector3.BACK
var _third_person_before := false
## Seat view state: chase view off by default; head yaw / pitch in seat space.
var chase_view := false
var seat_yaw := 0.0
var seat_pitch := 0.0
var _seat_basis := Basis.IDENTITY
var _rig: Node3D


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "RideCamera"
	_camera.current = false
	add_child(_camera)


func initialize(session_player: PlayerController) -> void:
	player = session_player


func is_riding() -> bool:
	return not car_id.is_empty()


func ride_camera() -> Camera3D:
	return _camera


func seated_hero() -> HeroModel:
	return _hero


func hud_text() -> String:
	return "RIDING · speed %d/%d · 1-9 speed · Shift leave · V %s" % [speed_level, MAX_SPEED_LEVEL, "seat view" if chase_view else "chase view"]


## Seats the player in the car `instance_id` (its visual body `body`, moved by
## `cart_service`). Fails while already riding or when the body has no rig.
func board(instance_id: String, body: Node3D, cart_service: CoasterCartService, capture_pointer: bool) -> Dictionary:
	if is_riding():
		return {"ok": false, "reason": "ALREADY_RIDING"}
	if player == null or body == null or cart_service == null:
		return {"ok": false, "reason": "NO_CAR"}
	var rig: Node3D = body.get_node_or_null("CartRig")
	var seat: Node3D = rig.get_node_or_null("Seat") if rig != null else null
	if rig == null or seat == null:
		return {"ok": false, "reason": "NO_CAR"}
	carts = cart_service
	car_id = instance_id
	speed_level = DEFAULT_SPEED_LEVEL
	carts.set_speed(car_id, float(speed_level))
	carts.set_parked(car_id, false)
	_third_person_before = player.third_person
	player.deactivate()
	player.hero.visible = false
	if capture_pointer:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hero = HeroModel.new()
	_hero.name = "RidingHero"
	_hero.position = SEAT_HERO_OFFSET
	seat.add_child(_hero)
	_hero.set_armored(armored)
	_hero.set_seated(true)
	_smooth_forward = carts.travel_direction(car_id)
	_update_horizontal_back()
	_rig = rig
	seat_yaw = 0.0
	seat_pitch = 0.0
	_seat_basis = rig.global_basis.orthonormalized()
	_camera.near = SEAT_NEAR
	_place_camera(rig, true)
	_camera.current = true
	return {"ok": true, "reason": "COASTER_BOARDED", "instance_id": car_id}


## Parks the car and stands the player beside it (on the rail cell's floor).
func leave(activate_player: bool, capture_pointer: bool) -> Dictionary:
	if not is_riding():
		return {"ok": false, "reason": "NOT_RIDING"}
	var landing := dismount_position()
	carts.set_parked(car_id, true)
	if _hero != null:
		_hero.queue_free()
		_hero = null
	_camera.current = false
	player.camera.current = true
	player.global_position = landing
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.set_third_person(_third_person_before)
	if activate_player:
		player.activate(capture_pointer)
	var left_id := car_id
	car_id = ""
	carts = null
	_rig = null
	return {"ok": true, "reason": "COASTER_LEFT", "instance_id": left_id, "position": landing}


## Mouse look in the seat: the head turns within the yaw / pitch limits of
## the seat basis (no turning around). Sensitivity and inversion follow the
## player's settings.
func apply_mouse_look(relative: Vector2) -> void:
	if not is_riding() or chase_view or player == null:
		return
	var vertical_direction := -1.0 if player.invert_y else 1.0
	seat_yaw = clampf(seat_yaw - relative.x * player.mouse_sensitivity, -SEAT_YAW_LIMIT, SEAT_YAW_LIMIT)
	seat_pitch = clampf(seat_pitch - relative.y * player.mouse_sensitivity * vertical_direction, -SEAT_PITCH_LIMIT, SEAT_PITCH_LIMIT)
	if _rig != null:
		_place_camera(_rig, false)


## V while riding: seat view <-> chase view.
func toggle_chase_view() -> bool:
	chase_view = not chase_view
	if _rig != null:
		_place_camera(_rig, true)
	return chase_view


## The camera's forward direction (diagnostics).
func view_forward() -> Vector3:
	return -_camera.global_basis.z


## Seat view: eyes at SEAT_EYE in the smoothed seat basis, turned by the head
## yaw / pitch. Chase view: the three-quarter camera behind the car.
func _place_camera(rig: Node3D, snap: bool) -> void:
	if chase_view:
		var target := _camera_target(rig.global_position)
		_camera.global_position = target if snap else _camera.global_position
		_look(rig.global_position)
		return
	if snap:
		_seat_basis = rig.global_basis.orthonormalized()
	_camera.global_position = rig.global_position + _seat_basis * SEAT_EYE
	var head := Basis.from_euler(Vector3(seat_pitch, seat_yaw, 0.0))
	_camera.global_basis = _seat_basis * head


## 1..9 cells per second; feedback text for the HUD.
func set_speed_level(level: int) -> Dictionary:
	if not is_riding():
		return {"ok": false, "reason": "NOT_RIDING"}
	speed_level = clampi(level, MIN_SPEED_LEVEL, MAX_SPEED_LEVEL)
	carts.set_speed(car_id, float(speed_level))
	return {"ok": true, "reason": "COASTER_SPEED", "level": speed_level}


func set_armored(value: bool) -> void:
	armored = value
	if _hero != null:
		_hero.set_armored(value)


## Beside the car on its right, feet at the floor of the rail cell (a car
## hanging in a loop leaves the player to drop to the ground).
func dismount_position() -> Vector3:
	var rig: Node3D = carts.cart_rig(car_id) if carts != null else null
	if rig == null:
		return player.global_position
	var forward := carts.travel_direction(car_id)
	var side := Vector3(forward.x, 0.0, forward.z).normalized().cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var origin := rig.global_position
	return Vector3(origin.x + side.x * DISMOUNT_SIDE, floorf(origin.y), origin.z + side.z * DISMOUNT_SIDE)


## Each frame while riding: drag the parked player body under the car and
## follow with the camera (also while paused, so the view never jumps).
func advance(delta: float) -> void:
	if not is_riding() or carts == null:
		return
	var rig: Node3D = carts.cart_rig(car_id)
	if rig == null:
		return
	player.global_position = rig.global_position
	var forward := carts.travel_direction(car_id)
	if forward.length() > 0.5:
		_smooth_forward = _smooth_forward.lerp(forward, minf(1.0, delta * FORWARD_SMOOTH_RATE))
		if _smooth_forward.length() > 0.05:
			_smooth_forward = _smooth_forward.normalized()
		else:
			_smooth_forward = forward
	_update_horizontal_back()
	if chase_view:
		var target := _camera_target(rig.global_position)
		_camera.global_position = _camera.global_position.lerp(target, minf(1.0, delta * CAMERA_FOLLOW_RATE))
		_look(rig.global_position)
		return
	# The seat basis eases toward the car's basis so a loop's climb, top and
	# dive read as one smooth turn of the head rather than per-cell jumps.
	var rig_basis := rig.global_basis.orthonormalized()
	var eased := Quaternion(_seat_basis).slerp(Quaternion(rig_basis), minf(1.0, delta * SEAT_BASIS_RATE))
	_seat_basis = Basis(eased.normalized())
	_place_camera(rig, false)


func _update_horizontal_back() -> void:
	var horizontal := Vector3(_smooth_forward.x, 0.0, _smooth_forward.z)
	if horizontal.length() > 0.15:
		_horizontal_back = -horizontal.normalized()


func _camera_target(rig_position: Vector3) -> Vector3:
	var right := (-_horizontal_back).cross(Vector3.UP)
	return rig_position + Vector3.UP * CAMERA_UP + _horizontal_back * CAMERA_BACK + right * CAMERA_SIDE


## The camera looks a little ahead of the car along its horizontal heading
## (never along a vertical climb, which would swing the car out of frame).
func _look(rig_position: Vector3) -> void:
	var focus := rig_position + Vector3.UP * CAMERA_LOOK_UP - _horizontal_back * CAMERA_LOOK_AHEAD
	if focus.distance_to(_camera.global_position) < 0.05:
		return
	_camera.look_at(focus, Vector3.UP)
