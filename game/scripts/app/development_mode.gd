class_name DevelopmentMode
extends Node

## Development Start (docs/DEVELOPMENT_EXPO.md): the owner's development
## world behind the main menu's Development Start button. It is the ordinary
## game - the same terrain, stations, industry, siege and day/night - opened
## on its own `<data root>/development/` coordinator so Slot A, Slot B and
## CoasterCraft are never read or written by it. What differs is only what
## §13 of the commission asks for: no ambient enemy pressure, no drill HUD
## line, no enemy-base compass, a stable daytime on a fresh world, and its
## own pause menu with Reset Expo. Inventory is NOT infinite here; the Expo's
## Supply Depot provides test stock.
##
## Modelled on CoasterCraftMode. The seams the other Expo cards use are at
## the bottom of this file:
##   * `set_builder(callable)` / `build_expo(session, fresh)` - the canonical
##     Expo fixture builder (card C); a stub until one is registered.
##   * `register_reset_group(name, callable)` / `reset_group(session, name)` -
##     the named reset groups of `ExpoResetService` (card E registers
##     `battlefield`).
##   * `EXPO_FIXTURE_VERSION` - bump it when the canonical fixture changes;
##     the session saves it (`snapshot()["expo"]["fixture_version"]`) so a
##     later card can spot a world built from an outdated fixture.

const SAVE_DIR := "development"
## The canonical Expo fixture this build generates. Raise it whenever the
## authored Expo changes in a way that an existing development world should
## be rebuilt for (Reset Expo).
const EXPO_FIXTURE_VERSION := 1
## A fresh development world starts at this time of day (mid-morning, full
## light). The clock keeps running afterwards: day/night is not removed.
const START_TIME := "09:00"

var app: CraftAndDefendApp
var saves: SaveCoordinator
## True from the moment Development New / Continue is pressed until the
## session leaves the mode (exit to menu, quit).
var active := false
## Set while `build_expo` runs so the check and the other cards can see it.
var building := false
## The last build report: {ok, fresh, builder, seconds}.
var last_build: Dictionary = {}
## Reset Expo asked for: the next session opened by this mode rebuilds the
## fixture from scratch.
var _reset_requested := false
var _builder: Callable = Callable()
var _reset_groups: Dictionary = {}
## The Expo manifest solved into districts, parcels, avenues and world bounds.
var layout: ExpoLayout
## The canonical fixture builder registered into `set_builder` at setup.
var expo_builder: ExpoBuilder


func setup(application: CraftAndDefendApp) -> void:
	app = application
	saves = SaveCoordinator.new(app.data_root.path_join(SAVE_DIR))
	# The fixed default seed: the canonical Expo is the same world every time.
	saves.random_world_seed = false
	# The Expo layout and builder (docs/DEVELOPMENT_EXPO.md sections 1-3) are
	# this mode's canonical fixture: `build_expo` drives the builder through
	# the `set_builder` seam, so Development New and Reset Expo both build the
	# campus, and `world_bounds()` sizes the world to what the layout needs.
	layout = ExpoLayout.new()
	var loaded := layout.load_layout()
	if not loaded.get("ok", false):
		push_error("DevelopmentMode: Expo layout failed to load (%s)" % str(loaded.get("reason", "")))
		layout = null
		return
	expo_builder = ExpoBuilder.new()
	expo_builder.name = "ExpoBuilder"
	expo_builder.configure(layout)
	add_child(expo_builder)
	set_builder(_build_with_expo_builder)


## The `set_builder` seam's handler for the real `ExpoBuilder`: it binds the
## session, queues the whole campus and hands every district's reset group up
## to this mode so Reset Expo and `reset_group` reach them.
func _build_with_expo_builder(session: GameSession, fresh: bool) -> Dictionary:
	if expo_builder == null:
		return {"ok": false, "reason": "NO_BUILDER"}
	expo_builder.bind_session(session)
	if not fresh:
		return {"ok": true, "reason": "CONTINUED", "built": false}
	var report := expo_builder.build_all()
	for group: String in expo_builder.reset_groups():
		register_reset_group(group, _reset_builder_group.bind(group))
	return report


func _reset_builder_group(_session: GameSession, group: String) -> Dictionary:
	return expo_builder.reset_group(group) if expo_builder != null else {"ok": false, "reason": "NO_BUILDER"}


## The canonical world bounds computed from the Expo layout plus its expansion
## margin (commission section 6). The app hands these to the session, which
## passes them to `WorldAdapter.initialize` as `bounds_override`; a normal game
## passes {} and keeps world.json's bounds.
func world_bounds() -> Dictionary:
	if layout == null:
		return {}
	var bounds := layout.world_bounds()
	var size: Variant = bounds.get("size", Vector3i.ZERO)
	if not size is Vector3i:
		return {}
	var extent: Vector3i = size
	if extent.x <= 0 or extent.y <= 0 or extent.z <= 0:
		return {}
	return bounds


