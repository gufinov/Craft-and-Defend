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
## T168, T179 track auto-clear, T180 trestle supports, T183 trestle trusses,
## T185 one track style, T186 smooth sweep, T187 snap to a track end) and
## `--coaster-rails-automation=visual` (needs a window: T163 renders
## `coaster-rails.png`, T181 `coaster-supports.png`, T186 `coaster-sweep-*.png`).

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

	# T168 Rail Switch (owner 2026-09-20: "the Rail Switch should be updated
	# to be smooth"): four rails, then the Rail Switch laid by its drag tool
	# - a right-press with it held starts the smooth_bend drag at the aimed
	# entry heading the way the player faces, the default ghost is the
	# 4-long S-bend to one lane right of travel (rail_loop curve pieces,
	# entry at the aim, exit four cells on and one lane over), release lays
	# them all for one item each - then four rails on the new lane; one
	# chain from the first rail to the last; a rail beside the entry on the
	# exit lane does not join; the entry and exit ride at rail height; a
	# mine cart crosses to the far end and back.
	var sw := Vector3i(-14, 0, 50)
	_level_ground(sw + Vector3i(-2, 0, -3), 18, 8, 9)
	app.session.inventory.try_transaction({}, {"rail": 12, "rail_switch": 16, "mine_cart": 1})
	var sw_ok := true
	for x in range(0, 4):
		sw_ok = sw_ok and bool(ws.try_place("rail", sw + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var switch_slot := _hotbar_slot_for("rail_switch", 3)
	interaction.placement_rotation_quarters = 1
	interaction.creative = false
	interaction.set_curve_size(CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
	var sw_entry := sw + Vector3i(4, 0, 0)
	var sw_exit := sw_entry + Vector3i(4, 0, 1)
	# The right-press path itself must start the switch drag (owner
	# 2026-09-20: it placed a single piece when it fell through to the
	# one-cell placement). The press looks down at the entry cell, leaning
	# +x, so the heading (which follows the player's facing) is +x.
	var press_origin := Vector3(sw_entry) + Vector3(0.3, 3.0, 0.5)
	var press_aim := Vector3(0.1, -1.0, 0.0).normalized()
	var press_started := interaction.secondary_press_from_view(press_origin, press_aim)
	var sw_ghost := interaction.drag_state()
	var press_mode := str(sw_ghost.get("mode", ""))
	var sw_ghost_cells: Array = sw_ghost.get("cells", [])
	var sw_default: bool = int(sw_ghost.get("curve_length", 0)) == 4 and int(sw_ghost.get("curve_lanes", 0)) == 1 and int(sw_ghost.get("rotation_quarters", -1)) == 1 and Vector3i(sw_ghost.get("anchor", Vector3i.MAX)) == sw_entry
	var sw_count := sw_ghost_cells.size()
	var sw_ghost_ok: bool = sw_count == CoasterRails.bend_piece_count(4, 1) and sw_count > 4 and Vector3i(sw_ghost_cells[0].cell) == sw_entry and Vector3i(sw_ghost_cells[sw_count - 1].cell) == sw_exit
	for entry in sw_ghost_cells:
		sw_ghost_ok = sw_ghost_ok and str(entry.state) == "ok" and str(entry.entity_id) == "rail_loop" and (entry.get("extra", {}) as Dictionary).has("curve")
	var switch_before := app.session.inventory.count("rail_switch")
	var sw_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var switch_spent := switch_before - app.session.inventory.count("rail_switch") == sw_count
	for x in range(1, 5):
		sw_ok = sw_ok and bool(ws.try_place("rail", sw_exit + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	# Control: a rail beside the entry on the exit lane must not join.
	sw_ok = sw_ok and bool(ws.try_place("rail", sw_entry + Vector3i(0, 0, 1), world.query_cell, AABB(), 0).get("ok", false))
	var sw_chain := CoasterRails.chain(ws.stations, sw)
	var sw_far := sw_exit + Vector3i(4, 0, 0)
	var control_alone := CoasterRails.chain(ws.stations, sw_entry + Vector3i(0, 0, 1)).size() == 1 and not sw_chain.has(sw_entry + Vector3i(0, 0, 1))
	var sw_entry_record: Dictionary = ws.station(ws.station_at_cell(sw_entry))
	var sw_exit_record: Dictionary = ws.station(ws.station_at_cell(sw_exit))
	var sw_rail_height: bool = sw_entry_record.has("curve") and CoasterRails.ride_point(sw_entry_record).is_equal_approx(Vector3(sw_entry) + Vector3(0.5, 0.55, 0.5)) and CoasterRails.ride_point(sw_exit_record).is_equal_approx(Vector3(sw_exit) + Vector3(0.5, 0.55, 0.5))
	var sw_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(sw_entry))
	var sw_drawn := sw_body != null and sw_body.get_node_or_null("LoopTrack") != null
	var sw_cart := ws.try_place("mine_cart", sw + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var sw_cart_id := str(sw_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var far_frame := -1
	var home_frame := -1
	var crossed_exit := false
	if app.session.coaster_carts != null:
		for frame in range(500):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
			var cell := app.session.coaster_carts.rider_cell(sw_cart_id)
			crossed_exit = crossed_exit or cell == sw_exit
			if far_frame < 0 and cell == sw_far:
				far_frame = frame
			if far_frame >= 0 and home_frame < 0 and cell == sw:
				home_frame = frame
				break
	_record("T168_LANE_SWITCHER", sw_ok and switch_slot >= 0 and press_started.get("reason") == "DRAG_STARTED" and press_mode == "smooth_bend" and sw_default and sw_ghost_ok and sw_laid.get("reason") == "BEND_PLACED" and int(sw_laid.get("changes", {}).get("count", 0)) == sw_count and switch_spent and sw_chain.size() == sw_count + 8 and sw_chain.has(sw_far) and control_alone and sw_rail_height and sw_drawn and sw_cart.get("ok", false) and crossed_exit and far_frame > 0 and home_frame > far_frame, "a right-press with Rail Switch held starts the smooth_bend drag at the aimed entry heading the way the player faces; the default ghost is the 4-long S-bend to one lane right (rail_loop curve pieces, entry at the aim, exit 4 on and 1 over, all green); release lays every piece for one Rail Switch each (BEND_PLACED); with four rails before and four after on the new lane one chain runs from the first rail to the last; a rail beside the entry on the exit lane stays alone; the entry and exit ride at rail height and draw the curve track; a mine cart crosses to the far rail and back", {"rails_ok": sw_ok, "slot": switch_slot, "press": press_started.get("reason"), "mode": press_mode, "anchor": sw_ghost.get("anchor"), "default": sw_default, "ghost_ok": sw_ghost_ok, "first": sw_ghost_cells[0].cell if sw_count > 0 else null, "last": sw_ghost_cells[sw_count - 1].cell if sw_count > 0 else null, "count": sw_count, "laid": sw_laid.get("reason"), "spent": switch_spent, "chain": sw_chain.size(), "control_alone": control_alone, "rail_height": sw_rail_height, "drawn": sw_drawn, "cart": sw_cart.get("reason"), "crossed_exit": crossed_exit, "far_frame": far_frame, "home_frame": home_frame})
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
	var cb_press_origin := Vector3(cb) + Vector3(-2.0, 3.0, 0.5)
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
	# T170 Rail Switch (CoasterCraft card 2; the smooth lane switcher since
	# 2026-09-20): with Rail Switch held a press ghosts an S-bend of
	# rail_loop curve pieces from the entry to one lane right four cells on; Shift-aim sets length and lanes (negative =
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
	var cv_press_origin := Vector3(cv) + Vector3(-2.0, 2.0, 0.5)
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

	# T182 the heading follows the aim (owner 2026-09-20: "the item should
	# start from where I place and extend towards its rotated direction, or
	# be dragged from that spot"): a coaster-tool press heads the way the
	# player faces whatever the build orientation was; a Shift-drag re-aims a
	# climb / loop along the drag, and a bend dragged behind its entry flips.
	var hd := Vector3i(30, 0, 66)
	var hd_loaded := await _wait_levelled(hd + Vector3i(-12, 0, -4), 24, 9, 14, [hd, hd + Vector3i(8, 0, 0), hd + Vector3i(-8, 0, 0)] as Array[Vector3i])
	app.session.inventory.try_transaction({}, {"rail_climb": 40, "rail_loop": 60, "rail_switch": 20})
	var hd_climb_slot := _hotbar_slot_for("rail_climb", 7)
	app.session.inventory.select_hotbar(hd_climb_slot)
	interaction.placement_rotation_quarters = 1
	interaction.set_climb(CoasterRails.CLIMB_LENGTH_DEFAULT, CoasterRails.CLIMB_RISE_DEFAULT)
	# Standing east of the entry looking west (-x): the climb must head west.
	var hd_origin := Vector3(hd) + Vector3(3.0, 2.5, 0.5)
	var hd_press := interaction.secondary_press_from_view(hd_origin, (Vector3(hd) + Vector3(0.5, 0.0, 0.5) - hd_origin).normalized())
	var hd_state := interaction.drag_state()
	var faces_west: bool = str(hd_state.get("mode", "")) == "climb" and int(hd_state.get("rotation_quarters", -1)) == 3 and Vector3i(hd_state.get("anchor", Vector3i.MAX)) == hd
	# Shift-drag 8 cells EAST of the entry: the climb turns around and heads east, length 8.
	interaction.update_drag_place(Vector3(hd) + Vector3(8.5, 6.0, 0.5), Vector3.DOWN, true)
	hd_state = interaction.drag_state()
	var climb_flipped: bool = int(hd_state.get("rotation_quarters", -1)) == 1 and int(hd_state.get("climb_length", 0)) == 8
	var climb_east := true
	for entry in hd_state.get("cells", []):
		if Vector3i(entry.cell).x < hd.x:
			climb_east = false
	interaction.cancel_drag_place()
	# The loop: pressed facing west, dragged 6 cells south (+z) heads south at diameter 6.
	app.session.inventory.select_hotbar(_hotbar_slot_for("rail_loop", 2))
	interaction.placement_rotation_quarters = 1
	interaction.secondary_press_from_view(hd_origin, (Vector3(hd) + Vector3(0.5, 0.0, 0.5) - hd_origin).normalized())
	var loop_west: bool = int(interaction.drag_state().get("rotation_quarters", -1)) == 3
	interaction.update_drag_place(Vector3(hd) + Vector3(0.5, 6.0, 6.5), Vector3.DOWN, true)
	hd_state = interaction.drag_state()
	var loop_south: bool = str(hd_state.get("mode", "")) == "loop_element" and int(hd_state.get("rotation_quarters", -1)) == 2 and int(hd_state.get("loop_size", 0)) == 6
	interaction.cancel_drag_place()
	# The Rail Switch: heading east, dragged 6 cells behind (west) flips to west, length 6.
	app.session.inventory.select_hotbar(_hotbar_slot_for("rail_switch", 4))
	interaction.placement_rotation_quarters = 1
	interaction.set_curve_size(CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
	interaction.begin_curve_tool_at(hd)
	interaction.update_drag_place(Vector3(hd) + Vector3(-5.5, 6.0, 1.5), Vector3.DOWN, true)
	hd_state = interaction.drag_state()
	var bend_flipped: bool = int(hd_state.get("rotation_quarters", -1)) == 3 and int(hd_state.get("curve_length", 0)) == 6
	interaction.cancel_drag_place()
	interaction.placement_rotation_quarters = 0
	interaction.set_curve_size(CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
	interaction.set_climb(CoasterRails.CLIMB_LENGTH_DEFAULT, CoasterRails.CLIMB_RISE_DEFAULT)
	_record("T182_HEADING_FOLLOWS_AIM", hd_loaded and hd_press.get("reason") == "DRAG_STARTED" and faces_west and climb_flipped and climb_east and loop_west and loop_south and bend_flipped, "with the build orientation East, a Climb right-press from east of the entry looking west starts a climb heading west at the aimed cell; Shift-dragging 8 cells east turns it east (length 8, every ghost cell east of the entry); a Loop pressed the same way heads west and a Shift-drag 6 cells south turns it south at diameter 6; a Bend heading east Shift-dragged 6 cells behind its entry flips west with length 6", {"loaded": hd_loaded, "press": hd_press.get("reason"), "faces_west": faces_west, "climb_flipped": climb_flipped, "climb_east": climb_east, "loop_west": loop_west, "loop_south": loop_south, "bend_flipped": bend_flipped, "bend_state": {"rotation": hd_state.get("rotation_quarters"), "length": hd_state.get("curve_length"), "lanes": hd_state.get("curve_lanes")}})

	# T183 trestle trusses (owner playtest 2026-09-20 item 7: "the girders
	# that hold up the climbs are broken and missing the diagonal bracing"):
	# a climb of length 12 / rise 6 on a levelled plate grows a real bent
	# under its middle piece - two legs, ties, an X of diagonals, and a
	# stringer reaching toward the next piece's bent.
	var tr := Vector3i(-40, 0, 70)
	var tr_loaded := await _wait_levelled(tr + Vector3i(-3, 0, -4), 20, 9, 14, [tr, tr + Vector3i(6, 3, 0), tr + Vector3i(12, 6, 0)] as Array[Vector3i])
	app.session.inventory.try_transaction({}, {"rail_climb": 40})
	_hotbar_slot_for("rail_climb", 7)
	interaction.placement_rotation_quarters = 1
	interaction.begin_climb_at(tr)
	interaction.set_climb(12, 6)
	var tr_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	interaction.set_climb(CoasterRails.CLIMB_LENGTH_DEFAULT, CoasterRails.CLIMB_RISE_DEFAULT)
	var tr_middle: Dictionary = {}
	var tr_next: Dictionary = {}
	for station_id: String in ws.stations.keys():
		var station_record: Dictionary = ws.stations[station_id]
		var station_anchor: Vector3i = station_record.get("anchor", Vector3i.ZERO)
		if str(station_record.get("entity_id", "")) == "rail_loop" and station_record.has("curve") and station_anchor.z == tr.z:
			if station_anchor.x == tr.x + 6:
				tr_middle = station_record
			elif station_anchor.x == tr.x + 7:
				tr_next = station_record
	var tr_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(tr_middle.get("anchor", Vector3i.MAX))) if not tr_middle.is_empty() else null
	var tr_support: Node = tr_body.find_child("Support", true, false) if tr_body != null else null
	var tr_legs := 0
	var tr_ties := 0
	var tr_diagonals := 0
	var tr_stringers := 0
	var tr_stringer_between := false
	var tr_post_reaches := false
	if tr_support != null and not tr_next.is_empty():
		var middle_x := CoasterRails.ride_point(tr_middle).x
		var next_x := CoasterRails.ride_point(tr_next).x
		for child in tr_support.get_children():
			var child_name := str(child.name)
			if child_name == "Post" or child_name == "Post2":
				tr_legs += 1
			elif child_name.begins_with("Tie"):
				tr_ties += 1
			elif child_name.begins_with("Diagonal"):
				tr_diagonals += 1
			elif child_name.begins_with("Stringer"):
				tr_stringers += 1
				var centre_x := (child as Node3D).global_position.x
				if centre_x > minf(middle_x, next_x) and centre_x < maxf(middle_x, next_x):
					tr_stringer_between = true
		tr_post_reaches = absf(_post_bottom(tr_support) - float(tr.y)) < 0.05
	_record("T183_TRESTLE_TRUSS", tr_loaded and tr_laid.get("reason") == "CLIMB_PLACED" and tr_legs == 2 and tr_ties >= 1 and tr_diagonals >= 2 and tr_stringers >= 1 and tr_stringer_between and tr_post_reaches, "the middle piece of a climb (length 12, rise 6) carries a Support bent with two legs (Post, Post2) reaching the plate, at least one Tie, at least two Diagonal braces and at least one Stringer whose centre lies between this bent and the next piece's bent", {"loaded": tr_loaded, "laid": tr_laid.get("reason"), "middle": tr_middle.get("anchor"), "next": tr_next.get("anchor"), "legs": tr_legs, "ties": tr_ties, "diagonals": tr_diagonals, "stringers": tr_stringers, "stringer_between": tr_stringer_between, "post_reaches": tr_post_reaches})

	# T184 undo (owner 2026-09-20: "when I place something big improperly, it
	# takes forever to chop it down"): U / Ctrl+Z takes back the newest
	# placement - the climb just laid (its pieces, the items it cost), then a
	# single rail, then a rail line through a dirt bump with auto-clear on
	# (the bump comes back, the mined dirt goes back out of the pack).
	var un_pieces_before := ws.stations.size()
	var un_climb_pieces: Array[String] = []
	for station_id: String in ws.stations.keys():
		var station_record: Dictionary = ws.stations[station_id]
		if station_record.has("curve") and Vector3i(station_record.get("anchor", Vector3i.MAX)).z == tr.z and Vector3i(station_record.get("anchor", Vector3i.MAX)).x >= tr.x and Vector3i(station_record.get("anchor", Vector3i.MAX)).x <= tr.x + 12:
			un_climb_pieces.append(station_id)
	var un_climbs_before := app.session.inventory.count("rail_climb")
	var un_count_before := interaction.undo_count()
	# The key path needs a live player and an unpaused session for a frame.
	var un_was_paused: bool = app.session.simulation_paused
	app.session.simulation_paused = false
	app.session.player.activate(false)
	await get_tree().process_frame
	for pressed in [true, false]:
		var un_key := InputEventKey.new()
		un_key.keycode = KEY_U
		un_key.physical_keycode = KEY_U
		un_key.pressed = pressed
		Input.parse_input_event(un_key)
		await get_tree().process_frame
	await get_tree().process_frame
	app.session.player.deactivate()
	app.session.simulation_paused = un_was_paused
	var un_climb_gone := true
	for station_id: String in un_climb_pieces:
		if ws.stations.has(station_id):
			un_climb_gone = false
	var un_visual_gone := true
	for station_id: String in un_climb_pieces:
		if app.session._station_visuals.has(station_id):
			un_visual_gone = false
	var un_climb_refund := app.session.inventory.count("rail_climb") - un_climbs_before
	var un_key_used: bool = interaction.undo_count() == un_count_before - 1 and ws.stations.size() == un_pieces_before - un_climb_pieces.size()
	# A single rail, undone by the service call.
	_hotbar_slot_for("rail", 0)
	var un_rail_cell := tr + Vector3i(2, 0, 4)
	var un_rails_before := app.session.inventory.count("rail")
	var un_rail := interaction.try_place_item(un_rail_cell, "rail")
	var un_rail_id := ws.station_at_cell(un_rail_cell)
	var un_rail_undo := interaction.undo_last()
	var un_rail_gone: bool = un_rail.get("ok", false) and not un_rail_id.is_empty() and not ws.stations.has(un_rail_id) and app.session.inventory.count("rail") == un_rails_before
	# A rail line through a dirt bump with auto-clear on: the bump returns.
	if not interaction.auto_clear:
		app._toggle_track_auto_clear()
	var un_line_anchor := tr + Vector3i(4, 0, 5)
	world.set_cell(un_line_anchor + Vector3i(2, 0, 0), 1)
	var un_dirt_before := app.session.inventory.count("dirt")
	interaction.begin_entity_line_at(un_line_anchor)
	interaction.set_drag_end(un_line_anchor + Vector3i(3, 0, 0))
	var un_line := interaction.commit_drag_place()
	var un_line_cleared: bool = un_line.get("reason") == "LINE_PLACED" and int(un_line.get("changes", {}).get("cleared", 0)) == 1 and app.session.inventory.count("dirt") == un_dirt_before + 1
	var un_line_undo := interaction.undo_last()
	var un_bump_back: bool = int(world.query_cell(un_line_anchor + Vector3i(2, 0, 0)).get("voxel_id", 0)) == 1 and app.session.inventory.count("dirt") == un_dirt_before and app.session.inventory.count("rail") == un_rails_before
	var un_line_gone := true
	for step in range(4):
		if not ws.station_at_cell(un_line_anchor + Vector3i(step, 0, 0)).is_empty():
			un_line_gone = false
	app._toggle_track_auto_clear()
	var un_empty := interaction.undo_last()
	_record("T184_UNDO", not un_climb_pieces.is_empty() and un_key_used and un_climb_gone and un_visual_gone and un_climb_refund == un_climb_pieces.size() and un_rail_gone and un_rail_undo.get("reason") == "UNDONE" and un_line_cleared and un_line_undo.get("reason") == "UNDONE" and un_bump_back and un_line_gone, "pressing U removes every piece of the climb just laid (records and visuals) and hands back one Rail Climb per piece, popping one undo entry; a single rail placed then undone is gone with its rail back; a rail line that auto-cleared a dirt bump, undone, loses its rails, the bump is back and the mined dirt leaves the pack", {"climb_pieces": un_climb_pieces.size(), "key_used": un_key_used, "climb_gone": un_climb_gone, "visual_gone": un_visual_gone, "climb_refund": un_climb_refund, "rail_gone": un_rail_gone, "rail_undo": un_rail_undo.get("reason"), "line_cleared": un_line_cleared, "line": un_line.get("reason"), "line_undo": un_line_undo.get("reason"), "bump_back": un_bump_back, "line_gone": un_line_gone, "empty": un_empty.get("reason")})

	# T185 one track style (owner playtest 2026-09-21: "I would like them
	# updated to match the newer 'curvable' pieces ... it would be nice if
	# curves transitioned smoothly"): on a levelled plate a plain-rail L
	# corner, a rail-slope-rail run, a rail-curve-rail run (radius 4) and a
	# rail-loop-rail (true loop, diameter 6). The corner is a round arc (no
	# RailArms plate, >= 5 sections), no rail / slope carries the old stone
	# posts or oak deck, and every joint's rail ends meet (`rail_end_gap`).
	var ts := Vector3i(-40, 0, 84)
	var ts_loaded := await _wait_levelled(ts + Vector3i(-2, 0, -2), 32, 12, 12, [ts, ts + Vector3i(2, 0, 2), ts + Vector3i(12, 0, 6), ts + Vector3i(24, 0, 3)] as Array[Vector3i])
	interaction.creative = false
	app.session.inventory.try_transaction({}, {"rail": 24, "rail_slope": 2, "rail_curve": 24, "rail_loop": 48})
	var ts_placed := true
	# The L corner: -x and +z neighbours of the corner cell.
	var ts_corner := ts + Vector3i(2, 0, 0)
	for cell: Vector3i in [ts, ts + Vector3i(1, 0, 0), ts_corner, ts_corner + Vector3i(0, 0, 1), ts_corner + Vector3i(0, 0, 2)]:
		ts_placed = ts_placed and bool(ws.try_place("rail", cell, world.query_cell, AABB(), 0).get("ok", false))
	# The slope run: two rails, a slope rising +x, two rails on a stone step.
	var ts_slope_row := ts + Vector3i(0, 0, 5)
	for x in [3, 4]:
		world.set_cell(ts_slope_row + Vector3i(x, 0, 0), 3)
	for x in [0, 1]:
		ts_placed = ts_placed and bool(ws.try_place("rail", ts_slope_row + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var ts_slope := ws.try_place("rail_slope", ts_slope_row + Vector3i(2, 0, 0), world.query_cell, AABB(), 1)
	ts_placed = ts_placed and bool(ts_slope.get("ok", false))
	for x in [3, 4]:
		ts_placed = ts_placed and bool(ws.try_place("rail", ts_slope_row + Vector3i(x, 1, 0), world.query_cell, AABB(), 0).get("ok", false))
	# The curve run: a radius-4 90-degree bend heading +x, rails at both ends.
	var ts_curve := ts + Vector3i(9, 0, 2)
	_hotbar_slot_for("rail_curve", 4)
	interaction.placement_rotation_quarters = 1
	interaction.begin_curve_at(ts_curve)
	interaction.set_curve_sweep(90, false)
	interaction.set_curve_radius(4)
	var ts_curve_laid := interaction.commit_drag_place()
	var ts_curve_exit: Vector3i = ts_curve_laid.get("changes", {}).get("exit", ts_curve)
	for step in [1, 2]:
		ts_placed = ts_placed and bool(ws.try_place("rail", ts_curve - Vector3i(step, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
		ts_placed = ts_placed and bool(ws.try_place("rail", ts_curve_exit + Vector3i(0, 0, step), world.query_cell, AABB(), 0).get("ok", false))
	# The true loop: diameter 6 heading +x, rails behind the entry and
	# beyond the exit one lane right.
	var ts_loop := ts + Vector3i(23, 0, 2)
	_hotbar_slot_for("rail_loop", 2)
	interaction.loop_true = true
	interaction.begin_coaster_loop_at(ts_loop)
	interaction.set_loop_diameter(6)
	var ts_loop_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var ts_loop_exit: Vector3i = CoasterRails.helix_layout(ts_loop, 1, 6).exit
	for step in [1, 2]:
		ts_placed = ts_placed and bool(ws.try_place("rail", ts_loop - Vector3i(step, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
		ts_placed = ts_placed and bool(ws.try_place("rail", ts_loop_exit + Vector3i(step, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	await get_tree().process_frame
	# The corner: round, no arms plate.
	var ts_corner_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(ts_corner))
	var ts_corner_arms := ts_corner_body != null and ts_corner_body.get_node_or_null("RailArms") != null
	var ts_corner_plate := ts_corner_body != null and ts_corner_body.find_child("JunctionPlate", true, false) != null
	var ts_corner_sections := _track_sections(ts_corner_body).size()
	# The old block style must be gone from every rail and slope on the plate,
	# and every joint's rail ends must meet.
	var ts_tracks := CoasterRails.track_records(ws.stations)
	var ts_posts := 0
	var ts_decks := 0
	var ts_pieces := 0
	var ts_joints := 0
	var ts_max_gap := 0.0
	var ts_worst: Array = []
	for station_id: String in ws.stations.keys():
		var station_record: Dictionary = ws.stations[station_id]
		var station_anchor: Vector3i = station_record.get("anchor", Vector3i.MAX)
		if station_anchor.x < ts.x - 2 or station_anchor.x > ts.x + 30 or station_anchor.z < ts.z - 2 or station_anchor.z > ts.z + 10 or not CoasterRails.is_track_id(str(station_record.get("entity_id", ""))):
			continue
		ts_pieces += 1
		var station_body: Node3D = app.session._station_visuals.get(station_id)
		if station_body == null:
			continue
		if str(station_record.get("entity_id", "")) in ["rail", "rail_slope"]:
			for mesh_node: Node in station_body.find_children("*", "MeshInstance3D", true, false):
				var box: BoxMesh = (mesh_node as MeshInstance3D).mesh as BoxMesh
				if box == null:
					continue
				if box.size.is_equal_approx(Vector3(0.22, 0.56, 0.22)) or box.size.is_equal_approx(Vector3(0.22, 1.36, 0.22)):
					ts_posts += 1
				if box.size.is_equal_approx(Vector3(0.96, 0.36, 0.96)) or box.size.is_equal_approx(Vector3(0.96, 0.14, 1.36)):
					ts_decks += 1
		var own_ends := _track_sections(station_body)
		for other_cell: Vector3i in CoasterRails.connected_cells(station_record, ts_tracks):
			var other_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(other_cell))
			if other_body == null:
				continue
			ts_joints += 1
			var gap := _rail_end_gap(own_ends, _track_sections(other_body))
			if gap > ts_max_gap:
				ts_max_gap = gap
				ts_worst = [station_anchor, other_cell]
	_record("T185_TRACK_STYLE", ts_loaded and ts_placed and ts_curve_laid.get("reason") == "CURVE_PLACED" and ts_loop_laid.get("reason") == "LOOP_PLACED" and not ts_corner_arms and not ts_corner_plate and ts_corner_sections >= 5 and ts_posts == 0 and ts_decks == 0 and ts_pieces >= 30 and ts_joints >= 30 and ts_max_gap < 0.02, "a plain-rail L corner on a levelled plate draws a round arc (no RailArms plate, at least 5 rail sections), no rail or slope in a rail-slope-rail run carries the old stone posts or oak deck, and across the corner, the slope run, a rail-curve-rail run (radius 4) and a rail-loop-rail true loop (diameter 6) every joined pair's rail ends meet within 0.02 (rail_end_gap)", {"loaded": ts_loaded, "placed": ts_placed, "curve": ts_curve_laid.get("reason"), "loop": ts_loop_laid.get("reason"), "corner_arms": ts_corner_arms, "corner_plate": ts_corner_plate, "corner_sections": ts_corner_sections, "posts": ts_posts, "decks": ts_decks, "pieces": ts_pieces, "joints": ts_joints, "rail_end_gap": ts_max_gap, "worst_joint": ts_worst})

	# T186 smooth track (owner playtest 2026-09-21: "the pieces standalone
	# are not even smooth ... starts flat, then suddenly shifts angle ... in
	# these corners, the rails are segmented"): a radius-4 curve and a 4 x 1
	# smooth switch between plain rails on their own plate. The switch's
	# lean (TrackCurve.up_at) is upright at both ends, at t 0.02 and at its
	# inflection, peaks between 3 degrees and the full bank and never steps
	# more than 2 degrees per 0.01 of t; the arc leans the full bank at its
	# middle and none at its ends; at every joint of both runs the two
	# pieces' end rings coincide (point within 0.02, across within 2
	# degrees); and every piece's rails and spine are one swept mesh (at most
	# three ArrayMesh surfaces), not boxes.
	var sm := Vector3i(48, 0, 62)
	var sm_loaded := await _wait_levelled(sm + Vector3i(-4, 0, -2), 12, 14, 6, [sm, sm + Vector3i(4, 0, 4), sm + Vector3i(0, 0, 8), sm + Vector3i(4, 0, 9)] as Array[Vector3i])
	app.session.inventory.try_transaction({}, {"rail": 12, "rail_curve": 24, "rail_switch": 16})
	var sm_placed := true
	_hotbar_slot_for("rail_curve", 4)
	interaction.placement_rotation_quarters = 1
	interaction.begin_curve_at(sm)
	interaction.set_curve_sweep(90, false)
	interaction.set_curve_radius(4)
	var sm_curve_laid := interaction.commit_drag_place()
	var sm_curve_exit: Vector3i = sm_curve_laid.get("changes", {}).get("exit", sm)
	for step in [1, 2]:
		sm_placed = sm_placed and bool(ws.try_place("rail", sm - Vector3i(step, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
		sm_placed = sm_placed and bool(ws.try_place("rail", sm_curve_exit + Vector3i(0, 0, step), world.query_cell, AABB(), 0).get("ok", false))
	var sm_bend := sm + Vector3i(0, 0, 8)
	_hotbar_slot_for("rail_switch", 5)
	interaction.set_curve_size(4, 1)
	interaction.begin_curve_tool_at(sm_bend)
	var sm_bend_laid := interaction.commit_drag_place()
	var sm_bend_exit := sm_bend + Vector3i(4, 0, 1)
	for step in [1, 2]:
		sm_placed = sm_placed and bool(ws.try_place("rail", sm_bend - Vector3i(step, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
		sm_placed = sm_placed and bool(ws.try_place("rail", sm_bend_exit + Vector3i(step, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	interaction.placement_rotation_quarters = 0
	await get_tree().process_frame
	# (a) the switch's lean along its S-bend.
	var sm_bend_curve: Dictionary = ws.station(ws.station_at_cell(sm_bend)).get("curve", {})
	var sm_bend_ends: Array[float] = []
	var sm_ends_flat := not sm_bend_curve.is_empty()
	for t: float in [0.0, 0.02, 0.5, 1.0]:
		var tilt := TrackCurve.tilt_degrees(sm_bend_curve, t)
		sm_bend_ends.append(snappedf(tilt, 0.01))
		sm_ends_flat = sm_ends_flat and tilt < 1.0
	var sm_max_tilt := 0.0
	var sm_max_step := 0.0
	var sm_previous_tilt := 0.0
	for index in range(101):
		var tilt := TrackCurve.tilt_degrees(sm_bend_curve, float(index) / 100.0)
		sm_max_tilt = maxf(sm_max_tilt, tilt)
		if index > 0:
			sm_max_step = maxf(sm_max_step, absf(tilt - sm_previous_tilt))
		sm_previous_tilt = tilt
	var sm_full_bank := TrackCurve.full_bank_degrees(sm_bend_curve)
	var sm_bend_ok: bool = sm_ends_flat and sm_max_tilt >= 3.0 and sm_max_tilt <= sm_full_bank + 1.0 and sm_max_step <= 2.0
	# (b) the arc: the full bank at its middle, none at its ends.
	var sm_arc_curve: Dictionary = ws.station(ws.station_at_cell(sm)).get("curve", {})
	var sm_arc_middle := TrackCurve.tilt_degrees(sm_arc_curve, 0.5)
	var sm_arc_full := TrackCurve.full_bank_degrees(sm_arc_curve)
	var sm_arc_start := TrackCurve.tilt_degrees(sm_arc_curve, 0.0)
	var sm_arc_end := TrackCurve.tilt_degrees(sm_arc_curve, 1.0)
	var sm_arc_ok: bool = not sm_arc_curve.is_empty() and absf(sm_arc_middle - sm_arc_full) < 1.0 and sm_arc_start < 0.01 and sm_arc_end < 0.01
	# (c) every joint's end rings coincide; (d) swept meshes, not boxes.
	var sm_tracks := CoasterRails.track_records(ws.stations)
	var sm_pieces := 0
	var sm_joints := 0
	var sm_max_gap := 0.0
	var sm_max_angle := 0.0
	var sm_worst: Array = []
	var sm_max_surfaces := 0
	var sm_box_rails := 0
	for station_id: String in ws.stations.keys():
		var station_record: Dictionary = ws.stations[station_id]
		var station_anchor: Vector3i = station_record.get("anchor", Vector3i.MAX)
		if station_anchor.x < sm.x - 4 or station_anchor.x > sm.x + 8 or station_anchor.z < sm.z - 2 or station_anchor.z > sm.z + 12 or not CoasterRails.is_track_id(str(station_record.get("entity_id", ""))):
			continue
		sm_pieces += 1
		var station_body: Node3D = app.session._station_visuals.get(station_id)
		if station_body == null:
			continue
		var surfaces := 0
		for mesh_node: Node in station_body.find_children("*", "MeshInstance3D", true, false):
			var instance := mesh_node as MeshInstance3D
			if instance.mesh is ArrayMesh:
				surfaces += (instance.mesh as ArrayMesh).get_surface_count()
			elif instance.mesh is BoxMesh and instance.get_parent() != null and instance.get_parent().has_meta("rail_length") and not (instance.mesh as BoxMesh).size.is_equal_approx(Vector3(0.10, 0.54, 0.10)):
				sm_box_rails += 1
		sm_max_surfaces = maxi(sm_max_surfaces, surfaces)
		var own_frames := _rail_end_frames(station_body)
		for other_cell: Vector3i in CoasterRails.connected_cells(station_record, sm_tracks):
			var other_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(other_cell))
			if other_body == null:
				continue
			sm_joints += 1
			var joint := _rail_joint_match(own_frames, _rail_end_frames(other_body))
			if float(joint[0]) > sm_max_gap or float(joint[1]) > sm_max_angle:
				sm_worst = [station_anchor, other_cell, joint]
			sm_max_gap = maxf(sm_max_gap, float(joint[0]))
			sm_max_angle = maxf(sm_max_angle, float(joint[1]))
	var sm_joints_ok: bool = sm_joints >= 20 and sm_max_gap < 0.02 and sm_max_angle < 2.0
	var sm_swept_ok: bool = sm_max_surfaces > 0 and sm_max_surfaces <= 3 and sm_box_rails == 0
	_record("T186_SMOOTH_TRACK", sm_loaded and sm_placed and sm_curve_laid.get("reason") == "CURVE_PLACED" and sm_bend_laid.get("reason") == "BEND_PLACED" and sm_bend_ok and sm_arc_ok and sm_joints_ok and sm_swept_ok, "a 4 x 1 smooth switch between plain rails leans (TrackCurve.up_at) within 1 degree of upright at t 0, 0.02, 0.5 and 1, peaks between 3 degrees and the full bank and never steps more than 2 degrees per 0.01 t; a radius-4 curve leans the full bank at its middle and none at its ends; at every joint of both runs the two pieces' end rings coincide (point within 0.02, across within 2 degrees); every piece's rails and spine are one swept ArrayMesh of at most three surfaces with no rail boxes", {"loaded": sm_loaded, "placed": sm_placed, "curve": sm_curve_laid.get("reason"), "bend": sm_bend_laid.get("reason"), "bend_tilt_at_0_002_05_1": sm_bend_ends, "bend_max_tilt": snappedf(sm_max_tilt, 0.01), "bend_max_step": snappedf(sm_max_step, 0.001), "full_bank": snappedf(sm_full_bank, 0.01), "arc_middle": snappedf(sm_arc_middle, 0.01), "arc_ends": [snappedf(sm_arc_start, 0.001), snappedf(sm_arc_end, 0.001)], "pieces": sm_pieces, "joints": sm_joints, "joint_gap": snappedf(sm_max_gap, 0.0001), "joint_angle": snappedf(sm_max_angle, 0.01), "worst_joint": sm_worst, "max_surfaces": sm_max_surfaces, "box_rails": sm_box_rails})
	# T187 snap to a track end (owner playtest 2026-09-21 item 2: "give the
	# piece it is going to attach to a color highlight, like yellow,
	# indicating that a connect was made"): three plain rails heading +x on a
	# levelled plate report exactly two open ends; a Rail Curve press aimed
	# one cell beside and one short of the run's end snaps its entry onto the
	# end's free cell heading +x, names the last rail (SnapHint on the ghost),
	# clears when aimed three cells away, and the snapped lay joins the run.
	# (46, 0, 0): clear of T186's plate at (48, 0, 62), which overlapped the old (46, 0, 66).
	var sn := Vector3i(46, 0, 0)
	var sn_loaded := await _wait_levelled(sn + Vector3i(-3, 0, -4), 16, 14, 8, [sn, sn + Vector3i(2, 0, 0), sn + Vector3i(6, 0, 4)] as Array[Vector3i])
	interaction.creative = false
	app.session.inventory.try_transaction({}, {"rail": 8, "rail_curve": 24, "mine_cart": 1})
	var sn_placed := true
	var sn_rail_ids: Array[String] = []
	for x in range(3):
		var sn_rail := ws.try_place("rail", sn + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
		sn_placed = sn_placed and bool(sn_rail.get("ok", false))
		sn_rail_ids.append(str(sn_rail.get("details", {}).get("station", {}).get("instance_id", ws.station_at_cell(sn + Vector3i(x, 0, 0)))))
	var sn_last_id := ws.station_at_cell(sn + Vector3i(2, 0, 0))
	var sn_next := sn + Vector3i(3, 0, 0)
	# Open ends of the run: exactly its two ends, west of the first rail and
	# east of the last, heading out of the run.
	var sn_ends: Array = []
	for end: Dictionary in CoasterRails.open_ends(CoasterRails.track_records(ws.stations)):
		if sn_rail_ids.has(str(end.instance_id)):
			sn_ends.append({"cell": end.cell, "next": end.next, "along": end.along})
	var sn_west := false
	var sn_east := false
	for end: Dictionary in sn_ends:
		if Vector3i(end.next) == sn - Vector3i(1, 0, 0) and Vector3i(end.cell) == sn and Vector3(end.along).is_equal_approx(Vector3(-1, 0, 0)):
			sn_west = true
		if Vector3i(end.next) == sn_next and Vector3i(end.cell) == sn + Vector3i(2, 0, 0) and Vector3(end.along).is_equal_approx(Vector3(1, 0, 0)):
			sn_east = true
	var sn_two_ends: bool = sn_ends.size() == 2 and sn_west and sn_east
	# The press: straight down onto the cell one beside (+z) and one short (-x)
	# of the free cell, with the build orientation north (0).
	_hotbar_slot_for("rail_curve", 4)
	interaction.placement_rotation_quarters = 0
	interaction.set_curve_sweep(90, false)
	interaction.set_curve_radius(4)
	var sn_raw := sn_next + Vector3i(-1, 0, 1)
	var sn_press := interaction.begin_drag_place(Vector3(sn_raw) + Vector3(0.5, 3.0, 0.5), Vector3.DOWN)
	var sn_state := interaction.drag_state()
	var sn_snap: Dictionary = sn_state.get("snap", {})
	var sn_snapped: bool = str(sn_state.get("mode", "")) == "curve" and str(sn_snap.get("instance_id", "")) == sn_last_id and Vector3i(sn_snap.get("next", Vector3i.MAX)) == sn_next and Vector3i(sn_state.get("anchor", Vector3i.MAX)) == sn_next and int(sn_state.get("rotation_quarters", -1)) == 1
	app.session._update_drag_preview(sn_state)
	var sn_hint_shown: bool = app.session._placement_preview != null and app.session._placement_preview.get_node_or_null("SnapHint") != null
	# Aimed three cells away: the snap clears and the hint goes.
	var sn_far := sn_next + Vector3i(3, 0, 3)
	sn_state = interaction.update_drag_place(Vector3(sn_far) + Vector3(0.5, 3.0, 0.5), Vector3.DOWN, false)
	var sn_cleared: bool = (sn_state.get("snap", {}) as Dictionary).is_empty() and Vector3i(sn_state.get("anchor", Vector3i.MAX)) == sn_far
	app.session._update_drag_preview(sn_state)
	var sn_hint_gone: bool = app.session._placement_preview != null and app.session._placement_preview.get_node_or_null("SnapHint") == null
	# Aimed back: snapped again; release lays the curve joined to the run.
	sn_state = interaction.update_drag_place(Vector3(sn_raw) + Vector3(0.5, 3.0, 0.5), Vector3.DOWN, false)
	var sn_resnapped: bool = str((sn_state.get("snap", {}) as Dictionary).get("instance_id", "")) == sn_last_id and Vector3i(sn_state.get("anchor", Vector3i.MAX)) == sn_next and int(sn_state.get("rotation_quarters", -1)) == 1
	var sn_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	var sn_exit: Vector3i = sn_laid.get("changes", {}).get("exit", sn_next)
	for step in [1, 2]:
		sn_placed = sn_placed and bool(ws.try_place("rail", sn_exit + Vector3i(0, 0, step), world.query_cell, AABB(), 0).get("ok", false))
	var sn_chain := CoasterRails.chain(ws.stations, sn)
	var sn_joined: bool = sn_chain.has(sn_next) and sn_chain.has(sn_exit) and sn_chain.has(sn_exit + Vector3i(0, 0, 2)) and (sn_chain.get(sn + Vector3i(2, 0, 0), []) as Array).has(sn_next)
	var sn_cart := ws.try_place("mine_cart", sn + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var sn_cart_id := str(sn_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var sn_ride := _ride_cart(sn_cart_id, [sn_exit, sn_exit + Vector3i(0, 0, 2)] as Array[Vector3i], 900, sn_exit + Vector3i(0, 0, 2))
	var sn_rode: bool = (sn_ride.reached as Dictionary).has(sn_exit) and (sn_ride.reached as Dictionary).has(sn_exit + Vector3i(0, 0, 2))
	if sn_cart.get("ok", false):
		ws.try_dismantle(sn_cart_id, world.query_cell, AABB())
	_record("T187_SNAP_TO_END", sn_loaded and sn_placed and sn_two_ends and sn_press.get("reason") == "DRAG_STARTED" and sn_snapped and sn_hint_shown and sn_cleared and sn_hint_gone and sn_resnapped and sn_laid.get("reason") == "CURVE_PLACED" and sn_joined and sn_cart.get("ok", false) and sn_rode, "three plain rails heading +x report exactly two open ends (west of the first, east of the last, heading out); a Rail Curve right-press aimed one cell beside and one short of the run's free cell snaps: the entry is that cell, the heading +x (rotation 1), drag_state().snap names the last rail and the ghost carries a SnapHint; aimed three cells away the snap and hint clear; aimed back it re-snaps and release lays the curve (CURVE_PLACED) joined to the run, and a cart from the first rail rides through the curve past its exit", {"loaded": sn_loaded, "placed": sn_placed, "ends": str(sn_ends), "two_ends": sn_two_ends, "press": sn_press.get("reason"), "snap": str(sn_snap), "snapped": sn_snapped, "hint_shown": sn_hint_shown, "cleared": sn_cleared, "hint_gone": sn_hint_gone, "resnapped": sn_resnapped, "laid": sn_laid.get("reason"), "exit": sn_exit, "joined": sn_joined, "cart": sn_cart.get("reason"), "reached": str(sn_ride.reached)})
	# T188 auto-shape (owner playtest 2026-09-21, items 3b + 4: "These 90
	# degree corners should be created automatically, no piece needed ...
	# Auto Lane Shift - 6 spaces"): plain rails laid through the interaction
	# service shape themselves. (a) A line heading +x and single rails
	# heading -z from its end: when both straights exist the three corner
	# cells become one radius-1.5 arc of rail_loop pieces, the straights
	# beyond stay plain, the chain runs end to end, both joins sit at rail
	# height 0.55 on the shared faces, the pack's rail count only moves by
	# the rail laid, a cart rides round; undoing the rail that triggered it
	# restores the plain rails and removes that rail. (b) Three rails in lane
	# 44 and three in lane 45 one cell further on become one s-bend of six
	# pieces a cart crosses. (c) A "+" of two lines stays plain rails.
	var as_anchor := Vector3i(-60, 0, 40)
	var as_loaded := await _wait_levelled(as_anchor + Vector3i(-3, 0, -6), 12, 20, 9, [as_anchor, as_anchor + Vector3i(3, 0, -4), as_anchor + Vector3i(5, 0, 5), as_anchor + Vector3i(2, 0, 12)] as Array[Vector3i])
	interaction.creative = false
	app.session.inventory.try_transaction({}, {"rail": 40, "mine_cart": 2})
	_hotbar_slot_for("rail", 0)
	interaction.placement_rotation_quarters = 0
	# (a) The elbow.
	interaction.begin_entity_line_at(as_anchor)
	interaction.set_drag_end(as_anchor + Vector3i(3, 0, 0))
	var as_line := interaction.commit_drag_place()
	var as_corner := as_anchor + Vector3i(3, 0, 0)
	var as_a := as_corner + Vector3i(-1, 0, 0)
	var as_b := as_corner + Vector3i(0, 0, -1)
	var as_b2 := as_corner + Vector3i(0, 0, -2)
	var as_early := true
	for step in [4, 3, 1]:
		var single := interaction.try_place_item(as_corner + Vector3i(0, 0, -step), "rail")
		as_early = as_early and single.get("reason") == "OK"
	# Every cell still plain: the corner has no straight beyond B yet.
	for cell: Vector3i in [as_a, as_corner, as_b]:
		as_early = as_early and str(ws.station(ws.station_at_cell(cell)).get("entity_id", "")) == "rail"
	var as_rails_before := app.session.inventory.count("rail")
	var as_trigger := interaction.try_place_item(as_b2, "rail")
	var as_rails_after := app.session.inventory.count("rail")
	var as_shaped: Array = as_trigger.get("changes", {}).get("shaped", [])
	var as_elbow := true
	var as_curve: Dictionary = {}
	for cell: Vector3i in [as_a, as_corner, as_b]:
		var piece := ws.station(ws.station_at_cell(cell))
		as_elbow = as_elbow and str(piece.get("entity_id", "")) == "rail_loop" and str(piece.get("auto_shaped", "")) == "elbow" and str(piece.get("curve", {}).get("kind", "")) == "arc"
		if as_curve.is_empty():
			as_curve = piece.get("curve", {})
	var as_radius := float(as_curve.get("params", {}).get("radius", 0.0))
	var as_straights := str(ws.station(ws.station_at_cell(as_a + Vector3i(-1, 0, 0))).get("entity_id", "")) == "rail" and str(ws.station(ws.station_at_cell(as_b2)).get("entity_id", "")) == "rail"
	var as_chain := CoasterRails.chain(ws.stations, as_anchor)
	var as_chain_ok := as_chain.size() == 8 and as_chain.has(as_corner + Vector3i(0, 0, -4)) and as_chain.has(as_corner)
	var as_start := TrackCurve.point(as_curve, 0.0) if not as_curve.is_empty() else Vector3.ZERO
	var as_end := TrackCurve.point(as_curve, 1.0) if not as_curve.is_empty() else Vector3.ZERO
	var as_joins_flush := as_start.is_equal_approx(Vector3(as_a) + Vector3(0.0, 0.55, 0.5)) and as_end.is_equal_approx(Vector3(as_b) + Vector3(0.5, 0.55, 0.0))
	var as_pack_ok := as_rails_after == as_rails_before - 1
	await get_tree().process_frame
	var as_tracks := CoasterRails.track_records(ws.stations)
	var as_max_gap := 0.0
	for cell: Vector3i in [as_a, as_corner, as_b]:
		var piece := ws.station(ws.station_at_cell(cell))
		var own_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(cell))
		for other_cell: Vector3i in CoasterRails.connected_cells(piece, as_tracks):
			var other_body: Node3D = app.session._station_visuals.get(ws.station_at_cell(other_cell))
			as_max_gap = maxf(as_max_gap, _rail_end_gap(_track_sections(own_body), _track_sections(other_body)))
	var as_cart := ws.try_place("mine_cart", as_anchor + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var as_cart_id := str(as_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var as_far := as_corner + Vector3i(0, 0, -4)
	var as_ride := _ride_cart(as_cart_id, [as_corner, as_far] as Array[Vector3i], 240, as_far)
	var as_home := _ride_cart(as_cart_id, [as_anchor] as Array[Vector3i], 240, as_anchor)
	var as_rode := (as_ride.reached as Dictionary).has(as_corner) and (as_ride.reached as Dictionary).has(as_far) and (as_home.reached as Dictionary).has(as_anchor)
	ws.try_dismantle(as_cart_id, world.query_cell, AABB(), false)
	# The kettle router (p3c) steps through the elbow too: from A2 toward the
	# far end its next cell is A, then C, then B, and its rail point on the
	# corner piece sits on the arc.
	var as_kettle_chain := app.session.siege_defense._rail_chain(as_anchor)
	var as_kettle_a := app.session.siege_defense._rail_step(as_kettle_chain, as_a + Vector3i(-1, 0, 0), as_far)
	var as_kettle_c := app.session.siege_defense._rail_step(as_kettle_chain, as_a, as_far)
	var as_kettle_b := app.session.siege_defense._rail_step(as_kettle_chain, as_corner, as_far)
	var as_kettle_point := app.session.siege_defense._rail_point(as_corner)
	var as_kettle_ok := as_kettle_a == as_a and as_kettle_c == as_corner and as_kettle_b == as_b and as_kettle_point.is_equal_approx(CoasterRails.ride_point(ws.station(ws.station_at_cell(as_corner))) + Vector3(0.0, 0.95, 0.0))
	# Undo the rail that triggered the elbow: plain rails back, that rail gone.
	var as_undo := interaction.undo_last()
	var as_restored := true
	for cell: Vector3i in [as_a, as_corner, as_b]:
		as_restored = as_restored and str(ws.station(ws.station_at_cell(cell)).get("entity_id", "")) == "rail"
	var as_undone: bool = as_undo.get("reason") == "UNDONE" and int(as_undo.get("changes", {}).get("replaced", 0)) == 3 and ws.station_at_cell(as_b2).is_empty() and app.session.inventory.count("rail") == as_rails_before
	# (b) The lane shift: three rails in lane 44, three in lane 45 one on.
	var as_shift := as_anchor + Vector3i(0, 0, 4)
	interaction.begin_entity_line_at(as_shift)
	interaction.set_drag_end(as_shift + Vector3i(2, 0, 0))
	var as_lane_a := interaction.commit_drag_place()
	interaction.begin_entity_line_at(as_shift + Vector3i(3, 0, 1))
	interaction.set_drag_end(as_shift + Vector3i(5, 0, 1))
	var as_lane_b := interaction.commit_drag_place()
	var as_shift_cells: Array[Vector3i] = [as_shift, as_shift + Vector3i(1, 0, 0), as_shift + Vector3i(2, 0, 0), as_shift + Vector3i(3, 0, 1), as_shift + Vector3i(4, 0, 1), as_shift + Vector3i(5, 0, 1)]
	var as_bend := true
	var as_bend_curve: Dictionary = {}
	for cell: Vector3i in as_shift_cells:
		var piece := ws.station(ws.station_at_cell(cell))
		as_bend = as_bend and str(piece.get("entity_id", "")) == "rail_loop" and str(piece.get("auto_shaped", "")) == "lane_shift" and str(piece.get("curve", {}).get("kind", "")) == "s_bend"
		if as_bend_curve.is_empty():
			as_bend_curve = piece.get("curve", {})
	var as_bend_flush := not as_bend_curve.is_empty() and TrackCurve.point(as_bend_curve, 0.0).is_equal_approx(Vector3(as_shift) + Vector3(0.0, 0.55, 0.5)) and TrackCurve.point(as_bend_curve, 1.0).is_equal_approx(Vector3(as_shift + Vector3i(5, 0, 1)) + Vector3(1.0, 0.55, 0.5))
	var as_bend_chain := CoasterRails.chain(ws.stations, as_shift).size() == 6
	var as_bend_cart := ws.try_place("mine_cart", as_shift + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var as_bend_cart_id := str(as_bend_cart.get("details", {}).get("station", {}).get("instance_id", ""))
	var as_bend_far := as_shift + Vector3i(5, 0, 1)
	var as_bend_ride := _ride_cart(as_bend_cart_id, [as_bend_far] as Array[Vector3i], 240, as_bend_far)
	var as_bend_home := _ride_cart(as_bend_cart_id, [as_shift] as Array[Vector3i], 240, as_shift)
	var as_bend_rode := (as_bend_ride.reached as Dictionary).has(as_bend_far) and (as_bend_home.reached as Dictionary).has(as_shift)
	ws.try_dismantle(as_bend_cart_id, world.query_cell, AABB(), false)
	# (c) A "+" of two lines: a crossroads stays plain rails.
	var as_cross := as_anchor + Vector3i(0, 0, 10)
	interaction.begin_entity_line_at(as_cross)
	interaction.set_drag_end(as_cross + Vector3i(4, 0, 0))
	var as_cross_a := interaction.commit_drag_place()
	interaction.begin_entity_line_at(as_cross + Vector3i(2, 0, -2))
	interaction.set_drag_end(as_cross + Vector3i(2, 0, 2))
	var as_cross_b := interaction.commit_drag_place()
	var as_cross_plain: bool = as_cross_a.get("reason") == "LINE_PLACED" and as_cross_b.get("reason") == "LINE_PLACED"
	for x in range(5):
		as_cross_plain = as_cross_plain and str(ws.station(ws.station_at_cell(as_cross + Vector3i(x, 0, 0))).get("entity_id", "")) == "rail"
	for z in [-2, -1, 1, 2]:
		as_cross_plain = as_cross_plain and str(ws.station(ws.station_at_cell(as_cross + Vector3i(2, 0, z))).get("entity_id", "")) == "rail"
	_record("T188_AUTO_SHAPE", as_loaded and as_line.get("reason") == "LINE_PLACED" and as_early and as_trigger.get("reason") == "RAILS_SHAPED_ELBOW" and as_shaped == ["elbow"] and as_elbow and is_equal_approx(as_radius, 1.5) and as_straights and as_chain_ok and as_joins_flush and as_pack_ok and as_max_gap < 0.02 and as_cart.get("ok", false) and as_rode and as_kettle_ok and as_restored and as_undone and as_lane_a.get("reason") == "LINE_PLACED" and as_lane_b.get("reason") == "RAILS_SHAPED_LANE_SHIFT" and as_bend and as_bend_flush and as_bend_chain and as_bend_rode and as_cross_plain, "plain rails (-60..-57, 40) then (-57, 36..39) stay plain until the straight beyond the corner exists; that rail turns the three corner cells into rail_loop pieces of one radius-1.5 arc (auto_shaped elbow) starting on A's far face and ending on B's far face at height 0.55, the straights beyond stay plain, the chain runs (-60,40)..(-57,36) as 8 cells, the pack's rails drop by the one laid, every joint's rail ends meet within 0.02, a cart rides round the corner and home, the kettle router steps A2 -> A -> C -> B with its rail point on the corner's arc; undo restores the three plain rails (replaced 3), removes the triggering rail and refunds it; three rails in lane 44 then three in lane 45 one cell on become one six-piece s_bend (auto_shaped lane_shift) from (-60,44)'s west face to (-55,45)'s east face that a cart crosses and returns; a '+' of two rail lines stays nine plain rails", {"loaded": as_loaded, "line": as_line.get("reason"), "early": as_early, "trigger": as_trigger.get("reason"), "shaped": as_shaped, "elbow": as_elbow, "radius": as_radius, "straights": as_straights, "chain": as_chain.size(), "start": as_start, "end": as_end, "joins_flush": as_joins_flush, "rails": [as_rails_before, as_rails_after], "rail_end_gap": as_max_gap, "cart": as_cart.get("reason"), "rode": as_rode, "ride": as_ride.reached, "kettle": as_kettle_ok, "kettle_steps": [as_kettle_a, as_kettle_c, as_kettle_b], "undo": as_undo.get("reason"), "replaced": as_undo.get("changes", {}).get("replaced"), "restored": as_restored, "undone": as_undone, "lane_a": as_lane_a.get("reason"), "lane_b": as_lane_b.get("reason"), "bend": as_bend, "bend_flush": as_bend_flush, "bend_chain": as_bend_chain, "bend_rode": as_bend_rode, "cross": as_cross_plain})

	# T189 a truss bridges other track (owner 2026-09-21: "when the Rail
	# Climb goes over a track piece, it should create a hole in its truss
	# system and not place supports on the track"): a climb of length 12 /
	# rise 6 crossing a plain-rail line under its middle - the pieces over
	# the line (and one cell either side) carry no Support; the bent before
	# the hole carries a Stringer reaching the first bent after it.
	var br := Vector3i(20, 0, 0)
	var br_loaded := await _wait_levelled(br + Vector3i(-3, 0, -5), 20, 11, 12, [br, br + Vector3i(6, 3, 0), br + Vector3i(12, 6, 0)] as Array[Vector3i])
	app.session.inventory.try_transaction({}, {"rail_climb": 40, "rail": 12})
	for z in range(-3, 4):
		ws.try_place("rail", br + Vector3i(6, 0, z), world.query_cell, AABB(), 0)
	_hotbar_slot_for("rail_climb", 7)
	interaction.placement_rotation_quarters = 1
	interaction.begin_climb_at(br)
	interaction.set_climb(12, 6)
	var br_laid := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	interaction.set_climb(CoasterRails.CLIMB_LENGTH_DEFAULT, CoasterRails.CLIMB_RISE_DEFAULT)
	await get_tree().process_frame
	var br_pieces: Dictionary = {}
	for station_id: String in ws.stations.keys():
		var station_record: Dictionary = ws.stations[station_id]
		if station_record.has("curve") and Vector3i(station_record.get("anchor", Vector3i.MAX)).z == br.z and Vector3i(station_record.get("anchor", Vector3i.MAX)).y > br.y:
			# One piece per column: the lowest (a steep cell stacks two pieces;
			# the upper one never carries a bent).
			var piece_anchor: Vector3i = station_record.get("anchor", Vector3i.ZERO)
			var kept: String = br_pieces.get(piece_anchor.x, "")
			if kept.is_empty() or Vector3i(ws.stations[kept].get("anchor", Vector3i.ZERO)).y > piece_anchor.y:
				br_pieces[piece_anchor.x] = station_id
	var hole_ok := true
	var hole_checked := 0
	for x in [br.x + 5, br.x + 6, br.x + 7]:
		if not br_pieces.has(x):
			continue
		hole_checked += 1
		var body: Node3D = app.session._station_visuals.get(br_pieces[x])
		if body != null and body.find_child("Support", true, false) != null:
			hole_ok = false
	var br_supported: Array[int] = []
	for x: int in br_pieces:
		var piece_body: Node3D = app.session._station_visuals.get(br_pieces[x])
		if piece_body != null and piece_body.find_child("Support", true, false) != null:
			br_supported.append(x)
	br_supported.sort()
	var before_id: String = br_pieces.get(br.x + 4, "")
	var after_x := -1
	for x in range(br.x + 8, br.x + 13):
		if br_pieces.has(x) and after_x < 0:
			var after_body: Node3D = app.session._station_visuals.get(br_pieces[x])
			if after_body != null and after_body.find_child("Support", true, false) != null:
				after_x = x
	var before_body: Node3D = app.session._station_visuals.get(before_id) if not before_id.is_empty() else null
	var before_support: Node = before_body.find_child("Support", true, false) if before_body != null else null
	var bridged := false
	var br_stringers: Array[float] = []
	var br_children: Array[String] = []
	if before_support != null and after_x > 0:
		for child in before_support.get_children():
			br_children.append(str(child.name))
			if str(child.name).begins_with("Stringer"):
				var centre_x := (child as Node3D).global_position.x
				br_stringers.append(centre_x)
				if centre_x > float(br.x + 5) + 0.5:
					bridged = true
	_record("T189_TRUSS_BRIDGE", br_loaded and br_laid.get("reason") == "CLIMB_PLACED" and hole_checked == 3 and hole_ok and before_support != null and after_x > 0 and bridged, "a climb (12 / 6) crossing a plain-rail line under its middle: the three pieces over the line and beside it carry no Support (a hole in the truss); the bent before the hole carries a Stringer whose centre lies past the hole's first cell, reaching the first bent after it", {"loaded": br_loaded, "laid": br_laid.get("reason"), "pieces": br_pieces.size(), "supported_x": str(br_supported), "piece_x": str(br_pieces.keys()), "stringers": str(br_stringers), "hole_checked": hole_checked, "hole_ok": hole_ok, "before": before_support != null, "after_x": after_x, "bridged": bridged})


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
	# One track style (2026-09-21): the lead-in turns a plain-rail corner
	# toward the camera so the round corner shows beside the loop.
	for cell: Vector3i in [origin + Vector3i(4, 0, 0), origin + Vector3i(4, 0, 1), origin + Vector3i(4, 0, 2)]:
		ws.try_place("rail", cell, world.query_cell, AABB(), 0)
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
	# Closer and looking down a little so the slope run and the corner in
	# front of the loop are in the frame (one track style, 2026-09-21).
	player.global_position = Vector3(origin) + Vector3(2.5, 5.5, 14.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = -0.3
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
	await _render_sweep()
	await _render_auto_shape()


## T172: a Rail Switch (smooth) and a Crossing with lead-in / exit rails and a
## mine cart on each, seen from above and behind (`coaster-smooth.png`).
func _render_smooth_pieces() -> void:
	var player := app.session.player
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var plate := Vector3i(10, 0, 30)
	_level_ground(plate, 24, 14, 9)
	app.session.inventory.try_transaction({}, {"rail_switch": 16, "rail_cross": 32, "rail": 16, "mine_cart": 2})
	interaction.placement_rotation_quarters = 1
	var bend_entry := Vector3i(14, 0, 33)
	_hotbar_slot_for("rail_switch", 4)
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

## T188 rendered: an auto-shaped elbow (rails laid as an L) and an auto
## lane shift (three rails, then three one lane over), each with a mine
## cart, seen from above and behind (`coaster-auto-shape.png`).
func _render_auto_shape() -> void:
	var player := app.session.player
	var ws := app.session.workstations
	var world := app.session.world
	var interaction := app.session.interaction
	var ap := Vector3i(-26, 0, 66)
	_level_ground(ap + Vector3i(-6, 0, -6), 22, 18, 9)
	app.session.inventory.try_transaction({}, {"rail": 24, "mine_cart": 2})
	_hotbar_slot_for("rail", 0)
	interaction.creative = false
	interaction.placement_rotation_quarters = 0
	# The elbow: five rails heading +x, then five heading +z from the end.
	interaction.begin_entity_line_at(ap)
	interaction.set_drag_end(ap + Vector3i(4, 0, 0))
	interaction.commit_drag_place()
	_hotbar_slot_for("rail", 0)
	interaction.begin_entity_line_at(ap + Vector3i(4, 0, 1))
	interaction.set_drag_end(ap + Vector3i(4, 0, 5))
	var elbow := interaction.commit_drag_place()
	var elbow_cart := ws.try_place("mine_cart", ap + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	# The lane shift: three rails in one lane, three in the next lane on.
	var sp := ap + Vector3i(0, 0, 8)
	# (The pack holds rails in several stacks: pick a stack before each line.)
	_hotbar_slot_for("rail", 0)
	interaction.begin_entity_line_at(sp)
	interaction.set_drag_end(sp + Vector3i(2, 0, 0))
	interaction.commit_drag_place()
	_hotbar_slot_for("rail", 0)
	interaction.begin_entity_line_at(sp + Vector3i(3, 0, 1))
	interaction.set_drag_end(sp + Vector3i(5, 0, 1))
	var shift := interaction.commit_drag_place()
	for x in range(1, 3):
		ws.try_place("rail", sp + Vector3i(-x, 0, 0), world.query_cell, AABB(), 0)
		ws.try_place("rail", sp + Vector3i(5 + x, 0, 1), world.query_cell, AABB(), 0)
	var shift_cart := ws.try_place("mine_cart", sp + Vector3i(-2, 1, 0), world.query_cell, AABB(), 0)
	if app.session.coaster_carts != null:
		for _frame in range(50):
			app.session.coaster_carts.advance(1.0 / 30.0, false)
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = Vector3(ap) + Vector3(3.0, 5.0, 13.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = -0.55
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var shape_texture := get_viewport().get_texture()
	var shape_image := shape_texture.get_image() if shape_texture != null else null
	var shape_path := app.data_root.path_join("coaster-auto-shape.png")
	if shape_image == null:
		_record("T188_AUTO_SHAPE_RENDERED", false, "an auto-shaped elbow and lane shift render in one 1280x720 view", {"path": shape_path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var shape_error := shape_image.save_png(shape_path)
	var shaped_parts := 0
	var shaped_pieces := 0
	for station_id: String in ws.stations.keys():
		var record: Dictionary = ws.stations[station_id]
		if record.has("auto_shaped"):
			shaped_pieces += 1
			var body: Node3D = app.session._station_visuals.get(station_id)
			if body != null:
				shaped_parts += body.find_children("*", "MeshInstance3D", true, false).size()
	_record("T188_AUTO_SHAPE_RENDERED", elbow.get("reason") == "RAILS_SHAPED_ELBOW" and shift.get("reason") == "RAILS_SHAPED_LANE_SHIFT" and elbow_cart.get("ok", false) and shift_cart.get("ok", false) and shape_error == OK and shape_image.get_size() == Vector2i(1280, 720) and shaped_pieces == 9 and shaped_parts >= 36, "an L of plain rails shaped into an elbow and two three-rail runs shaped into a lane shift, a mine cart on each, render in one 1280x720 view (nine auto-shaped pieces)", {"path": shape_path, "size": shape_image.get_size(), "error": shape_error, "elbow": elbow.get("reason"), "shift": shift.get("reason"), "elbow_cart": elbow_cart.get("reason"), "shift_cart": shift_cart.get("reason"), "shaped_pieces": shaped_pieces, "shaped_parts": shaped_parts})



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
	# The Rail Switch item (owner 2026-09-20: "updated to be smooth") is the
	# bend tool; no separate rail_bend item exists any more. Its entity keeps
	# its support because the loop element still lays it as its blocky
	# lane-shift piece.
	var bend: Dictionary = registry.entity("rail_switch")
	var bend_order := -1
	var bend_output := 0
	for recipe in registry.recipes_for("workbench"):
		if str(recipe.get("id", "")) == "rail_switch":
			bend_order = int(recipe.get("recipe_book_order", -1))
			bend_output = int(recipe.get("outputs", {}).get("rail_switch", 0))
	var content_ok: bool = str(bend.get("coaster_tool", "")) == "bend" and interaction.is_smooth_bend_item("rail_switch") and not interaction.is_linear_entity_item("rail_switch") and bend_order == 208 and bend_output == 8 and registry.max_stack("rail_switch") == 64 and ItemIconCatalog.missing_item_ids(["rail_switch"]).is_empty() and registry.item("rail_bend").is_empty() and registry.entity("rail_bend").is_empty() and CoasterRails.BEND_DEFAULT_LENGTH == 4 and CoasterRails.BEND_DEFAULT_LANES == 1
	var bx := Vector3i(8, 0, 30)
	_level_ground(bx + Vector3i(-4, 0, -4), 24, 12, 9)
	app.session.inventory.try_transaction({}, {"rail": 12, "rail_switch": 24, "mine_cart": 1})
	var placed := true
	for x in range(1, 4):
		placed = placed and bool(ws.try_place("rail", bx - Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false))
	var slot := _hotbar_slot_for("rail_switch", 4)
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
	var default_exit := bx + Vector3i(4, 0, 1)
	var default_count := ghost_cells.size()
	var default_shape: bool = default_count == CoasterRails.bend_piece_count(4, 1) and not ghost_cells.is_empty() and Vector3i(ghost_cells[0].cell) == bx and Vector3i(ghost_cells[ghost_cells.size() - 1].cell) == default_exit and int(ghost.get("curve_length", 0)) == 4 and int(ghost.get("curve_lanes", 0)) == 1
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
	var in_pack := app.session.inventory.count("rail_switch")
	var capped_ok: bool = capped < 40 and CoasterRails.bend_piece_count(capped, -3) <= in_pack and CoasterRails.bend_piece_count(capped + 1, -3) > in_pack
	interaction.set_curve_size(CoasterRails.BEND_DEFAULT_LENGTH, CoasterRails.BEND_DEFAULT_LANES)
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
	var before := app.session.inventory.count("rail_switch")
	var laid := interaction.commit_drag_place()
	var paid: bool = before - app.session.inventory.count("rail_switch") == default_count
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
	var mid_record: Dictionary = ws.station(ws.station_at_cell(bx + Vector3i(2, 0, 0)))
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
	_record("T170_SMOOTH_SWITCH", content_ok and placed and slot >= 0 and press_started.get("reason") == "DRAG_STARTED" and press_mode == "smooth_bend" and started.get("ok", false) and ghost_ok and default_shape and sized_ok and eleven == 11 and ten == 10 and capped_ok and red > 0 and nothing_laid and laid.get("reason") == "BEND_PLACED" and int(laid.get("changes", {}).get("count", 0)) == default_count and paid and chain_ok and rail_height and mid_between and drawn and cart.get("ok", false) and rode and home_frame > 0 and round_trip, "rail_switch (Rail Switch = the smooth lane switcher, coaster_tool bend, order 208, 8 per craft, stack 64, smooth-S icon; no rail_bend item or entity) ghosts an S-bend of rail_loop curve pieces from the entry to one lane right four cells on (the default 4 x 1); Shift-aim 10 ahead and 3 left sizes it (length 10, lanes -3, exit there); C / X make 11 / 10; the pack caps 40 to what 24 items pay for; a stone block on the path shows red and release lays nothing; release lays every piece for one item each; rails behind and ahead join into one chain while a rail beside the entry on the exit lane stays out; entry and exit ride at rail height and the middle rides between the lanes; the entry draws the loop track; a mine cart rides through to the far rail and back; the track survives a save round-trip", {"content_ok": content_ok, "placed": placed, "press": press_started.get("reason"), "press_mode": press_mode, "started": started.get("reason"), "ghost_ok": ghost_ok, "default_count": default_count, "default_shape": default_shape, "sized": [sized.get("curve_length"), sized.get("curve_lanes")], "sized_ok": sized_ok, "eleven": eleven, "ten": ten, "capped": capped, "capped_ok": capped_ok, "red": red, "refused": refused.get("reason"), "nothing_laid": nothing_laid, "laid": laid.get("reason"), "count": laid.get("changes", {}).get("count"), "paid": paid, "chain": chain.size(), "chain_ok": chain_ok, "entry_point": entry_point, "exit_point": exit_point, "mid_point": mid_point, "drawn": drawn, "cart": cart.get("reason"), "far_frame": far_frame, "home_frame": home_frame, "round_trip": round_trip, "restored": restored.get("reason")})


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
	# A plain-rail line crossing under the climb's middle: the truss leaves
	# a hole over it and bridges it (T189).
	for z in range(-3, 4):
		ws.try_place("rail", climb_origin + Vector3i(6, 0, z), world.query_cell, AABB(), 0)
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
	# Close enough that the trestle bents under the climb read (2026-09-20).
	player.global_position = Vector3(climb_origin) + Vector3(6.0, 3.6, 11.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = 0.06
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


## T186: the smooth sweep close up (`coaster-sweep-crossing.png`: the
## crossing's centre from `_render_smooth_pieces` with a plain-rail L
## corner laid in front of it; `coaster-sweep-uturn.png`: the radius-3
## U-turn from `_render_curves`), so a kink at a crossing's centre or ends,
## a stepped twist along a bend or a faceted corner would show.
func _render_sweep() -> void:
	var player := app.session.player
	var ws := app.session.workstations
	var world := app.session.world
	app.session.inventory.try_transaction({}, {"rail": 8})
	var corner_laid := true
	for cell: Vector3i in [Vector3i(16, 0, 42), Vector3i(17, 0, 42), Vector3i(18, 0, 42), Vector3i(18, 0, 43)]:
		corner_laid = corner_laid and bool(ws.try_place("rail", cell, world.query_cell, AABB(), 0).get("ok", false))
	await get_tree().process_frame
	var crossing_path := app.data_root.path_join("coaster-sweep-crossing.png")
	var crossing_error := await _capture_from(player, Vector3(21.5, 2.4, 46.0), Vector3(18.0, 0.55, 40.0), crossing_path)
	var uturn_path := app.data_root.path_join("coaster-sweep-uturn.png")
	var uturn_error := await _capture_from(player, Vector3(17.5, 3.2, 49.0), Vector3(10.5, 0.55, 53.5), uturn_path)
	_record("T186_SWEEP_RENDERED", corner_laid and crossing_error == OK and uturn_error == OK, "the crossing's centre with a plain-rail corner in front and the radius-3 U-turn render close up in coaster-sweep-crossing.png and coaster-sweep-uturn.png", {"crossing": crossing_path, "crossing_error": crossing_error, "uturn": uturn_path, "uturn_error": uturn_error, "corner_laid": corner_laid})


## Moves the (deactivated) player's eye to `from` looking at `target`,
## waits for the frame and saves the viewport to `path` (an Error).
func _capture_from(player: PlayerController, from: Vector3, target: Vector3, path: String) -> Error:
	var delta := target - from
	player.global_position = from
	player.rotation = Vector3(0.0, atan2(-delta.x, -delta.z), 0.0)
	player.look_pitch = atan2(delta.y, Vector2(delta.x, delta.z).length())
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(60):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	if image == null:
		return ERR_UNAVAILABLE
	return image.save_png(path)


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
	# Framed to show the whole bent, pads to cap (trusses, 2026-09-20).
	player.global_position = Vector3(origin) + Vector3(-3.0, 4.0, 15.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = -0.06
	player.apply_mouse_look(Vector2.ZERO)
	for _frame in range(60):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var supports_path := app.data_root.path_join("coaster-supports.png")
	var supports_image := get_viewport().get_texture().get_image()
	var supports_error := supports_image.save_png(supports_path) if supports_image != null else ERR_UNAVAILABLE
	_record("T181_SUPPORTS_RENDERED", line_laid and line_cells.size() >= 6 and line_posts == line_cells.size() and line_reach and loop_posts >= 4 and supports_error == OK, "a straight of rail_loop pieces laid five cells up grows a stone post per piece down to the plate, the true loop's lower pieces carry posts, and both render in coaster-supports.png", {"path": supports_path, "error": supports_error, "line_laid": line_laid, "line_cells": line_cells.size(), "line_posts": line_posts, "line_reach": line_reach, "loop_posts": loop_posts})


## The rail sections of a track piece's visual: [start, end] world points
## of every node carrying the `rail_length` meta (`GameSession._add_track_run`).
func _track_sections(body: Node3D) -> Array[Array]:
	var sections: Array[Array] = []
	if body == null:
		return sections
	for node: Node in body.find_children("*", "Node3D", true, false):
		if not node.has_meta("rail_length"):
			continue
		var section := node as Node3D
		var half: float = float(node.get_meta("rail_length")) * 0.5
		var along: Vector3 = section.global_transform.basis.z
		sections.append([section.global_position - along * half, section.global_position + along * half])
	return sections


## The end rings of a track piece's visual: [point, across] (world) for
## both ends of every node carrying the `rail_length` / `rail_across` meta
## (`GameSession._add_track_run`).
func _rail_end_frames(body: Node3D) -> Array[Array]:
	var frames: Array[Array] = []
	if body == null:
		return frames
	for node: Node in body.find_children("*", "Node3D", true, false):
		if not node.has_meta("rail_length") or not node.has_meta("rail_across"):
			continue
		var section := node as Node3D
		var half: float = float(node.get_meta("rail_length")) * 0.5
		var along: Vector3 = section.global_transform.basis.z
		var across: Array = node.get_meta("rail_across")
		frames.append([section.global_position + along * half, Vector3(across[0])])
		frames.append([section.global_position - along * half, Vector3(across[1])])
	return frames


## The closest pair of end rings of two pieces: [distance, angle between
## their across lines in degrees (sign-free)]; [INF, INF] when either has
## none. Joined pieces should share a ring, so a smooth joint reads ~[0, 0].
func _rail_joint_match(own: Array[Array], other: Array[Array]) -> Array:
	var best_distance := INF
	var best_angle := INF
	for frame: Array in own:
		for other_frame: Array in other:
			var distance: float = Vector3(frame[0]).distance_to(Vector3(other_frame[0]))
			if distance < best_distance:
				best_distance = distance
				best_angle = rad_to_deg(acos(clampf(absf(Vector3(frame[1]).dot(Vector3(other_frame[1]))), 0.0, 1.0)))
	return [best_distance, best_angle]


## The smallest distance between any rail end of one piece and any rail end
## of another (INF when either has none): joined pieces should meet at one
## point, so a well-drawn joint reads ~0.
func _rail_end_gap(own: Array[Array], other: Array[Array]) -> float:
	var gap := INF
	for section: Array in own:
		for end: Vector3 in section:
			for other_section: Array in other:
				for other_end: Vector3 in other_section:
					gap = minf(gap, end.distance_to(other_end))
	return gap


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
			# Collision meshes lag the voxels by a few frames; the Shift-aim
			# checks ray-cast against them (T173 flaked once on the export).
			for _settle in range(45):
				await get_tree().physics_frame
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
