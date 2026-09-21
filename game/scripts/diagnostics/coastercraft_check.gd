class_name CoasterCraftCheck
extends Node

## Headless check of the CoasterCraft mode (docs/COASTERCRAFT_MODE.md):
## `--coastercraft-check` boots the app, walks the mode through the same
## paths its buttons use (CoasterCraft > New, pause, Save, Save and Restart,
## Save and Exit to Menu, CoasterCraft > Continue) and asserts the plate is
## bare, the pause menu has no drill column, the mode's own save directory
## is used and a checkpoint continues. Prints `COASTERCRAFT_CHECK ok=…` and
## quits 0 / 1. The rails gate runs the same round trip in-process as T191
## (`exercise`).

const READY_TIMEOUT_MS := 90000
const PLATE_TIMEOUT_MS := 60000
const SAVE_TIMEOUT_MS := 120000
const RAIL_A := Vector3i(0, 1, 30)
const RAIL_B := Vector3i(2, 1, 34)

var app: CraftAndDefendApp
var failures: Array[String] = []
var evidence: Dictionary = {}


func run(application: CraftAndDefendApp) -> void:
	app = application
	var report := await exercise(app)
	print("COASTERCRAFT_CHECK ok=%s failures=%s evidence=%s" % [report.get("ok", false), report.get("failures", []), JSON.stringify(report.get("evidence", {}))])
	# Let the closed session's streaming settle before quitting (as the gates do).
	for _settle in range(60):
		await get_tree().process_frame
	get_tree().quit(0 if report.get("ok", false) else 1)


