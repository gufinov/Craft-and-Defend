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
	if not await _wait_built("plaza"):
		return
	await _test_plaza_and_day_one()
	_test_supply_depot()
	await _test_mountain()
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
	await _shoot_supply_row()
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
	if not await _wait_built("supply depot"):
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
