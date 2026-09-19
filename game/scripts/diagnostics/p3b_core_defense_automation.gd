class_name P3BCoreDefenseAutomation
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
		"recipe_visual":
			await _run_recipe_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p3b_core_defense_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3B_CORE_DEFENSE_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3B_CORE_DEFENSE_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var core := app.session.core_defense
	var started := core.start_prototype()
	if not started.get("ok", false):
		_record("T66_BARRICADE_RECIPE_PLACEMENT", false, "the core-defense arena starts", started)
		return
	var center: Vector3i = core.arena_center
	var workbench_cell := center + Vector3i(4, 0, 3)
	app.session.inventory.try_transaction({}, {"workbench": 1})
	var workbench := _place("workbench", workbench_cell)
	var workbench_id := str(workbench.get("details", {}).get("station", {}).get("instance_id", ""))
	var recipe_ui := await _inspect_workbench_barricade_recipe(workbench_id)
	app.session.inventory.try_transaction({}, {"planks": 4})
	var crafted := app.session.try_craft("wood_barricade", "workbench", workbench_id)
	var barricade_cell := Vector3i(center.x, center.y, center.z)
	var placed := _place("wood_barricade", barricade_cell)
	var barricade_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var status := app.session.workstations.defense_status(barricade_id)
	var nav := app.session.workstations.navigation_cell_data(barricade_id)
	var occupied: Array = placed.get("details", {}).get("occupied_cells", [])
	var damaged_once := app.session.workstations.try_damage(barricade_id, CoreDefenseService.RAIDER_DAMAGE)
	app.session.inventory.try_transaction({}, {"planks": 1})
	var planks_before_repair := app.session.inventory.count("planks")
	var repaired_once := app.session.workstations.try_repair_structure(barricade_id)
	var repaired_status := app.session.workstations.defense_status(barricade_id)
	var repair_atomic: bool = repaired_once.get("ok", false) and app.session.inventory.count("planks") == planks_before_repair - 1 and int(repaired_status.get("details", {}).get("integrity", 0)) == 30
	var recipe_placement_ok: bool = bool(workbench.get("ok", false)) and bool(recipe_ui.get("ok", false)) and bool(crafted.get("ok", false)) and bool(placed.get("ok", false)) and occupied.size() == 2 and status.get("ok", false) and int(status.get("details", {}).get("integrity", 0)) == 30 and nav.get("tags", []).has("breachable_wood") and damaged_once.get("ok", false) and repair_atomic
	_record("T66_BARRICADE_RECIPE_PLACEMENT", recipe_placement_ok, "the progression-ordered Workbench book (Planks first) finds Wood Barricade by search before crafting one placeable two-cell defense with a stable identity, exact footprint, 30 integrity and atomic Planks repair", {"workbench": workbench, "recipe_ui": recipe_ui, "crafted": crafted, "placed": placed, "status": status, "navigation": nav, "damage": damaged_once, "repair": repaired_once, "repair_status": repaired_status})

	core.warning_remaining = 0.0
	core._begin_attack()
	var open_route_ok: bool = core.last_route_reason == "OK" and core.active_target_type == "core" and int(app.session.workstations.defense_status(barricade_id).get("details", {}).get("integrity", 0)) == 30
	_record("T67_OPEN_ROUTE_PREFERENCE", open_route_ok, "one field-side raider chooses the open route to the strategic core and leaves a nearby defense undamaged", {"route_reason": core.last_route_reason, "target": core.active_target_type, "barricade": app.session.workstations.defense_status(barricade_id), "route_cells": core.raider.route.size() if is_instance_valid(core.raider) else 0})

	var row_results: Array = []
	for x in range(center.x - 5, center.x + 6):
		if x == center.x:
			continue
		app.session.inventory.try_transaction({}, {"wood_barricade": 1})
		row_results.append(_place("wood_barricade", Vector3i(x, center.y, center.z)))
	core._plan_from_raider()
	var targeted_id := core.active_target_id
	var target_before := app.session.workstations.defense_status(targeted_id)
	var count_before := app.session.inventory.count("wood_barricade")
	var attack_results: Array = []
	if core.active_target_type == "structure":
		for _hit in range(5):
			attack_results.append(app.session.workstations.try_damage(targeted_id, CoreDefenseService.RAIDER_DAMAGE))
	for _frame in range(3):
		await get_tree().process_frame
	var released: bool = app.session.workstations.station(targeted_id).is_empty()
	var no_refund: bool = app.session.inventory.count("wood_barricade") == count_before
	var replanned: bool = core.last_route_reason == "OK" and core.active_target_type == "core"
	var row_ok: bool = row_results.all(func(result: Dictionary) -> bool: return result.get("ok", false))
	_record("T68_BOUNDED_BREACH_REPLAN", row_ok and target_before.get("ok", false) and released and no_refund and replanned and core.exact_invalidations >= 2, "a fully blocked lane selects one exact wooden barricade, destroys its full footprint without a refund, then replans through the released opening", {"target": targeted_id, "before": target_before, "attacks": attack_results, "released": released, "no_refund": no_refund, "route_reason_after": core.last_route_reason, "target_after": core.active_target_type, "invalidations": core.exact_invalidations})

	app.session.inventory.try_transaction({}, {"gate_frame": 1})
	var gate := _place("gate_frame", center + Vector3i(3, 0, 3))
	var gate_id := str(gate.get("details", {}).get("station", {}).get("instance_id", ""))
	var gate_nav := app.session.workstations.navigation_cell_data(gate_id)
	var planner := LocalGridPathfinder.new()
	var basic_damage := planner._damage_for(gate_nav.get("tags", []), core._basic_raider_capability().get("damage_per_hit", {}))
	var siege_damage := planner._damage_for(gate_nav.get("tags", []), {"stone": 8, "fortification": 8})
	_record("T69_RAIDER_CASTLE_BOUNDARY", gate.get("ok", false) and basic_damage == 0.0 and siege_damage == 8.0, "the basic raider cannot damage a castle entity while the documented siege candidate can identify the same stone obstruction", {"gate": gate, "navigation": gate_nav, "basic_damage": basic_damage, "siege_damage": siege_damage})