## The whole round trip from the main menu; returns {ok, failures, evidence}
## and leaves the app at the main menu.
func exercise(application: CraftAndDefendApp) -> Dictionary:
	app = application
	failures.clear()
	evidence.clear()
	_check("menu_state", app.state == CraftAndDefendApp.AppState.MAIN_MENU, "starts at the main menu (state %d)" % app.state)
	var game_checkpoint_before: bool = app.saves.has_checkpoint()
	# The submenu: Continue disabled until the mode has a save.
	app._show_coastercraft_menu()
	_check("submenu", app.coastercraft_menu_panel.visible and not app.menu_panel.visible, "CoasterCraft submenu shows over the main menu")
	var had_save: bool = app.coastercraft.has_save()
	_check("continue_gated", app.coastercraft_continue_button.disabled == not had_save, "Continue enabled only with a CoasterCraft save (had_save=%s disabled=%s)" % [had_save, app.coastercraft_continue_button.disabled])
	# New: the mode's coordinator, the bare plate, creative, stock, no drills.
	app._on_coastercraft_new_pressed()
	if not await _wait_ready():
		return _report()
	var first_session := app.session
	var mode_root: String = app.coastercraft.data_root()
	print("COASTERCRAFT DATA_ROOT %s" % mode_root)
	_check("save_dir", mode_root == app.data_root.path_join(CoasterCraftMode.SAVE_DIR) and app.active_saves() == app.coastercraft.saves and app.active_saves() != app.saves, "the session saves through the mode's coordinator under <data root>/coastercraft (%s)" % mode_root)
	_check("session_flags", app.session.coastercraft and app.coastercraft.active and app.session.interaction.creative and app.session.workstations.creative, "session is in CoasterCraft with creative placement")
	_check("fixed_seed", int(app.session.open_data.get("snapshot", {}).get("world", {}).get("seed", 0)) == SaveCoordinator.DEFAULT_WORLD_SEED and not bool(app.session.open_data.get("continued", true)), "a new world on the fixed seed %d" % SaveCoordinator.DEFAULT_WORLD_SEED)
	await _wait_plate()
	var bare := CoasterCraftMode.plate_bare_report(app.session)
	evidence["bare_new"] = bare
	_check("plate_bare", bool(bare.get("ok", false)) and int(bare.get("sampled", 0)) >= 200, "the plate is bare: stone at y 0 and air above across the sample grid, no stations (%s)" % JSON.stringify(bare))
	var spawn_ok := true
	for y in range(1, 4):
		if int(app.session.world.query_cell(Vector3i(0, y, 40)).get("voxel_id", 1)) != 0:
			spawn_ok = false
	_check("spawn_on_plate", spawn_ok and int(app.session.world.query_cell(Vector3i(0, 0, 40)).get("voxel_id", 0)) == 3 and app.session.player.global_position.y < 3.0 and app.session.player.global_position.y > 0.5, "the player stands on the plate at the spawn (%s)" % app.session.player.global_position)
	var registry := app.session.registry
	var stocked := true
	for item_id in CoasterCraftMode.STOCK:
		if app.session.inventory.count(item_id) < registry.max_stack(item_id):
			stocked = false
	var hotbar_ok := str(app.session.inventory.slots[0].get("item_id", "")) == "rail" and str(app.session.inventory.slots[7].get("item_id", "")) == "mine_cart" and str(app.session.inventory.slots[8].get("item_id", "")) == "coaster_car"
	_check("stock", stocked and hotbar_ok and app.session.inventory.count("core_of_power") == 0, "every stock item is at its stack size, the hotbar is in stock order (rail first, mine cart, coaster car), no Core of Power")
	_check("hud_lines", app.defense_label.text.is_empty() and not app.defense_label.visible and app.navigation_label.text.begins_with("COASTERCRAFT") and not app.navigation_label.text.contains("ENEMY BASE"), "the drill line is hidden and the navigation line names the mode without the enemy base (%s | %s)" % [app.defense_label.text, app.navigation_label.text])
	var no_enemy_core := true
	for record: Dictionary in app.session.workstations.stations.values():
		if str(record.get("entity_id", "")) == "enemy_core":
			no_enemy_core = false
	_check("no_monsters", no_enemy_core and not app.session.defense.is_active() and not app.session.core_defense.is_active() and app.minimap != null and not app.minimap.show_enemy_base, "no enemy core, no drill running, the minimap hides the enemy base")
	# The pause menu: the mode's panel, no drill column.
	app._pause_game()
	var buttons := _button_texts(app.coastercraft_pause_panel)
	var drill_buttons := 0
	for text: String in buttons:
		if text.to_lower().contains("drill") or text.to_lower().contains("attack"):
			drill_buttons += 1
	var wanted: Array[String] = ["Resume", "Save", "Save and Restart (new bare plate)", "Save and Exit to Menu", "Save and Quit", "Settings", "Keybinds"]
	var all_wanted := true
	for text: String in wanted:
		if not buttons.has(text):
			all_wanted = false
	evidence["pause_buttons"] = buttons
	_check("pause_menu", app.state == CraftAndDefendApp.AppState.PAUSED and app.coastercraft_pause_panel.visible and not app.pause_panel.visible and drill_buttons == 0 and all_wanted, "pausing shows CoasterCraft's own menu with Resume / Save / Save and Restart / Save and Exit / Save and Quit and no drills (%s)" % [buttons])
	# Save in place: a rail placed first must survive, the checkpoint lands
	# in the mode's directory, the game stays paused with the same session.
	var rail_a := app.session.workstations.try_place("rail", RAIL_A, app.session.world.query_cell, AABB(), 0)
	_check("rail_a", bool(rail_a.get("ok", false)), "a rail is placed on the plate (%s)" % rail_a.get("reason"))
	app._coastercraft_save()
	var saved := await _wait_state(CraftAndDefendApp.AppState.PAUSED, SAVE_TIMEOUT_MS)
	var status_a: Dictionary = app.coastercraft.saves.checkpoint_status()
	_check("save_in_place", saved and app.session == first_session and int(status_a.get("revision", 0)) == 1 and app.coastercraft_pause_panel.visible and app.session.workstations.stations.size() == 1, "Save checkpoints revision 1 in the mode's directory and returns to the paused game with the rail still placed (%s)" % JSON.stringify(status_a))
	app._resume_game()
	var streaming_back := await _wait_cell_loaded(RAIL_A, 30000)
	_check("resume_after_save", app.state == CraftAndDefendApp.AppState.PLAYING and streaming_back and int(app.session.world.query_cell(RAIL_A + Vector3i(0, -1, 0)).get("voxel_id", 0)) == 3, "the world streams again after the in-place save (plate stone under the rail)")
	# Save and Restart: a fresh bare plate, the rail is gone, the mode stays.
	app._pause_game()
	app._coastercraft_save_and_restart()
	var deadline := Time.get_ticks_msec() + SAVE_TIMEOUT_MS + READY_TIMEOUT_MS
	while app.session == null or app.session == first_session or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("restart timeout")
			return _report()
		await get_tree().process_frame
	await _wait_plate()
	var bare_restart := CoasterCraftMode.plate_bare_report(app.session)
	evidence["bare_restart"] = bare_restart
	var status_restart: Dictionary = app.coastercraft.saves.checkpoint_status()
	_check("restart", app.coastercraft.active and app.session.coastercraft and app.state == CraftAndDefendApp.AppState.PLAYING and bool(bare_restart.get("ok", false)) and int(status_restart.get("revision", 0)) == 2, "Save and Restart checkpoints revision 2 and opens a new bare plate (no rail) in the mode (%s)" % JSON.stringify(bare_restart))
	# Save and Exit to Menu, then Continue: the last checkpoint comes back.
	var rail_b := app.session.workstations.try_place("rail", RAIL_B, app.session.world.query_cell, AABB(), 0)
	_check("rail_b", bool(rail_b.get("ok", false)), "a rail is placed on the new plate (%s)" % rail_b.get("reason"))
	app._pause_game()
	app._save_and_exit_to_menu()
	var at_menu := await _wait_state(CraftAndDefendApp.AppState.MAIN_MENU, SAVE_TIMEOUT_MS)
	var status_exit: Dictionary = app.coastercraft.saves.checkpoint_status()
	_check("exit_to_menu", at_menu and app.session == null and not app.coastercraft.active and app.menu_panel.visible and int(status_exit.get("revision", 0)) == 3, "Save and Exit to Menu checkpoints revision 3 and leaves the mode (%s)" % JSON.stringify(status_exit))
	_check("game_saves_untouched", app.saves.has_checkpoint() == game_checkpoint_before, "the real game's slot is untouched (checkpoint before=%s after=%s)" % [game_checkpoint_before, app.saves.has_checkpoint()])
	app._show_coastercraft_menu()
	_check("continue_enabled", app.coastercraft_menu_panel.visible and not app.coastercraft_continue_button.disabled, "Continue is enabled once the mode has a save")
	app._on_coastercraft_continue_pressed()
	if not await _wait_ready():
		return _report()
	await _wait_cell_loaded(RAIL_B, 30000)
	var stations: Array = app.session.workstations.stations.values()
	var continued_rail: bool = stations.size() == 1 and Vector3i(stations[0].get("anchor", Vector3i.MAX)) == RAIL_B and str(stations[0].get("entity_id", "")) == "rail"
	var bare_continue := CoasterCraftMode.plate_bare_report(app.session)
	evidence["continue"] = {"stations": stations.size(), "plate": bare_continue}
	_check("continue", bool(app.session.open_data.get("continued", false)) and app.session.coastercraft and app.coastercraft.active and continued_rail and int(bare_continue.get("stone", 0)) == int(bare_continue.get("sampled", 0)) and app.session.interaction.creative and app.session.inventory.count("rail") == registry.max_stack("rail"), "Continue restores the last checkpoint: the plate, the one rail at %s, creative and the stock" % RAIL_B)
	# Leave the app at the main menu.
	app._pause_game()
	app._save_and_exit_to_menu()
	var left := await _wait_state(CraftAndDefendApp.AppState.MAIN_MENU, SAVE_TIMEOUT_MS)
	_check("final_exit", left and app.session == null, "the continued session saves and exits to the menu")
	return _report()


