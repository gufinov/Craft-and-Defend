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
	if not await _wait_built("plaza", _district_owners(["central_plaza", "supply_depot", "future_expansion", "day_one", "equipment", "resources"])):
		return
	await _test_plaza_and_day_one()
	await _test_mountain()
	await _test_coaster_gallery()
	await _test_grand_coaster()
	_test_signs()
	await _settle_near_spawn()


func _run_visual() -> void:
	app._on_development_new_pressed()
	if not await _wait_ready():
		return
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
	await _shoot_coaster()
	await _settle_near_spawn()


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


## Waits until the builder has nothing left to do. With `owners` (district and
## exhibit ids, from `_district_owners`) it waits only on that district's work:
## a district on the far side of the campus is deliberately parked until
## someone walks there, so waiting on the whole queue from the plaza would
## never finish once the CoasterCraft park (card F) is built too.
func _wait_built(label: String, owners: PackedStringArray = PackedStringArray()) -> bool:
	var builder: ExpoBuilder = app.development.expo_builder
	var deadline := Time.get_ticks_msec() + BUILD_TIMEOUT_MSEC
	while _still_building(builder, owners):
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
