class_name HeroModel
extends Node3D

## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): the player's hero
## from the owner's references (hero_unarmored.webp / hero_armored.webp) built
## from box / cylinder / cone primitives like BasicRaider. Feet at the origin,
## front toward -z, about 1.8 tall.
##
## Unarmored: brown hair, skin, blue tunic with gold trim and a gold lion-crest
## rectangle, blue scarf, brown belts / bracers / boots, cream sleeves, a sword
## in the right hand. `set_armored(true)` rebuilds the plate look: silver
## plates with gold trim, a blue tabard, gold shoulder diamonds, silver greaves
## and bracers. `set_seated(true)` poses the hero for the coaster car: arms
## forward on the bar, legs hidden by the car body, sword stowed.
## `animate_walk(delta, moving, distance)` runs the walk cycle like the raiders.

## Walk cycle: swing phase (radians) per metre travelled and the swing sizes.
const WALK_PHASE_PER_METRE := 4.2
const LEG_SWING := 0.55
const ARM_SWING := 0.40
## Seated pose: arms forward onto the car's bar.
## Positive pitch swings the hanging arm forward (toward -z) onto the bar.
const SEATED_ARM_PITCH := 1.25

var armored := false
var seated := false
var walk_phase := 0.0
var _walk_blend := 0.0
var _model: Node3D
var _leg_left: Node3D
var _leg_right: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _sword: Node3D
var _head: Node3D


func _ready() -> void:
	if _model == null:
		_rebuild()


func set_armored(value: bool) -> void:
	if armored == value and _model != null:
		return
	armored = value
	_rebuild()


func set_seated(value: bool) -> void:
	seated = value
	_apply_pose()


## Riding look (owner 2026-09-20): the whole body turns with the rider's
## yaw and the head tilts with the pitch, so the seated body matches the
## seat view instead of staying fixed while only the camera turns.
var look_yaw := 0.0
var look_pitch := 0.0


func set_look(yaw: float, pitch: float) -> void:
	look_yaw = yaw
	look_pitch = pitch
	if _model != null:
		_model.rotation.y = yaw
	if _head != null:
		_head.rotation.x = pitch


