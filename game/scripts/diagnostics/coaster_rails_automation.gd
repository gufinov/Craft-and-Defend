class_name CoasterRailsAutomation
extends Node

## Coaster rails side project (docs/COASTER_RAILS.md): slope rails that join
## two levels, the loop drag tool and the mine cart that rides the whole
## track. Runs with `--coaster-rails-automation=gate` (headless: T160-T162,
## T168, T176-T177) and `--coaster-rails-automation=visual` (needs a window:
## T163 renders `coaster-rails.png`, T178 `coaster-climb.png`).
## track. Runs with `--coaster-rails-automation=gate` (headless: T160-T162, T168,
## T170-T171) and `--coaster-rails-automation=visual` (needs a window: T163
## renders `coaster-rails.png`, T172 `coaster-smooth.png`).
## track. Runs with `--coaster-rails-automation=gate` (headless: T160-T162, T168,
## T173-T174) and `--coaster-rails-automation=visual` (needs a window: T163
## renders `coaster-rails.png`, T175 `coaster-curves.png`).
## T168, T179 track auto-clear, T180 trestle supports) and
## `--coaster-rails-automation=visual` (needs a window: T163 renders
## `coaster-rails.png`, T181 `coaster-supports.png`).

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
	_write_json(app.data_root.path_join("coaster_rails_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("COASTER_RAILS_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("COASTER_RAILS_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	await _wait_region_loaded()
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var registry := app.session.registry
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction

	# T160 content: the three pieces, their icons and workbench recipes.
	var slope: Dictionary = registry.entity("rail_slope")
	var loop: Dictionary = registry.entity("rail_loop")
	var cart: Dictionary = registry.entity("mine_cart")
	var missing_icons := ItemIconCatalog.missing_item_ids(["rail_slope", "rail_loop", "mine_cart"])
	var recipe_orders: Dictionary = {}
	var recipe_outputs: Dictionary = {}
	for recipe in registry.recipes_for("workbench"):
		var recipe_id := str(recipe.get("id", ""))
		if recipe_id in ["rail_slope", "rail_loop", "mine_cart"]:
			recipe_orders[recipe_id] = int(recipe.get("recipe_book_order", -1))
			recipe_outputs[recipe_id] = int(recipe.get("outputs", {}).get(recipe_id, 0))
	var recipes_ok: bool = recipe_orders.get("rail_slope", -1) == 204 and recipe_orders.get("rail_loop", -1) == 205 and recipe_orders.get("mine_cart", -1) == 206 and recipe_outputs.get("rail_slope", 0) == 4 and recipe_outputs.get("rail_loop", 0) == 2 and recipe_outputs.get("mine_cart", 0) == 1
	var slope_ok: bool = int(slope.get("slope", 0)) == 1 and not slope.has("linear") and str(slope.get("attributes", {}).get("role", "")) == "rail" and not interaction.is_linear_entity_item("rail_slope")
	var loop_ok: bool = str(loop.get("coaster_tool", "")) == "loop" and (loop.get("support_offsets", [1]) as Array).is_empty() and interaction.is_coaster_loop_item("rail_loop") and not interaction.is_linear_entity_item("rail_loop")
	var cart_ok: bool = float(cart.get("cart", {}).get("rail_speed", 0.0)) == 3.0 and cart.get("mount", {}).get("allowed", []) == ["rail_mount"] and not cart.has("siege")
	var tracks_ok := CoasterRails.is_track_id("rail") and CoasterRails.is_track_id("rail_slope") and CoasterRails.is_track_id("rail_loop") and not CoasterRails.is_track_id("mine_cart")
	_record("T160_COASTER_CONTENT", missing_icons.is_empty() and recipes_ok and slope_ok and loop_ok and cart_ok and tracks_ok, "rail_slope (slope 1, not linear), rail_loop (loop tool, no support) and mine_cart (rail speed 3, rail mount) are registered with icons and workbench recipes at orders 204-206 (4 slopes, 2 loops, 1 cart)", {"missing_icons": missing_icons, "orders": recipe_orders, "outputs": recipe_outputs, "slope_ok": slope_ok, "loop_ok": loop_ok, "cart_ok": cart_ok, "tracks_ok": tracks_ok})

	# T161 slope chain: two flat rails, a slope rising +x and three flat rails
	# one level up form one chain; a rail on the upper level beside a lower
	# rail without a slope does not join; a mine cart rides up and back.
	var base := Vector3i(-14, 0, 30)
	_level_ground(base + Vector3i(-2, 0, -2), 14, 6, 9)
	for x in range(3, 6):
		world.set_cell(base + Vector3i(x, 0, 0), 3)
	world.set_cell(base + Vector3i(8, 0, 0), 3)
	app.session.inventory.try_transaction({}, {"rail": 8, "rail_slope": 2, "mine_cart": 1})
	var placed_ok := true
	for x in [0, 1]:
		placed_ok = placed_ok and bool(ws.try_place("rail", base + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var slope_placed := ws.try_place("rail_slope", base + Vector3i(2, 0, 0), world.query_cell, AABB(), 1)
	placed_ok = placed_ok and bool(slope_placed.get("ok", false))
	for x in [3, 4, 5]:
		placed_ok = placed_ok and bool(ws.try_place("rail", base + Vector3i(x, 1, 0), world.query_cell, AABB(), 0).get("ok", false))
	# Control: an upper rail beside a lower one with no slope between them.
	placed_ok = placed_ok and bool(ws.try_place("rail", base + Vector3i(7, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	placed_ok = placed_ok and bool(ws.try_place("rail", base + Vector3i(8, 1, 0), world.query_cell, AABB(), 0).get("ok", false))
	var chain := CoasterRails.chain(ws.stations, base)
	var chain_cells := chain.size()
	var climbs := chain.has(base + Vector3i(2, 0, 0)) and chain.has(base + Vector3i(3, 1, 0)) and chain.has(base + Vector3i(5, 1, 0))
	var slope_joints: Array = chain.get(base + Vector3i(2, 0, 0), [])
	var slope_degree := slope_joints.size()
	var control_chain := CoasterRails.chain(ws.stations, base + Vector3i(7, 0, 0))
	var control_isolated := control_chain.size() == 1
	var kettle_chain := app.session.siege_defense._rail_chain(base)
	var kettle_step := app.session.siege_defense._rail_step(kettle_chain, base + Vector3i(2, 0, 0), base + Vector3i(5, 1, 0))
	var slope_id := str(slope_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var slope_body: Node3D = app.session._station_visuals.get(slope_id)
	var slope_parts := slope_body.find_children("*", "MeshInstance3D", true, false).size() if slope_body != null else 0
	var cart_placed := ws.try_place("mine_cart", base + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var cart_id := str(cart_placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var carts := app.session.coaster_carts
	var top_frame := -1
	var back_frame := -1
	if carts != null:
		for frame in range(240):
			carts.advance(1.0 / 30.0, false)
			var cell := carts.rider_cell(cart_id)
			if top_frame < 0 and cell == base + Vector3i(5, 1, 0):
				top_frame = frame
			if top_frame >= 0 and back_frame < 0 and cell == base:
				back_frame = frame
				break
	var cart_body: Node3D = app.session._station_visuals.get(cart_id)
	var rig: Node3D = cart_body.get_node_or_null("CartRig") if cart_body != null else null
	var rig_low := rig != null and rig.global_position.y < 1.0
	_record("T161_SLOPE_CHAIN_AND_CART", placed_ok and chain_cells == 6 and climbs and slope_degree == 2 and control_isolated and kettle_step == base + Vector3i(3, 1, 0) and slope_parts >= 12 and cart_placed.get("ok", false) and str(cart_placed.get("details", {}).get("mount", "")) == "rail_mount" and carts != null and top_frame > 0 and back_frame > top_frame and rig_low, "two flat rails, a slope rising +x and three rails one level up chain as six cells (the slope joins both ends); an upper rail beside a lower one without a slope stays alone; the kettle router steps up through the slope; the slope model has posts, deck, rails and ties; a mine cart mounts on the first rail, rides to the top rail and comes back down", {"placed": placed_ok, "chain_cells": chain_cells, "climbs": climbs, "slope_degree": slope_degree, "control_isolated": control_isolated, "kettle_step": kettle_step, "slope_parts": slope_parts, "cart": cart_placed.get("reason"), "mount": cart_placed.get("details", {}).get("mount", ""), "service": carts != null, "top_frame": top_frame, "back_frame": back_frame, "rig_y": rig.global_position.y if rig != null else null})
	if cart_placed.get("ok", false):
		ws.try_dismantle(cart_id, world.query_cell, AABB())

	# T168 lane switcher (owner 2026-09-20): four rails, the switcher laid by
	# its drag tool (entry, two middles side by side, exit one lane to the
	# right of travel), four rails on the new lane; one chain; the middles
	# ride on the diagonal; a rail beside a middle does not join; a mine cart
	# crosses to the far end and back; the middles draw diagonal rails.
	var sw := Vector3i(-14, 0, 50)
	_level_ground(sw + Vector3i(-2, 0, -3), 18, 8, 9)
	app.session.inventory.try_transaction({}, {"rail": 12, "rail_switch": 8, "mine_cart": 1})
	var sw_ok := true
	for x in range(0, 4):
		sw_ok = sw_ok and bool(ws.try_place("rail", sw + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var switch_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_switch":
			switch_slot = slot_index
	if switch_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(switch_slot, 3)
		switch_slot = 3
	app.session.inventory.select_hotbar(switch_slot)
	interaction.placement_rotation_quarters = 1
	# The right-press path itself must start the switcher drag (owner
	# 2026-09-20: it placed a single piece when it fell through to the
	# one-cell placement).
	var press_origin := Vector3(sw) + Vector3(4.5, 2.0, 3.0)
	var press_aim := (Vector3(sw) + Vector3(4.5, 0.0, 0.5) - press_origin).normalized()
	var press_started := interaction.secondary_press_from_view(press_origin, press_aim)
	var press_mode := str(interaction.drag_state().get("mode", ""))
	interaction.cancel_drag_place()
	var sw_started := interaction.begin_lane_switch_at(sw + Vector3i(4, 0, 0))
	var sw_ghost := interaction.drag_state()
	var sw_ghost_cells: Array = sw_ghost.get("cells", [])
	var sw_ghost_ok := sw_ghost_cells.size() == 4
	for entry in sw_ghost_cells:
		sw_ghost_ok = sw_ghost_ok and str(entry.state) == "ok"
	var switch_before := app.session.inventory.count("rail_switch")
	var sw_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var switch_spent := switch_before - app.session.inventory.count("rail_switch") == 4
	for x in range(7, 11):
		sw_ok = sw_ok and bool(ws.try_place("rail", sw + Vector3i(x, 0, 1), world.query_cell, AABB(), 0).get("ok", false))
	# Control: a rail in lane 0 beside the lane-1 middle must not join.
	sw_ok = sw_ok and bool(ws.try_place("rail", sw + Vector3i(6, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var sw_chain := CoasterRails.chain(ws.stations, sw)
	var sw_layout := CoasterRails.switch_layout(sw + Vector3i(4, 0, 0), 1)
	var mid_a: Vector3i = sw_layout[1].cell
	var mid_b: Vector3i = sw_layout[2].cell
	var sw_exit: Vector3i = sw_layout[3].cell
	var sw_shape := mid_a == sw + Vector3i(5, 0, 0) and mid_b == sw + Vector3i(5, 0, 1) and sw_exit == sw + Vector3i(6, 0, 1)
	var control_alone := CoasterRails.chain(ws.stations, sw + Vector3i(6, 0, 0)).size() == 1 and not sw_chain.has(sw + Vector3i(6, 0, 0))
	var mid_a_record: Dictionary = ws.station(ws.station_at_cell(mid_a))
	var mid_b_record: Dictionary = ws.station(ws.station_at_cell(mid_b))
	var ride_a := CoasterRails.ride_point(mid_a_record)
	var ride_b := CoasterRails.ride_point(mid_b_record)
	var rides_diagonal := ride_a.is_equal_approx(Vector3(mid_a) + Vector3(0.25, 0.55, 0.75)) and ride_b.is_equal_approx(Vector3(mid_b) + Vector3(0.75, 0.55, 0.25))
	var kettle_point := app.session.siege_defense._rail_point(mid_a)
	var kettle_on_diagonal := kettle_point.is_equal_approx(ride_a + Vector3(0.0, 0.95, 0.0))
	var mid_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(mid_a))
	var mid_diagonal := mid_body != null and mid_body.get_node_or_null("SwitchRails") != null
	var sw_cart := ws.try_place("mine_cart", sw + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var sw_cart_id := str(sw_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var far_frame := -1
	var home_frame := -1
	var crossed_mid_b := false
	if app.session.coaster_carts != null:
		for frame in range(400):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(sw_cart_id)
			crossed_mid_b = crossed_mid_b or cell == mid_b
			if far_frame < 0 and cell == sw + Vector3i(10, 0, 1):
				far_frame = frame
			if far_frame >= 0 and home_frame < 0 and cell == sw:
				home_frame = frame
				break
	_record("T168_LANE_SWITCHER", sw_ok and press_started.get("reason") == "DRAG_STARTED" and press_mode == "lane_switch" and sw_started.get("ok", false) and sw_ghost_ok and sw_laid.get("reason") == "SWITCH_PLACED" and switch_spent and sw_shape and sw_chain.size() == 12 and control_alone and rides_diagonal and kettle_on_diagonal and mid_diagonal and sw_cart.get("ok", false) and crossed_mid_b and far_frame > 0 and home_frame > far_frame, "the Lane Switcher drag ghosts four cells (entry, two middles side by side, exit one lane right) and lays them for four items; with four rails before and four after on the new lane the twelve pieces chain; a lane-0 rail beside the lane-1 middle stays alone; the middles ride a quarter cell onto their diagonal (kettles too) and draw diagonal rails; a mine cart crosses to the far rail and comes home", {"placed": sw_ok, "press": press_started.get("reason"), "press_mode": press_mode, "started": sw_started.get("reason"), "ghost": sw_ghost_ok, "laid": sw_laid.get("reason"), "spent": switch_spent, "shape": sw_shape, "chain": sw_chain.size(), "control_alone": control_alone, "ride_a": ride_a, "ride_b": ride_b, "kettle": kettle_point, "mid_diagonal": mid_diagonal, "cart": sw_cart.get("reason"), "crossed": crossed_mid_b, "far_frame": far_frame, "home_frame": home_frame})
	if sw_cart.get("ok", false):
		ws.try_dismantle(sw_cart_id, world.query_cell, AABB())

	# T162 the Loop element (owner 2026-09-20): with Rail Loop held a press
	# ghosts a complete size-4 loop (two switchers, two slopes, the circle);
	# 4-9 / X / C resize it; release lays every piece for one item; the chain
	# from the entry runs through the loop to the exit two lanes over; a cart
	# from the approach rides over the top and out; a blocked ghost is refused
	# and lays nothing; the laid track survives a save round-trip.
	var anchor := Vector3i(-14, 0, 40)
	_level_ground(anchor + Vector3i(-12, 0, -4), 22, 8, 14)
	app.session.inventory.try_transaction({}, {"rail_loop": 4, "mine_cart": 1, "rail": 6})
	var loop_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_loop":
			loop_slot = slot_index
	if loop_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(loop_slot, 2)
		loop_slot = 2
	app.session.inventory.select_hotbar(loop_slot)
	interaction.placement_rotation_quarters = 3
	interaction.loop_true = false
	interaction.set_loop_size(4)
	var started := interaction.begin_coaster_loop_at(anchor)
	var ghost := interaction.drag_state()
	var ghost_cells: Array = ghost.get("cells", [])
	var size_four := int(ghost.get("loop_size", 0)) == 4
	var four_ok := true
	var four_entities: Dictionary = {}
	for entry in ghost_cells:
		four_ok = four_ok and str(entry.state) == "ok"
		var entity := str(entry.entity_id)
		four_entities[entity] = int(four_entities.get(entity, 0)) + 1
	var four_count := ghost_cells.size()
	# Sizes: 6 by number key, 7 by C, 6 by X, 9 clamps at the limit.
	interaction.set_loop_size(6)
	var six_count: int = (interaction.drag_state().get("cells", []) as Array).size()
	interaction.coaster_loop_keys(false, true)
	interaction.coaster_loop_keys(false, false)
	var seven := int(interaction.drag_state().get("loop_size", 0))
	interaction.coaster_loop_keys(true, false)
	interaction.coaster_loop_keys(false, false)
	var six_again := int(interaction.drag_state().get("loop_size", 0))
	interaction.set_loop_size(12)
	var clamped := int(interaction.drag_state().get("loop_size", 0))
	interaction.set_loop_size(4)
	# Every ring piece rides the true circle and never below the slope corners.
	var round_cells: Array = interaction.drag_state().get("cells", [])
	var round_loops := 0
	var round_arcs := 0
	for entry in round_cells:
		if str(entry.entity_id) == "rail_loop":
			round_loops += 1
			if (entry.get("extra", {}) as Dictionary).has("loop_center"):
				round_arcs += 1
	var round_ok: bool = round_loops > 8 and round_arcs == round_loops
	var loops_before := app.session.inventory.count("rail_loop")
	var committed := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var one_item := loops_before - app.session.inventory.count("rail_loop") == 1
	var layout := CoasterRails.loop_element_layout(anchor, 3, 4, CoasterRails.LOOP_LIFTS[interaction.loop_lift_index])
	var exit_cell: Vector3i = layout.exit
	var left_slope: Vector3i = layout.left_slope
	var right_slope: Vector3i = layout.right_slope
	var arch: Array = layout.arch
	# The top row's middle piece (the row's end pieces are the corners).
	var top_cell: Vector3i = arch[0]
	for cell: Vector3i in arch:
		if cell.y > top_cell.y or (cell.y == top_cell.y and absf(float(cell.x) + 0.5 - float(layout.center.x)) < absf(float(top_cell.x) + 0.5 - float(layout.center.x))):
			top_cell = cell
	var loop_chain := CoasterRails.chain(ws.stations, anchor)
	var chain_ok := loop_chain.size() == four_count and loop_chain.has(exit_cell) and loop_chain.has(top_cell) and (loop_chain.get(left_slope, []) as Array).size() == 2 and (loop_chain.get(right_slope, []) as Array).size() == 2
	var switch_pieces := int(four_entities.get("rail_switch", 0)) == 6 and int(four_entities.get("rail_slope", 0)) == 2 and int(four_entities.get("rail_loop", 0)) == arch.size()
	# Octagon: the top row draws as flat rail pieces, the vertical runs as
	# loop arms; every piece knows the loop's centre to lean toward.
	var side_cell: Vector3i = arch[0]
	var arc_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(side_cell))
	var top_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(top_cell))
	var arc_drawn := arc_body != null and arc_body.get_node_or_null("LoopTrack") != null and top_body != null and top_body.get_node_or_null("LoopTrack") != null
	var top_record: Dictionary = ws.station(ws.station_at_cell(top_cell))
	var first_record: Dictionary = ws.station(ws.station_at_cell(side_cell))
	var rides_circle := CoasterRails.lean_center(top_record) != Vector3.INF and CoasterRails.lean_center(top_record).y < CoasterRails.ride_point(top_record).y and side_cell == left_slope + Vector3i(-1, 1, 0) and CoasterRails.ride_point(first_record).y >= float(anchor.y) + CoasterRails.SLOPE_RAIL_TOP - 0.001
	# Approach rails behind the entry (travel -x, so behind is +x) and a cart.
	for x in range(1, 4):
		ws.try_place("rail", anchor + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var loop_cart := ws.try_place("mine_cart", anchor + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	var loop_cart_id := str(loop_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var top_reached := -1
	var exit_reached := -1
	if app.session.coaster_carts != null:
		for frame in range(900):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(loop_cart_id)
			if top_reached < 0 and cell == top_cell:
				top_reached = frame
			if top_reached >= 0 and exit_reached < 0 and cell == exit_cell:
				exit_reached = frame
				break
	# Blocked: a stone column where the circle goes; nothing is laid.
	var blocked_anchor := anchor + Vector3i(0, 0, 5)
	world.set_cell(blocked_anchor + Vector3i(-2, 3, -1), 3)
	app.session.inventory.select_hotbar(loop_slot)
	interaction.placement_rotation_quarters = 3
	interaction.begin_coaster_loop_at(blocked_anchor)
	var blocked_state: Array = interaction.drag_state().get("cells", [])
	var red := 0
	for entry in blocked_state:
		if str(entry.state) == "blocked":
			red += 1
	var stations_before := ws.stations.size()
	var refused := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var nothing_laid: bool = ws.stations.size() == stations_before and refused.get("reason") == "LOOP_BLOCKED"
	# Save round-trip keeps the joints and the circle.
	var chain_before_save := CoasterRails.chain(ws.stations, anchor).size()
	var saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(saved, world.query_cell) if saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var restored_chain := CoasterRails.chain(ws.stations, anchor)
	var round_trip: bool = restored.get("ok", false) and restored_chain.size() == chain_before_save and CoasterRails.lean_center(ws.station(ws.station_at_cell(top_cell))) != Vector3.INF
	# The true loop (owner 2026-09-20): L switches to the helix; every ghost
	# piece is a rail_loop piece; the entry and the exit one lane right are
	# the only ground cells; Shift-drag sizing; a cart rides the approach,
	# over the top (drifting a lane) and out on the exit lane.
	var helix_anchor := anchor + Vector3i(0, 0, 12)
	_level_ground(helix_anchor + Vector3i(-12, 0, -4), 22, 8, 14)
	app.session.inventory.try_transaction({}, {"rail_loop": 60, "rail": 8})
	app.session.inventory.select_hotbar(loop_slot)
	interaction.placement_rotation_quarters = 3
	interaction.begin_coaster_loop_at(helix_anchor)
	var helix_on := interaction.toggle_loop_kind()
	interaction.set_loop_diameter(8)
	var helix_ghost: Array = interaction.drag_state().get("cells", [])
	var helix_all_loops := not helix_ghost.is_empty()
	var helix_ground := 0
	for entry in helix_ghost:
		helix_all_loops = helix_all_loops and str(entry.entity_id) == "rail_loop" and str(entry.state) == "ok"
		if Vector3i(entry.cell).y == helix_anchor.y:
			helix_ground += 1
	var eight_count := helix_ghost.size()
	# Shift-drag: aiming 14 cells along the lane from above sets diameter 14.
	var far_origin := Vector3(helix_anchor) + Vector3(-13.5, 6.0, 0.5)
	interaction.update_drag_place(far_origin, Vector3.DOWN, true)
	var dragged := int(interaction.drag_state().get("loop_size", 0))
	var dragged_count: int = (interaction.drag_state().get("cells", []) as Array).size()
	# The pack caps the size: with about 60 loops in the pack, asking for 40 stops
	# at the largest diameter whose pieces the pack can pay for.
	interaction.set_loop_diameter(40)
	var capped := int(interaction.drag_state().get("loop_size", 0))
	var loops_in_pack := app.session.inventory.count("rail_loop")
	var capped_ok := capped < 40 and CoasterRails.helix_piece_count(capped) <= loops_in_pack and CoasterRails.helix_piece_count(capped + 1) > loops_in_pack
	interaction.set_loop_diameter(8)
	var loops_before_helix := app.session.inventory.count("rail_loop")
	var helix_laid := interaction.commit_drag_place()
	var paid_per_piece := loops_before_helix - app.session.inventory.count("rail_loop") == eight_count
	interaction.placement_rotation_quarters = 0
	var helix_layout := CoasterRails.helix_layout(helix_anchor, 3, 8)
	var helix_exit: Vector3i = helix_layout.exit
	var helix_top := helix_anchor
	for cell: Vector3i in helix_layout.cells:
		if cell.y > helix_top.y:
			helix_top = cell
	for x in range(1, 4):
		ws.try_place("rail", helix_anchor + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	for x in range(1, 4):
		ws.try_place("rail", helix_exit + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
	var helix_chain := CoasterRails.chain(ws.stations, helix_anchor)
	var helix_joined := helix_chain.has(helix_exit) and helix_chain.has(helix_top) and helix_chain.has(helix_exit + Vector3i(-3, 0, 0)) and helix_chain.has(helix_anchor + Vector3i(3, 0, 0)) and not (helix_chain.get(helix_anchor, []) as Array).has(helix_exit)
	var helix_cart := ws.try_place("mine_cart", helix_anchor + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	var helix_cart_id := str(helix_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var helix_over := -1
	var helix_out := -1
	if app.session.coaster_carts != null:
		for frame in range(1200):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(helix_cart_id)
			if helix_over < 0 and cell == helix_top:
				helix_over = frame
			if helix_over >= 0 and helix_out < 0 and cell == helix_exit + Vector3i(-3, 0, 0):
				helix_out = frame
				break
	var helix_ok: bool = capped_ok and paid_per_piece and helix_on and helix_all_loops and helix_ground >= 4 and dragged == 14 and dragged_count > eight_count and helix_laid.get("reason") == "LOOP_PLACED" and int(helix_laid.get("changes", {}).get("count", 0)) == eight_count and helix_joined and helix_cart.get("ok", false) and helix_over > 0 and helix_out > helix_over
	if helix_cart.get("ok", false):
		ws.try_dismantle(helix_cart_id, world.query_cell, AABB())
	interaction.loop_true = true
	_record("T162_LOOP_ELEMENT", started.get("ok", false) and size_four and four_ok and switch_pieces and six_count > four_count and seven == 7 and six_again == 6 and clamped == 9 and round_ok and committed.get("reason") == "LOOP_PLACED" and int(committed.get("changes", {}).get("count", 0)) == four_count and one_item and chain_ok and arc_drawn and rides_circle and loop_cart.get("ok", false) and top_reached > 0 and exit_reached > top_reached and red > 0 and nothing_laid and round_trip and helix_ok, "with Rail Loop held a press ghosts a complete size-4 loop (six switcher pieces, two slopes, the circle pieces); 6 by key adds pieces, C makes 7, X makes 6, 12 clamps to 9, every ring piece rides the true circle; release lays every piece for one item as one chain from the entry through both slopes and the circle's top to the exit two lanes over; every ring piece draws the loop track (rails, ties, spine) and leans toward the loop's centre; a cart from the approach reaches the top and then the exit; a ghost over a stone column shows red and lays nothing; the laid track survives a save round-trip; L switches to the TRUE loop: a diameter-8 helix of rail_loop pieces touching the ground only at its entry and exit one lane right, Shift-drag to 14 grows it, the pack caps the size (about 60 loops) and pays one per piece, and a cart rides the approach over the top and out on the exit lane", {"started": started.get("reason"), "size_four": size_four, "four_ok": four_ok, "entities": four_entities, "four_count": four_count, "six_count": six_count, "seven": seven, "six_again": six_again, "clamped": clamped, "round_loops": round_loops, "round_arcs": round_arcs, "committed": committed.get("reason"), "count": committed.get("changes", {}).get("count", 0), "one_item": one_item, "chain": loop_chain.size(), "chain_ok": chain_ok, "arc_drawn": arc_drawn, "rides_circle": rides_circle, "cart": loop_cart.get("reason"), "top_frame": top_reached, "exit_frame": exit_reached, "red": red, "nothing_laid": nothing_laid, "refused": refused.get("reason"), "round_trip": round_trip, "restored": restored.get("reason"), "helix_ok": helix_ok, "capped": capped, "capped_ok": capped_ok, "paid_per_piece": paid_per_piece, "helix_all_loops": helix_all_loops, "helix_ground": helix_ground, "eight_count": eight_count, "dragged": dragged, "dragged_count": dragged_count, "helix_laid": helix_laid.get("reason"), "helix_joined": helix_joined, "helix_cart": helix_cart.get("reason"), "helix_over": helix_over, "helix_out": helix_out})

	# T176 the Climb (CoasterCraft card 5, 2026-09-20): with Climb held a
	# press ghosts a complete climb (slope-in, grade, slope-out) from the
	# entry to a landing 8 ahead and 4 up; Shift-aim sets length and rise
	# (a hilltop column, a pit for a descent); 4-9 / X / C set the rise; the
	# pack caps the length; release lays every rail_loop piece for one item
	# each; plain rails join both ends at their heights; a cart rides up to
	# the landing and back without its up vector flipping; a blocked ghost
	# shows red and lays nothing; the track survives a save round-trip.
	var cb := Vector3i(8, 0, 20)
	_level_ground(cb + Vector3i(-4, 0, -4), 26, 9, 14)
	app.session.inventory.try_transaction({}, {"rail_climb": 20, "rail": 12, "mine_cart": 1})
	var climb_item: Dictionary = registry.item("rail_climb")
	var climb_entity: Dictionary = registry.entity("rail_climb")
	var climb_recipe: Dictionary = {}
	for recipe: Dictionary in registry.recipes_for("workbench"):
		if str(recipe.get("id", "")) == "rail_climb":
			climb_recipe = recipe
	var climb_content := not climb_item.is_empty() and str(climb_entity.get("coaster_tool", "")) == "climb" and (climb_entity.get("support_offsets", [1]) as Array).is_empty() and int(climb_recipe.get("recipe_book_order", 0)) == 212 and int((climb_recipe.get("outputs", {}) as Dictionary).get("rail_climb", 0)) == 8 and ItemIconCatalog.missing_item_ids(["rail_climb"]).is_empty() and interaction.is_climb_item("rail_climb") and not interaction.is_linear_entity_item("rail_climb")
	var climb_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_climb":
			climb_slot = slot_index
	if climb_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(climb_slot, 4)
		climb_slot = 4
	app.session.inventory.select_hotbar(climb_slot)
	interaction.placement_rotation_quarters = 1
	interaction.set_climb(CoasterRails.CLIMB_LENGTH_DEFAULT, CoasterRails.CLIMB_RISE_DEFAULT)
	# The right-press path itself starts the climb drag.
	var cb_press_origin := Vector3(cb) + Vector3(0.5, 3.0, 3.0)
	var cb_press_aim := (Vector3(cb) + Vector3(0.5, 0.0, 0.5) - cb_press_origin).normalized()
	var cb_press := interaction.secondary_press_from_view(cb_press_origin, cb_press_aim)
	var cb_press_mode := str(interaction.drag_state().get("mode", ""))
	var cb_press_anchor: Vector3i = interaction.drag_state().get("anchor", Vector3i.MAX)
	interaction.cancel_drag_place()
	var cb_started := interaction.begin_climb_at(cb)
	var cb_ghost: Array = interaction.drag_state().get("cells", [])
	var cb_default := int(interaction.drag_state().get("climb_length", 0)) == 8 and int(interaction.drag_state().get("climb_rise", 0)) == 4
	var cb_all_ok := not cb_ghost.is_empty()
	for entry in cb_ghost:
		cb_all_ok = cb_all_ok and str(entry.entity_id) == "rail_loop" and str(entry.state) == "ok" and (entry.get("extra", {}) as Dictionary).has("curve")
	var cb_ends_ok := cb_all_ok and Vector3i(cb_ghost[0].cell) == cb and Vector3i(cb_ghost[cb_ghost.size() - 1].cell) == cb + Vector3i(8, 4, 0)
	var cb_default_count := cb_ghost.size()
	# Shift-aim: a stone column 12 ahead, 6 high; aiming down at it sets
	# length 12 and rise 6.
	for y in range(0, 6):
		world.set_cell(cb + Vector3i(12, y, 0), 3)
	interaction.update_drag_place(Vector3(cb) + Vector3(12.5, 12.0, 0.5), Vector3.DOWN, true)
	var cb_shift_up := int(interaction.drag_state().get("climb_length", 0)) == 12 and int(interaction.drag_state().get("climb_rise", 0)) == 6
	var cb_shift_landing: Vector3i = interaction.drag_state().get("end", Vector3i.MAX)
	# A pit 10 ahead (floor at -4, open from 3 ahead so the descent's cells
	# are clear): aiming into it sets length 10, rise -3.
	for x in range(3, 11):
		for y in range(-1, -4, -1):
			world.set_cell(cb + Vector3i(x, y, 0), 0)
		world.set_cell(cb + Vector3i(x, -4, 0), 3)
	interaction.update_drag_place(Vector3(cb) + Vector3(10.5, 8.0, 0.5), Vector3.DOWN, true)
	var cb_shift_down := int(interaction.drag_state().get("climb_length", 0)) == 10 and int(interaction.drag_state().get("climb_rise", 0)) == -3
	var cb_descent_ok := true
	var cb_descent_cells: Array = interaction.drag_state().get("cells", [])
	for entry in cb_descent_cells:
		cb_descent_ok = cb_descent_ok and str(entry.state) == "ok"
	cb_descent_ok = cb_descent_ok and Vector3i(cb_descent_cells[cb_descent_cells.size() - 1].cell) == cb + Vector3i(10, -3, 0)
	# Keys: 6 sets the rise, X lowers it, C raises it.
	interaction.set_climb_rise(6)
	var cb_six := int(interaction.drag_state().get("climb_rise", 0))
	interaction.coaster_loop_keys(true, false)
	interaction.coaster_loop_keys(false, false)
	var cb_five := int(interaction.drag_state().get("climb_rise", 0))
	interaction.coaster_loop_keys(false, true)
	interaction.coaster_loop_keys(false, false)
	var cb_six_again := int(interaction.drag_state().get("climb_rise", 0))
	# The pack caps the length: with 20 items, asking for 60 stops where the
	# next length would cost more than the pack holds.
	interaction.set_climb(60, 4)
	var cb_capped := int(interaction.drag_state().get("climb_length", 0))
	var cb_in_pack := app.session.inventory.count("rail_climb")
	var cb_capped_ok := cb_capped < 60 and CoasterRails.climb_piece_count(cb_capped, 4) <= cb_in_pack and CoasterRails.climb_piece_count(cb_capped + 1, 4) > cb_in_pack
	# Lay the default climb (8 ahead, 4 up) for one item per piece.
	interaction.set_climb(8, 4)
	var cb_before := app.session.inventory.count("rail_climb")
	var cb_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var cb_landing: Vector3i = cb_laid.get("changes", {}).get("landing", Vector3i.MAX)
	var cb_paid := cb_before - app.session.inventory.count("rail_climb") == cb_default_count and int(cb_laid.get("changes", {}).get("count", 0)) == cb_default_count
	# Plain rails: three behind the entry, three past the landing (4 up, on
	# a stone ledge).
	var cb_rails := true
	var cb_rail_reasons: Array[String] = []
	for x in range(1, 4):
		var behind := ws.try_place("rail", cb + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
		cb_rails = cb_rails and bool(behind.get("ok", false))
		cb_rail_reasons.append(str(behind.get("reason")))
	for x in range(1, 4):
		world.set_cell(cb_landing + Vector3i(x, -1, 0), 3)
		var ahead := ws.try_place("rail", cb_landing + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
		cb_rails = cb_rails and bool(ahead.get("ok", false))
		cb_rail_reasons.append(str(ahead.get("reason")))
	var cb_chain := CoasterRails.chain(ws.stations, cb + Vector3i(-3, 0, 0))
	var cb_joined := cb_chain.size() == cb_default_count + 6 and cb_chain.has(cb_landing + Vector3i(3, 0, 0)) and cb_landing == cb + Vector3i(8, 4, 0)
	var cb_entry_record: Dictionary = ws.station(ws.station_at_cell(cb))
	var cb_landing_record: Dictionary = ws.station(ws.station_at_cell(cb_landing))
	var cb_heights := is_equal_approx(CoasterRails.ride_point(cb_entry_record).y, float(cb.y) + 0.55) and is_equal_approx(CoasterRails.ride_point(cb_landing_record).y, float(cb_landing.y) + 0.55)
	var cb_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(cb + Vector3i(4, 2, 0)))
	var cb_drawn := cb_body != null and cb_body.get_node_or_null("LoopTrack") != null
	var cb_cart := ws.try_place("mine_cart", cb + Vector3i(-3, 1, 0), world.query_cell, AABB(), 0)
	var cb_cart_id := str(cb_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var cb_top_frame := -1
	var cb_home_frame := -1
	var cb_min_up := 1.0
	if app.session.coaster_carts != null:
		for frame in range(900):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(cb_cart_id)
			var cb_rig: Node3D = app.session.coaster_carts.cart_rig(cb_cart_id)
			if cb_rig != null:
				cb_min_up = minf(cb_min_up, cb_rig.global_basis.y.y)
			if cb_top_frame < 0 and cell == cb_landing + Vector3i(3, 0, 0):
				cb_top_frame = frame
			if cb_top_frame >= 0 and cb_home_frame < 0 and cell == cb + Vector3i(-3, 0, 0):
				cb_home_frame = frame
				break
	if cb_cart.get("ok", false):
		ws.try_dismantle(cb_cart_id, world.query_cell, AABB())
	# Blocked: a stone column across the grade shows red and lays nothing.
	var cb_blocked_entry := cb + Vector3i(0, 0, 3)
	for y in range(0, 4):
		world.set_cell(cb_blocked_entry + Vector3i(4, y, 0), 3)
	app.session.inventory.try_transaction({}, {"rail_climb": 20})
	app.session.inventory.select_hotbar(climb_slot)
	interaction.placement_rotation_quarters = 1
	interaction.begin_climb_at(cb_blocked_entry)
	var cb_red := 0
	for entry in interaction.drag_state().get("cells", []):
		if str(entry.state) == "blocked":
			cb_red += 1
	var cb_stations := ws.stations.size()
	var cb_refused := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var cb_nothing: bool = ws.stations.size() == cb_stations and cb_refused.get("reason") == "CLIMB_BLOCKED"
	# Save round-trip keeps the curve and the joints.
	var cb_saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var cb_restored := ws.restore(cb_saved, world.query_cell) if cb_saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var cb_restored_chain := CoasterRails.chain(ws.stations, cb + Vector3i(-3, 0, 0))
	var cb_round_trip: bool = cb_restored.get("ok", false) and cb_restored_chain.size() == cb_chain.size() and ws.station(ws.station_at_cell(cb_landing)).has("curve") and is_equal_approx(CoasterRails.ride_point(ws.station(ws.station_at_cell(cb_landing))).y, float(cb_landing.y) + 0.55)
	_record("T176_CLIMB", climb_content and cb_press.get("reason") == "DRAG_STARTED" and cb_press_mode == "climb" and cb_press_anchor == cb and cb_started.get("ok", false) and cb_default and cb_all_ok and cb_ends_ok and cb_shift_up and cb_shift_landing == cb + Vector3i(12, 6, 0) and cb_shift_down and cb_descent_ok and cb_six == 6 and cb_five == 5 and cb_six_again == 6 and cb_capped_ok and cb_laid.get("reason") == "CLIMB_PLACED" and cb_paid and cb_rails and cb_joined and cb_heights and cb_drawn and cb_cart.get("ok", false) and cb_top_frame > 0 and cb_home_frame > cb_top_frame and cb_min_up > 0.5 and cb_red > 0 and cb_nothing and cb_round_trip, "rail_climb (climb tool, no support, recipe 212 -> 8, icon) is registered; with Climb held a right-press starts the climb drag at the aim; the ghost is a complete climb of rail_loop curve pieces from the entry to a landing 8 ahead and 4 up; Shift-aiming at a 6-high column 12 ahead sets length 12 / rise 6 (landing on the column's top) and aiming into a pit 10 ahead sets length 10 / rise -3 (a descent, all pieces ok); 6 by key, X and C set the rise; a 20-item pack caps the length; release lays every piece for one item each; plain rails join the entry (behind) and the landing (ahead, 4 up) in one chain, both ends ride at rail height, the pieces draw the loop track; a mine cart rides up to the rail past the landing and back home with its up vector never dipping below 0.5; a ghost through a stone column shows red and lays nothing; the laid climb survives a save round-trip", {"content": climb_content, "press": cb_press.get("reason"), "press_mode": cb_press_mode, "press_anchor": cb_press_anchor, "started": cb_started.get("reason"), "default": cb_default, "all_ok": cb_all_ok, "ends_ok": cb_ends_ok, "count": cb_default_count, "shift_up": cb_shift_up, "shift_landing": cb_shift_landing, "shift_down": cb_shift_down, "descent_ok": cb_descent_ok, "six": cb_six, "five": cb_five, "six_again": cb_six_again, "capped": cb_capped, "capped_ok": cb_capped_ok, "in_pack": cb_in_pack, "laid": cb_laid.get("reason"), "landing": cb_landing, "paid": cb_paid, "rails": cb_rails, "rail_reasons": cb_rail_reasons, "chain": cb_chain.size(), "joined": cb_joined, "heights": cb_heights, "drawn": cb_drawn, "cart": cb_cart.get("reason"), "top_frame": cb_top_frame, "home_frame": cb_home_frame, "min_up": cb_min_up, "red": cb_red, "nothing": cb_nothing, "refused": cb_refused.get("reason"), "round_trip": cb_round_trip, "restored": cb_restored.get("reason")})

	# T177 the mountain: a stepped stone bank (x -5..4, one step per cell up
	# to 6 high), a climb from the plate onto its top (length 11, rise 6),
	# plain rails across the top, a descent back down (length 10, rise -6);
	# a cart rides up, across and down to the far rail and back; a climb too
	# low for the bank ghosts red and lays nothing.
	var mb := Vector3i(14, 0, 56)
	_level_ground(mb + Vector3i(-16, 0, -4), 33, 11, 14)
	app.session.inventory.try_transaction({}, {"rail_climb": 64, "rail": 12, "mine_cart": 1})
	for x in range(-5, 5):
		var height := mini(6, x + 6)
		for z in range(-3, 4):
			for y in range(0, height):
				world.set_cell(mb + Vector3i(x, y, z), 3)
	app.session.inventory.select_hotbar(climb_slot)
	interaction.placement_rotation_quarters = 1
	interaction.begin_climb_at(mb + Vector3i(-13, 0, 0))
	interaction.set_climb(13, 6)
	var mb_up := interaction.commit_drag_place()
	var mb_top: Vector3i = mb_up.get("changes", {}).get("landing", Vector3i.MAX)
	var mb_top_ok := mb_top == mb + Vector3i(0, 6, 0)
	var mb_rails := true
	var mb_rail_reasons: Array[String] = []
	for x in range(1, 4):
		var top_rail := ws.try_place("rail", mb + Vector3i(x, 6, 0), world.query_cell, AABB(), 0)
		mb_rails = mb_rails and bool(top_rail.get("ok", false))
		mb_rail_reasons.append(str(top_rail.get("reason")))
	interaction.begin_climb_at(mb + Vector3i(4, 6, 0))
	interaction.set_climb(10, -6)
	var mb_down := interaction.commit_drag_place()
	var mb_foot: Vector3i = mb_down.get("changes", {}).get("landing", Vector3i.MAX)
	var mb_foot_ok := mb_foot == mb + Vector3i(14, 0, 0)
	for end_cell: Vector3i in [mb + Vector3i(-14, 0, 0), mb + Vector3i(15, 0, 0)]:
		var end_rail := ws.try_place("rail", end_cell, world.query_cell, AABB(), 0)
		mb_rails = mb_rails and bool(end_rail.get("ok", false))
		mb_rail_reasons.append(str(end_rail.get("reason")))
	var mb_chain := CoasterRails.chain(ws.stations, mb + Vector3i(-14, 0, 0))
	var mb_chain_ok := mb_chain.has(mb + Vector3i(15, 0, 0)) and mb_chain.has(mb + Vector3i(2, 6, 0)) and mb_chain.size() == int(mb_up.get("changes", {}).get("count", 0)) + int(mb_down.get("changes", {}).get("count", 0)) + 5
	var mb_cart := ws.try_place("mine_cart", mb + Vector3i(-14, 1, 0), world.query_cell, AABB(), 0)
	var mb_cart_id := str(mb_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var mb_top_frame := -1
	var mb_far_frame := -1
	var mb_home_frame := -1
	var mb_min_up := 1.0
	if app.session.coaster_carts != null:
		for frame in range(1500):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(mb_cart_id)
			var mb_rig: Node3D = app.session.coaster_carts.cart_rig(mb_cart_id)
			if mb_rig != null:
				mb_min_up = minf(mb_min_up, mb_rig.global_basis.y.y)
			if mb_top_frame < 0 and cell == mb + Vector3i(2, 6, 0):
				mb_top_frame = frame
			if mb_top_frame >= 0 and mb_far_frame < 0 and cell == mb + Vector3i(15, 0, 0):
				mb_far_frame = frame
			if mb_far_frame >= 0 and mb_home_frame < 0 and cell == mb + Vector3i(-14, 0, 0):
				mb_home_frame = frame
				break
	if mb_cart.get("ok", false):
		ws.try_dismantle(mb_cart_id, world.query_cell, AABB())
	# Too low: a climb of rise 2 on the next lane runs into the bank.
	interaction.begin_climb_at(mb + Vector3i(-13, 0, 2))
	interaction.set_climb(13, 2)
	var mb_red := 0
	for entry in interaction.drag_state().get("cells", []):
		if str(entry.state) == "blocked":
			mb_red += 1
	var mb_stations := ws.stations.size()
	var mb_refused := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	interaction.set_climb(CoasterRails.CLIMB_LENGTH_DEFAULT, CoasterRails.CLIMB_RISE_DEFAULT)
	var mb_nothing: bool = ws.stations.size() == mb_stations and mb_refused.get("reason") == "CLIMB_BLOCKED"
	_record("T177_CLIMB_MOUNTAIN", mb_up.get("reason") == "CLIMB_PLACED" and mb_top_ok and mb_rails and mb_down.get("reason") == "CLIMB_PLACED" and mb_foot_ok and mb_chain_ok and mb_cart.get("ok", false) and mb_top_frame > 0 and mb_far_frame > mb_top_frame and mb_home_frame > mb_far_frame and mb_min_up > 0.5 and mb_red > 0 and mb_nothing, "a climb of length 13 / rise 6 from the plate lands on top of a 6-high stepped stone bank, three plain rails cross the top, a descent of length 10 / rise -6 lands back on the plate, and with a rail at each end the whole run is one chain; a mine cart rides up the climb, across the top, down the descent to the far rail and back home with its up vector never dipping below 0.5; a climb of rise 2 into the bank ghosts red cells and lays nothing", {"up": mb_up.get("reason"), "up_count": mb_up.get("changes", {}).get("count", 0), "top": mb_top, "rails": mb_rails, "rail_reasons": mb_rail_reasons, "down": mb_down.get("reason"), "down_count": mb_down.get("changes", {}).get("count", 0), "foot": mb_foot, "chain": mb_chain.size(), "chain_ok": mb_chain_ok, "cart": mb_cart.get("reason"), "top_frame": mb_top_frame, "far_frame": mb_far_frame, "home_frame": mb_home_frame, "min_up": mb_min_up, "red": mb_red, "nothing": mb_nothing, "refused": mb_refused.get("reason")})
	# T170 Smooth Switch (CoasterCraft card 2): with Smooth Switch held a
	# press ghosts an S-bend of rail_loop curve pieces from the entry to one
	# lane right six cells on; Shift-aim sets length and lanes (negative =
	# left); the pack caps the length; a blocked cell lays nothing; release
	# lays every piece for one item each; rails join both ends at rail
	# height; a mine cart rides through and back; save round-trip.
	await _test_smooth_switch()

	# T171 Crossing (CoasterCraft card 3): two S-bends whose lanes swap; the
	# shared middle cells carry both curves with two joint pairs; a cart
	# entering on A leaves on A's exit, one entering on B on B's; the shared
	# cell draws both tracks.
	await _test_crossing()
	# T173 the 90-degree curve (CoasterCraft card 4, 2026-09-20): with Curve
	# held a press ghosts a whole flat arc of rail_loop pieces from the entry
	# bending right; Shift-aim snaps the sweep and sets the radius (aiming
	# left mirrors it); the pack caps the radius; release lays all pieces for
	# one item each; both ends join plain rails; a cart rides through and back
	# leaning into the bend; a blocked ghost lays nothing; save round-trip.
	var cv := Vector3i(40, 0, 40)
	_level_ground(cv + Vector3i(-8, 0, -8), 24, 26, 9)
	app.session.inventory.try_transaction({}, {"rail": 12, "rail_curve": 40, "mine_cart": 1})
	var curve_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_curve":
			curve_slot = slot_index
	if curve_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(curve_slot, 4)
		curve_slot = 4
	app.session.inventory.select_hotbar(curve_slot)
	var curve_entity: Dictionary = registry.entity("rail_curve")
	var curve_content := str(curve_entity.get("coaster_tool", "")) == "curve" and (curve_entity.get("support_offsets", [1]) as Array).is_empty() and interaction.is_curve_item("rail_curve") and ItemIconCatalog.missing_item_ids(["rail_curve"]).is_empty()
	var curve_recipe_ok := false
	for recipe in registry.recipes_for("workbench"):
		if str(recipe.get("id", "")) == "rail_curve":
			curve_recipe_ok = int(recipe.get("recipe_book_order", -1)) == 211 and int(recipe.get("outputs", {}).get("rail_curve", 0)) == 8
	# Travel +x (rotation 1): right of travel is +z.
	interaction.placement_rotation_quarters = 1
	interaction.curve_radius = 4
	interaction.curve_sweep = 90
	interaction.curve_left = false
	var cv_press_origin := Vector3(cv) + Vector3(0.5, 2.0, 3.0)
	var cv_press := interaction.secondary_press_from_view(cv_press_origin, (Vector3(cv) + Vector3(0.5, 0.0, 0.5) - cv_press_origin).normalized())
	var cv_press_mode := str(interaction.drag_state().get("mode", ""))
	interaction.cancel_drag_place()
	var cv_started := interaction.begin_curve_at(cv)
	var cv_ghost := interaction.drag_state()
	var cv_ghost_cells: Array = cv_ghost.get("cells", [])
	var cv_ghost_ok := not cv_ghost_cells.is_empty()
	var cv_ghost_flat := true
	for entry in cv_ghost_cells:
		cv_ghost_ok = cv_ghost_ok and str(entry.state) == "ok" and str(entry.entity_id) == "rail_loop"
		cv_ghost_flat = cv_ghost_flat and Vector3i(entry.cell).y == cv.y
	var cv_layout := CoasterRails.curve_layout(cv, 1, 4.0, 90.0)
	var cv_exit: Vector3i = cv_layout.exit
	# A 90-degree bend of radius 4 to the right of +x travel exits 4 cells
	# on (+x) and 4 to the right (+z), heading +z.
	var cv_shape: bool = cv_exit == cv + Vector3i(4, 0, 4) and Vector3i(cv_ghost.get("curve_exit", Vector3i.ZERO)) == cv_exit and Vector3i(cv_layout.exit_cell_ahead) == cv_exit + Vector3i(0, 0, 1) and Vector3i(cv_layout.before) == cv + Vector3i(-1, 0, 0)
	var default_count := cv_ghost_cells.size()
	# Shift-aim (from above): 12 cells straight right of travel snaps a
	# 135-degree bend of radius 6; 12 cells ahead-left a 90-degree LEFT bend.
	interaction.update_drag_place(Vector3(cv) + Vector3(0.5, 6.0, 0.5 + 12.0), Vector3.DOWN, true)
	var aimed_135 := int(interaction.drag_state().get("curve_sweep", 0)) == 135 and int(interaction.drag_state().get("curve_radius", 0)) == 6 and not bool(interaction.drag_state().get("curve_left", true))
	interaction.update_drag_place(Vector3(cv) + Vector3(0.5 + 8.5, 6.0, 0.5 - 8.5), Vector3.DOWN, true)
	var aimed_left := int(interaction.drag_state().get("curve_sweep", 0)) == 90 and int(interaction.drag_state().get("curve_radius", 0)) == 6 and bool(interaction.drag_state().get("curve_left", false))
	var left_exit: Vector3i = interaction.drag_state().get("curve_exit", Vector3i.ZERO)
	var left_mirrored := left_exit == cv + Vector3i(6, 0, -6)
	# Straight ahead snaps 45 degrees; straight behind a U-turn.
	interaction.update_drag_place(Vector3(cv) + Vector3(0.5 + 8.0, 6.0, 0.5), Vector3.DOWN, true)
	var aimed_45 := int(interaction.drag_state().get("curve_sweep", 0)) == 45
	interaction.update_drag_place(Vector3(cv) + Vector3(0.5 - 8.0, 6.0, 0.5), Vector3.DOWN, true)
	var aimed_180 := int(interaction.drag_state().get("curve_sweep", 0)) == 180
	# Number keys and X / C set the radius; the pack (40 curves) caps it.
	interaction.set_curve_sweep(90, false)
	interaction.set_curve_radius(5)
	var five := int(interaction.drag_state().get("curve_radius", 0)) == 5
	interaction.curve_keys(false, true)
	interaction.curve_keys(false, false)
	var six := int(interaction.drag_state().get("curve_radius", 0)) == 6
	interaction.curve_keys(true, false)
	interaction.curve_keys(false, false)
	var five_again := int(interaction.drag_state().get("curve_radius", 0)) == 5
	interaction.set_curve_radius(30)
	var capped_radius := int(interaction.drag_state().get("curve_radius", 0))
	var curves_in_pack := app.session.inventory.count("rail_curve")
	var cv_capped_ok := capped_radius < 30 and CoasterRails.curve_piece_count(capped_radius, 90) <= curves_in_pack and CoasterRails.curve_piece_count(capped_radius + 1, 90) > curves_in_pack
	interaction.set_curve_radius(4)
	var cv_before := app.session.inventory.count("rail_curve")
	var cv_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var cv_paid := cv_before - app.session.inventory.count("rail_curve") == default_count
	# Plain rails behind the entry (-x) and beyond the exit (+z).
	var cv_rails := true
	for x in range(1, 4):
		cv_rails = cv_rails and bool(ws.try_place("rail", cv + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	for z in range(1, 4):
		cv_rails = cv_rails and bool(ws.try_place("rail", cv_exit + Vector3i(0, 0, z), world.query_cell, AABB(), 0).get("ok", false))
	var cv_chain := CoasterRails.chain(ws.stations, cv)
	var cv_joined := cv_chain.size() == default_count + 6 and cv_chain.has(cv_exit + Vector3i(0, 0, 3)) and cv_chain.has(cv + Vector3i(-3, 0, 0)) and (cv_chain.get(cv, []) as Array).size() == 2 and (cv_chain.get(cv_exit, []) as Array).size() == 2
	var cv_entry_record: Dictionary = ws.station(ws.station_at_cell(cv))
	var cv_exit_record: Dictionary = ws.station(ws.station_at_cell(cv_exit))
	var cv_ends_flush := CoasterRails.ride_point(cv_entry_record).is_equal_approx(Vector3(cv) + Vector3(0.5, 0.55, 0.5)) and CoasterRails.ride_point(cv_exit_record).is_equal_approx(Vector3(cv_exit) + Vector3(0.5, 0.55, 0.5))
	var cv_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(cv))
	var cv_drawn := cv_body != null and cv_body.get_node_or_null("LoopTrack") != null
	# The mid piece leans toward the centre by about the bank (0.35).
	var cv_center: Vector3 = cv_layout.center
	var cv_mid_cell: Vector3i = cv_layout.cells[int(cv_layout.cells.size() / 2.0)]
	var cv_mid_record: Dictionary = ws.station(ws.station_at_cell(cv_mid_cell))
	var cv_mid_up := TrackCurve.up_at(cv_mid_record.get("curve", {}), TrackCurve.piece_t(cv_mid_record))
	var cv_toward := cv_center - CoasterRails.ride_point(cv_mid_record)
	cv_toward.y = 0.0
	var cv_lean := cv_mid_up.y > 0.8 and cv_mid_up.dot(cv_toward.normalized()) > 0.3
	var cv_cart := ws.try_place("mine_cart", cv + Vector3i(-3, 1, 0), world.query_cell, AABB(), 0)
	var cv_cart_id := str(cv_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var cv_far := -1
	var cv_home := -1
	var cv_rig_lean := false
	if app.session.coaster_carts != null:
		for frame in range(600):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(cv_cart_id)
			if cell == cv_mid_cell:
				var cv_rig: Node3D = app.session.coaster_carts.cart_rig(cv_cart_id)
				var rig_up: Vector3 = cv_rig.global_basis.y
				cv_rig_lean = cv_rig_lean or (rig_up.y > 0.8 and rig_up.dot(cv_toward.normalized()) > 0.3)
			if cv_far < 0 and cell == cv_exit + Vector3i(0, 0, 3):
				cv_far = frame
			if cv_far >= 0 and cv_home < 0 and cell == cv + Vector3i(-3, 0, 0):
				cv_home = frame
				break
	if cv_cart.get("ok", false):
		ws.try_dismantle(cv_cart_id, world.query_cell, AABB())
	# Blocked: a stone block where the arc ends; nothing is laid.
	var cv_blocked_anchor := cv + Vector3i(0, 0, 12)
	world.set_cell(cv_blocked_anchor + Vector3i(4, 0, 4), 3)
	app.session.inventory.select_hotbar(curve_slot)
	interaction.placement_rotation_quarters = 1
	interaction.begin_curve_at(cv_blocked_anchor)
	var cv_red := 0
	for entry in interaction.drag_state().get("cells", []):
		if str(entry.state) == "blocked":
			cv_red += 1
	var cv_stations_before := ws.stations.size()
	var cv_refused := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var cv_nothing_laid: bool = ws.stations.size() == cv_stations_before and cv_refused.get("reason") == "CURVE_BLOCKED"
	var cv_saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var cv_restored := ws.restore(cv_saved, world.query_cell) if cv_saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var cv_restored_chain := CoasterRails.chain(ws.stations, cv)
	var cv_round_trip: bool = cv_restored.get("ok", false) and cv_restored_chain.size() == cv_chain.size() and ws.station(ws.station_at_cell(cv_mid_cell)).has("curve") and CoasterRails.ride_point(ws.station(ws.station_at_cell(cv_exit))).is_equal_approx(Vector3(cv_exit) + Vector3(0.5, 0.55, 0.5))
	_record("T173_CURVE_90", curve_content and curve_recipe_ok and cv_press.get("reason") == "DRAG_STARTED" and cv_press_mode == "curve" and cv_started.get("ok", false) and cv_ghost_ok and cv_ghost_flat and cv_shape and default_count >= 6 and aimed_135 and aimed_left and left_mirrored and aimed_45 and aimed_180 and five and six and five_again and cv_capped_ok and cv_laid.get("reason") == "CURVE_PLACED" and int(cv_laid.get("changes", {}).get("count", 0)) == default_count and cv_paid and cv_rails and cv_joined and cv_ends_flush and cv_drawn and cv_lean and cv_cart.get("ok", false) and cv_far > 0 and cv_home > cv_far and cv_rig_lean and cv_red > 0 and cv_nothing_laid and cv_round_trip, "rail_curve (curve tool, no support, icon, recipe 211 -> 8) is registered; with Curve held a right-press ghosts a flat 90-degree arc of rail_loop pieces bending right with radius 4 (entry heading +x exits 4 on and 4 right, heading +z); Shift-aim straight right snaps 135 degrees at half the distance, ahead-left a mirrored 90-degree LEFT bend, ahead 45, behind 180; 5 by key, C 6, X 5, 30 caps at what 40 curves pay for; release lays every piece for one item each; three rails behind and three beyond the exit chain through it with flush ends; the pieces draw the curve track and lean toward the centre by the bank; a cart rides to the far rail leaning into the bend and comes home; a stone block on the arc shows red and lays nothing; the laid curve survives a save round-trip", {"content": curve_content, "recipe": curve_recipe_ok, "press": cv_press.get("reason"), "press_mode": cv_press_mode, "started": cv_started.get("reason"), "ghost": cv_ghost_ok, "flat": cv_ghost_flat, "shape": cv_shape, "exit": cv_exit, "count": default_count, "aimed_135": aimed_135, "aimed_left": aimed_left, "left_exit": left_exit, "aimed_45": aimed_45, "aimed_180": aimed_180, "five": five, "six": six, "five_again": five_again, "capped_radius": capped_radius, "capped_ok": cv_capped_ok, "laid": cv_laid.get("reason"), "paid": cv_paid, "rails": cv_rails, "chain": cv_chain.size(), "joined": cv_joined, "flush": cv_ends_flush, "drawn": cv_drawn, "mid_up": cv_mid_up, "lean": cv_lean, "cart": cv_cart.get("reason"), "far": cv_far, "home": cv_home, "rig_lean": cv_rig_lean, "red": cv_red, "nothing_laid": cv_nothing_laid, "refused": cv_refused.get("reason"), "round_trip": cv_round_trip})

	# T174 the U-turn and two 45s: a 180-degree curve of radius 3 exits on
	# the lane 2R to the right heading back, joins rails at both ends and a
	# cart rides through; a 45-degree curve ends on a diagonal that a second
	# 45 continues (its entry takes the diagonal heading) into one chain that
	# turns 90 degrees in all and joins plain rails at both ends.
	var ut := Vector3i(-40, 0, 50)
	_level_ground(ut + Vector3i(-6, 0, -3), 14, 12, 9)
	app.session.inventory.try_transaction({}, {"rail": 16, "rail_curve": 64, "mine_cart": 1})
	app.session.inventory.select_hotbar(curve_slot)
	interaction.placement_rotation_quarters = 1
	interaction.begin_curve_at(ut)
	interaction.set_curve_sweep(180, false)
	interaction.set_curve_radius(3)
	var ut_ghost: Array = interaction.drag_state().get("cells", [])
	var ut_ghost_ok := not ut_ghost.is_empty()
	for entry in ut_ghost:
		ut_ghost_ok = ut_ghost_ok and str(entry.state) == "ok"
	var ut_laid := interaction.commit_drag_place()
	var ut_layout := CoasterRails.curve_layout(ut, 1, 3.0, 180.0)
	var ut_exit: Vector3i = ut_layout.exit
	var ut_shape: bool = ut_exit == ut + Vector3i(0, 0, 6) and Vector3i(ut_layout.exit_cell_ahead) == ut_exit + Vector3i(-1, 0, 0)
	var ut_rails := true
	for x in range(1, 4):
		ut_rails = ut_rails and bool(ws.try_place("rail", ut + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
		ut_rails = ut_rails and bool(ws.try_place("rail", ut_exit + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var ut_chain := CoasterRails.chain(ws.stations, ut)
	var ut_joined := ut_chain.size() == ut_ghost.size() + 6 and ut_chain.has(ut_exit + Vector3i(-3, 0, 0)) and (ut_chain.get(ut, []) as Array).size() == 2 and (ut_chain.get(ut_exit, []) as Array).size() == 2
	var ut_cart := ws.try_place("mine_cart", ut + Vector3i(-3, 1, 0), world.query_cell, AABB(), 0)
	var ut_cart_id := str(ut_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var ut_far := -1
	var ut_home := -1
	if app.session.coaster_carts != null:
		for frame in range(600):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(ut_cart_id)
			if ut_far < 0 and cell == ut_exit + Vector3i(-3, 0, 0):
				ut_far = frame
			if ut_far >= 0 and ut_home < 0 and cell == ut + Vector3i(-3, 0, 0):
				ut_home = frame
				break
	if ut_cart.get("ok", false):
		ws.try_dismantle(ut_cart_id, world.query_cell, AABB())
	# Two 45s: the first travelling -x bends right to a diagonal (-x, -z)
	# end; the second, pressed on that diagonal cell, takes the diagonal
	# heading and bends right to -z.
	var fa := Vector3i(-42, 0, 26)
	_level_ground(fa + Vector3i(-12, 0, -10), 18, 14, 9)
	interaction.placement_rotation_quarters = 3
	interaction.begin_curve_at(fa)
	interaction.set_curve_sweep(45, false)
	interaction.set_curve_radius(6)
	var fa_laid := interaction.commit_drag_place()
	var fa_layout := CoasterRails.curve_layout(fa, 3, 6.0, 45.0)
	var fa_exit: Vector3i = fa_layout.exit
	var fa_ahead: Vector3i = fa_layout.exit_cell_ahead
	var fa_diagonal := fa_ahead - fa_exit == Vector3i(-1, 0, -1)
	# A plain rail on the diagonal cell does not join (documented limit).
	var fa_rail := ws.try_place("rail", fa_ahead, world.query_cell, AABB(), 0)
	var fa_rail_alone := CoasterRails.chain(ws.stations, fa_ahead).size() == 1
	if fa_rail.get("ok", false):
		ws.try_dismantle(str(fa_rail.get("details", {}).get("station", {}).get("instance_id", "")), world.query_cell, AABB())
	interaction.placement_rotation_quarters = 0
	interaction.begin_curve_at(fa_ahead)
	var fb_state := interaction.drag_state()
	var fb_diagonal_entry := bool(fb_state.get("curve_diagonal_entry", false))
	var fb_laid := interaction.commit_drag_place()
	var fb_exit: Vector3i = fb_state.get("curve_exit", Vector3i.ZERO)
	var fb_layout := CoasterRails.curve_layout(fa_ahead, 0, 6.0, 45.0, false, Vector3(-1.0, 0.0, -1.0).normalized())
	var fb_heading: Vector3 = fb_layout.exit_heading
	var fb_turns_to_z := fb_heading.is_equal_approx(Vector3(0.0, 0.0, -1.0)) and Vector3i(fb_layout.exit_cell_ahead) == fb_exit + Vector3i(0, 0, -1)
	var fb_rails := true
	for x in range(1, 4):
		fb_rails = fb_rails and bool(ws.try_place("rail", fa + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	for z in range(1, 4):
		fb_rails = fb_rails and bool(ws.try_place("rail", fb_exit + Vector3i(0, 0, -z), world.query_cell, AABB(), 0).get("ok", false))
	var fb_chain := CoasterRails.chain(ws.stations, fa)
	var fb_joined := fb_chain.has(fa_exit) and fb_chain.has(fa_ahead) and fb_chain.has(fb_exit) and fb_chain.has(fb_exit + Vector3i(0, 0, -3)) and fb_chain.has(fa + Vector3i(3, 0, 0)) and fb_chain.size() == int(fa_laid.get("changes", {}).get("count", 0)) + int(fb_laid.get("changes", {}).get("count", 0)) + 6
	var fb_cart := ws.try_place("mine_cart", fa + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	var fb_cart_id := str(fb_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var fb_far := -1
	if app.session.coaster_carts != null:
		for frame in range(600):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			if app.session.coaster_carts.rider_cell(fb_cart_id) == fb_exit + Vector3i(0, 0, -3):
				fb_far = frame
				break
	if fb_cart.get("ok", false):
		ws.try_dismantle(fb_cart_id, world.query_cell, AABB())
	_record("T174_UTURN_AND_45S", ut_ghost_ok and ut_laid.get("reason") == "CURVE_PLACED" and ut_shape and ut_rails and ut_joined and ut_cart.get("ok", false) and ut_far > 0 and ut_home > ut_far and fa_laid.get("reason") == "CURVE_PLACED" and fa_diagonal and fa_rail.get("ok", false) and fa_rail_alone and fb_diagonal_entry and fb_laid.get("reason") == "CURVE_PLACED" and fb_turns_to_z and fb_rails and fb_joined and fb_cart.get("ok", false) and fb_far > 0, "a 180-degree curve of radius 3 entered heading +x exits 6 cells to the right (2R) heading -x and joins three rails at each end; a cart rides to the far rail and home; a 45-degree curve of radius 6 ends on the diagonal (-x, -z) cell, which a plain rail cannot join; a Curve pressed on that cell takes the diagonal heading and its 45 bends to -z, and the two 45s with rails behind and beyond chain as one track a cart rides to the far end", {"ghost": ut_ghost_ok, "laid": ut_laid.get("reason"), "exit": ut_exit, "shape": ut_shape, "rails": ut_rails, "chain": ut_chain.size(), "joined": ut_joined, "cart": ut_cart.get("reason"), "far": ut_far, "home": ut_home, "fa_laid": fa_laid.get("reason"), "fa_exit": fa_exit, "fa_ahead": fa_ahead, "fa_diagonal": fa_diagonal, "fa_rail": fa_rail.get("reason"), "fa_rail_alone": fa_rail_alone, "fb_diagonal_entry": fb_diagonal_entry, "fb_laid": fb_laid.get("reason"), "fb_exit": fb_exit, "fb_heading": fb_heading, "fb_turns_to_z": fb_turns_to_z, "fb_rails": fb_rails, "fb_chain": fb_chain.size(), "fb_joined": fb_joined, "fb_cart": fb_cart.get("reason"), "fb_far": fb_far})
	# T179 track auto-clear (CoasterCraft card 6): with the setting off a
	# loop ghost over stone, water and castle stone shows those cells red and
	# is refused; on, the stone cell alone turns amber ("clear"), water and
	# castle stone stay red; with only the stone in the way release mines it
	# (the pack gains the stone), lays every piece and reports the count; a
	# rail line through a dirt bump clears it too; the setting persists in
	# settings.cfg and a fresh store reads it back.
	var clear_anchor := Vector3i(-14, 0, 66)
	var clear_layout := CoasterRails.helix_layout(clear_anchor, 3, 8)
	var clear_cells: Array[Vector3i] = clear_layout.cells
	# This plate lies far from the spawn: level it once its chunks are in.
	var plate_loaded := await _wait_levelled(clear_anchor + Vector3i(-12, 0, -4), 22, 8, 14, clear_cells)
	var stone_cell := Vector3i.MAX
	var water_cell := Vector3i.MAX
	var castle_cell := Vector3i.MAX
	for cell: Vector3i in clear_cells:
		if cell.y == clear_anchor.y + 3 and stone_cell == Vector3i.MAX:
			stone_cell = cell
		elif cell.y == clear_anchor.y + 2 and water_cell == Vector3i.MAX:
			water_cell = cell
		elif cell.y == clear_anchor.y + 1 and castle_cell == Vector3i.MAX and cell != water_cell:
			castle_cell = cell
	world.set_cell(stone_cell, 3)
	world.set_cell(water_cell, 12)
	world.set_cell(castle_cell, 8)
	app.session.inventory.try_transaction({}, {"rail_loop": 60, "rail": 8})
	loop_slot = _hotbar_slot_for("rail_loop", 2)
	var auto_clear_off: bool = not interaction.auto_clear and not app.settings.track_auto_clear
	interaction.placement_rotation_quarters = 3
	interaction.begin_coaster_loop_at(clear_anchor)
	interaction.set_loop_diameter(8)
	var off_states: Dictionary = {}
	for entry in interaction.drag_state().get("cells", []):
		off_states[entry.cell] = str(entry.state)
	var off_red: bool = off_states.get(stone_cell, "") == "blocked" and off_states.get(water_cell, "") == "blocked" and off_states.get(castle_cell, "") == "blocked"
	var off_red_count := 0
	for cell: Vector3i in off_states:
		if str(off_states[cell]) == "blocked":
			off_red_count += 1
	var off_stations := ws.stations.size()
	var off_refused := interaction.commit_drag_place()
	var off_nothing: bool = off_refused.get("reason") == "LOOP_BLOCKED" and ws.stations.size() == off_stations and int(world.query_cell(stone_cell).get("voxel_id", 0)) == 3
	# The pause-menu toggle turns it on (settings.cfg) and the session mirrors it.
	app._toggle_track_auto_clear()
	var mirrored: bool = app.settings.track_auto_clear and interaction.auto_clear and app.track_auto_clear_button.text.ends_with("on")
	var config := ConfigFile.new()
	var persisted: bool = config.load(app.data_root.path_join("settings.cfg")) == OK and bool(config.get_value("track", "auto_clear", false))
	var fresh_store := SettingsStore.new(app.data_root)
	fresh_store.load_and_apply()
	var reloaded: bool = fresh_store.track_auto_clear
	interaction.placement_rotation_quarters = 3
	interaction.begin_coaster_loop_at(clear_anchor)
	interaction.set_loop_diameter(8)
	var on_states: Dictionary = {}
	var on_clear_cells: Array = []
	for entry in interaction.drag_state().get("cells", []):
		on_states[entry.cell] = str(entry.state)
		if str(entry.state) == "clear":
			on_clear_cells.append(entry.get("clear", []))
	var on_amber: bool = on_states.get(stone_cell, "") == "clear" and on_states.get(water_cell, "") == "blocked" and on_states.get(castle_cell, "") == "blocked"
	var on_amber_exact: bool = on_clear_cells.size() == 1 and on_clear_cells[0] is Array and (on_clear_cells[0] as Array).size() == 1 and on_clear_cells[0][0] == stone_cell
	var still_refused := interaction.commit_drag_place()
	var water_stays: bool = still_refused.get("reason") == "LOOP_BLOCKED" and ws.stations.size() == off_stations and int(world.query_cell(stone_cell).get("voxel_id", 0)) == 3
	# Only the stone in the way: release mines it and lays the loop.
	world.set_cell(water_cell, 0)
	world.set_cell(castle_cell, 0)
	interaction.placement_rotation_quarters = 3
	interaction.begin_coaster_loop_at(clear_anchor)
	interaction.set_loop_diameter(8)
	var clear_only := 0
	var clear_blocked := 0
	for entry in interaction.drag_state().get("cells", []):
		if str(entry.state) == "clear":
			clear_only += 1
		elif str(entry.state) == "blocked":
			clear_blocked += 1
	var stone_before := app.session.inventory.count("stone")
	var loops_before_clear := app.session.inventory.count("rail_loop")
	var cleared_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var cleared_changes: Dictionary = cleared_laid.get("changes", {})
	var clear_ok: bool = cleared_laid.get("reason") == "LOOP_PLACED" and int(cleared_changes.get("count", 0)) == clear_cells.size() and int(cleared_changes.get("cleared", 0)) == 1 and int(world.query_cell(stone_cell).get("voxel_id", 3)) == 0 and app.session.inventory.count("stone") == stone_before + 1 and loops_before_clear - app.session.inventory.count("rail_loop") == clear_cells.size() and not ws.station_at_cell(stone_cell).is_empty()
	# A rail line through a dirt bump: the bump turns amber and is mined.
	var line_anchor := clear_anchor + Vector3i(6, 0, 2)
	world.set_cell(line_anchor + Vector3i(-2, 0, 0), 2)
	var rail_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail":
			rail_slot = slot_index
	if rail_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(rail_slot, 3)
		rail_slot = 3
	app.session.inventory.select_hotbar(rail_slot)
	interaction.begin_entity_line_at(line_anchor)
	interaction.set_drag_end(line_anchor + Vector3i(-3, 0, 0))
	var line_states: Dictionary = {}
	for entry in interaction.drag_state().get("cells", []):
		line_states[entry.cell] = str(entry.state)
	var dirt_before := app.session.inventory.count("dirt")
	var line_laid := interaction.commit_drag_place()
	var line_ok: bool = line_states.get(line_anchor + Vector3i(-2, 0, 0), "") == "clear" and line_states.get(line_anchor, "") == "ok" and line_laid.get("reason") == "LINE_PLACED" and int(line_laid.get("changes", {}).get("count", 0)) == 4 and int(line_laid.get("changes", {}).get("cleared", 0)) == 1 and app.session.inventory.count("dirt") == dirt_before + 1 and int(world.query_cell(line_anchor + Vector3i(-2, 0, 0)).get("voxel_id", 2)) == 0
	_record("T179_TRACK_AUTO_CLEAR", plate_loaded and auto_clear_off and off_red and off_red_count == 3 and off_nothing and mirrored and persisted and reloaded and on_amber and on_amber_exact and water_stays and clear_only == 1 and clear_blocked == 0 and clear_ok and line_ok, "auto-clear off: a diameter-8 loop ghost over a stone, a water and a castle-stone cell shows exactly those three red and release lays nothing; the pause-menu toggle turns it on, writes [track] auto_clear to settings.cfg (a fresh store reads it back) and the session mirrors it; on: the stone cell alone is amber (its clear list is exactly that cell), water and castle stone stay red and the loop is still refused; with only the stone in the way release mines it (+1 stone in the pack, reports cleared 1), lays every piece paying one loop each; a rail line through a dirt bump shows the bump amber, mines it (+1 dirt) and lays four rails", {"plate_loaded": plate_loaded, "auto_clear_off": auto_clear_off, "off_red": off_red, "off_states": str(off_states), "off_red_count": off_red_count, "off_nothing": off_nothing, "off_refused": off_refused.get("reason"), "mirrored": mirrored, "persisted": persisted, "reloaded": reloaded, "on_amber": on_amber, "on_amber_exact": on_amber_exact, "on_clear_cells": str(on_clear_cells), "water_stays": water_stays, "clear_only": clear_only, "clear_blocked": clear_blocked, "clear_ok": clear_ok, "cleared_laid": cleared_laid.get("reason"), "cleared": cleared_changes.get("cleared"), "count": cleared_changes.get("count"), "expected_count": clear_cells.size(), "stone_cell": stone_cell, "line_ok": line_ok, "line_laid": line_laid.get("reason"), "line_states": str(line_states)})
	app._toggle_track_auto_clear()

	# T180 automatic trestle supports (CoasterCraft card 8): the diameter-8
	# loop just laid grows stone posts under its lower pieces down to the
	# plate, none under the pieces over the top (inverted) and none under a
	# piece standing right above another piece of the same curve.
	var lower_posts := 0
	var lower_missing: Array = []
	var top_posts: Array = []
	var stacked_posts: Array = []
	var stacked_checked := 0
	var post_reaches := true
	var top_y := clear_anchor.y
	for cell: Vector3i in clear_cells:
		top_y = maxi(top_y, cell.y)
	for cell: Vector3i in clear_cells:
		var body: Node3D = app.session._station_visuals.get(ws.station_at_cell(cell))
		var support: Node = body.find_child("Support", true, false) if body != null else null
		var below_same := clear_cells.has(cell + Vector3i(0, -1, 0)) or clear_cells.has(cell + Vector3i(0, -2, 0))
		if cell.y == top_y:
			if support != null:
				top_posts.append(cell)
		elif below_same:
			stacked_checked += 1
			if support != null:
				stacked_posts.append(cell)
		elif cell.y >= clear_anchor.y + 1 and cell.y <= clear_anchor.y + 3:
			if support == null:
				lower_missing.append(cell)
			else:
				lower_posts += 1
				post_reaches = post_reaches and absf(_post_bottom(support) - float(clear_anchor.y)) < 0.05
	_record("T180_TRESTLE_SUPPORTS", lower_posts >= 4 and lower_missing.is_empty() and top_posts.is_empty() and stacked_checked > 0 and stacked_posts.is_empty() and post_reaches, "every lower piece of the laid diameter-8 loop (1-3 cells up, not over another piece of the loop) carries a Support node whose post reaches the plate; the top row has none; a piece within two cells above another piece of the same loop has none", {"lower_posts": lower_posts, "lower_missing": str(lower_missing), "top_posts": str(top_posts), "stacked_checked": stacked_checked, "stacked_posts": str(stacked_posts), "post_reaches": post_reaches, "top_y": top_y})


## Rendered evidence: a lead-in, a radius-3 loop and its exit with a cart on
## the track, beside a slope run climbing a step, in one 1280x720 view.
func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	await _wait_region_loaded()
	var player := app.session.player
	player.deactivate()
	# Paused: the carts advance only by the fixed steps below, so the loop cart
	# is parked over the top of the loop for the picture.
	app.session.simulation_paused = true
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var origin := Vector3i(-2, 0, 36)
	_level_ground(origin + Vector3i(-10, 0, -6), 22, 14, 14)
	app.session.inventory.try_transaction({}, {"rail_loop": 64, "mine_cart": 2, "rail": 12, "rail_slope": 2})
	var loop_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_loop":
			loop_slot = slot_index
	if loop_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(loop_slot, 2)
		loop_slot = 2
	loop_slot = _hotbar_slot_for("rail_loop", 2)
	interaction.placement_rotation_quarters = 3
	interaction.set_loop_size(6)
	interaction.begin_coaster_loop_at(origin)
	var committed := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	for x in range(1, 4):
		ws.try_place("rail", origin + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var cart := ws.try_place("mine_cart", origin + Vector3i(2, 1, 0), world.query_cell, AABB(), 0)
	# A slope run in front: two rails, a slope, two rails on a stone step.
	var step_base := origin + Vector3i(2, 0, 5)
	for x in range(3, 5):
		world.set_cell(step_base + Vector3i(x, 0, 0), 3)
	var slope_ok := true
	for x in [0, 1]:
		slope_ok = slope_ok and bool(ws.try_place("rail", step_base + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	slope_ok = slope_ok and bool(ws.try_place("rail_slope", step_base + Vector3i(2, 0, 0), world.query_cell, AABB(), 1).get("ok", false))
	for x in [3, 4]:
		slope_ok = slope_ok and bool(ws.try_place("rail", step_base + Vector3i(x, 1, 0), world.query_cell, AABB(), 0).get("ok", false))
	var slope_cart := ws.try_place("mine_cart", step_base + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var cart_id := str(cart.get("details", {}).get("station", {}).get("instance_id", ""))
	if app.session.coaster_carts != null:
		# Through the entry, the first switcher, the base and up the far
		# side to the top of the circle (about 18 cells at speed 3).
		for _frame in range(900):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var top_now := app.session.coaster_carts.rider_cell(cart_id)
			if top_now.y >= origin.y + 5:
				break
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(origin) + Vector3(-1.5, 5.0, 14.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = 0.05
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("coaster-rails.png")
	if image == null:
		_record("T163_COASTER_RENDERED", false, "a lead-in, loop and exit with a cart render in one 1280x720 view", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var loop_parts := 0
	for station_id: String in ws.stations.keys():
		if str(ws.stations[station_id].get("entity_id", "")) == "rail_loop":
			var body: Node3D = app.session._station_visuals.get(station_id)
			if body != null:
				loop_parts += body.find_children("*", "MeshInstance3D", true, false).size()
	var cart_body: Node3D = app.session._station_visuals.get(cart_id)
	var cart_parts := cart_body.find_children("*", "MeshInstance3D", true, false).size() if cart_body != null else 0
	var cart_cell := app.session.coaster_carts.rider_cell(cart_id) if app.session.coaster_carts != null else Vector3i(0, -9999, 0)
	_record("T163_COASTER_RENDERED", committed.get("reason") == "LOOP_PLACED" and cart.get("ok", false) and slope_ok and slope_cart.get("ok", false) and error == OK and image.get_size() == Vector2i(1280, 720) and loop_parts >= 60 and cart_parts >= 18 and cart_cell.y >= origin.y + 5, "a diameter-6 true loop renders with a mine cart on it, beside a slope run climbing a step with its own cart, in one 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "committed": committed.get("reason"), "cart": cart.get("reason"), "slope_ok": slope_ok, "slope_cart": slope_cart.get("reason"), "loop_parts": loop_parts, "cart_parts": cart_parts, "cart_cell": cart_cell})
	await _render_smooth_pieces()
	await _render_climb()
	await _render_curves()
	await _render_supports()


## T172: a Smooth Switch and a Crossing with lead-in / exit rails and a
## mine cart on each, seen from above and behind (`coaster-smooth.png`).
func _render_smooth_pieces() -> void:
	var player := app.session.player
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var plate := Vector3i(10, 0, 30)
	_level_ground(plate, 24, 14, 9)
	app.session.inventory.try_transaction({}, {"rail_bend": 16, "rail_cross": 32, "rail": 16, "mine_cart": 2})
	interaction.placement_rotation_quarters = 1
	var bend_entry := Vector3i(14, 0, 33)
	_hotbar_slot_for("rail_bend", 4)
	interaction.set_curve_size(6, 1)
	interaction.begin_curve_tool_at(bend_entry)
	var bend := interaction.commit_drag_place()
	var bend_exit := bend_entry + Vector3i(6, 0, 1)
	for x in range(1, 4):
		ws.try_place("rail", bend_entry - Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
		ws.try_place("rail", bend_exit + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var bend_cart := ws.try_place("mine_cart", bend_entry + Vector3i(-3, 1, 0), world.query_cell, AABB(), 0)
	var cross_entry := Vector3i(14, 0, 38)
	_hotbar_slot_for("rail_cross", 5)
	interaction.set_curve_size(8, 2)
	interaction.begin_curve_tool_at(cross_entry)
	var cross := interaction.commit_drag_place()
	var layout := CoasterRails.cross_layout(cross_entry, 1, 8, 2)
	for x in range(1, 4):
		for cell: Vector3i in [Vector3i(layout.entry_a) - Vector3i(x, 0, 0), Vector3i(layout.entry_b) - Vector3i(x, 0, 0), Vector3i(layout.exit_a) + Vector3i(x, 0, 0), Vector3i(layout.exit_b) + Vector3i(x, 0, 0)]:
			ws.try_place("rail", cell, world.query_cell, AABB(), 0)
	var cross_cart := ws.try_place("mine_cart", Vector3i(layout.entry_b) + Vector3i(-3, 1, 0), world.query_cell, AABB(), 0)
	interaction.placement_rotation_quarters = 0
	var bend_cart_id := str(bend_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var cross_cart_id := str(cross_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	if app.session.coaster_carts != null:
		for _frame in range(150):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(bend_entry) + Vector3(4.0, 7.5, 16.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = -0.5
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("coaster-smooth.png")
	if image == null:
		_record("T172_SMOOTH_RENDERED", false, "a smooth switch and a crossing render with a cart on each in one 1280x720 view", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var track_parts := 0
	var two_track_cells := 0
	for station_id: String in ws.stations.keys():
		var record: Dictionary = ws.stations[station_id]
		if str(record.get("entity_id", "")) == "rail_loop" and Vector3i(record.get("anchor", Vector3i.ZERO)).x >= plate.x:
			var body: Node3D = app.session._station_visuals.get(station_id)
			if body != null:
				track_parts += body.find_children("*", "MeshInstance3D", true, false).size()
				if body.get_node_or_null("LoopTrackB") != null:
					two_track_cells += 1
	var bend_cell := app.session.coaster_carts.rider_cell(bend_cart_id) if app.session.coaster_carts != null else Vector3i(0, -9999, 0)
	var cross_cell := app.session.coaster_carts.rider_cell(cross_cart_id) if app.session.coaster_carts != null else Vector3i(0, -9999, 0)
	_record("T172_SMOOTH_RENDERED", bend.get("reason") == "BEND_PLACED" and cross.get("reason") == "CROSS_PLACED" and bend_cart.get("ok", false) and cross_cart.get("ok", false) and error == OK and image.get_size() == Vector2i(1280, 720) and track_parts >= 80 and two_track_cells >= 1 and bend_cell.x > bend_entry.x and cross_cell.x > cross_entry.x, "a six-long smooth switch and an eight-long two-lane crossing render with lead-in and exit rails and a mine cart riding each, the shared cells drawing both tracks, in one 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "bend": bend.get("reason"), "cross": cross.get("reason"), "bend_cart": bend_cart.get("reason"), "cross_cart": cross_cart.get("reason"), "track_parts": track_parts, "two_track_cells": two_track_cells, "bend_cell": bend_cell, "cross_cell": cross_cell})


func _hotbar_slot_for(item_id: String, fallback: int) -> int:
	var slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == item_id:
			slot = slot_index
	if slot < 0:
		return -1
	if slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(slot, fallback)
		slot = fallback
	app.session.inventory.select_hotbar(slot)
	return slot


## Runs `frames` cart steps; returns {reached: {cell: frame}} for `watch`.
func _ride_cart(cart_id: String, watch: Array[Vector3i], frames: int, stop_at: Vector3i = Vector3i.MAX) -> Dictionary:
	var reached: Dictionary = {}
	var visited: Dictionary = {}
	if app.session.coaster_carts == null:
		return {"reached": reached, "visited": visited}
	for frame in range(frames):
		app.session.coaster_carts.advance(1.0 / 30.0, false)
		var cell := app.session.coaster_carts.rider_cell(cart_id)
		visited[cell] = true
		if watch.has(cell) and not reached.has(cell):
			reached[cell] = frame
		if cell == stop_at:
			break
	return {"reached": reached, "visited": visited}


func _test_smooth_switch() -> void:
	var registry := app.session.registry
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var bend: Dictionary = registry.entity("rail_bend")
	var bend_order := -1
	var bend_output := 0
	for recipe in registry.recipes_for("workbench"):
		if str(recipe.get("id", "")) == "rail_bend":
			bend_order = int(recipe.get("recipe_book_order", -1))
			bend_output = int(recipe.get("outputs", {}).get("rail_bend", 0))
	var content_ok: bool = str(bend.get("coaster_tool", "")) == "bend" and (bend.get("support_offsets", [1]) as Array).is_empty() and interaction.is_smooth_bend_item("rail_bend") and not interaction.is_linear_entity_item("rail_bend") and bend_order == 209 and bend_output == 8 and registry.max_stack("rail_bend") == 64 and ItemIconCatalog.missing_item_ids(["rail_bend"]).is_empty()
	var bx := Vector3i(8, 0, 30)
	_level_ground(bx + Vector3i(-4, 0, -4), 24, 12, 9)
	app.session.inventory.try_transaction({}, {"rail": 12, "rail_bend": 24, "mine_cart": 1})
	var placed := true
	for x in range(1, 4):
		placed = placed and bool(ws.try_place("rail", bx - Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var slot := _hotbar_slot_for("rail_bend", 4)
	interaction.placement_rotation_quarters = 1
	interaction.creative = false
	interaction.set_curve_size(CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
	# The right-press path itself starts the bend drag.
	var press_origin := Vector3(bx) + Vector3(0.5, 3.0, 0.5)
	var press_started := interaction.secondary_press_from_view(press_origin, Vector3.DOWN)
	var press_mode := str(interaction.drag_state().get("mode", ""))
	interaction.cancel_drag_place()
	var started := interaction.begin_curve_tool_at(bx)
	var ghost := interaction.drag_state()
	var ghost_cells: Array = ghost.get("cells", [])
	var ghost_ok := not ghost_cells.is_empty()
	for entry in ghost_cells:
		ghost_ok = ghost_ok and str(entry.state) == "ok" and str(entry.entity_id) == "rail_loop" and (entry.get("extra", {}) as Dictionary).has("curve")
	var default_exit := bx + Vector3i(6, 0, 1)
	var default_count := ghost_cells.size()
	var default_shape: bool = default_count == CoasterRails.bend_piece_count(6, 1) and not ghost_cells.is_empty() and Vector3i(ghost_cells[0].cell) == bx and Vector3i(ghost_cells[ghost_cells.size() - 1].cell) == default_exit and int(ghost.get("curve_length", 0)) == 6 and int(ghost.get("curve_lanes", 0)) == 1
	# Shift-aim: 10 ahead and 3 to the LEFT of travel (+x travel: left is -z).
	interaction.update_drag_place(Vector3(bx) + Vector3(10.5, 3.0, -2.5), Vector3.DOWN, true)
	var sized := interaction.drag_state()
	var sized_cells: Array = sized.get("cells", [])
	var sized_ok: bool = int(sized.get("curve_length", 0)) == 10 and int(sized.get("curve_lanes", 0)) == -3 and not sized_cells.is_empty() and Vector3i(sized_cells[sized_cells.size() - 1].cell) == bx + Vector3i(10, 0, -3)
	# X / C and number keys change the length only.
	interaction.coaster_loop_keys(false, true)
	interaction.coaster_loop_keys(false, false)
	var eleven := int(interaction.drag_state().get("curve_length", 0))
	interaction.coaster_loop_keys(true, false)
	interaction.coaster_loop_keys(false, false)
	var ten := int(interaction.drag_state().get("curve_length", 0))
	# The pack caps the length: 24 items cannot pay a 40-long bend.
	interaction.set_curve_length(40)
	var capped := int(interaction.drag_state().get("curve_length", 0))
	var in_pack := app.session.inventory.count("rail_bend")
	var capped_ok: bool = capped < 40 and CoasterRails.bend_piece_count(capped, -3) <= in_pack and CoasterRails.bend_piece_count(capped + 1, -3) > in_pack
	interaction.set_curve_size(6, 1)
	# A stone block on the path: red, and release lays nothing.
	world.set_cell(bx + Vector3i(1, 0, 0), 3)
	interaction.cancel_drag_place()
	interaction.begin_curve_tool_at(bx)
	var red := 0
	for entry in interaction.drag_state().get("cells", []):
		if str(entry.state) == "blocked":
			red += 1
	var stations_before := ws.stations.size()
	var refused := interaction.commit_drag_place()
	var nothing_laid: bool = refused.get("reason") == "BEND_BLOCKED" and ws.stations.size() == stations_before
	world.set_cell(bx + Vector3i(1, 0, 0), 0)
	interaction.begin_curve_tool_at(bx)
	var before := app.session.inventory.count("rail_bend")
	var laid := interaction.commit_drag_place()
	var paid: bool = before - app.session.inventory.count("rail_bend") == default_count
	for x in range(1, 4):
		placed = placed and bool(ws.try_place("rail", default_exit + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	# Control: a rail beside the entry on the exit lane must not join.
	placed = placed and bool(ws.try_place("rail", bx + Vector3i(0, 0, 1), world.query_cell, AABB(), 0).get("ok", false))
	var chain := CoasterRails.chain(ws.stations, bx - Vector3i(3, 0, 0))
	var chain_ok: bool = chain.size() == default_count + 6 and chain.has(default_exit + Vector3i(3, 0, 0)) and not chain.has(bx + Vector3i(0, 0, 1))
	var entry_record: Dictionary = ws.station(ws.station_at_cell(bx))
	var exit_record: Dictionary = ws.station(ws.station_at_cell(default_exit))
	var entry_point := CoasterRails.ride_point(entry_record)
	var exit_point := CoasterRails.ride_point(exit_record)
	var rail_height: bool = entry_point.is_equal_approx(Vector3(bx) + Vector3(0.5, 0.55, 0.5)) and exit_point.is_equal_approx(Vector3(default_exit) + Vector3(0.5, 0.55, 0.5))
	var mid_record: Dictionary = ws.station(ws.station_at_cell(bx + Vector3i(3, 0, 0)))
	var mid_point := CoasterRails.ride_point(mid_record)
	var mid_between: bool = not mid_record.is_empty() and mid_point.z > float(bx.z) + 0.5 and mid_point.z < float(bx.z) + 1.5 and absf(mid_point.y - 0.55) < 0.001
	var entry_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(bx))
	var drawn := entry_body != null and entry_body.get_node_or_null("LoopTrack") != null
	var cart := ws.try_place("mine_cart", bx + Vector3i(-3, 1, 0), world.query_cell, AABB(), 0)
	var cart_id := str(cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var far_cell := default_exit + Vector3i(3, 0, 0)
	var ride := _ride_cart(cart_id, [far_cell, bx - Vector3i(3, 0, 0)], 700)
	var far_frame := int(ride.reached.get(far_cell, -1))
	var rode := far_frame > 0
	var home_frame := -1
	if rode:
		home_frame = int(_ride_cart(cart_id, [bx - Vector3i(3, 0, 0)], 700).reached.get(bx - Vector3i(3, 0, 0), -1))
	if cart.get("ok", false):
		ws.try_dismantle(cart_id, world.query_cell, AABB())
	var saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(saved, world.query_cell) if saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var restored_chain := CoasterRails.chain(ws.stations, bx - Vector3i(3, 0, 0))
	var round_trip: bool = restored.get("ok", false) and restored_chain.size() == chain.size() and ws.station(ws.station_at_cell(bx)).has("curve")
	interaction.placement_rotation_quarters = 0
	_record("T170_SMOOTH_SWITCH", content_ok and placed and slot >= 0 and press_started.get("reason") == "DRAG_STARTED" and press_mode == "smooth_bend" and started.get("ok", false) and ghost_ok and default_shape and sized_ok and eleven == 11 and ten == 10 and capped_ok and red > 0 and nothing_laid and laid.get("reason") == "BEND_PLACED" and int(laid.get("changes", {}).get("count", 0)) == default_count and paid and chain_ok and rail_height and mid_between and drawn and cart.get("ok", false) and rode and home_frame > 0 and round_trip, "rail_bend (Smooth Switch, coaster_tool bend, order 209, 8 per craft, stack 64, icon) ghosts an S-bend of rail_loop curve pieces from the entry to one lane right six cells on; Shift-aim 10 ahead and 3 left sizes it (length 10, lanes -3, exit there); C / X make 11 / 10; the pack caps 40 to what 24 items pay for; a stone block on the path shows red and release lays nothing; release lays every piece for one item each; rails behind and ahead join into one chain while a rail beside the entry on the exit lane stays out; entry and exit ride at rail height and the middle rides between the lanes; the entry draws the loop track; a mine cart rides through to the far rail and back; the track survives a save round-trip", {"content_ok": content_ok, "placed": placed, "press": press_started.get("reason"), "press_mode": press_mode, "started": started.get("reason"), "ghost_ok": ghost_ok, "default_count": default_count, "default_shape": default_shape, "sized": [sized.get("curve_length"), sized.get("curve_lanes")], "sized_ok": sized_ok, "eleven": eleven, "ten": ten, "capped": capped, "capped_ok": capped_ok, "red": red, "refused": refused.get("reason"), "nothing_laid": nothing_laid, "laid": laid.get("reason"), "count": laid.get("changes", {}).get("count"), "paid": paid, "chain": chain.size(), "chain_ok": chain_ok, "entry_point": entry_point, "exit_point": exit_point, "mid_point": mid_point, "drawn": drawn, "cart": cart.get("reason"), "far_frame": far_frame, "home_frame": home_frame, "round_trip": round_trip, "restored": restored.get("reason")})


func _test_crossing() -> void:
	var registry := app.session.registry
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var cross: Dictionary = registry.entity("rail_cross")
	var cross_order := -1
	var cross_output := 0
	for recipe in registry.recipes_for("workbench"):
		if str(recipe.get("id", "")) == "rail_cross":
			cross_order = int(recipe.get("recipe_book_order", -1))
			cross_output = int(recipe.get("outputs", {}).get("rail_cross", 0))
	var content_ok: bool = str(cross.get("coaster_tool", "")) == "cross" and (cross.get("support_offsets", [1]) as Array).is_empty() and interaction.is_rail_cross_item("rail_cross") and cross_order == 210 and cross_output == 4 and registry.max_stack("rail_cross") == 32 and ItemIconCatalog.missing_item_ids(["rail_cross"]).is_empty()
	var cx := Vector3i(8, 0, 42)
	_level_ground(cx + Vector3i(-4, 0, -4), 24, 12, 9)
	app.session.inventory.try_transaction({}, {"rail": 16, "rail_cross": 32, "mine_cart": 2})
	var slot := _hotbar_slot_for("rail_cross", 5)
	interaction.placement_rotation_quarters = 1
	interaction.creative = false
	interaction.set_curve_size(CoasterRails.CROSS_DEFAULT_LENGTH, CoasterRails.CROSS_DEFAULT_LANES)
	var layout := CoasterRails.cross_layout(cx, 1, 8, 2)
	var entry_a: Vector3i = layout.entry_a
	var entry_b: Vector3i = layout.entry_b
	var exit_a: Vector3i = layout.exit_a
	var exit_b: Vector3i = layout.exit_b
	var shared: Array = layout.shared
	var lanes_swap: bool = entry_b == cx + Vector3i(0, 0, 2) and exit_a == cx + Vector3i(8, 0, 2) and exit_b == cx + Vector3i(8, 0, 0) and shared.size() >= 1
	var placed := true
	for x in range(1, 4):
		for cell: Vector3i in [entry_a - Vector3i(x, 0, 0), entry_b - Vector3i(x, 0, 0), exit_a + Vector3i(x, 0, 0), exit_b + Vector3i(x, 0, 0)]:
			placed = placed and bool(ws.try_place("rail", cell, world.query_cell, AABB(), 0).get("ok", false))
	var press_started := interaction.secondary_press_from_view(Vector3(cx) + Vector3(0.5, 3.0, 0.5), Vector3.DOWN)
	var press_mode := str(interaction.drag_state().get("mode", ""))
	var ghost_cells: Array = interaction.drag_state().get("cells", [])
	var ghost_ok: bool = ghost_cells.size() == layout.pieces.size() and not ghost_cells.is_empty()
	var ghost_two := 0
	for entry in ghost_cells:
		ghost_ok = ghost_ok and str(entry.state) == "ok"
		if entry.has("joints_b"):
			ghost_two += 1
	var before := app.session.inventory.count("rail_cross")
	var laid := interaction.commit_drag_place()
	var paid: bool = before - app.session.inventory.count("rail_cross") == ghost_cells.size()
	interaction.placement_rotation_quarters = 0
	var shared_cell: Vector3i = shared[0] if not shared.is_empty() else cx
	var shared_record: Dictionary = ws.station(ws.station_at_cell(shared_cell))
	var two_pairs: bool = CoasterRails.has_second_curve(shared_record) and (shared_record.get("coaster_joints", []) as Array).size() == 2 and (shared_record.get("coaster_joints_b", []) as Array).size() == 2 and CoasterRails.connections(shared_record).size() >= 3
	var pair_a := CoasterRails.pair_for(shared_record, Vector3i.MAX, "a")
	var pair_b := CoasterRails.pair_for(shared_record, Vector3i.MAX, "b")
	var pairs_differ: bool = str(pair_a.pair) == "a" and str(pair_b.pair) == "b" and JSON.stringify(pair_a.curve) != JSON.stringify(pair_b.curve)
	var kettle_point := app.session.siege_defense._rail_point(shared_cell)
	var kettle_on_a: bool = kettle_point.is_equal_approx(CoasterRails.ride_point(pair_a) + Vector3(0.0, 0.95, 0.0))
	var start_a := entry_a - Vector3i(3, 0, 0)
	var start_b := entry_b - Vector3i(3, 0, 0)
	var far_a := exit_a + Vector3i(3, 0, 0)
	var far_b := exit_b + Vector3i(3, 0, 0)
	var chain := CoasterRails.chain(ws.stations, start_a)
	var chain_ok: bool = chain.size() == ghost_cells.size() + 12 and chain.has(far_a) and chain.has(far_b) and chain.has(start_b)
	var cart_a := ws.try_place("mine_cart", start_a + Vector3i.UP, world.query_cell, AABB(), 0)
	var cart_a_id := str(cart_a.get("details", {}).get("station", {}).get("instance_id", ""))
	var ride_a := _ride_cart(cart_a_id, [far_a, far_b, shared_cell], 900, far_a)
	var a_ok: bool = int(ride_a.reached.get(far_a, -1)) > 0 and int(ride_a.reached.get(shared_cell, -1)) > 0 and not ride_a.reached.has(far_b) and not ride_a.visited.has(exit_b) and not ride_a.visited.has(entry_b)
	# And back home along A again.
	var back_a := _ride_cart(cart_a_id, [start_a], 900, start_a)
	var a_home: bool = int(back_a.reached.get(start_a, -1)) > 0 and not back_a.visited.has(start_b)
	if cart_a.get("ok", false):
		ws.try_dismantle(cart_a_id, world.query_cell, AABB())
	var cart_b := ws.try_place("mine_cart", start_b + Vector3i.UP, world.query_cell, AABB(), 0)
	var cart_b_id := str(cart_b.get("details", {}).get("station", {}).get("instance_id", ""))
	var ride_b := _ride_cart(cart_b_id, [far_a, far_b, shared_cell], 900, far_b)
	var b_ok: bool = int(ride_b.reached.get(far_b, -1)) > 0 and int(ride_b.reached.get(shared_cell, -1)) > 0 and not ride_b.reached.has(far_a) and not ride_b.visited.has(exit_a) and not ride_b.visited.has(entry_a)
	if cart_b.get("ok", false):
		ws.try_dismantle(cart_b_id, world.query_cell, AABB())
	var shared_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(shared_cell))
	var two_tracks: bool = shared_body != null and shared_body.get_node_or_null("LoopTrack") != null and shared_body.get_node_or_null("LoopTrackB") != null and shared_body.find_children("*", "CollisionShape3D", true, false).size() == 1
	var saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(saved, world.query_cell) if saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var round_trip: bool = restored.get("ok", false) and CoasterRails.chain(ws.stations, start_a).size() == chain.size() and CoasterRails.has_second_curve(ws.station(ws.station_at_cell(shared_cell)))
	_record("T171_CROSSING", content_ok and slot >= 0 and lanes_swap and placed and press_started.get("reason") == "DRAG_STARTED" and press_mode == "rail_cross" and ghost_ok and ghost_two == shared.size() and laid.get("reason") == "CROSS_PLACED" and paid and two_pairs and pairs_differ and kettle_on_a and chain_ok and cart_a.get("ok", false) and a_ok and a_home and cart_b.get("ok", false) and b_ok and two_tracks and round_trip, "rail_cross (Crossing, coaster_tool cross, order 210, 4 per craft, stack 32, icon) ghosts two S-bends of one length whose lanes swap (A: lane 0 -> 2, B: lane 2 -> 0, eight cells) and lays them for one item per piece; the shared middle cell is one record with two curves and two joint pairs joining both tracks (kettles ride it as A); with rails at all four ends everything is one chain; a cart entering on A passes the shared cell and leaves on A's exit, never touching B's entry or exit, and comes home on A; a cart entering on B leaves on B's exit; the shared cell draws two track node sets over one collision box; the crossing survives a save round-trip", {"content_ok": content_ok, "lanes_swap": lanes_swap, "shared": shared, "placed": placed, "press": press_started.get("reason"), "press_mode": press_mode, "ghost_ok": ghost_ok, "ghost_count": ghost_cells.size(), "ghost_two": ghost_two, "laid": laid.get("reason"), "paid": paid, "two_pairs": two_pairs, "pairs_differ": pairs_differ, "kettle": kettle_point, "kettle_on_a": kettle_on_a, "chain": chain.size(), "chain_ok": chain_ok, "cart_a": cart_a.get("reason"), "ride_a": ride_a.reached, "a_home": a_home, "cart_b": cart_b.get("reason"), "ride_b": ride_b.reached, "two_tracks": two_tracks, "round_trip": round_trip})


## T178: the Climb rendered (`coaster-climb.png`).
func _render_climb() -> void:
	var player := app.session.player
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	# T178 the Climb rendered: a climb of length 12 / rise 6 with rails at
	# both ends and a mine cart part way up, seen from the side.
	var climb_origin := Vector3i(-12, 0, 52)
	_level_ground(climb_origin + Vector3i(-3, 0, -4), 22, 20, 14)
	app.session.inventory.try_transaction({}, {"rail_climb": 64, "rail": 12, "mine_cart": 1})
	var climb_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_climb":
			climb_slot = slot_index
	if climb_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(climb_slot, 4)
		climb_slot = 4
	app.session.inventory.select_hotbar(climb_slot)
	interaction.placement_rotation_quarters = 1
	interaction.begin_climb_at(climb_origin)
	interaction.set_climb(12, 6)
	var climb_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var climb_landing: Vector3i = climb_laid.get("changes", {}).get("landing", climb_origin + Vector3i(12, 6, 0))
	for x in range(1, 3):
		ws.try_place("rail", climb_origin + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
		ws.try_place("rail", climb_landing + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var climb_cart := ws.try_place("mine_cart", climb_origin + Vector3i(-2, 1, 0), world.query_cell, AABB(), 0)
	var climb_cart_id := str(climb_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var climb_cart_cell := climb_origin
	if app.session.coaster_carts != null:
		for _frame in range(900):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			climb_cart_cell = app.session.coaster_carts.rider_cell(climb_cart_id)
			if climb_cart_cell.y >= climb_origin.y + 3:
				break
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(climb_origin) + Vector3(6.0, 4.0, 13.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = 0.08
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var climb_texture := get_viewport().get_texture()
	var climb_image := climb_texture.get_image() if climb_texture != null else null
	var climb_path := app.data_root.path_join("coaster-climb.png")
	if climb_image == null:
		_record("T178_CLIMB_RENDERED", false, "a climb with a cart part way up renders in one 1280x720 view", {"path": climb_path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var climb_error := climb_image.save_png(climb_path)
	var climb_parts := 0
	for cell: Vector3i in CoasterRails.chain(ws.stations, climb_origin).keys():
		var record: Dictionary = ws.station(ws.station_at_cell(cell))
		if record.has("curve"):
			var body: Node3D = app.session._station_visuals.get(ws.station_at_cell(cell))
			if body != null:
				climb_parts += body.find_children("*", "MeshInstance3D", true, false).size()
	_record("T178_CLIMB_RENDERED", climb_laid.get("reason") == "CLIMB_PLACED" and climb_cart.get("ok", false) and climb_error == OK and climb_image.get_size() == Vector2i(1280, 720) and climb_parts >= 40 and climb_cart_cell.y >= climb_origin.y + 3, "a climb of length 12 / rise 6 renders with rails at both ends and a mine cart part way up, seen from the side, in one 1280x720 view", {"path": climb_path, "size": climb_image.get_size(), "error": climb_error, "laid": climb_laid.get("reason"), "cart": climb_cart.get("reason"), "parts": climb_parts, "cart_cell": climb_cart_cell})

## T175: flat curves rendered (`coaster-curves.png`).
func _render_curves() -> void:
	var player := app.session.player
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var origin := Vector3i(-2, 0, 36)

	# T175 (CoasterCraft card 4): a 90-degree curve, a U-turn and an S of two
	# 45s render on their own plate in `coaster-curves.png`.
	var cp := Vector3i(20, 0, 50)
	_level_ground(cp + Vector3i(-16, 0, -8), 36, 18, 10)
	app.session.inventory.try_transaction({}, {"rail_curve": 64, "rail": 24, "mine_cart": 1})
	var curve_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_curve":
			curve_slot = slot_index
	if curve_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(curve_slot, 4)
		curve_slot = 4
	app.session.inventory.select_hotbar(curve_slot)
	interaction.creative = true
	interaction.placement_rotation_quarters = 1
	# The 90: entry at cp heading +x, radius 4, bending right (+z).
	interaction.begin_curve_at(cp)
	interaction.set_curve_sweep(90, false)
	interaction.set_curve_radius(4)
	var ninety := interaction.commit_drag_place()
	var ninety_exit: Vector3i = ninety.get("changes", {}).get("exit", cp)
	for x in range(1, 4):
		ws.try_place("rail", cp + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
	for z in range(1, 3):
		ws.try_place("rail", ninety_exit + Vector3i(0, 0, z), world.query_cell, AABB(), 0)
	var curve_cart := ws.try_place("mine_cart", cp + Vector3i(-2, 1, 0), world.query_cell, AABB(), 0)
	# The U-turn: 10 cells to the -x, radius 3, bending right.
	var up := cp + Vector3i(-10, 0, 0)
	interaction.begin_curve_at(up)
	interaction.set_curve_sweep(180, false)
	interaction.set_curve_radius(3)
	var uturn := interaction.commit_drag_place()
	var uturn_exit: Vector3i = uturn.get("changes", {}).get("exit", up)
	for x in range(1, 3):
		ws.try_place("rail", up + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
		ws.try_place("rail", uturn_exit + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
	# The S: a 45 right then a 45 left from the diagonal end, radius 5.
	var sp := cp + Vector3i(0, 0, -5)
	interaction.begin_curve_at(sp)
	interaction.set_curve_sweep(45, false)
	interaction.set_curve_radius(5)
	var s_first := interaction.commit_drag_place()
	var s_first_layout := CoasterRails.curve_layout(sp, 1, 5.0, 45.0)
	interaction.begin_curve_at(s_first_layout.exit_cell_ahead)
	interaction.set_curve_sweep(45, true)
	var s_second := interaction.commit_drag_place()
	var s_exit: Vector3i = s_second.get("changes", {}).get("exit", sp)
	for x in range(1, 3):
		ws.try_place("rail", sp + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
		ws.try_place("rail", s_exit + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	interaction.placement_rotation_quarters = 0
	interaction.creative = false
	var curve_cart_id := str(curve_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	if app.session.coaster_carts != null:
		for _frame in range(60):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(cp) + Vector3(-3.0, 7.5, 17.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = -0.36
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var curve_texture := get_viewport().get_texture()
	var curve_image := curve_texture.get_image() if curve_texture != null else null
	var curve_path := app.data_root.path_join("coaster-curves.png")
	if curve_image == null:
		_record("T175_CURVES_RENDERED", false, "a 90-degree curve, a U-turn and an S of two 45s render in one 1280x720 view", {"path": curve_path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var curve_error := curve_image.save_png(curve_path)
	var curve_parts := 0
	for station_id: String in ws.stations.keys():
		var record: Dictionary = ws.stations[station_id]
		if str(record.get("entity_id", "")) == "rail_loop" and record.has("curve") and Vector3i(record.get("anchor", Vector3i.ZERO)).x >= cp.x - 16:
			var body: Node3D = app.session._station_visuals.get(station_id)
			if body != null:
				curve_parts += body.find_children("*", "MeshInstance3D", true, false).size()
	var curve_cart_cell := app.session.coaster_carts.rider_cell(curve_cart_id) if app.session.coaster_carts != null else Vector3i(0, -9999, 0)
	_record("T175_CURVES_RENDERED", ninety.get("reason") == "CURVE_PLACED" and uturn.get("reason") == "CURVE_PLACED" and s_first.get("reason") == "CURVE_PLACED" and s_second.get("reason") == "CURVE_PLACED" and curve_cart.get("ok", false) and curve_error == OK and curve_image.get_size() == Vector2i(1280, 720) and curve_parts >= 60 and curve_cart_cell != cp + Vector3i(-2, 0, 0), "a radius-4 90-degree curve with a mine cart on it, a radius-3 U-turn and an S of two radius-5 45s render with rails at their ends in one 1280x720 view", {"path": curve_path, "size": curve_image.get_size(), "error": curve_error, "ninety": ninety.get("reason"), "uturn": uturn.get("reason"), "s_first": s_first.get("reason"), "s_second": s_second.get("reason"), "s_exit": s_exit, "cart": curve_cart.get("reason"), "curve_parts": curve_parts, "cart_cell": curve_cart_cell})


## T181: trestle supports rendered (`coaster-supports.png`).
func _render_supports() -> void:
	var player := app.session.player
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var origin := Vector3i(-2, 0, 36)

	# T181 trestle supports rendered (CoasterCraft card 8): the loop above
	# grew its posts on placement; a straight of rail_loop pieces laid five
	# cells up (TrackCurve.make_line) grows a post per piece down to the
	# plate. Both render in `coaster-supports.png`.
	var line_start := Vector3(origin) + Vector3(-9.0, 5.55, 3.5)
	var line_curve := TrackCurve.make_line(line_start, Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), 6.0)
	var line_pieces := TrackCurve.pieces(line_curve, "rail_loop", 1, Vector3i(floori(line_start.x) - 1, 5, floori(line_start.z)), Vector3i(floori(line_start.x) + 6, 5, floori(line_start.z)))
	var line_cells: Array[Vector3i] = []
	var line_laid := true
	for piece: Dictionary in line_pieces:
		var piece_cell: Vector3i = piece.cell
		var joints: Array = []
		for joint in piece.get("joints", []):
			if joint is Vector3i:
				var offset: Vector3i = joint - piece_cell
				joints.append([offset.x, offset.y, offset.z])
		var extra: Dictionary = (piece.get("extra", {}) as Dictionary).duplicate()
		extra["coaster_joints"] = joints
		extra["_free"] = true
		line_laid = line_laid and bool(ws.try_place("rail_loop", piece_cell, world.query_cell, AABB(), int(piece.rotation), extra).get("ok", false))
		line_cells.append(piece_cell)
	var line_posts := 0
	var line_reach := true
	for cell: Vector3i in line_cells:
		var body: Node3D = app.session._station_visuals.get(ws.station_at_cell(cell))
		var support: Node = body.find_child("Support", true, false) if body != null else null
		if support != null:
			line_posts += 1
			line_reach = line_reach and absf(_post_bottom(support) - float(origin.y)) < 0.05
	var loop_posts := 0
	for station_id: String in ws.stations.keys():
		var station_record: Dictionary = ws.stations[station_id]
		if str(station_record.get("entity_id", "")) == "rail_loop" and station_record.has("curve") and not line_cells.has(station_record.get("anchor", Vector3i.ZERO)):
			var loop_body: Node3D = app.session._station_visuals.get(station_id)
			if loop_body != null and loop_body.find_child("Support", true, false) != null:
				loop_posts += 1
	player.global_position = Vector3(origin) + Vector3(-3.0, 4.5, 13.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = 0.02
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(60):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var supports_path := app.data_root.path_join("coaster-supports.png")
	var supports_image := get_viewport().get_texture().get_image()
	var supports_error := supports_image.save_png(supports_path) if supports_image != null else ERR_UNAVAILABLE
	_record("T181_SUPPORTS_RENDERED", line_laid and line_cells.size() >= 6 and line_posts == line_cells.size() and line_reach and loop_posts >= 4 and supports_error == OK, "a straight of rail_loop pieces laid five cells up grows a stone post per piece down to the plate, the true loop's lower pieces carry posts, and both render in coaster-supports.png", {"path": supports_path, "error": supports_error, "line_laid": line_laid, "line_cells": line_cells.size(), "line_posts": line_posts, "line_reach": line_reach, "loop_posts": loop_posts})


## World y of the bottom of a Support node's post (-99 without one).
func _post_bottom(support: Node) -> float:
	var post := support.find_child("Post", true, false) as MeshInstance3D
	if post == null or not post.mesh is BoxMesh:
		return -99.0
	return post.global_position.y - (post.mesh as BoxMesh).size.y * 0.5


func _count_entities(ws: WorkstationService, entity_id: String) -> int:
	var count := 0
	for station_id: String in ws.stations.keys():
		if str(ws.stations[station_id].get("entity_id", "")) == entity_id:
			count += 1
	return count


func _level_ground(origin: Vector3i, width: int, depth: int, height: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(origin + Vector3i(x, -1, z), 3)
			for y in range(height):
				app.session.world.set_cell(origin + Vector3i(x, y, z), 0)


## The fixtures of every coaster test live in x -30..46, z 12..64 around the
## spawn; terrain streams in over a few seconds, so wait until that box is
## editable before laying anything (placements on unloaded cells fail with
## UNLOADED and levelling silently does nothing).
func _wait_region_loaded() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		var all_loaded := true
		for x in range(-30, 47, 8):
			for z in range(12, 65, 8):
				for y in [-1, 6]:
					if app.session.world.query_cell(Vector3i(x, y, z)).get("state") != "LOADED":
						all_loaded = false
		if all_loaded:
			var loaded_x: Array[int] = []
			var loaded_z: Array[int] = []
			for x in range(-96, 97, 8):
				if app.session.world.query_cell(Vector3i(x, 0, 40)).get("state") == "LOADED":
					loaded_x.append(x)
			for z in range(-64, 129, 8):
				if app.session.world.query_cell(Vector3i(0, 0, z)).get("state") == "LOADED":
					loaded_z.append(z)
			print("REGION_LOADED x %s z %s" % [loaded_x, loaded_z])
			return
		await get_tree().process_frame
	push_warning("coaster test region did not finish loading in 60 s")
## Levels a plate and waits (up to ten seconds) until every cell in `cells`
## reads LOADED and empty and the whole stone plate under it is in,
## re-levelling as chunks stream in.
func _wait_levelled(origin: Vector3i, width: int, depth: int, height: int, cells: Array[Vector3i]) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		_level_ground(origin, width, depth, height)
		var clear := true
		for cell: Vector3i in cells:
			var query := app.session.world.query_cell(cell)
			if query.get("state") != "LOADED" or int(query.get("voxel_id", 1)) != 0:
				clear = false
				break
		for x in range(width):
			for z in range(depth):
				var plate := app.session.world.query_cell(origin + Vector3i(x, -1, z))
				if plate.get("state") != "LOADED" or int(plate.get("voxel_id", 0)) != 3:
					clear = false
		if clear:
			return true
		await get_tree().process_frame
	return false


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
