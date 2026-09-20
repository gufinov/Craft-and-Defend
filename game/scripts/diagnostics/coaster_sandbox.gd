class_name CoasterSandbox
extends Node

## Owner test sandbox for the coaster rails side project (`--coaster-sandbox`):
## starts a new game, levels a plate beside the spawn, lays a premade loop
## with a parked coaster car and a slope run with a mine cart, and keeps the
## pack topped up with rails, carts, cars, kettles, blocks and tools so nothing
## has to be mined.

const TOP_UP_SECONDS := 1.0
## Hotbar order, then the rest of the pack.
const STOCK: Array[String] = ["rail", "rail_slope", "rail_loop", "rail_switch", "mine_cart", "coaster_car", "kettle", "castle_stone", "planks", "iron_pick", "iron_sword", "stone_shot", "flame_shot", "torch", "chest", "wood_axe", "dirt", "stone"]

var app: CraftAndDefendApp
var loop_car_id := ""
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
	app.session.navigation_changed.emit("COASTER SANDBOX  ·  infinite stock  ·  loop ahead (Shift on the car to ride, 1-9 speed), slope run to the right, V third person")
	print("COASTER_SANDBOX_READY")
	if OS.get_cmdline_user_args().has("--coaster-sandbox-ride-shot"):
		# Seat-view pictures: boarding, mid-climb, head turned left.
		var shots: Array[Dictionary] = [{"wait": 0.2, "name": "ride-start.png"}, {"wait": 0.6, "name": "view-front.png", "view": "front"}, {"wait": 0.6, "name": "view-left.png", "view": "left"}, {"wait": 0.6, "name": "view-right.png", "view": "right"}, {"wait": 0.6, "name": "view-back.png", "view": "back"}, {"wait": 0.6, "name": "view-seat.png", "view": "back"}, {"wait": 1.6, "name": "ride-climb.png"}, {"wait": 1.2, "name": "ride-left.png", "yaw": Vector2(-400.0, 0.0)}, {"wait": 0.4, "name": "view-front-turned.png", "view": "front"}]
		app.session.board_coaster_car(str(loop_car_id))
		app.session.set_ride_speed(4)
		for shot in shots:
			var until := Time.get_ticks_msec() + int(float(shot.wait) * 1000.0)
			while Time.get_ticks_msec() < until:
				await get_tree().process_frame
			if shot.has("yaw"):
				app.session.coaster_ride.apply_mouse_look(shot.yaw)
				await get_tree().process_frame
			if shot.has("view"):
				app.session.coaster_ride.select_view(str(shot.view))
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(app.data_root.path_join(str(shot.name)))
			print("COASTER_SANDBOX shot %s forward=%s" % [shot.name, app.session.coaster_ride.view_forward()])
		get_tree().quit(0)
	if OS.get_cmdline_user_args().has("--coaster-sandbox-facing-check"):
		app.session.board_coaster_car(str(loop_car_id))
		app.session.set_ride_speed(6)
		var previous_travel := Vector3.ZERO
		var reversals := 0
		for sample in range(40):
			var until := Time.get_ticks_msec() + 500
			while Time.get_ticks_msec() < until:
				await get_tree().process_frame
			var ride := app.session.coaster_ride
			var hero := ride.seated_hero()
			var travel: Vector3 = app.session.coaster_carts.travel_direction(str(loop_car_id))
			var hero_forward: Vector3 = -hero.global_basis.z
			var rig: Node3D = app.session.coaster_carts.cart_rig(str(loop_car_id))
			if previous_travel.length() > 0.5 and travel.dot(previous_travel) < -0.5:
				reversals += 1
			previous_travel = travel
			print("FACING t=%.1f cell=%s travel=%s hero=%s dot=%.2f rig_up=%s cam_from_rig=%s" % [sample * 0.5, app.session.coaster_carts.rider_cell(str(loop_car_id)), travel, hero_forward, travel.dot(hero_forward), rig.global_basis.y, (ride.ride_camera().global_position - rig.global_position)])
		print("FACING reversals=%d" % reversals)
		get_tree().quit(0)
	if OS.get_cmdline_user_args().has("--coaster-sandbox-switch-click"):
		# A real right-click (press, a few frames, release) with Rail Switch
		# held, aiming at clear plate: four pieces must be laid.
		var player := app.session.player
		app.session.inventory.select_hotbar(STOCK.find("rail_switch"))
		player.global_position = Vector3(4.0, 1.0, 26.0)
		player.rotation = Vector3.ZERO
		player.look_pitch = -0.6
		player.apply_mouse_look(Vector2.ZERO)
		await get_tree().process_frame
		var before := 0
		for station_id: String in app.session.workstations.stations:
			if str(app.session.workstations.station(station_id).get("entity_id", "")) == "rail_switch":
				before += 1
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_RIGHT
			click.pressed = pressed
			Input.parse_input_event(click)
			for _frame in range(5):
				await get_tree().process_frame
			print("SWITCH_CLICK pressed=%s drag=%s state=%s" % [pressed, app.session.interaction.drag_active(), app.session.interaction.drag_state().get("mode", "")])
		var after := 0
		for station_id: String in app.session.workstations.stations:
			if str(app.session.workstations.station(station_id).get("entity_id", "")) == "rail_switch":
				after += 1
		print("SWITCH_CLICK laid %d pieces" % (after - before))
		get_tree().quit(0)
	if OS.get_cmdline_user_args().has("--coaster-sandbox-board-check"):
		# Aim from beside the parked car at the rail piece under it: Shift must
		# still board (owner 2026-09-20: the aim landed on the rail, not the car).
		var car_cell := Vector3i(3, 2, 30)
		var from := Vector3(car_cell) + Vector3(0.5, 1.6, 3.0)
		var at := Vector3(car_cell) + Vector3(0.5, -0.6, 0.5)
		var boarded := app.session.interaction.interact_from_view(from, (at - from).normalized())
		print("COASTER_SANDBOX board via rail aim: %s riding=%s" % [boarded.get("reason"), app.session.is_riding()])
		app.session.leave_coaster_car()
		var second := app.session.interaction.secondary_press_from_view(from, (Vector3(car_cell) + Vector3(0.5, 0.2, 0.5) - from).normalized())
		print("COASTER_SANDBOX board via right-click: %s riding=%s" % [second.get("reason"), app.session.is_riding()])
		app.session.leave_coaster_car()
		await get_tree().process_frame
		# A real Shift key press must board and stay boarded (the same press
		# reaches the session's input handler, which must not leave again).
		var player := app.session.player
		player.global_position = from - Vector3(0.0, 1.6, 0.0)
		player.rotation = Vector3.ZERO
		player.look_pitch = -0.6
		player.apply_mouse_look(Vector2.ZERO)
		await get_tree().process_frame
		var aim: Vector3 = -player.camera.global_basis.z
		print("COASTER_SANDBOX aim %s from %s" % [aim, player.view_origin()])
		var press := InputEventKey.new()
		press.keycode = KEY_SHIFT
		press.physical_keycode = KEY_SHIFT
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().process_frame
		var release := InputEventKey.new()
		release.keycode = KEY_SHIFT
		release.physical_keycode = KEY_SHIFT
		release.pressed = false
		Input.parse_input_event(release)
		await get_tree().process_frame
		await get_tree().process_frame
		print("COASTER_SANDBOX board via real Shift press: riding=%s" % app.session.is_riding())
		get_tree().quit(0)
	if OS.get_cmdline_user_args().has("--coaster-sandbox-shot"):
		var player := app.session.player
		# Above and behind the loop's bottom, looking down the lead-in so the
		# 45-degree steps into and out of the circle show.
		# Over the lane switcher demo, looking down its length.
		player.deactivate()
		player.global_position = Vector3(-1.0, 4.5, 42.0)
		player.rotation = Vector3.ZERO
		player.look_pitch = 0.08
		player.apply_mouse_look(Vector2.ZERO)
		app.session.inventory.select_hotbar(STOCK.find("iron_pick"))
		player.apply_mouse_look(Vector2.ZERO)
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
## A stone plate beside the spawn with a size-6 loop element in a closed circuit and

