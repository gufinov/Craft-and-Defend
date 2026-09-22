class_name DevelopmentExpoAutomation
extends Node

## Development Expo gate (docs/DEVELOPMENT_EXPO.md, docs/TEST_PLAN.md T213 and
## T214). This suite is the milestone's home: the later Expo cards add their
## own records to it.
##
##   --development-expo-automation=gate    headless, T213 + T214
##   --development-expo-automation=visual  windowed, builds and renders the
##                                         plaza and the mountain tunnel
##
## The layout half (T213) needs no world; the campus half (T214) opens a fresh
## Development world, walks the player to the districts this milestone builds
## and reads the voxels and stations back out.

const AIR := 0
const STONE := 3
const COAL_ORE := 6
const IRON_ORE := 7
const GOLD_ORE := 11
## Cells of the mountain tunnel walked in a straight line.
const TUNNEL_WALK := 56
## A tunnel sample counts as lit with a light entity this near.
const LIGHT_RANGE := 12.0
const BUILD_TIMEOUT_MSEC := 240000
## Miner ticks T216 drives so the Ore Bin holds both an ore and its fuel.
const INDUSTRY_MINER_TICKS := 24
## 1/30 s cart steps T216 allows the mine cart for one bin-to-warehouse haul.
const INDUSTRY_CART_STEPS := 9000
## One-second foundry ticks T216 allows for the first ingot.
const INDUSTRY_FOUNDRY_STEPS := 240
## The six light sources the Lighting district shows side by side, in walk order.
const LIGHT_EXHIBITS: Array[String] = ["light_torch", "light_wall_lantern", "light_post_lantern",
	"light_campfire", "light_blue_block", "light_red_block"]

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
	# The campus is read exactly as the fixture built it: no service ticks until
	# T216 drives the Industry chain itself, so "containers start empty" is a
	# statement about the canonical world and not about how fast the gate ran.
	app.session.simulation_paused = true
	if not await _wait_built("plaza"):
		return
	await _test_plaza_and_day_one()
	await _test_mountain()
	_test_signs()
	await _test_industry()
	await _test_lighting()
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
	# The Industry chain, looked along from the ore face towards the yard, so
	# the miner, the bin, the rail and the warehouse are in one frame.
	var ore_face := app.development.layout.parcel_for("industry_ore_face")
	var face_origin: Vector3i = ore_face["origin"]
	var face_size: Vector3i = ore_face["size"]
	var yard_eye := Vector3(float(face_origin.x) - 2.5, float(face_origin.y) + 4.0, float(face_origin.z + face_size.z) + 4.5)
	var yard_target := Vector3(float(face_origin.x + 6), float(face_origin.y) + 1.0, float(face_origin.z + face_size.z))
	_teleport(yard_eye)
	if not await _wait_built("industry"):
		return
	_look_from(yard_eye, yard_target)
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(yard_eye, yard_target)
	await get_tree().process_frame
	var industry_path := app.data_root.path_join("development-expo-industry.png")
	var industry_shot := await _save_viewport(industry_path)
	_record("T216V_INDUSTRY_VIEW", industry_shot, "rendered evidence of the Industry chain: the ore face with its Miner and Ore Bin, the rail out of the mountain and the cart on it", {"path": industry_path})
	# The light walk, looked down the roofed gallery from the open west end.
	var pavilion := app.development.layout.parcel_for("light_pavilion")
	var pavilion_origin: Vector3i = pavilion["origin"]
	var pavilion_size: Vector3i = pavilion["size"]
	var walk_eye := Vector3(float(pavilion_origin.x) + 4.5, float(pavilion_origin.y) + 1.7, float(pavilion_origin.z) + 8.5)
	var walk_target := Vector3(float(pavilion_origin.x + pavilion_size.x) - 1.5, float(pavilion_origin.y) + 1.0, float(pavilion_origin.z) + 2.5)
	_teleport(walk_eye)
	if not await _wait_built("lighting"):
		return
	_look_from(walk_eye, walk_target)
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(walk_eye, walk_target)
	await get_tree().process_frame
	var lighting_path := app.data_root.path_join("development-expo-lighting.png")
	var lighting_shot := await _save_viewport(lighting_path)
	_record("T217V_LIGHTING_VIEW", lighting_shot, "rendered evidence of the roofed light walk with the six light sources side by side", {"path": lighting_path})
	await _settle_near_spawn()


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


