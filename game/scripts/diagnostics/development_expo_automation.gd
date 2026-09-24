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
## Frames one walked cell is given for the terrain around it to stream in.
const STREAM_FRAMES := 240
const BUILD_TIMEOUT_MSEC := 420000
## Signs card 2 (T225): the exhibit whose board is anchored by its gate, and
## how far from that anchor the board may end up (the builder takes the nearest
## free cell around a requested one when the exhibit itself stands there).
const ANCHORED_EXHIBIT := "battlefield_field"
const SIGN_ANCHOR_TOLERANCE := 4
## Miner ticks T216 drives so the Ore Bin holds both an ore and its fuel.
const INDUSTRY_MINER_TICKS := 24
## 1/30 s cart steps T216 allows the mine cart for one bin-to-warehouse haul.
const INDUSTRY_CART_STEPS := 9000
## One-second foundry ticks T216 allows for the first ingot.
const INDUSTRY_FOUNDRY_STEPS := 240
## The six light sources the Lighting district shows side by side, in walk order.
const LIGHT_EXHIBITS: Array[String] = ["light_torch", "light_wall_lantern", "light_post_lantern",
	"light_campfire", "light_blue_block", "light_red_block"]
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
## Card F. What must stand inside each gallery booth's parcel: the entity ids
## and the track families (`_track_family`, read from the station records'
## entity and curve data alone).
const COASTER_GALLERY: Array[Dictionary] = [
	{"id": "coaster_arrival", "entities": ["post_lantern"], "families": []},
	{"id": "coaster_rail", "entities": ["rail"], "families": ["straight"]},
	{"id": "coaster_rail_slope", "entities": ["rail_slope", "rail"], "families": ["slope"]},
	{"id": "coaster_rail_loop", "entities": ["rail"], "families": ["loop"]},
	{"id": "coaster_rail_switch", "entities": ["rail"], "families": ["switch"]},
	{"id": "coaster_rail_cross", "entities": ["rail"], "families": ["cross"]},
	{"id": "coaster_rail_curve", "entities": ["rail"], "families": ["curve"]},
	{"id": "coaster_rail_climb", "entities": ["rail"], "families": ["climb"]},
	{"id": "coaster_mine_cart", "entities": ["mine_cart", "rail"], "families": []},
	{"id": "coaster_car", "entities": ["coaster_car", "rail"], "families": []},
	{"id": "coaster_shop", "entities": ["coastercraft_shop"], "families": []},
]
## Every family the Grand Demonstration Coaster must contain.
const COASTER_FAMILIES: Array[String] = ["straight", "climb", "curve", "loop", "switch", "cross"]
## The lane switcher's own lane shift, which tells it apart from the crossing's
## two long s-bends (both are shifted s_bends; only the crossing's shared cells
## carry a second curve).
const COASTER_SWITCH_SHIFT := 1.0
## Card D1 - the Expo Directory. What the owner's own example search must
## find, the three districts a teleport is proven in (the last of them the far
## CoasterCraft park) and how near the parcel the teleport must land.
const DIRECTORY_SEARCH := "wall kit"
const DIRECTORY_SEARCH_EXHIBIT := "cy_wall_kit"
const DIRECTORY_TELEPORT_EXHIBITS: Array[String] = ["cy_wall_kit", "light_post_lantern", "grand_coaster"]
const DIRECTORY_LANDING_CELLS := 6.0
## The subject the notes test writes its history against.
const NOTES_SUBJECT := "cy_wall_kit"
const NOTES_FIRST_REMARK := "The stair at the west end leaves a gap."
const NOTES_SECOND_REMARK := "Merlons look right after a rebuild."
## Frames the parked car is given to ride the whole circuit and come home.
const RIDE_FRAME_BUDGET := 40000
const RIDE_TIMEOUT_MSEC := 240000

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
	# The structural reads below all run against that pristine world.
	app.session.simulation_paused = true
	await _drive_build()
	if not await _wait_built("plaza", _district_owners(["central_plaza", "supply_depot", "future_expansion", "day_one", "equipment", "resources"])):
		return
	await _test_plaza_and_day_one()
	_test_supply_depot()
	await _test_mountain()
	_test_signs()
	_test_sign_anchors()
	await _test_industry()
	await _test_lighting()
	await _test_construction_yard()
	await _test_coaster_gallery()
	# The live scenarios need the services running: the Defense Range's reload
	# is `siege_defense.advance` doing its ordinary work, the Battlefield is a
	# real `CoreDefenseService` drill and the Grand Coaster is a real ride on
	# `CoasterCartService`. Everything that had to be read as built has been
	# read by now, so the simulation is handed back to the game.
	app.session.simulation_paused = false
	await _test_defense_range()
	await _test_battlefield()
	await _test_grand_coaster()
	_test_directory_search()
	await _test_directory_teleport()
	await _test_expo_notes()
	await _settle_near_spawn()


func _run_visual() -> void:
	app._on_development_new_pressed()
	if not await _wait_ready():
		return
	await _drive_build()
	if not await _wait_built("plaza", _district_owners(["central_plaza"])):
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
	await _shoot_supply_row()
	var tunnel := app.development.layout.parcel_for("mountain_tunnel")
	var tunnel_origin: Vector3i = tunnel["origin"]
	var tunnel_size: Vector3i = tunnel["size"]
	var mouth := Vector3(float(tunnel_origin.x + tunnel_size.x - 3), float(tunnel_origin.y) + 1.6, float(tunnel_origin.z + tunnel_size.z / 2) + 0.5)
	_teleport(mouth)
	if not await _wait_built("mountain", _district_owners(["mining_mountain"])):
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
	if not await _wait_built("industry", _district_owners(["industry"])):
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
	if not await _wait_built("lighting", _district_owners(["lighting"])):
		return
	_look_from(walk_eye, walk_target)
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(walk_eye, walk_target)
	await get_tree().process_frame
	var lighting_path := app.data_root.path_join("development-expo-lighting.png")
	var lighting_shot := await _save_viewport(lighting_path)
	_record("T217V_LIGHTING_VIEW", lighting_shot, "rendered evidence of the roofed light walk with the six light sources side by side", {"path": lighting_path})
	await _shoot_card_e_districts()
	await _shoot_coaster()
	await _shoot_directory()
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
		"rendered evidence of the Defense Range: seven weapon booths, each on its mount with its ammunition chest, target and sign")
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


