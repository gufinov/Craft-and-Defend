class_name P3CPlayerDefenseAutomation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_phase1()
		"save":
			await _run_save_checkpoint()
		"restore":
			await _run_restore_checkpoint()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p3c_player_defense_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3C_PLAYER_DEFENSE_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3C_PLAYER_DEFENSE_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var registry := app.session.registry
	var missing_icons := ItemIconCatalog.missing_item_ids(registry.items.keys())
	_record("T72_VISUAL_CATALOG", missing_icons.is_empty() and registry.items.size() >= 26, "every registered item resolves a stable atlas region (original or derived placeholder)", {"items": registry.items.size(), "missing": missing_icons})

	app.session.inventory.try_transaction({}, {"workbench": 1, "planks": 16, "stone": 16, "stick": 8, "iron_ingot": 8})
	var workbench_cell := Vector3i(5, 0, 43)
	var workbench := app.session.workstations.try_place("workbench", workbench_cell, app.session.world.query_cell, AABB(), 0)
	var workbench_id := str(workbench.get("details", {}).get("station", {}).get("instance_id", ""))
	app.state = app.AppState.PLAYING
	app._show_crafting(workbench_id, "workbench")
	await get_tree().process_frame
	# The Workbench book grows with every card; the page count follows it.
	var book_pages := maxi(1, ceili(float(app._available_crafting_recipes().size()) / float(app.RECIPE_PAGE_SIZE)))
	var first_page_count := app.crafting_recipe_list.get_child_count()
	var page_one := app.crafting_recipe_page_label.text
	var next_available := not app.crafting_recipe_next.disabled
	var missing_highlight := false
	for child in app.crafting_recipe_list.get_children():
		if child is RecipeCatalogCard and child.is_missing_materials():
			missing_highlight = true
			break
	var wheel_next := app._turn_recipe_page_from_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().process_frame
	var page_two := app.crafting_recipe_page_label.text
	var wheel_previous := app._turn_recipe_page_from_wheel(MOUSE_BUTTON_WHEEL_UP)
	await get_tree().process_frame
	var wheel_returned := app.crafting_recipe_page_label.text == "Page 1 / %d" % book_pages
	app._change_recipe_page(1)
	app.crafting_recipe_search.text = "kettle"
	app._on_crafting_recipe_search_changed("kettle")
	await get_tree().process_frame
	var search_count := app.crafting_recipe_list.get_child_count()
	var selected_id := ""
	if search_count == 1 and app.crafting_recipe_list.get_child(0) is RecipeCatalogCard:
		selected_id = app.crafting_recipe_list.get_child(0).recipe_id
	_record("T73_PAGED_RECIPE_BOOK", bool(workbench.get("ok", false)) and first_page_count == app.RECIPE_PAGE_SIZE and book_pages >= 2 and page_one == "Page 1 / %d" % book_pages and next_available and wheel_next and page_two == "Page 2 / %d" % book_pages and wheel_previous and wheel_returned and missing_highlight and search_count == 1 and selected_id == "kettle", "the Workbench uses a bounded 12-tile page with wheel/button paging and search; recipes missing resources are red-highlighted", {"first_page_count": first_page_count, "page_one": page_one, "page_two": page_two, "wheel_previous": wheel_previous, "wheel_returned": wheel_returned, "missing_highlight": missing_highlight, "search_count": search_count, "selected": selected_id})
	app.crafting_recipe_search.clear()
	app._close_crafting()
	app.session.simulation_paused = true
	app.session.player.deactivate()

	var core := app.session.core_defense
	var started := core.start_prototype()
	core.warning_remaining = 0.0
	core._begin_attack()
	core.raider.active = false
	app.session.inventory.try_transaction({}, {"iron_sword": 1})
	var sword_slot := _slot_for("iron_sword")
	if sword_slot >= F0Inventory.HOTBAR_COUNT:
		app.session.inventory.swap_slots(sword_slot, 0)
		sword_slot = 0
	app.session.inventory.select_hotbar(sword_slot)
	var target := core.raider_target_position()
	var origin := target + Vector3(0.0, 0.0, -2.2)
	await get_tree().physics_frame
	var hit := app.session._player_primary_action(origin, (target - origin).normalized())
	var health_after_hit := core.raider_health
	var cooldown := app.session._player_primary_action(origin, (target - origin).normalized())
	app.session._melee_cooldown = 0.0
	var miss := app.session._player_primary_action(origin, Vector3.LEFT)
	for _strike in range(4):
		if core.raider_health <= 0:
			break
		app.session._melee_cooldown = 0.0
		app.session._player_primary_action(origin, (target - origin).normalized())
	var sword_ok: bool = bool(started.get("ok", false)) and hit.get("reason") == "RAIDER_DAMAGED" and health_after_hit == 13 and cooldown.get("reason") == "MELEE_COOLDOWN" and miss.get("reason") == "SWORD_MISS" and core.state == CoreDefenseService.WON
	_record("T74_SWORD_COMBAT", sword_ok, "an equipped sword uses the enemy-first primary path, deals exactly seven once, rejects cooldown/miss without mutation and can win the defense", {"hit": hit, "health_after_hit": health_after_hit, "cooldown": cooldown, "miss": miss, "final": core.snapshot()})

	# T74 already proved the public start path. Build the siege fixture while the
	# won drill is inactive, then re-arm its raider. This prevents placement-driven
	# navigation replans from coupling these weapon tests to the UI fixture.
	core.raider_health = CoreDefenseService.RAIDER_MAX_HEALTH
	if is_instance_valid(core.raider):
		core.raider.revive()
	core.raider.active = false
	var center := core.arena_center
	core.raider.global_position = Vector3(center + Vector3i(0, 0, 8)) + Vector3(0.5, 0.9, 0.5)
	app.session.inventory.try_transaction({}, {"ballista": 2, "tower_platform": 1, "catapult": 1})
	var ground_ballista := app.session.workstations.try_place("ballista", center + Vector3i(-1, 0, -4), app.session.world.query_cell, AABB(), 0)
	var tower := app.session.workstations.try_place("tower_platform", center + Vector3i(3, 0, -4), app.session.world.query_cell, AABB(), 0)
	var socket_ballista := app.session.workstations.try_place("ballista", center + Vector3i(3, 1, -4), app.session.world.query_cell, AABB(), 0)
	var catapult := app.session.workstations.try_place("catapult", center + Vector3i(-4, 0, -4), app.session.world.query_cell, AABB(), 0)
	core.state = CoreDefenseService.ROUTING
	var ballista_id := str(ground_ballista.get("details", {}).get("station", {}).get("instance_id", ""))
	var ballista_before := app.session.workstations.siege_status(ballista_id)
	var blocker := _make_blocker(app.session.siege_defense.trajectory_result(ballista_id, core.raider_target_position()).get("origin", Vector3.ZERO).lerp(core.raider_target_position(), 0.5))
	await get_tree().physics_frame
	# P4a-1: machines turn to face their target before firing; the firing-rule
	# checks below face the raider instantly so they test range and occlusion.
	app.session.siege_defense.face_target_now(ballista_id, core.raider_target_position())
	var blocked := app.session.siege_defense._attempt_fire(ballista_id, ballista_before.get("details", {}), true)
	var ammo_after_block := int(app.session.workstations.siege_status(ballista_id).get("details", {}).get("ammo", -1))
	blocker.queue_free()
	await get_tree().physics_frame
	var clear := app.session.siege_defense._attempt_fire(ballista_id, app.session.workstations.siege_status(ballista_id).get("details", {}), true)
	var ammo_after_clear := int(app.session.workstations.siege_status(ballista_id).get("details", {}).get("ammo", -1))
	var ballista_ok: bool = bool(ground_ballista.get("ok", false)) and bool(tower.get("ok", false)) and bool(socket_ballista.get("ok", false)) and blocked.get("reason") == "LINE_OF_SIGHT_BLOCKED" and ammo_after_block == 8 and clear.get("ok", false) and ammo_after_clear == 7 and core.raider_health == 14
	_record("T75_BALLISTA", ballista_ok, "ground and typed tower mounts work; direct occlusion costs nothing; a clear shot consumes one bolt and damages once", {"ground": ground_ballista, "tower": tower, "socket": socket_ballista, "blocked": blocked, "ammo_after_block": ammo_after_block, "clear": clear, "ammo_after_clear": ammo_after_clear, "raider_health": core.raider_health})

	var catapult_id := str(catapult.get("details", {}).get("station", {}).get("instance_id", ""))
	var catapult_status := app.session.workstations.siege_status(catapult_id)
	var muzzle: Vector3 = app.session.siege_defense.trajectory_result(catapult_id, core.raider_target_position()).get("origin", Vector3.ZERO)
	var too_close := app.session.siege_defense.trajectory_result(catapult_id, muzzle + Vector3(2.0, 0.0, 0.0))
	var too_far := app.session.siege_defense.trajectory_result(catapult_id, muzzle + Vector3(40.0, 0.0, 0.0))
	var catapult_before := int(catapult_status.get("details", {}).get("ammo", -1))
	app.session.siege_defense.face_target_now(catapult_id, core.raider_target_position())
	var catapult_fire := app.session.siege_defense._attempt_fire(catapult_id, catapult_status.get("details", {}), true)
	var catapult_after := int(app.session.workstations.siege_status(catapult_id).get("details", {}).get("ammo", -1))
	var catapult_ok: bool = bool(catapult.get("ok", false)) and too_close.get("reason") == "TARGET_TOO_CLOSE" and too_far.get("reason") == "TARGET_TOO_FAR" and catapult_fire.get("ok", false) and catapult_after == catapult_before - 1 and core.raider_health == 5
	_record("T76_CATAPULT", catapult_ok, "the catapult enforces minimum/maximum range and consumes one shot only for a clear valid ballistic arc", {"placed": catapult, "too_close": too_close, "too_far": too_far, "fire": catapult_fire, "ammo_before": catapult_before, "ammo_after": catapult_after, "raider_health": core.raider_health})

	var snapshot := app.session.workstations.snapshot()
	var restored_inventory := F0Inventory.new(registry)
	var restored_service := WorkstationService.new(registry, restored_inventory)
	var restored := restored_service.restore(snapshot, app.session.world.query_cell)
	var restored_ballista := restored_service.siege_status(ballista_id)
	var restored_catapult := restored_service.siege_status(catapult_id)
	var persistence_ok: bool = restored.get("ok", false) and int(restored_ballista.get("details", {}).get("ammo", -1)) == ammo_after_clear and int(restored_catapult.get("details", {}).get("ammo", -1)) == catapult_after
	_record("T77_SIEGE_PERSISTENCE", persistence_ok, "placed siege identity, remaining ammunition and reload state round-trip through the existing station snapshot", {"restore": restored, "ballista": restored_ballista, "catapult": restored_catapult})

	# P4a-1 motion: a fresh catapult turns toward the raider at TURN_RATE and
	# only then fires; the arm whips to ARM_THROWN and winds back over the
	# reload; the bucket stone is hidden while unloaded.
	var siege := app.session.siege_defense
	var turret: Node3D = app.session._station_visuals[catapult_id].get_node("SiegeTurret")
	var arm: Node3D = turret.find_child("CatapultArm", true, false)
	var stone: Node3D = turret.find_child("CatapultStone", true, false)
	siege.face_target_now(catapult_id, core.raider_target_position())
	turret.rotation.y = wrapf(turret.rotation.y + 2.4, -PI, PI)
	var faced_immediately := siege.facing_target(catapult_id, core.raider_target_position())
	var turned_seconds := 0.0
	while not siege.facing_target(catapult_id, core.raider_target_position()) and turned_seconds < 3.0:
		siege.advance(0.05, false)
		turned_seconds += 0.05
	var faced_after_turning := siege.facing_target(catapult_id, core.raider_target_position())
	var thrown_after_fire := absf(arm.rotation.x - SiegeDefenseService.ARM_THROWN) < 0.3 or arm.has_meta("throwing")
	var stone_hidden_after_fire: bool = not stone.visible
	var cooldown_total := float(app.session.workstations.siege_status(catapult_id).get("details", {}).get("definition", {}).get("cooldown_seconds", 3.2))
	arm.remove_meta("throwing")
	for _step in range(int(ceil(cooldown_total / 0.1)) + 2):
		siege.advance(0.1, false)
	var rest_after_reload := absf(arm.rotation.x - SiegeDefenseService.ARM_REST) < 0.05
	var stone_back: bool = stone.visible
	_record("T118_CATAPULT_MOTION", not faced_immediately and faced_after_turning and turned_seconds > 0.5 and turned_seconds < 2.5 and thrown_after_fire and stone_hidden_after_fire and rest_after_reload and stone_back, "a catapult turned away from the raider swings its turntable to face it at the turn rate before firing, the arm whips forward on the shot and winds back to rest over the reload, and the bucket stone reappears only when reloaded", {"faced_immediately": faced_immediately, "turned_seconds": turned_seconds, "faced_after_turning": faced_after_turning, "thrown_after_fire": thrown_after_fire, "stone_hidden_after_fire": stone_hidden_after_fire, "rest_after_reload": rest_after_reload, "stone_back": stone_back})

	# T119 munitions and supply: stance Hold withholds fire; load/unload move
	# munitions between inventory and weapon with type rules; a Chest within the
	# supply radius auto-reloads an empty weapon; one outside does not.
	var ws := app.session.workstations
	core.raider_health = CoreDefenseService.RAIDER_MAX_HEALTH
	if is_instance_valid(core.raider):
		core.raider.revive()
	core.state = CoreDefenseService.ROUTING
	core.raider.active = false
	core.raider.global_position = Vector3(center + Vector3i(0, 0, 8)) + Vector3(0.5, 0.9, 0.5)
	siege.face_target_now(catapult_id, core.raider_target_position())
	var ammo_before_hold := int(ws.siege_status(catapult_id).get("details", {}).get("ammo", -1))
	var stance_hold := ws.siege_set_stance(catapult_id, "hold")
	var held_fire := siege._attempt_fire(catapult_id, ws.siege_status(catapult_id).get("details", {}), true)
	siege.advance(0.5, false)
	var ammo_after_hold := int(ws.siege_status(catapult_id).get("details", {}).get("ammo", -1))
	ws.siege_set_stance(catapult_id, "fire_at_will")
	var pack_before_unload := app.session.inventory.count("stone_shot")
	var unloaded := ws.siege_unload(catapult_id)
	var stone_back_in_pack := app.session.inventory.count("stone_shot") - pack_before_unload
	app.session.inventory.try_transaction({}, {"flame_shot": 3, "stone_shot": 2, "chest": 2})
	var wrong_type_ok: bool = ws.siege_load(catapult_id, "ballista_bolt", 1).get("reason") == "WRONG_AMMUNITION"
	var flame_loaded := ws.siege_load(catapult_id, "flame_shot", 2)
	var mixed_refused: bool = ws.siege_load(catapult_id, "stone_shot", 1).get("reason") == "AMMO_TYPE_LOADED"
	var status_after_load: Dictionary = ws.siege_status(catapult_id).get("details", {})
	ws.siege_unload(catapult_id)
	var near_chest := ws.try_place("chest", center + Vector3i(-4, 0, 0), app.session.world.query_cell, AABB(), 0)
	var far_chest := ws.try_place("chest", center + Vector3i(9, 0, 9), app.session.world.query_cell, AABB(), 0)
	var near_id := str(near_chest.get("details", {}).get("station", {}).get("instance_id", ""))
	var far_id := str(far_chest.get("details", {}).get("station", {}).get("instance_id", ""))
	var far_deposit := ws.container_deposit(far_id, "stone_shot", 2)
	var supply_without_near := ws.siege_supply(catapult_id).size()
	var no_supply: bool = ws.siege_auto_reload(catapult_id).get("reason") == "NO_SUPPLY"
	var near_deposit := ws.container_deposit(near_id, "flame_shot", 3)
	var reloaded := ws.siege_auto_reload(catapult_id)
	var chest_left := ws.container_count(near_id, "flame_shot")
	var withdraw := ws.container_withdraw(far_id, "stone_shot", 2)
	var munitions_ok: bool = stance_hold.get("ok", false) and held_fire.get("reason") == "STANCE_HOLD" and ammo_after_hold == ammo_before_hold and ammo_before_hold > 0 		and unloaded.get("ok", false) and stone_back_in_pack == ammo_before_hold and wrong_type_ok and flame_loaded.get("ok", false) and mixed_refused 		and str(status_after_load.get("ammo_item", "")) == "flame_shot" and int(status_after_load.get("ammo", 0)) == 2 		and str(status_after_load.get("munition", {}).get("effect", "")) == "fire" 		and near_chest.get("ok", false) and far_chest.get("ok", false) and far_deposit.get("ok", false) and supply_without_near == 0 and no_supply 		and near_deposit.get("ok", false) and reloaded.get("ok", false) and int(reloaded.get("details", {}).get("moved", 0)) == 3 and chest_left == 0 		and withdraw.get("ok", false) and app.session.inventory.count("stone_shot") == pack_before_unload + ammo_before_hold + 2
	_record("T119_MUNITIONS_AND_SUPPLY", munitions_ok, "Hold withholds fire; unload returns shot; load enforces the weapon's munition list and one type at a time; a chest inside the supply radius auto-reloads an empty weapon while one outside is ignored; chest deposit and withdraw round-trip", {"hold": held_fire.get("reason"), "ammo_after_hold": ammo_after_hold, "unloaded": unloaded.get("reason"), "flame_loaded": flame_loaded.get("reason"), "mixed_refused": mixed_refused, "status": status_after_load, "supply_without_near": supply_without_near, "reloaded": reloaded.get("reason"), "chest_left": chest_left, "wrong_type_ok": wrong_type_ok, "stone_back": stone_back_in_pack, "ammo_before_hold": ammo_before_hold, "near_chest": near_chest.get("reason"), "far_chest": far_chest.get("reason"), "far_deposit": far_deposit.get("reason"), "no_supply": no_supply, "near_deposit": near_deposit.get("reason"), "moved": reloaded.get("details", {}).get("moved", -1), "withdraw": withdraw.get("reason"), "final_stone": app.session.inventory.count("stone_shot"), "pack_before": pack_before_unload})

	# T120 flame shot: the impact ignites cells, fire damages the raider standing
	# in it, a planks block in the fire is consumed after its fuel burns, and the
	# fire on bare ground goes out after burn_seconds.
	var fire_service := app.session.fire_service
	var plank_cell := center + Vector3i(2, 0, 9)
	app.session.world.set_cell(plank_cell, 5)
	core.raider.global_position = Vector3(center + Vector3i(0, 0, 9)) + Vector3(0.5, 0.9, 0.5)
	core.raider_health = CoreDefenseService.RAIDER_MAX_HEALTH
	if is_instance_valid(core.raider):
		core.raider.revive()
	core.state = CoreDefenseService.ROUTING
	siege.face_target_now(catapult_id, core.raider_target_position())
	var flame_fire := siege._attempt_fire(catapult_id, ws.siege_status(catapult_id).get("details", {}), true)
	var burning_after_shot := fire_service.burning_cells().size()
	var plank_burning := fire_service.is_burning(plank_cell)
	var health_before_burn := core.raider_health
	for _tick in range(12):
		fire_service.advance(0.5, false)
	var health_after_burn := core.raider_health
	var plank_gone := int(app.session.world.query_cell(plank_cell).get("voxel_id", -1)) == 0
	for _tick in range(40):
		fire_service.advance(0.5, false)
	var fires_out := fire_service.burning_cells().size() == 0
	_record("T120_FLAME_SHOT_FIRE", flame_fire.get("ok", false) and burning_after_shot >= 3 and plank_burning and health_after_burn < health_before_burn and plank_gone and fires_out, "a flame shot ignites the ground around its impact, burns the raider standing there, consumes a planks block once its fuel is spent, and the ground fire dies out after burn_seconds", {"fire": flame_fire.get("reason"), "burning": burning_after_shot, "plank_burning": plank_burning, "health_before": health_before_burn, "health_after": health_after_burn, "plank_gone": plank_gone, "fires_out": fires_out})



