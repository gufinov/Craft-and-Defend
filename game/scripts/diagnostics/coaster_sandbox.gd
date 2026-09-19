class_name CoasterSandbox
extends Node

## Owner test sandbox for the coaster rails side project (`--coaster-sandbox`):
## starts a new game, levels a plate beside the spawn, lays a premade loop
## and a slope run with mine carts, and keeps the pack topped up with rails,
## carts, kettles, blocks and tools so nothing has to be mined.

const TOP_UP_SECONDS := 1.0
## Hotbar order, then the rest of the pack.
const STOCK: Array[String] = ["rail", "rail_slope", "rail_loop", "mine_cart", "kettle", "castle_stone", "planks", "iron_pick", "iron_sword", "stone_shot", "flame_shot", "torch", "chest", "wood_axe", "dirt", "stone"]

var app: CraftAndDefendApp
var _top_up_left := 0.0


func run(application: CraftAndDefendApp) -> void:
	app = application
	app._on_start_pressed()
	var deadline := Time.get_ticks_msec() + 60000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			push_error("COASTER_SANDBOX world ready timeout")
			return
		await get_tree().process_frame
	# A frame for the spawn hand-off (starter grant, respawn placement).
	await get_tree().process_frame
	_stock_pack(true)
	_lay_demo()
	app.session.navigation_changed.emit("COASTER SANDBOX  ·  infinite stock  ·  loop ahead, slope run to the right")
	print("COASTER_SANDBOX_READY")
	if OS.get_cmdline_user_args().has("--coaster-sandbox-shot"):
		var player := app.session.player
		player.global_position = Vector3(2.0, 6.0, 46.0)
		player.look_at(Vector3(-2.0, 2.0, 31.0), Vector3.UP)
		player.camera.rotation.x = -0.15
		for _frame in range(150):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(app.data_root.path_join("sandbox.png"))
		get_tree().quit(0)


func _process(delta: float) -> void:
	if app == null or app.session == null or not app.session.world_ready:
		return
	_top_up_left -= delta
	if _top_up_left <= 0.0:
		_top_up_left = TOP_UP_SECONDS
		_stock_pack(false)


## Fills every STOCK item to its stack size; on the first pass the hotbar is
## arranged in STOCK order.
func _stock_pack(arrange: bool) -> void:
	var inventory: F0Inventory = app.session.inventory
	var registry: ContentRegistry = app.session.registry
	for item_id in STOCK:
		var maximum := registry.max_stack(item_id)
		var have := inventory.count(item_id)
		if maximum > 0 and have < maximum:
			inventory.try_transaction({}, {item_id: maximum - have})
	if not arrange:
		return
	for hotbar_index in range(mini(F0Inventory.HOTBAR_COUNT, STOCK.size())):
		var wanted := STOCK[hotbar_index]
		if str(inventory.slots[hotbar_index].get("item_id", "")) == wanted:
			continue
		for slot_index in range(F0Inventory.SLOT_COUNT):
			if slot_index != hotbar_index and str(inventory.slots[slot_index].get("item_id", "")) == wanted:
				inventory.swap_slots(hotbar_index, slot_index)
				break
	inventory.select_hotbar(0)


## A stone plate beside the spawn with a lead-in + loop (radius 3) along +x
## and a slope run climbing a two-block step, each with a mine cart.
func _lay_demo() -> void:
	var ws: WorkstationService = app.session.workstations
	var world: WorldAdapter = app.session.world
	var interaction: InteractionService = app.session.interaction
	var plate := Vector3i(-14, 0, 22)
	_level_ground(plate, 30, 16, 12)
	# Loop: lead-in from x=-8, loop rises over z=30.
	var origin := Vector3i(-8, 1, 30)
	# The loop drag reads the active item: hold Rail Loop for the lay, then
	# hand the hotbar back to Rail.
	app.session.inventory.select_hotbar(STOCK.find("rail_loop"))
	interaction.begin_coaster_loop_at(origin)
	interaction.set_drag_end(origin + Vector3i(3, 0, 0))
	interaction.set_coaster_loop(true)
	var loop := interaction.commit_drag_place()
	var loop_cart := ws.try_place("mine_cart", origin + Vector3i(1, 1, 0), world.query_cell, AABB(), 0)
	print("COASTER_SANDBOX loop %s cart %s" % [loop.get("reason"), loop_cart.get("reason")])
	app.session.inventory.select_hotbar(0)
	# Slope run: rails, slope, two-block step with rails on top, then down again.
	var step := Vector3i(2, 1, 34)
	for x in range(3, 6):
		world.set_cell(step + Vector3i(x, 0, 0), 3)
	for x in [0, 1]:
		ws.try_place("rail", step + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	ws.try_place("rail_slope", step + Vector3i(2, 0, 0), world.query_cell, AABB(), 1)
	for x in [3, 4, 5]:
		ws.try_place("rail", step + Vector3i(x, 1, 0), world.query_cell, AABB(), 0)
	ws.try_place("rail_slope", step + Vector3i(6, 0, 0), world.query_cell, AABB(), 3)
	for x in [7, 8, 9]:
		ws.try_place("rail", step + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var slope_cart := ws.try_place("mine_cart", step + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	print("COASTER_SANDBOX slope run %d pieces, cart %s" % [CoasterRails.chain(ws.stations, step).size(), slope_cart.get("reason")])


func _level_ground(origin: Vector3i, width: int, depth: int, height: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(origin + Vector3i(x, 0, z), 3)
			for y in range(1, height):
				app.session.world.set_cell(origin + Vector3i(x, y, z), 0)