## Card F's rendered evidence: the component gallery, and the Grand
## Demonstration Coaster from a vantage that shows its lift hill and true loop.
func _shoot_coaster() -> void:
	var layout: ExpoLayout = app.development.layout
	var gallery := layout.parcel_for("coaster_rail_slope")
	var gallery_origin: Vector3i = gallery["origin"]
	_teleport(_parcel_centre(gallery) + Vector3(0.0, 3.0, 0.0))
	if not await _wait_built("coastercraft", _district_owners(["coastercraft"])):
		return
	# Along the first row from the path south of it, over the levelled park:
	# the Slope, the true Loop and the Switch booths with their boards.
	var gallery_eye := Vector3(gallery_origin) + Vector3(-6.0, 10.0, 14.0)
	var gallery_target := Vector3(gallery_origin) + Vector3(29.0, 1.0, 5.0)
	_look_from(gallery_eye, gallery_target)
	for _frame in range(90):
		await get_tree().process_frame
	_look_from(gallery_eye, gallery_target)
	await get_tree().process_frame
	var gallery_path := app.data_root.path_join("development-expo-coaster-gallery.png")
	var gallery_shot := await _save_viewport(gallery_path)
	_record("T221V_COASTER_GALLERY_VIEW", gallery_shot, "rendered evidence of the CoasterCraft component gallery: the signed booths of the track family side by side", {"path": gallery_path})
	var show := layout.parcel_for("grand_coaster")
	var show_origin: Vector3i = show["origin"]
	var station := ExpoCoaster.show_station(show_origin)
	var lane_a := int(station["lane_a"])
	var eye := Vector3(float(show_origin.x) + 56.0, 17.0, float(lane_a) + 28.0)
	var target := Vector3(float(show_origin.x) + 32.0, 5.0, float(lane_a) + 1.0)
	_teleport(eye)
	if not await _wait_built("grand coaster", _district_owners(["coastercraft"])):
		return
	_look_from(eye, target)
	for _frame in range(90):
		await get_tree().process_frame
	_look_from(eye, target)
	await get_tree().process_frame
	var show_path := app.data_root.path_join("development-expo-coaster.png")
	var show_shot := await _save_viewport(show_path)
	_record("T222V_GRAND_COASTER_VIEW", show_shot, "rendered evidence of the Grand Demonstration Coaster: the lift hill, the crest and drop, and the true loop over the station", {"path": show_path})


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


## T223: the generated Supply Depot. Every non-hidden visible item of the
## registry is stocked exactly once, eight units of it, in a chest holding at
## most eight distinct types with a slot left free; every chest's board lists
## exactly the ids in the chest below it; the depot is a clear walk from the
## spawn; and an item with no Expo category is reported as unassigned instead
## of being filed away silently (the classifier is driven directly for that).
func _test_supply_depot() -> void:
	var builder: ExpoBuilder = app.development.expo_builder
	var catalog := builder.supply_catalog()
	var stands := builder.supply_stands()
	var requests := builder.sign_requests()
	var workstations: WorkstationService = app.session.workstations
	var units := int(catalog.get("units", SupplyDepot.DEFAULT_UNITS))
	var expected := SupplyDepot.visible_items(app.session.registry, _supply_whitelist())
	var stocked: Array[String] = []
	var problems: Array[String] = []
	for stand: Dictionary in stands:
		var items: Array = stand.get("items", [])
		var instance_id := str(stand.get("instance_id", ""))
		var label := str(stand.get("category", "")) + " @ " + str(stand.get("chest", Vector3i.ZERO))
		if instance_id.is_empty() or str(workstations.stations.get(instance_id, {}).get("entity_id", "")) != "chest":
			problems.append(label + ": no chest station")
			continue
		if items.size() > SupplyDepot.DEFAULT_TYPES_PER_CHEST:
			problems.append(label + ": more than eight distinct types")
		var held: Dictionary = {}
		var empty_slots := 0
		for entry: Variant in workstations.container_slots(instance_id):
			var slot: Dictionary = entry
			var item_id := str(slot.get("item_id", ""))
			if item_id.is_empty():
				empty_slots += 1
				continue
			held[item_id] = int(held.get(item_id, 0)) + int(slot.get("count", 0))
		if empty_slots < 1:
			problems.append(label + ": no free slot left in the chest")
		for entry: Variant in items:
			var item_id := str(entry)
			stocked.append(item_id)
			if int(held.get(item_id, 0)) != units:
				problems.append("%s: %s holds %d, expected %d" % [label, item_id, int(held.get(item_id, 0)), units])
		if held.size() != items.size():
			problems.append(label + ": chest holds items its catalog record does not name")
		var board := _sign_of(requests, str(stand.get("sign_owner", "")), workstations)
		if board.is_empty():
			problems.append(label + ": no sign placed above the chest")
			continue
		if str(board.get("mode", "")) != "header_items" or not str(board.get("text_a", "")).begins_with(str(stand.get("label", ""))):
			problems.append(label + ": the board is not a Header + Item Grid of its category")
		var listed: Array = board.get("items", [])
		if listed.size() != items.size():
			problems.append(label + ": the board lists %d ids for %d items" % [listed.size(), items.size()])
		else:
			for index in range(listed.size()):
				if str(listed[index]) != str(items[index]):
					problems.append(label + ": the board lists " + str(listed[index]) + " where the chest holds " + str(items[index]))
	var duplicates: Array[String] = []
	for item_id: String in stocked:
		if stocked.count(item_id) > 1 and item_id not in duplicates:
			duplicates.append(item_id)
	var missing: Array[String] = []
	for item_id: String in expected:
		if item_id not in stocked:
			missing.append(item_id)
	var extra: Array[String] = []
	for item_id: String in stocked:
		if item_id not in expected and item_id not in extra:
			extra.append(item_id)
	var walk := _walk_to_depot()
	var probe := _unassigned_probe()
	var ok: bool = bool(catalog.get("ok", false)) and (catalog.get("unassigned", []) as Array).is_empty() \
		and not stands.is_empty() and problems.is_empty() and duplicates.is_empty() \
		and missing.is_empty() and extra.is_empty() and bool(walk.get("ok", false)) \
		and bool(probe.get("ok", false))
	_record("T223_SUPPLY_DEPOT", ok,
		"after a Development New every non-hidden visible item of the registry is stocked exactly once in the generated Supply Depot, %d units of it, in a chest of at most eight distinct types that still has a free slot; every chest's board is a Header + Item Grid listing exactly the ids in that chest; the depot is an unobstructed walk from the spawn; and an item with no Expo category is reported as unassigned instead of being bucketed" % units,
		{"chests": stands.size(), "reserved": (catalog.get("reserved", []) as Array).size(), "stocked": stocked.size(),
		"expected": expected.size(), "missing": missing, "extra": extra, "duplicates": duplicates,
		"problems": problems, "walk": walk, "unassigned_probe": probe})


## The manifest's development-asset whitelist (hidden ids the depot may stock).
func _supply_whitelist() -> Array[String]:
	var result: Array[String] = []
	var config: Variant = app.development.layout.manifest.get("supply", {})
	if config is Dictionary:
		var raw: Variant = (config as Dictionary).get("hidden_whitelist", [])
		if raw is Array:
			for value: Variant in raw as Array:
				result.append(str(value))
	return result


## The stored board of the sign request `owner_id` placed ({} when there is none).
func _sign_of(requests: Array[Dictionary], owner_id: String, workstations: WorkstationService) -> Dictionary:
	for request: Dictionary in requests:
		if str(request.get("owner", "")) != owner_id or not bool(request.get("ok", false)):
			continue
		return workstations.sign_data(str(request.get("instance_id", "")))
	return {}


