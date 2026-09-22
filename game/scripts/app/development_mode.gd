class_name DevelopmentMode
extends Node

## ============================================================================
## CARD C STUB - the Development Expo entry card (card A) owns this file.
## ----------------------------------------------------------------------------
## Only what the layout / builder card needs to run and test its own work is
## here: a dedicated save namespace, the Expo-sized world bounds and the build
## on a fresh Development world. Card A's version (main-menu Development
## Start / Continue, the development pause panel, the canonical fixture
## version, Reset Expo with its confirmation, save isolation checks) REPLACES
## this file at integration; keep card A's and keep the three seams it uses:
##   set_builder(builder) / builder_for() ... how the Expo builder is attached
##   world_bounds() .................... what the session's world is sized to
##   reset_group(name) ................. what Reset Expo calls per district
## ============================================================================

const SAVE_DIR := "development"

var app: CraftAndDefendApp
var saves: SaveCoordinator
## True from Development Start / Continue until the session leaves the mode.
var active := false
var layout: ExpoLayout
var builder: ExpoBuilder
var last_build: Dictionary = {}


func setup(application: CraftAndDefendApp) -> void:
	app = application
	saves = SaveCoordinator.new(app.data_root.path_join(SAVE_DIR))
	# The Expo is authored, not rolled: one fixed seed, one canonical campus.
	saves.random_world_seed = false
	layout = ExpoLayout.new()
	var loaded := layout.load_layout()
	if not loaded.get("ok", false):
		push_error("DevelopmentMode: Expo layout failed to load (%s)" % str(loaded.get("reason", "")))
		return
	var expo_builder := ExpoBuilder.new()
	expo_builder.name = "ExpoBuilder"
	expo_builder.configure(layout)
	add_child(expo_builder)
	set_builder(expo_builder)


## Card A's seam: the Expo builder this mode drives.
func set_builder(expo_builder: ExpoBuilder) -> void:
	builder = expo_builder
	if builder != null and layout != null:
		builder.configure(layout)


func builder_for() -> ExpoBuilder:
	return builder


func has_save() -> bool:
	return saves != null and saves.has_checkpoint()


func data_root() -> String:
	return saves.data_root if saves != null else ""


## The canonical world bounds computed from the Expo layout plus its expansion
## margin (handoff section 6). The session hands these to the WorldAdapter in
## place of the ones in world.json; a normal game passes {} and keeps world.json.
func world_bounds() -> Dictionary:
	if layout == null:
		return {}
	var bounds := layout.world_bounds()
	var size: Vector3i = bounds.get("size", Vector3i.ZERO)
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		return {}
	return bounds


func begin(continue_existing: bool) -> void:
	active = true
	app._open_session(continue_existing)


func leave() -> void:
	active = false
	if builder != null:
		builder.clear_queue()


## Called by the app once the world is ready. A fresh Development world is
## built from the manifest; a continued one keeps whatever the owner changed
## (handoff section 13) and only the builder's reset groups rebuild anything.
func on_session_ready(fresh: bool) -> void:
	if app == null or app.session == null or builder == null:
		return
	builder.bind_session(app.session)
	if not fresh:
		last_build = {"built": false, "reason": "CONTINUED"}
		return
	last_build = builder.build_all()


func reset_group(group: String) -> Dictionary:
	if builder == null:
		return {"ok": false, "reason": "NO_BUILDER"}
	return builder.reset_group(group)
