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
	var graphics_defaults := app.settings.msaa_3d == SettingsStore.DEFAULT_MSAA_3D and app.settings.vsync_enabled and app.get_viewport().msaa_3d == Viewport.MSAA_4X and bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	_record("T35_GRAPHICS_DEFAULTS", graphics_defaults, "4× MSAA, VSync and physics interpolation are active by default", {"msaa": app.get_viewport().msaa_3d, "vsync": app.settings.vsync_enabled, "physics_interpolation": ProjectSettings.get_setting("physics/common/physics_interpolation", false)})
	var graphics_saved := app.settings.set_graphics_preferences(Viewport.MSAA_8X, false)
	app._apply_runtime_graphics()
	_record("T35_GRAPHICS_SAVE", graphics_saved.get("ok", false) and app.get_viewport().msaa_3d == Viewport.MSAA_8X and not app.settings.vsync_enabled, "graphics quality changes apply and persist through the settings store", graphics_saved)
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.apply_world_settings("0810", true)
	var sun_rotation_before := app.session._sun.rotation
	app.session.clock.advance(0.1, false)
	app.session._process(0.0)
	var shadow_tuning := app.session._sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS and app.session._sun.directional_shadow_blend_splits and is_equal_approx(app.session._sun.directional_shadow_max_distance, 48.0)
	var minute_stable := sun_rotation_before.is_equal_approx(app.session._sun.rotation)
	_record("T35_SHADOW_STABILITY", shadow_tuning and minute_stable, "directional shadows use four blended near-field splits and do not reproject within the same game minute", {"shadow_tuning": shadow_tuning, "minute_stable": minute_stable, "max_distance": app.session._sun.directional_shadow_max_distance})
	app._show_inventory()
	var inventory_only := app.state == app.AppState.INVENTORY and app.inventory_panel.visible and not app.crafting_panel.visible and not get_tree().paused and app.session.menu_open and not app.session.player.active
	app._close_inventory()
	app.session.inventory.try_transaction({}, {"log": 2, "planks": 4, "stick": 2})
	app._show_crafting()
	var hand_only := app.state == app.AppState.CRAFTING and app.crafting_panel.visible and not app.inventory_panel.visible and app.crafting_grid.columns == 2 and app.crafting_grid.get_child_count() == 4 and app.crafting_inventory_slots.size() == F0Inventory.SLOT_COUNT and app.crafting_recipe_search != null and not get_tree().paused and app.session.menu_open and not app.session.player.active
	app._select_crafting_recipe("planks")
	var recipe_autofill := app._selected_recipe_id == "planks" and app._grid_counts(app._craft_grid_items) == {"log": 1}
	app._clear_crafting_grid()
	app._on_crafting_item_dropped("grid", 0, {"kind": "crafting_item", "source_kind": "inventory", "source_index": 0, "item_id": "log"})
	var manual_grid := app._selected_recipe_id == "planks" and app._grid_matches_recipe(app.session.registry.recipe("planks"))
	app.crafting_recipe_search.text = "work"
	app._on_crafting_recipe_search_submitted("work")
	var search_autofill := app._selected_recipe_id == "workbench" and app._grid_counts(app._craft_grid_items) == {"planks": 4}
	app._close_crafting()
	_record("T31_CONTEXTS", inventory_only and hand_only and app.state == app.AppState.PLAYING and not get_tree().paused and app.session.player.active, "Tab inventory and three-panel hand crafting are separate UI contexts (the world keeps running under them) and return cleanly to play", {"inventory_only": inventory_only, "hand_only": hand_only, "state": app.state})
	_record("T36_CRAFTING_INPUT", recipe_autofill and manual_grid and search_autofill, "inventory-to-grid staging, manual recognition and Enter-to-autofill recipe search all work", {"recipe_autofill": recipe_autofill, "manual_grid": manual_grid, "search_autofill": search_autofill})
	app._show_crafting("furnace_diagnostic", "furnace")
	var furnace_only := app.state == app.AppState.CRAFTING and app.crafting_title_label.text == "FURNACE" and app.crafting_grid.columns == 3 and app.crafting_grid.get_child_count() == 3 and app.craft_selected_button.text == "Start Processing" and app.crafting_inventory_slots.size() == F0Inventory.SLOT_COUNT and app.crafting_clear_button.text == "Return Input + Fuel"
	app._close_crafting()
	_record("T33_FURNACE_MODAL", furnace_only and app.state == app.AppState.PLAYING, "Furnace owns distinct input, fuel and retained-output slots and returns cleanly to play", {"furnace_modal": furnace_only, "state": app.state})


func _run_phase2() -> void:
	_record("T31_BUILD_RESTART", app.settings.get_keycode("build") == KEY_V, "Build binding persists through a complete process restart", app.settings.get_binding("build"))
	_record("T35_GRAPHICS_RESTART", app.settings.msaa_3d == Viewport.MSAA_8X and not app.settings.vsync_enabled and app.get_viewport().msaa_3d == Viewport.MSAA_8X, "graphics quality persists through a complete process restart", {"msaa": app.get_viewport().msaa_3d, "vsync": app.settings.vsync_enabled})
	app.settings.set_graphics_preferences(SettingsStore.DEFAULT_MSAA_3D, SettingsStore.DEFAULT_VSYNC_ENABLED)
	app._apply_runtime_graphics()
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
	app._select_crafting_recipe("wood_pick")
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