func _run_save_checkpoint() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var core := app.session.core_defense
	var started := core.start_prototype()
	if not started.get("ok", false):
		_record("T70_CORE_CHECKPOINT_SAVE", false, "the core prototype starts before checkpointing", started)
		return
	app.session.inventory.try_transaction({}, {"wood_barricade": 1})
	var placed := _place("wood_barricade", core.arena_center)
	var instance_id := str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	var damaged := app.session.workstations.try_damage(instance_id, CoreDefenseService.RAIDER_DAMAGE)
	core.warning_remaining = 0.0
	core._begin_attack()
	core.core_integrity = 18
	core.raider_health = 14
	core._update_core_presentation()
	var saved := await app.saves.save_session(app.session)
	_record("T70_CORE_CHECKPOINT_SAVE", placed.get("ok", false) and damaged.get("ok", false) and saved.get("ok", false), "one atomic checkpoint stores core, raider target and damaged player-built barricade state", {"save": saved, "core_defense": core.snapshot(), "barricade": app.session.workstations.defense_status(instance_id)})


func _run_restore_checkpoint() -> void:
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var core := app.session.core_defense
	var barricades: Array[Dictionary] = []
	for record: Dictionary in app.session.workstations.stations.values():
		if str(record.get("entity_id", "")) == "wood_barricade":
			barricades.append(record)
	var integrity := int(barricades[0].get("integrity", 0)) if barricades.size() == 1 else -1
	var restored: bool = core.state in [CoreDefenseService.ROUTING, CoreDefenseService.ATTACKING_CORE] and core.core_integrity == 18 and core.raider_health == 14 and is_instance_valid(core.raider) and core.active_target_type == "core" and barricades.size() == 1 and integrity == 24
	_record("T70_CORE_CHECKPOINT_RESTORE", restored, "a clean-process Continue reconstructs the exact core, raider target and surviving barricade integrity", {"core_defense": core.snapshot(), "barricades": barricades})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.apply_world_settings("1030", false)
	var core := app.session.core_defense
	var started := core.start_prototype()
	if not started.get("ok", false):
		_record("T71_CORE_DEFENSE_VISUAL", false, "the core-defense visual fixture starts", started)
		return
	var center: Vector3i = core.arena_center
	var highlighted_id := ""
	for x in range(center.x - 4, center.x + 5):
		if x == center.x:
			continue
		app.session.inventory.try_transaction({}, {"wood_barricade": 1})
		var placed := _place("wood_barricade", Vector3i(x, center.y, center.z))
		if x == center.x + 1:
			highlighted_id = str(placed.get("details", {}).get("station", {}).get("instance_id", ""))
	if not highlighted_id.is_empty():
		app.session.workstations.try_damage(highlighted_id, CoreDefenseService.RAIDER_DAMAGE)
		_add_structure_label(highlighted_id)
	core.warning_remaining = 0.0
	core._begin_attack()
	if is_instance_valid(core.raider):
		core.raider.global_position = Vector3(center + Vector3i(0, 0, -3)) + Vector3(0.5, 0.9, 0.5)
	core._emit_state()
	app.session.simulation_paused = true
	app.session.player.position = Vector3(center) + Vector3(0.0, 4.5, -9.0)
	app.session.player.camera.look_at(Vector3(center) + Vector3(0.0, 1.0, 2.0), Vector3.UP)
	_add_caption()
	for _frame in range(90):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("p3b-core-defense.png")
	var error := image.save_png(path)
	var status := app.session.workstations.defense_status(highlighted_id)
	var visual_ok: bool = core.last_route_reason == "OK" and core.active_target_type == "core" and status.get("ok", false) and int(status.get("details", {}).get("integrity", 0)) == 24 and error == OK and not image.is_empty() and image.get_size() == Vector2i(1280, 720)
	_record("T71_CORE_DEFENSE_VISUAL", visual_ok, "rendered evidence shows the strategic core, field-side raider, player-built barricades, an open route and damaged barricade integrity in one frame", {"path": path, "size": image.get_size(), "error": error, "route_reason": core.last_route_reason, "target": core.active_target_type, "barricade": status})


