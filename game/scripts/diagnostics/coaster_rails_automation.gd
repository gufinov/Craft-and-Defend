class_name CoasterRailsAutomation
extends Node

## Coaster rails side project (docs/COASTER_RAILS.md): slope rails that join
## two levels, the loop drag tool and the mine cart that rides the whole
## track. Runs with `--coaster-rails-automation=gate` (headless: T160-T162,
## T168, T176-T177) and `--coaster-rails-automation=visual` (needs a window:
## T163 renders `coaster-rails.png`, T178 `coaster-climb.png`).

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
	var cb := Vector3i(-14, 0, 62)
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
	var mb := Vector3i(0, 0, 72)
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


## Rendered evidence: a lead-in, a radius-3 loop and its exit with a cart on
## the track, beside a slope run climbing a step, in one 1280x720 view.
func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
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
	app.session.inventory.select_hotbar(loop_slot)
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
