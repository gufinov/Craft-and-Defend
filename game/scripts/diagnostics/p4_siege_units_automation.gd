class_name P4SiegeUnitsAutomation
extends Node

## P4C siege units: cannon (direct, cannonball), turret catapult (tower-top
## ballistic), rail + kettle (rides a rail chain along a wall top and dumps hot
## oil), and the remodelled ballista's draw/release presentation. Runs with
## `--p4-siege-units-automation=gate`.

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"gate":
			await _run_gate()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p4_siege_units_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P4_SIEGE_UNITS_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P4_SIEGE_UNITS_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var registry := app.session.registry
	var ws := app.session.workstations
	var siege := app.session.siege_defense
	var core := app.session.core_defense
	var world := app.session.world

	# T130 content: the new units, munitions, recipes and icons are registered.
	var new_items := ["cannon", "cannonball", "turret_catapult", "rail", "kettle", "hot_oil"]
	var missing_icons := ItemIconCatalog.missing_item_ids(new_items)
	var munitions_ok: bool = registry.munition("cannonball").get("damage", 0) == 14 and registry.munition("hot_oil").get("effect", "") == "fire"
	var hot_oil_recipe := ws.furnace_recipe_for_input("log")
	var entities_ok := true
	for entity_id in ["cannon", "turret_catapult", "rail", "kettle"]:
		if registry.entity(entity_id).is_empty():
			entities_ok = false
	var kettle_siege: Dictionary = registry.entity("kettle").get("siege", {})
	_record("T130_SIEGE_UNIT_CONTENT", missing_icons.is_empty() and munitions_ok and hot_oil_recipe == "hot_oil" and entities_ok and str(kettle_siege.get("fire_mode", "")) == "dump" and float(kettle_siege.get("rail_speed", 0.0)) > 0.0, "cannon, turret catapult, rail, kettle, cannonball and hot oil are registered with icons; hot oil smelts from logs; the kettle is a rail-riding dump weapon", {"missing_icons": missing_icons, "munitions_ok": munitions_ok, "hot_oil_recipe": hot_oil_recipe, "entities_ok": entities_ok, "kettle": kettle_siege})

	# Drill fixture: start the core defense, park its raider, level the arena.
	var started := core.start_prototype()
	core.warning_remaining = 0.0
	core._begin_attack()
	core.raider.active = false
	var center := core.arena_center
	_level_ground(center + Vector3i(-8, 0, -8), 17, 17)
	core.raider.global_position = Vector3(center + Vector3i(2, 0, 2)) + Vector3(0.5, 0.9, 0.5)
	core.raider_health = CoreDefenseService.RAIDER_MAX_HEALTH
	core.state = CoreDefenseService.ROUTING
	app.session.inventory.try_transaction({}, {"cannon": 1, "turret_catapult": 1, "tower_platform": 1, "rail": 8, "kettle": 2, "ballista": 1, "castle_stone": 32})

	# T131 cannon: a direct-fire weapon that launches a cannonball from its
	# barrel muzzle, recoils, and deals the cannonball's damage.
	var cannon := ws.try_place("cannon", center + Vector3i(-5, 0, -6), world.query_cell, AABB(), 0)
	var cannon_id := str(cannon.get("details", {}).get("station", {}).get("instance_id", ""))
	await get_tree().physics_frame
	_rearm(core)
	siege.face_target_now(cannon_id, core.raider_target_position())
	var cannon_body: Node3D = siege.visual_bodies.get(cannon_id)
	var barrel: Node3D = cannon_body.find_child("CannonBarrel", true, false) if cannon_body != null else null
	var cannon_trajectory := siege.trajectory_result(cannon_id, core.raider_target_position())
	var muzzle_origin: Vector3 = cannon_trajectory.get("origin", Vector3.ZERO)
	var muzzle_node: Node3D = cannon_body.find_child("SiegeMuzzle", true, false) if cannon_body != null else null
	var muzzle_matches := muzzle_node != null and muzzle_node.global_position.distance_to(muzzle_origin) < 0.01
	var health_before_cannon := core.raider_health
	var cannon_shot := siege._attempt_fire(cannon_id, ws.siege_status(cannon_id).get("details", {}), true)
	var cannon_ammo := int(ws.siege_status(cannon_id).get("details", {}).get("ammo", -1))
	var cannon_damage := health_before_cannon - core.raider_health
	_record("T131_CANNON", cannon.get("ok", false) and barrel != null and muzzle_matches and cannon_shot.get("ok", false) and cannon_ammo == 1 and cannon_damage == 14, "the cannon places on 2x3 ground, launches from its barrel muzzle and a cannonball deals 14", {"placed": cannon.get("reason"), "barrel": barrel != null, "muzzle_matches": muzzle_matches, "shot": cannon_shot.get("reason"), "ammo": cannon_ammo, "damage": cannon_damage})

	# T132 turret catapult: mounts on a tower platform's light_siege socket,
	# lobs stone shot with the shared arm animation nodes.
	core.raider_health = CoreDefenseService.RAIDER_MAX_HEALTH
	var tower := ws.try_place("tower_platform", center + Vector3i(4, 0, -6), world.query_cell, AABB(), 0)
	var turret := ws.try_place("turret_catapult", center + Vector3i(4, 1, -6), world.query_cell, AABB(), 0)
	var turret_id := str(turret.get("details", {}).get("station", {}).get("instance_id", ""))
	var turret_mount := str(turret.get("details", {}).get("mount", ""))
	await get_tree().physics_frame
	_rearm(core)
	siege.face_target_now(turret_id, core.raider_target_position())
	var turret_body: Node3D = siege.visual_bodies.get(turret_id)
	var turret_arm: Node3D = turret_body.find_child("CatapultArm", true, false) if turret_body != null else null
	var turret_shot := siege._attempt_fire(turret_id, ws.siege_status(turret_id).get("details", {}), true)
	var turret_ammo := int(ws.siege_status(turret_id).get("details", {}).get("ammo", -1))
	var turret_damage := CoreDefenseService.RAIDER_MAX_HEALTH - core.raider_health
	_record("T132_TURRET_CATAPULT", tower.get("ok", false) and turret.get("ok", false) and turret_mount == "light_siege" and turret_arm != null and turret_shot.get("ok", false) and turret_ammo == 3 and turret_damage == 9, "the turret catapult mounts on a tower platform socket, shares the catapult arm animation and lobs stone shot for 9", {"tower": tower.get("reason"), "turret": turret.get("reason"), "mount": turret_mount, "arm": turret_arm != null, "shot": turret_shot.get("reason"), "ammo": turret_ammo, "damage": turret_damage})

	# T133 rails and kettle: rails chain along a wall top; a kettle mounts only
	# on a rail, rides the chain to the raider at the wall foot, and dumps hot
	# oil straight down, lighting the ground and burning the raider.
	var wall_base := center + Vector3i(-3, 0, 3)
	for x in range(6):
		for y in range(3):
			world.set_cell(wall_base + Vector3i(x, y, 0), 8)
	var rails_ok := true
	for x in range(6):
		var rail := ws.try_place("rail", wall_base + Vector3i(x, 3, 0), world.query_cell, AABB(), 0)
		rails_ok = rails_ok and bool(rail.get("ok", false))
	var bad_kettle := ws.try_place("kettle", center + Vector3i(6, 0, 6), world.query_cell, AABB(), 0)
	var kettle := ws.try_place("kettle", wall_base + Vector3i(0, 4, 0), world.query_cell, AABB(), 0)
	var kettle_id := str(kettle.get("details", {}).get("station", {}).get("instance_id", ""))
	await get_tree().physics_frame
	_rearm(core)
	ws.siege_set_stance(cannon_id, "hold")
	ws.siege_set_stance(turret_id, "hold")
	core.raider_health = CoreDefenseService.RAIDER_MAX_HEALTH
	core.raider.global_position = Vector3(wall_base + Vector3i(5, 0, 1)) + Vector3(0.5, 0.9, 0.5)
	var far_before_ride := siege.trajectory_result(kettle_id, core.raider_target_position())
	var health_before_oil := core.raider_health
	var fired_frames := -1
	for frame in range(300):
		siege.advance(1.0 / 30.0, false)
		app.session.fire_service.advance(1.0 / 30.0, false)
		if fired_frames < 0 and int(ws.siege_status(kettle_id).get("details", {}).get("ammo", 2)) < 2:
			fired_frames = frame
		if fired_frames >= 0 and frame > fired_frames + 45:
			break
	var rider_cell := siege.rail_rider_cell(kettle_id)
	var kettle_ammo := int(ws.siege_status(kettle_id).get("details", {}).get("ammo", -1))
	var burning := app.session.fire_service.burning_cells().size()
	var oil_damage := health_before_oil - core.raider_health
	app.session.fire_service.extinguish_all()
	_record("T133_RAIL_KETTLE", rails_ok and bad_kettle.get("reason") == "INVALID_MOUNT" and kettle.get("ok", false) and str(kettle.get("details", {}).get("mount", "")) == "rail_mount" and far_before_ride.get("reason") == "TARGET_TOO_FAR" and rider_cell == wall_base + Vector3i(5, 3, 0) and fired_frames > 0 and kettle_ammo == 1 and burning > 0 and oil_damage >= 6, "six rails chain along a wall top; a kettle needs a rail mount, rides to the rail above the raider, dumps hot oil that lights the ground and burns the raider", {"rails": rails_ok, "bad_kettle": bad_kettle.get("reason"), "kettle": kettle.get("reason"), "mount": kettle.get("details", {}).get("mount", ""), "far_before_ride": far_before_ride.get("reason"), "rider_cell": rider_cell, "fired_frame": fired_frames, "ammo": kettle_ammo, "burning": burning, "damage": oil_damage})

	# T134 ballista presentation: the remodel exposes the slider, bolt and
	# strings; the bolt shows only while loaded and strings span tip to nock.
	var ballista := ws.try_place("ballista", center + Vector3i(-7, 0, 0), world.query_cell, AABB(), 0)
	var ballista_id := str(ballista.get("details", {}).get("station", {}).get("instance_id", ""))
	await get_tree().physics_frame
	_rearm(core)
	siege.advance(1.0 / 30.0, false)
	var ballista_body: Node3D = siege.visual_bodies.get(ballista_id)
	var slider: Node3D = ballista_body.find_child("BallistaSlider", true, false) if ballista_body != null else null
	var bolt: Node3D = ballista_body.find_child("BallistaBolt", true, false) if ballista_body != null else null
	var string_pivot: Node3D = ballista_body.find_child("BallistaString_L", true, false) if ballista_body != null else null
	var strand: Node3D = string_pivot.get_child(0) if string_pivot != null and string_pivot.get_child_count() > 0 else null
	var bolt_loaded := bolt != null and bolt.visible
	var strand_length := strand.scale.z if strand != null else 0.0
	var unloaded := ws.siege_unload(ballista_id)
	siege.advance(1.0 / 30.0, false)
	var bolt_after_unload := bolt != null and bolt.visible
	_record("T134_BALLISTA_PRESENTATION", ballista.get("ok", false) and slider != null and bolt_loaded and strand_length > 0.8 and strand_length < 2.5 and unloaded.get("ok", false) and not bolt_after_unload, "the remodelled ballista shows a drawn slider with a bolt while loaded, strings spanning from tips to nock, and hides the bolt once unloaded", {"placed": ballista.get("reason"), "slider": slider != null, "bolt_loaded": bolt_loaded, "strand": strand_length, "unloaded": unloaded.get("reason"), "bolt_after_unload": bolt_after_unload, "started": started.get("reason")})

	# T135 wave drill: a farther spawn line and several raiders (one brute);
	# splash damages every raider in radius, the nearest one is targeted, and
	# the drill is won only when the whole wave is down.
	core.clear_for_other_mode()
	_level_ground(center + Vector3i(-8, 0, -24), 17, 18)
	var wave := core.start_prototype({"raiders": 4, "brutes": 1, "spawn_distance": 20})
	core.warning_remaining = 0.0
	core._begin_attack()
	var wave_count := core.living_raider_count()
	var brutes := 0
	var far_spawns := 0
	for node in core.raider_nodes():
		node.active = false
		if node.kind == BasicRaider.KIND_BRUTE:
			brutes += 1
		if node.global_position.z <= float(center.z - 19):
			far_spawns += 1
	var cluster := Vector3(center + Vector3i(0, 0, -2)) + Vector3(0.5, 0.9, 0.5)
	var index := 0
	for node in core.raider_nodes():
		node.global_position = cluster + Vector3(float(index) * 0.8, 0.0, 0.0)
		index += 1
	var nearest := core.nearest_raider_position(cluster + Vector3(3.0, 0.0, 0.0))
	var nearest_is_last := nearest.distance_to(cluster + Vector3(2.4, 0.65, 0.0)) < 0.01
	var brute_only := core.nearest_raider_position(cluster, "brute")
	var splash_hits := core.damage_raiders_within(cluster + Vector3(1.2, 0.65, 0.0), 1.5, 5, "test")
	var still_active := core.state == CoreDefenseService.ROUTING
	var killed := 0
	for node in core.raider_nodes():
		if core.try_damage_raider_node(node, 100, "test").get("reason", "") == "RAIDER_DEFEATED":
			killed += 1
	var snapshot := core.snapshot()
	_record("T135_WAVE_DRILL", wave.get("ok", false) and int(wave.get("spawn_distance", 0)) == 20 and wave_count == 4 and brutes == 1 and far_spawns == 4 and nearest_is_last and brute_only.is_finite() and splash_hits >= 2 and still_active and killed == 4 and core.state == CoreDefenseService.WON and int(snapshot.get("wave_size", 0)) == 4, "a wave drill spawns four raiders (one brute) twenty cells out; splash damages every raider in radius; the nearest raider is targeted; the drill is won only once the whole wave is down", {"wave": wave.get("reason"), "count": wave_count, "brutes": brutes, "far_spawns": far_spawns, "nearest_is_last": nearest_is_last, "brute_only": brute_only.is_finite(), "splash_hits": splash_hits, "still_active": still_active, "killed": killed, "state": core.state})


