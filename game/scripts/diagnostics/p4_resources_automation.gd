class_name P4ResourcesAutomation
extends Node

## P4b-1 resource distribution and gold chain gate (T137–T140), plus the
## industry miner (T193, docs/INDUSTRY.md).
## See docs/P4B_RESOURCE_DISTRIBUTION.md for the contract under test.

const GOLD_ORE := P1TerrainGenerator.GOLD_ORE
const IRON_ORE := P1TerrainGenerator.IRON_ORE
const COAL_ORE := P1TerrainGenerator.COAL_ORE
const STONE := P1TerrainGenerator.STONE
const AIR := P1TerrainGenerator.AIR
const WORLD_SEED := 41026

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"gate":
			await _run_gate()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p4_resources_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P4_RESOURCES_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P4_RESOURCES_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	_test_depth_bands()
	_test_p1_layout_preserved()
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	_test_gold_mining()
	_test_gold_smelting()
	await _test_miner()


## T137: sampled columns across the world obey the depth bands and rarity order
## of the ore table, deterministically per seed.
func _test_depth_bands() -> void:
	var config := _read_json("res://data/world.json")
	var terrain_settings: Dictionary = config.get("terrain", {})
	var first := P1TerrainGenerator.new(WORLD_SEED, terrain_settings)
	var second := P1TerrainGenerator.new(WORLD_SEED, terrain_settings)
	var other_seed := P1TerrainGenerator.new(WORLD_SEED + 1, terrain_settings)
	var table := first.ore_table()
	var min_depth := {}
	for row in table:
		min_depth[int(row["voxel_id"])] = int(row["min_depth"])
	var counts := {COAL_ORE: 0, IRON_ORE: 0, GOLD_ORE: 0}
	var shallowest := {COAL_ORE: 999, IRON_ORE: 999, GOLD_ORE: 999}
	var deepest := {COAL_ORE: 0, IRON_ORE: 0, GOLD_ORE: 0}
	var deterministic := true
	var differs_by_seed := false
	var sampled := 0
	var band_violations := 0
	for z in range(-62, 63, 3):
		for x in range(-30, 31, 3):
			var surface := first.surface_height(x, z)
			for y in range(-15, surface - 2):
				if first._starter_resource_at(x, y, z) != AIR:
					continue  # the guaranteed starter veins are fixtures, not distribution
				var voxel := first.sample_voxel(x, y, z, surface)
				deterministic = deterministic and voxel == second.sample_voxel(x, y, z, surface)
				differs_by_seed = differs_by_seed or voxel != other_seed.sample_voxel(x, y, z, other_seed.surface_height(x, z))
				sampled += 1
				if not counts.has(voxel):
					continue
				var depth := surface - y
				counts[voxel] = int(counts[voxel]) + 1
				shallowest[voxel] = mini(int(shallowest[voxel]), depth)
				deepest[voxel] = maxi(int(deepest[voxel]), depth)
				if depth < int(min_depth.get(voxel, 0)):
					band_violations += 1
	var coal := int(counts[COAL_ORE])
	var iron := int(counts[IRON_ORE])
	var gold := int(counts[GOLD_ORE])
	var coal_shallow := int(shallowest[COAL_ORE]) < 6
	var iron_band := int(shallowest[IRON_ORE]) >= 6
	var gold_band := int(shallowest[GOLD_ORE]) >= 12
	var rarity_order := gold > 0 and gold < iron and iron < coal
	var table_ok := table.size() == 3 and int(table[0]["band_start"]) == 0 and int(table[0]["band_end"]) == 32 \
		and int(table[1]["band_start"]) == 32 and int(table[1]["band_end"]) == 92 \
		and int(table[2]["voxel_id"]) == GOLD_ORE and int(table[2]["band_end"]) < 1000
	_record("T137_ORE_DEPTH_BANDS", deterministic and differs_by_seed and band_violations == 0 and coal_shallow and iron_band and gold_band and rarity_order and table_ok,
		"sampled columns show coal above depth 6, iron only from depth 6, gold only from depth 12, gold rarer than iron rarer than coal, identical per seed and different for another seed",
		{"sampled": sampled, "coal": coal, "iron": iron, "gold": gold, "shallowest": shallowest, "deepest": deepest, "band_violations": band_violations, "deterministic": deterministic, "differs_by_seed": differs_by_seed, "table": table})


