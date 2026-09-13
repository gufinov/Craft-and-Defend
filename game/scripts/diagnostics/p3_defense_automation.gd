class_name P3DefenseAutomation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_phase1()
		"visual":
			await _run_visual()
		"save":
			await _run_save_checkpoint()
		"restore":
			await _run_restore_checkpoint()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p3_defense_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P3_DEFENSE_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P3_DEFENSE_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var defense := app.session.defense
	var started := defense.start_drill()
	_record("T57_WARNED_WAVE", started.get("ok", false) and defense.state == DefenseService.WARNING and is_instance_valid(defense._wall_root) and is_instance_valid(defense._ballista_root) and defense.ballista_bolts == DefenseService.BALLISTA_STARTING_BOLTS, "an explicit drill creates one barricade and one mounted stationary ballista before a visible five-second warning", {"started": started, "hud": defense.hud_text()})
	defense.advance(DefenseService.WARNING_SECONDS + 0.1, false)
	var physical := is_instance_valid(defense.raider) and defense.raider is CharacterBody3D
	var route_valid := physical and not defense.raider.route.is_empty() and defense.last_route_reason == "ATTACK_OBSTRUCTION"
	var invalidations_before := defense.exact_invalidations
	app.session.inventory.try_transaction({}, {"parapet_merlon": 1})
	var entity_cell := defense.arena_center + Vector3i(2, 0, 2)
	var placed := app.session.interaction.try_place_item(entity_cell, "parapet_merlon", -1, 0)
	var placed_invalidated := defense.exact_invalidations > invalidations_before
	if placed.get("ok", false):
		app.session.interaction.try_dismantle_station(str(placed.get("changes", {}).get("station", {}).get("instance_id", "")))
	_record("T58_PHYSICAL_ROUTE_INVALIDATION", route_valid and placed.get("ok", false) and placed_invalidated and defense.exact_invalidations > invalidations_before + 1, "the 1x2 physical raider receives the P2 obstruction plan and placed-entity add/remove events refresh exact occupied cells", {"route_reason": defense.last_route_reason, "route_cells": defense.raider.route.size() if physical else 0, "placed": placed, "invalidations": defense.exact_invalidations})

	defense.raider.global_position = Vector3(defense.arena_center + Vector3i(0, 0, 1)) + Vector3(0.5, 0.9, 0.5)
	defense._on_raider_route_finished()
	defense.advance(0.3, false)
	var damaged := defense.wall_integrity == DefenseService.WALL_MAX_INTEGRITY - DefenseService.RAIDER_DAMAGE
	app.session.inventory.try_transaction({}, {"planks": 1})
	var planks_before := app.session.inventory.count("planks")
	await get_tree().physics_frame
	var repair_origin := Vector3(defense.arena_center) + Vector3(0.5, 1.5, -2.0)
	var repaired := app.session._defense_interact(repair_origin, Vector3(0.0, 0.0, 1.0))
	var repair_atomic: bool = bool(repaired.get("ok", false)) and defense.wall_integrity == DefenseService.WALL_MAX_INTEGRITY and app.session.inventory.count("planks") == planks_before - 1
	var no_extra := defense.try_repair("training_wall")
	_record("T59_DAMAGE_REPAIR", damaged and repair_atomic and not no_extra.get("ok", true) and no_extra.get("reason") == "NO_REPAIR_NEEDED", "one raider strike visibly damages the barricade and Shift-use semantics consume exactly one Planks item for one bounded repair", {"damaged": damaged, "repair": repaired, "no_extra": no_extra, "wall": defense.wall_integrity})

	defense.wall_integrity = DefenseService.WALL_MAX_INTEGRITY - DefenseService.RAIDER_DAMAGE
	defense.raider_health = DefenseService.RAIDER_MAX_HEALTH
	defense.ballista_bolts = DefenseService.BALLISTA_STARTING_BOLTS
	defense.state = DefenseService.ATTACKING
	for _shot in range(DefenseService.BALLISTA_STARTING_BOLTS):
		defense._ballista_fire()
	_record("T60_BALLISTA_AMMUNITION", defense.state == DefenseService.COMPLETE and defense.raider_health == 0 and defense.ballista_bolts == 0 and defense.wall_integrity > 0, "the stationary ballista consumes four visible bolts exactly once and defeats the single raider after the wall has taken readable damage", {"state": defense.state, "raider_health": defense.raider_health, "bolts": defense.ballista_bolts, "wall": defense.wall_integrity})

	var saved := defense.snapshot()
	var restored := DefenseService.new()
	app.session.add_child(restored)
	restored.initialize(app.session.world, app.session.inventory, app.session.registry, app.session.workstations, saved)
	var restore_result := restored.restore_after_world_ready()
	var persistence_ok: bool = bool(restore_result.get("ok", false)) and restored.state == defense.state and restored.wall_integrity == defense.wall_integrity and restored.ballista_bolts == defense.ballista_bolts and restored.arena_center == defense.arena_center
	_record("T61_DEFENSE_PERSISTENCE", persistence_ok, "defense phase, arena, wall integrity and exact ammunition round-trip through the save envelope", {"saved": saved, "restored": restored.snapshot(), "result": restore_result})
	restored.queue_free()


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var defense := app.session.defense
	var started := defense.start_drill()
	if not started.get("ok", false):
		_record("T63_DEFENSE_VISUAL", false, "defense drill visual fixture starts", started)
		return
	defense.warning_remaining = 0.0
	defense._begin_wave()
	defense.state = DefenseService.ATTACKING
	defense.wall_integrity = 12
	defense.ballista_bolts = 3
	defense.raider_health = 15
	defense._update_wall_presentation()
	defense._emit_state()
	app.session.simulation_paused = true
	app.session.player.position = Vector3(defense.arena_center) + Vector3(10.0, 10.0, 10.0)
	app.session.player.camera.look_at(Vector3(defense.arena_center) + Vector3(0.0, 0.7, 0.0), Vector3.UP)
	_add_caption()
	for _frame in range(90):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("p3-defense-slice.png")
	var error := image.save_png(path)
	_record("T63_DEFENSE_VISUAL", error == OK and not image.is_empty() and image.get_size() == Vector2i(1280, 720), "rendered evidence shows the damaged barricade, mounted ballista, physical raider and readable defense HUD in one frame", {"path": path, "size": image.get_size(), "error": error})