## Rendered evidence: the five machines (ballista, catapult, turret catapult on
## a tower platform, cannon, kettle on a rail-topped wall) in one 1280x720 view.
func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var player := app.session.player
	player.deactivate()
	var ws := app.session.workstations
	var world := app.session.world
	var origin := Vector3i(-6, 0, 36)
	_level_ground(origin + Vector3i(-2, 0, -2), 20, 14)
	app.session.inventory.try_transaction({}, {"ballista": 1, "catapult": 1, "turret_catapult": 1, "tower_platform": 1, "cannon": 1, "rail": 4, "kettle": 1})
	var placements := {
		"ballista": ws.try_place("ballista", origin + Vector3i(0, 0, 4), world.query_cell, AABB(), 0),
		"catapult": ws.try_place("catapult", origin + Vector3i(3, 0, 3), world.query_cell, AABB(), 0),
		"tower_platform": ws.try_place("tower_platform", origin + Vector3i(6, 0, 4), world.query_cell, AABB(), 0),
		"turret_catapult": ws.try_place("turret_catapult", origin + Vector3i(6, 1, 4), world.query_cell, AABB(), 0),
		"cannon": ws.try_place("cannon", origin + Vector3i(9, 0, 3), world.query_cell, AABB(), 0),
	}
	for x in range(4):
		for y in range(2):
			world.set_cell(origin + Vector3i(12 + x, y, 4), 8)
	var rails_ok := true
	for x in range(4):
		rails_ok = rails_ok and bool(ws.try_place("rail", origin + Vector3i(12 + x, 2, 4), world.query_cell, AABB(), 0).get("ok", false))
	placements["kettle"] = ws.try_place("kettle", origin + Vector3i(13, 3, 4), world.query_cell, AABB(), 0)
	var all_placed := rails_ok
	for key in placements:
		all_placed = all_placed and bool(placements[key].get("ok", false))
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(origin) + Vector3(8.5, 2.6, -5.0)
	player.look_at(Vector3(origin) + Vector3(8.5, 0.6, 4.0), Vector3.UP)
	player.camera.rotation.x = -0.12
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("p4-siege-units.png")
	if image == null:
		_record("T136_SIEGE_UNITS_RENDERED", false, "the five siege machines render in one 1280x720 view", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var mesh_parts := 0
	for key in ["cannon", "turret_catapult", "kettle"]:
		var body: Node3D = app.session._station_visuals.get(str(placements[key].get("details", {}).get("station", {}).get("instance_id", "")))
		if body != null:
			mesh_parts += body.find_children("*", "MeshInstance3D", true, false).size()
	_record("T136_SIEGE_UNITS_RENDERED", all_placed and error == OK and image.get_size() == Vector2i(1280, 720) and mesh_parts >= 40, "the ballista, catapult, turret catapult on its tower, cannon and kettle on a rail-topped wall render as distinct multi-part machines in one 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "placed": all_placed, "mesh_parts": mesh_parts, "rails": rails_ok})


## Fixture placements queue deferred replans that can stop the drill (the
## parked raider has no permitted route); the weapon tests only need a live,
## parked raider, so re-arm it after every frame.
func _rearm(core: CoreDefenseService) -> void:
	if is_instance_valid(core.raider):
		core.raider.active = false
	if core.core_integrity > 0 and core.raider_health > 0:
		core.state = CoreDefenseService.ROUTING


func _level_ground(origin: Vector3i, width: int, depth: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(origin + Vector3i(x, -1, z), 3)
			for y in range(6):
				app.session.world.set_cell(origin + Vector3i(x, y, z), 0)


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
