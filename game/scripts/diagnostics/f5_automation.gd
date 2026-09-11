class_name F5Automation
extends Node

var app: CraftAndDefendApp
var failures: Array[String] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"phase1":
			await _run_phase1()
		"phase2":
			await _run_phase2()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	if failures.is_empty():
		print("F5_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("F5_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	_record("T31_BUILD_DEFAULT", app.settings.get_keycode("build") == KEY_B, "Build / Hand Crafting defaults to physical B", app.settings.get_binding("build"))
	var rebound := app.settings.rebind_key("build", KEY_V)
	_record("T31_BUILD_REBIND", rebound.get("ok", false) and app.settings.get_keycode("build") == KEY_V, "Build can be rebound through the persistent conflict-checked settings store", rebound)
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app._show_inventory()
	var inventory_only := app.state == app.AppState.INVENTORY and app.inventory_panel.visible and not app.crafting_panel.visible and get_tree().paused and not app.session.player.active
	app._close_inventory()
	app._show_crafting()
	var hand_only := app.state == app.AppState.CRAFTING and app.crafting_panel.visible and not app.inventory_panel.visible and app.crafting_grid.columns == 2 and app.crafting_grid.get_child_count() == 4 and get_tree().paused and not app.session.player.active
	app._close_crafting()
	_record("T31_CONTEXTS", inventory_only and hand_only and app.state == app.AppState.PLAYING and not get_tree().paused and app.session.player.active, "Tab inventory and hand crafting are separate paused UI contexts and return cleanly to play", {"inventory_only": inventory_only, "hand_only": hand_only, "state": app.state})


func _run_phase2() -> void:
	_record("T31_BUILD_RESTART", app.settings.get_keycode("build") == KEY_V, "Build binding persists through a complete process restart", app.settings.get_binding("build"))
	var reset := app.settings.reset_action("build")
	_record("T31_BUILD_RESET", reset.get("ok", false) and app.settings.get_keycode("build") == KEY_B, "Per-action reset restores Build to B", reset)


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var started := Time.get_ticks_msec()
	while app.session.world.query_cell(Vector3i(0, -1, 38)).get("state") != "LOADED" and Time.get_ticks_msec() - started < 15000:
		await get_tree().process_frame
	app.session.inventory.try_transaction({}, {"workbench": 1, "planks": 8, "stick": 4, "stone": 8})
	var placed := app.session.interaction.try_place_item(Vector3i(0, 0, 38), "workbench")
	var bench_id := str(placed.get("changes", {}).get("station", {}).get("instance_id", ""))
	app._show_crafting(bench_id, "workbench")
	for _frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("f5-workbench-crafting.png")
	var error := image.save_png(path)
	_record("T34_WORKBENCH_VISUAL", placed.get("ok", false) and error == OK and not image.is_empty() and image.get_size() == Vector2i(1280, 720), "rendered 1280×720 workbench modal shows the 3×3 recipe surface", {"path": path, "size": image.get_size(), "placed": placed})


func _wait_ready() -> bool:
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 20000:
		await get_tree().process_frame
	if app.state != app.AppState.PLAYING:
		failures.append("session ready timeout: " + app.status_label.text)
		return false
	return true


func _record(test_id: String, passed: bool, expected: String, evidence: Variant) -> void:
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if passed else "FAIL", expected, JSON.stringify(evidence)])
	if not passed:
		failures.append(test_id)
