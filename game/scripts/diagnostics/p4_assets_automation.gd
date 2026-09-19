class_name P4AssetsAutomation
extends Node

## P4G Core of Power and light sources: the asset attribute sheet in content,
## placement of every new entity with its OmniLight3D, and one rendered view.
## Runs with `--p4-assets-automation=gate` (headless) and
## `--p4-assets-automation=visual` (needs a window; renders one PNG).

const ASSET_IDS: Array[String] = [
	"core_of_power", "enemy_core", "torch", "wall_lantern", "post_lantern", "campfire",
	"light_block_blue", "light_block_red",
]
const CRAFTABLE_IDS: Array[String] = [
	"torch", "wall_lantern", "post_lantern", "campfire", "light_block_blue", "light_block_red", "core_of_power",
]
const ATTRIBUTE_KEYS: Array[String] = ["value", "role", "light", "mount", "space", "notes"]
const LIGHT_KEYS: Array[String] = ["color", "energy", "range", "flicker"]

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
	_write_json(app.data_root.path_join("p4_assets_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P4_ASSETS_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P4_ASSETS_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var registry := app.session.registry
	var ws := app.session.workstations
	var world := app.session.world

	# T148 asset attributes: every new entity carries the attribute sheet
	# (value, role, light, mount, space, notes) with a light, a visual ghost,
	# navigation and defense; the craftable ones resolve to a workbench recipe
	# in book order; the enemy core is hidden from the book; icons resolve.
	var attribute_problems: Array[String] = []
	var attribute_values: Dictionary = {}
	for entity_id in ASSET_IDS:
		var definition := registry.entity(entity_id)
		var attributes := registry.entity_attributes(entity_id)
		var complete := not attributes.is_empty()
		for key in ATTRIBUTE_KEYS:
			complete = complete and attributes.has(key)
		var light_value: Variant = attributes.get("light", null)
		var light_ok := light_value is Dictionary
		if light_ok:
			var light_definition: Dictionary = light_value
			for key in LIGHT_KEYS:
				light_ok = light_ok and light_definition.has(key)
			light_ok = light_ok and float(light_definition.get("energy", 0.0)) > 0.0 and float(light_definition.get("range", 0.0)) > 0.0
		var parts: Array = definition.get("visual", {}).get("parts", [])
		var defense: Dictionary = definition.get("defense", {})
		var navigation: Dictionary = definition.get("navigation", {})
		var item := registry.item(entity_id)
		var ok := complete and light_ok and not parts.is_empty() and int(defense.get("max_integrity", 0)) > 0 and int(navigation.get("integrity", 0)) == int(defense.get("max_integrity", -1)) and str(item.get("places_entity", "")) == entity_id
		if not ok:
			attribute_problems.append(entity_id)
		attribute_values[entity_id] = {"value": attributes.get("value"), "role": attributes.get("role"), "mount": attributes.get("mount"), "space": attributes.get("space"), "light": light_value, "integrity": defense.get("max_integrity")}
	var recipe_problems: Array[String] = []
	var previous_order := 196
	for recipe_id in CRAFTABLE_IDS:
		var recipe := registry.recipe(recipe_id)
		var order := int(recipe.get("recipe_book_order", -1))
		if recipe.is_empty() or str(recipe.get("station", "")) != "workbench" or not recipe.get("outputs", {}).has(recipe_id) or order <= previous_order:
			recipe_problems.append(recipe_id)
		previous_order = order
	var enemy_hidden := registry.is_hidden_item("enemy_core") and registry.recipe("enemy_core").is_empty()
	var book_ids: Array[String] = []
	for recipe in app.session.recipes_for("workbench"):
		book_ids.append(str(recipe.get("id", "")))
	var missing_icons := ItemIconCatalog.missing_item_ids(ASSET_IDS)
	var core_attributes := registry.entity_attributes("core_of_power")
	var core_ok: bool = str(core_attributes.get("role", "")) == "core" and int(core_attributes.get("value", 0)) == 500 and str(core_attributes.get("mount", "")) == "ground" and _space_of(core_attributes) == Vector3i(3, 4, 3) and str(core_attributes.get("light", {}).get("color", "")) == "4c9dff" and registry.entity("core_of_power").get("occupied_offsets", []).size() == 12
	var enemy_attributes := registry.entity_attributes("enemy_core")
	var enemy_ok: bool = str(enemy_attributes.get("light", {}).get("color", "")) == "ff3030" and int(enemy_attributes.get("value", -1)) == 0 and int(registry.entity("enemy_core").get("defense", {}).get("max_integrity", 0)) == 400
	var torch_attributes := registry.entity_attributes("torch")
	var torch_ok: bool = bool(torch_attributes.get("light", {}).get("flicker", false)) and bool(registry.entity_attributes("campfire").get("light", {}).get("flicker", false)) and not bool(registry.entity_attributes("wall_lantern").get("light", {}).get("flicker", true))
	_record("T148_ASSET_ATTRIBUTES", attribute_problems.is_empty() and recipe_problems.is_empty() and enemy_hidden and not book_ids.has("enemy_core") and book_ids.has("core_of_power") and book_ids.has("torch") and missing_icons.is_empty() and core_ok and enemy_ok and torch_ok, "every core and light entity carries value/role/light/mount/space/notes with a light, a ghost visual, navigation and defense; the seven craftable ones are workbench recipes ordered after the chest; the enemy core is hidden from the book; all eight icons resolve", {"attribute_problems": attribute_problems, "recipe_problems": recipe_problems, "enemy_hidden": enemy_hidden, "book_ids": book_ids, "missing_icons": missing_icons, "core_ok": core_ok, "enemy_ok": enemy_ok, "torch_ok": torch_ok, "attributes": attribute_values})

	# T149 placement and light: each entity placed on levelled ground gets a
	# visual body with an OmniLight3D of its attribute colour; the core's
	# 3×3 base plus centre column is occupied; defense_status reports the
	# integrity; a torch over air is refused and a torch on a light block
	# (any solid top) is accepted; the torch light flickers.
	var origin := Vector3i(-6, 0, 36)
	_level_ground(origin + Vector3i(-3, 0, -3), 20, 14)
	app.session.inventory.try_transaction({}, {"core_of_power": 1, "enemy_core": 1, "torch": 2, "wall_lantern": 1, "post_lantern": 1, "campfire": 1, "light_block_blue": 1, "light_block_red": 1})
	var anchors := {
		"core_of_power": origin + Vector3i(0, 0, 0),
		"enemy_core": origin + Vector3i(5, 0, 0),
		"campfire": origin + Vector3i(10, 0, 0),
		"post_lantern": origin + Vector3i(0, 0, 6),
		"wall_lantern": origin + Vector3i(2, 0, 6),
		"torch": origin + Vector3i(4, 0, 6),
		"light_block_blue": origin + Vector3i(6, 0, 6),
		"light_block_red": origin + Vector3i(8, 0, 6),
	}
	# The wall lantern is wall-mounted (owner 2026-09-19): a castle-stone post
	# beside its cell.
	world.set_cell(origin + Vector3i(1, 0, 6), 8)
	var placements: Dictionary = {}
	var placement_reasons: Dictionary = {}
	var light_problems: Array[String] = []
	var mesh_counts: Dictionary = {}
	for entity_id: String in anchors.keys():
		var placed := ws.try_place(entity_id, anchors[entity_id], world.query_cell, AABB(), 0)
		placement_reasons[entity_id] = placed.get("reason")
		if not placed.get("ok", false):
			light_problems.append(entity_id + ":not_placed")
			continue
		var instance_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
		placements[entity_id] = instance_id
		var body: Node3D = app.session._station_visuals.get(instance_id)
		if body == null:
			light_problems.append(entity_id + ":no_body")
			continue
		mesh_counts[entity_id] = body.find_children("*", "MeshInstance3D", true, false).size()
		var lights := body.find_children("*", "OmniLight3D", true, false)
		var expected_light: Dictionary = registry.entity_attributes(entity_id).get("light", {})
		if lights.size() != 1:
			light_problems.append(entity_id + ":lights=%d" % lights.size())
			continue
		var light: OmniLight3D = lights[0]
		var expected_color := Color(str(expected_light.get("color", "")))
		if not light.light_color.is_equal_approx(expected_color) or not is_equal_approx(light.omni_range, float(expected_light.get("range", 0.0))) or light.name != GameSession.ENTITY_LIGHT_NAME:
			light_problems.append(entity_id + ":light_mismatch")
	var core_id := str(placements.get("core_of_power", ""))
	var core_cells_ok := not core_id.is_empty()
	for offset in registry.entity("core_of_power").get("occupied_offsets", []):
		var cell: Vector3i = anchors["core_of_power"] + Vector3i(int(offset[0]), int(offset[1]), int(offset[2]))
		core_cells_ok = core_cells_ok and ws.station_at_cell(cell) == core_id
	var column_only := ws.station_at_cell(anchors["core_of_power"] + Vector3i(0, 1, 0)).is_empty() and ws.station_at_cell(anchors["core_of_power"] + Vector3i(1, 3, 1)) == core_id and ws.station_at_cell(anchors["core_of_power"] + Vector3i(1, 4, 1)).is_empty()
	var core_status := ws.defense_status(core_id)
	var enemy_status := ws.defense_status(str(placements.get("enemy_core", "")))
	var torch_status := ws.defense_status(str(placements.get("torch", "")))
	var core_integrity := int(core_status.get("details", {}).get("integrity", -1))
	var enemy_integrity := int(enemy_status.get("details", {}).get("integrity", -1))
	var torch_integrity := int(torch_status.get("details", {}).get("integrity", -1))
	var floating_torch := ws.try_place("torch", origin + Vector3i(4, 2, 8), world.query_cell, AABB(), 0)
	var stacked_torch := ws.try_place("torch", anchors["light_block_blue"] + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var torch_body: Node3D = app.session._station_visuals.get(str(placements.get("torch", "")))
	var torch_light: OmniLight3D = torch_body.find_child(GameSession.ENTITY_LIGHT_NAME, true, false) if torch_body != null else null
	var torch_base_energy := float(registry.entity_attributes("torch").get("light", {}).get("energy", 0.0))
	var energies: Array[float] = []
	for _sample in range(6):
		await get_tree().create_timer(0.08).timeout
		if torch_light != null:
			energies.append(torch_light.light_energy)
	var flickers := false
	for energy in energies:
		flickers = flickers or not is_equal_approx(energy, torch_base_energy)
	var lantern_body: Node3D = app.session._station_visuals.get(str(placements.get("wall_lantern", "")))
	var lantern_light: OmniLight3D = lantern_body.find_child(GameSession.ENTITY_LIGHT_NAME, true, false) if lantern_body != null else null
	var lantern_steady := lantern_light != null and is_equal_approx(lantern_light.light_energy, float(registry.entity_attributes("wall_lantern").get("light", {}).get("energy", 0.0)))
	_record("T149_ASSET_PLACEMENT_AND_LIGHT", placements.size() == 8 and light_problems.is_empty() and core_cells_ok and column_only and core_integrity == 240 and enemy_integrity == 400 and torch_integrity == 4 and not floating_torch.get("ok", false) and str(floating_torch.get("reason", "")) in ["UNSUPPORTED", "INVALID_MOUNT"] and stacked_torch.get("ok", false) and flickers and lantern_steady, "all eight entities place on levelled ground with one EntityLight OmniLight3D of the attribute colour and range each; the core occupies its 3×3 base and centre column only; defense_status reports 240 / 400 / 4; a torch over air is refused and a torch on a light block places; the torch light flickers while the lantern holds steady", {"placements": placement_reasons, "light_problems": light_problems, "mesh_counts": mesh_counts, "core_cells_ok": core_cells_ok, "column_only": column_only, "core_integrity": core_integrity, "enemy_integrity": enemy_integrity, "torch_integrity": torch_integrity, "floating_torch": floating_torch.get("reason"), "stacked_torch": stacked_torch.get("reason"), "torch_energies": energies, "lantern_steady": lantern_steady})


## Rendered evidence: both cores, the campfire, the post and wall lanterns,
## the torch and both light blocks in one evening 1280x720 view.
func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var player := app.session.player
	player.deactivate()
	var ws := app.session.workstations
	var world := app.session.world
	var origin := Vector3i(-6, 0, 36)
	_level_ground(origin + Vector3i(-4, 0, -4), 22, 16)
	app.session.inventory.try_transaction({}, {"core_of_power": 1, "enemy_core": 1, "torch": 1, "wall_lantern": 1, "post_lantern": 1, "campfire": 1, "light_block_blue": 1, "light_block_red": 1})
	var placements := {
		"core_of_power": ws.try_place("core_of_power", origin + Vector3i(0, 0, 4), world.query_cell, AABB(), 0),
		"enemy_core": ws.try_place("enemy_core", origin + Vector3i(10, 0, 4), world.query_cell, AABB(), 0),
		"campfire": ws.try_place("campfire", origin + Vector3i(5, 0, 5), world.query_cell, AABB(), 0),
		"post_lantern": ws.try_place("post_lantern", origin + Vector3i(4, 0, 1), world.query_cell, AABB(), 0),
		"wall_lantern": _place_wall_lantern(ws, world, origin + Vector3i(6, 0, 1)),
		"torch": ws.try_place("torch", origin + Vector3i(8, 0, 1), world.query_cell, AABB(), 0),
		"light_block_blue": ws.try_place("light_block_blue", origin + Vector3i(2, 0, 1), world.query_cell, AABB(), 0),
		"light_block_red": ws.try_place("light_block_red", origin + Vector3i(10, 0, 1), world.query_cell, AABB(), 0),
	}
	var all_placed := true
	for key in placements:
		all_placed = all_placed and bool(placements[key].get("ok", false))
	var evening := app.session.apply_world_settings("2030", false)
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(origin) + Vector3(6.5, 2.6, -3.6)
	player.look_at(Vector3(origin) + Vector3(6.5, 1.0, 4.0), Vector3.UP)
	player.camera.rotation.x = -0.10
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("p4-assets.png")
	if image == null:
		_record("T150_ASSETS_RENDERED", false, "both cores and the six light sources render in one evening 1280x720 view", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var mesh_parts := 0
	var lights := 0
	for key in placements:
		var body: Node3D = app.session._station_visuals.get(str(placements[key].get("details", {}).get("station", {}).get("instance_id", "")))
		if body != null:
			mesh_parts += body.find_children("*", "MeshInstance3D", true, false).size()
			lights += body.find_children("*", "OmniLight3D", true, false).size()
	_record("T150_ASSETS_RENDERED", all_placed and evening.get("ok", false) and error == OK and image.get_size() == Vector2i(1280, 720) and lights == 8 and mesh_parts >= 300, "the blue Core of Power, the red enemy core, the campfire, the post lantern, the wall lantern, the torch and both light blocks render with their lights in one evening 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "placed": all_placed, "evening": evening.get("period"), "mesh_parts": mesh_parts, "lights": lights})


func _space_of(attributes: Dictionary) -> Vector3i:
	var space: Array = attributes.get("space", [])
	if space.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(space[0]), int(space[1]), int(space[2]))


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


func _place_wall_lantern(ws: WorkstationService, world: WorldAdapter, cell: Vector3i) -> Dictionary:
	world.set_cell(cell + Vector3i(0, 0, 1), 8)
	return ws.try_place("wall_lantern", cell, world.query_cell, AABB(), 0)