## The walk a visitor actually makes: straight down the plaza avenue from the
## spawn to the depot's front aisle, then along that aisle past every chest.
## Each cell must be air at head and foot height with solid ground under it.
func _walk_to_depot() -> Dictionary:
	var layout: ExpoLayout = app.development.layout
	var world: WorldAdapter = app.session.world
	var parcel := layout.parcel_for("supply_depot_stock")
	if parcel.is_empty():
		return {"ok": false, "reason": "NO_PARCEL"}
	var origin: Vector3i = parcel["origin"]
	var size: Vector3i = parcel["size"]
	var spawn := layout.spawn_feet()
	var feet_y := layout.ground_y() + 1
	var aisle_z := origin.z + size.z - 2
	var cells: Array[Vector3i] = []
	for z in range(int(floor(spawn.z)), aisle_z - 1, -1):
		cells.append(Vector3i(int(floor(spawn.x)), feet_y, z))
	for x in range(size.x):
		cells.append(Vector3i(origin.x + x, feet_y, aisle_z))
	var blocked: Array[Vector3i] = []
	var checked := 0
	for cell: Vector3i in cells:
		var feet := world.query_cell(cell)
		var head := world.query_cell(cell + Vector3i(0, 1, 0))
		if str(feet.get("state", "")) != "LOADED" or str(head.get("state", "")) != "LOADED":
			continue
		checked += 1
		var ground := int(world.query_cell(cell + Vector3i(0, -1, 0)).get("voxel_id", AIR))
		if int(feet.get("voxel_id", 1)) != AIR or int(head.get("voxel_id", 1)) != AIR or ground == AIR:
			blocked.append(cell)
	return {"ok": checked == cells.size() and blocked.is_empty(), "cells": cells.size(),
		"checked": checked, "blocked": blocked.size(), "first_blocked": blocked[0] if not blocked.is_empty() else Vector3i.ZERO}


## Drives the classifier directly: a registry carrying one item nobody has
## classified must produce an unassigned report, not a silent bucket.
func _unassigned_probe() -> Dictionary:
	var probe := ContentRegistry.new()
	probe.items["expo_unclassified_probe"] = {"id": "expo_unclassified_probe", "max_stack": 64, "category": "resource"}
	var catalog := SupplyDepot.catalog(probe, {"hidden_whitelist": _supply_whitelist()})
	var unassigned: Array = catalog.get("unassigned", [])
	var stocked: Array = catalog.get("items", [])
	return {"ok": not bool(catalog.get("ok", true)) and unassigned.has("expo_unclassified_probe")
		and not stocked.has("expo_unclassified_probe"),
		"classified": ItemCategories.classify("expo_unclassified_probe"), "unassigned": unassigned}


## T225 (signs card 2): the manifest's `sign_anchor` puts a board where it can
## be read instead of at its parcel's corner, and a block asking for the wide
## board gets the two-cell `sign_board`. The Battlefield's arena sign must
## stand within `SIGN_ANCHOR_TOLERANCE` cells of the gate it is anchored to -
## it used to stand tens of cells away, at the corner of the whole field - and
## the plaza's orientation board must be the wide one. Every other request is
## still fulfilled, which T215 asserts in full.
func _test_sign_anchors() -> void:
	var builder: ExpoBuilder = app.development.expo_builder
	var workstations: WorkstationService = app.session.workstations
	var requests := builder.sign_requests()
	var anchored := builder.sign_anchor_for(ANCHORED_EXHIBIT)
	var arena := _sign_request_of(requests, ANCHORED_EXHIBIT)
	var arena_cell: Vector3i = arena.get("cell", Vector3i.ZERO)
	var anchor_cell: Vector3i = anchored.get("cell", Vector3i.ZERO)
	var distance := (Vector3(arena_cell) - Vector3(anchor_cell)).length()
	var arena_placed: bool = not anchored.is_empty() and bool(arena.get("ok", false))
	var arena_ok: bool = arena_placed and distance <= float(SIGN_ANCHOR_TOLERANCE)
	# The gate it labels, so the evidence shows the walk it saved.
	var gate := app.development.layout.parcel_for("battlefield_fortification")
	var corner: Vector3i = app.development.layout.parcel_for(ANCHORED_EXHIBIT).get("origin", Vector3i.ZERO)
	var plaza := _sign_request_of(requests, "central_plaza")
	var plaza_entity := str(workstations.stations.get(str(plaza.get("instance_id", "")), {}).get("entity_id", ""))
	var plaza_ok: bool = bool(plaza.get("ok", false)) and plaza_entity == WorkstationService.SIGN_BOARD_ENTITY
	# A wide board owns both of its cells: the second one answers to it too.
	var plaza_cell: Vector3i = plaza.get("cell", Vector3i.ZERO)
	var second: Vector3i = plaza_cell + workstations.footprints.rotate_offset(
		Vector3i(0, 0, 1), int(workstations.stations.get(str(plaza.get("instance_id", "")), {}).get("rotation_quarters", 0)))
	var both_cells: bool = workstations.station_at_cell(second) == str(plaza.get("instance_id", ""))
	var depot := _sign_request_of(requests, "supply_chest_00")
	var depot_entity := str(workstations.stations.get(str(depot.get("instance_id", "")), {}).get("entity_id", ""))
	var depot_ok: bool = bool(depot.get("ok", false)) and depot_entity == WorkstationService.SIGN_BOARD_ENTITY
	var ok: bool = arena_ok and plaza_ok and both_cells and depot_ok and builder.pending_signs().is_empty()
	_record("T225_SIGN_ANCHORS", ok,
		"an exhibit's `sign_anchor` stands its board where it is read - the Battlefield's arena sign within %d cells of the player-side gate instead of at the parcel corner - the plaza orientation board and the Supply Depot chest boards are the two-cell wide board owning both of their cells, and no sign request is left unfulfilled" % SIGN_ANCHOR_TOLERANCE,
		{"arena_cell": arena_cell, "anchor_cell": anchor_cell, "parcel_corner": corner,
		"gate": gate.get("origin", Vector3i.ZERO), "distance": distance, "arena_ok": arena_ok,
		"plaza_cell": plaza_cell, "plaza_entity": plaza_entity, "second_cell": second, "both_cells": both_cells,
		"depot_entity": depot_entity, "pending": builder.pending_signs().size()})