func _run_recipe_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var core := app.session.core_defense
	var started := core.start_prototype()
	if not started.get("ok", false):
		_record("T66_WORKBENCH_RECIPE_VISIBLE", false, "the core-defense arena starts before the Workbench evidence capture", started)
		return
	var workbench_cell := core.arena_center + Vector3i(4, 0, 3)
	app.session.inventory.try_transaction({}, {"workbench": 1, "planks": 4})
	var workbench := _place("workbench", workbench_cell)
	var workbench_id := str(workbench.get("details", {}).get("station", {}).get("instance_id", ""))
	app._show_crafting(workbench_id, "workbench")
	# P3F ordered the book by progression (Planks first); the barricade sits on
	# page two, so the evidence capture reaches it through the search box.
	app.crafting_recipe_search.text = "wood barricade"
	app._on_crafting_recipe_search_changed("wood barricade")
	for _frame in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("p3b-workbench-recipe.png")
	var error := image.save_png(path)
	var first_card_text := _first_recipe_button_text()
	var visible := bool(workbench.get("ok", false)) and first_card_text.contains("Wood Barricade") and first_card_text.contains("READY") and error == OK and not image.is_empty() and image.get_size() == Vector2i(1280, 720)
	app.crafting_recipe_search.clear()
	_record("T66_WORKBENCH_RECIPE_VISIBLE", visible, "the default 1280×720 Workbench page visibly presents a READY Wood Barricade recipe once searched (the progression-ordered book starts with Planks)", {"path": path, "size": image.get_size(), "error": error, "first_card_text": first_card_text, "workbench": workbench})


func _place(entity_id: String, cell: Vector3i) -> Dictionary:
	return app.session.workstations.try_place(entity_id, cell, app.session.world.query_cell, AABB(), 0)


func _inspect_workbench_barricade_recipe(workbench_id: String) -> Dictionary:
	app._show_crafting(workbench_id, "workbench")
	await get_tree().process_frame
	var recipes := app._available_crafting_recipes()
	var first_recipe_id := str(recipes[0].get("id", "")) if not recipes.is_empty() else ""
	var initial_cards := app.crafting_recipe_list.get_child_count()
	var first_card_text := _first_recipe_button_text()
	app.crafting_recipe_search.text = "wood barricade"
	app._on_crafting_recipe_search_changed("wood barricade")
	await get_tree().process_frame
	var search_cards := app.crafting_recipe_list.get_child_count()
	var search_card_text := _first_recipe_button_text()
	var result := {
		"ok": first_recipe_id == "planks" and initial_cards == mini(app.RECIPE_PAGE_SIZE, recipes.size()) and first_card_text.contains("Planks") and search_cards == 1 and search_card_text.contains("Wood Barricade"),
		"first_recipe_id": first_recipe_id,
		"recipe_count": recipes.size(),
		"initial_cards": initial_cards,
		"first_card_text": first_card_text,
		"search_cards": search_cards,
		"search_card_text": search_card_text,
	}
	app.crafting_recipe_search.clear()
	app._close_crafting()
	return result


func _first_recipe_button_text() -> String:
	if app.crafting_recipe_list.get_child_count() == 0:
		return ""
	var card := app.crafting_recipe_list.get_child(0)
	return str(card.tooltip_text) if card is Control else ""


func _add_structure_label(instance_id: String) -> void:
	var body: Node3D = app.session._station_visuals.get(instance_id)
	if body == null:
		return
	var label := Label3D.new()
	label.text = "PLAYER BARRICADE 24/30"
	label.position = Vector3(0.0, 2.05, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 44
	label.pixel_size = 0.008
	label.outline_size = 8
	label.modulate = Color("ffe08a")
	body.add_child(label)


func _add_caption() -> void:
	var caption := Label.new()
	caption.text = "P3B CORE & BREACH PROTOTYPE\nCYAN: strategic core   RED: field-side raider   BROWN: player-built wooden barricades\nOPENING REMAINS → raider targets the core; castle stone remains outside basic-raider damage"
	caption.position = Vector2(22, 142)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_constant_override("outline_size", 4)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	app.add_child(caption)


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		if app.state == app.AppState.PLAYING and app.session != null and app.session.world_ready:
			return true
		await get_tree().process_frame
	failures.append("world_ready_timeout")
	return false


func _record(id: String, passed: bool, expected: String, evidence: Variant) -> void:
	var result := {"id": id, "passed": passed, "expected": expected, "evidence": evidence}
	records.append(result)
	print("%s %s expected=%s evidence=%s" % [id, "PASS" if passed else "FAIL", expected, JSON.stringify(evidence)])
	if not passed:
		failures.append(id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  "))
