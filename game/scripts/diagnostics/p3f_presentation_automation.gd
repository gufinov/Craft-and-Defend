class_name P3FPresentationAutomation
extends Node

const EXPECTED_WORKBENCH_ORDER: Array[String] = [
	"planks", "sticks", "workbench", "wood_pick", "wood_axe", "stone_pick", "furnace", "castle_stone", "stone_stair", "wall_walk_slab", "parapet_merlon", "tower_platform", "gate_frame", "wood_barricade", "iron_pick", "iron_sword", "ballista_bolt", "stone_shot", "flame_shot", "cannonball", "ballista", "catapult", "turret_catapult", "turret_catapult_mk2", "cannon", "kettle", "chest", "torch", "wall_lantern", "post_lantern", "campfire", "light_block_blue", "light_block_red", "core_of_power", "coastercraft_shop",
	"miner", "ore_bin", "warehouse", "foundry",
	# Development Expo section 9 (docs/SIGNS.md): the Sign, then its wide board.
	"sign", "sign_board",
	# Defence sets (docs/DEFENSE_SETS.md): the gate leaf and the rail turret.
	"gate", "rail_turret",
	# Gates card 2 (docs/DEFENSE_SETS.md): the rest of the gate family, each
	# size with the frame built for it — 222, 223, 224 and, past the District
	# Board, 226.
	"double_gate_frame", "double_gate", "great_gate_frame",
	# Signs card 3 (docs/SIGNS.md): the District Board, three cells across (225).
	"sign_board_large",
	"great_gate",
	# Traps wave 1 (docs/TRAPS.md): the Spike Trap (229).
	"spike_trap",
]
## The CoasterCraft Shop's own book (docs/INDUSTRY_PLAN.md wave 1): the coaster
## recipes keep their workbench-era orders (194, 204-212) and live only here.
const EXPECTED_COASTERCRAFT_SHOP_ORDER: Array[String] = [
	"rail", "rail_slope", "rail_loop", "mine_cart", "coaster_car", "rail_switch", "rail_cross", "rail_curve", "rail_climb",
]
const VISUAL_ITEMS: Array[String] = [
	"wood_pick", "iron_sword", "wood_axe", "stick",
	"castle_stone", "gate_frame", "ballista", "catapult",
]

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
	_write_json(app.data_root.path_join("p3f_presentation_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3F_PRESENTATION_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3F_PRESENTATION_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	app._crafting_station_type = "workbench"
	var recipes := app._available_crafting_recipes()
	var recipe_ids: Array[String] = []
	var order_values: Array[int] = []
	for recipe in recipes:
		recipe_ids.append(str(recipe.id))
		order_values.append(int(recipe.get("recipe_book_order", -1)))
	var monotonic := true
	for index in range(1, order_values.size()):
		monotonic = monotonic and order_values[index] > order_values[index - 1]
	_record("T90_RECIPE_PROGRESSION_ORDER", recipe_ids == EXPECTED_WORKBENCH_ORDER and monotonic, "the Workbench recipe book begins with basic hand materials and tools, then advances through castle, iron and siege recipes", {"ids": recipe_ids, "orders": order_values})

	var item_ids: Array = app.session.registry.items.keys()
	item_ids.sort()
	var missing := ItemIconCatalog.missing_world_reference_item_ids(item_ids)
	var held_failures: Array[String] = []
	for value in item_ids:
		var item_id := str(value)
		app.session._held_item_view.present(item_id)
		var children := app.session._held_item_view.model_root.get_children()
		if children.size() != 1 or not children[0] is Sprite3D or children[0].texture == null:
			held_failures.append(item_id)
	var mesher := app.session.world.terrain.mesher as VoxelMesherBlocky
	var library := mesher.library as VoxelBlockyLibrary
	var block_failures: Array[String] = []
	for block_id in range(1, WorldAdapter.BLOCK_NAMES.size()):
		var model := library.get_model(block_id) as VoxelBlockyModelCube
		if model == null or model.atlas_size_in_tiles != Vector2i.ONE:
			block_failures.append(WorldAdapter.BLOCK_NAMES[block_id])
	var region_failures: Array[String] = []
	for value in item_ids:
		var item_id := str(value)
		var card_texture := ItemIconCatalog.texture_for(item_id) as AtlasTexture
		var held_texture := ItemIconCatalog.world_reference_texture_for(item_id) as AtlasTexture
		if card_texture == null or held_texture == null or not card_texture.filter_clip or not held_texture.filter_clip:
			region_failures.append(item_id)
	# P3H.4: regions are measured from the art, not the nominal grid. Every item
	# must be measured, and each measured object must sit inside its nominal cell
	# (or, for ammunition, its half) without overlapping any other measured object.
	var unmeasured: Array[String] = []
	var overlapping: Array[String] = []
	var measured_rects: Dictionary = {}
	for value in item_ids:
		var item_id := str(value)
		if not ItemIconCatalog.is_measured(item_id):
			unmeasured.append(item_id)
			continue
		measured_rects[item_id] = ItemIconCatalog.region_for(item_id)
	for a in measured_rects.keys():
		for b in measured_rects.keys():
			if a < b and ItemIconCatalog.atlas_key_for(a) == ItemIconCatalog.atlas_key_for(b) \
				and measured_rects[a].intersects(measured_rects[b]):
				overlapping.append("%s/%s" % [a, b])
	var workbench_region := ItemIconCatalog.region_for("workbench")
	var gate_region := ItemIconCatalog.region_for("gate_frame")
	var regions_isolated := unmeasured.is_empty() and overlapping.is_empty() \
		and ItemIconCatalog.region_for_index(12).encloses(workbench_region) \
		and ItemIconCatalog.region_for_index(18).encloses(gate_region)
	var atlas_texture := load(ItemIconCatalog.ATLAS_PATH) as Texture2D
	var atlas_image := atlas_texture.get_image() if atlas_texture != null else null
	var alpha_atlas_ok := atlas_image != null and not atlas_image.is_empty() \
		and atlas_image.get_format() == Image.FORMAT_RGBA8 \
		and atlas_image.get_size() == Vector2i(1536, 1024) \
		and atlas_image.get_pixel(0, 0).a <= 0.01
	var ammunition_texture := load(ItemIconCatalog.AMMUNITION_ATLAS_PATH) as Texture2D
	var ammunition_image := ammunition_texture.get_image() if ammunition_texture != null else null
	var bolt_region := ItemIconCatalog.region_for("ballista_bolt")
	var shot_region := ItemIconCatalog.region_for("stone_shot")
	var ammunition_alpha_ok := ammunition_image != null and not ammunition_image.is_empty() \
		and ammunition_image.get_format() == Image.FORMAT_RGBA8 \
		and ammunition_image.get_size() == Vector2i(1774, 887) \
		and ammunition_image.get_pixel(0, 0).a <= 0.01 \
		and ItemIconCatalog.atlas_key_for("ballista_bolt") == "ammunition" \
		and ItemIconCatalog.atlas_key_for("stone_shot") == "ammunition" \
		and not bolt_region.intersects(shot_region) \
		and shot_region.position.x > 887.0
	app.session._held_item_view.present("iron_sword")
	var presentation := app.session._held_item_view.debug_presentation()
	var sword_size: Vector2 = presentation.sprite_size
	app.session._held_item_view.present("stone_shot")
	var shot_presentation := app.session._held_item_view.debug_presentation()
	var shot_size: Vector2 = shot_presentation.sprite_size
	var hinge: Vector3 = presentation.hinge_position
	app.session._held_item_view.present("wood_axe")
	var axe_mirrored: bool = app.session._held_item_view.debug_presentation().get("mirrored", false)
	app.session._held_item_view.present("iron_sword")
	var sword_mirrored: bool = app.session._held_item_view.debug_presentation().get("mirrored", false)
	# Hinge model: hand in the lower-right, sword normalised to TOOL_HEIGHT, ammunition
	# normalised to LOW_HEIGHT (so the 887 px atlas no longer renders 3.5x too large),
	# and a swing arc broad enough to reach toward the crosshair.
	var framing_ok := bool(presentation.hinge_model) and bool(presentation.raised) \
		and hinge.x >= HeldItemView.HINGE_RIGHT_MIN - 0.001 and hinge.y < 0.0 \
		and is_equal_approx(sword_size.y, HeldItemView.TOOL_HEIGHT) \
		and is_equal_approx(shot_size.y, HeldItemView.LOW_HEIGHT) \
		and shot_size.x < 0.6 \
		and not bool(shot_presentation.raised) \
		and float(presentation.tool_swing_arc_radians) >= 1.2 \
		and not axe_mirrored and not sword_mirrored
	_record("T91_HELD_AND_BLOCK_IDENTITY", missing.is_empty() and held_failures.is_empty() and block_failures.is_empty() and region_failures.is_empty() and regions_isolated and alpha_atlas_ok and ammunition_alpha_ok and framing_ok, "all inventory and held items resolve filter-clipped true-alpha art; every item resolves a measured art region isolated from its neighbours; the held view hinges at the lower-right hand with tools and ammunition normalised to one scale and a broad swing arc; voxel cubes retain complete face textures", {"items": item_ids.size(), "missing": missing, "held_failures": held_failures, "block_failures": block_failures, "region_failures": region_failures, "unmeasured": unmeasured, "overlapping": overlapping, "workbench_region": workbench_region, "gate_region": gate_region, "bolt_region": bolt_region, "shot_region": shot_region, "alpha_atlas_ok": alpha_atlas_ok, "ammunition_alpha_ok": ammunition_alpha_ok, "presentation": presentation, "shot_presentation": shot_presentation})

	app.session.inventory.try_transaction({}, {"gate_frame": 1, "wall_walk_slab": 1})
	var gate_placed := app.session.workstations.try_place("gate_frame", Vector3i(8, 0, 40), app.session.world.query_cell, AABB(), 0)
	var slab_placed := app.session.workstations.try_place("wall_walk_slab", Vector3i(12, 0, 40), app.session.world.query_cell, AABB(), 0)
	var gate_body: Node3D = app.session._station_visuals.get(str(gate_placed.get("details", {}).get("station", {}).get("instance_id", "")))
	var slab_body: Node3D = app.session._station_visuals.get(str(slab_placed.get("details", {}).get("station", {}).get("instance_id", "")))
	var placed_skin_ok := _body_has_albedo_texture(gate_body) and _body_has_albedo_texture(slab_body)
	_record("T105_CASTLE_ENTITY_SKINS", gate_placed.get("ok", false) and slab_placed.get("ok", false) and placed_skin_ok, "placed Gate Frame and Wall Walk Slab mesh parts use the Castle Stone skin instead of flat gray material", {"gate": gate_placed, "slab": slab_placed, "gate_parts": gate_body.get_child_count() if gate_body != null else 0, "slab_parts": slab_body.get_child_count() if slab_body != null else 0, "textured": placed_skin_ok})

	# T192 CoasterCraft Shop book: the shop lists exactly the coaster recipes
	# in order, the workbench book no longer lists them (and offers the shop
	# itself); a placed shop opens the crafting modal under its own title and
	# crafts a rail there, while the workbench refuses the same recipe.
	app._crafting_station_type = "coastercraft_shop"
	var shop_ids: Array[String] = []
	var shop_orders: Array[int] = []
	for recipe in app._available_crafting_recipes():
		shop_ids.append(str(recipe.id))
		shop_orders.append(int(recipe.get("recipe_book_order", -1)))
	var shop_monotonic := true
	for index in range(1, shop_orders.size()):
		shop_monotonic = shop_monotonic and shop_orders[index] > shop_orders[index - 1]
	app._crafting_station_type = "workbench"
	var bench_ids: Array[String] = []
	for recipe in app._available_crafting_recipes():
		bench_ids.append(str(recipe.id))
	var bench_clean := bench_ids == EXPECTED_WORKBENCH_ORDER and bench_ids.has("coastercraft_shop") and bench_ids.has("kettle")
	for shop_id: String in EXPECTED_COASTERCRAFT_SHOP_ORDER:
		bench_clean = bench_clean and not bench_ids.has(shop_id)
	app._crafting_station_type = "hand"
	var shop_recipe := app.session.registry.recipe("coastercraft_shop")
	var shop_recipe_ok: bool = str(shop_recipe.get("station", "")) == "workbench" and int(shop_recipe.get("recipe_book_order", -1)) == 213 and int(shop_recipe.get("inputs", {}).get("iron_ingot", 0)) == 4 and int(shop_recipe.get("outputs", {}).get("coastercraft_shop", 0)) == 1
	var shop_entity := app.session.registry.entity("coastercraft_shop")
	var shop_entity_ok: bool = str(shop_entity.get("station_type", "")) == "coastercraft_shop" and (shop_entity.get("occupied_offsets", []) as Array).size() == 2 and int(app.session.registry.max_stack("coastercraft_shop")) == 4 and ItemIconCatalog.missing_item_ids(["coastercraft_shop"]).is_empty()
	app.session.inventory.try_transaction({}, {"coastercraft_shop": 1, "workbench": 1, "planks": 16, "iron_ingot": 8})
	var bench_placed := app.session.workstations.try_place("workbench", Vector3i(5, 0, 45), app.session.world.query_cell, AABB(), 0)
	var workbench_id := str(bench_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var shop_placed := app.session.workstations.try_place("coastercraft_shop", Vector3i(2, 0, 45), app.session.world.query_cell, AABB(), 0)
	var shop_id := str(shop_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var shop_body: Node = app.session._station_visuals.get(shop_id, null)
	var shop_visual_ok := shop_body != null and shop_body.has_node("ShopCart")
	app._show_workstation(shop_id, "coastercraft_shop")
	await _settle_frames(4)
	var shop_title := app.crafting_title_label.text
	var shop_modal_ok := app.state == app.AppState.CRAFTING and app._crafting_station_type == "coastercraft_shop" and shop_title == "COASTERCRAFT SHOP" and app.crafting_recipe_page_label.text == "Page 1 / 1"
	app._close_crafting()
	var rails_before := app.session.inventory.count("rail")
	var crafted_rail := app.session.try_craft("rail", "coastercraft_shop", shop_id)
	var rails_after := app.session.inventory.count("rail")
	var bench_refused := app.session.try_craft("rail", "workbench", workbench_id)
	var craft_ok: bool = crafted_rail.get("ok", false) and rails_after == rails_before + 4 and not bench_refused.get("ok", false) and str(bench_refused.get("reason", "")) == "WRONG_WORKSTATION"
	_record("T192_COASTERCRAFT_SHOP_BOOK", shop_ids == EXPECTED_COASTERCRAFT_SHOP_ORDER and shop_monotonic and bench_clean and shop_recipe_ok and shop_entity_ok and bench_placed.get("ok", false) and shop_placed.get("ok", false) and shop_visual_ok and shop_modal_ok and craft_ok, "the CoasterCraft Shop's book lists exactly rail, rail_slope, rail_loop, mine_cart, coaster_car, rail_switch, rail_cross, rail_curve, rail_climb in order; the Workbench book no longer lists them and ends with the shop (order 213); a placed shop opens the crafting modal titled COASTERCRAFT SHOP on one page and crafts 4 rails, which the Workbench refuses (WRONG_WORKSTATION)", {"shop_ids": shop_ids, "shop_orders": shop_orders, "bench_ids": bench_ids, "shop_recipe": shop_recipe, "entity_ok": shop_entity_ok, "placed": shop_placed.get("ok", false), "bench_placed": bench_placed.get("ok", false), "visual_ok": shop_visual_ok, "title": shop_title, "page": app.crafting_recipe_page_label.text, "crafted": crafted_rail, "bench_refused": bench_refused, "rails": [rails_before, rails_after]})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var additions: Dictionary = {}
	for item_id in VISUAL_ITEMS:
		additions[item_id] = 1
	additions["furnace"] = 1
	app.session.inventory.try_transaction({}, additions)
	for index in range(VISUAL_ITEMS.size()):
		_move_to_hotbar(VISUAL_ITEMS[index], index)
	_move_to_hotbar("furnace", 8)
	app.session.player.deactivate()
	app.session.simulation_paused = false
	var placed_castle_stone := app.session.world.set_cell(Vector3i(1, 0, 39), 8)
	app.session.player.global_position = Vector3(1.5, 1.0, 35.0)
	app.session.player.look_at(Vector3(1.5, 0.8, 40.0), Vector3.UP)
	var contact := Image.create_empty(1920, 720, false, Image.FORMAT_RGBA8)
	var captured := 0
	for index in range(VISUAL_ITEMS.size()):
		app.session.inventory.select_hotbar(index)
		await _settle_frames(8)
		var texture := get_viewport().get_texture()
		var frame := texture.get_image() if texture != null else null
		if frame == null:
			continue
		frame.resize(480, 360, Image.INTERPOLATE_LANCZOS)
		contact.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i((index % 4) * 480, (index / 4) * 360))
		captured += 1
	var path := app.data_root.path_join("p3f-held-item-contact-sheet.png")
	var error := contact.save_png(path)
	_record("T92_PRESENTATION", placed_castle_stone and captured == VISUAL_ITEMS.size() and error == OK, "one rendered contact sheet shows complete Pick, Sword and Axe silhouettes plus representative low-held building and siege items without opaque inventory-card backgrounds", {"path": path, "items": VISUAL_ITEMS, "placed_castle_stone": placed_castle_stone, "captured": captured, "size": contact.get_size(), "error": error})

	# Four panels: ready, strike toward the crosshair (~0.035 s), whip down-left
	# out of sight (~0.09 s), and the low-held Furnace frame.
	var motion_contact := Image.create_empty(2560, 360, false, Image.FORMAT_RGBA8)
	app.session.inventory.select_hotbar(1)
	app.session._held_item_view.present("iron_sword")
	await _settle_frames(4)
	var ready_ok := _blit_viewport_panel(motion_contact, Vector2i(0, 0))
	app.session._held_item_view.play_use()
	await get_tree().create_timer(0.035).timeout
	await _settle_frames(1)
	var strike_ok := _blit_viewport_panel(motion_contact, Vector2i(640, 0))
	await get_tree().create_timer(0.04).timeout
	await _settle_frames(1)
	var swing_ok := _blit_viewport_panel(motion_contact, Vector2i(1280, 0))
	await get_tree().create_timer(0.30).timeout
	app.session.inventory.select_hotbar(8)
	app.session._held_item_view.present("furnace")
	await _settle_frames(4)
	var block_ok := _blit_viewport_panel(motion_contact, Vector2i(1920, 0))
	var motion_path := app.data_root.path_join("p3h2-held-scale-and-swing.png")
	var motion_error := motion_contact.save_png(motion_path)
	_record("T104_HELD_SCALE_AND_SWING", ready_ok and strike_ok and swing_ok and block_ok and motion_error == OK, "a rendered four-panel comparison shows the ready sword, its strike toward the crosshair, the whip down-left out of sight, and the low-held Furnace presentation", {"path": motion_path, "ready": ready_ok, "strike": strike_ok, "swing": swing_ok, "block": block_ok, "size": motion_contact.get_size(), "error": motion_error})

	app.session.inventory.try_transaction({}, {"workbench": 1, "planks": 64, "stone": 64, "stick": 64, "iron_ingot": 16})
	var placed := app.session.workstations.try_place("workbench", Vector3i(5, 0, 43), app.session.world.query_cell, AABB(), 0)
	var workbench_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	app._show_crafting(workbench_id, "workbench")
	await _settle_frames(8)
	var page_one_path := app.data_root.path_join("p3f-workbench-page-1.png")
	var page_one_ok := await _save_viewport(page_one_path)
	app._crafting_recipe_page = 1
	app._refresh_crafting_panel()
	await _settle_frames(8)
	var page_two_path := app.data_root.path_join("p3f-workbench-page-2.png")
	var page_two_ok := await _save_viewport(page_two_path)
	_record("T103_ATLAS_CARD_ALIGNMENT", placed.get("ok", false) and page_one_ok and page_two_ok and app.crafting_recipe_page_label.text == "Page 2 / %d" % maxi(1, ceili(float(app._available_crafting_recipes().size()) / float(app.RECIPE_PAGE_SIZE))), "both rendered Workbench pages keep each icon entirely inside its own recipe card with complete bottom-row tools and no neighboring fragments", {"page_one_path": page_one_path, "page_two_path": page_two_path, "page": app.crafting_recipe_page_label.text, "size": get_viewport().get_visible_rect().size})

	app._close_crafting()
	app.session.inventory.try_transaction({}, {"gate_frame": 1, "wall_walk_slab": 1})
	var gate := app.session.workstations.try_place("gate_frame", Vector3i(8, 0, 40), app.session.world.query_cell, AABB(), 0)
	var slab := app.session.workstations.try_place("wall_walk_slab", Vector3i(12, 0, 40), app.session.world.query_cell, AABB(), 0)
	app.session.player.global_position = Vector3(10.5, 2.0, 34.0)
	app.session.player.look_at(Vector3(10.5, 1.2, 40.5), Vector3.UP)
	await _settle_frames(12)
	var castle_path := app.data_root.path_join("p3h3-placed-castle-skins.png")
	var castle_ok := await _save_viewport(castle_path)
	_record("T106_CASTLE_SKIN_PRESENTATION", gate.get("ok", false) and slab.get("ok", false) and castle_ok, "rendered evidence shows the Castle Stone skin on the placed Gate Frame and Wall Walk Slab", {"path": castle_path, "gate": gate.get("ok", false), "slab": slab.get("ok", false), "size": get_viewport().get_visible_rect().size})

	# T192 rendered: the CoasterCraft Shop's own book page and the placed
	# 2 x 1 machine (stone base, oak bench, rail and cart body, gold studs).
	app.session.inventory.try_transaction({}, {"coastercraft_shop": 1})
	var shop := app.session.workstations.try_place("coastercraft_shop", Vector3i(2, 0, 45), app.session.world.query_cell, AABB(), 0)
	var shop_id := str(shop.get("details", {}).get("station", {}).get("instance_id", ""))
	app._show_workstation(shop_id, "coastercraft_shop")
	await _settle_frames(8)
	var shop_book_path := app.data_root.path_join("p3f-coastercraft-shop-book.png")
	var shop_book_ok := await _save_viewport(shop_book_path)
	var shop_title: String = app.crafting_title_label.text
	app._close_crafting()
	app.session.player.global_position = Vector3(3.0, 2.0, 41.5)
	app.session.player.look_at(Vector3(3.0, 0.6, 45.5), Vector3.UP)
	await _settle_frames(12)
	var shop_path := app.data_root.path_join("p3f-coastercraft-shop.png")
	var shop_ok := await _save_viewport(shop_path)
	_record("T192_COASTERCRAFT_SHOP_RENDERED", shop.get("ok", false) and shop_book_ok and shop_ok and shop_title == "COASTERCRAFT SHOP", "rendered evidence shows the CoasterCraft Shop's own recipe book (titled COASTERCRAFT SHOP) and the placed 2 x 1 shop machine", {"book_path": shop_book_path, "path": shop_path, "title": shop_title, "placed": shop.get("ok", false)})



func _move_to_hotbar(item_id: String, target: int) -> void:
	for index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[index].get("item_id", "")) == item_id:
			if index != target:
				app.session.inventory.swap_slots(index, target)
			return


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


func _settle_frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _save_viewport(path: String) -> bool:
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	return image != null and image.get_size() == Vector2i(1280, 720) and image.save_png(path) == OK


func _blit_viewport_panel(target: Image, destination: Vector2i) -> bool:
	var texture := get_viewport().get_texture()
	var frame := texture.get_image() if texture != null else null
	if frame == null:
		return false
	frame.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	target.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), destination)
	return true


func _body_has_albedo_texture(body: Node3D) -> bool:
	if body == null:
		return false
	for child in body.get_children():
		if child is MeshInstance3D:
			var material := child.material_override as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				return true
	return false


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