## The request the builder recorded for `owner_id` ({} when there is none).
func _sign_request_of(requests: Array[Dictionary], owner_id: String) -> Dictionary:
	for request: Dictionary in requests:
		if str(request.get("owner", "")) == owner_id:
			return request
	return {}


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
	if not await _wait_built("mountain", _district_owners(["mining_mountain"])):
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
	var blocked: Array[Dictionary] = []
	var lights := _light_positions()
	# The tunnel is longer than one streaming region, so this is a real walk:
	# the player is moved down it cell by cell and the terrain around each cell
	# is given frames to arrive before it is read (card E's campus-walk rule).
	for step in range(TUNNEL_WALK):
		var cell := Vector3i(tunnel_origin.x + tunnel_size.x - 3 - step, tunnel_origin.y, centre_z)
		_teleport(Vector3(float(cell.x) + 0.5, float(cell.y) + 1.1, float(cell.z) + 0.5))
		var head := world.query_cell(cell + Vector3i(0, 1, 0))
		var feet := world.query_cell(cell)
		for _frame in range(STREAM_FRAMES):
			if str(feet.get("state", "")) == "LOADED" and str(head.get("state", "")) == "LOADED":
				break
			await get_tree().process_frame
			head = world.query_cell(cell + Vector3i(0, 1, 0))
			feet = world.query_cell(cell)
		if str(feet.get("state", "")) != "LOADED" or str(head.get("state", "")) != "LOADED":
			continue
		walked += 1
		var floor_voxel := int(world.query_cell(cell + Vector3i(0, -1, 0)).get("voxel_id", AIR))
		if int(feet.get("voxel_id", 1)) == AIR and int(head.get("voxel_id", 1)) == AIR and floor_voxel != AIR:
			walkable += 1
		elif blocked.size() < 8:
			# Name the first few obstructions so a failure says where and what.
			blocked.append({"cell": str(cell), "feet": int(feet.get("voxel_id", -1)),
				"head": int(head.get("voxel_id", -1)), "floor": floor_voxel})
		for light: Vector3 in lights:
			if light.distance_to(Vector3(cell)) <= LIGHT_RANGE:
				lit += 1
				break
	# Only the mine line: the Defense Range's kettle booth lays rails of its own
	# along a wall top, and those are not part of this chain.
	var rail_parcel := _parcel_box("mountain_rail")
	var rails: Array[Vector3i] = []
	for instance_id: String in app.session.workstations.stations.keys():
		var record: Dictionary = app.session.workstations.stations[instance_id]
		var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
		if str(record.get("entity_id", "")) == "rail" and _inside(rail_parcel, anchor):
			rails.append(anchor)
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
		{"ores": ores, "core_sampled": core_sampled, "walked": walked, "walkable": walkable, "lit": lit, "blocked": blocked,
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
	if not await _wait_built("industry", _district_owners(["industry"])):
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
	# Only the mine line's own two parcels: the Defense Range's kettle booth
	# lays rails along a wall top and the CoasterCraft district lays hundreds
	# of them, and none of those belong to this chain.
	var mountain_box := _parcel_box("mountain_rail")
	var yard_box := _parcel_box("industry_rail")
	var rails: Array[Vector3i] = []
	for instance_id: String in ws.stations.keys():
		var record: Dictionary = ws.stations[instance_id]
		var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
		if str(record.get("entity_id", "")) != "rail":
			continue
		if _inside(mountain_box, anchor) or _inside(yard_box, anchor):
			rails.append(anchor)
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
	if not await _wait_built("lighting", _district_owners(["lighting"])):
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
## T218: the Construction Yard shows every castle piece on its own booth and
## then the same pieces assembled - a drag-built wall, a stamped blueprint and
## a small castle - each of them signed.
func _test_construction_yard() -> void:
	var layout: ExpoLayout = app.development.layout
	if not await _walk_to_district("construction_yard"):
		return
	var pieces := {"cy_stone_stair": "stone_stair", "cy_wall_walk_slab": "wall_walk_slab",
		"cy_parapet_merlon": "parapet_merlon", "cy_tower_platform": "tower_platform",
		"cy_gate_frame": "gate_frame", "cy_gate": "gate", "cy_wood_barricade": "wood_barricade"}
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
	# Defence sets (docs/DEFENSE_SETS.md): the gate booth hangs a real leaf in a
	# frame, and it is hung shut; the wall kit booth is a whole stamped section.
	var gate_box := _parcel_box("cy_gate")
	var gate_leaves := _stations_in(gate_box, "gate")
	var gate_shut: bool = not gate_leaves.is_empty() and not app.session.workstations.gate_is_open(gate_leaves[0])
	var gate_framed: bool = not _stations_in(gate_box, "gate_frame").is_empty()
	var kit_box := _parcel_box("cy_wall_kit")
	var kit_stone := _voxels_in(kit_box, CASTLE_STONE)
	var kit_walk := _stations_in(kit_box, "wall_walk_slab").size()
	var kit_merlons := _stations_in(kit_box, "parapet_merlon").size()
	var kit_stairs := _stations_in(kit_box, "stone_stair").size()
	var reserved_empty: bool = _stations_in(_parcel_box("cy_expansion_reserved"), "").is_empty()
	var ok: bool = missing_pieces.is_empty() and stone_booth and unsigned.is_empty() \
		and wall_stone >= 36 and wall_deck >= 8 and wall_merlons >= 4 \
		and stamp_stone > 0 and stamps_ok \
		and gate_shut and gate_framed \
		and kit_stone == 16 and kit_walk == 8 and kit_merlons == 4 and kit_stairs == 4 \
		and castle_stone > 0 and castle_gate and castle_platform and castle_stairs >= 3 and reserved_empty
	_record("T218_EXPO_CONSTRUCTION", ok,
		"the Construction Yard stands each castle piece on its own signed booth and then shows them assembled: a drag-built run of castle stone with a wall-walk deck and merlons on it, the FOUNDATION 4 / TOWER SEGMENT 4 / CAP 4 blueprint stack stamped and recorded as stamps, the Gate booth hanging a real leaf in a frame, shut; the Wall Kit booth holding one whole stamped section (sixteen castle stone, an eight-cell wall-walk, four merlons and four stair steps); and a small castle with a gate frame, a stair and a tower platform; the future-castle-technology parcel is signed and empty",
		{"missing_pieces": missing_pieces, "castle_stone_booth": stone_booth, "unsigned": unsigned,
		"wall": {"stone": wall_stone, "deck": wall_deck, "merlons": wall_merlons},
		"stamp": {"stone": stamp_stone, "stamps": stamped},
		"gate": {"shut": gate_shut, "framed": gate_framed},
		"wall_kit": {"stone": kit_stone, "walk": kit_walk, "merlons": kit_merlons, "stairs": kit_stairs},
		"castle": {"stone": castle_stone, "gate": castle_gate, "platform": castle_platform, "stairs": castle_stairs},
		"reserved_empty": reserved_empty})


## T219: every Defense Range booth (seven since the defence sets card added
## the Rail Turret) is a weapon that could be demonstrated -
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
		"dr_cannon": "cannon", "dr_kettle": "kettle", "dr_rail_turret": "rail_turret"}
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
		"each of the seven Defense Range booths stands its weapon on the mount its sheet allows, with its own munition in the container the storage network sees beside it, a castle-stone target down its lane and a sign naming the weapon and the ammunition; draining the Cannon back to the clip its sheet opens with is topped up again by the existing storage-network reload, and the munition comes out of the chest",
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
	if not await _wait_built("battlefield reset", _district_owners(["battlefield"])):
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
## T221 (card F): every component-gallery specimen stands inside its own
## parcel, laid by the real lay tools (its pieces carry the tools' curves),
## each under its own placed sign; the CoasterCraft Shop is a usable station
## whose recipe book opens on its own modal.
func _test_coaster_gallery() -> void:
	var layout: ExpoLayout = app.development.layout
	var centre := _parcel_centre(layout.parcel_for("coaster_rail_curve"))
	_teleport(centre + Vector3(0.0, 2.0, 0.0))
	if not await _wait_built("coastercraft gallery", _district_owners(["coastercraft"])):
		return
	var workstations: WorkstationService = app.session.workstations
	var signs: Dictionary = {}
	for request: Dictionary in app.development.expo_builder.sign_requests():
		if bool(request.get("ok", false)):
			signs[str(request.get("owner", ""))] = str(request.get("instance_id", ""))
	var missing: Array[String] = []
	var booths: Array[Dictionary] = []
	for booth: Dictionary in COASTER_GALLERY:
		var exhibit_id := str(booth["id"])
		var parcel := layout.parcel_for(exhibit_id)
		var found := _parcel_contents(parcel)
		var entities: Dictionary = found["entities"]
		var families: Dictionary = found["families"]
		for entity_id: Variant in booth["entities"]:
			if not entities.has(str(entity_id)):
				missing.append("%s: no %s" % [exhibit_id, entity_id])
		for family: Variant in booth["families"]:
			if not families.has(str(family)):
				missing.append("%s: no %s piece" % [exhibit_id, family])
		if not signs.has(exhibit_id):
			missing.append(exhibit_id + ": no sign")
		booths.append({"id": exhibit_id, "entities": entities.keys(), "families": families.keys(), "sign": signs.get(exhibit_id, "")})
	# The shop is not a prop: it opens its own recipe book.
	var shop_id := ""
	for instance_id: String in workstations.stations.keys():
		var record: Dictionary = workstations.stations[instance_id]
		if str(record.get("entity_id", "")) == "coastercraft_shop":
			shop_id = instance_id
			break
	var book_ok := false
	var title := ""
	if not shop_id.is_empty():
		app._show_workstation(shop_id, "coastercraft_shop")
		for _frame in range(4):
			await get_tree().process_frame
		title = app.crafting_title_label.text
		book_ok = app.state == app.AppState.CRAFTING and app._crafting_station_type == "coastercraft_shop" and title == "COASTERCRAFT SHOP"
		app._close_crafting()
		for _frame in range(4):
			await get_tree().process_frame
	var ok: bool = missing.is_empty() and not shop_id.is_empty() and book_ok
	_record("T221_EXPO_COASTER_GALLERY", ok,
		"every CoasterCraft gallery specimen stands in its own parcel with its sign - plain Rail, Rail Slope, the true Rail Loop, Rail Switch, Rail Cross, Rail Curve, Rail Climb, a Mine Cart, a Coaster Car and a placed CoasterCraft Shop - each track specimen laid by the real lay tool (its pieces carry that tool's curve), and the Shop opens its own COASTERCRAFT SHOP recipe book",
		{"booths": booths, "missing": missing, "shop": shop_id, "book_title": title, "book_ok": book_ok})


