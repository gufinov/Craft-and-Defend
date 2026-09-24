class_name BasicRaider
extends CharacterBody3D

signal route_finished
## Emitted when the body made no progress toward its next route cell for
## STUCK_SECONDS (blocked by a corner, a tree or another body).
signal stuck
## Progress watchdog (wave 1 "raiders unstuck"): emitted once per stage when
## the body's best horizontal distance to its goal has not improved for
## PROGRESS_STAGE_SECONDS[stage - 1] seconds (1: re-plan wide, 2: unstick
## hop, 3: stalled out). The drill owns the goal (set_goal / clear_goal).
signal progress_stalled(stage: int)
## Traps card 2 (docs/TRAPS.md): the body was moved by something that is not
## its route - today a Spring Plate's push - and has come to rest again. The
## drill answers by re-planning from where the body actually landed.
signal displaced

const MOVE_SPEED := 2.8
const GRAVITY := 14.0
## Step-up assist: a body walking into a one-block ledge climbs it (the player
## uses the same test_move probe with a half-block step).
const MAX_STEP_HEIGHT := 1.02
const STEP_FLOOR_PROBE := 0.1
## Shuffle: standing still against another raider for SHUFFLE_AFTER_SECONDS
## makes the body nudge itself sideways for SHUFFLE_SECONDS (no shoving).
const SHUFFLE_AFTER_SECONDS := 1.0
const SHUFFLE_SECONDS := 0.45
const PROGRESS_STAGE_SECONDS: Array[float] = [6.0, 12.0, 20.0]
const PROGRESS_EPSILON := 0.05

## Raider kinds. A "raider" is the basic orc with two cleavers; a "brute" is the
## same orc scaled up with a purple tint (bigger, slower, hits harder); a
## "troll" is the blue-grey crossbow unit that shoots from range. Health,
## damage, range and intervals live in CoreDefenseService.
const KIND_RAIDER := "raider"
const KIND_BRUTE := "brute"
const KIND_TROLL := "troll"
const TROLL_MOVE_SPEED := 2.4
const BRUTE_SCALE := 1.25
## Walk cycle: swing phase (radians) per metre travelled and the swing sizes.
const WALK_PHASE_PER_METRE := 4.2
const LEG_SWING := 0.55
const ARM_SWING := 0.42
const CORPSE_SECONDS := 6.0

var route: Array[Vector3i] = []
var route_index := 0
var active := false
var kind := KIND_RAIDER
var move_speed := MOVE_SPEED
## Set by die(): the body topples, stays a few seconds, then frees itself.
var dead := false
## Set by the drill: cell -> bool, true when the world has that cell loaded.
## Over unloaded ground the body ghost-walks its route kinematically (no
## physics, y from the route cell) so a march from the far enemy base keeps
## going where no chunks exist yet.
var ground_loaded: Callable
const STUCK_SECONDS := 1.6
var _stuck_timer := 0.0
var _best_distance := INF
## Progress watchdog state: the goal point (Vector3.INF = none), whether it is
## watched, the best horizontal distance to it, the seconds without a gain
## and the stage already reported (0..3). Unlike the route watchdog it keeps
## counting while the body is parked without a route (the drill's stall retry)
## so a walled-in raider still stalls out; it is switched off while the body
## deliberately stands (attacking, chasing, shooting).
var goal_point := Vector3.INF
var goal_watch := false
var stall_stage := 0
var _goal_best_distance := INF
var _goal_stall_timer := 0.0
var _contact_timer := 0.0
var _shuffle_timer := 0.0
var _shuffle_side := 1.0
## Counters diagnostics read: one-block step-ups taken and shuffles started.
var step_ups := 0
var shuffles := 0
## Traps card 2 (docs/TRAPS.md), the `slow` effect: a timed multiplier on the
## walking speed. 1.0 = unslowed. It is simulation state, so it rides in the
## wave snapshot with the body's health and position and comes back with it.
var slow_factor := 1.0
var slow_seconds_left := 0.0
## The `push` effect: while this runs down the body is in the air on the
## impulse the trap gave it and its route does not steer it. On landing it
## emits `displaced` once so the drill re-plans from where it came down.
var _push_seconds_left := 0.0
var _push_airborne := 0.0
## Counters diagnostics read: pushes taken and slows applied.
var pushes := 0
var slows := 0
var _death_tween: Tween
var _attack_tween: Tween
## Model root (feet at its origin, 0.9 below the body origin); the limb pivots
## the walk cycle and the attack poses turn.
var _model: Node3D
var _leg_left: Node3D
var _leg_right: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _weapon: Node3D
var _muzzle: Node3D
var _arm_rest_left := Vector3.ZERO
var _arm_rest_right := Vector3.ZERO
var _walk_distance := 0.0
var _walk_blend := 0.0
var _swing_count := 0


