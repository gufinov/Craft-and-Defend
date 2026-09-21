class_name CoasterCarAutomation
extends Node

## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): the rideable
## coaster car, its 1-9 speed keys, the hero model and the third-person
## toggle. Runs with `--coaster-car-automation=gate` (headless: T164-T166)
## and `--coaster-car-automation=visual` (needs a window: T167 renders
## `coaster-car.png` from the ride camera).

const CAR := "coaster_car"

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
	_write_json(app.data_root.path_join("coaster_car_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("COASTER_CAR_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("COASTER_CAR_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var session := app.session
	var player := session.player
	player.deactivate()
	session.simulation_paused = true
	var registry := session.registry
	var ws := session.workstations
	var world := session.world
	var interaction := session.interaction

	# T164 content: the car item, entity, recipe and icon.
	var car: Dictionary = registry.entity(CAR)
	var item: Dictionary = registry.item(CAR)
	var missing_icons := ItemIconCatalog.missing_item_ids([CAR])
	var recipe: Dictionary = {}
	for candidate in registry.recipes_for("workbench"):
		if str(candidate.get("id", "")) == CAR:
			recipe = candidate
	var inputs: Dictionary = recipe.get("inputs", {})
	var recipe_ok: bool = int(recipe.get("recipe_book_order", -1)) == 207 and inputs.size() == 3 and int(inputs.get("planks", 0)) == 4 and int(inputs.get("iron_ingot", 0)) == 2 and int(inputs.get("castle_stone", 0)) == 1 and int(recipe.get("outputs", {}).get(CAR, 0)) == 1
	var entity_ok: bool = float(car.get("cart", {}).get("rail_speed", 0.0)) == 3.0 and car.get("mount", {}).get("allowed", []) == ["rail_mount"] and str(car.get("attributes", {}).get("role", "")) == "rail" and not car.has("siege")
	var item_ok: bool = int(item.get("max_stack", 0)) == 2 and str(item.get("places_entity", "")) == CAR
	var ids_ok := CoasterRails.CAR == CAR and not CoasterRails.is_track_id(CAR)
	_record("T164_COASTER_CAR_CONTENT", missing_icons.is_empty() and recipe_ok and entity_ok and item_ok and ids_ok, "coaster_car is a stackable (2) building item placing a rail-mounted cart entity (rail speed 3, role rail) with an owner-art icon and a Workbench recipe at order 207 (4 planks + 2 iron ingot + 1 castle stone -> 1)", {"missing_icons": missing_icons, "recipe": recipe, "entity_ok": entity_ok, "item_ok": item_ok, "ids_ok": ids_ok})

	# T165 ride: a parked car on a loop fixture waits; Shift boards it; 1-9
	# set the speed (measured in cells per second); Shift leaves beside it.
	var anchor := Vector3i(-6, 0, 40)
	_level_ground(anchor + Vector3i(-10, 0, -4), 22, 8, 14)
	session.inventory.try_transaction({}, {"rail_loop": 4, CAR: 1})
	_hold_item("rail_loop")
	interaction.placement_rotation_quarters = 3
	interaction.loop_true = false
	interaction.set_loop_size(6)
	interaction.begin_coaster_loop_at(anchor)
	var committed := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	session.inventory.try_transaction({}, {"rail": 6})
	for x in range(1, 5):
		ws.try_place("rail", anchor + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var placed := ws.try_place(CAR, anchor + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	var car_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var carts := session.coaster_carts
	var parked_before := carts != null and carts.is_parked(car_id)
	var rig: Node3D = carts.cart_rig(car_id) if carts != null else null
	var rest := rig.global_position if rig != null else Vector3.ZERO
	if carts != null:
		for _frame in range(60):
			carts.advance(1.0 / 30.0, false)
	var stayed := rig != null and rig.global_position.distance_to(rest) < 0.001
	var car_body: Node3D = session._station_visuals.get(car_id)
	var car_parts := car_body.find_children("*", "MeshInstance3D", true, false).size() if car_body != null else 0
	var seat_ok := car_body != null and car_body.get_node_or_null("CartRig/Seat") != null
	# Shift from two cells south of the car, aiming at it, through the
	# interaction service (the same path the Interact key takes).
	for _frame in range(4):
		await get_tree().physics_frame
	var aim_origin := Vector3(anchor) + Vector3(3.5, 1.6, 3.0)
	var aim_target := Vector3(anchor) + Vector3(3.5, 1.4, 0.5)
	var boarded := interaction.interact_from_view(aim_origin, (aim_target - aim_origin).normalized())
	var ride := session.coaster_ride
	var riding_ok := session.is_riding() and ride.car_id == car_id and not player.active and ride.ride_camera().current and not player.camera.current
	var hero := ride.seated_hero()
	# The hero is hidden in the seat view and shown from the outside views.
	var hero_ok := hero != null and hero.seated and hero.mesh_count() >= 30 and hero.get_parent().name == "Seat" and not hero.visible and ride.select_view("back") == "back" and hero.visible and ride.select_view("back") == "seat" and not hero.visible
	var default_speed := ride.speed_level == 3 and carts.speed_of(car_id) == 3.0 and not carts.is_parked(car_id)
	var hud_ok := session.coaster_ride.hud_text().begins_with("RIDING · speed 3/9 · 1-9 speed · view seat")
	# Speed 2 for one second, then speed 6 for one second: path length.
	session.set_ride_speed(2)
	var slow := _measure_travel(carts, rig, 30)
	session.set_ride_speed(6)
	var fast := _measure_travel(carts, rig, 30)
	var speeds_ok := absf(slow - 2.0) < 0.2 and absf(fast - 6.0) < 0.5 and carts.speed_of(car_id) == 6.0
	# Keys while riding: 5 sets the speed and leaves the hotbar slot alone;
	# Shift (interact) leaves the car.
	session.simulation_paused = false
	var slot_before := session.inventory.selected_hotbar
	session._unhandled_input(_action_event("hotbar_5"))
	var key_speed := ride.speed_level == 5 and session.inventory.selected_hotbar == slot_before
	var rig_before_leave := rig.global_position
	# The leave press must come in a later frame than the boarding press
	# (the guard that stops one Shift from boarding and leaving at once).
	session._boarded_frame = -1
	session._unhandled_input(_action_event("interact"))
	session.simulation_paused = true
	var left := not session.is_riding() and player.active and player.camera.current and not ride.ride_camera().current and carts.is_parked(car_id) and ride.seated_hero() == null
	player.deactivate()
	var beside := Vector2(player.global_position.x - rig_before_leave.x, player.global_position.z - rig_before_leave.z).length()
	var beside_ok := absf(beside - 1.0) < 0.05 and absf(player.global_position.y - floorf(rig_before_leave.y)) < 0.01
	for _frame in range(30):
		carts.advance(1.0 / 30.0, false)
	var parked_after := rig.global_position.distance_to(rig_before_leave) < 0.001
	# A real Shift key press from the same spot: the press must board and
	# stay boarded (owner 2026-09-20: the same press reached the session's
	# input handler and left again).
	# The car parked where the ride ended (possibly up in the loop): stand
	# 3 m south of it and look at it.
	var key_origin := rig.global_position + Vector3(0.0, 1.6, 3.0)
	player.global_position = key_origin - Vector3(0.0, 1.6, 0.0)
	player.rotation = Vector3.ZERO
	player.look_pitch = atan2(-1.6, 3.0)
	player.apply_mouse_look(Vector2.ZERO)
	# The key path needs a live player and an unpaused session for one frame.
	session.simulation_paused = false
	player.activate(false)
	await get_tree().process_frame
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SHIFT
		key.physical_keycode = KEY_SHIFT
		key.pressed = pressed
		Input.parse_input_event(key)
		await get_tree().process_frame
	await get_tree().process_frame
	var key_boarded := session.is_riding()
	if key_boarded:
		session.leave_coaster_car()
		await get_tree().process_frame
	player.look_pitch = 0.0
	player.apply_mouse_look(Vector2.ZERO)
	player.deactivate()
	session.simulation_paused = true
	# The station snapshot keeps the car; the saved player stands beside it
	# even when the save happens mid-ride.
	var snapshot_ok := false
	if session.board_coaster_car(car_id).get("ok", false):
		var saved: Dictionary = session.snapshot()
		var saved_position: Array = saved.get("player", {}).get("position", [])
		var landing := ride.dismount_position()
		snapshot_ok = saved_position.size() == 3 and absf(float(saved_position[0]) - landing.x) < 0.01 and absf(float(saved_position[2]) - landing.z) < 0.01
		var stations: Dictionary = saved.get("workstations", {})
		snapshot_ok = snapshot_ok and JSON.stringify(stations).contains(CAR)
		session.leave_coaster_car()
		player.deactivate()
	_record("T165_COASTER_CAR_RIDE", committed.get("reason") == "LOOP_PLACED" and placed.get("ok", false) and parked_before and stayed and car_parts >= 30 and seat_ok and key_boarded and boarded.get("reason") == "COASTER_BOARDED" and riding_ok and hero_ok and default_speed and hud_ok and speeds_ok and key_speed and left and beside_ok and parked_after and snapshot_ok, "a coaster car placed on a loop's lead-in stays parked; Shift aimed at it boards (player parked, ride camera current, seated hero on the Seat node, speed 3/9 HUD); speed 2 then 6 move the car about 2 and 6 cells per second; the 5 key sets speed 5 without touching the hotbar; Shift leaves the player 1 m beside the parked car on the rail cell's floor; a mid-ride snapshot saves the player beside the car", {"key_boarded": key_boarded, "committed": committed.get("reason"), "placed": placed.get("reason"), "parked_before": parked_before, "stayed": stayed, "car_parts": car_parts, "seat": seat_ok, "boarded": boarded.get("reason"), "riding": riding_ok, "hero": hero_ok, "default_speed": default_speed, "hud": hud_ok, "slow_cells_per_second": slow, "fast_cells_per_second": fast, "key_speed": key_speed, "left": left, "beside": beside, "beside_ok": beside_ok, "parked_after": parked_after, "snapshot": snapshot_ok})

	# T166 hero: parts, the armoured swap, the walk cycle, the seated pose,
	# the third-person toggle and the persisted armour setting.
	var model := HeroModel.new()
	add_child(model)
	var plain := model.part_names()
	var plain_ok := model.mesh_count() >= 40 and _has_all(plain, ["Hair", "Face", "Tunic", "LionCrest", "Scarf", "Belt", "Bracer", "Boot", "Sword", "Blade", "LegL", "ArmR"]) and not plain.has("Breastplate")
	model.set_armored(true)
	var plated := model.part_names()
	var plated_ok := _has_all(plated, ["Breastplate", "Pauldron", "ShoulderDiamond", "Tabard", "Greave", "Vambrace", "Scarf", "Hair", "Sword"]) and not plated.has("Tunic")
	model.set_armored(false)
	for _step in range(12):
		model.animate_walk(1.0 / 30.0, true, 0.12)
	var leg: Node3D = model.get_node_or_null("HeroRig/LegL")
	var arm: Node3D = model.get_node_or_null("HeroRig/ArmR")
	var walks := leg != null and arm != null and absf(leg.rotation.x) > 0.05 and absf(arm.rotation.x) > 0.03
	model.set_seated(true)
	var sword: Node3D = model.get_node_or_null("HeroRig/ArmR/Sword")
	var seated_ok: bool = leg != null and not leg.visible and absf(arm.rotation.x - HeroModel.SEATED_ARM_PITCH) < 0.001 and sword != null and not sword.visible
	model.queue_free()
	var first_person := not player.third_person and not player.hero.visible and player.camera.position.is_equal_approx(Vector3(0.0, 1.6, 0.0))
	session.simulation_paused = false
	var toggled := session.toggle_third_person()
	session.simulation_paused = true
	var chase := player.third_person and player.hero.visible and player.camera.position.z > 3.0 and player.camera.position.y > 2.0
	var eye := player.view_origin()
	var eye_ok := eye.distance_to(player.global_position + Vector3(PlayerController.THIRD_PERSON_SHOULDER, 1.6, 0.0) + Vector3.UP * PlayerController.THIRD_PERSON_HEIGHT) < 0.6
	player.set_third_person(false)
	var back := not player.third_person and not player.hero.visible
	var armor_result := app.settings.set_hero_armored(true)
	app._refresh_hero_armor_button()
	var reloaded := SettingsStore.new(app.data_root)
	reloaded.load_and_apply()
	var persisted := reloaded.hero_armored
	session.set_hero_armored(true)
	var applied := player.hero.armored and session.coaster_ride.armored
	app.settings.set_hero_armored(false)
	session.set_hero_armored(false)
	var button_ok := app.hero_armor_button != null and app.hero_armor_button.text == "Hero: Armour on"
	app._refresh_hero_armor_button()
	button_ok = button_ok and app.hero_armor_button.text == "Hero: Armour off"
	_record("T166_HERO_MODEL_AND_THIRD_PERSON", plain_ok and plated_ok and walks and seated_ok and first_person and toggled and chase and eye_ok and back and armor_result.get("ok", false) and persisted and applied and not player.hero.armored and button_ok, "the hero model has hair, face, tunic, lion crest, scarf, belt, bracers, boots and a sword; armoured it swaps to breastplate, pauldrons with shoulder diamonds, tabard, greaves and vambraces; walking swings legs and arms; seated hides the legs and puts the arms on the bar; V moves the camera 3.5 m behind and above with the hero visible and the aim ray still from the eye; the pause-menu Hero: Armour toggle persists in settings.cfg and re-dresses the hero", {"plain_parts": plain.size(), "plain_ok": plain_ok, "plated_ok": plated_ok, "walks": walks, "seated": seated_ok, "first_person": first_person, "toggled": toggled, "chase": chase, "camera": player.camera.position, "eye_ok": eye_ok, "back": back, "armor_saved": armor_result.get("reason"), "persisted": persisted, "applied": applied, "button": button_ok})


	await _run_hauling()


## T195 hauling (docs/INDUSTRY.md): a mine cart on a straight loads from an
## ore bin beside cell 3 and unloads into a warehouse beside cell 9; a bin
## with 20 gives up 16 (CART_CARGO) and keeps 4; a mid-haul save keeps the
## cargo; the coaster car hauls nothing.
func _run_hauling() -> void:
	var session := app.session
	var player := session.player
	var ws := session.workstations
	var world := session.world
	var anchor := Vector3i(-40, 0, 60)
	_level_ground(anchor + Vector3i(-4, 0, -4), 20, 10, 6)
	session.inventory.try_transaction({}, {"rail": 12, "mine_cart": 1, CAR: 1})
	var rails_ok := true
	for x in range(12):
		rails_ok = rails_ok and ws.try_place("rail", anchor + Vector3i(x, 0, 0), world.query_cell, AABB(), 0).get("ok", false)
	var cart := ws.try_place("mine_cart", anchor + Vector3i(0, 1, 0), world.query_cell, AABB(), 0)
	var cart_id := str(cart.get("details", {}).get("station", {}).get("instance_id", ""))
	# The bin and the warehouse are placed free of an item (their cards add
	# the items; the entities here are the shared contract).
	var bin := ws.try_place(CoasterCartService.ORE_BIN, anchor + Vector3i(3, 0, 1), world.query_cell, AABB(), 0, {"_free": true})
	var bin_id := str(bin.get("details", {}).get("station", {}).get("instance_id", ""))
	var warehouse := ws.try_place(CoasterCartService.WAREHOUSE, anchor + Vector3i(9, 0, 1), world.query_cell, AABB(), 0, {"_free": true})
	var warehouse_id := str(warehouse.get("details", {}).get("station", {}).get("instance_id", ""))
	var stocked := ws.container_put(bin_id, "iron_ore", 10)
	var carts := session.coaster_carts
	var fixture_ok: bool = rails_ok and cart.get("ok", false) and bin.get("ok", false) and warehouse.get("ok", false) and stocked.get("ok", false) and carts != null and ws.container_slots(bin_id).size() == 9 and ws.container_slots(warehouse_id).size() == 27
	if not fixture_ok:
		_record("T195_HAULING", false, "fixture", {"rails": rails_ok, "cart": cart.get("reason"), "bin": bin.get("reason"), "warehouse": warehouse.get("reason"), "stocked": stocked.get("reason"), "carts": carts != null})
		return
	# The player stands by the track so the HUD reports the docks.
	player.global_position = Vector3(anchor) + Vector3(6.5, 0.0, 4.5)
	var lines: Array[String] = []
	var collect := func(message: String) -> void:
		lines.append(message)
	session.feedback_changed.connect(collect)
	var body: Node3D = session._station_visuals.get(cart_id)
	var heap: Node3D = body.get_node_or_null("CartRig/Cargo") if body != null else null
	var heap_hidden_before := heap != null and not heap.visible and heap.get_child_count() >= 3
	# Pass 1: 10 iron ore ride from the bin to the warehouse.
	var reached_mid := _advance_until_x(carts, cart_id, anchor, 6)
	var loaded_ten: bool = carts.cargo(cart_id) == {"iron_ore": 10} and ws.container_count(bin_id, "iron_ore") == 0 and ws.container_count(warehouse_id, "iron_ore") == 0
	var heap_shown := heap != null and heap.visible
	var load_line := lines.has("Cart loaded 10 iron ore")
	session._haul_notice_msec = -100000
	var reached_end := _advance_until_x(carts, cart_id, anchor, 11)
	var unloaded_ten: bool = carts.cargo(cart_id).is_empty() and ws.container_count(warehouse_id, "iron_ore") == 10 and ws.container_count(bin_id, "iron_ore") == 0
	var heap_hidden_after := heap != null and not heap.visible
	var unload_line := lines.has("Cart unloaded 10 iron ore")
	# Pass 2 (the cart turns around at the end and rides back): 20 in the bin,
	# the cart takes 16 and 4 stay; the cargo survives a mid-haul save.
	ws.container_put(bin_id, "iron_ore", 20)
	var reached_home := _advance_until_x(carts, cart_id, anchor, 0)
	var took_sixteen: bool = carts.cargo(cart_id) == {"iron_ore": 16} and ws.container_count(bin_id, "iron_ore") == 4
	var saved: Variant = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var restored := ws.restore(saved, world.query_cell) if saved is Dictionary else {"ok": false, "reason": "SNAPSHOT_NOT_JSON"}
	var round_trip: bool = restored.get("ok", false) and ws.station(cart_id).get("cargo", {}) == {"iron_ore": 16} and ws.container_count(bin_id, "iron_ore") == 4
	# Back past the bin (no second load: it holds 4, the cart is full anyway
	# and the bin cell was the last dock) to the warehouse.
	var reached_end_again := _advance_until_x(carts, cart_id, anchor, 11)
	var unloaded_sixteen: bool = carts.cargo(cart_id).is_empty() and ws.container_count(warehouse_id, "iron_ore") == 26 and ws.container_count(bin_id, "iron_ore") == 4
	# The coaster car rides the same straight and hauls nothing.
	carts.set_parked(cart_id, true)
	var car := ws.try_place(CAR, anchor + Vector3i(5, 1, 0), world.query_cell, AABB(), 0)
	var car_id := str(car.get("details", {}).get("station", {}).get("instance_id", ""))
	carts.set_parked(car_id, false)
	var car_reached := _advance_until_x(carts, car_id, anchor, 11) and _advance_until_x(carts, car_id, anchor, 0)
	var car_hauls_nothing: bool = car.get("ok", false) and car_reached and carts.cargo(car_id).is_empty() and ws.container_count(bin_id, "iron_ore") == 4 and ws.container_count(warehouse_id, "iron_ore") == 26
	session.feedback_changed.disconnect(collect)
	_record("T195_HAULING", heap_hidden_before and reached_mid and loaded_ten and heap_shown and load_line and reached_end and unloaded_ten and heap_hidden_after and unload_line and reached_home and took_sixteen and round_trip and reached_end_again and unloaded_sixteen and car_hauls_nothing, "a mine cart passing an ore bin (10 iron ore) beside cell 3 loads it all (HUD: Cart loaded 10 iron ore, the Cargo heap shows) and unloads it into the warehouse beside cell 9 (HUD: Cart unloaded 10 iron ore, heap hidden); from a bin with 20 it takes 16 and 4 stay; a mid-haul save round-trip keeps the 16; the warehouse ends with 26; a coaster car riding the same straight hauls nothing", {"heap_hidden_before": heap_hidden_before, "reached_mid": reached_mid, "loaded_ten": loaded_ten, "heap_shown": heap_shown, "load_line": load_line, "reached_end": reached_end, "unloaded_ten": unloaded_ten, "heap_hidden_after": heap_hidden_after, "unload_line": unload_line, "reached_home": reached_home, "took_sixteen": took_sixteen, "round_trip": round_trip, "restored": restored.get("reason"), "reached_end_again": reached_end_again, "unloaded_sixteen": unloaded_sixteen, "car_hauls_nothing": car_hauls_nothing, "lines": lines})


## Advances the cart service until the cart's rider cell is `anchor + x`
## (at most 20 s of 1/30 s steps); true when it got there.
func _advance_until_x(carts: CoasterCartService, cart_id: String, anchor: Vector3i, x: int) -> bool:
	for _frame in range(600):
		if carts.rider_cell(cart_id) == anchor + Vector3i(x, 0, 0):
			return true
		carts.advance(1.0 / 30.0, false)
	return carts.rider_cell(cart_id) == anchor + Vector3i(x, 0, 0)


## Rendered evidence: the hero riding the coaster car over the sandbox loop
## from the ride camera, 1280x720.
func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var session := app.session
	var player := session.player
	player.deactivate()
	session.simulation_paused = true
	var ws := session.workstations
	var world := session.world
	var interaction := session.interaction
	var origin := Vector3i(-2, 0, 36)
	_level_ground(origin + Vector3i(-10, 0, -6), 22, 14, 14)
	session.inventory.try_transaction({}, {"rail_loop": 4, CAR: 1})
	_hold_item("rail_loop")
	interaction.placement_rotation_quarters = 3
	interaction.loop_true = false
	interaction.set_loop_size(6)
	interaction.begin_coaster_loop_at(origin)
	var committed := interaction.commit_drag_place()
	interaction.placement_rotation_quarters = 0
	session.inventory.try_transaction({}, {"rail": 6})
	for x in range(1, 5):
		ws.try_place("rail", origin + Vector3i(x, 0, 0), world.query_cell, AABB(), 0)
	var placed := ws.try_place(CAR, origin + Vector3i(3, 1, 0), world.query_cell, AABB(), 0)
	var car_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	for _frame in range(4):
		await get_tree().physics_frame
	session.set_hero_armored(false)
	var boarded := session.board_coaster_car(car_id)
	# Picture from behind the car so the seated hero is in it.
	session.coaster_ride.select_view("back")
	session.set_ride_speed(4)
	var carts := session.coaster_carts
	# Into the loop's climb so the picture shows the car leaning into the circle.
	if carts != null:
		for _frame in range(84):
			carts.advance(1.0 / 30.0, false)
			session.coaster_ride.advance(1.0 / 30.0)
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("coaster-car.png")
	if image == null:
		_record("T167_COASTER_CAR_RENDERED", false, "the hero riding the coaster car over a loop renders from the ride camera in one 1280x720 view", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var car_body: Node3D = session._station_visuals.get(car_id)
	var car_parts := car_body.find_children("*", "MeshInstance3D", true, false).size() if car_body != null else 0
	var hero := session.coaster_ride.seated_hero()
	var hero_parts := hero.mesh_count() if hero != null else 0
	var cell := carts.rider_cell(car_id) if carts != null else Vector3i(0, -9999, 0)
	var camera_current := session.coaster_ride.ride_camera().current
	var rig_node: Node3D = carts.cart_rig(car_id) if carts != null else null
	print("COASTER_CAR_VISUAL camera=%s rig=%s rig_basis=%s player=%s" % [session.coaster_ride.ride_camera().global_position, rig_node.global_position if rig_node != null else null, rig_node.global_basis if rig_node != null else null, player.global_position])
	# Bonus evidence (not gated): both hero looks facing the player, `hero.png`.
	session.leave_coaster_car()
	player.deactivate()
	var stage := Vector3(origin) + Vector3(4.5, 0.0, 10.5)
	for index in range(2):
		var model := HeroModel.new()
		model.position = stage + Vector3(-1.0 + 2.0 * float(index), 0.0, 0.0)
		model.rotation.y = PI
		session.add_child(model)
		model.set_armored(index == 1)
	player.global_position = stage + Vector3(0.0, 0.0, 4.2)
	player.rotation.y = 0.0
	player.look_pitch = -0.12
	player.camera.rotation.x = -0.12
	for _frame in range(60):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var hero_image := get_viewport().get_texture().get_image()
	if hero_image != null:
		hero_image.save_png(app.data_root.path_join("hero.png"))
	_record("T167_COASTER_CAR_RENDERED", committed.get("reason") == "LOOP_PLACED" and placed.get("ok", false) and boarded.get("ok", false) and error == OK and image.get_size() == Vector2i(1280, 720) and car_parts >= 30 and hero_parts >= 30 and cell.y >= origin.y + 1 and camera_current, "the hero sits in the coaster car climbing into the loop, seen from the chase camera behind and above the car, in one 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "committed": committed.get("reason"), "placed": placed.get("reason"), "boarded": boarded.get("reason"), "car_parts": car_parts, "hero_parts": hero_parts, "cell": cell, "camera_current": camera_current})


## Path length the rig covers over `frames` steps of 1/30 s (cells per second
## when `frames` is 30).
func _measure_travel(carts: CoasterCartService, rig: Node3D, frames: int) -> float:
	var travelled := 0.0
	var previous := rig.global_position
	for _frame in range(frames):
		carts.advance(1.0 / 30.0, false)
		travelled += rig.global_position.distance_to(previous)
		previous = rig.global_position
	return travelled


func _action_event(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _hold_item(item_id: String) -> void:
	var inventory := app.session.inventory
	var slot := -1
	for slot_index in range(F0Inventory.SLOT_COUNT):
		if str(inventory.slots[slot_index].get("item_id", "")) == item_id:
			slot = slot_index
	if slot >= F0Inventory.HOTBAR_COUNT:
		inventory.swap_slots(slot, 2)
		slot = 2
	if slot >= 0:
		inventory.select_hotbar(slot)


func _has_all(names: Array[String], wanted: Array[String]) -> bool:
	for name_wanted in wanted:
		if not names.has(name_wanted):
			return false
	return true


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