## T222 (card F): the Grand Demonstration Coaster. Every required track family
## is present, the whole circuit is one connected chain through the station,
## and the parked Coaster Car boards through the real `CoasterRide` path,
## rides the whole circuit and comes home without ever hanging upside down
## outside the loop.
func _test_grand_coaster() -> void:
	var layout: ExpoLayout = app.development.layout
	var parcel := layout.parcel_for("grand_coaster")
	var origin: Vector3i = parcel["origin"]
	_teleport(_parcel_centre(parcel) + Vector3(0.0, 2.0, 0.0))
	if not await _wait_built("grand coaster", _district_owners(["coastercraft"])):
		return
	var workstations: WorkstationService = app.session.workstations
	var found := _parcel_contents(parcel)
	var families: Dictionary = found["families"]
	var cells: Dictionary = found["cells"]
	var loop_cells: Dictionary = found["loop_cells"]
	var missing_families: Array[String] = []
	for family: String in COASTER_FAMILIES:
		if not families.has(family):
			missing_families.append(family)
	# The lane switcher is the shifted s-bend of one lane; the crossing's own
	# s-bends are six lanes wide and its middle cells carry a second curve.
	var shifts: Array = found["switch_shifts"]
	var switch_ok: bool = shifts.has(COASTER_SWITCH_SHIFT)
	# One connected chain: everything the showpiece laid is reachable from the
	# station rail, and the chain leaves nothing out and nothing over.
	var station := ExpoCoaster.show_station(origin)
	var station_cell: Vector3i = station["station"]
	var chain := CoasterRails.chain(workstations.stations, station_cell)
	var off_circuit := 0
	for cell: Variant in chain.keys():
		if not cells.has(cell):
			off_circuit += 1
	var unreachable: Array = []
	for cell: Variant in cells.keys():
		if not chain.has(cell):
			unreachable.append(cell)
	var chain_ok: bool = chain.size() == cells.size() and off_circuit == 0 and unreachable.is_empty()
	# The ride itself, through the ordinary board / advance / leave path.
	var car_cell: Vector3i = station["car"]
	var car_id := workstations.station_at_cell(car_cell)
	var boarded := app.session.board_coaster_car(car_id)
	app.session.set_ride_speed(CoasterRide.MAX_SPEED_LEVEL)
	var rig: Node3D = app.session.coaster_carts.cart_rig(car_id)
	var covered := false
	var returned := false
	var inverted_outside := 0
	var frames := 0
	var deadline := Time.get_ticks_msec() + RIDE_TIMEOUT_MSEC
	while frames < RIDE_FRAME_BUDGET and Time.get_ticks_msec() < deadline and not returned:
		await get_tree().process_frame
		frames += 1
		var here: Vector3i = app.session.coaster_carts.rider_cell(car_id)
		# A lap is over when the car has been on every cell of the circuit and
		# is back on the station rail it started from.
		if frames % 10 == 0:
			covered = _trail_covers(car_id, cells)
		if covered and here == station_cell:
			returned = true
		if rig != null and is_instance_valid(rig) and rig.global_basis.y.y < 0.0 and not loop_cells.has(here):
			inverted_outside += 1
	var trail := app.session.coaster_carts.trail(car_id)
	var ridden: Dictionary = {}
	for cell: Variant in trail.keys():
		var record: Dictionary = _track_record_at(cell)
		var family := _track_family(record)
		if not family.is_empty():
			ridden[family] = int(ridden.get(family, 0)) + 1
	var ridden_missing: Array[String] = []
	for family: String in COASTER_FAMILIES:
		if not ridden.has(family):
			ridden_missing.append(family)
	app.session.leave_coaster_car()
	var ok: bool = missing_families.is_empty() and switch_ok and chain_ok and bool(boarded.get("ok", false)) \
		and returned and ridden_missing.is_empty() and inverted_outside == 0
	_record("T222_EXPO_GRAND_COASTER", ok,
		"the Grand Demonstration Coaster holds at least one piece of every track family (straight, climb, curve, true loop, lane switcher, crossing) read from the station records' entity and curve data; its %d pieces form one connected chain through the station and nothing else; the parked Coaster Car boards through CoasterRide, rides every family, returns to the station rail inside %d frames, and the rider's up vector never inverts outside the loop" % [cells.size(), RIDE_FRAME_BUDGET],
		{"families": families.keys(), "missing_families": missing_families, "switch_shifts": shifts,
		"pieces": cells.size(), "chain": chain.size(), "off_circuit": off_circuit, "unreachable": unreachable,
		"boarded": boarded.get("reason", ""), "frames": frames, "returned": returned, "covered": covered,
		"trail": trail.size(),
		"ridden": ridden, "ridden_missing": ridden_missing, "inverted_outside": inverted_outside,
		"station": station_cell, "car": car_cell})


## The track family of a station record, from its entity id and its recorded
## curve alone: "straight" (a plain rail or a flat run of the Climb tool),
## "slope", "curve" (an arc), "loop" (a helix), "climb" (a rising s-bend),
## "switch" (a shifted s-bend) or "cross" (a cell carrying two curves).
static func _track_family(record: Dictionary) -> String:
	var entity_id := str(record.get("entity_id", ""))
	if entity_id == CoasterRails.FLAT:
		return "straight"
	if entity_id == CoasterRails.SLOPE:
		return "slope"
	if entity_id != CoasterRails.LOOP:
		return ""
	if CoasterRails.has_second_curve(record):
		return "cross"
	var curve: Dictionary = record.get("curve", {})
	var params: Dictionary = curve.get("params", {})
	match str(curve.get("kind", "")):
		"helix":
			return "loop"
		"arc":
			return "curve"
		"s_bend":
			if absf(float(params.get("rise", 0.0))) > 0.01:
				return "climb"
			if absf(float(params.get("shift", 0.0))) > 0.01:
				return "switch"
			return "straight"
	return ""