func _run_save_checkpoint() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var defense := app.session.defense
	var started := defense.start_drill()
	if not started.get("ok", false):
		_record("T62_DEFENSE_CHECKPOINT_SAVE", false, "a live defense state reaches the atomic checkpoint writer", started)
		return
	defense.warning_remaining = 0.0
	defense._begin_wave()
	defense.state = DefenseService.ATTACKING
	defense.wall_integrity = 12
	defense.ballista_bolts = 3
	defense.raider_health = 15
	defense.ballista_armed = true
	defense._update_wall_presentation()
	var saved := await app.saves.save_session(app.session)
	_record("T62_DEFENSE_CHECKPOINT_SAVE", saved.get("ok", false), "a live attacking phase with wall damage, ammunition and raider health reaches one atomic checkpoint", {"save": saved, "defense": defense.snapshot()})


func _run_restore_checkpoint() -> void:
	app._on_continue_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	var defense := app.session.defense
	var restored: bool = defense.state in [DefenseService.ROUTING, DefenseService.ATTACKING] and defense.wall_integrity == 12 and defense.ballista_bolts == 3 and defense.raider_health == 15 and is_instance_valid(defense.raider)
	_record("T62_DEFENSE_CHECKPOINT_RESTORE", restored, "a clean-process Continue restores the same active defense state and reconstructs one physical raider", defense.snapshot())


func _add_caption() -> void:
	var caption := Label.new()
	caption.text = "P3 DEFENSE SLICE · ONE WARNED RAIDER\nBROWN/RED: damaged repairable wall   WOOD/STEEL: mounted ballista   RED: physical raider\nShift-use wall with Planks to repair · bounded drill, not campaign gameplay"
	caption.position = Vector2(20, 138)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_constant_override("outline_size", 4)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	app.add_child(caption)


func _wait_ready() -> bool:
	for _frame in range(1200):
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