func _report() -> Dictionary:
	return {"ok": failures.is_empty(), "failures": failures.duplicate(), "evidence": evidence.duplicate(true)}


func _check(step: String, ok: bool, expected: String) -> void:
	evidence[step] = ok
	print("COASTERCRAFT_CHECK %s %s: %s" % [step, "PASS" if ok else "FAIL", expected])
	if not ok:
		failures.append(step)


func _button_texts(panel: Control) -> Array[String]:
	var texts: Array[String] = []
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Button:
			texts.append((node as Button).text)
		for child in node.get_children():
			pending.append(child)
	return texts


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + READY_TIMEOUT_MS
	while app.session == null or not app.session.world_ready or app.state != CraftAndDefendApp.AppState.PLAYING:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	# A frame for the spawn hand-off (stock, respawn placement, HUD lines).
	for _frame in range(20):
		await get_tree().process_frame
	return true


## Waits for the mode to level every plate column (its chunks stream in
## over a few seconds); the remaining count is recorded either way.
func _wait_plate() -> void:
	var deadline := Time.get_ticks_msec() + PLATE_TIMEOUT_MS
	while app.coastercraft.pending_columns() > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	evidence["plate_pending"] = app.coastercraft.pending_columns()
	evidence["plate_levelled"] = app.coastercraft.levelled_columns()
	print("COASTERCRAFT_CHECK plate levelled=%d pending=%d" % [app.coastercraft.levelled_columns(), app.coastercraft.pending_columns()])


func _wait_state(wanted: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while app.state != wanted:
		if Time.get_ticks_msec() >= deadline:
			failures.append("state %d timeout (state %d)" % [wanted, app.state])
			return false
		await get_tree().process_frame
	return true


func _wait_cell_loaded(cell: Vector3i, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while app.session != null and str(app.session.world.query_cell(cell).get("state", "")) != "LOADED":
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().process_frame
	return app.session != null