## What stands inside a parcel: {entities: {id: count}, families: {family:
## count}, cells: {cell: true} of its track pieces, loop_cells: {cell: true}
## of the true loop's pieces, switch_shifts: the lane shifts of its s-bends}.
func _parcel_contents(parcel: Dictionary) -> Dictionary:
	var origin: Vector3i = parcel.get("origin", Vector3i.ZERO)
	var size: Vector3i = parcel.get("size", Vector3i.ZERO)
	var entities: Dictionary = {}
	var families: Dictionary = {}
	var cells: Dictionary = {}
	var loop_cells: Dictionary = {}
	var shifts: Array = []
	for instance_id: String in app.session.workstations.stations.keys():
		var record: Dictionary = app.session.workstations.stations[instance_id]
		var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
		if anchor.x < origin.x or anchor.x >= origin.x + size.x or anchor.z < origin.z or anchor.z >= origin.z + size.z:
			continue
		var entity_id := str(record.get("entity_id", ""))
		entities[entity_id] = int(entities.get(entity_id, 0)) + 1
		var family := _track_family(record)
		if family.is_empty():
			continue
		families[family] = int(families.get(family, 0)) + 1
		cells[anchor] = true
		if family == "loop":
			loop_cells[anchor] = true
		if family == "switch":
			var shift := absf(float((record.get("curve", {}) as Dictionary).get("params", {}).get("shift", 0.0)))
			if not shifts.has(shift):
				shifts.append(shift)
	return {"entities": entities, "families": families, "cells": cells, "loop_cells": loop_cells, "switch_shifts": shifts}


## True once the car's trail holds every cell of the circuit.
func _trail_covers(car_id: String, cells: Dictionary) -> bool:
	var trail := app.session.coaster_carts.trail(car_id)
	for cell: Variant in cells.keys():
		if not trail.has(cell):
			return false
	return true


## The station record of the track piece in `cell` ({} when there is none).
func _track_record_at(cell: Vector3i) -> Dictionary:
	var instance_id := app.session.workstations.station_at_cell(cell)
	if instance_id.is_empty():
		return {}
	return app.session.workstations.stations.get(instance_id, {})


static func _parcel_centre(parcel: Dictionary) -> Vector3:
	var origin: Vector3i = parcel.get("origin", Vector3i.ZERO)
	var size: Vector3i = parcel.get("size", Vector3i.ZERO)
	return Vector3(origin) + Vector3(float(size.x) * 0.5, 0.0, float(size.z) * 0.5)


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


## Reading evidence for T223: one Supply Depot chest framed from the aisle in
## front of it, close enough to read its board's 4x2 item grid against the
## chest below. The Construction chest is chosen because it is the fullest
## grid the current catalog produces.
func _shoot_supply_row() -> void:
	var stands := app.development.expo_builder.supply_stands()
	var chosen: Dictionary = {}
	for stand: Dictionary in stands:
		if str(stand.get("category", "")) == "construction":
			chosen = stand
			break
	if chosen.is_empty() and not stands.is_empty():
		chosen = stands[0]
	if chosen.is_empty():
		_record("T223V_SUPPLY_VIEW", false, "rendered evidence of a Supply Depot chest and its board", {"reason": "NO_STAND"})
		return
	var chest: Vector3i = chosen["chest"]
	# Close enough to read the 4x2 grid, low enough to keep the chest under it
	# in frame: the board is two cells above the chest, one cell behind it.
	var board := Vector3(float(chest.x) + 0.5, float(chest.y) + 1.75, float(chest.z) - 0.5)
	var eye := Vector3(float(chest.x) + 0.5, float(chest.y) + 1.45, float(chest.z) + 4.0)
	_teleport(eye)
	if not await _wait_built("supply depot", _district_owners(["supply_depot"])):
		return
	_look_from(eye, board)
	for _frame in range(60):
		await get_tree().process_frame
	_look_from(eye, board)
	await get_tree().process_frame
	var path := app.data_root.path_join("development-expo-supply.png")
	var shot := await _save_viewport(path)
	_record("T223V_SUPPLY_VIEW", shot,
		"rendered evidence that a Supply Depot chest stands under its own Header + Item Grid board, the grid listing the eight-unit stock inside it",
		{"path": path, "category": str(chosen.get("category", "")), "items": chosen.get("items", []), "cell": chest})


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
		# Either board is a sign: the manifest asks for the wide one with
		# `"board": "wide"` (docs/SIGNS.md).
		if not WorkstationService.is_sign(str(record.get("entity_id", ""))):
			unfulfilled.append(owner_id + ": no sign station")
			continue
		if str(record.get("entity_id", "")) != str(request.get("entity", "sign")):
			mismatched.append(owner_id + ": wrong board")
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


## Waits until the builder has nothing left to do. With `owners` (district and
## exhibit ids, from `_district_owners`) it waits only on that district's work:
## a district on the far side of the campus is deliberately parked until
## someone walks there, so waiting on the whole queue from the plaza would
## never finish once the CoasterCraft park (card F) is built too.
func _wait_built(label: String, owners: PackedStringArray = PackedStringArray()) -> bool:
	var builder: ExpoBuilder = app.development.expo_builder
	var deadline := Time.get_ticks_msec() + BUILD_TIMEOUT_MSEC
	while _still_building(builder, owners):
		builder.advance(BUILD_BUDGET_PER_FRAME)
		if Time.get_ticks_msec() >= deadline:
			failures.append("%s build timeout (%s)" % [label, JSON.stringify(builder.progress())])
			return false
		await get_tree().process_frame
	# A queue can empty while a late cell is still streaming in: settle and
	# re-check ONLY this wait's own districts (advancing the whole queue here
	# burned the far parcels' requeue budget while the player stood elsewhere,
	# which is what made the exported build give up on the coaster pad).
	for _settle in range(3):
		for _frame in range(30):
			await get_tree().process_frame
		if not _still_building(builder, owners):
			break
		var settle_deadline := Time.get_ticks_msec() + BUILD_TIMEOUT_MSEC
		while _still_building(builder, owners):
			builder.advance(BUILD_BUDGET_PER_FRAME)
			if Time.get_ticks_msec() >= settle_deadline:
				failures.append("%s build timeout after settling (%s)" % [label, JSON.stringify(builder.progress())])
				return false
			await get_tree().process_frame
	# Only this wait's own districts count: a far parcel that has not streamed
	# in yet is not this district's failure.
	var mine: Array[String] = []
	for failure: String in builder.failures():
		if owners.is_empty() or _failure_owned(failure, owners):
			mine.append(failure)
	if not mine.is_empty():
		failures.append("%s build failures: %s" % [label, "; ".join(mine)])
		return false
	return true


static func _failure_owned(failure: String, owners: PackedStringArray) -> bool:
	for owner: String in owners:
		if failure.contains(owner):
			return true
	return false


