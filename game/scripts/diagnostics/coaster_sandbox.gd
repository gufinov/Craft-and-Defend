class_name CoasterSandbox
extends Node

## Owner test sandbox for the coaster rails side project (`--coaster-sandbox`):
## the CoasterCraft mode (CoasterCraftMode: a new world on the fixed seed,
## the bare stone plate, creative placement, the pack topped up every second
## with rails, carts, cars, kettles, blocks and tools) plus the premade demo
## tracks on the old 30 x 50 area of the plate (x -14..15, z 22..71) that the
## `--coaster-sandbox-*` checks and the gates depend on.

## The mode's stock list (hotbar order, then the rest of the pack).
const STOCK: Array[String] = CoasterCraftMode.STOCK

var app: CraftAndDefendApp
var loop_car_id := ""


func run(application: CraftAndDefendApp) -> void:
	app = application
	app._on_coastercraft_new_pressed()
	var deadline := Time.get_ticks_msec() + 60000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			push_error("COASTER_SANDBOX world ready timeout")
			return
		await get_tree().process_frame
	# A frame for the spawn hand-off (the mode's stock, respawn placement).
	await get_tree().process_frame
	_lay_demo()
	app.session.navigation_changed.emit("COASTER SANDBOX  ·  infinite stock  ·  loop ahead (Shift on the car to ride, 1-9 speed); curves, a mountain climb, a smooth switch and a crossing behind you")
	var spawn_clear := true
	for y in range(1, 4):
		if int(app.session.world.query_cell(Vector3i(0, y, 40)).get("voxel_id", 0)) != 0:
			spawn_clear = false
	print("COASTER_SANDBOX spawn clear=%s player=%s" % [spawn_clear, app.session.player.global_position])
	print("COASTER_SANDBOX_READY")
	if OS.get_cmdline_user_args().has("--coaster-sandbox-drop-check"):
		# Windowed drop / pickup round-trip (the drop icon is a Sprite3D).
		app.session.inventory.select_hotbar(0)
		var dropped := app.session.drop_held_item(false)
		await get_tree().process_frame
		var drop_at: Array = app.session.drops_snapshot()[0].position if app.session.drops_snapshot().size() == 1 else [0, 0, 0]
		app.session.player.global_position = Vector3(float(drop_at[0]), float(drop_at[1]) + 0.2, float(drop_at[2]))
		for _frame in range(5):
			await get_tree().process_frame
		print("DROP_CHECK dropped=%s picked_up=%s" % [dropped.get("reason"), app.session.drops_snapshot().is_empty()])
		await get_tree().process_frame
		get_tree().quit(0)
		return
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
		# A reversal is the travel direction flipping between two CONSECUTIVE
		# frames (a cart turning back on itself); the circuit's U-turn is a
		# legitimate 180 over many frames and never flips within one, which
		# the old half-second sampling could not tell apart (reversals=1
		# whenever a sample pair straddled the U-turn).
		var previous_travel := Vector3.ZERO
		var reversals := 0
		for sample in range(40):
			var until := Time.get_ticks_msec() + 500
			while Time.get_ticks_msec() < until:
				await get_tree().process_frame
				var frame_travel: Vector3 = app.session.coaster_carts.travel_direction(str(loop_car_id))
				if previous_travel.length() > 0.5 and frame_travel.length() > 0.5 and frame_travel.dot(previous_travel) < -0.5:
					reversals += 1
				previous_travel = frame_travel
			var ride := app.session.coaster_ride
			var hero := ride.seated_hero()
			var travel: Vector3 = app.session.coaster_carts.travel_direction(str(loop_car_id))
			var hero_forward: Vector3 = -hero.global_basis.z
			var rig: Node3D = app.session.coaster_carts.cart_rig(str(loop_car_id))
			print("FACING t=%.1f cell=%s travel=%s hero=%s dot=%.2f rig_up=%s cam_from_rig=%s" % [sample * 0.5, app.session.coaster_carts.rider_cell(str(loop_car_id)), travel, hero_forward, travel.dot(hero_forward), rig.global_basis.y, (ride.ride_camera().global_position - rig.global_position)])
		print("FACING reversals=%d" % reversals)
		get_tree().quit(0)
	if OS.get_cmdline_user_args().has("--coaster-sandbox-switch-click"):
		# A real right-click (press, a few frames, release) with Rail Switch
		# held, aiming at clear plate: the whole smooth switch (its default
		# 4-long, one-lane S-bend of `rail_loop` pieces) must be laid.
		var player := app.session.player
		app.session.inventory.select_hotbar(STOCK.find("rail_switch"))
		player.global_position = Vector3(4.0, 1.0, 26.0)
		player.rotation = Vector3.ZERO
		player.look_pitch = -0.6
		player.apply_mouse_look(Vector2.ZERO)
		await get_tree().process_frame
		var before := app.session.workstations.stations.size()
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_RIGHT
			click.pressed = pressed
			Input.parse_input_event(click)
			for _frame in range(5):
				await get_tree().process_frame
			var state := app.session.interaction.drag_state()
			var states: Array[String] = []
			for entry in state.get("cells", []):
				states.append("%s:%s" % [entry.cell, entry.state])
			print("SWITCH_CLICK pressed=%s drag=%s state=%s anchor=%s length=%s lanes=%s cells=%s" % [pressed, app.session.interaction.drag_active(), state.get("mode", ""), state.get("anchor"), state.get("curve_length"), state.get("curve_lanes"), states])
		var after := app.session.workstations.stations.size()
		print("SWITCH_CLICK laid %d pieces (expected %d)" % [after - before, CoasterRails.bend_piece_count(CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)])
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
		# Beside the mountain climb's foot, looking over the plate: the climb
		# rises to the right onto the stone bank, the loop stands beyond.
		player.deactivate()
		player.global_position = Vector3(-8.0, 5.5, 44.0)
		player.rotation = Vector3.ZERO
		player.look_pitch = 0.06
		player.apply_mouse_look(Vector2.ZERO)
		app.session.inventory.select_hotbar(STOCK.find("iron_pick"))
		player.apply_mouse_look(Vector2.ZERO)
		for _frame in range(150):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(app.data_root.path_join("sandbox.png"))
		get_tree().quit(0)