## T138: the table reproduces the terrain_p1_1 coal/iron layout cell for cell
## (iron roll [0,18) from depth 6, coal roll [18,55) from depth 3) and only adds
## gold where P1 produced stone, so existing saves keep their generator version.
func _test_p1_layout_preserved() -> void:
	var config := _read_json("res://data/world.json")
	var generator := P1TerrainGenerator.new(WORLD_SEED, config.get("terrain", {}))
	var mismatches := 0
	var gold_over_ore := 0
	var gold_cells := 0
	var compared := 0
	for z in range(-63, 64, 2):
		for x in range(-31, 32, 2):
			var surface := generator.surface_height(x, z)
			for y in range(-15, surface - 2):
				var actual := generator.sample_voxel(x, y, z, surface)
				var reference := _p1_reference_voxel(generator, x, y, z, surface)
				compared += 1
				if actual == GOLD_ORE:
					gold_cells += 1
					if reference != STONE or surface - y < 12:
						gold_over_ore += 1
				elif actual != reference:
					mismatches += 1
	_record("T138_P1_LAYOUT_PRESERVED", compared > 0 and mismatches == 0 and gold_over_ore == 0 and gold_cells > 0,
		"every non-gold cell below the soil matches the reference band formula and gold only replaces stone at depth 12 or deeper",
		{"compared": compared, "mismatches": mismatches, "gold_cells": gold_cells, "gold_over_ore": gold_over_ore})


## The layout formula the table must reproduce (P4E bands 32 / 92; the
## surface and soil cells are the generator's own since surface ore landed).
func _p1_reference_voxel(generator: P1TerrainGenerator, x: int, y: int, z: int, surface: int) -> int:
	if y == -16:
		return P1TerrainGenerator.BEDROCK
	var starter := generator._starter_resource_at(x, y, z)
	if starter != AIR:
		return starter
	if y > surface:
		return generator._tree_voxel_at(x, y, z)
	if y == surface:
		return generator.sample_voxel(x, y, z, surface)
	if y >= surface - 2:
		return generator.sample_voxel(x, y, z, surface)
	var cluster := Vector3i(floori(float(x) / 2.0), floori(float(y) / 2.0), floori(float(z) / 2.0))
	var roll := posmod(hash(Vector3i(cluster.x + WORLD_SEED, cluster.y - WORLD_SEED * 3, cluster.z + WORLD_SEED * 7)), 1000)
	# P4E bands: iron [0,32) from depth 6, coal [32,92) from depth 3.
	if y <= surface - 6 and roll < 32:
		return IRON_ORE
	if roll >= 32 and roll < 92:
		return COAL_ORE
	return STONE


## T139: gold ore refuses the Stone Pick, yields one Gold Ore item to the Iron
## Pick, and the loaded terrain around the clearing really contains gold.
func _test_gold_mining() -> void:
	var inventory := app.session.inventory
	var interaction := app.session.interaction
	inventory.try_transaction({}, {"stone_pick": 1, "iron_pick": 1})
	var generated_gold: Array = []
	var loaded_cells := 0
	for z in range(31, 50):
		for x in range(-12, 13):
			for y in range(-15, -12):
				var query := app.session.world.query_cell(Vector3i(x, y, z))
				if query.get("state") != "LOADED":
					continue
				loaded_cells += 1
				if int(query.get("voxel_id", 0)) == GOLD_ORE:
					generated_gold.append([x, y, z])
	var target := Vector3i(0, -14, 40)
	var used_generated := false
	if not generated_gold.is_empty():
		var found: Array = generated_gold[0]
		target = Vector3i(int(found[0]), int(found[1]), int(found[2]))
		used_generated = true
	else:
		app.session.world.set_cell(target, GOLD_ORE)
	var before_query := app.session.world.query_cell(target)
	_select_item("stone_pick")
	var wrong_tool := interaction.try_break_cell(target)
	var gold_before := inventory.count("gold_ore")
	_select_item("iron_pick")
	var mined := interaction.try_break_cell(target)
	var gold_after := inventory.count("gold_ore")
	var after_query := app.session.world.query_cell(target)
	var block := app.session.registry.block_for_voxel(GOLD_ORE)
	var content_ok := str(block.get("id", "")) == "gold_ore" and str(block.get("drop", "")) == "gold_ore" and int(block.get("min_pick_tier", 0)) == 3 \
		and app.session.registry.max_stack("gold_ore") == 64 and app.session.registry.max_stack("gold_ingot") == 64 \
		and app.session.registry.display_name("gold_ore") == "Gold Ore" and WorldAdapter.BLOCK_NAMES[GOLD_ORE] == "gold_ore" \
		and ResourceLoader.exists("res://assets/blocks/gold_ore.svg")
	var icons_ok := ItemIconCatalog.is_measured("gold_ore") and ItemIconCatalog.is_measured("gold_ingot") \
		and ItemIconCatalog.atlas_key_for("gold_ore") == "gold" and ItemIconCatalog.texture_for("gold_ingot") != null
	_record("T139_GOLD_MINING", int(before_query.get("voxel_id", 0)) == GOLD_ORE and str(wrong_tool.get("reason", "")) == "WRONG_TOOL" and mined.get("ok", false) \
		and gold_after == gold_before + 1 and int(after_query.get("voxel_id", -1)) == AIR and content_ok and icons_ok and loaded_cells > 0,
		"a Gold Ore cell refuses the Stone Pick, breaks under the Iron Pick into one Gold Ore item, and the block, item, texture and icons are registered",
		{"target": [target.x, target.y, target.z], "used_generated_cell": used_generated, "generated_gold_near_clearing": generated_gold.size(), "loaded_cells_scanned": loaded_cells, "wrong_tool": wrong_tool, "mined": mined, "content_ok": content_ok, "icons_ok": icons_ok})