static func _still_building(builder: ExpoBuilder, owners: PackedStringArray) -> bool:
	if owners.is_empty():
		return builder.pending_ops() > 0 or builder.deferred_ops() > 0
	return builder.pending_for(owners) > 0


## A district's id plus every exhibit id in it: the owners of its build ops.
func _district_owners(district_ids: Array) -> PackedStringArray:
	var owners := PackedStringArray()
	for district_id: Variant in district_ids:
		owners.append(str(district_id))
		for exhibit_id: String in app.development.layout.exhibit_ids(str(district_id)):
			owners.append(exhibit_id)
	return owners


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


# --- Card D1: the Expo Directory, What's new and the test notes ---------------


## T234. The raw key opens the panel in Development mode and is refused in the
## ordinary game; the owner's own search ("wall kit") finds the exhibit with
## the description its sign carries; the district and category filters narrow
## the list; and the What's new filter shows what the manifest stamped.
func _test_directory_search() -> void:
	var evidence: Dictionary = {}
	var ok := true
	# Refused outside Development mode: the same key, with the mode's flags
	# down, must leave the game playing and say why.
	app._close_directory()
	app.development.active = false
	app.session.development = false
	_press_key(KEY_K)
	var refused: bool = app.state == CraftAndDefendApp.AppState.PLAYING and not app.directory_available()
	evidence["refused_outside_development"] = refused
	ok = ok and refused
	app.development.active = true
	app.session.development = true
	_press_key(KEY_K)
	var opened: bool = app.state == CraftAndDefendApp.AppState.DIRECTORY and app.directory_panel.visible
	evidence["key_opens_panel"] = opened
	ok = ok and opened
	if not opened:
		_record("T234_DIRECTORY_SEARCH", false, "K opens the Directory in Development mode and is refused elsewhere", evidence)
		return
	var model := ExpoDirectory.new(app.development.layout, app.session.registry, app.session.expo_notes)
	var rows := model.entries()
	evidence["entries"] = rows.size()
	# The search field itself: typing filters live, and the panel draws what
	# the filter answers.
	app.directory_search.text = DIRECTORY_SEARCH
	app._on_directory_search_changed(DIRECTORY_SEARCH)
	var found := _directory_shown()
	var hit: Dictionary = {}
	for row: Dictionary in found:
		if str(row.get("id", "")) == DIRECTORY_SEARCH_EXHIBIT:
			hit = row
	var described: bool = not hit.is_empty() and not str(hit.get("description", "")).is_empty()
	evidence["wall_kit"] = {"found": not hit.is_empty(), "name": str(hit.get("name", "")),
		"description": str(hit.get("description", "")), "district": str(hit.get("district", "")),
		"icon": str(hit.get("icon_item", "")), "matches": found.size()}
	# The panel really lists them (one card per row it answered).
	var drawn: int = app.directory_list.get_child_count()
	evidence["cards_drawn"] = drawn
	ok = ok and described and drawn == found.size()
	# District filter: only that district's rows come back, and the wall kit's
	# own district still holds it.
	var district := str(hit.get("district", "construction_yard"))
	app._set_directory_filter("district", district)
	var by_district := _directory_shown()
	var district_only := not by_district.is_empty()
	var district_holds := false
	for row: Dictionary in by_district:
		if str(row.get("district", "")) != district:
			district_only = false
		if str(row.get("id", "")) == DIRECTORY_SEARCH_EXHIBIT:
			district_holds = true
	evidence["district_filter"] = {"district": district, "rows": by_district.size(), "only_that_district": district_only, "holds_wall_kit": district_holds}
	ok = ok and district_only and district_holds and by_district.size() < rows.size()
	# Category filter, applied on its own over the whole campus.
	app._clear_directory_filters()
	var category := str(hit.get("category", ""))
	app._set_directory_filter("category", category)
	var by_category := _directory_shown()
	var category_only := not by_category.is_empty()
	for row: Dictionary in by_category:
		if str(row.get("category", "")) != category:
			category_only = false
	evidence["category_filter"] = {"category": category, "rows": by_category.size(), "only_that_category": category_only}
	ok = ok and category_only and by_category.size() < rows.size()
	# What's new: the manifest's newest `added_in` stamp and nothing older.
	app._clear_directory_filters()
	app._toggle_directory_whats_new()
	var newest := ExpoDirectory.newest_added_in(rows)
	var new_rows := _directory_shown()
	var new_ids: Array[String] = []
	var all_newest := not new_rows.is_empty()
	for row: Dictionary in new_rows:
		new_ids.append(str(row.get("id", "")))
		if str(row.get("added_in", "")) != newest:
			all_newest = false
	evidence["whats_new"] = {"stamp": newest, "ids": new_ids}
	ok = ok and all_newest and new_ids.has(DIRECTORY_SEARCH_EXHIBIT)
	app._clear_directory_filters()
	_record("T234_DIRECTORY_SEARCH", ok, "K opens the Directory in Development mode and is refused elsewhere; a search for the owner's own words answers the wall-kit exhibit with its sign's description; the district, category and What's new filters narrow the list", evidence)


## T235. Selecting a row puts the player on loaded ground beside that parcel,
## looking at it - for three districts, the last of them the far CoasterCraft
## park whose terrain has to stream in first.
func _test_directory_teleport() -> void:
	var evidence: Array[Dictionary] = []
	var ok := true
	if app.state != CraftAndDefendApp.AppState.DIRECTORY:
		app._open_directory()
	for exhibit_id: String in DIRECTORY_TELEPORT_EXHIBITS:
		var parcel := app.development.layout.parcel_for(exhibit_id)
		if parcel.is_empty():
			evidence.append({"exhibit": exhibit_id, "parcel": false})
			ok = false
			continue
		await app._directory_teleport(exhibit_id, exhibit_id)
		var player: PlayerController = app.session.player
		var feet := player.global_position
		var distance := _distance_to_parcel(parcel, feet)
		var cell := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z))
		var under := app.session.world.query_cell(cell + Vector3i(0, -1, 0))
		var standing: bool = str(under.get("state", "")) == "LOADED" and int(under.get("voxel_id", AIR)) != AIR
		var at_feet := app.session.world.query_cell(cell)
		var clear: bool = str(at_feet.get("state", "")) == "LOADED" and int(at_feet.get("voxel_id", AIR)) == AIR
		var origin: Vector3i = parcel["origin"]
		var size: Vector3i = parcel["size"]
		var centre := Vector3(origin) + Vector3(size) * 0.5
		var to_centre := Vector3(centre.x, feet.y, centre.z) - feet
		var forward := -player.global_transform.basis.z
		var facing := Vector2(forward.x, forward.z).normalized().dot(Vector2(to_centre.x, to_centre.z).normalized())
		var near: bool = distance <= DIRECTORY_LANDING_CELLS
		evidence.append({"exhibit": exhibit_id, "district": str(parcel.get("district", "")),
			"cells_from_parcel": snappedf(distance, 0.01), "standing_on_loaded_ground": standing,
			"head_room": clear, "facing_dot": snappedf(facing, 0.01)})
		ok = ok and near and standing and clear and facing >= 0.5
	_record("T235_DIRECTORY_TELEPORT", ok, "selecting an exhibit stands the player on loaded, solid ground within %d cells of its parcel, looking at it, in three districts including the far CoasterCraft park" % int(DIRECTORY_LANDING_CELLS), evidence)