func _run_save_checkpoint() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	app.session.inventory.try_transaction({}, {"iron_sword": 1, "ballista": 1, "catapult": 1})
	var ballista := app.session.workstations.try_place("ballista", Vector3i(5, 0, 34), app.session.world.query_cell, AABB(), 0)
	var catapult := app.session.workstations.try_place("catapult", Vector3i(2, 0, 34), app.session.world.query_cell, AABB(), 0)
	var ballista_id := str(ballista.get("details", {}).get("station", {}).get("instance_id", ""))
	var catapult_id := str(catapult.get("details", {}).get("station", {}).get("instance_id", ""))
	var ballista_shot := app.session.workstations.commit_siege_shot(ballista_id)
	var catapult_shot := app.session.workstations.commit_siege_shot(catapult_id)
	var saved := await app.saves.save_session(app.session)
	var ok: bool = ballista.get("ok", false) and catapult.get("ok", false) and ballista_shot.get("ok", false) and catapult_shot.get("ok", false) and saved.get("ok", false)
	_record("T77_SIEGE_CHECKPOINT_SAVE", ok, "one atomic checkpoint stores the carried sword plus placed siege identity, remaining ammunition and reload state", {"save": saved, "sword_count": app.session.inventory.count("iron_sword"), "ballista": app.session.workstations.siege_status(ballista_id), "catapult": app.session.workstations.siege_status(catapult_id)})


