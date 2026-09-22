class_name DevelopmentExpoAutomation
extends Node

## Development Expo gate (docs/DEVELOPMENT_EXPO.md, docs/TEST_PLAN.md T213-T220).
## This suite is the milestone's home: each Expo card adds its own records to it.
##
##   --development-expo-automation=gate    headless: T213 layout, T214 plaza /
##                                         Day One / mountain, T215 signs, T218
##                                         Construction Yard, T219 Defense Range,
##                                         T220 Battlefield
##   --development-expo-automation=visual  windowed: the plaza, a sign, the
##                                         mountain tunnel, the Construction
##                                         Yard, the Defense Range and the
##                                         Battlefield mid-attack
##
## The layout half (T213) needs no world; everything else opens a fresh
## Development world, walks the player round the campus so the whole fixture
## builds, and then reads the voxels, the stations and the live services back
## out district by district.

const AIR := 0
const STONE := 3
const COAL_ORE := 6
const IRON_ORE := 7
const GOLD_ORE := 11
const CASTLE_STONE := 8
## Cells of the mountain tunnel walked in a straight line.
const TUNNEL_WALK := 56
## A tunnel sample counts as lit with a light entity this near.
const LIGHT_RANGE := 12.0
const BUILD_TIMEOUT_MSEC := 420000
## Work units the gate pushes through the builder itself each frame, on top of
## the builder's own per-frame budget (`ExpoBuilder.advance` exists for this):
## the campus is three districts bigger than it was and a headless gate has no
## frame to protect.
const BUILD_BUDGET_PER_FRAME := 2400
## Frames spent at each district while driving the build round the campus.
const BUILD_FRAMES_PER_STOP := 150
## How long one Battlefield assault may take to muster, close on the core and
## be shot at (the drill's own warning countdown is 20 seconds of it).
const ATTACK_TIMEOUT_MSEC := 120000
## How long a drained weapon may take to be reloaded from the storage beside it.
const RELOAD_TIMEOUT_MSEC := 30000
## How much nearer the core a wave has to get before it counts as closing in.
const CLOSING_CELLS := 6.0

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
	_write_json(app.data_root.path_join("development_expo_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("DEVELOPMENT_EXPO_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("DEVELOPMENT_EXPO_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	_test_layout()
	app._on_development_new_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	await _drive_build()
	if not await _wait_built("plaza"):
		return
	await _test_plaza_and_day_one()
	await _test_mountain()
	await _test_construction_yard()
	await _test_defense_range()
	await _test_battlefield()
	_test_signs()
	await _settle_near_spawn()


func _run_visual() -> void:
	app._on_development_new_pressed()
	if not await _wait_ready():
		return
	if not await _wait_built("plaza"):
		return
	var plaza := app.development.layout.district_bounds("central_plaza")
	var plaza_origin: Vector3i = plaza["origin"]
	var plaza_size: Vector3i = plaza["size"]
	var plaza_eye := Vector3(plaza_origin) + Vector3(float(plaza_size.x) * 0.5, 9.0, -6.0)
	var plaza_target := Vector3(plaza_origin) + Vector3(float(plaza_size.x) * 0.5, 1.0, float(plaza_size.z) * 0.5)
	_look_from(plaza_eye, plaza_target)
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(plaza_eye, plaza_target)
	await get_tree().process_frame
	var plaza_path := app.data_root.path_join("development-expo-plaza.png")
	var plaza_shot := await _save_viewport(plaza_path)
	_record("T214V_PLAZA_VIEW", plaza_shot, "rendered evidence of the Development Expo plaza with its Core", {"path": plaza_path})
	await _shoot_sign("central_plaza")
	var tunnel := app.development.layout.parcel_for("mountain_tunnel")
	var tunnel_origin: Vector3i = tunnel["origin"]
	var tunnel_size: Vector3i = tunnel["size"]
	var mouth := Vector3(float(tunnel_origin.x + tunnel_size.x - 3), float(tunnel_origin.y) + 1.6, float(tunnel_origin.z + tunnel_size.z / 2) + 0.5)
	_teleport(mouth)
	if not await _wait_built("mountain"):
		return
	_look_from(mouth, mouth + Vector3(-20.0, -1.0, 0.0))
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(mouth, mouth + Vector3(-20.0, -1.0, 0.0))
	await get_tree().process_frame
	var tunnel_path := app.data_root.path_join("development-expo-tunnel.png")
	var tunnel_shot := await _save_viewport(tunnel_path)
	_record("T214V_TUNNEL_VIEW", tunnel_shot, "rendered evidence of the lit mountain tunnel with its rail line", {"path": tunnel_path})
	await _shoot_card_e_districts()
	await _settle_near_spawn()


## Reading evidence for the eastern half of the campus: the Construction Yard's
## kit and the castle built from it, the Defense Range's booth line, and the
## Battlefield with an assault actually crossing it.
func _shoot_card_e_districts() -> void:
	if not await _walk_to_district("construction_yard"):
		return
	var castle := app.development.layout.parcel_for("cy_castle_demo")
	var castle_origin: Vector3i = castle["origin"]
	var castle_size: Vector3i = castle["size"]
	await _shoot("T218V_CONSTRUCTION_VIEW",
		Vector3(castle_origin) + Vector3(float(castle_size.x) * 0.5, 16.0, float(castle_size.z) + 18.0),
		Vector3(castle_origin) + Vector3(float(castle_size.x) * 0.5, 2.0, float(castle_size.z) * 0.5),
		"development-expo-construction.png",
		"rendered evidence of the Construction Yard: the castle pieces on their signed booths and the small castle assembled from them")
	if not await _walk_to_district("defense_range"):
		return
	var range_bounds := app.development.layout.district_bounds("defense_range")
	var range_origin: Vector3i = range_bounds["origin"]
	var range_size: Vector3i = range_bounds["size"]
	await _shoot("T219V_RANGE_VIEW",
		Vector3(range_origin) + Vector3(float(range_size.x) * 0.5, 16.0, float(range_size.z) + 6.0),
		Vector3(range_origin) + Vector3(float(range_size.x) * 0.5, 2.0, float(range_size.z) * 0.4),
		"development-expo-range.png",
		"rendered evidence of the Defense Range: six weapon booths, each on its mount with its ammunition chest, target and sign")
	var core_parcel := app.development.layout.parcel_for("battlefield_player_core")
	var core_origin: Vector3i = core_parcel["origin"]
	if not await _walk_to(core_origin + Vector3i(1, 0, 8), "battlefield"):
		return
	app.battlefield_start_attack()
	var deadline := Time.get_ticks_msec() + ATTACK_TIMEOUT_MSEC
	while app.session.core_defense.living_raider_count() == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	for _frame in range(300):
		await get_tree().process_frame
	await _shoot("T220V_BATTLEFIELD_VIEW",
		Vector3(core_origin) + Vector3(1.5, 13.0, 12.0),
		Vector3(core_origin) + Vector3(1.5, 1.0, -22.0),
		"development-expo-battlefield.png",
		"rendered evidence of the Battlefield mid-attack: the Core behind its gate, the batteries either side and the wave crossing the open ground from the enemy core")
	app.session.core_defense.clear_for_other_mode()


func _shoot(test_id: String, eye: Vector3, target: Vector3, file_name: String, expected: String) -> void:
	_look_from(eye, target)
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(eye, target)
	await get_tree().process_frame
	var path := app.data_root.path_join(file_name)
	var shot := await _save_viewport(path)
	_record(test_id, shot, expected, {"path": path})


## T213: the manifest, the solved layout and the computed world bounds, with no
## world open.
func _test_layout() -> void:
	var registry := ContentRegistry.new()
	var first := ExpoLayout.new()
	var loaded := first.load_layout()
	var second := ExpoLayout.new()
	second.load_layout()
	var report := first.report()
	var unknown_ids: Array[String] = []
	var reserved_with_content: Array[String] = []
	var signs := 0
	for exhibit_id: String in first.exhibit_ids():
		var record := first.exhibit(exhibit_id)
		for entity_id: Variant in record.get("entities", []):
			if registry.entity(str(entity_id)).is_empty():
				unknown_ids.append("entity " + str(entity_id))
		for item_id: Variant in record.get("items", []):
			if registry.item(str(item_id)).is_empty():
				unknown_ids.append("item " + str(item_id))
		if not first.sign_data(exhibit_id).is_empty():
			signs += 1
		if str(record.get("kind", "")) == "reserved":
			var entities: Variant = record.get("entities", [])
			var items: Variant = record.get("items", [])
			if (entities is Array and not (entities as Array).is_empty()) or (items is Array and not (items as Array).is_empty()):
				reserved_with_content.append(exhibit_id)
	var bounds := first.world_bounds()
	var minimum: Vector3i = bounds["min"]
	var size: Vector3i = bounds["size"]
	var chunk := int(first.manifest.get("chunk_size", 16))
	var margin := int(first.manifest.get("expansion_margin", 0))
	var margin_ok := true
	for exhibit_id: String in first.exhibit_ids():
		var parcel := first.parcel_for(exhibit_id)
		var parcel_origin: Vector3i = parcel["origin"]
		var parcel_size: Vector3i = parcel["size"]
		margin_ok = margin_ok and parcel_origin.x - margin >= minimum.x and parcel_origin.z - margin >= minimum.z \
			and parcel_origin.x + parcel_size.x + margin <= minimum.x + size.x \
			and parcel_origin.z + parcel_size.z + margin <= minimum.z + size.z
	var aligned: bool = size.x % chunk == 0 and size.y % chunk == 0 and size.z % chunk == 0
	var deterministic: bool = first.fingerprint() == second.fingerprint() and not first.fingerprint().is_empty()
	var corridors_ok: bool = (report.get("without_corridor", []) as Array).is_empty()
	var overlaps_ok: bool = (report.get("overlaps", []) as Array).is_empty()
	var contained: bool = (report.get("outside_world_bounds", []) as Array).is_empty()
	var ok: bool = loaded.get("ok", false) and unknown_ids.is_empty() and reserved_with_content.is_empty() \
		and int(report.get("reserved_parcels", 0)) >= 1 and corridors_ok and overlaps_ok and contained \
		and margin_ok and aligned and deterministic and signs > 0
	_record("T213_EXPO_LAYOUT", ok,
		"the Expo manifest parses, every referenced item/entity id exists, no two parcels or districts overlap, every district has an expansion corridor, the reserved parcels are empty and signed, the chunk-aligned world bounds hold every parcel plus the expansion margin, and two loads of the same manifest solve identically",
		{"loaded": loaded.get("reason", "ok"), "unknown_ids": unknown_ids, "reserved_with_content": reserved_with_content,
		"report": report, "world_min": minimum, "world_size": size, "chunk_aligned": aligned, "margin_ok": margin_ok,
		"deterministic": deterministic, "signs": signs})


## T214 part one: the plaza is level and clear where the player spawns, the
## development Core stands, and the Day One chain's stations are in book order.
func _test_plaza_and_day_one() -> void:
	var layout: ExpoLayout = app.development.layout
	var world: WorldAdapter = app.session.world
	var ground := layout.ground_y()
	var spawn := layout.spawn_feet()
	var spawn_cell := Vector3i(int(floor(spawn.x)), ground, int(floor(spawn.z)))
	var solid := 0
	var clear := 0
	var sampled := 0
	for x in range(-6, 7, 2):
		for z in range(-6, 7, 2):
			var floor_cell := spawn_cell + Vector3i(x, 0, z)
			var floor_query := world.query_cell(floor_cell)
			if str(floor_query.get("state", "")) != "LOADED":
				continue
			sampled += 1
			if int(floor_query.get("voxel_id", AIR)) != AIR:
				solid += 1
			if int(world.query_cell(floor_cell + Vector3i(0, 1, 0)).get("voxel_id", 1)) == AIR \
					and int(world.query_cell(floor_cell + Vector3i(0, 2, 0)).get("voxel_id", 1)) == AIR:
				clear += 1
	var core_parcel := layout.parcel_for("plaza_core")
	var core_anchor: Vector3i = core_parcel["origin"]
	var core_id := app.session.workstations.station_at_cell(core_anchor)
	var core_ok: bool = not core_id.is_empty() and str(app.session.workstations.station(core_id).get("entity_id", "")) == "core_of_power"
	var chain: Array[String] = ["day_one_tree", "day_one_log", "day_one_planks", "day_one_sticks", "day_one_workbench",
		"day_one_wood_pick", "day_one_stone", "day_one_stone_pick", "day_one_furnace", "day_one_iron", "day_one_iron_pick"]
	var order_ok := true
	var previous := Vector3i(-99999, 0, -99999)
	var present: Array[String] = []
	for exhibit_id: String in chain:
		var parcel := layout.parcel_for(exhibit_id)
		if parcel.is_empty():
			order_ok = false
			continue
		var origin: Vector3i = parcel["origin"]
		# The chain reads along +x within a row, rows run +z: never backwards.
		if origin.z < previous.z or (origin.z == previous.z and origin.x <= previous.x):
			order_ok = false
		previous = origin
		if _exhibit_present(exhibit_id, origin, parcel["size"]):
			present.append(exhibit_id)
	var stations_ok: bool = present.has("day_one_workbench") and present.has("day_one_furnace")
	var ok: bool = sampled > 0 and solid == sampled and clear == sampled and core_ok and order_ok and present.size() == chain.size() and stations_ok
	_record("T214_EXPO_PLAZA_AND_DAY_ONE", ok,
		"after a Development New the plaza is level and clear around the spawn, the development Core of Power stands on it, and all eleven Day One exhibits are built in chain order with the Workbench and Furnace standing",
		{"sampled": sampled, "solid": solid, "clear": clear, "core": core_id, "order_ok": order_ok,
		"present": present, "missing": chain.size() - present.size()})


## T214 part two: the mountain's authored ore core, the lit and traversable
## tunnel and the rail line inside it.
func _test_mountain() -> void:
	var layout: ExpoLayout = app.development.layout
	var tunnel := layout.parcel_for("mountain_tunnel")
	var tunnel_origin: Vector3i = tunnel["origin"]
	var tunnel_size: Vector3i = tunnel["size"]
	var centre_z := tunnel_origin.z + tunnel_size.z / 2
	# Walk in from the campus side of the mountain.
	_teleport(Vector3(float(tunnel_origin.x + tunnel_size.x - 3), float(tunnel_origin.y) + 1.1, float(centre_z) + 0.5))
	if not await _wait_built("mountain"):
		return
	var world: WorldAdapter = app.session.world
	var core := layout.parcel_for("mountain_ore_core")
	var core_origin: Vector3i = core["origin"]
	var core_size: Vector3i = core["size"]
	var ores := {COAL_ORE: 0, IRON_ORE: 0, GOLD_ORE: 0}
	var core_sampled := 0
	for x in range(0, core_size.x, 3):
		for y in range(0, core_size.y, 2):
			for z in range(0, core_size.z, 3):
				var query := world.query_cell(core_origin + Vector3i(x, y, z))
				if str(query.get("state", "")) != "LOADED":
					continue
				core_sampled += 1
				var voxel := int(query.get("voxel_id", AIR))
				if ores.has(voxel):
					ores[voxel] = int(ores[voxel]) + 1
	var walkable := 0
	var lit := 0
	var walked := 0
	var lights := _light_positions()
	for step in range(TUNNEL_WALK):
		var cell := Vector3i(tunnel_origin.x + tunnel_size.x - 3 - step, tunnel_origin.y, centre_z)
		var head := world.query_cell(cell + Vector3i(0, 1, 0))
		var feet := world.query_cell(cell)
		if str(feet.get("state", "")) != "LOADED" or str(head.get("state", "")) != "LOADED":
			continue
		walked += 1
		var floor_voxel := int(world.query_cell(cell + Vector3i(0, -1, 0)).get("voxel_id", AIR))
		if int(feet.get("voxel_id", 1)) == AIR and int(head.get("voxel_id", 1)) == AIR and floor_voxel != AIR:
			walkable += 1
		for light: Vector3 in lights:
			if light.distance_to(Vector3(cell)) <= LIGHT_RANGE:
				lit += 1
				break
	var rails: Array[Vector3i] = []
	for instance_id: String in app.session.workstations.stations.keys():
		var record: Dictionary = app.session.workstations.stations[instance_id]
		if str(record.get("entity_id", "")) == "rail":
			rails.append(record.get("anchor", Vector3i.ZERO))
	rails.sort_custom(func(first: Vector3i, second: Vector3i) -> bool: return first.x < second.x)
	var chained := rails.size() > 1
	for index in range(1, rails.size()):
		if rails[index] - rails[index - 1] != Vector3i(1, 0, 0):
			chained = false
	var miner_ok := false
	var bin_ok := false
	for instance_id: String in app.session.workstations.stations.keys():
		var entity_id := str((app.session.workstations.stations[instance_id] as Dictionary).get("entity_id", ""))
		miner_ok = miner_ok or entity_id == "miner"
		bin_ok = bin_ok or entity_id == "ore_bin"
	var ore_ok: bool = int(ores[COAL_ORE]) > 0 and int(ores[IRON_ORE]) > 0 and int(ores[GOLD_ORE]) > 0
	var ok: bool = ore_ok and walked >= TUNNEL_WALK / 2 and walkable == walked and lit == walked \
		and chained and rails.size() >= 32 and miner_ok and bin_ok
	_record("T214_EXPO_MOUNTAIN", ok,
		"the mountain's authored ore core holds coal, iron and gold voxels; a straight walk of %d cells down the tunnel is unobstructed, floored and within %d cells of a light the whole way; the rail line inside chains cell by cell; the automated-mining exhibit's Miner and Ore Bin stand" % [TUNNEL_WALK, int(LIGHT_RANGE)],
		{"ores": ores, "core_sampled": core_sampled, "walked": walked, "walkable": walkable, "lit": lit,
		"rails": rails.size(), "chained": chained, "lights": lights.size(), "miner": miner_ok, "ore_bin": bin_ok,
		"builder": app.development.expo_builder.progress()})


## T218: the Construction Yard shows every castle piece on its own booth and
## then the same pieces assembled - a drag-built wall, a stamped blueprint and
## a small castle - each of them signed.
func _test_construction_yard() -> void:
	var layout: ExpoLayout = app.development.layout
	if not await _walk_to_district("construction_yard"):
		return
	var pieces := {"cy_stone_stair": "stone_stair", "cy_wall_walk_slab": "wall_walk_slab",
		"cy_parapet_merlon": "parapet_merlon", "cy_tower_platform": "tower_platform",
		"cy_gate_frame": "gate_frame", "cy_wood_barricade": "wood_barricade"}
	var missing_pieces: Array[String] = []
	for exhibit_id: String in pieces.keys():
		if _stations_in(_parcel_box(exhibit_id), str(pieces[exhibit_id])).is_empty():
			missing_pieces.append(exhibit_id)
	var stone_booth: bool = _voxels_in(_parcel_box("cy_castle_stone"), CASTLE_STONE) > 0
	var unsigned: Array[String] = []
	for exhibit_id: String in layout.exhibit_ids("construction_yard"):
		if not _sign_placed(exhibit_id):
			unsigned.append(exhibit_id)
	# The drag-built wall: a run of castle stone with a battlemented top.
	var wall_box := _parcel_box("cy_drag_wall")
	var wall_stone := _voxels_in(wall_box, CASTLE_STONE)
	var wall_deck := _stations_in(wall_box, "wall_walk_slab").size()
	var wall_merlons := _stations_in(wall_box, "parapet_merlon").size()
	# The stamped blueprint: the P3K stack, recorded as stamps so a later piece
	# snaps to its sockets exactly as a player-stamped one would.
	var stamp_box := _parcel_box("cy_blueprint_stamp")
	var stamp_stone := _voxels_in(stamp_box, CASTLE_STONE)
	var stamped: Array[String] = []
	for entry: Variant in app.session.interaction.stamps_snapshot():
		stamped.append(str((entry as Dictionary).get("blueprint_id", "")))
	var stamps_ok: bool = stamped.has("foundation_4") and stamped.has("tower_segment_4") and stamped.has("cap_4")
	# The payoff: the kit assembled into something that defends.
	var castle_box := _parcel_box("cy_castle_demo")
	var castle_stone := _voxels_in(castle_box, CASTLE_STONE)
	var castle_gate: bool = not _stations_in(castle_box, "gate_frame").is_empty()
	var castle_platform: bool = not _stations_in(castle_box, "tower_platform").is_empty()
	var castle_stairs := _stations_in(castle_box, "stone_stair").size()
	var reserved_empty: bool = _stations_in(_parcel_box("cy_expansion_reserved"), "").is_empty()
	var ok: bool = missing_pieces.is_empty() and stone_booth and unsigned.is_empty() \
		and wall_stone >= 36 and wall_deck >= 8 and wall_merlons >= 4 \
		and stamp_stone > 0 and stamps_ok \
		and castle_stone > 0 and castle_gate and castle_platform and castle_stairs >= 3 and reserved_empty
	_record("T218_EXPO_CONSTRUCTION", ok,
		"the Construction Yard stands each castle piece on its own signed booth and then shows them assembled: a drag-built run of castle stone with a wall-walk deck and merlons on it, the FOUNDATION 4 / TOWER SEGMENT 4 / CAP 4 blueprint stack stamped and recorded as stamps, and a small castle with a gate frame, a stair and a tower platform; the future-castle-technology parcel is signed and empty",
		{"missing_pieces": missing_pieces, "castle_stone_booth": stone_booth, "unsigned": unsigned,
		"wall": {"stone": wall_stone, "deck": wall_deck, "merlons": wall_merlons},
		"stamp": {"stone": stamp_stone, "stamps": stamped},
		"castle": {"stone": castle_stone, "gate": castle_gate, "platform": castle_platform, "stairs": castle_stairs},
		"reserved_empty": reserved_empty})


## T219: every Defense Range booth is a weapon that could be demonstrated -
## the mount its sheet allows, its own munition in the storage touching it, a
## target down range and a sign naming both - and the storage network really
## does reload one of them.
func _test_defense_range() -> void:
	if not await _walk_to_district("defense_range"):
		return
	var workstations: WorkstationService = app.session.workstations
	var storage: StorageNetwork = app.session.siege_defense.storage
	var booths := {"dr_ballista": "ballista", "dr_catapult": "catapult",
		"dr_turret_catapult": "turret_catapult", "dr_turret_catapult_mk2": "turret_catapult_mk2",
		"dr_cannon": "cannon", "dr_kettle": "kettle"}
	var problems: Array[String] = []
	var booth_report: Dictionary = {}
	for exhibit_id: String in booths.keys():
		var entity_id := str(booths[exhibit_id])
		var box := _parcel_box(exhibit_id)
		var weapons := _stations_in(box, entity_id)
		if weapons.is_empty():
			problems.append(exhibit_id + ": no weapon")
			continue
		var weapon_id: String = weapons[0]
		var record: Dictionary = workstations.station(weapon_id)
		var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
		var details: Dictionary = workstations.siege_status(weapon_id).get("details", {})
		var ammo_item := str(details.get("definition", {}).get("ammo_item", ""))
		var support_id := workstations.station_at_cell(anchor + Vector3i(0, -1, 0))
		var support := str(workstations.station(support_id).get("entity_id", "")) if not support_id.is_empty() else ""
		var allowed: Array = app.session.registry.entity(entity_id).get("mount", {}).get("allowed", [])
		var ground_support: bool = int(app.session.world.query_cell(anchor + Vector3i(0, -1, 0)).get("voxel_id", AIR)) != AIR
		var mount_ok: bool = (support == "tower_platform" and allowed.has("light_siege")) \
			or (support == "rail" and allowed.has("rail_mount")) \
			or (support.is_empty() and ground_support and allowed.has("ground"))
		var network := storage.network_of(weapon_id)
		var stored := storage.count(network, ammo_item)
		var target_box := {"origin": Vector3i(box["origin"].x + 2, box["origin"].y, box["origin"].z + 2), "size": Vector3i(2, 3, 1)}
		var target := _voxels_in(target_box, CASTLE_STONE)
		var signed := _sign_placed(exhibit_id)
		booth_report[exhibit_id] = {"weapon": weapon_id, "support": support, "mount_ok": mount_ok,
			"ammo_item": ammo_item, "loaded": int(details.get("ammo", 0)), "storage": stored,
			"containers": network.size(), "target": target, "signed": signed}
		if not mount_ok:
			problems.append("%s: mount %s" % [exhibit_id, support if not support.is_empty() else "ground"])
		if network.is_empty() or stored <= 0:
			problems.append(exhibit_id + ": no munition in the storage beside it")
		if target <= 0:
			problems.append(exhibit_id + ": no target")
		if not signed:
			problems.append(exhibit_id + ": unsigned")
	var reload := await _test_booth_reload("dr_cannon", "cannon")
	var ok: bool = problems.is_empty() and bool(reload.get("ok", false))
	_record("T219_EXPO_DEFENSE_RANGE", ok,
		"each of the six Defense Range booths stands its weapon on the mount its sheet allows, with its own munition in the container the storage network sees beside it, a castle-stone target down its lane and a sign naming the weapon and the ammunition; draining the Cannon back to the clip its sheet opens with is topped up again by the existing storage-network reload, and the munition comes out of the chest",
		{"problems": problems, "booths": booth_report, "reload": reload})


## One booth's weapon is drained back to its opening clip and the ordinary
## siege service is left to reload it from the container beside it.
func _test_booth_reload(exhibit_id: String, entity_id: String) -> Dictionary:
	var workstations: WorkstationService = app.session.workstations
	var storage: StorageNetwork = app.session.siege_defense.storage
	var weapons := _stations_in(_parcel_box(exhibit_id), entity_id)
	if weapons.is_empty():
		return {"ok": false, "reason": "NO_WEAPON"}
	var weapon_id: String = weapons[0]
	workstations.restore_siege_ammo(weapon_id)
	var details: Dictionary = workstations.siege_status(weapon_id).get("details", {})
	var ammo_item := str(details.get("ammo_item", ""))
	var capacity := int(details.get("capacity", 1))
	var before := int(details.get("ammo", 0))
	var stored_before := storage.count(storage.network_of(weapon_id), ammo_item)
	var deadline := Time.get_ticks_msec() + RELOAD_TIMEOUT_MSEC
	var after := before
	while after < capacity and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		after = int(workstations.siege_status(weapon_id).get("details", {}).get("ammo", 0))
	var stored_after := storage.count(storage.network_of(weapon_id), ammo_item)
	return {"ok": after > before and after == capacity and stored_after < stored_before,
		"weapon": weapon_id, "item": ammo_item, "before": before, "after": after, "capacity": capacity,
		"storage_before": stored_before, "storage_after": stored_after}


## T220: the Battlefield scenario end to end. START ATTACK sends a mixed wave
## of the enemy kinds that exist at the Battlefield's own Core; the wave closes
## on it; a player siege weapon engages; RESET BATTLEFIELD then clears the
## fight and restores the arena, leaving damage in other districts alone; and a
## second START ATTACK works straight away.
func _test_battlefield() -> void:
	var workstations: WorkstationService = app.session.workstations
	var core_defense: CoreDefenseService = app.session.core_defense
	var bounds: Dictionary = app.development.expo_builder.reset_service.group_bounds("battlefield")
	var core_id := app.battlefield_core_station_id()
	var core_parcel := _parcel_box("battlefield_player_core")
	var core_origin: Vector3i = core_parcel["origin"]
	if not await _walk_to(core_origin + Vector3i(6, 0, 4), "battlefield"):
		return
	core_id = app.battlefield_core_station_id()
	var enemy_core: Array[String] = _stations_in(_parcel_box("battlefield_enemy_core"), "enemy_core")
	var control: Array[String] = _stations_in(_parcel_box("battlefield_control"), "battlefield_control")
	var weapons := _siege_stations_in(bounds)
	var core_cell := Vector3(workstations.station(core_id).get("anchor", Vector3i.ZERO)) + Vector3(1.5, 0.0, 1.5)
	var started := app.battlefield_start_attack()
	var attack := await _watch_attack(core_cell, weapons)
	# Damage two exhibits in other districts: a battlefield reset must leave
	# them exactly as they are (the plaza Core and a Defense Range weapon).
	var plaza_core: Array[String] = _stations_in(_parcel_box("plaza_core"), "core_of_power")
	var range_ballista: Array[String] = _stations_in(_parcel_box("dr_ballista"), "ballista")
	var elsewhere: Dictionary = {}
	for instance_id: String in [plaza_core[0] if not plaza_core.is_empty() else "", range_ballista[0] if not range_ballista.is_empty() else ""]:
		if instance_id.is_empty():
			continue
		workstations.try_damage(instance_id, 9)
		elsewhere[instance_id] = int(workstations.defense_status(instance_id).get("details", {}).get("integrity", 0))
	# The core the wave is chewing is restored by the reset, so record how far
	# it got first.
	var core_before := int(workstations.defense_status(core_id).get("details", {}).get("integrity", 0))
	var reset := app.battlefield_reset()
	var cleared: bool = core_defense.living_raider_count() == 0 and not core_defense.is_active()
	if not await _wait_built("battlefield reset"):
		return
	var untouched: Array[String] = []
	for instance_id: String in elsewhere.keys():
		if int(workstations.defense_status(instance_id).get("details", {}).get("integrity", 0)) != int(elsewhere[instance_id]):
			untouched.append(instance_id)
	var restored_core := int(workstations.defense_status(core_id).get("details", {}).get("integrity", 0))
	var core_max := int(workstations.defense_status(core_id).get("details", {}).get("max_integrity", 0))
	var enemy_after: Array[String] = _stations_in(_parcel_box("battlefield_enemy_core"), "enemy_core")
	var ammo_ok := true
	var restored_weapons := _siege_stations_in(bounds)
	for weapon_id: String in restored_weapons:
		var details: Dictionary = workstations.siege_status(weapon_id).get("details", {})
		ammo_ok = ammo_ok and int(details.get("ammo", 0)) >= int(details.get("definition", {}).get("starting_ammo", 0))
	var magazine := 0
	for chest_id: String in _stations_in(_parcel_box("battlefield_magazine"), "chest"):
		for stack: Variant in workstations.container_slots(chest_id):
			magazine += int((stack as Dictionary).get("count", 0))
	var again := app.battlefield_start_attack()
	var ok: bool = bool(started.get("ok", false)) and not enemy_core.is_empty() and not control.is_empty() \
		and weapons.size() >= 5 and bool(attack.get("ok", false)) \
		and bool(reset.get("ok", false)) and cleared and untouched.is_empty() \
		and restored_core == core_max and core_max > 0 and not enemy_after.is_empty() \
		and ammo_ok and magazine > 0 and restored_weapons.size() == weapons.size() \
		and bool(again.get("ok", false))
	core_defense.clear_for_other_mode()
	_record("T220_EXPO_BATTLEFIELD", ok,
		"START ATTACK on the Battlefield pedestal sends a mixed wave of the enemy kinds that exist at the Battlefield's own Core of Power (not the plaza's); the wave's distance to that Core shrinks as it routes in and a player siege weapon engages it; RESET BATTLEFIELD then removes every attacker, ends the drill, puts both cores, the batteries, their ammunition and the magazine back, and leaves damage done to the plaza Core and to a Defense Range weapon exactly as it was; a second START ATTACK straight afterwards is accepted",
		{"started": started, "attack": attack, "weapons": weapons.size(), "enemy_core": enemy_core.size(),
		"control": control.size(), "reset": reset, "cleared": cleared, "elsewhere": elsewhere,
		"still_damaged_elsewhere": untouched.is_empty(), "core_before": core_before,
		"core_after": restored_core, "core_max": core_max, "enemy_core_after": enemy_after.size(),
		"ammo_restored": ammo_ok, "magazine": magazine, "restarted": again})


## Watches one assault: the wave has to appear, carry more than one enemy kind,
## close on the core and be shot at by a player weapon.
func _watch_attack(core_cell: Vector3, weapons: Array[String]) -> Dictionary:
	var core_defense: CoreDefenseService = app.session.core_defense
	var workstations: WorkstationService = app.session.workstations
	var siege: SiegeDefenseService = app.session.siege_defense
	var opening: Dictionary = {}
	for weapon_id: String in weapons:
		opening[weapon_id] = int(workstations.siege_status(weapon_id).get("details", {}).get("ammo", 0))
	var deadline := Time.get_ticks_msec() + ATTACK_TIMEOUT_MSEC
	var kinds: Dictionary = {}
	var first_distance := -1.0
	var closest := -1.0
	var engaged := false
	var spawned := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var nodes := core_defense.raider_nodes()
		spawned = maxi(spawned, nodes.size())
		var near := -1.0
		for node: BasicRaider in nodes:
			kinds[str(node.kind)] = true
			var distance := Vector2(node.global_position.x - core_cell.x, node.global_position.z - core_cell.z).length()
			near = distance if near < 0.0 else minf(near, distance)
		if near >= 0.0:
			if first_distance < 0.0:
				first_distance = near
			closest = near if closest < 0.0 else minf(closest, near)
		if siege.pending_impacts() > 0:
			engaged = true
		for weapon_id: String in weapons:
			if int(workstations.siege_status(weapon_id).get("details", {}).get("ammo", 0)) < int(opening[weapon_id]):
				engaged = true
		if spawned > 0 and engaged and first_distance > 0.0 and closest < first_distance - CLOSING_CELLS:
			break
	return {"ok": spawned >= 2 and kinds.size() >= 2 and first_distance > 0.0 and closest < first_distance - CLOSING_CELLS and engaged,
		"spawned": spawned, "kinds": kinds.keys(), "first_distance": first_distance, "closest": closest, "engaged": engaged}


## Reading evidence for T215: one of the campus's real signs framed from in
## front of its board, close enough to read the manifest's words off it.
func _shoot_sign(owner_id: String) -> void:
	var stand := Vector3.ZERO
	var normal := Vector3(1.0, 0.0, 0.0)
	var found := false
	for request: Dictionary in app.development.expo_builder.sign_requests():
		if str(request.get("owner", "")) != owner_id:
			continue
		var record: Dictionary = app.session.workstations.stations.get(str(request.get("instance_id", "")), {})
		if record.is_empty():
			continue
		stand = Vector3(record.get("anchor", Vector3i.ZERO)) + Vector3(0.5, 0.5, 0.5)
		# The board faces local +X turned by -quarters * 90 degrees.
		var angle := -float(int(record.get("rotation_quarters", 0))) * PI / 2.0
		normal = Vector3(cos(angle), 0.0, -sin(angle))
		found = true
		break
	if not found:
		_record("T215V_SIGN_VIEW", false, "rendered evidence of a placed Expo sign", {"owner": owner_id, "reason": "NO_SIGN"})
		return
	var eye := stand + normal * 2.2 + Vector3(0.0, 0.2, 0.0)
	_look_from(eye, stand)
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(eye, stand)
	await get_tree().process_frame
	var path := app.data_root.path_join("development-expo-sign.png")
	var shot := await _save_viewport(path)
	_record("T215V_SIGN_VIEW", shot, "rendered evidence that the plaza's orientation sign is a real readable board, not a recorded request", {"path": path, "owner": owner_id, "cell": stand})


## T215: every sign the manifest asked for is a real placed `sign` station,
## not a recorded request. Each request must carry an instance id whose station
## is a `sign`, and that station's `sign_data` must hold exactly what the
## manifest said - the title in `text_a`, the body lines in `text_b`, the named
## item in `items`. The plaza orientation sign and one district sign are read
## back field by field as the spot checks.
func _test_signs() -> void:
	var builder: ExpoBuilder = app.development.expo_builder
	var workstations: WorkstationService = app.session.workstations
	var requests := builder.sign_requests()
	var unfulfilled: Array[String] = []
	var mismatched: Array[String] = []
	var placed := 0
	for request: Dictionary in requests:
		var owner_id := str(request.get("owner", ""))
		var instance_id := str(request.get("instance_id", ""))
		if not bool(request.get("ok", false)) or instance_id.is_empty():
			unfulfilled.append("%s: %s" % [owner_id, str(request.get("reason", "UNFULFILLED"))])
			continue
		var record: Dictionary = workstations.stations.get(instance_id, {})
		if str(record.get("entity_id", "")) != "sign":
			unfulfilled.append(owner_id + ": no sign station")
			continue
		placed += 1
		if not _sign_matches(workstations.sign_data(instance_id), request.get("sign", {})):
			mismatched.append(owner_id)
	var plaza_spot := _sign_spot_check("central_plaza", requests, workstations)
	var district_spot := _sign_spot_check("day_one", requests, workstations)
	var ok: bool = not requests.is_empty() and unfulfilled.is_empty() and mismatched.is_empty() \
		and builder.pending_signs().is_empty() and placed == requests.size() \
		and bool(plaza_spot.get("ok", false)) and bool(district_spot.get("ok", false))
	_record("T215_EXPO_SIGNS_PLACED", ok,
		"after a Development New every manifest exhibit and district sign request has placed a real `sign` station whose `sign_data` carries the manifest's mode, title, body lines and item; nothing is left unfulfilled, and the plaza orientation sign and the Day One district sign read back field by field",
		{"requested": requests.size(), "placed": placed, "unfulfilled": unfulfilled, "mismatched": mismatched,
		"pending": builder.pending_signs().size(), "plaza": plaza_spot, "district": district_spot})


## Compares a station's stored sign against the block the builder asked for.
func _sign_matches(stored: Dictionary, wanted: Dictionary) -> bool:
	if stored.is_empty() or wanted.is_empty():
		return false
	if str(stored.get("mode", "")) != str(wanted.get("mode", "")):
		return false
	for field: String in ["text_a", "text_b"]:
		var wanted_text := str(wanted.get(field, "")).substr(0, WorkstationService.SIGN_TEXT_LIMIT)
		if str(stored.get(field, "")) != wanted_text:
			return false
	var stored_items: Array = stored.get("items", [])
	var wanted_items: Array = wanted.get("items", [])
	if stored_items.size() != wanted_items.size():
		return false
	for index in range(stored_items.size()):
		if str(stored_items[index]) != str(wanted_items[index]):
			return false
	return true


## One named sign read back against the manifest itself, not against the
## builder's request: the title, every body line and the item id.
func _sign_spot_check(owner_id: String, requests: Array[Dictionary], workstations: WorkstationService) -> Dictionary:
	var manifest := app.development.layout.sign_data(owner_id)
	for request: Dictionary in requests:
		if str(request.get("owner", "")) != owner_id:
			continue
		var stored := workstations.sign_data(str(request.get("instance_id", "")))
		if stored.is_empty():
			return {"ok": false, "owner": owner_id, "reason": "NO_SIGN_DATA"}
		var text := str(stored.get("text_a", "")) + "\n" + str(stored.get("text_b", ""))
		var carries := str(stored.get("text_a", "")) == str(manifest.get("title", ""))
		var lines: Variant = manifest.get("lines", [])
		if lines is Array:
			for line: Variant in lines as Array:
				carries = carries and text.contains(str(line))
		var item := str(manifest.get("item", ""))
		if not item.is_empty():
			carries = carries and (stored.get("items", []) as Array).has(item)
		return {"ok": carries, "owner": owner_id, "cell": request.get("cell", Vector3i.ZERO),
			"mode": stored.get("mode", ""), "text_a": stored.get("text_a", ""), "items": stored.get("items", [])}
	return {"ok": false, "owner": owner_id, "reason": "NO_REQUEST"}


# ------------------------------------------------------------ card E helpers

## The solved parcel of an exhibit, as a box.
func _parcel_box(exhibit_id: String) -> Dictionary:
	var parcel: Dictionary = app.development.layout.parcel_for(exhibit_id)
	if parcel.is_empty():
		return {}
	return {"origin": parcel["origin"] as Vector3i, "size": parcel["size"] as Vector3i}


## A cell is in a parcel when its column is: a weapon standing on a platform,
## a merlon on a wall-walk and the deck under both belong to the same exhibit.
static func _inside(box: Dictionary, cell: Vector3i) -> bool:
	if box.is_empty():
		return false
	var origin: Vector3i = box["origin"]
	var size: Vector3i = box["size"]
	return cell.x >= origin.x and cell.x < origin.x + size.x \
		and cell.z >= origin.z and cell.z < origin.z + size.z


## The stations of one entity standing in a box; with no entity id, everything
## but the exhibit's own sign board (a reserved parcel still carries its sign).
func _stations_in(box: Dictionary, entity_id: String) -> Array[String]:
	var found: Array[String] = []
	if box.is_empty():
		return found
	for instance_id: String in app.session.workstations.stations.keys():
		var record: Dictionary = app.session.workstations.stations[instance_id]
		var standing := str(record.get("entity_id", ""))
		if entity_id.is_empty():
			if standing == "sign":
				continue
		elif standing != entity_id:
			continue
		if _inside(box, record.get("anchor", Vector3i.ZERO)):
			found.append(instance_id)
	return found


## Every siege weapon standing in a box.
func _siege_stations_in(box: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for instance_id: String in app.session.workstations.stations.keys():
		var record: Dictionary = app.session.workstations.stations[instance_id]
		if not app.session.workstations.siege_status(instance_id).get("ok", false):
			continue
		if _inside(box, record.get("anchor", Vector3i.ZERO)):
			found.append(instance_id)
	return found


func _voxels_in(box: Dictionary, voxel: int) -> int:
	if box.is_empty():
		return 0
	var world: WorldAdapter = app.session.world
	var origin: Vector3i = box["origin"]
	var size: Vector3i = box["size"]
	var count := 0
	for x in range(size.x):
		for y in range(maxi(1, size.y)):
			for z in range(size.z):
				if int(world.query_cell(origin + Vector3i(x, y, z)).get("voxel_id", AIR)) == voxel:
					count += 1
	return count


func _sign_placed(owner_id: String) -> bool:
	for request: Dictionary in app.development.expo_builder.sign_requests():
		if str(request.get("owner", "")) == owner_id:
			return bool(request.get("ok", false))
	return false


## Walks the player round the campus so every district's chunks stream in and
## the builder can run the ops parked waiting for them (a column whose chunks
## are not loaded is deferred until the player moves - see `ExpoBuilder`). The
## campus is thirteen districts wide now, so the strict wait that follows only
## succeeds if someone has been to all of them.
func _drive_build() -> void:
	var builder: ExpoBuilder = app.development.expo_builder
	var layout: ExpoLayout = app.development.layout
	var deadline := Time.get_ticks_msec() + BUILD_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if builder.pending_ops() == 0 and builder.deferred_ops() == 0:
			return
		for district_id: String in layout.district_ids():
			var bounds := layout.district_bounds(district_id)
			var origin: Vector3i = bounds["origin"]
			var size: Vector3i = bounds["size"]
			_teleport(Vector3(origin) + Vector3(float(size.x) * 0.5, 8.0, float(size.z) * 0.5))
			for _frame in range(BUILD_FRAMES_PER_STOP):
				builder.advance(BUILD_BUDGET_PER_FRAME)
				await get_tree().process_frame
				if builder.pending_ops() == 0 and builder.deferred_ops() == 0:
					return
			if Time.get_ticks_msec() >= deadline:
				return


## Stands the player on a cell and waits for everything still queued there.
func _walk_to(cell: Vector3i, label: String) -> bool:
	_teleport(Vector3(float(cell.x) + 0.5, float(cell.y) + 1.6, float(cell.z) + 0.5))
	return await _wait_built(label)


func _walk_to_district(district_id: String) -> bool:
	var bounds := app.development.layout.district_bounds(district_id)
	var origin: Vector3i = bounds["origin"]
	var size: Vector3i = bounds["size"]
	return await _walk_to(Vector3i(origin.x + size.x / 2, app.development.layout.ground_y(), origin.z + size.z / 2), district_id)


func _light_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for instance_id: String in app.session.workstations.stations.keys():
		var record: Dictionary = app.session.workstations.stations[instance_id]
		var attributes := app.session.registry.entity_attributes(str(record.get("entity_id", "")))
		if str(attributes.get("role", "")) == "light":
			result.append(Vector3(record.get("anchor", Vector3i.ZERO)))
	return result


## A built exhibit: its parcel carries a station, or the terrain under it is no
## longer the untouched surface (a plinth, a plant, an ore face).
func _exhibit_present(exhibit_id: String, origin: Vector3i, size: Vector3i) -> bool:
	var world: WorldAdapter = app.session.world
	for x in range(size.x):
		for z in range(size.z):
			var column := Vector3i(origin.x + x, origin.y, origin.z + z)
			if not app.session.workstations.station_at_cell(column).is_empty():
				return true
			for y in range(maxi(1, size.y)):
				var query := world.query_cell(column + Vector3i(0, y, 0))
				if str(query.get("state", "")) == "LOADED" and int(query.get("voxel_id", AIR)) != AIR:
					return true
	failures.append("exhibit not built: " + exhibit_id)
	return false


func _teleport(position: Vector3) -> void:
	app.session.player.global_position = position
	app.session.player.velocity = Vector3.ZERO


## Frames the shot: the body is parked (the camera is its child, so it would
## otherwise snap back to the player's own aim on the next frame).
func _look_from(eye: Vector3, target: Vector3) -> void:
	app.session.player.deactivate()
	_teleport(eye)
	var camera := app.session.player.camera
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)


## Quitting while terrain streams around a far-teleported player crashes the
## engine: settle back beside the spawn first.
func _settle_near_spawn() -> void:
	var spawn := app.development.layout.spawn_feet()
	_teleport(Vector3(spawn.x, spawn.y + 1.0, spawn.z))
	for _frame in range(120):
		await get_tree().process_frame


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 60000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


## Waits until the builder's queue is empty and nothing is parked waiting for
## terrain to stream in around the player.
func _wait_built(label: String) -> bool:
	var builder: ExpoBuilder = app.development.expo_builder
	var deadline := Time.get_ticks_msec() + BUILD_TIMEOUT_MSEC
	while builder.pending_ops() > 0 or builder.deferred_ops() > 0:
		builder.advance(BUILD_BUDGET_PER_FRAME)
		if Time.get_ticks_msec() >= deadline:
			failures.append("%s build timeout (%s)" % [label, JSON.stringify(builder.progress())])
			return false
		await get_tree().process_frame
	for _frame in range(30):
		await get_tree().process_frame
	if not builder.failures().is_empty():
		failures.append("%s build failures: %s" % [label, "; ".join(builder.failures())])
		return false
	return true


func _save_viewport(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	return image != null and image.save_png(path) == OK


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