## T140: a Furnace turns Gold Ore + Coal into Gold Ingots through the ordinary
## auto-processing path, one item per recipe duration.
func _test_gold_smelting() -> void:
	var inventory := F0Inventory.new(app.session.registry)
	inventory.try_transaction({}, {"furnace": 1, "gold_ore": 2, "coal": 1})
	var service := WorkstationService.new(app.session.registry, inventory)
	var placed := service.try_place("furnace", Vector3i.ZERO, _fixture_world_query, AABB(Vector3(100.0, 100.0, 100.0), Vector3.ONE))
	var furnace_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var ore_moved := service.try_transfer_inventory_stack_to_furnace(furnace_id, _slot_for(inventory, "gold_ore"))
	var coal_moved := service.try_transfer_inventory_stack_to_furnace(furnace_id, _slot_for(inventory, "coal"))
	var recipe := app.session.registry.recipe("gold_ingot")
	var duration := float(recipe.get("duration_seconds", 0.0))
	service.advance(0.01, false)
	var started := service.furnace_job_status(furnace_id)
	service.advance(duration * 0.5, false)
	var halfway := service.furnace_slots(furnace_id)
	service.advance(duration * 1.5 + 0.1, false)
	var finished := service.furnace_slots(furnace_id)
	var idle := not bool(service.furnace_job_status(furnace_id).get("active", false))
	var collected := service.try_collect_furnace_stack(furnace_id, "output")
	var recipe_ok := str(recipe.get("station", "")) == "furnace" and int(recipe.get("inputs", {}).get("gold_ore", 0)) == 1 \
		and int(recipe.get("inputs", {}).get("coal", 0)) == 1 and int(recipe.get("outputs", {}).get("gold_ingot", 0)) == 1 and duration > 0.0 \
		and service.furnace_recipe_for_input("gold_ore") == "gold_ingot"
	var ok: bool = bool(placed.get("ok", false)) and bool(ore_moved.get("ok", false)) and bool(coal_moved.get("ok", false)) and recipe_ok \
		and bool(started.get("active", false)) and str(started.get("recipe_id", "")) == "gold_ingot" \
		and int(halfway.get("output", {}).get("count", 0)) == 0 \
		and str(finished.get("output", {}).get("item_id", "")) == "gold_ingot" and int(finished.get("output", {}).get("count", 0)) == 2 \
		and int(finished.get("input", {}).get("count", 0)) == 0 and idle and bool(collected.get("ok", false)) and inventory.count("gold_ingot") == 2
	_record("T140_GOLD_SMELTING", ok, "two Gold Ore and one Coal auto-start the gold_ingot recipe and yield two collectable Gold Ingots after two recipe durations",
		{"placed": placed.get("ok", false), "started": started, "halfway": halfway, "finished": finished, "idle": idle, "collected": collected, "recipe_ok": recipe_ok, "duration": duration})


