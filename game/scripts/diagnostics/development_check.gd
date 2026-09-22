class_name DevelopmentCheck
extends Node

## Headless check of Development Start (docs/DEVELOPMENT_EXPO.md):
## `--development-check` boots the app, walks the mode through the same paths
## its buttons use (Development Start > New, pause, Reset Expo and its
## confirmation) and asserts the save namespace, the runtime rules (no
## ambient enemy pressure, no drill line, a daytime clock, no creative
## top-up) and that a normal save is untouched by any of it
## (T211_DEVELOPMENT_MODE_ISOLATION). Prints `DEVELOPMENT_CHECK ok=…` and
## quits 0 / 1.

const READY_TIMEOUT_MS := 90000
## The normal-slot fixture the isolation test watches. It is a complete
## checkpoint on disk in Slot A, written before the mode is ever opened.
const MARKER_TEXT := "development-check-marker"

var app: CraftAndDefendApp
var failures: Array[String] = []
var evidence: Dictionary = {}
## Set by the probe builder registered before Reset Expo.
var _probe_builds := 0
var _probe_resets := 0


func run(application: CraftAndDefendApp) -> void:
	app = application
	var report := await exercise(app)
	print("DEVELOPMENT_CHECK ok=%s failures=%s evidence=%s" % [report.get("ok", false), report.get("failures", []), JSON.stringify(report.get("evidence", {}))])
	# Let the closed session's streaming settle before quitting (as the gates do).
	for _settle in range(60):
		await get_tree().process_frame
	get_tree().quit(0 if report.get("ok", false) else 1)