## A stone plate beside the spawn with a lead-in + loop (radius 3) along +x
## the car on its approach; nothing else on the plate.
func _lay_demo() -> void:
	var ws: WorkstationService = app.session.workstations
	var world: WorldAdapter = app.session.world
	var interaction: InteractionService = app.session.interaction
	var plate := Vector3i(-14, 0, 22)
	_level_ground(plate, 30, 22, 14)
	# The Loop element (owner 2026-09-20): size 6, entry heading -x from
	# (0, 30) on lane A (z=30); base row z=29 with the slopes at x=1 and x=-4;
	# exit on lane C (z=28) heading -x. A coaster car waits on the approach.
	var origin := Vector3i(0, 1, 30)
	app.session.inventory.select_hotbar(STOCK.find("rail_loop"))
	interaction.placement_rotation_quarters = 3
	interaction.set_loop_size(6)
	# `--coaster-sandbox-lift=1|2` lays ring fit B / C for comparison.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--coaster-sandbox-lift="):
			for _cycle in range(int(argument.trim_prefix("--coaster-sandbox-lift="))):
				interaction.cycle_loop_lift()
	interaction.begin_coaster_loop_at(origin)
	var loop := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	app.session.inventory.select_hotbar(0)
	# Approach rails on lane A (x 1..4), the car on the third.
	for x in range(1, 5):
		ws.try_place("rail", origin + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var loop_car := ws.try_place("coaster_car", origin + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	loop_car_id = str(loop_car.get("details", {}).get("station", {}).get("instance_id", ""))
	print("COASTER_SANDBOX loop %s (%s pieces) car %s" % [loop.get("reason"), loop.get("changes", {}).get("count"), loop_car.get("reason")])
	# Closed circuit: from the exit (-1, 28) on to x=-8, up to z=32, back to
	# x=4 and down to the approach, so the car laps forever.
	var circuit: Array[Vector3i] = []
	for x in range(-2, -9, -1):
		circuit.append(Vector3i(x, origin.y, 28))
	for z in range(29, 33):
		circuit.append(Vector3i(-8, origin.y, z))
	for x in range(-7, 5):
		circuit.append(Vector3i(x, origin.y, 32))
	circuit.append(Vector3i(4, origin.y, 31))
	var laid := 0
	for cell: Vector3i in circuit:
		if ws.try_place("rail", cell, world.query_cell, AABB(), 0).get("ok", false):
			laid += 1
	print("COASTER_SANDBOX circuit %d / %d rails, chain %d" % [laid, circuit.size(), CoasterRails.chain(ws.stations, origin).size()])
	# Owner 2026-09-20: nothing else on the plate - the loop, its circuit and
	# the car are the whole sandbox; build the rest yourself.


func _level_ground(origin: Vector3i, width: int, depth: int, height: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(origin + Vector3i(x, 0, z), 3)
			for y in range(1, height):
				app.session.world.set_cell(origin + Vector3i(x, y, z), 0)
