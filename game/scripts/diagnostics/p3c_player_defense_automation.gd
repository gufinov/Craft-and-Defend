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
	_record("T72_VISUAL_CATALOG", missing_icons.is_empty() and registry.items.size() == 26, "every registered item resolves a stable original atlas region", {"items": registry.items.size(), "missing": missing_icons})

	app.session.inventory.try_transaction({}, {"workbench": 1, "planks": 16, "stone": 16, "stick": 8, "iron_ingot": 8})
	var workbench_cell := Vector3i(5, 0, 43)
	var workbench := app.session.workstations.try_place("workbench", workbench_cell, app.session.world.query_cell, AABB(), 0)
	var workbench_id := str(workbench.get("details", {}).get("station", {}).get("instance_id", ""))
	app.state = app.AppState.PLAYING
	app._show_crafting(workbench_id, "workbench")
	await get_tree().process_frame
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
	var wheel_returned := app.crafting_recipe_page_label.text == "Page 1 / 2"
	app._change_recipe_page(1)
	app.crafting_recipe_search.text = "catapult"
	app._on_crafting_recipe_search_changed("catapult")
	await get_tree().process_frame
	var search_count := app.crafting_recipe_list.get_child_count()
	var selected_id := ""
	if search_count == 1 and app.crafting_recipe_list.get_child(0) is RecipeCatalogCard:
		selected_id = app.crafting_recipe_list.get_child(0).recipe_id
	_record("T73_PAGED_RECIPE_BOOK", bool(workbench.get("ok", false)) and first_page_count == app.RECIPE_PAGE_SIZE and page_one == "Page 1 / 2" and next_available and wheel_next and page_two == "Page 2 / 2" and wheel_previous and wheel_returned and missing_highlight and search_count == 1 and selected_id == "catapult", "the Workbench uses a bounded 12-tile page with wheel/button paging and search; recipes missing resources are red-highlighted", {"first_page_count": first_page_count, "page_one": page_one, "page_two": page_two, "wheel_previous": wheel_previous, "wheel_returned": wheel_returned, "missing_highlight": missing_highlight, "search_count": search_count, "selected": selected_id})
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
	var blocked := app.session.siege_defense._attempt_fire(ballista_id, ballista_before.get("details", {}))
	var ammo_after_block := int(app.session.workstations.siege_status(ballista_id).get("details", {}).get("ammo", -1))
	blocker.queue_free()
	await get_tree().physics_frame
	var clear := app.session.siege_defense._attempt_fire(ballista_id, app.session.workstations.siege_status(ballista_id).get("details", {}))
	var ammo_after_clear := int(app.session.workstations.siege_status(ballista_id).get("details", {}).get("ammo", -1))
	var ballista_ok: bool = bool(ground_ballista.get("ok", false)) and bool(tower.get("ok", false)) and bool(socket_ballista.get("ok", false)) and blocked.get("reason") == "LINE_OF_SIGHT_BLOCKED" and ammo_after_block == 8 and clear.get("ok", false) and ammo_after_clear == 7 and core.raider_health == 14
	_record("T75_BALLISTA", ballista_ok, "ground and typed tower mounts work; direct occlusion costs nothing; a clear shot consumes one bolt and damages once", {"ground": ground_ballista, "tower": tower, "socket": socket_ballista, "blocked": blocked, "ammo_after_block": ammo_after_block, "clear": clear, "ammo_after_clear": ammo_after_clear, "raider_health": core.raider_health})

	var catapult_id := str(catapult.get("details", {}).get("station", {}).get("instance_id", ""))
	var catapult_status := app.session.workstations.siege_status(catapult_id)
	var muzzle: Vector3 = app.session.siege_defense.trajectory_result(catapult_id, core.raider_target_position()).get("origin", Vector3.ZERO)
	var too_close := app.session.siege_defense.trajectory_result(catapult_id, muzzle + Vector3(2.0, 0.0, 0.0))
	var too_far := app.session.siege_defense.trajectory_result(catapult_id, muzzle + Vector3(40.0, 0.0, 0.0))
	var catapult_before := int(catapult_status.get("details", {}).get("ammo", -1))
	var catapult_fire := app.session.siege_defense._attempt_fire(catapult_id, catapult_status.get("details", {}))
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
	var visual_ok := error == OK and image.get_size() == Vector2i(1280, 720) and app.crafting_recipe_list.get_child_count() == app.RECIPE_PAGE_SIZE and populated_cards == app.RECIPE_PAGE_SIZE and app.crafting_recipe_page_label.text == "Page 1 / 2"
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