## The whole round trip from the main menu; returns {ok, failures, evidence}.
func exercise(application: CraftAndDefendApp) -> Dictionary:
	app = application
	failures.clear()
	evidence.clear()
	_check("menu_state", app.state == CraftAndDefendApp.AppState.MAIN_MENU, "starts at the main menu (state %d)" % app.state)
	# A complete normal checkpoint in Slot A, with a marker to read back.
	_write_normal_slot_marker()
	var normal_before := app.saves.checkpoint_status("a")
	var normal_marker_before := str(normal_before.get("snapshot", {}).get("development_check_marker", ""))
	var coastercraft_before: bool = app.coastercraft.has_save()
	_check("normal_fixture", normal_before.get("ok", false) and normal_marker_before == MARKER_TEXT, "a normal Slot A checkpoint with the marker exists before the mode is opened (%s)" % JSON.stringify(normal_before.get("reason", "OK")))
	# The submenu: Continue disabled until the mode has a save.
	app._show_development_menu()
	var had_save: bool = app.development.has_save()
	_check("submenu", app.development_menu_panel.visible and not app.menu_panel.visible, "the Development submenu shows over the main menu")
	_check("continue_gated", app.development_continue_button.disabled == not had_save, "Continue is enabled only with a development save (had_save=%s disabled=%s)" % [had_save, app.development_continue_button.disabled])
	# New: the mode's coordinator, the Expo build, the runtime rules.
	app._on_development_new_pressed()
	if not await _wait_ready():
		return _report()
	var mode_root: String = app.development.data_root()
	print("DEVELOPMENT DATA_ROOT %s" % mode_root)
	evidence["data_root"] = mode_root
	_check("save_dir", mode_root == app.data_root.path_join(DevelopmentMode.SAVE_DIR) and app.active_saves() == app.development.saves and app.active_saves() != app.saves and app.active_saves() != app.coastercraft.saves, "the session saves through the mode's own coordinator under <data root>/development (%s)" % mode_root)
	_check("session_flags", app.session.development and app.development.active and not app.session.coastercraft and not app.coastercraft.active, "the session is in Development mode and not in CoasterCraft")
	_check("fixture_version", app.session.expo_fixture_version == DevelopmentMode.EXPO_FIXTURE_VERSION and int(app.session.snapshot().get("expo", {}).get("fixture_version", -1)) == DevelopmentMode.EXPO_FIXTURE_VERSION and str(app.session.snapshot().get("mode", "")) == "development", "the snapshot records the mode and the canonical fixture version %d" % DevelopmentMode.EXPO_FIXTURE_VERSION)
	# No ambient pressure: nothing scheduled, no enemy core, no drill line.
	var enemy_core_stations := 0
	for record: Dictionary in app.session.workstations.stations.values():
		if str(record.get("entity_id", "")) == "enemy_core":
			enemy_core_stations += 1
	var quiet := not app.session.core_defense.is_active() and not app.session.defense.is_active() and app.session.core_defense.state == CoreDefenseService.IDLE and enemy_core_stations == 0
	# Nothing may schedule a wave on its own: let the world run for a while.
	for _frame in range(180):
		await get_tree().process_frame
	var still_quiet := not app.session.core_defense.is_active() and not app.session.defense.is_active() and app.session.core_defense.state == CoreDefenseService.IDLE
	evidence["waves"] = {"state": app.session.core_defense.state, "enemy_cores": enemy_core_stations}
	_check("no_ambient_waves", quiet and still_quiet, "no wave is scheduled and no enemy core is placed after three seconds of play (%s)" % JSON.stringify(evidence["waves"]))
	_check("hud_lines", app.defense_label.text.is_empty() and not app.defense_label.visible and app.navigation_label.text.begins_with("DEVELOPMENT EXPO") and not app.navigation_label.text.contains("ENEMY BASE") and app.minimap != null and not app.minimap.show_enemy_base, "the drill line is hidden and the navigation line names the Expo without the enemy base (%s | %s)" % [app.defense_label.text, app.navigation_label.text])
	var minutes: int = app.session.clock.current_minutes()
	evidence["clock_minutes"] = minutes
	_check("daytime", minutes >= DayNightClock.SUNRISE_MINUTES and minutes <= DayNightClock.SUNSET_MINUTES and app.session.clock.cycle_enabled, "a fresh Expo opens in daylight (%s) with the day/night cycle still running" % app.session.clock.time_label())
	# Inventory is not infinite here: nothing tops the pack up (§13).
	var pack_before: int = _pack_size()
	for _pack_frame in range(120):
		await get_tree().process_frame
	var pack_after: int = _pack_size()
	evidence["pack"] = {"before": pack_before, "after": pack_after}
	_check("no_creative_top_up", pack_after == pack_before and not app.session.interaction.creative and not app.session.workstations.creative, "the pack is not topped up and placement is not creative (%d -> %d items)" % [pack_before, pack_after])
	# The builder seam: New ran the canonical ExpoBuilder registered at setup
	# (the card-A stub build is gone now that card C's builder is wired in).
	evidence["canonical_build"] = app.development.last_build.duplicate(true)
	_check("canonical_build", bool(app.development.last_build.get("ok", false)) and bool(app.development.last_build.get("builder", false)) and bool(app.development.last_build.get("fresh", false)) and app.development.expo_builder != null, "a fresh world ran build_expo through the canonical ExpoBuilder (%s)" % JSON.stringify(app.development.last_build))
	# The reset-group seam: unknown groups are refused, a registered one runs.
	var unknown := app.development.reset_group(app.session, "battlefield")
	app.development.register_reset_group("probe", _probe_reset)
	var known := app.development.reset_group(app.session, "probe")
	evidence["reset_group"] = {"unknown": unknown, "known": known, "groups": app.development.reset_groups()}
	_check("reset_group_seam", str(unknown.get("reason", "")) == "NO_GROUP" and known.get("ok", false) and _probe_resets == 1, "reset_group refuses an unregistered group and runs a registered one (%s)" % JSON.stringify(evidence["reset_group"]))
	# The pause menu: the mode's own panel, no drills, Reset Expo present.
	app._pause_game()
	var buttons := _button_texts(app.development_pause_panel)
	var drill_buttons := 0
	for text: String in buttons:
		if text.to_lower().contains("drill") or text.to_lower().contains("attack"):
			drill_buttons += 1
	var wanted: Array[String] = ["Resume", "Save", "Reset Expo", "Save and Exit to Menu", "Save and Quit", "Settings", "Keybinds"]
	var all_wanted := true
	for text: String in wanted:
		if not buttons.has(text):
			all_wanted = false
	evidence["pause_buttons"] = buttons
	_check("pause_menu", app.state == CraftAndDefendApp.AppState.PAUSED and app.development_pause_panel.visible and not app.pause_panel.visible and not app.coastercraft_pause_panel.visible and drill_buttons == 0 and all_wanted, "pausing shows the Expo's own menu with Resume / Save / Reset Expo / Save and Exit / Save and Quit and no drills (%s)" % [buttons])
	# Reset Expo: the confirmation first, then the fixture path with a builder.
	app._development_reset_pressed()
	var confirm_shown: bool = app.development_reset_panel.visible and not app.development_pause_panel.visible
	app._cancel_development_reset()
	var cancel_kept: bool = not app.development_reset_panel.visible and app.development_pause_panel.visible and app.session != null
	_check("reset_confirmation", confirm_shown and cancel_kept, "Reset Expo asks first and keeping this world changes nothing")
	app.development.set_builder(_probe_builder)
	var reset_session := app.session
	app._development_reset_pressed()
	app._development_reset_confirmed()
	if not await _wait_new_session(reset_session):
		return _report()
	evidence["reset_build"] = app.development.last_build.duplicate(true)
	_check("reset_expo", app.session != reset_session and app.session.development and app.development.active and not bool(app.session.open_data.get("continued", true)) and _probe_builds == 1 and bool(app.development.last_build.get("builder", false)), "Reset Expo opens a new world on the same save file and runs the canonical fixture builder (%s)" % JSON.stringify(app.development.last_build))
	# Isolation: nothing the mode did touched the normal or CoasterCraft saves.
	var normal_after := app.saves.checkpoint_status("a")
	var normal_marker_after := str(normal_after.get("snapshot", {}).get("development_check_marker", ""))
	var isolated: bool = normal_after.get("ok", false) and normal_marker_after == MARKER_TEXT and int(normal_after.get("revision", -1)) == int(normal_before.get("revision", -2)) and app.coastercraft.has_save() == coastercraft_before and not app.development.data_root().begins_with(app.saves.slots_base_root)
	evidence["T211_DEVELOPMENT_MODE_ISOLATION"] = {"normal_revision_before": normal_before.get("revision", -2), "normal_revision_after": normal_after.get("revision", -1), "marker": normal_marker_after, "coastercraft_save": app.coastercraft.has_save(), "development_root": app.development.data_root(), "game_root": app.saves.data_root}
	_check("T211_DEVELOPMENT_MODE_ISOLATION", isolated, "a Development New and a Reset Expo leave Slot A (marker and revision) and the CoasterCraft namespace untouched (%s)" % JSON.stringify(evidence["T211_DEVELOPMENT_MODE_ISOLATION"]))
	# Leave the app at the main menu with the Expo saved.
	app._pause_game()
	app._save_and_exit_to_menu()
	var left := await _wait_state(CraftAndDefendApp.AppState.MAIN_MENU, 120000)
	var saved_status := app.development.saves.checkpoint_status()
	_check("save_and_exit", left and app.session == null and not app.development.active and saved_status.get("ok", false), "Save and Exit to Menu checkpoints the Expo in its own namespace (%s)" % JSON.stringify(saved_status.get("reason", "OK")))
	app._show_development_menu()
	_check("continue_enabled", app.development_menu_panel.visible and not app.development_continue_button.disabled, "Continue is enabled once the Expo has a save")
	app._show_main_menu()
	return _report()