## Walk cycle from the distance travelled this frame: legs scissor, arms
## counter-swing; blends out when standing. Ignored while seated.
func animate_walk(delta: float, moving: bool, distance: float) -> void:
	if _model == null or seated:
		return
	_walk_blend = move_toward(_walk_blend, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		walk_phase += distance * WALK_PHASE_PER_METRE
	var swing := sin(walk_phase) * _walk_blend
	_leg_left.rotation.x = swing * LEG_SWING
	_leg_right.rotation.x = -swing * LEG_SWING
	_arm_left.rotation.x = swing * ARM_SWING
	_arm_right.rotation.x = -swing * ARM_SWING
	_model.position.y = absf(sin(walk_phase)) * 0.03 * _walk_blend


## Named parts for diagnostics: every MeshInstance3D / pivot name under the rig.
func part_names() -> Array[String]:
	var names: Array[String] = []
	if _model == null:
		return names
	for node in _model.find_children("*", "Node3D", true, false):
		names.append(str(node.name))
	return names


func mesh_count() -> int:
	if _model == null:
		return 0
	return _model.find_children("*", "MeshInstance3D", true, false).size()


func _rebuild() -> void:
	if _model != null:
		# Out of the tree at once so the new rig keeps the "HeroRig" name.
		remove_child(_model)
		_model.queue_free()
	_model = Node3D.new()
	_model.name = "HeroRig"
	add_child(_model)
	var skin := _material(Color("e8b48c"))
	var hair := _material(Color("5a3a22"))
	var eye := _material(Color("3d7ad6"), 0.4, 0.0, Color("2a5fb8"))
	var blue := _material(Color("2f56b8"))
	var blue_dark := _material(Color("24428f"))
	var gold := _material(Color("d9a437"), 0.45, 0.6)
	var leather := _material(Color("6b4426"))
	var leather_dark := _material(Color("4a2e19"))
	var cream := _material(Color("d9cdb4"))
	var trouser := _material(Color("3b3230"))
	var silver := _material(Color("c9d0d8"), 0.4, 0.5)
	var iron_dark := _material(Color("55606a"), 0.5, 0.6)
	var blade := _material(Color("cfd6dd"), 0.3, 0.9)
	_build_legs(trouser, leather, leather_dark, gold, silver)
	_build_torso(blue, blue_dark, gold, leather, leather_dark, silver, iron_dark)
	_head = _build_head(skin, hair, eye, blue)
	_build_arms(skin, blue, cream, leather, gold, silver)
	_build_sword(_arm_right, blade, gold, leather)
	_apply_pose()


func _build_legs(trouser: Material, boot: Material, boot_dark: Material, gold: Material, silver: Material) -> void:
	_leg_left = _pivot(_model, "LegL", Vector3(-0.14, 0.86, 0.0))
	_leg_right = _pivot(_model, "LegR", Vector3(0.14, 0.86, 0.0))
	for leg: Node3D in [_leg_left, _leg_right]:
		_add_box(leg, Vector3(0.22, 0.40, 0.24), Vector3(0.0, -0.20, 0.0), trouser, "Thigh")
		if armored:
			_add_box(leg, Vector3(0.24, 0.20, 0.26), Vector3(0.0, -0.14, -0.01), silver, "CuissePlate")
			_add_box(leg, Vector3(0.26, 0.34, 0.30), Vector3(0.0, -0.64, 0.0), silver, "Greave")
			_add_box(leg, Vector3(0.28, 0.06, 0.32), Vector3(0.0, -0.49, 0.0), gold, "GreaveTrim")
			_add_box(leg, Vector3(0.26, 0.12, 0.34), Vector3(0.0, -0.80, -0.02), boot, "Boot")
			_add_box(leg, Vector3(0.20, 0.10, 0.10), Vector3(0.0, -0.80, -0.18), silver, "ToeCap")
		else:
			_add_box(leg, Vector3(0.26, 0.36, 0.30), Vector3(0.0, -0.66, 0.0), boot, "Boot")
			_add_box(leg, Vector3(0.28, 0.08, 0.32), Vector3(0.0, -0.50, 0.0), boot_dark, "BootCuff")
			_add_box(leg, Vector3(0.28, 0.05, 0.32), Vector3(0.0, -0.62, 0.0), boot_dark, "BootStrap")
			_add_box(leg, Vector3(0.06, 0.06, 0.02), Vector3(0.0, -0.62, -0.165), gold, "BootBuckle")


func _build_torso(blue: Material, blue_dark: Material, gold: Material, leather: Material, leather_dark: Material, silver: Material, iron_dark: Material) -> void:
	if armored:
		_add_box(_model, Vector3(0.58, 0.60, 0.36), Vector3(0.0, 1.20, 0.0), silver, "Breastplate")
		_add_box(_model, Vector3(0.60, 0.05, 0.38), Vector3(0.0, 1.47, 0.0), gold, "CollarTrim")
		_add_box(_model, Vector3(0.60, 0.05, 0.38), Vector3(0.0, 0.94, 0.0), gold, "PlateHem")
		_add_stud(_model, Vector3(0.0, 1.30, -0.195), gold, FRONT_DIAMOND, "ChestDiamond", 0.14)
		_add_box(_model, Vector3(0.30, 0.40, 0.03), Vector3(0.0, 0.72, -0.19), blue, "Tabard")
		_add_box(_model, Vector3(0.32, 0.04, 0.04), Vector3(0.0, 0.53, -0.19), gold, "TabardTrim")
		_add_box(_model, Vector3(0.14, 0.14, 0.02), Vector3(0.0, 0.78, -0.21), gold, "LionCrest")
		_add_box(_model, Vector3(0.30, 0.36, 0.03), Vector3(0.0, 0.74, 0.19), blue, "TabardBack")
		_add_box(_model, Vector3(0.62, 0.10, 0.40), Vector3(0.0, 0.96, 0.0), leather, "Belt")
		_add_box(_model, Vector3(0.14, 0.12, 0.03), Vector3(0.0, 0.96, -0.21), silver, "BeltBuckle")
		_add_stud(_model, Vector3(0.0, 0.96, -0.23), gold, FRONT_DIAMOND, "BeltDiamond", 0.06)
		var strap := _add_box(_model, Vector3(0.09, 0.70, 0.02), Vector3(0.0, 1.20, -0.19), leather, "Baldric")
		strap.rotation.z = 0.62
		_add_box(_model, Vector3(0.42, 0.14, 0.36), Vector3(0.0, 1.55, 0.0), blue, "Scarf")
		_add_box(_model, Vector3(0.44, 0.04, 0.38), Vector3(0.0, 1.62, 0.0), iron_dark, "Gorget")
	else:
		_add_box(_model, Vector3(0.56, 0.60, 0.34), Vector3(0.0, 1.20, 0.0), blue, "Tunic")
		_add_box(_model, Vector3(0.58, 0.04, 0.36), Vector3(0.0, 0.92, 0.0), gold, "TunicHem")
		_add_box(_model, Vector3(0.04, 0.50, 0.36), Vector3(0.0, 1.20, 0.0), gold, "TunicSeam")
		_add_box(_model, Vector3(0.14, 0.16, 0.02), Vector3(-0.14, 1.28, -0.18), gold, "LionCrest")
		_add_box(_model, Vector3(0.30, 0.36, 0.03), Vector3(0.0, 0.74, -0.18), blue, "Tabard")
		_add_box(_model, Vector3(0.32, 0.04, 0.04), Vector3(0.0, 0.56, -0.18), gold, "TabardTrim")
		_add_box(_model, Vector3(0.12, 0.12, 0.02), Vector3(0.0, 0.76, -0.20), gold, "TabardLion")
		_add_box(_model, Vector3(0.30, 0.32, 0.03), Vector3(0.0, 0.76, 0.18), blue_dark, "TabardBack")
		_add_box(_model, Vector3(0.60, 0.10, 0.38), Vector3(0.0, 0.95, 0.0), leather, "Belt")
		_add_box(_model, Vector3(0.12, 0.10, 0.03), Vector3(0.0, 0.95, -0.20), gold, "BeltBuckle")
		_add_box(_model, Vector3(0.12, 0.12, 0.08), Vector3(-0.22, 0.94, -0.16), leather_dark, "BeltPouch")
		var strap := _add_box(_model, Vector3(0.09, 0.70, 0.02), Vector3(0.0, 1.20, -0.18), leather, "Baldric")
		strap.rotation.z = 0.62
		_add_box(_model, Vector3(0.08, 0.07, 0.03), Vector3(0.10, 1.34, -0.19), gold, "BaldricBuckle")
		var strap_back := _add_box(_model, Vector3(0.09, 0.70, 0.02), Vector3(0.0, 1.20, 0.18), leather, "BaldricBack")
		strap_back.rotation.z = -0.62
		_add_box(_model, Vector3(0.42, 0.14, 0.36), Vector3(0.0, 1.55, 0.0), blue, "Scarf")
		_add_box(_model, Vector3(0.10, 0.34, 0.03), Vector3(0.24, 1.32, 0.19), blue, "ScarfTail")


func _build_head(skin: Material, hair: Material, eye: Material, _blue: Material) -> Node3D:
	var head := _pivot(_model, "Head", Vector3(0.0, 1.62, 0.0))
	_add_box(head, Vector3(0.32, 0.34, 0.32), Vector3(0.0, 0.18, 0.0), skin, "Face")
	_add_box(head, Vector3(0.34, 0.12, 0.34), Vector3(0.0, 0.36, 0.0), hair, "Hair")
	_add_box(head, Vector3(0.34, 0.10, 0.08), Vector3(0.0, 0.30, -0.15), hair, "Fringe")
	_add_box(head, Vector3(0.06, 0.20, 0.30), Vector3(-0.155, 0.24, 0.02), hair, "HairSideL")
	_add_box(head, Vector3(0.06, 0.20, 0.30), Vector3(0.155, 0.24, 0.02), hair, "HairSideR")
	_add_box(head, Vector3(0.05, 0.04, 0.02), Vector3(-0.07, 0.20, -0.165), eye, "EyeL")
	_add_box(head, Vector3(0.05, 0.04, 0.02), Vector3(0.07, 0.20, -0.165), eye, "EyeR")
	_add_box(head, Vector3(0.07, 0.02, 0.02), Vector3(-0.07, 0.245, -0.165), hair, "BrowL")
	_add_box(head, Vector3(0.07, 0.02, 0.02), Vector3(0.07, 0.245, -0.165), hair, "BrowR")
	_add_box(head, Vector3(0.06, 0.04, 0.02), Vector3(0.0, 0.14, -0.165), skin, "Nose")
	return head


func _build_arms(skin: Material, blue: Material, cream: Material, leather: Material, gold: Material, silver: Material) -> void:
	_arm_left = _pivot(_model, "ArmL", Vector3(-0.38, 1.44, 0.0))
	_arm_right = _pivot(_model, "ArmR", Vector3(0.38, 1.44, 0.0))
	for arm: Node3D in [_arm_left, _arm_right]:
		var outward := -1.0 if arm == _arm_left else 1.0
		if armored:
			_add_box(arm, Vector3(0.26, 0.18, 0.30), Vector3(outward * 0.02, 0.02, 0.0), blue, "Pauldron")
			_add_box(arm, Vector3(0.28, 0.04, 0.32), Vector3(outward * 0.02, -0.08, 0.0), gold, "PauldronTrim")
			_add_stud(arm, Vector3(outward * 0.15, 0.02, 0.0), gold, SIDE_DIAMOND, "ShoulderDiamond", 0.10)
			_add_box(arm, Vector3(0.20, 0.28, 0.20), Vector3(0.0, -0.20, 0.0), silver, "UpperArm")
			_add_box(arm, Vector3(0.20, 0.22, 0.20), Vector3(0.0, -0.44, 0.0), silver, "Vambrace")
			_add_box(arm, Vector3(0.22, 0.04, 0.22), Vector3(0.0, -0.34, 0.0), gold, "VambraceTrim")
			_add_box(arm, Vector3(0.18, 0.14, 0.18), Vector3(0.0, -0.62, 0.0), leather, "Gauntlet")
		else:
			_add_box(arm, Vector3(0.20, 0.30, 0.20), Vector3(0.0, -0.14, 0.0), blue, "Sleeve")
			_add_box(arm, Vector3(0.22, 0.04, 0.22), Vector3(0.0, -0.28, 0.0), gold, "SleeveTrim")
			_add_box(arm, Vector3(0.18, 0.20, 0.18), Vector3(0.0, -0.40, 0.0), cream, "Forearm")
			_add_box(arm, Vector3(0.20, 0.16, 0.20), Vector3(0.0, -0.56, 0.0), leather, "Bracer")
			_add_box(arm, Vector3(0.06, 0.05, 0.02), Vector3(0.0, -0.56, -0.105), gold, "BracerBuckle")
			_add_box(arm, Vector3(0.16, 0.14, 0.16), Vector3(0.0, -0.70, 0.0), skin, "Fist")


## The sword at the right fist: leather grip, gold pommel and cross guard
## with a blue gem, a broad silver blade ending in a cone tip. It points up
## and outward so it reads from the front and follows the arm's swing.
func _build_sword(arm: Node3D, blade: Material, gold: Material, leather: Material) -> void:
	_sword = _pivot(arm, "Sword", Vector3(0.0, -0.70, 0.0))
	_sword.basis = Basis(Quaternion(Vector3.UP, Vector3(0.45, 0.85, -0.25).normalized()))
	_add_cylinder(_sword, 0.03, 0.20, Vector3(0.0, -0.10, 0.0), Vector3.ZERO, leather, "Grip")
	_add_box(_sword, Vector3(0.08, 0.06, 0.08), Vector3(0.0, -0.22, 0.0), gold, "Pommel")
	_add_box(_sword, Vector3(0.24, 0.06, 0.07), Vector3(0.0, 0.02, 0.0), gold, "CrossGuard")
	_add_stud(_sword, Vector3(0.0, 0.02, -0.04), _material(Color("4c8dff"), 0.3, 0.0, Color("2f6fe0")), FRONT_DIAMOND, "GuardGem", 0.05)
	_add_box(_sword, Vector3(0.09, 0.62, 0.025), Vector3(0.0, 0.36, 0.0), blade, "Blade")
	_add_cone(_sword, 0.05, 0.14, Vector3(0.0, 0.74, 0.0), Vector3.ZERO, blade, "BladeTip")


func _apply_pose() -> void:
	if _model == null:
		return
	_leg_left.visible = not seated
	_leg_right.visible = not seated
	if _sword != null:
		_sword.visible = not seated
	if seated:
		_arm_left.rotation = Vector3(SEATED_ARM_PITCH, 0.0, 0.0)
		_arm_right.rotation = Vector3(SEATED_ARM_PITCH, 0.0, 0.0)
		_model.position.y = 0.0
	else:
		_arm_left.rotation = Vector3.ZERO
		_arm_right.rotation = Vector3.ZERO


# --- Primitive helpers (BasicRaider style). -----------------------------------


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
		material.emission_energy_multiplier = 1.2
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


func _add_cone(parent: Node3D, radius: float, height: float, offset: Vector3, part_rotation: Vector3, material: Material, node_name: String = "") -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	if not node_name.is_empty():
		mesh_instance.name = node_name
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


## A gold diamond: a cube turned 45 degrees so it reads as a diamond from the
## face it decorates (`FRONT_DIAMOND` for a -z face, `SIDE_DIAMOND` for +-x).
const FRONT_DIAMOND := Vector3(0.0, 0.0, PI / 4.0)
const SIDE_DIAMOND := Vector3(PI / 4.0, 0.0, 0.0)
func _add_stud(parent: Node3D, offset: Vector3, material: Material, diamond_rotation: Vector3, node_name: String = "", size: float = 0.08) -> MeshInstance3D:
	var stud := _add_box(parent, Vector3(size, size, size), offset, material, node_name)
	stud.rotation = diamond_rotation
	return stud