const SEPARATION_RADIUS := 0.85
const SEPARATION_PUSH := 2.6


func _ready() -> void:
	# Raiders live on layer 4 and collide only with the world (layer 1): they
	# never shove each other off their routes (the player's mask includes 4);
	# a soft separation keeps them from standing inside one another.
	collision_layer = 4
	collision_mask = 1
	add_to_group("raiders")
	match kind:
		KIND_BRUTE:
			name = "BruteRaider"
		KIND_TROLL:
			name = "TrollRaider"
		_:
			name = "BasicRaider"
	var brute := kind == KIND_BRUTE
	# The collision shape stays a direct child of the root: die() and revive()
	# toggle every CollisionShape3D child.
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42 if brute else 0.34
	capsule.height = 1.8
	collision.shape = capsule
	add_child(collision)
	_model = Node3D.new()
	_model.name = "Model"
	_model.position = Vector3(0.0, -0.9, 0.0)
	if brute:
		_model.scale = Vector3.ONE * BRUTE_SCALE
	add_child(_model)
	if kind == KIND_TROLL:
		_build_troll()
		move_speed = TROLL_MOVE_SPEED
	else:
		_build_orc(brute)
		move_speed = MOVE_SPEED * 0.7 if brute else MOVE_SPEED


## Sets the kind before the node enters the tree.
func configure(raider_kind: String) -> void:
	kind = raider_kind


func is_ranged() -> bool:
	return kind == KIND_TROLL


## Where a troll's bolt leaves the crossbow (the body's chest for others).
func muzzle_position() -> Vector3:
	if _muzzle != null and is_instance_valid(_muzzle):
		return _muzzle.global_position
	return global_position + Vector3.UP * 0.5