## Refills the pack (the mode's list) between demos that used a stack up.
func _stock_pack(arrange: bool) -> void:
	app.coastercraft.stock_pack(arrange)


## The demo area of the plate (the old 30 x 50 sandbox plate, inside the
## mode's 60 x 100 one) with a size-6 loop element in a closed circuit and
## the car on its approach; the curves, the mountain climb, the smooth
## switch and the crossing behind it.
func _lay_demo() -> void:
	var ws: WorkstationService = app.session.workstations
	var world: WorldAdapter = app.session.world
	var interaction: InteractionService = app.session.interaction
	# Levelled right now (the mode levels the rest of the plate over the
	# next frames as its chunks stream in) so the demos land on stone.
	app.coastercraft.level_area_now(Vector3i(-14, 0, 22), 30, 50)
	# The Loop element (owner 2026-09-20): size 6, entry heading -x from
	# (0, 30) on lane A (z=30); base row z=29 with the slopes at x=1 and x=-4;
	# exit on lane C (z=28) heading -x. A coaster car waits on the approach.
	var origin := Vector3i(0, 1, 30)
	# Creative (the mode): loops cost nothing here and grow as far as the sky allows.
	app.session.inventory.select_hotbar(STOCK.find("rail_loop"))
	interaction.placement_rotation_quarters = 3
	# The true loop (owner 2026-09-20): diameter 8, entry at (0, 30) heading
	# -x on lane z=30, exit one lane right at (0, 29). `--coaster-sandbox-
	# classic` lays the foundation loop (fit C) instead.
	interaction.loop_true = not OS.get_cmdline_user_args().has("--coaster-sandbox-classic")
	interaction.set_loop_diameter(8)
	interaction.set_loop_size(6)
	interaction.begin_coaster_loop_at(origin)
	var loop := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	app.session.inventory.select_hotbar(0)
	# Approach rails on the entry lane (x 1..4), the car on the third.
	for x in range(1, 5):
		ws.try_place("rail", origin + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var loop_car := ws.try_place("coaster_car", origin + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	loop_car_id = str(loop_car.get("details", {}).get("station", {}).get("instance_id", ""))
	print("COASTER_SANDBOX loop %s (%s pieces) car %s" % [loop.get("reason"), loop.get("changes", {}).get("count"), loop_car.get("reason")])
	# Closed circuit from the exit lane (z=29 true loop / z=28 classic) on to
	# x=-9, up to z=32, back to x=5 and down to the approach.
	var exit_z := 29 if interaction.loop_true else 28
	var circuit: Array[Vector3i] = []
	for x in range(-1, -10, -1):
		circuit.append(Vector3i(x, origin.y, exit_z))
	for z in range(exit_z + 1, 33):
		circuit.append(Vector3i(-9, origin.y, z))
	for x in range(-8, 6):
		circuit.append(Vector3i(x, origin.y, 32))
	circuit.append(Vector3i(5, origin.y, 31))
	circuit.append(Vector3i(5, origin.y, 30))
	var laid := 0
	for cell: Vector3i in circuit:
		if ws.try_place("rail", cell, world.query_cell, AABB(), 0).get("ok", false):
			laid += 1
	print("COASTER_SANDBOX circuit %d / %d rails, chain %d" % [laid, circuit.size(), CoasterRails.chain(ws.stations, origin).size()])
	# CoasterCraft card 4 (2026-09-20): the Curve tool's two shapes behind the
	# loop (z 36..42): a radius-4 90-degree bend entered heading +x at
	# (-12, 37) that exits heading +z at (-8, 41), and a radius-3 U-turn
	# entered heading +x at (2, 36) that comes back heading -x at (2, 42);
	# plain rails at their ends and a mine cart on each approach.
	_stock_pack(false)
	app.session.inventory.select_hotbar(STOCK.find("rail_curve"))
	interaction.placement_rotation_quarters = 1
	var bend_entry := Vector3i(-12, origin.y, 47)
	interaction.begin_curve_at(bend_entry)
	interaction.set_curve_sweep(90, false)
	interaction.set_curve_radius(4)
	var bend := interaction.commit_drag_place()
	var bend_exit: Vector3i = bend.get("changes", {}).get("exit", bend_entry)
	for x in [-2, -1]:
		ws.try_place("rail", bend_entry + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	ws.try_place("rail", bend_exit + Vector3i(0, 0, 1), world.query_cell, AABB(), 0)
	var bend_cart := ws.try_place("mine_cart", bend_entry + Vector3i(-1, 1, 0), world.query_cell, AABB(), 0)
	var turn_entry := Vector3i(2, origin.y, 46)
	interaction.begin_curve_at(turn_entry)
	interaction.set_curve_sweep(180, false)
	interaction.set_curve_radius(3)
	var turn := interaction.commit_drag_place()
	var turn_exit: Vector3i = turn.get("changes", {}).get("exit", turn_entry)
	for x in [-3, -2, -1]:
		ws.try_place("rail", turn_entry + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
		ws.try_place("rail", turn_exit + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	# Back to the tool's defaults: the owner's first Rail Curve came out a U-turn.
	interaction.set_curve_sweep(90, false)
	interaction.set_curve_radius(4)
	var turn_cart := ws.try_place("mine_cart", turn_entry + Vector3i(-2, 1, 0), world.query_cell, AABB(), 0)
	interaction.placement_rotation_quarters = 0
	app.session.inventory.select_hotbar(0)
	print("COASTER_SANDBOX curves: 90 %s (%s pieces, cart %s), U-turn %s (%s pieces, cart %s)" % [bend.get("reason"), bend.get("changes", {}).get("count"), bend_cart.get("reason"), turn.get("reason"), turn.get("changes", {}).get("count"), turn_cart.get("reason")])
	# Owner 2026-09-20: nothing else on the plate - the loop, its circuit and
	# the car are the whole sandbox; build the rest yourself.
	_lay_mountain()


## The mountain test (CoasterCraft card 5): a stepped stone bank on the
## plate (x -5..4, z 36..42, one step per cell up to 6 high) with a Climb
## from the plate onto its top (length 13, rise 6), plain rails across the
## top, a descent back to the plate (length 10, rise -6) and a mine cart
## riding up, across and down.
func _lay_mountain() -> void:
	var ws: WorkstationService = app.session.workstations
	var world: WorldAdapter = app.session.world
	var interaction: InteractionService = app.session.interaction
	# Lane 65, bank z 62..68 at the far end of the plate: clear of the spawn
	# cell (0, 40) - the bank used to sit on it and the spawn pushed the player
	# through the plate - and of the curve demos (z 44..50).
	var lane := 65
	# The loop's circuit used the whole rail stack; refill before laying more.
	_stock_pack(false)
	for x in range(-5, 5):
		var height := mini(6, x + 6)
		for z in range(62, 69):
			for y in range(1, height + 1):
				world.set_cell(Vector3i(x, y, z), 3)
	app.session.inventory.select_hotbar(STOCK.find("rail_climb"))
	interaction.placement_rotation_quarters = 1
	interaction.begin_climb_at(Vector3i(-13, 1, lane))
	interaction.set_climb(13, 6)
	var up := interaction.commit_drag_place()
	var top: Vector3i = up.get("changes", {}).get("landing", Vector3i(0, 7, lane))
	for x in range(top.x + 1, 4):
		ws.try_place("rail", Vector3i(x, top.y, lane), world.query_cell, AABB(), 0)
	interaction.begin_climb_at(Vector3i(4, top.y, lane))
	interaction.set_climb(10, -6)
	var down := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	interaction.set_climb(CoasterRails.CLIMB_LENGTH_DEFAULT, CoasterRails.CLIMB_RISE_DEFAULT)
	app.session.inventory.select_hotbar(0)
	ws.try_place("rail", Vector3i(-14, 1, lane), world.query_cell, AABB(), 0)
	ws.try_place("rail", Vector3i(15, 1, lane), world.query_cell, AABB(), 0)
	var cart := ws.try_place("mine_cart", Vector3i(-14, 2, lane), world.query_cell, AABB(), 0)
	print("COASTER_SANDBOX mountain climb %s (%s pieces) descent %s (%s pieces) cart %s chain %d" % [up.get("reason"), up.get("changes", {}).get("count"), down.get("reason"), down.get("changes", {}).get("count"), cart.get("reason"), CoasterRails.chain(ws.stations, Vector3i(-14, 1, lane)).size()])
	# CoasterCraft cards 2-3 (behind the loop, z 36..42): a Rail Switch (the
	# smooth lane switcher) heading +x from (-12, 54) that lands one lane
	# right (z 55) four cells on,
	# and a Crossing heading +x from (-1, 39) whose two tracks swap lanes
	# z 39 <-> z 41 over eight cells; plain rails lead in and out, a mine
	# cart on each.
	var bend_entry := Vector3i(-12, 1, 54)
	# The circuit used the rail stack: top up before the lead-ins.
	_stock_pack(false)
	app.session.inventory.select_hotbar(STOCK.find("rail_switch"))
	interaction.placement_rotation_quarters = 1
	interaction.set_curve_size(CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
	interaction.begin_curve_tool_at(bend_entry)
	var bend := interaction.commit_drag_place()
	var bend_layout := CoasterRails.bend_layout(bend_entry, 1, CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
	for step in range(1, 3):
		ws.try_place("rail", bend_entry - Vector3i(step, 0, 0), world.query_cell, AABB(), 0)
		ws.try_place("rail", Vector3i(bend_layout.exit) + Vector3i(step, 0, 0), world.query_cell, AABB(), 0)
	var bend_cart := ws.try_place("mine_cart", bend_entry + Vector3i(-2, 1, 0), world.query_cell, AABB(), 0)
	print("COASTER_SANDBOX rail switch %s (%s pieces) cart %s" % [bend.get("reason"), bend.get("changes", {}).get("count"), bend_cart.get("reason")])
	var cross_entry := Vector3i(-1, 1, 57)
	app.session.inventory.select_hotbar(STOCK.find("rail_cross"))
	# Size the crossing once its drag is active: with no drag, set_curve_size
	# sizes the Rail Switch (it leaked 8 x 2 into the player's first switch).
	interaction.begin_curve_tool_at(cross_entry)
	interaction.set_curve_size(CoasterRails.CROSS_DEFAULT_LENGTH, CoasterRails.CROSS_DEFAULT_LANES)
	var cross := interaction.commit_drag_place()
	var cross_layout := CoasterRails.cross_layout(cross_entry, 1, CoasterRails.CROSS_DEFAULT_LENGTH, CoasterRails.CROSS_DEFAULT_LANES)
	for step in range(1, 3):
		for end_cell: Vector3i in [cross_layout.entry_a, cross_layout.entry_b]:
			ws.try_place("rail", end_cell - Vector3i(step, 0, 0), world.query_cell, AABB(), 0)
		for end_cell: Vector3i in [cross_layout.exit_a, cross_layout.exit_b]:
			ws.try_place("rail", end_cell + Vector3i(step, 0, 0), world.query_cell, AABB(), 0)
	var cross_cart := ws.try_place("mine_cart", Vector3i(cross_layout.entry_a) + Vector3i(-2, 1, 0), world.query_cell, AABB(), 0)
	print("COASTER_SANDBOX crossing %s (%s pieces, %d shared) cart %s" % [cross.get("reason"), cross.get("changes", {}).get("count"), (cross_layout.shared as Array).size(), cross_cart.get("reason")])
	interaction.placement_rotation_quarters = 0
	app.session.inventory.select_hotbar(0)