## T193: on a levelled plate a miner beside an ore bin drills three iron ore
## voxels within radius 3 into the bin, one per MINER_SECONDS; the voxels
## become stone; with no ore left it idles ("no ore"); a bin-less miner
## reports "no bin"; a save round-trip keeps the bin contents and the count.
func _test_miner() -> void:
	var session := app.session
	var ws := session.workstations
	var world := session.world
	var miners: MinerService = session.miner_service
	var origin := Vector3i(18, 0, 30)
	var loaded := await _wait_levelled(origin + Vector3i(-6, 0, -6), 14, 14, 6)
	if not loaded or miners == null:
		_record("T193_MINER", false, "the miner fixture plate is loaded", {"loaded": loaded, "service": miners != null})
		return
	# Three iron ore voxels in the plate within radius 3 of the miner (one
	# level down), a fourth well outside it, and a stone cell in between.
	var ores: Array[Vector3i] = [origin + Vector3i(2, -1, 0), origin + Vector3i(-2, -1, 1), origin + Vector3i(0, -1, 3)]
	for cell: Vector3i in ores:
		world.set_cell(cell, IRON_ORE)
	var far_ore := origin + Vector3i(5, -1, 0)
	world.set_cell(far_ore, IRON_ORE)
	session.inventory.try_transaction({}, {"miner": 2, "ore_bin": 1})
	var placed_miner := ws.try_place("miner", origin, world.query_cell, AABB(Vector3(100.0, 100.0, 100.0), Vector3.ONE))
	var miner_id := str(placed_miner.get("details", {}).get("station", {}).get("instance_id", ""))
	var placed_bin := ws.try_place("ore_bin", origin + Vector3i(1, 0, 0), world.query_cell, AABB(Vector3(100.0, 100.0, 100.0), Vector3.ONE))
	var bin_id := str(placed_bin.get("details", {}).get("station", {}).get("instance_id", ""))
	var content_ok := ws.station_type(miner_id) == "miner" and ws.is_container(bin_id) and ws.container_slots(bin_id).size() == 9 \
		and str(session.registry.recipe("miner").get("station", "")) == "workbench" and int(session.registry.recipe("miner").get("recipe_book_order", 0)) == 214 \
		and int(session.registry.recipe("ore_bin").get("recipe_book_order", 0)) == 215 \
		and ItemIconCatalog.is_measured("miner") and ItemIconCatalog.is_measured("ore_bin")
	var visuals_ok := session._station_visuals.has(miner_id) and session._station_visuals[miner_id].get_node_or_null("Drill") != null \
		and session._station_visuals.has(bin_id) and session._station_visuals[bin_id].get_node_or_null("OreHeap") != null
	# Nothing happens before the first tick.
	miners.advance(MinerService.MINER_SECONDS * 0.5, false)
	var early := ws.container_count(bin_id, "iron_ore")
	var counts: Array[int] = []
	var statuses: Array[String] = []
	for _tick in range(3):
		miners.advance(MinerService.MINER_SECONDS + 0.1, false)
		counts.append(ws.container_count(bin_id, "iron_ore"))
		statuses.append(str(miners.miner_state(miner_id).get("status", "")))
	var ores_stone := true
	for cell: Vector3i in ores:
		if int(world.query_cell(cell).get("voxel_id", -1)) != STONE:
			ores_stone = false
	var far_kept := int(world.query_cell(far_ore).get("voxel_id", -1)) == IRON_ORE
	var mined_three := int(miners.miner_state(miner_id).get("mined", 0)) == 3
	var drilling := statuses.size() == 3 and statuses[0].begins_with("drilling iron ore") and statuses[2].begins_with("drilling iron ore")
	# Fourth tick: no ore left in range, nothing changes.
	miners.advance(MinerService.MINER_SECONDS + 0.1, false)
	var after_fourth := ws.container_count(bin_id, "iron_ore")
	var no_ore := str(miners.miner_state(miner_id).get("status", "")) == MinerService.STATUS_NO_ORE
	var status_line := session.miner_status_line(miner_id)
	var bin_body: Node = session._station_visuals[bin_id]
	var heap_shown: bool = bin_body.get_node("OreHeap").get_child_count() > 0
	# A bin-less miner beside ore reports "no bin" and leaves the ore alone.
	var lone := origin + Vector3i(0, 0, -5)
	var lone_ore := lone + Vector3i(1, -1, 0)
	world.set_cell(lone_ore, IRON_ORE)
	var placed_lone := ws.try_place("miner", lone, world.query_cell, AABB(Vector3(100.0, 100.0, 100.0), Vector3.ONE))
	var lone_id := str(placed_lone.get("details", {}).get("station", {}).get("instance_id", ""))
	miners.advance(MinerService.MINER_SECONDS + 0.1, false)
	var no_bin := str(miners.miner_state(lone_id).get("status", "")) == MinerService.STATUS_NO_BIN and int(world.query_cell(lone_ore).get("voxel_id", -1)) == IRON_ORE
	var no_bin_line := session.miner_status_line(lone_id)
	# Save round-trip (JSON, as the save file does) keeps the bin and the counter.
	var saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored_ws := WorkstationService.new(session.registry, F0Inventory.new(session.registry))
	var restored := restored_ws.restore(saved, world.query_cell) if saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var restored_miner: Dictionary = restored_ws.station(miner_id).get("miner", {})
	var round_trip: bool = restored.get("ok", false) and restored_ws.container_count(bin_id, "iron_ore") == 3 \
		and int(restored_miner.get("mined", 0)) == 3 and str(restored_miner.get("status", "")) == MinerService.STATUS_NO_ORE \
		and restored_ws.container_slots(bin_id).size() == 9
	var ok: bool = bool(placed_miner.get("ok", false)) and bool(placed_bin.get("ok", false)) and content_ok and visuals_ok and early == 0 \
		and counts == ([1, 2, 3] as Array[int]) and ores_stone and far_kept and mined_three and drilling and after_fourth == 3 and no_ore \
		and status_line.begins_with("Miner: 3 ore mined, no ore.") and heap_shown and bool(placed_lone.get("ok", false)) and no_bin \
		and no_bin_line.begins_with("Miner: 0 ore mined, no bin.") and round_trip
	_record("T193_MINER", ok, "a miner beside an ore bin drills the three iron ore voxels within radius 3 into the bin one per MINER_SECONDS (the voxels become stone, the far ore stays), then idles with 'no ore'; a bin-less miner reports 'no bin'; the status lines read as documented; a save round-trip keeps the bin's three ore and the miner's count",
		{"placed_miner": placed_miner.get("reason"), "placed_bin": placed_bin.get("reason"), "content_ok": content_ok, "visuals_ok": visuals_ok, "early": early, "counts": counts, "statuses": statuses, "ores_stone": ores_stone, "far_kept": far_kept, "mined_three": mined_three, "after_fourth": after_fourth, "no_ore": no_ore, "status_line": status_line, "heap_shown": heap_shown, "no_bin": no_bin, "no_bin_line": no_bin_line, "round_trip": round_trip, "restored": restored.get("reason")})