## Turns the body toward a point on its own level (used when a troll stops
## to shoot and when a melee raider reaches its target).
func face_point(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_squared_to(global_position) > 0.0001:
		look_at(flat, Vector3.UP)


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
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
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


## Attack presentation: orcs chop with alternating cleavers; trolls kick the
## crossbow back and level it again.
func play_attack() -> void:
	if dead or _model == null:
		return
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
	_attack_tween = create_tween()
	if kind == KIND_TROLL:
		if _weapon == null:
			return
		var rest_z := _weapon.position.z
		_attack_tween.tween_property(_weapon, "position:z", rest_z + 0.12, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_attack_tween.parallel().tween_property(_arm_right, "rotation:x", _arm_rest_right.x + 0.25, 0.06)
		_attack_tween.tween_property(_weapon, "position:z", rest_z, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_attack_tween.parallel().tween_property(_arm_right, "rotation:x", _arm_rest_right.x, 0.30)
		return
	_swing_count += 1
	var arm := _arm_right if _swing_count % 2 == 1 else _arm_left
	var rest := _arm_rest_right if arm == _arm_right else _arm_rest_left
	_attack_tween.tween_property(arm, "rotation:x", 2.4, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(arm, "rotation:x", 0.55, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.tween_property(arm, "rotation:x", rest.x, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_route(cells: Array) -> void:
	_best_distance = INF
	_stuck_timer = 0.0
	route.clear()
	for value in cells:
		if value is Vector3i:
			route.append(value)
	route_index = 1 if route.size() > 1 else route.size()
	active = route_index < route.size()
	if route.size() == 1:
		route_finished.emit()


func feet_cell() -> Vector3i:
	# The body origin sits 0.9 m above its logical feet cell. Subtracting the
	# full value can cross an integer boundary through floating-point rounding.
	return Vector3i(floori(global_position.x), floori(global_position.y - 0.5), floori(global_position.z))


## Starts (or continues) watching progress toward `point`. A new goal resets
## the watchdog; the same goal keeps its timers, so a re-plan toward the same
## target after the 1.6 s watchdog does not restart the 6/12/20 s clock.
func set_goal(point: Vector3) -> void:
	goal_watch = true
	if goal_point.is_finite() and goal_point.distance_squared_to(point) < 0.01:
		return
	goal_point = point
	reset_progress()


## Stops watching (the body stands to attack, chase or shoot).
func clear_goal() -> void:
	goal_watch = false
	goal_point = Vector3.INF
	reset_progress()


func reset_progress() -> void:
	_goal_best_distance = INF
	_goal_stall_timer = 0.0
	stall_stage = 0


## Seconds without a gain toward the goal (diagnostics read it).
func progress_stall_seconds() -> float:
	return _goal_stall_timer


## --- Trap effects (docs/TRAPS.md, traps card 2) ---------------------------
## The two things a trap can do to a body that are not damage. Both are
## driven entirely by the trap's attribute block; nothing here knows which
## trap called it.

## How fast the body actually walks right now: its kind's speed times any
## slow a trap has laid on it.
func walk_speed() -> float:
	return move_speed * slow_factor


## The `slow` effect (the Tar Patch). A timed multiplier on the walking
## speed; the strongest slow in force wins and the longer clock is kept, so
## crossing a second tar cell never makes a raider faster. It clears itself.
func apply_slow(factor: float, seconds: float) -> void:
	if dead:
		return
	var wanted := clampf(factor, 0.05, 0.99)
	slow_factor = minf(slow_factor, wanted) if slow_seconds_left > 0.0 else wanted
	slow_seconds_left = maxf(slow_seconds_left, maxf(0.1, seconds))
	slows += 1


## Puts a saved slow back on a restored body (CoreDefenseService).
func restore_slow(factor: float, seconds: float) -> void:
	if seconds <= 0.0:
		clear_slow()
		return
	slow_factor = clampf(factor, 0.05, 1.0)
	slow_seconds_left = seconds


func clear_slow() -> void:
	slow_factor = 1.0
	slow_seconds_left = 0.0


func is_slowed() -> bool:
	return slow_seconds_left > 0.0


func _tick_slow(delta: float) -> void:
	if slow_seconds_left <= 0.0:
		return
	slow_seconds_left = maxf(0.0, slow_seconds_left - delta)
	if slow_seconds_left <= 0.0:
		slow_factor = 1.0


## The `push` effect (the Spring Plate). One impulse, then the body is in the
## air under gravity and its route does not steer it; when it lands it emits
## `displaced` so the drill re-plans from where it came down. `max_seconds`
## is only the safety cap for a body that somehow never touches down.
func apply_push(impulse: Vector3, max_seconds: float = 2.5) -> void:
	if dead:
		return
	velocity = impulse
	_push_seconds_left = maxf(0.2, max_seconds)
	_push_airborne = 0.0
	pushes += 1


func is_pushed() -> bool:
	return _push_seconds_left > 0.0


## One physics step of a body in the air on a trap's impulse.
func _tick_push(delta: float) -> void:
	_push_seconds_left = maxf(0.0, _push_seconds_left - delta)
	_push_airborne += delta
	velocity.y -= GRAVITY * delta
	move_and_slide()
	_animate_walk(delta, false)
	if (_push_airborne > 0.15 and is_on_floor()) or _push_seconds_left <= 0.0:
		_push_seconds_left = 0.0
		velocity = Vector3.ZERO
		_best_distance = INF
		_stuck_timer = 0.0
		displaced.emit()


## The progress watchdog: the best horizontal distance to the goal must
## improve by PROGRESS_EPSILON within each stage's window, else the stage is
## reported once. Stage 3 stops the clock until the drill resets the goal.
func _tick_progress(delta: float) -> void:
	if not goal_watch or not goal_point.is_finite() or stall_stage >= PROGRESS_STAGE_SECONDS.size():
		return
	var distance := Vector2(goal_point.x - global_position.x, goal_point.z - global_position.z).length()
	if distance < _goal_best_distance - PROGRESS_EPSILON:
		_goal_best_distance = distance
		_goal_stall_timer = 0.0
		stall_stage = 0
		return
	_goal_stall_timer += delta
	if _goal_stall_timer >= PROGRESS_STAGE_SECONDS[stall_stage]:
		stall_stage += 1
		progress_stalled.emit(stall_stage)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick_progress(delta)
	_tick_slow(delta)
	if _push_seconds_left > 0.0:
		# Thrown by a Spring Plate: gravity and nothing else until it lands.
		_tick_push(delta)
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
		_animate_walk(delta, false)
		return
	var target_cell := route[route_index]
	var target := Vector3(target_cell) + Vector3(0.5, 0.9, 0.5)
	var offset := target - global_position
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	if horizontal.length() <= 0.08 and absf(offset.y) <= 0.6:
		global_position = target
		route_index += 1
		_best_distance = INF
		_stuck_timer = 0.0
		if route_index >= route.size():
			active = false
			velocity = Vector3.ZERO
			route_finished.emit()
		return
	# Progress watchdog: no gain toward the cell for STUCK_SECONDS -> stuck.
	var distance := horizontal.length()
	if distance < _best_distance - 0.02:
		_best_distance = distance
		_stuck_timer = 0.0
	else:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_SECONDS:
			_stuck_timer = 0.0
			_best_distance = INF
			stuck.emit()
	var direction := horizontal.normalized()
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP)
	# A trap's slow (docs/TRAPS.md) is a multiplier on this one number, so
	# every path below - ghost walk, walk, shuffle - is slowed by it at once.
	var speed := walk_speed()
	if ground_loaded.is_valid() and not bool(ground_loaded.call(feet_cell() + Vector3i.DOWN)):
		# Ghost walk: slide along the route at walking speed, y from the route.
		var step := minf(speed * delta, horizontal.length())
		global_position += direction * step
		global_position.y = move_toward(global_position.y, target.y, 4.0 * delta)
		velocity = Vector3(direction.x * speed, 0.0, direction.z * speed)
		_walk_distance += step
		_animate_walk(delta, true)
		return
	var push := _separation()
	velocity.x = direction.x * speed + push.x
	velocity.z = direction.z * speed + push.z
	# Shuffle: pressed against another body and not moving, step sideways for
	# a moment (alternating sides) instead of leaning into it.
	if _shuffle_timer > 0.0:
		_shuffle_timer -= delta
		var side := Vector3(-direction.z, 0.0, direction.x) * _shuffle_side
		velocity.x = side.x * speed * 0.8
		velocity.z = side.z * speed * 0.8
	# Step-up assist: blocked by a single block with air above it, climb it.
	var stepped := _try_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta)
	var normal_snap := floor_snap_length
	if stepped:
		floor_snap_length = MAX_STEP_HEIGHT + STEP_FLOOR_PROBE
		velocity.y = 0.0
	elif is_on_floor():
		# Fallback hop toward a higher cell once the step-up assist has not
		# taken it within half a second (a diagonal edge, a half-open corner).
		velocity.y = 5.0 if offset.y > 0.5 and _stuck_timer > 0.5 else 0.0
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	floor_snap_length = normal_snap
	var travelled := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_walk_distance += travelled
	if _shuffle_timer <= 0.0 and travelled < speed * delta * 0.15 and push.length_squared() > 0.0:
		_contact_timer += delta
		if _contact_timer >= SHUFFLE_AFTER_SECONDS:
			_contact_timer = 0.0
			_shuffle_side = -_shuffle_side
			_shuffle_timer = SHUFFLE_SECONDS
			shuffles += 1
	else:
		_contact_timer = 0.0
	_animate_walk(delta, true)


## Climbs a one-block step the way the player does: the horizontal motion is
## blocked, the space one block up is free, the motion from there is free and
## there is a floor within the probe below the raised spot.
func _try_step_up(horizontal_motion: Vector3) -> bool:
	if not is_on_floor() or horizontal_motion.length_squared() <= 0.000001:
		return false
	if not test_move(global_transform, horizontal_motion):
		return false
	var upward_motion := Vector3.UP * MAX_STEP_HEIGHT
	if test_move(global_transform, upward_motion):
		return false
	var raised_transform := global_transform.translated(upward_motion)
	if test_move(raised_transform, horizontal_motion * 4.0):
		return false
	var advanced_transform := raised_transform.translated(horizontal_motion * 4.0)
	if not test_move(advanced_transform, Vector3.DOWN * (MAX_STEP_HEIGHT + STEP_FLOOR_PROBE)):
		return false
	global_position += upward_motion
	step_ups += 1
	return true


## Push away from other living raiders closer than SEPARATION_RADIUS.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other_node in get_tree().get_nodes_in_group("raiders"):
		if other_node == self or not other_node is BasicRaider:
			continue
		var other: BasicRaider = other_node
		if other.dead:
			continue
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		var distance: float = away.length()
		if distance < 0.01 or distance >= SEPARATION_RADIUS:
			continue
		push += away.normalized() * (SEPARATION_RADIUS - distance) * SEPARATION_PUSH
	return push


## Walk cycle from the distance travelled: legs scissor, orc arms counter-swing
## (unless a chop is playing), trolls keep the crossbow levelled and bob.
func _animate_walk(delta: float, moving: bool) -> void:
	if _model == null:
		return
	_walk_blend = move_toward(_walk_blend, 1.0 if moving else 0.0, delta * 6.0)
	var phase := _walk_distance * WALK_PHASE_PER_METRE
	var swing := sin(phase) * _walk_blend
	_leg_left.rotation.x = swing * LEG_SWING
	_leg_right.rotation.x = -swing * LEG_SWING
	var attacking := _attack_tween != null and _attack_tween.is_valid() and _attack_tween.is_running()
	if kind == KIND_TROLL:
		_model.position.y = -0.9 + absf(sin(phase)) * 0.05 * _walk_blend
		if not attacking:
			_arm_right.rotation.x = _arm_rest_right.x + swing * 0.06
			_arm_left.rotation.x = _arm_rest_left.x + swing * 0.06
		return
	if not attacking:
		_arm_left.rotation.x = _arm_rest_left.x + swing * ARM_SWING
		_arm_right.rotation.x = _arm_rest_right.x - swing * ARM_SWING


# --- Models: box/cylinder/cone parts, feet at y = 0, front toward -z. ----------


## Orc melee (owner reference orc_melee.webp): green skin, bald with pointed
## ears and tusks, red left pauldron with an iron plate, baldric and iron
## buckle, red loincloth banner, brown boots with iron toe caps, two grey
## cleavers with gold guards. Brutes reuse it with a purple tint.
func _build_orc(brute: bool) -> void:
	var skin := _material(Color("8a4a9a") if brute else Color("7fb33a"))
	var skin_dark := _material(Color("6a3778") if brute else Color("5f8a2a"))
	var iron := _material(Color("5a6169"), 0.55, 0.55)
	var dark_iron := _material(Color("3a4047"), 0.6, 0.45)
	var red := _material(Color("b8322a"))
	var leather := _material(Color("5a3a22"))
	var boot := _material(Color("6b4426"))
	var fur := _material(Color("c9b48a"))
	var gold := _material(Color("d9a021"), 0.45, 0.7)
	var blade := _material(Color("9ca3ab"), 0.35, 0.8)
	var tusk := _material(Color("f1e9d2"))
	var eye := _material(Color("ff2a2a"), 0.4, 0.0, Color("ff2a2a"))
	_build_legs(skin, boot, iron, fur)
	_build_torso(skin, skin_dark, leather, iron, red)
	var head := _build_head(skin, skin_dark, tusk, eye)
	_add_box(head, Vector3(0.10, 0.06, 0.02), Vector3(-0.12, 0.30, -0.20), skin_dark)
	_add_box(head, Vector3(0.10, 0.06, 0.02), Vector3(0.12, 0.30, -0.20), skin_dark)
	# Left pauldron: red plate with an iron rim, iron diamond and a rear spike.
	_add_box(_model, Vector3(0.42, 0.18, 0.46), Vector3(-0.44, 1.50, 0.0), red, "OrcPauldron")
	_add_box(_model, Vector3(0.46, 0.06, 0.50), Vector3(-0.44, 1.61, 0.0), iron)
	_add_box(_model, Vector3(0.06, 0.20, 0.50), Vector3(-0.66, 1.48, 0.0), iron)
	_add_stud(_model, Vector3(-0.44, 1.67, 0.0), iron, Vector3(0.0, 0.0, 0.0))
	_add_cone(_model, 0.05, 0.14, Vector3(-0.50, 1.70, 0.16), Vector3(-0.35, 0.0, 0.0), dark_iron)
	# Right shoulder strap and a red bracer on the right forearm.
	_add_box(_model, Vector3(0.30, 0.08, 0.36), Vector3(0.44, 1.56, 0.0), leather)
	_build_arms(skin, Vector3(0.5, 0.0, 0.35), Vector3(0.5, 0.0, -0.35))
	_add_box(_arm_left, Vector3(0.26, 0.10, 0.26), Vector3(0.0, -0.52, 0.0), red)
	_add_box(_arm_right, Vector3(0.26, 0.20, 0.26), Vector3(0.0, -0.50, 0.0), red)
	_add_box(_arm_right, Vector3(0.06, 0.12, 0.12), Vector3(0.14, -0.50, 0.0), iron)
	_build_cleaver(_arm_left, "OrcSwordL", -1.0, blade, gold, leather, iron)
	_build_cleaver(_arm_right, "OrcSwordR", 1.0, blade, gold, leather, iron)


## Troll ranged (owner reference troll_ranged.webp): blue-grey skin, black
## topknot ponytail, tusks and a beard, red-and-fur right shoulder pad, brown
## leather bracers and boots with iron plates, red loincloth with a white
## sigil, a quiver of bolts on the left hip and a wooden crossbow.
func _build_troll() -> void:
	var skin := _material(Color("7f93b3"))
	var skin_dark := _material(Color("5f718f"))
	var iron := _material(Color("5a6169"), 0.55, 0.55)
	var dark_iron := _material(Color("3a4047"), 0.6, 0.45)
	var red := _material(Color("b8322a"))
	var leather := _material(Color("5a3a22"))
	var boot := _material(Color("6b4426"))
	var fur := _material(Color("c9b48a"))
	var gold := _material(Color("d9a021"), 0.45, 0.7)
	var wood := _material(Color("8a5a2b"))
	var rope := _material(Color("c8a870"))
	var hair := _material(Color("1c1a1f"))
	var white := _material(Color("efe6d6"))
	var eye := _material(Color("f0a020"), 0.4, 0.0, Color("f0a020"))
	_build_legs(skin, boot, iron, fur)
	_build_torso(skin, skin_dark, leather, iron, red)
	_add_box(_model, Vector3(0.12, 0.14, 0.02), Vector3(0.0, 0.58, -0.225), white)
	_add_box(_model, Vector3(0.20, 0.05, 0.02), Vector3(0.0, 0.50, -0.225), white)
	var head := _build_head(skin, skin_dark, white, eye)
	_add_box(head, Vector3(0.18, 0.12, 0.18), Vector3(0.0, 0.42, 0.02), hair, "TrollTopknot")
	_add_box(head, Vector3(0.10, 0.05, 0.10), Vector3(0.0, 0.46, 0.02), gold)
	var tail := _add_box(head, Vector3(0.09, 0.09, 0.32), Vector3(0.0, 0.40, 0.22), hair)
	tail.rotation.x = 0.55
	_add_box(head, Vector3(0.16, 0.12, 0.06), Vector3(0.0, -0.06, -0.16), hair)
	# Right shoulder pad: fur under a red plate with an iron rim and spike.
	_add_box(_model, Vector3(0.48, 0.10, 0.52), Vector3(0.44, 1.42, 0.0), fur)
	_add_box(_model, Vector3(0.42, 0.18, 0.46), Vector3(0.44, 1.52, 0.0), red, "TrollShoulderPad")
	_add_box(_model, Vector3(0.46, 0.06, 0.50), Vector3(0.44, 1.63, 0.0), iron)
	_add_stud(_model, Vector3(0.44, 1.69, 0.0), iron, Vector3.ZERO)
	_add_cone(_model, 0.05, 0.14, Vector3(0.50, 1.72, 0.14), Vector3(-0.35, 0.0, 0.0), dark_iron)
	# Quiver of bolts on the left hip.
	var quiver := Node3D.new()
	quiver.name = "TrollQuiver"
	quiver.position = Vector3(-0.38, 0.86, 0.14)
	quiver.rotation.z = 0.28
	_model.add_child(quiver)
	_add_cylinder(quiver, 0.075, 0.40, Vector3.ZERO, Vector3.ZERO, leather)
	_add_box(quiver, Vector3(0.17, 0.05, 0.17), Vector3(0.0, 0.12, 0.0), iron)
	for index in range(3):
		var angle := float(index) * TAU / 3.0
		var shaft_offset := Vector3(cos(angle) * 0.035, 0.30, sin(angle) * 0.035)
		_add_cylinder(quiver, 0.012, 0.26, shaft_offset, Vector3.ZERO, wood)
		_add_cone(quiver, 0.03, 0.09, shaft_offset + Vector3(0.0, 0.17, 0.0), Vector3.ZERO, iron)
	# Arms held forward around the crossbow; leather bracers with iron plates.
	_build_arms(skin, Vector3(1.20, 0.0, 0.30), Vector3(1.35, 0.0, -0.12))
	for arm: Node3D in [_arm_left, _arm_right]:
		var side := -1.0 if arm == _arm_left else 1.0
		_add_box(arm, Vector3(0.30, 0.06, 0.30), Vector3(0.0, -0.36, 0.0), fur)
		_add_box(arm, Vector3(0.27, 0.24, 0.27), Vector3(0.0, -0.50, 0.0), leather)
		_add_box(arm, Vector3(0.06, 0.16, 0.16), Vector3(side * 0.15, -0.50, 0.0), iron)
		_add_stud(arm, Vector3(side * 0.19, -0.50, 0.0), dark_iron, Vector3(0.0, 0.0, PI / 2.0))
	_build_crossbow(wood, iron, dark_iron, gold, rope)


func _build_legs(skin: Material, boot: Material, iron: Material, fur: Material) -> void:
	_leg_left = _pivot(_model, "LegL", Vector3(-0.17, 0.80, 0.0))
	_leg_right = _pivot(_model, "LegR", Vector3(0.17, 0.80, 0.0))
	for leg: Node3D in [_leg_left, _leg_right]:
		_add_box(leg, Vector3(0.24, 0.40, 0.26), Vector3(0.0, -0.22, 0.0), skin)
		_add_box(leg, Vector3(0.26, 0.36, 0.30), Vector3(0.0, -0.60, 0.0), boot)
		_add_box(leg, Vector3(0.30, 0.08, 0.34), Vector3(0.0, -0.44, 0.0), fur)
		_add_box(leg, Vector3(0.24, 0.14, 0.14), Vector3(0.0, -0.72, -0.16), iron)
		_add_box(leg, Vector3(0.14, 0.14, 0.04), Vector3(0.0, -0.54, -0.16), iron)
		_add_stud(leg, Vector3(0.0, -0.54, -0.18), iron, Vector3(PI / 2.0, 0.0, 0.0))


func _build_torso(skin: Material, skin_dark: Material, leather: Material, iron: Material, red: Material) -> void:
	_add_box(_model, Vector3(0.64, 0.56, 0.40), Vector3(0.0, 1.14, 0.0), skin, "Torso")
	_add_box(_model, Vector3(0.72, 0.22, 0.42), Vector3(0.0, 1.34, 0.0), skin)
	_add_box(_model, Vector3(0.56, 0.16, 0.36), Vector3(0.0, 0.90, 0.0), skin_dark)
	var baldric := _add_box(_model, Vector3(0.10, 0.74, 0.04), Vector3(0.0, 1.14, -0.21), leather)
	baldric.rotation.z = 0.6
	var baldric_back := _add_box(_model, Vector3(0.10, 0.74, 0.04), Vector3(0.0, 1.14, 0.21), leather)
	baldric_back.rotation.z = -0.6
	_add_cylinder(_model, 0.11, 0.04, Vector3(0.0, 1.18, -0.225), Vector3(PI / 2.0, 0.0, 0.0), iron)
	_add_stud(_model, Vector3(0.0, 1.18, -0.25), iron, Vector3(PI / 2.0, 0.0, 0.0))
	_add_box(_model, Vector3(0.68, 0.12, 0.44), Vector3(0.0, 0.84, 0.0), leather)
	_add_box(_model, Vector3(0.20, 0.18, 0.06), Vector3(0.0, 0.84, -0.22), iron, "BeltBuckle")
	_add_stud(_model, Vector3(0.0, 0.84, -0.26), iron, Vector3(PI / 2.0, 0.0, 0.0))
	_add_box(_model, Vector3(0.32, 0.42, 0.04), Vector3(0.0, 0.60, -0.20), red, "Loincloth")
	_add_box(_model, Vector3(0.32, 0.36, 0.04), Vector3(0.0, 0.62, 0.20), red)


func _build_head(skin: Material, skin_dark: Material, tusk: Material, eye: Material) -> Node3D:
	var head := _pivot(_model, "Head", Vector3(0.0, 1.50, 0.0))
	_add_box(head, Vector3(0.38, 0.36, 0.38), Vector3(0.0, 0.20, 0.0), skin)
	_add_box(head, Vector3(0.34, 0.14, 0.30), Vector3(0.0, 0.02, -0.02), skin_dark)
	_add_box(head, Vector3(0.30, 0.05, 0.04), Vector3(0.0, 0.31, -0.18), skin_dark)
	_add_cone(head, 0.07, 0.22, Vector3(-0.28, 0.24, 0.0), Vector3(0.0, 0.0, PI / 2.0), skin)
	_add_cone(head, 0.07, 0.22, Vector3(0.28, 0.24, 0.0), Vector3(0.0, 0.0, -PI / 2.0), skin)
	_add_box(head, Vector3(0.06, 0.04, 0.02), Vector3(-0.09, 0.24, -0.195), eye)
	_add_box(head, Vector3(0.06, 0.04, 0.02), Vector3(0.09, 0.24, -0.195), eye)
	_add_box(head, Vector3(0.05, 0.12, 0.05), Vector3(-0.10, 0.06, -0.17), tusk)
	_add_box(head, Vector3(0.05, 0.12, 0.05), Vector3(0.10, 0.06, -0.17), tusk)
	return head


func _build_arms(skin: Material, rest_left: Vector3, rest_right: Vector3) -> void:
	_arm_left = _pivot(_model, "ArmL", Vector3(-0.42, 1.40, 0.0))
	_arm_right = _pivot(_model, "ArmR", Vector3(0.42, 1.40, 0.0))
	_arm_rest_left = rest_left
	_arm_rest_right = rest_right
	_arm_left.rotation = rest_left
	_arm_right.rotation = rest_right
	for arm: Node3D in [_arm_left, _arm_right]:
		_add_box(arm, Vector3(0.22, 0.46, 0.22), Vector3(0.0, -0.20, 0.0), skin)
		_add_box(arm, Vector3(0.20, 0.18, 0.20), Vector3(0.0, -0.70, 0.0), skin)


## A cleaver held at the fist: grip, gold pommel and guard, wide grey blade
## with a cone tip. The blade points up and out to the side (`outward` is
## -1 for the left hand, +1 for the right) from the arm's rest pose so it
## reads from the front, and it follows the arm's swing.
func _build_cleaver(arm: Node3D, node_name: String, outward: float, blade: Material, gold: Material, leather: Material, iron: Material) -> void:
	var sword := _pivot(arm, node_name, Vector3(0.0, -0.72, 0.0))
	var blade_direction := Vector3(outward * 0.6, 0.78, -0.2).normalized()
	sword.basis = arm.basis.inverse() * Basis(Quaternion(Vector3.UP, blade_direction))
	_add_cylinder(sword, 0.035, 0.22, Vector3(0.0, -0.10, 0.0), Vector3.ZERO, leather)
	_add_box(sword, Vector3(0.09, 0.07, 0.09), Vector3(0.0, -0.24, 0.0), gold)
	_add_box(sword, Vector3(0.22, 0.07, 0.08), Vector3(0.0, 0.04, 0.0), gold)
	_add_box(sword, Vector3(0.12, 0.60, 0.03), Vector3(0.0, 0.38, 0.0), blade)
	_add_box(sword, Vector3(0.04, 0.50, 0.035), Vector3(0.05, 0.34, 0.0), iron)
	_add_cone(sword, 0.07, 0.16, Vector3(0.0, 0.76, 0.0), Vector3.ZERO, blade)


## A wooden crossbow held level in the right hand: iron-banded stock, gold nut
## block, grey iron-banded bow limbs swept back, rope string, loaded bolt with
## an iron tip. The muzzle node marks where a fired bolt starts.
func _build_crossbow(wood: Material, iron: Material, dark_iron: Material, gold: Material, rope: Material) -> void:
	_weapon = _pivot(_arm_right, "TrollCrossbow", Vector3(-0.04, -0.72, 0.0))
	_weapon.rotation.x = -_arm_rest_right.x
	_add_box(_weapon, Vector3(0.09, 0.11, 0.92), Vector3(0.0, 0.02, -0.30), wood)
	_add_box(_weapon, Vector3(0.11, 0.08, 0.16), Vector3(0.0, -0.03, 0.10), wood)
	for z: float in [-0.06, -0.36, -0.64]:
		_add_box(_weapon, Vector3(0.12, 0.13, 0.05), Vector3(0.0, 0.02, z), iron)
	_add_box(_weapon, Vector3(0.14, 0.12, 0.12), Vector3(0.0, 0.09, 0.02), gold)
	_add_box(_weapon, Vector3(0.04, 0.10, 0.04), Vector3(0.0, -0.08, -0.10), dark_iron)
	var limb_left := _add_box(_weapon, Vector3(0.44, 0.06, 0.07), Vector3(-0.21, 0.03, -0.62), iron)
	limb_left.rotation.y = 0.35
	var limb_right := _add_box(_weapon, Vector3(0.44, 0.06, 0.07), Vector3(0.21, 0.03, -0.62), iron)
	limb_right.rotation.y = -0.35
	_add_box(_weapon, Vector3(0.08, 0.08, 0.09), Vector3(-0.40, 0.03, -0.55), gold)
	_add_box(_weapon, Vector3(0.08, 0.08, 0.09), Vector3(0.40, 0.03, -0.55), gold)
	_add_cylinder(_weapon, 0.012, 0.82, Vector3(0.0, 0.03, -0.53), Vector3(0.0, 0.0, PI / 2.0), rope)
	_add_cylinder(_weapon, 0.02, 0.56, Vector3(0.0, 0.095, -0.36), Vector3(PI / 2.0, 0.0, 0.0), wood, "TrollBoltLoaded")
	_add_cone(_weapon, 0.035, 0.11, Vector3(0.0, 0.095, -0.68), Vector3(-PI / 2.0, 0.0, 0.0), iron)
	_muzzle = Node3D.new()
	_muzzle.name = "TrollMuzzle"
	_muzzle.position = Vector3(0.0, 0.095, -0.76)
	_weapon.add_child(_muzzle)


# --- Part helpers (same shapes GameSession uses for the machines). ----------


func _pivot(parent: Node3D, node_name: String, offset: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = offset
	parent.add_child(pivot)
	return pivot


func _material(color: Color, roughness: float = 0.85, metallic: float = 0.0, emission: Color = Color.TRANSPARENT) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission != Color.TRANSPARENT:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.4
	return material


func _add_box(parent: Node3D, size: Vector3, offset: Vector3, material: Material, node_name: String = "") -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	if not node_name.is_empty():
		mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_cylinder(parent: Node3D, radius: float, height: float, offset: Vector3, part_rotation: Vector3, material: Material, node_name: String = "") -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	if not node_name.is_empty():
		mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.rotation = part_rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_cone(parent: Node3D, radius: float, height: float, offset: Vector3, part_rotation: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.rotation = part_rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


## A small diamond: a cube rotated 45 degrees about the given axis.
func _add_stud(parent: Node3D, offset: Vector3, material: Material, axis_rotation: Vector3) -> MeshInstance3D:
	var stud := _add_box(parent, Vector3(0.09, 0.09, 0.09), offset, material)
	stud.rotation = axis_rotation + Vector3(0.0, 0.785, 0.0)
	return stud
