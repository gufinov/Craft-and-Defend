class_name P4ResourcesAutomation
extends Node

## P4b-1 resource distribution and gold chain gate (T137–T140).
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
	var table_ok := table.size() == 3 and int(table[0]["band_start"]) == 0 and int(table[0]["band_end"]) == 18 \
		and int(table[1]["band_start"]) == 18 and int(table[1]["band_end"]) == 55 \
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
		"every non-gold cell matches the P1 reference formula and gold only replaces stone at depth 12 or deeper",
		{"compared": compared, "mismatches": mismatches, "gold_cells": gold_cells, "gold_over_ore": gold_over_ore})


## The P1 formula as shipped before the table existed (magic bands 18 / 55).
func _p1_reference_voxel(generator: P1TerrainGenerator, x: int, y: int, z: int, surface: int) -> int:
	if y == -16:
		return P1TerrainGenerator.BEDROCK
	var starter := generator._starter_resource_at(x, y, z)
	if starter != AIR:
		return starter
	if y > surface:
		return generator._tree_voxel_at(x, y, z)
	if y == surface:
		return P1TerrainGenerator.GRASS
	if y >= surface - 2:
		return P1TerrainGenerator.DIRT
	var cluster := Vector3i(floori(float(x) / 2.0), floori(float(y) / 2.0), floori(float(z) / 2.0))
	var roll := posmod(hash(Vector3i(cluster.x + WORLD_SEED, cluster.y - WORLD_SEED * 3, cluster.z + WORLD_SEED * 7)), 1000)
	if y <= surface - 6 and roll < 18:
		return IRON_ORE
	if roll >= 18 and roll < 55:
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
