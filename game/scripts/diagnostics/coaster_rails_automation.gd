class_name CoasterRailsAutomation
extends Node

## Coaster rails side project (docs/COASTER_RAILS.md): slope rails that join
## two levels, the loop drag tool and the mine cart that rides the whole
## track. Runs with `--coaster-rails-automation=gate` (headless: T160-T162)
## and `--coaster-rails-automation=visual` (needs a window: T163 renders
## `coaster-rails.png`).

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

	# T169 loop snap (owner 2026-09-20): a base row of five rails between two
	# slopes rising outward; Rail Loop aimed at the base raises the arch (15
	# loop pieces, radius 4) joined to both slopes; a cart circulates the
	# loop; a base with four rails (odd spacing) is refused.
	var lb := Vector3i(-14, 0, 60)
	_level_ground(lb + Vector3i(-3, 0, -2), 16, 5, 12)
	app.session.inventory.try_transaction({}, {"rail": 12, "rail_slope": 4, "rail_loop": 40, "mine_cart": 1})
	var lb_ok := bool(ws.try_place("rail_slope", lb, world.query_cell, AABB(), 3).get("ok", false))
	for x in range(1, 6):
		lb_ok = lb_ok and bool(ws.try_place("rail", lb + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	lb_ok = lb_ok and bool(ws.try_place("rail_slope", lb + Vector3i(6, 0, 0), world.query_cell, AABB(), 1).get("ok", false))
	var loop_item_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_loop":
			loop_item_slot = slot_index
	if loop_item_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(loop_item_slot, 2)
		loop_item_slot = 2
	app.session.inventory.select_hotbar(loop_item_slot)
	var loops_before := app.session.inventory.count("rail_loop")
	var snapped := interaction.begin_coaster_loop_at(lb + Vector3i(3, 1, 0))
	var snap_no_drag := not interaction.drag_active()
	var snap_spent := loops_before - app.session.inventory.count("rail_loop") == 15
	var snap_chain := CoasterRails.chain(ws.stations, lb + Vector3i(3, 0, 0))
	var snap_top := lb + Vector3i(3, 6, 0)
	var arch_joined := snap_chain.has(snap_top) and snap_chain.has(lb + Vector3i(-1, 1, 0)) and snap_chain.has(lb + Vector3i(7, 1, 0)) and (snap_chain.get(lb, []) as Array).has(lb + Vector3i(-1, 1, 0))
	var snap_cart := ws.try_place("mine_cart", lb + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	var snap_cart_id := str(snap_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var over_top := -1
	var back_home := -1
	if app.session.coaster_carts != null:
		for frame in range(900):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(snap_cart_id)
			if over_top < 0 and cell == snap_top:
				over_top = frame
			if over_top >= 0 and back_home < 0 and cell == lb + Vector3i(3, 0, 0):
				back_home = frame
				break
	# Odd spacing: slopes five apart (four rails between) is refused.
	var ob := lb + Vector3i(0, 0, 3)
	var ob_ok := bool(ws.try_place("rail_slope", ob, world.query_cell, AABB(), 3).get("ok", false))
	for x in range(1, 5):
		ob_ok = ob_ok and bool(ws.try_place("rail", ob + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	ob_ok = ob_ok and bool(ws.try_place("rail_slope", ob + Vector3i(5, 0, 0), world.query_cell, AABB(), 1).get("ok", false))
	var odd_result := interaction.begin_coaster_loop_at(ob + Vector3i(2, 1, 0))
	var odd_refused: bool = odd_result.get("reason") == "LOOP_BASE_ODD" and not interaction.drag_active()
	_record("T169_LOOP_SNAP", lb_ok and snapped.get("reason") == "LOOP_SNAPPED" and int(snapped.get("changes", {}).get("count", 0)) == 15 and int(snapped.get("changes", {}).get("radius", 0)) == 4 and snap_no_drag and snap_spent and snap_chain.size() == 22 and arch_joined and snap_cart.get("ok", false) and over_top > 0 and back_home > over_top and ob_ok and odd_refused, "Rail Loop aimed at a base row (five rails between two slopes rising outward) snaps a 15-piece radius-4 arch joined to both slopes without starting a drag; the 22-cell chain carries a cart from the base over the top and back; a base with four rails between the slopes is refused as odd", {"base": lb_ok, "snapped": snapped.get("reason"), "count": snapped.get("changes", {}).get("count"), "radius": snapped.get("changes", {}).get("radius"), "no_drag": snap_no_drag, "spent": snap_spent, "chain": snap_chain.size(), "arch_joined": arch_joined, "cart": snap_cart.get("reason"), "over_top": over_top, "back_home": back_home, "odd_base": ob_ok, "odd": odd_result.get("reason")})
	if snap_cart.get("ok", false):
		ws.try_dismantle(snap_cart_id, world.query_cell, AABB())

	# T162 loop drag: the ghost lays a lead-in, Shift adds a radius-3 loop and
	# a two-cell exit, X/C resize it within 2..6, release lays every piece as
	# one chain, and a cart rides the loop before taking the exit.
	var anchor := Vector3i(-14, 0, 40)
	_level_ground(anchor + Vector3i(-2, 0, -3), 20, 7, 10)
	app.session.inventory.try_transaction({}, {"rail_loop": 64, "mine_cart": 1})
	var loop_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_loop":
			loop_slot = slot_index
	if loop_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(loop_slot, 2)
		loop_slot = 2
	app.session.inventory.select_hotbar(loop_slot)
	var started := interaction.begin_coaster_loop_at(anchor)
	var lead_in := interaction.set_drag_end(anchor + Vector3i(3, 0, 0))
	var lead_in_count: int = lead_in.get("cells", []).size()
	var lead_in_flat: bool = not bool(lead_in.get("loop", false)) and lead_in_count == 4
	var aim_origin := Vector3(anchor) + Vector3(1.5, 6.0, 0.5)
	var with_loop := interaction.update_drag_place(aim_origin, Vector3.DOWN, true)
	var default_radius := int(with_loop.get("loop_radius", 0))
	var default_cells: int = with_loop.get("cells", []).size()
	var default_loop_cells := int(with_loop.get("loop_cells", 0))
	var frozen: bool = with_loop.get("end", Vector3i.ZERO) == anchor + Vector3i(3, 0, 0)
	interaction.coaster_loop_keys(true, false)
	interaction.coaster_loop_keys(false, false)
	var smaller := interaction.drag_state()
	var smaller_radius := int(smaller.get("loop_radius", 0))
	var smaller_cells: int = smaller.get("cells", []).size()
	for _press in range(8):
		interaction.coaster_loop_keys(false, true)
		interaction.coaster_loop_keys(false, false)
	var largest := interaction.drag_state()
	var largest_radius := int(largest.get("loop_radius", 0))
	var largest_cells: int = largest.get("cells", []).size()
	interaction.coaster_loop_keys(true, false)
	interaction.coaster_loop_keys(true, false)
	interaction.coaster_loop_keys(true, false)
	var held_x_radius := int(interaction.drag_state().get("loop_radius", 0))
	interaction.coaster_loop_keys(false, false)
	for _press in range(2):
		interaction.coaster_loop_keys(true, false)
		interaction.coaster_loop_keys(false, false)
	var back_to_default := int(interaction.drag_state().get("loop_radius", 0)) == 3
	var all_ok := true
	for entry in interaction.drag_state().get("cells", []):
		all_ok = all_ok and str(entry.get("state", "")) == "ok"
	var loop_count_before := _count_entities(ws, "rail_loop")
	var committed := interaction.commit_drag_place()
	var loop_pieces := _count_entities(ws, "rail_loop") - loop_count_before
	var loop_chain := CoasterRails.chain(ws.stations, anchor)
	# The circle sits one cell right (+z) of the lead-in; the exit run two.
	var top_cell := anchor + Vector3i(5, 6, 1)
	var side_cell := anchor + Vector3i(8, 3, 1)
	var exit_end := anchor + Vector3i(8, 0, 2)
	var top_joints: Array = loop_chain.get(top_cell, [])
	var side_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(side_cell))
	var top_curved := side_body != null and side_body.get_node_or_null("LoopArms") != null
	var lead_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(anchor + Vector3i(1, 0, 0)))
	var lead_flat := lead_body != null and lead_body.get_node_or_null("RailArms") != null
	var loop_cart := ws.try_place("mine_cart", anchor + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var loop_cart_id := str(loop_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var loop_carts := app.session.coaster_carts
	var top_reached := -1
	var exit_reached := -1
	var home_again := -1
	if loop_carts != null:
		for frame in range(900):
			loop_carts.advance(1.0 / 30.0, false)
			var cell := loop_carts.rider_cell(loop_cart_id)
			if top_reached < 0 and cell == top_cell:
				top_reached = frame
			if exit_reached < 0 and cell == exit_end:
				exit_reached = frame
			if exit_reached >= 0 and home_again < 0 and cell == anchor:
				home_again = frame
				break
	var loop_cart_body: Node3D = app.session._station_visuals.get(loop_cart_id)
	var loop_rig: Node3D = loop_cart_body.get_node_or_null("CartRig") if loop_cart_body != null else null
	# The recorded joints survive a save round-trip (snapshot -> JSON -> restore).
	var saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(saved, world.query_cell) if saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var restored_chain := CoasterRails.chain(ws.stations, anchor)
	var restored_top: Array = restored_chain.get(top_cell, [])
	var round_trip: bool = restored.get("ok", false) and restored_chain.size() == 22 and restored_top.size() == 2 and restored_chain.has(exit_end)
	_record("T162_LOOP_DRAG_AND_RIDE", started.get("ok", false) and lead_in_flat and bool(with_loop.get("loop", false)) and default_radius == 3 and default_loop_cells == 16 and default_cells == 22 and frozen and smaller_radius == 2 and smaller_cells == 18 and largest_radius == 6 and largest_cells == 38 and held_x_radius == 5 and back_to_default and all_ok and committed.get("reason") == "COASTER_PLACED" and int(committed.get("changes", {}).get("count", 0)) == 22 and loop_pieces == 22 and loop_chain.size() == 22 and top_joints.size() == 2 and top_curved and lead_flat and loop_cart.get("ok", false) and top_reached > 0 and exit_reached > top_reached and home_again > exit_reached and round_trip, "a rail_loop drag lays a 4-cell lead-in; Shift adds a radius-3 loop (16 cells) and a 2-cell exit for 22 ghost cells with the lead-in frozen; X shrinks to radius 2 (18 cells), C grows to the limit 6 (38 cells), a held key resizes once; release lays all 22 pieces as one chain whose top piece joins two cells and draws curved arms while the lead-in draws as a rail; a cart rides over the top of the loop, out the exit and back home; the laid track survives a save round-trip", {"round_trip": round_trip, "restored": restored.get("reason"), "started": started.get("reason"), "lead_in": lead_in_count, "default_radius": default_radius, "default_cells": default_cells, "loop_cells": default_loop_cells, "frozen": frozen, "smaller": [smaller_radius, smaller_cells], "largest": [largest_radius, largest_cells], "held_x": held_x_radius, "back_to_default": back_to_default, "all_ok": all_ok, "committed": committed.get("reason"), "count": committed.get("changes", {}).get("count", 0), "pieces": loop_pieces, "chain": loop_chain.size(), "top_joints": top_joints.size(), "top_curved": top_curved, "lead_flat": lead_flat, "cart": loop_cart.get("reason"), "top_frame": top_reached, "exit_frame": exit_reached, "home_frame": home_again, "rig": loop_rig.global_position if loop_rig != null else null})


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
	var origin := Vector3i(-8, 0, 36)
	_level_ground(origin + Vector3i(-3, 0, -6), 22, 14, 10)
	app.session.inventory.try_transaction({}, {"rail_loop": 64, "mine_cart": 2, "rail": 6, "rail_slope": 2})
	var loop_slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[slot_index].get("item_id", "")) == "rail_loop":
			loop_slot = slot_index
	if loop_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(loop_slot, 2)
		loop_slot = 2
	app.session.inventory.select_hotbar(loop_slot)
	interaction.begin_coaster_loop_at(origin)
	interaction.set_drag_end(origin + Vector3i(3, 0, 0))
	interaction.set_coaster_loop(true)
	var committed := interaction.commit_drag_place()
	var cart := ws.try_place("mine_cart", origin + Vector3i(1, 1, 0), world.query_cell, AABB(), 0)
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
		for _frame in range(121):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(origin) + Vector3(5.0, 4.5, 12.5)
	player.look_at(Vector3(origin) + Vector3(5.0, 3.2, 0.5), Vector3.UP)
	player.camera.rotation.x = -0.04
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
	_record("T163_COASTER_RENDERED", committed.get("reason") == "COASTER_PLACED" and cart.get("ok", false) and slope_ok and slope_cart.get("ok", false) and error == OK and image.get_size() == Vector2i(1280, 720) and loop_parts >= 120 and cart_parts >= 18 and cart_cell.y >= origin.y + 5, "a four-cell lead-in, a radius-3 loop and a two-cell exit render as a polygonal loop of rail pieces with a mine cart hanging over its top, beside a slope run climbing a step with its own cart, in one 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "committed": committed.get("reason"), "cart": cart.get("reason"), "slope_ok": slope_ok, "slope_cart": slope_cart.get("reason"), "loop_parts": loop_parts, "cart_parts": cart_parts, "cart_cell": cart_cell})


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