func _run_restore_checkpoint() -> void:
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var ballista_status: Dictionary = {}
	var catapult_status: Dictionary = {}
	for instance_id: String in app.session.workstations.stations:
		var record: Dictionary = app.session.workstations.stations[instance_id]
		if str(record.get("entity_id", "")) == "ballista":
			ballista_status = app.session.workstations.siege_status(instance_id)
		elif str(record.get("entity_id", "")) == "catapult":
			catapult_status = app.session.workstations.siege_status(instance_id)
	var ballista_details: Dictionary = ballista_status.get("details", {})
	var catapult_details: Dictionary = catapult_status.get("details", {})
	var restored: bool = app.session.inventory.count("iron_sword") == 1 and ballista_status.get("ok", false) and catapult_status.get("ok", false) and int(ballista_details.get("ammo", -1)) == 7 and is_equal_approx(float(ballista_details.get("cooldown", -1.0)), 1.5) and int(catapult_details.get("ammo", -1)) == 4 and is_equal_approx(float(catapult_details.get("cooldown", -1.0)), 3.2)
	_record("T77_SIEGE_CHECKPOINT_RESTORE", restored, "a separate executable Continue restores the exact carried sword and placed siege ammunition/reload state", {"sword_count": app.session.inventory.count("iron_sword"), "ballista": ballista_status, "catapult": catapult_status})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.inventory.try_transaction({}, {"workbench": 1, "planks": 32, "stone": 32, "stick": 16, "iron_ingot": 12, "iron_sword": 1, "ballista": 1, "catapult": 1})
	var placed := app.session.workstations.try_place("workbench", Vector3i(5, 0, 43), app.session.world.query_cell, AABB(), 0)
	var workbench_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	app._show_crafting(workbench_id, "workbench")
	for _frame in range(30):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("p3c-visual-catalog.png")
	if image == null:
		_record("T78_PRESENTATION", false, "the rendered 1280×720 Workbench shows twelve icon-first recipe cards with explicit paging and the three crafting panels", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var populated_cards := 0
	for child in app.crafting_recipe_list.get_children():
		if child is RecipeCatalogCard and child.is_populated():
			populated_cards += 1
	var visual_ok := error == OK and image.get_size() == Vector2i(1280, 720) and app.crafting_recipe_list.get_child_count() == app.RECIPE_PAGE_SIZE and populated_cards == app.RECIPE_PAGE_SIZE and app.crafting_recipe_page_label.text == "Page 1 / %d" % maxi(1, ceili(float(app._available_crafting_recipes().size()) / float(app.RECIPE_PAGE_SIZE)))
	_record("T78_PRESENTATION", visual_ok, "the rendered 1280×720 Workbench shows twelve populated icon-first recipe cards with explicit paging and the three crafting panels", {"path": path, "size": image.get_size(), "error": error, "page": app.crafting_recipe_page_label.text, "cards": app.crafting_recipe_list.get_child_count(), "populated_cards": populated_cards})


func _slot_for(item_id: String) -> int:
	for index in range(F0Inventory.SLOT_COUNT):
		if str(app.session.inventory.slots[index].get("item_id", "")) == item_id:
			return index
	return -1


func _make_blocker(position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "P3CBallistaOccluder"
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 3.0, 0.8)
	collision.shape = shape
	body.add_child(collision)
	app.session.add_child(body)
	return body


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