## T236. A note with a status is stored, survives a save/restore, shows in the
## panel, keeps its history, exports as the markdown table - and no snapshot
## outside Development mode carries the notes namespace at all.
func _test_expo_notes() -> void:
	var evidence: Dictionary = {}
	var ok := true
	if app.state != CraftAndDefendApp.AppState.DIRECTORY:
		app._open_directory()
	var notes: ExpoNotes = app.session.expo_notes
	notes.clear()
	app._open_directory_notes(NOTES_SUBJECT, "Wall Kit", "exhibit")
	app._set_directory_note_status("broken")
	app.directory_note_edit.text = NOTES_FIRST_REMARK
	app._add_directory_note()
	app.directory_note_edit.text = NOTES_SECOND_REMARK
	app._set_directory_note_status("working")
	app._add_directory_note()
	# A status change keeps the newest remark: no retyping.
	app._set_directory_note_status("approved")
	app._apply_directory_status()
	var stored := {"status": notes.status_of(NOTES_SUBJECT), "remark": str(notes.latest_remark(NOTES_SUBJECT).get("remark", "")),
		"history": notes.note_count(NOTES_SUBJECT)}
	evidence["stored"] = stored
	ok = ok and str(stored["status"]) == "approved" and str(stored["remark"]) == NOTES_SECOND_REMARK and int(stored["history"]) == 3
	# The panel shows the newest remark and status on the row.
	app._refresh_directory()
	var shown_row: Dictionary = {}
	for row: Dictionary in app._directory_rows:
		if str(row.get("id", "")) == NOTES_SUBJECT:
			shown_row = row
	evidence["panel_row"] = {"status": str(shown_row.get("status", "")), "remark": str(shown_row.get("remark", "")), "notes": int(shown_row.get("notes", 0))}
	ok = ok and str(shown_row.get("status", "")) == "approved" and str(shown_row.get("remark", "")) == NOTES_SECOND_REMARK
	# The development save's own namespace: the snapshot carries the notes and
	# they come back out of it unchanged.
	var snapshot := app.session.snapshot()
	var carried: bool = snapshot.has("expo_notes")
	var restored := ExpoNotes.new()
	var saved: Variant = snapshot.get("expo_notes", {})
	restored.restore(saved if saved is Dictionary else {})
	var round_trip: bool = restored.status_of(NOTES_SUBJECT) == "approved" \
		and restored.note_count(NOTES_SUBJECT) == 3 \
		and str(restored.latest_remark(NOTES_SUBJECT).get("remark", "")) == NOTES_SECOND_REMARK
	evidence["save_round_trip"] = {"snapshot_has_notes": carried, "restored": round_trip,
		"restored_history": restored.note_count(NOTES_SUBJECT)}
	ok = ok and carried and round_trip
	# And a real checkpoint on disk: the development save is written and read
	# back the way `--expo-notes-export` reads it, with no world opened.
	var written: Dictionary = await app.active_saves().save_session(app.session)
	var checkpoint := app.development.saves.read_checkpoint()
	var on_disk := ExpoNotes.new()
	var disk_data: Variant = checkpoint.get("snapshot", {}).get("expo_notes", {})
	on_disk.restore(disk_data if disk_data is Dictionary else {})
	var disk_ok: bool = bool(written.get("ok", false)) and bool(checkpoint.get("ok", false)) 		and on_disk.status_of(NOTES_SUBJECT) == "approved" and on_disk.note_count(NOTES_SUBJECT) == 3
	evidence["checkpoint"] = {"saved": bool(written.get("ok", false)), "reason": str(written.get("reason", "")),
		"read_back": bool(checkpoint.get("ok", false)), "history": on_disk.note_count(NOTES_SUBJECT),
		"status": on_disk.status_of(NOTES_SUBJECT)}
	ok = ok and disk_ok
	# No other save ever carries them: the same session, asked for an ordinary
	# game's snapshot, writes no notes namespace at all.
	app.session.development = false
	var normal := app.session.snapshot()
	app.session.development = true
	var isolated: bool = not normal.has("expo_notes") and not normal.has("expo")
	evidence["normal_save_untouched"] = {"expo_notes_key": normal.has("expo_notes"),
		"development_data_root": app.development.data_root(), "game_data_root": app.saves.data_root}
	ok = ok and isolated and app.development.data_root() != app.saves.data_root
	# The export: the table, the newest remark and the whole history under it.
	var exported := app.export_expo_notes(notes)
	var path := str(exported.get("path", ""))
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	var table: bool = text.contains("| Subject | Status | Newest remark | Date |") \
		and text.contains(NOTES_SUBJECT) and text.contains("Approved") \
		and text.contains(NOTES_SECOND_REMARK) and text.contains(NOTES_FIRST_REMARK)
	evidence["export"] = {"path": path, "bytes": text.length(), "table": table, "subjects": int(exported.get("subjects", 0))}
	ok = ok and bool(exported.get("ok", false)) and table
	app._close_directory()
	_record("T236_EXPO_NOTES", ok, "a remark and a status are stored per subject, appended as a history, shown on the panel's row, carried through the development save's own namespace and written to the markdown table, with no notes namespace in an ordinary save", evidence)


## The rows the panel is showing right now, through the same filter the panel
## itself uses.
func _directory_shown() -> Array[Dictionary]:
	var model := ExpoDirectory.new(app.development.layout, app.session.registry, app.session.expo_notes)
	var rows := model.entries()
	return ExpoDirectory.filter(rows, app._directory_filters, ExpoDirectory.newest_added_in(rows),
		app.session.expo_notes.last_seen_added_in())


## Horizontal distance from a position to the nearest cell of a parcel (0 when
## it stands inside it).
static func _distance_to_parcel(parcel: Dictionary, position: Vector3) -> float:
	var origin: Vector3i = parcel["origin"]
	var size: Vector3i = parcel["size"]
	var dx := maxf(maxf(float(origin.x) - position.x, position.x - float(origin.x + size.x)), 0.0)
	var dz := maxf(maxf(float(origin.z) - position.z, position.z - float(origin.z + size.z)), 0.0)
	return sqrt(dx * dx + dz * dz)


## One raw key press through the app's own handler, so the gate exercises the
## real key path and not a private call.
func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	app._unhandled_input(event)


## T234V (=visual). The Directory open over the running world with a search
## typed into it, so the rows, their icons and their status badges can be read
## off the screenshot.
func _shoot_directory() -> void:
	if not await _walk_to_district("construction_yard"):
		return
	app._open_directory()
	if app.state != CraftAndDefendApp.AppState.DIRECTORY:
		_record("T234V_DIRECTORY_VIEW", false, "the Expo Directory panel open with results listed", {"state": app.state})
		return
	app.session.expo_notes.add_note(DIRECTORY_SEARCH_EXHIBIT, NOTES_FIRST_REMARK, "broken", "Wall Kit", "exhibit")
	app.directory_search.text = "rail"
	app._on_directory_search_changed("rail")
	for _frame in range(30):
		await get_tree().process_frame
	var path := app.data_root.path_join("development-expo-directory.png")
	var shot := await _save_viewport(path)
	_record("T234V_DIRECTORY_VIEW", shot, "rendered evidence of the Expo Directory: the search field, the district / category / status filters and the icon-first rows with their status badges", {"path": path, "rows": app.directory_list.get_child_count()})
	app._close_directory()