## T216: the Industry district is a chain the owner can walk, and it runs.
## The rail that leaves the mountain tunnel continues into the yard as one
## unbroken line; the miner, the ore bin, the cart, the warehouse and the
## foundry stand on it; every container is empty as built; and then the
## services are advanced by hand - the miner fills the bin, the cart hauls the
## ore to the warehouse and the foundry smelts an ingot back into storage. The
## four storage-network booths are read through `StorageNetwork` itself.
func _test_industry() -> void:
	var layout: ExpoLayout = app.development.layout
	var ws: WorkstationService = app.session.workstations
	var yard := layout.parcel_for("industry_warehouse")
	var yard_origin: Vector3i = yard["origin"]
	# Stand in the yard so the district's parked build ops finish.
	_teleport(Vector3(float(yard_origin.x) + 0.5, float(yard_origin.y) + 1.1, float(yard_origin.z) + 4.5))
	if not await _wait_built("industry"):
		return
	var miner_id := _pinned_station("industry_ore_face", "miner")
	var bin_id := _pinned_station("industry_ore_face", "ore_bin")
	var cart_id := _pinned_station("industry_rail", "mine_cart")
	var warehouse_id := _pinned_station("industry_warehouse", "warehouse")
	var foundry_id := _pinned_station("industry_warehouse", "foundry")
	var standing := {"miner": miner_id, "ore_bin": bin_id, "mine_cart": cart_id,
		"warehouse": warehouse_id, "foundry": foundry_id}
	var chain_ok := true
	for key: String in standing.keys():
		chain_ok = chain_ok and not str(standing[key]).is_empty()
	# One rail line: the mountain's cells and the yard's, cell by cell in +x.
	var mountain_rail := layout.parcel_for("mountain_rail")
	var yard_rail := layout.parcel_for("industry_rail")
	var rail_from: Vector3i = mountain_rail["origin"]
	var rail_to: Vector3i = yard_rail["origin"] + Vector3i(int((yard_rail["size"] as Vector3i).x) - 1, 0, 0)
	var rails: Array[Vector3i] = []
	for instance_id: String in ws.stations.keys():
		var record: Dictionary = ws.stations[instance_id]
		if str(record.get("entity_id", "")) == "rail":
			rails.append(record.get("anchor", Vector3i.ZERO))
	rails.sort_custom(func(first: Vector3i, second: Vector3i) -> bool: return first.x < second.x)
	var rail_chained: bool = not rails.is_empty() and rails[0] == rail_from and rails[rails.size() - 1] == rail_to
	for index in range(1, rails.size()):
		if rails[index] - rails[index - 1] != Vector3i(1, 0, 0):
			rail_chained = false
	# Every container of the district starts empty: the owner watches them fill.
	var containers: Dictionary = {"ore_bin": bin_id, "warehouse": warehouse_id}
	for exhibit_id: String in ["industry_net_chest", "industry_net_chain", "industry_net_foundry", "industry_net_furnace"]:
		for entity_id: String in ["warehouse", "chest"]:
			for index in range(2):
				var container_id := _pinned_station(exhibit_id, entity_id, index)
				if not container_id.is_empty():
					containers["%s:%s:%d" % [exhibit_id, entity_id, index]] = container_id
	var stocked: Array[String] = []
	for key: String in containers.keys():
		if _container_total(str(containers[key])) > 0:
			stocked.append(key)
	var foundry: FoundryService = app.session.foundry
	var slots_before := foundry.slots(foundry_id) if foundry != null and not foundry_id.is_empty() else {}
	var slots_empty := true
	for slot: String in ["ore", "fuel", "output"]:
		slots_empty = slots_empty and int((slots_before.get(slot, {}) as Dictionary).get("count", 0)) == 0
	var cart_empty: bool = app.session.coaster_carts != null and app.session.coaster_carts.cargo(cart_id).is_empty()
	var empty_start: bool = stocked.is_empty() and slots_empty and cart_empty
	# Now run it. Each service is advanced directly, as the industry gates do.
	var miners: MinerService = app.session.miner_service
	for _tick in range(INDUSTRY_MINER_TICKS):
		miners.advance(MinerService.MINER_SECONDS + 0.1, false)
	var bin_contents := _container_contents(bin_id)
	var mined: bool = _container_total(bin_id) > 0
	var carts: CoasterCartService = app.session.coaster_carts
	var hauled := false
	var cart_steps := 0
	for _step in range(INDUSTRY_CART_STEPS):
		cart_steps += 1
		carts.advance(1.0 / 30.0, false)
		if _container_total(warehouse_id) > 0:
			hauled = true
			break
	var storage := StorageNetwork.new(ws)
	var network := foundry.network_for(foundry_id) if foundry != null else ([] as Array[String])
	var smelted := 0
	var foundry_steps := 0
	for _step in range(INDUSTRY_FOUNDRY_STEPS):
		foundry_steps += 1
		foundry.advance(1.0, false)
		smelted = storage.count(network, "iron_ingot") + storage.count(network, "gold_ingot")
		if smelted > 0:
			break
	# The four storage-network booths, read through the rule itself.
	var demos: Dictionary = {}
	var demos_ok := true
	for entry: Array in [["industry_net_chest", "warehouse", 0, "chest", 0], ["industry_net_chain", "warehouse", 0, "warehouse", 1],
			["industry_net_foundry", "foundry", 0, "warehouse", 0], ["industry_net_furnace", "furnace", 0, "chest", 0]]:
		var exhibit_id := str(entry[0])
		var from_id := _pinned_station(exhibit_id, str(entry[1]), int(entry[2]))
		var pooled_id := _pinned_station(exhibit_id, str(entry[3]), int(entry[4]))
		var pooled := storage.network_of(from_id) if not from_id.is_empty() else ([] as Array[String])
		var ok: bool = not from_id.is_empty() and not pooled_id.is_empty() and pooled.has(pooled_id) and pooled.size() == 1
		demos[exhibit_id] = {"ok": ok, "network": pooled.size(), "pools": str(entry[3])}
		demos_ok = demos_ok and ok
	var ok: bool = chain_ok and rail_chained and empty_start and mined and hauled and smelted > 0 and demos_ok
	_record("T216_EXPO_INDUSTRY", ok,
		"after a Development New the Industry district holds the whole chain - a Miner on an authored ore face, an Ore Bin beside it, one unbroken rail line continuing out of the mountain tunnel with a Mine Cart on it, a Warehouse at the dock and a Foundry touching it - with every container and every foundry slot empty as built; advancing the services runs it end to end (the miner fills the bin, the cart hauls the ore into the warehouse, the foundry smelts an ingot back into storage) and the four storage-network booths each pool exactly as their signs say",
		{"stations": standing, "rails": rails.size(), "rail_from": rail_from, "rail_to": rail_to, "rail_chained": rail_chained,
		"empty_start": empty_start, "stocked": stocked, "slots_empty": slots_empty, "cart_empty": cart_empty,
		"bin": bin_contents, "mined": mined, "hauled": hauled, "cart_steps": cart_steps,
		"warehouse": _container_contents(warehouse_id), "smelted": smelted, "foundry_steps": foundry_steps,
		"network": network.size(), "demos": demos})


