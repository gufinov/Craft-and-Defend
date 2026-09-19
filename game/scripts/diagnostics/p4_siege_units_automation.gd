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
		"save":
			await _run_save()
		"restore":
			await _run_restore()
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
	if is_instance_valid(core.raider):
		core.raider.revive()
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
	if is_instance_valid(core.raider):
		core.raider.revive()
	var tower := ws.try_place("tower_platform", center + Vector3i(4, 0, -6), world.query_cell, AABB(), 0)
	var turret := ws.try_place("turret_catapult", center + Vector3i(4, 1, -6), world.query_cell, AABB(), 0)
	var turret_id := str(turret.get("details", {}).get("station", {}).get("instance_id", ""))
	var turret_mount := str(turret.get("details", {}).get("mount", ""))
	await get_tree().physics_frame
	_rearm(core)
	siege.face_target_now(turret_id, core.raider_target_position())
	var raider_ground := Vector3i(center.x + 2, -1, center.z + 2)
	world.set_cell(raider_ground, 1)
	var turret_body: Node3D = siege.visual_bodies.get(turret_id)
	var turret_arm: Node3D = turret_body.find_child("CatapultArm", true, false) if turret_body != null else null
	var turret_shot := siege._attempt_fire(turret_id, ws.siege_status(turret_id).get("details", {}), true)
	var turret_ammo := int(ws.siege_status(turret_id).get("details", {}).get("ammo", -1))
	var turret_damage := CoreDefenseService.RAIDER_MAX_HEALTH - core.raider_health
	var scorched := int(world.query_cell(raider_ground).get("voxel_id", -1)) == 2
	_record("T132_TURRET_CATAPULT", tower.get("ok", false) and turret.get("ok", false) and turret_mount == "light_siege" and turret_arm != null and turret_shot.get("ok", false) and turret_ammo == 3 and turret_damage == 9 and scorched, "the turret catapult mounts on a tower platform socket, shares the catapult arm animation, lobs stone shot for 9 and the impact tears the grass under the raider to dirt", {"tower": tower.get("reason"), "turret": turret.get("reason"), "mount": turret_mount, "arm": turret_arm != null, "shot": turret_shot.get("reason"), "ammo": turret_ammo, "damage": turret_damage, "scorched": scorched})

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
	if is_instance_valid(core.raider):
		core.raider.revive()
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
	# A stack picked up on the cursor (the inventory click gesture) loads too.
	var inventory := app.session.inventory
	var bolt_slot := -1
	for index in range(F0Inventory.SLOT_COUNT):
		if str(inventory.slots[index].get("item_id", "")) == "ballista_bolt":
			bolt_slot = index
			break
	var picked := inventory.cursor_pick_slot(bolt_slot) if bolt_slot >= 0 else {"ok": false}
	var held_before := int(inventory.cursor_stack.get("count", 0))
	var cursor_one := ws.siege_load_from_cursor(ballista_id, true)
	var cursor_rest := ws.siege_load_from_cursor(ballista_id, false)
	var cursor_ammo := int(ws.siege_status(ballista_id).get("details", {}).get("ammo", -1))
	var cursor_empty := str(inventory.cursor_stack.get("item_id", "")).is_empty()
	var cursor_ok: bool = picked.get("ok", false) and held_before == 8 and cursor_one.get("ok", false) and int(cursor_one.get("details", {}).get("moved", 0)) == 1 and cursor_rest.get("ok", false) and cursor_ammo == 8 and cursor_empty
	_record("T134_BALLISTA_PRESENTATION", ballista.get("ok", false) and slider != null and bolt_loaded and strand_length > 0.8 and strand_length < 2.5 and unloaded.get("ok", false) and not bolt_after_unload and cursor_ok, "the remodelled ballista shows a drawn slider with a bolt while loaded, strings spanning from tips to nock, hides the bolt once unloaded, and a stack held on the cursor loads one (right-click) then the rest", {"placed": ballista.get("reason"), "slider": slider != null, "bolt_loaded": bolt_loaded, "strand": strand_length, "unloaded": unloaded.get("reason"), "bolt_after_unload": bolt_after_unload, "started": started.get("reason"), "cursor": {"picked": picked.get("reason"), "held": held_before, "one": cursor_one.get("reason"), "rest": cursor_rest.get("reason"), "ammo": cursor_ammo, "empty": cursor_empty}})

	# T135 wave drill: a farther spawn line and several raiders (one brute);
	# splash damages every raider in radius, the nearest one is targeted, and
	# the drill is won only when the whole wave is down.
	core.clear_for_other_mode()
	_level_ground(center + Vector3i(-8, 0, -24), 17, 18)
	var wave := core.start_prototype({"raiders": 4, "brutes": 1, "spawn_distance": 20})
	core.warning_remaining = 0.0
	core._begin_attack()
	var waited_wave := 0
	while core.last_route_reason == "WAITING_FOR_TERRAIN" and waited_wave < 600:
		await get_tree().process_frame
		waited_wave += 1
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

	# T142 far spawn on natural ground: the farthest wave line (28 cells) lies
	# outside the flat clearing; raiders spawn on the terrain surface there and
	# still find a route (or a permitted breach) toward the core.
	core.clear_for_other_mode()
	var far := core.start_prototype({"raiders": 3, "brutes": 0, "spawn_distance": 28})
	core.warning_remaining = 0.0
	core._begin_attack()
	# The far line may sit on terrain the streamer is still loading; the
	# service retries its capture every half second.
	var waited := 0
	while core.last_route_reason == "WAITING_FOR_TERRAIN" and waited < 600:
		await get_tree().process_frame
		waited += 1
	var far_count := core.living_raider_count()
	var routed := 0
	var reasons: Array[String] = []
	reasons.append(core.last_route_reason)
	if core.last_route_reason in ["OK", "ATTACK_OBSTRUCTION"]:
		routed += 1
	for entry in core.extra_raiders:
		reasons.append(str(entry.route_reason))
		if str(entry.route_reason) in ["OK", "ATTACK_OBSTRUCTION"]:
			routed += 1
	var on_surface := true
	for node in core.raider_nodes():
		var feet := node.feet_cell()
		var below := int(world.query_cell(feet + Vector3i.DOWN).get("voxel_id", 0))
		var at := int(world.query_cell(feet).get("voxel_id", 0))
		if below == 0 or at != 0:
			on_surface = false
		node.active = false
	_record("T142_FAR_SPAWN_NATURAL_GROUND", far.get("ok", false) and int(far.get("spawn_distance", 0)) == 28 and far_count == 3 and on_surface and routed == 3 and core.state == CoreDefenseService.ROUTING, "a 28-cell wave line over natural terrain spawns every raider on the surface and each one routes toward the core", {"far": far.get("reason"), "count": far_count, "on_surface": on_surface, "routed": routed, "reasons": reasons, "state": core.state, "waited_frames": waited})

	# T143 the enemy never gives up: walled in, the raider probes (ROUTING,
	# NO_PERMITTED_ROUTE) instead of failing the drill and re-plans once a gap
	# opens; a chest plugging the only gap is a breachable obstruction that the
	# raider attacks and destroys before continuing.
	core.clear_for_other_mode()
	for station_id: String in ws.stations.keys().duplicate():
		if ws.defense_status(station_id).get("ok", false):
			ws.try_damage(station_id, 9999)
	_level_ground(center + Vector3i(-8, 0, -10), 17, 19)
	var wall_z := center.z - 3
	for x in range(-7, 8):
		for y in range(3):
			world.set_cell(Vector3i(center.x + x, y, wall_z), 8)
	var walled := core.start_prototype()
	core.warning_remaining = 0.0
	core._begin_attack()
	var probing := core.last_route_reason
	var breaks_wall := core.active_target_type == "voxel"
	var still_routing := core.state == CoreDefenseService.ROUTING
	# Let it chew: 2 damage per hit against castle stone (90) breaks the cell
	# after 45 hits; then the wall has a hole.
	var wall_cell := core.active_target_cell
	core.raider.active = false
	core._on_raider_route_finished()
	var hits := 0
	while int(world.query_cell(wall_cell).get("voxel_id", 0)) != 0 and hits < 60:
		core._attack_structure()
		hits += 1
	var wall_broken := int(world.query_cell(wall_cell).get("voxel_id", -1)) == 0 and hits == 45
	# Rebuild that cell so the chest gap below is the only way through.
	world.set_cell(wall_cell, 8)
	await get_tree().process_frame
	# Open a 2-wide gap at x 0..1, plug it with a chest and cap the gap so the
	# chest cannot be climbed over.
	for x in range(2):
		for y in range(2):
			world.set_cell(Vector3i(center.x + x, y, wall_z), 0)
	app.session.inventory.try_transaction({}, {"chest": 1})
	var plug := ws.try_place("chest", Vector3i(center.x, 0, wall_z), world.query_cell, AABB(), 0)
	var plug_id := str(plug.get("details", {}).get("station", {}).get("instance_id", ""))
	var waited_stall := 0
	while core.active_target_id != plug_id and waited_stall < 240:
		await get_tree().process_frame
		waited_stall += 1
	var breach_reason := core.last_route_reason
	var breach_target := core.active_target_id
	core.raider.active = false
	core._on_raider_route_finished()
	var attacking := core.state == CoreDefenseService.ATTACKING_STRUCTURE
	for _hit in range(5):
		if ws.station(plug_id).is_empty():
			break
		core._attack_structure()
	var chest_gone := ws.station(plug_id).is_empty()
	await get_tree().process_frame
	await get_tree().process_frame
	var route_after := core.last_route_reason
	_record("T143_ENEMY_NEVER_GIVES_UP", walled.get("ok", false) and probing == "ATTACK_OBSTRUCTION" and breaks_wall and wall_broken and still_routing and plug.get("ok", false) and breach_reason == "ATTACK_OBSTRUCTION" and breach_target == plug_id and attacking and chest_gone and route_after == "OK", "a walled-in raider sets out to break the wall itself (voxel breach) instead of failing the drill, switches to the chest plugging a newly opened gap as the cheaper breach, destroys it and routes on to the core", {"walled": walled.get("reason"), "probing": probing, "breaks_wall": breaks_wall, "wall_broken": wall_broken, "wall_hits": hits, "still_routing": still_routing, "plug": plug.get("reason"), "breach_reason": breach_reason, "breach_target": breach_target, "attacking": attacking, "chest_gone": chest_gone, "route_after": route_after, "waited": waited_stall})

	# T147 hybrid rule: a brute passing a player-built structure turns on it
	# and smashes it; plain raiders keep rushing the core.
	core.clear_for_other_mode()
	for x in range(2):
		for y in range(3):
			world.set_cell(Vector3i(center.x + x, y, wall_z), 0)
	app.session.inventory.try_transaction({}, {"chest": 1})
	var bait := ws.try_place("chest", Vector3i(center.x + 4, 0, center.z + 1), world.query_cell, AABB(), 0)
	var bait_id := str(bait.get("details", {}).get("station", {}).get("instance_id", ""))
	var brute_wave := core.start_prototype({"raiders": 2, "brutes": 1})
	core.warning_remaining = 0.0
	core._begin_attack()
	var brute_entry: Dictionary = {}
	for entry in core.extra_raiders:
		if str(entry.kind) == BasicRaider.KIND_BRUTE:
			brute_entry = entry
	var brute_node: BasicRaider = brute_entry.get("node")
	if brute_node != null:
		brute_node.active = false
		brute_node.global_position = Vector3(center.x + 4.5, 0.9, center.z + 2.5)
	core.raider.active = false
	for _tick in range(30):
		core.advance(1.0 / 20.0, false)
	var diverted := str(brute_entry.get("phase", "")) == "attacking_structure" and str(brute_entry.get("target_id", "")) == bait_id
	var chest_before := int(ws.defense_status(bait_id).get("details", {}).get("integrity", -1))
	for _tick in range(40):
		core.advance(1.0 / 20.0, false)
	var chest_after := int(ws.defense_status(bait_id).get("details", {}).get("integrity", -1))
	var raider_still_routing := core.active_target_type == "core"
	_record("T147_BRUTE_SMASHES_DEFENSES", bait.get("ok", false) and brute_wave.get("ok", false) and brute_node != null and diverted and chest_after < chest_before and raider_still_routing, "a brute within reach of a chest turns on it and hits it (integrity drops) while the plain raider keeps its core route", {"bait": bait.get("reason"), "wave": brute_wave.get("reason"), "diverted": diverted, "phase": brute_entry.get("phase", ""), "target": brute_entry.get("target_id", ""), "chest_before": chest_before, "chest_after": chest_after, "raider_target": core.active_target_type})

	# T151 far attack: the wave spawns at the enemy base 150-200 cells away,
	# marches the generated surface (ghost-walking over unloaded ground) and
	# hands over to the local planner once inside the defended area.
	core.clear_for_other_mode()
	var generator: P1TerrainGenerator = world.terrain.generator
	var base := generator.enemy_base_cell()
	var far_attack := core.start_prototype({"raiders": 3, "brutes": 1, "from_enemy_base": true})
	core.warning_remaining = 0.0
	core._begin_attack()
	var base_distance := Vector2(float(base.x - center.x), float(base.z - center.z)).length()
	var spawned_far := true
	var routed_all := true
	for node in core.raider_nodes():
		var away := Vector2(node.global_position.x - center.x, node.global_position.z - center.z).length()
		if away < 100.0:
			spawned_far = false
		if node.route.size() < 50:
			routed_all = false
	var lead_start: Vector3 = core.raider.global_position
	for _frame in range(120):
		await get_tree().physics_frame
	var lead_moved := lead_start.distance_to(core.raider.global_position)
	var marching := core.last_route_reason == "MARCHING" and core.state == CoreDefenseService.ROUTING
	# Jump the lead to the handover ring and finish its march: the local
	# planner (or its terrain wait) takes over.
	core.raider.active = false
	core.raider.global_position = Vector3(center + Vector3i(0, 0, -10)) + Vector3(0.5, 0.9, 0.5)
	core._on_raider_route_finished()
	var handed_over := core.last_route_reason != "MARCHING"
	_record("T151_FAR_ATTACK_FROM_ENEMY_BASE", far_attack.get("ok", false) and base_distance >= 150.0 and base_distance <= 200.0 and spawned_far and routed_all and lead_moved >= 4.0 and marching and handed_over, "the enemy base lies 150-200 cells from home; a far wave spawns there with long surface routes, marches (ghost-walking unloaded ground) and hands over to the local planner inside the defended area", {"far": far_attack.get("reason"), "base": base, "base_distance": base_distance, "spawned_far": spawned_far, "routed_all": routed_all, "lead_moved": lead_moved, "marching": marching, "handover_reason": core.last_route_reason})
	core.clear_for_other_mode()

	# T152 the placed Core of Power is what the drill defends: the arena
	# centres on it, raider hits land on the station's integrity, and its
	# destruction fails the drill and removes the core.
	core.clear_for_other_mode()
	_level_ground(center + Vector3i(-8, 0, -10), 17, 19)
	app.session.inventory.try_transaction({}, {"core_of_power": 1})
	var core_anchor := center + Vector3i(4, 0, 4)
	var placed_core := ws.try_place("core_of_power", core_anchor, world.query_cell, AABB(), 0)
	var core_id := str(placed_core.get("details", {}).get("station", {}).get("instance_id", ""))
	var core_drill := core.start_prototype()
	var centred := core.core_station_id == core_id and core._core_cell() == core_anchor + Vector3i(1, 0, 1) and core.core_max_integrity == 240
	core.warning_remaining = 0.0
	core._begin_attack()
	var routed_to_core := core.last_route_reason == "OK" and core.active_target_type == "core"
	var approach := core._core_approach_cell(core.raider.feet_cell())
	var approach_adjacent := (approach - core._core_cell()).length() == 2.0
	core.raider.active = false
	core.state = CoreDefenseService.ATTACKING_CORE
	core._attack_core()
	var station_after_hit := int(ws.defense_status(core_id).get("details", {}).get("integrity", -1))
	var drill_after_hit := core.core_integrity
	ws.try_damage(core_id, 9999)
	await get_tree().process_frame
	var core_gone := ws.station(core_id).is_empty()
	var failed := core.state == CoreDefenseService.FAILED and core.core_integrity == 0
	_record("T152_PLACED_CORE_DEFENDED", placed_core.get("ok", false) and core_drill.get("ok", false) and centred and routed_to_core and approach_adjacent and station_after_hit == 234 and drill_after_hit == 234 and core_gone and failed, "the drill centres on the placed Core of Power (240 integrity), routes raiders to a free cell beside it, mirrors hits onto the station and fails when the core is destroyed", {"placed": placed_core.get("reason"), "drill": core_drill.get("reason"), "centred": centred, "routed": routed_to_core, "route_reason": core.last_route_reason, "approach": approach, "station_after_hit": station_after_hit, "drill_after_hit": drill_after_hit, "core_gone": core_gone, "failed": failed})
	core.clear_for_other_mode()

	# T153 aggro and player health: a sword hit provokes the raider, which
	# chases the player and hits back (health drops, HUD shows it); a machine
	# hit provokes a chase of that machine; attention lapses back to the core.
	core.clear_for_other_mode()
	_level_ground(center + Vector3i(-8, 0, -10), 17, 19)
	var aggro := core.start_prototype({"raiders": 2})
	core.warning_remaining = 0.0
	core._begin_attack()
	var player := app.session.player
	player.restore_health()
	core.raider.active = false
	core.raider.global_position = Vector3(center + Vector3i(0, 0, -4)) + Vector3(0.5, 0.9, 0.5)
	player.global_position = Vector3(center + Vector3i(0, 0, -6)) + Vector3(0.5, 1.0, 0.5)
	await get_tree().physics_frame
	_rearm(core)
	app.session.inventory.try_transaction({}, {"iron_sword": 1})
	var sword_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "iron_sword":
			sword_slot = slot_index
	if sword_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(sword_slot, 0)
		sword_slot = 0
	app.session.inventory.select_hotbar(sword_slot)
	app.session._melee_cooldown = 0.0
	var eye := player.global_position + Vector3(0.0, 0.6, 0.0)
	var to_raider := (core.raider.global_position + Vector3.UP * 0.65 - eye).normalized()
	var swing := app.session._player_primary_action(eye, to_raider)
	var provoked := not core._primary_chase.is_empty() and str(core._primary_chase.get("kind", "")) == "player"
	var health_before := player.health
	for _tick in range(50):
		core.advance(0.1, false)
	var hit_back := player.health < health_before and core.player_hits > 0
	# Attention lapses: push the clock past the window and the raider re-plans.
	core._primary_chase["until"] = Time.get_ticks_msec() - 1
	core.advance(0.1, false)
	await get_tree().process_frame
	var back_to_core := core._primary_chase.is_empty() and core.active_target_type == "core"
	# A machine hit provokes a chase of that machine.
	app.session.inventory.try_transaction({}, {"chest": 1})
	var bait_chest := ws.try_place("chest", center + Vector3i(3, 0, -4), world.query_cell, AABB(), 0)
	var bait_chest_id := str(bait_chest.get("details", {}).get("station", {}).get("instance_id", ""))
	core.notify_raider_provoked(core.raider, bait_chest_id)
	var chases_machine := str(core._primary_chase.get("kind", "")) == "structure" and str(core._primary_chase.get("id", "")) == bait_chest_id
	for _frame in range(150):
		core.advance(1.0 / 60.0, false)
		await get_tree().physics_frame
	var chest_hurt := int(ws.defense_status(bait_chest_id).get("details", {}).get("integrity", 24)) < 24
	# Death respawns at full health beside the core/home.
	player.take_damage(999, "test")
	var respawned := player.health == PlayerController.MAX_HEALTH
	_record("T153_AGGRO_AND_PLAYER_HEALTH", aggro.get("ok", false) and swing.get("ok", false) and provoked and hit_back and back_to_core and chases_machine and chest_hurt and respawned, "a sword hit lands and provokes the raider, which chases and hits the player (health drops); when attention lapses it returns to the core; a machine that hurt it gets chased and hit; the player respawns at full health", {"aggro": aggro.get("reason"), "swing": swing.get("reason"), "provoked": provoked, "hit_back": hit_back, "health_after": player.health if not respawned else health_before, "player_hits": core.player_hits, "back_to_core": back_to_core, "route": core.last_route_reason, "chases_machine": chases_machine, "chest_hurt": chest_hurt, "respawned": respawned})
	core.clear_for_other_mode()

	# T154 rail aiming and patrol: aiming at a rail from above lands the kettle
	# on the cell over the rail (the aim stops at entity-owned cells); Patrol
	# rides the chain end to end while idle.
	core.clear_for_other_mode()
	var rail_base := center + Vector3i(-6, 0, 6)
	for x in range(5):
		for y in range(2):
			world.set_cell(rail_base + Vector3i(x, y, 0), 8)
	app.session.inventory.try_transaction({}, {"rail": 5, "kettle": 1})
	var rails_laid := true
	for x in range(5):
		rails_laid = rails_laid and bool(app.session.interaction.try_place_item(rail_base + Vector3i(x, 2, 0), "rail").get("ok", false))
	var aim_origin := Vector3(rail_base) + Vector3(2.5, 6.0, 0.5)
	var aim_cell := app.session.interaction.placement_anchor_from_view(aim_origin, Vector3.DOWN)
	var aimed_above_rail := aim_cell == rail_base + Vector3i(2, 3, 0)
	var kettle_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "kettle":
			kettle_slot = slot_index
	if kettle_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(kettle_slot, 1)
		kettle_slot = 1
	app.session.inventory.select_hotbar(kettle_slot)
	var kettle_from_view := app.session.interaction.place_from_view(aim_origin, Vector3.DOWN)
	var patrol_id := ""
	for station_id: String in ws.stations.keys():
		if str(ws.stations[station_id].get("entity_id", "")) == "kettle" and ws.stations[station_id].get("anchor", Vector3i.ZERO) == rail_base + Vector3i(2, 3, 0):
			patrol_id = station_id
	var patrol := ws.siege_set_stance(patrol_id, "patrol")
	var catapult_patrol := ws.siege_set_stance(turret_id, "patrol") if ws.stations.has(turret_id) else {"reason": "NOT_A_RAIL_WEAPON"}
	await get_tree().physics_frame
	var visited: Dictionary = {}
	for _frame in range(240):
		siege.advance(1.0 / 30.0, false)
		visited[siege.rail_rider_cell(patrol_id)] = true
	var reached_both_ends := visited.has(rail_base + Vector3i(0, 2, 0)) and visited.has(rail_base + Vector3i(4, 2, 0))
	_record("T154_RAIL_AIM_AND_PATROL", rails_laid and aimed_above_rail and kettle_from_view.get("ok", false) and not patrol_id.is_empty() and patrol.get("ok", false) and catapult_patrol.get("reason") == "NOT_A_RAIL_WEAPON" and reached_both_ends, "aiming down at a rail places the kettle on the cell above it; Patrol is a rail-weapon stance that rides the chain from end to end while idle", {"rails": rails_laid, "aim_cell": aim_cell, "placed": kettle_from_view.get("reason"), "patrol": patrol.get("reason"), "catapult_patrol": catapult_patrol.get("reason"), "visited": visited.size(), "both_ends": reached_both_ends})


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
	app.session.inventory.try_transaction({}, {"ballista": 1, "catapult": 1, "turret_catapult": 1, "turret_catapult_mk2": 1, "tower_platform": 1, "cannon": 1, "rail": 4, "kettle": 1})
	var placements := {
		"turret_catapult_mk2": ws.try_place("turret_catapult_mk2", origin + Vector3i(-3, 0, 4), world.query_cell, AABB(), 0),
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
	player.global_position = Vector3(origin) + Vector3(7.0, 3.0, -7.5)
	player.look_at(Vector3(origin) + Vector3(7.0, 0.6, 4.0), Vector3.UP)
	player.camera.rotation.x = -0.12
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("p4-siege-units.png")
	var minimap_visible := app.minimap != null and app.minimap.visible and app.minimap.generator != null
	if image == null:
		_record("T136_SIEGE_UNITS_RENDERED", false, "the five siege machines render in one 1280x720 view", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var mesh_parts := 0
	for key in ["cannon", "turret_catapult", "kettle", "turret_catapult_mk2"]:
		var body: Node3D = app.session._station_visuals.get(str(placements[key].get("details", {}).get("station", {}).get("instance_id", "")))
		if body != null:
			mesh_parts += body.find_children("*", "MeshInstance3D", true, false).size()
	_record("T136_SIEGE_UNITS_RENDERED", all_placed and error == OK and image.get_size() == Vector2i(1280, 720) and mesh_parts >= 60 and minimap_visible, "the turret catapult mk2, ballista, catapult, turret catapult on its tower, cannon and kettle on a rail-topped wall render as distinct multi-part machines in one 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "placed": all_placed, "mesh_parts": mesh_parts, "rails": rails_ok})


## T141 wave persistence: a running wave (three raiders, one brute, two of
## them damaged) checkpoints and a clean-process Continue rebuilds every raider
## with its kind and health.
func _run_save() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var core := app.session.core_defense
	var wave := core.start_prototype({"raiders": 3, "brutes": 1, "spawn_distance": 14})
	if not wave.get("ok", false):
		_record("T141_WAVE_CHECKPOINT_SAVE", false, "the wave drill starts before checkpointing", wave)
		return
	core.warning_remaining = 0.0
	core._begin_attack()
	for node in core.raider_nodes():
		node.active = false
	core.raider_health = 11
	var brute_hit := {"ok": false}
	for node in core.raider_nodes():
		if node.kind == BasicRaider.KIND_BRUTE:
			brute_hit = core.try_damage_raider_node(node, 15, "test")
	var saved := await app.saves.save_session(app.session)
	_record("T141_WAVE_CHECKPOINT_SAVE", saved.get("ok", false) and core.living_raider_count() == 3 and brute_hit.get("ok", false), "one atomic checkpoint stores the wave: three raiders, the lead at 11, the brute at 25", {"save": saved.get("reason"), "core": core.snapshot()})


func _run_restore() -> void:
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var core := app.session.core_defense
	var kinds: Array[String] = []
	var brute_health := -1
	for node in core.raider_nodes():
		kinds.append(node.kind)
	for entry in core.extra_raiders:
		if str(entry.kind) == BasicRaider.KIND_BRUTE:
			brute_health = int(entry.health)
	kinds.sort()
	var restored: bool = core.is_active() and core.living_raider_count() == 3 and core.raider_health == 11 and brute_health == 25 and kinds == ["brute", "raider", "raider"] and core.wave_size == 3 and core.spawn_distance == 14
	_record("T141_WAVE_CHECKPOINT_RESTORE", restored, "a clean-process Continue rebuilds the wave: three living raiders (one brute at 25), the lead raider at 11, wave size and spawn distance intact", {"core": core.snapshot(), "kinds": kinds, "brute_health": brute_health})


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