## A stand-in for card C's ExpoBuilder: proves build_expo runs its callable.
func _probe_builder(session: GameSession, fresh: bool) -> Dictionary:
	_probe_builds += 1
	return {"ok": session != null, "reason": "PROBE", "fresh": fresh}


## A stand-in for card E's `battlefield` group.
func _probe_reset(session: GameSession) -> Dictionary:
	_probe_resets += 1
	return {"ok": session != null, "reason": "PROBE"}


func _pack_size() -> int:
	var total := 0
	for slot: Dictionary in app.session.inventory.slots:
		total += int(slot.get("count", 0))
	return total


## A complete normal-game checkpoint in Slot A carrying the marker. It is
## written straight to disk (as F3's fixtures are) so the isolation test has
## something to watch without opening a second world.
func _write_normal_slot_marker() -> void:
	var slot_root: String = app.saves.slots_base_root.path_join("a")
	var checkpoint := slot_root.path_join("checkpoints/checkpoint_000001_devcheck")
	_write_text(checkpoint.path_join("world.sqlite"), "development-check-fixture")
	var gameplay := {
		"schema_version": SaveCoordinator.SAVE_SCHEMA,
		"content_version": SaveCoordinator.CONTENT_VERSION,
		"development_check_marker": MARKER_TEXT,
		"inventory": {"dirt": 0, "revision": 0},
		"workstations": {"stations": [], "jobs": {}},
		"player": {"position": [0.5, 2.0, 40.5]},
	}
	_write_text(checkpoint.path_join("gameplay.json"), JSON.stringify(gameplay, "  "))
	var manifest := {
		"schema_version": SaveCoordinator.SAVE_SCHEMA,
		"content_version": SaveCoordinator.CONTENT_VERSION,
		"checkpoint_revision": 1,
		"database_sha256": FileAccess.get_sha256(checkpoint.path_join("world.sqlite")),
		"gameplay_sha256": FileAccess.get_sha256(checkpoint.path_join("gameplay.json")),
	}
	_write_text(checkpoint.path_join("manifest.json"), JSON.stringify(manifest, "  "))
	_write_text(slot_root.path_join("current.json"), JSON.stringify({"schema_version": SaveCoordinator.SAVE_SCHEMA, "revision": 1, "checkpoint": "checkpoint_000001_devcheck", "slot_id": "a"}, "  "))


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("write failed " + path)
		return
	file.store_string(text)
	file.close()


func _report() -> Dictionary:
	return {"ok": failures.is_empty(), "failures": failures.duplicate(), "evidence": evidence.duplicate(true)}


func _check(step: String, ok: bool, expected: String) -> void:
	evidence[step] = ok
	print("DEVELOPMENT_CHECK %s %s: %s" % [step, "PASS" if ok else "FAIL", expected])
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
	# A frame for the spawn hand-off (Expo build, HUD lines).
	for _frame in range(20):
		await get_tree().process_frame
	return true


func _wait_new_session(previous: GameSession) -> bool:
	var deadline := Time.get_ticks_msec() + READY_TIMEOUT_MS
	while app.session == null or app.session == previous or not app.session.world_ready or app.state != CraftAndDefendApp.AppState.PLAYING:
		if Time.get_ticks_msec() >= deadline:
			failures.append("reset session timeout")
			return false
		await get_tree().process_frame
	for _frame in range(20):
		await get_tree().process_frame
	return true


func _wait_state(wanted: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while app.state != wanted:
		if Time.get_ticks_msec() >= deadline:
			failures.append("state %d timeout (state %d)" % [wanted, app.state])
			return false
		await get_tree().process_frame
	return true