## Levels a stone plate (top at y -1, air above) and waits until it is
## editable; terrain streams in over a few seconds.
func _wait_levelled(origin: Vector3i, width: int, depth: int, height: int) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var clear := true
		for x in range(width):
			for z in range(depth):
				app.session.world.set_cell(origin + Vector3i(x, -1, z), STONE)
				for y in range(height):
					app.session.world.set_cell(origin + Vector3i(x, y, z), AIR)
				var plate := app.session.world.query_cell(origin + Vector3i(x, -1, z))
				if plate.get("state") != "LOADED" or int(plate.get("voxel_id", 0)) != STONE:
					clear = false
		if clear:
			return true
		await get_tree().process_frame
	return false


func _fixture_world_query(cell: Vector3i) -> Dictionary:
	return {"state": "LOADED", "voxel_id": 1 if cell.y < 0 else 0}


func _slot_for(inventory: F0Inventory, item_id: String) -> int:
	for index in range(F0Inventory.SLOT_COUNT):
		if str(inventory.slots[index].get("item_id", "")) == item_id:
			return index
	return -1


func _select_item(item_id: String) -> void:
	for index in range(F0Inventory.HOTBAR_COUNT):
		if str(app.session.inventory.slots[index].get("item_id", "")) == item_id:
			app.session.inventory.select_hotbar(index)
			return
	failures.append("Hotbar item not found: " + item_id)


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