func has_save() -> bool:
	return saves != null and saves.has_checkpoint()


func data_root() -> String:
	return saves.data_root if saves != null else ""


## New (continue_existing false) or Continue: opens the session through the
## app's ordinary path with this mode's coordinator.
func begin(continue_existing: bool) -> void:
	active = true
	app._open_session(continue_existing)


func leave() -> void:
	active = false
	building = false
	if expo_builder != null:
		expo_builder.clear_queue()


## Called by the app once the world is ready. A fresh world (New, or Reset
## Expo) gets the canonical Expo and the stable start time; a continued world
## keeps whatever the owner left behind.
func on_session_ready(fresh: bool) -> void:
	if app == null or app.session == null:
		return
	var session: GameSession = app.session
	session.expo_fixture_version = EXPO_FIXTURE_VERSION
	if fresh:
		session.set_clock_time(START_TIME)
		build_expo(session, true)
	else:
		# A continued world keeps what the owner left behind, but the builder
		# still binds to it so Reset Expo and the district reset groups work.
		build_expo(session, false)
	_reset_requested = false


func _process(_delta: float) -> void:
	# The Expo has no per-frame work of its own yet (the builder runs once on
	# a fresh world). Card C may budget its levelling here, as CoasterCraft
	# does for its plate.
	pass


# --- Seams for the other Expo cards -------------------------------------------


## Registers the canonical Expo builder. `builder` is called as
## `builder.call(session, fresh)` and returns a Dictionary report (`ok`).
## Card C registers the real ExpoBuilder; without one `build_expo` is a stub
## that changes nothing.
func set_builder(builder: Callable) -> void:
	_builder = builder


func has_builder() -> bool:
	return _builder.is_valid()


## Builds (or rebuilds) the canonical Expo into `session`. Called on a fresh
## development world and by Reset Expo. Logs `EXPO_BUILD start` /
## `EXPO_BUILD end` around the registered builder so every card's runs are
## visible in the log; with no builder registered it is a no-op stub.
func build_expo(session: GameSession, fresh: bool) -> Dictionary:
	if session == null:
		return {"ok": false, "reason": "NO_SESSION"}
	var started := Time.get_ticks_msec()
	building = true
	print("EXPO_BUILD start fixture=%d fresh=%s builder=%s" % [EXPO_FIXTURE_VERSION, fresh, _builder.is_valid()])
	var report: Dictionary = {"ok": true, "reason": "NO_BUILDER"}
	if _builder.is_valid():
		var returned: Variant = _builder.call(session, fresh)
		if returned is Dictionary:
			report = returned
		else:
			report = {"ok": true, "reason": "OK"}
	session.expo_fixture_version = EXPO_FIXTURE_VERSION
	building = false
	last_build = {"ok": bool(report.get("ok", false)), "fresh": fresh, "builder": _builder.is_valid(), "seconds": float(Time.get_ticks_msec() - started) / 1000.0}
	print("EXPO_BUILD end ok=%s builder=%s seconds=%.2f" % [last_build.ok, last_build.builder, last_build.seconds])
	return report


## Registers a named reset group (§14, `ExpoResetService`). `handler` is
## called as `handler.call(session)` and returns a Dictionary report.
## Card E registers `battlefield`.
func register_reset_group(group: String, handler: Callable) -> void:
	if group.is_empty() or not handler.is_valid():
		return
	_reset_groups[group] = handler


func reset_groups() -> Array[String]:
	var names: Array[String] = []
	for group: String in _reset_groups.keys():
		names.append(group)
	names.sort()
	return names


## Restores one named district (`battlefield`, …) without touching the rest
## of the Expo. Unknown group: `{"ok": false, "reason": "NO_GROUP"}`.
func reset_group(session: GameSession, group: String) -> Dictionary:
	if session == null:
		return {"ok": false, "reason": "NO_SESSION"}
	if not _reset_groups.has(group):
		return {"ok": false, "reason": "NO_GROUP", "group": group}
	var handler: Callable = _reset_groups[group]
	if not handler.is_valid():
		return {"ok": false, "reason": "NO_GROUP", "group": group}
	var returned: Variant = handler.call(session)
	var report: Dictionary = returned if returned is Dictionary else {"ok": true, "reason": "OK"}
	report["group"] = group
	return report


## Reset Expo (pause menu, after its confirmation): the development world is
## regenerated from the canonical fixture and the development-world changes
## are discarded. It is a New into the same save file, so the app checkpoints
## the rebuilt world over the old one - no other save is touched.
func request_reset() -> void:
	_reset_requested = true


func reset_requested() -> bool:
	return _reset_requested