## T217: the Lighting gallery - all six light sources placed inside the roofed
## walk, each with its own signed parcel, each carrying a real light node with
## the colour and range its content sheet declares (the check
## `p4_assets_automation.gd` makes), and a roof over each one so the difference
## reads at midday.
func _test_lighting() -> void:
	var layout: ExpoLayout = app.development.layout
	var ws: WorkstationService = app.session.workstations
	var world: WorldAdapter = app.session.world
	var pavilion := layout.parcel_for("light_pavilion")
	var pavilion_origin: Vector3i = pavilion["origin"]
	var pavilion_size: Vector3i = pavilion["size"]
	_teleport(Vector3(float(pavilion_origin.x) + float(pavilion_size.x) * 0.5, float(pavilion_origin.y) + 1.1,
		float(pavilion_origin.z) + float(pavilion_size.z) * 0.5))
	if not await _wait_built("lighting"):
		return
	var signed: Dictionary = {}
	for request: Dictionary in app.development.expo_builder.sign_requests():
		if bool(request.get("ok", false)):
			signed[str(request.get("owner", ""))] = true
	var lights: Dictionary = {}
	var problems: Array[String] = []
	for exhibit_id: String in LIGHT_EXHIBITS:
		var record := layout.exhibit(exhibit_id)
		var entity_id := str((record.get("entities", []) as Array)[0]) if not (record.get("entities", []) as Array).is_empty() else ""
		var instance_id := _pinned_station(exhibit_id, entity_id)
		if instance_id.is_empty():
			problems.append(exhibit_id + ":not_placed")
			continue
		if not signed.has(exhibit_id):
			problems.append(exhibit_id + ":no_sign")
		var body: Node3D = app.session._station_visuals.get(instance_id)
		var light: OmniLight3D = body.find_child(GameSession.ENTITY_LIGHT_NAME, true, false) if body != null else null
		if light == null:
			problems.append(exhibit_id + ":no_light")
			continue
		var declared: Dictionary = app.session.registry.entity_attributes(entity_id).get("light", {})
		var colour := Color(str(declared.get("color", "")))
		if not light.light_color.is_equal_approx(colour) or not is_equal_approx(light.omni_range, float(declared.get("range", 0.0))) \
				or light.light_energy <= 0.0:
			problems.append(exhibit_id + ":light_mismatch")
		# Roofed: the gallery's own slab stands over the light, so the source
		# reads against shade rather than against daylight.
		var cell: Vector3i = ws.stations.get(instance_id, {}).get("anchor", Vector3i.ZERO)
		var roof := world.query_cell(Vector3i(cell.x, pavilion_origin.y + pavilion_size.y - 1, cell.z))
		if str(roof.get("state", "")) != "LOADED" or int(roof.get("voxel_id", AIR)) == AIR:
			problems.append(exhibit_id + ":not_roofed")
		lights[exhibit_id] = {"entity": entity_id, "colour": str(declared.get("color", "")),
			"range": light.omni_range, "energy": light.light_energy, "cell": cell}
	var ok: bool = problems.is_empty() and lights.size() == LIGHT_EXHIBITS.size()
	_record("T217_EXPO_LIGHTING", ok,
		"after a Development New the Lighting district's roofed gallery holds all six light sources - torch, wall lantern, post lantern, campfire and the blue and red light blocks - each on its own signed parcel, each a real placed entity whose light node carries the colour, range and energy its content sheet declares, and each under the gallery's roof so the difference reads at midday",
		{"lights": lights, "problems": problems, "pavilion": pavilion_origin})


