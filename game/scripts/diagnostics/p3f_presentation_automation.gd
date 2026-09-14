class_name P3FPresentationAutomation
extends Node

const EXPECTED_WORKBENCH_ORDER: Array[String] = [
	"planks", "sticks", "workbench", "wood_pick", "wood_axe", "stone_pick",
	"furnace", "castle_stone", "stone_stair", "wall_walk_slab",
	"parapet_merlon", "tower_platform", "gate_frame", "wood_barricade",
	"iron_pick", "iron_sword", "ballista_bolt", "stone_shot", "ballista", "catapult",
]
const VISUAL_ITEMS: Array[String] = ["wood_pick", "stick", "castle_stone", "dirt", "ballista", "catapult"]

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
	_record("T91_HELD_AND_BLOCK_IDENTITY", missing.is_empty() and held_failures.is_empty() and block_failures.is_empty(), "all 26 carried items use transparent catalog cutouts and every voxel cube maps its complete authored face texture", {"items": item_ids.size(), "missing": missing, "held_failures": held_failures, "block_failures": block_failures})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var additions: Dictionary = {}
	for item_id in VISUAL_ITEMS:
		additions[item_id] = 1
	app.session.inventory.try_transaction({}, additions)
	for index in range(VISUAL_ITEMS.size()):
		_move_to_hotbar(VISUAL_ITEMS[index], index)
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
		frame.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		contact.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i((index % 3) * 640, (index / 3) * 360))
		captured += 1
	var path := app.data_root.path_join("p3f-held-item-contact-sheet.png")
	var error := contact.save_png(path)
	_record("T92_PRESENTATION", placed_castle_stone and captured == VISUAL_ITEMS.size() and error == OK, "one rendered contact sheet shows raised Wood Pick plus low held Sticks, textured placed/held blocks, Ballista and Catapult without opaque inventory-card backgrounds", {"path": path, "items": VISUAL_ITEMS, "placed_castle_stone": placed_castle_stone, "captured": captured, "size": contact.get_size(), "error": error})


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


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