## The station standing on a manifest `placements` entry (the `index`-th entry
## naming `entity_id` in that exhibit); "" when nothing of that kind is there.
func _pinned_station(exhibit_id: String, entity_id: String, index: int = 0) -> String:
	var parcel := app.development.layout.parcel_for(exhibit_id)
	if parcel.is_empty():
		return ""
	var origin: Vector3i = parcel["origin"]
	var seen := 0
	for entry: Variant in app.development.layout.exhibit(exhibit_id).get("placements", []):
		if not entry is Dictionary:
			continue
		var placement: Dictionary = entry
		if str(placement.get("entity", "")) != entity_id:
			continue
		if seen < index:
			seen += 1
			continue
		var raw: Variant = placement.get("offset", [])
		if not raw is Array or (raw as Array).size() != 3:
			return ""
		var offset: Array = raw
		var instance_id := app.session.workstations.station_at_cell(origin + Vector3i(int(offset[0]), int(offset[1]), int(offset[2])))
		if instance_id.is_empty():
			return ""
		return instance_id if str(app.session.workstations.station(instance_id).get("entity_id", "")) == entity_id else ""
	return ""


## Everything a container holds, item id -> count.
func _container_contents(instance_id: String) -> Dictionary:
	var contents: Dictionary = {}
	if instance_id.is_empty():
		return contents
	for slot: Variant in app.session.workstations.container_slots(instance_id):
		if not slot is Dictionary:
			continue
		var stack: Dictionary = slot
		var item_id := str(stack.get("item_id", ""))
		var count := int(stack.get("count", 0))
		if item_id.is_empty() or count <= 0:
			continue
		contents[item_id] = int(contents.get(item_id, 0)) + count
	return contents


func _container_total(instance_id: String) -> int:
	var total := 0
	for count: Variant in _container_contents(instance_id).values():
		total += int(count)
	return total


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
