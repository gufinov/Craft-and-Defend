class_name GameSession
extends Node3D

signal ready_for_play
signal hud_changed(text: String)
signal status_changed(message: String)
signal feedback_changed(message: String)
signal inventory_changed(snapshot: Dictionary)
signal workstation_requested(instance_id: String, station_type: String)
signal navigation_changed(text: String)
signal defense_changed(text: String)
## The player's health reached zero (the respawn already ran): an open menu closes.
signal player_died
## The world could not be restored after it streamed in. The app leaves the
## loading screen and offers Back to Main Menu; it is never left spinning
## (lost-Core Continue, docs/DEVELOPMENT_EXPO.md).
signal load_failed(reason: String)

const REASON_TEXT := {
	"OK": "Edit complete.",
	"OUT_OF_BOUNDS": "World boundary — that cell is outside the finite test world.",
	"UNLOADED": "That area is still loading; try again in a moment.",
	"OCCUPIED": "Placement rejected — that cell is occupied.",
	"PLAYER_OVERLAP": "Placement rejected — move out of the target cell.",
	"UNSUPPORTED": "Placement rejected — attach the block to a solid neighboring face.",
	"WRONG_TOOL": "That block needs a different tool.",
	"OUT_OF_REACH": "That target is out of reach.",
	"NO_RESOURCE": "The selected item is not available to place.",
	"INVENTORY_FULL": "Inventory is full; the block was not removed.",
	"STALE_REVISION": "The world changed before that edit; try again.",
	"PROTECTED": "The bottom bedrock layer is protected.",
	"NO_TARGET": "No editable block is targeted.",
	"DRAG_PLACED": "Blocks placed.",
	"LINE_PLACED": "Pieces laid in a line.",
	"COASTER_PLACED": "Coaster track laid.",
	"LOOP_PLACED": "Loop built. Rails join its entry (behind) and its exit (ahead, one lane right).",
	"LOOP_BLOCKED": "The loop does not fit here: a red cell is in the way (ground, tree, hill or block). Move, turn (W / R) or resize (4-9).",
	"CLIMB_PLACED": "Climb built. Rails join its entry (behind) and its landing (ahead, at the top).",
	"CLIMB_BLOCKED": "The climb does not fit here: a red cell is in the way (ground, tree, hill or block). Move, turn (W / R), or hold Shift and aim past the obstacle.",
	"BEND_PLACED": "Lane switcher laid: the track shifts to its new lane. Rails join its entry (behind) and its exit (ahead, on the new lane).",
	"BEND_BLOCKED": "The lane switcher does not fit here: a red cell is in the way. Move, turn (W / R) or resize (Shift-aim, X / C, 4-9).",
	"CROSS_PLACED": "Crossing laid: two tracks swap lanes through the middle. Rails join both entries (behind) and both exits (ahead).",
	"CROSS_BLOCKED": "The crossing does not fit here: a red cell is in the way. Move, turn (W / R) or resize (Shift-aim, X / C, 4-9).",
	"CURVE_PLACED": "Curve laid. Rails join its entry (behind) and its exit (ahead in the new direction); a 45 or 135 curve ends on a diagonal that only another curve continues.",
	"CURVE_BLOCKED": "The curve does not fit here: a red cell is in the way (ground, tree, hill or block). Move, turn (W / R) or resize (4-9, Shift-aim).",
	"TRACK_SNAPPED": "Snapped to the track end — release to join.",
	"RAILS_SHAPED_ELBOW": "Rails laid. Rails shaped into an elbow.",
	"RAILS_SHAPED_LANE_SHIFT": "Rails laid. Rails shaped into a lane shift.",
	"COASTER_BOARDED": "Boarded the coaster car — 1-9 sets the speed, Shift or Escape leaves.",
	"COASTER_LEFT": "Left the coaster car.",
	"ALREADY_RIDING": "Already riding.",
	"BLUEPRINT_STAMPED": "Blueprint built.",
	"UNKNOWN_BLUEPRINT": "That blueprint is not in the catalogue.",
	"DRAG_CANCELLED": "Build cancelled; nothing was placed.",
	"DRAG_EMPTY": "No valid cells to build; nothing was placed.",
	"INSUFFICIENT_BLOCKS": "Not enough blocks carried for that build.",
	"MISSING_CONTENT": "That content definition is unavailable.",
	"NOT_PLACEABLE": "The selected hotbar item cannot be placed.",
	"NO_STATION": "Aim at a workbench or furnace, then interact.",
	"SECONDARY_REQUIRED": "Use right click to open this station.",
	"OPEN_STATION": "Workstation opened.",
	"GATE_OPENED": "Gate open — the leaf is drawn back and the way through is clear.",
	"GATE_CLOSED": "Gate shut — the wall is whole again.",
	"NOT_A_GATE": "That is not a gate.",
	"WRONG_WORKSTATION": "That recipe needs a different workstation.",
	"INSUFFICIENT_INPUT": "Missing recipe materials.",
	"STATION_BUSY": "That furnace is already working.",
	"STATION_NOT_EMPTY": "Remove the Furnace input, fuel and output before dismantling it.",
	"SUPPORT_IN_USE": "Dismantle the supported placed object before removing this block.",
	"JOB_STARTED": "Furnace started; one ore and one stored fuel operation were consumed.",
	"JOB_COMPLETED": "Furnace finished; collect the retained output from its Output slot.",
	"DEFENSE_ALREADY_ACTIVE": "A defense drill is already active.",
	"DEFENSE_ARENA_BLOCKED": "No clear practice lane is available near home. Move or dismantle nearby builds, then try again.",
	"CORE_ARENA_BLOCKED": "No clear core-defense lane is available near home. Move or dismantle nearby builds, then try again.",
	"MISSING_REPAIR_MATERIAL": "Repair requires one Planks item in carried inventory or the hotbar.",
	"NO_REPAIR_NEEDED": "That barricade is already at full integrity.",
	"REPAIRED": "Barricade repaired; one Planks item was consumed.",
	"INVALID_MOUNT": "That siege device needs fully supported ground or its allowed tower socket.",
	"MELEE_COOLDOWN": "The sword is between swings; release and strike again.",
	"SWORD_MISS": "The sword swing did not reach a raider.",
	"RAIDER_DAMAGED": "Sword strike landed.",
	"RAIDER_DEFEATED": "Raider defeated — the core is safe.",
	# Industry wave 1 (docs/INDUSTRY.md): the miner's right-click status line
	# is "Miner: N ore mined, <status>." plus one of these hints.
	"MINER_NO_BIN_HINT": "Place an Ore Bin in a cell beside the miner.",
	"MINER_BIN_FULL_HINT": "Empty the Ore Bin (right-click it) or let a mine cart collect from it.",
	"MINER_NO_ORE_HINT": "No ore within 3 cells; move the miner next to iron, gold or coal ore.",
}

const STARTER_IRON_MARKER := Vector3(-6.5, 0.0, 36.5)
## Defence sets (docs/DEFENSE_SETS.md): the gate's sliding leaf and how far it
## travels - one cell, straight into the frame's jamb.
const GATE_LEAF_NODE := "GateLeaf"
const GATE_LEAF_OPEN_X := -0.98

## CoasterCraft (docs/COASTERCRAFT_MODE.md), set by the app before
## initialize(): no enemy core, no enemy-base compass, no starter markers on
## the plate, no drill line; the navigation line names the mode.
var coastercraft := false
## Development Expo (docs/DEVELOPMENT_EXPO.md), set by the app before
## initialize(): the owner's development world. No ambient enemy pressure
## (combat only through an explicit Expo control), no enemy core placed by
## wandering, no enemy-base compass, no drill line. Everything else - the
## clock, machines, saving, the live-menu contract, item costs - is the
## ordinary game.
var development := false
## Stations dropped by the last restore (each {reason, entity_id,
## instance_id}); diagnostics and the load report read it.
var restore_skipped: Array[Dictionary] = []
## Development Expo: the canonical fixture version the world was built from
## (DevelopmentMode.EXPO_FIXTURE_VERSION), saved with the game.
var expo_fixture_version := 0

var world: WorldAdapter
var player: PlayerController
var registry: ContentRegistry
var inventory: F0Inventory
var crafting: CraftingService
var workstations: WorkstationService
## Industry wave 1 (docs/INDUSTRY.md): foundries smelting from warehouses.
var foundry: FoundryService
var interaction: InteractionService
var clock: DayNightClock
var defense: DefenseService
var core_defense: CoreDefenseService
var siege_defense: SiegeDefenseService
## Coaster rails side project: present only while a mine cart is placed.
var coaster_carts: CoasterCartService
## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): the ride state and
## camera; hero_armored mirrors the pause-menu toggle (settings.cfg).
var coaster_ride: CoasterRide
var hero_armored := false
## Track auto-clear (CoasterCraft card 6): mirrors the pause-menu toggle
## into InteractionService.auto_clear.
var track_auto_clear := false
var _cleared_for_track := 0
## Lanes the last Rail Switch shifted (its BEND_PLACED report names them).
var _bend_lanes_laid := 0
var open_data: Dictionary
var world_ready := false
var saving := false
var simulation_paused := true
## A UI menu (inventory, hand build, a station panel) is open: the body stands
## still and the pointer belongs to the UI, but the world keeps running - only
## the pause menu (simulation_paused) and saving stop it (owner 2026-09-22).
var menu_open := false
var _pending_workstation_snapshot: Dictionary = {}
var _station_visuals: Dictionary = {}
var _station_visual_materials: Dictionary = {}
var _placement_preview: Node3D
var _placement_preview_key := ""
## Snap to a track end: the end last announced ("Snapped to the track end"),
## so the line shows once per snap.
var _snap_announced := ""
## Hauling (docs/INDUSTRY.md): the HUD reports a cart docking within
## HAUL_NOTICE_RANGE m of the player, one line per second at most.
const HAUL_NOTICE_RANGE := 12.0
var _haul_notice_msec := -100000
var _held_item_view: HeldItemView
var fire_service: FireService
## Industry wave 1 (docs/INDUSTRY.md): miners fill ore bins.
var miner_service: MinerService
## Miner visuals: instance id -> the "Drill" node spun while the miner works.
var _miner_drills: Dictionary = {}
## Set by the app before initialize(): Settings > Graphics terrain view distance.
var settings_view_distance := 0
## Set by the app before initialize(): the Development Expo's canonical world
## bounds ({"min": Vector3i, "size": Vector3i}); {} keeps world.json's.
var world_bounds_override: Dictionary = {}
var _resource_markers: Node3D
var _environment: Environment
var _sun: DirectionalLight3D
var _sun_visual: MeshInstance3D
var _last_visual_minute := -1
var _navigation_elapsed := 0.0
var _melee_cooldown := 0.0


func initialize(session_data: Dictionary) -> Dictionary:
	open_data = session_data
	var snapshot: Dictionary = session_data.get("snapshot", {})
	registry = ContentRegistry.new()
	if not registry.load_error.is_empty():
		return {"ok": false, "reason": registry.load_error}
	inventory = F0Inventory.new(registry)
	var inventory_snapshot: Dictionary = snapshot.get("inventory", {"dirt": 0, "revision": 0})
	if not inventory.restore(inventory_snapshot):
		return {"ok": false, "reason": "INVALID_INVENTORY_SNAPSHOT"}
	var grant: Variant = inventory_snapshot.get("grant", {})
	if grant is Dictionary and not grant.is_empty():
		inventory.try_transaction({}, grant)
	crafting = CraftingService.new(registry, inventory)
	workstations = WorkstationService.new(registry, inventory)
	foundry = FoundryService.new(workstations, registry)
	foundry.foundry_changed.connect(_on_foundry_changed)
	_pending_workstation_snapshot = snapshot.get("workstations", {})
	clock = DayNightClock.new()
	if not clock.load_error.is_empty():
		return {"ok": false, "reason": clock.load_error}
	if not clock.restore(snapshot.get("clock", {})):
		return {"ok": false, "reason": "INVALID_CLOCK_SNAPSHOT"}

	var world_environment := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.environment = _environment
	add_child(world_environment)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_max_distance = 48.0
	_sun.directional_shadow_fade_start = 0.9
	_sun.shadow_bias = 0.08
	_sun.shadow_normal_bias = 1.0
	_sun.shadow_blur = 1.15
	add_child(_sun)
	_create_sun_visual()
	clock.apply_visuals(_environment, _sun)
	_update_sun_visual()

	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.set_hero_armored(hero_armored)
	coaster_ride = CoasterRide.new()
	coaster_ride.name = "CoasterRide"
	add_child(coaster_ride)
	coaster_ride.initialize(player)
	coaster_ride.set_armored(hero_armored)
	_held_item_view = HeldItemView.new(registry)
	_held_item_view.name = "HeldItemView"
	player.camera.add_child(_held_item_view)
	if not player.restore(snapshot.get("player", {})):
		return {"ok": false, "reason": "INVALID_PLAYER_SNAPSHOT"}
	var viewer := VoxelViewer.new()
	viewer.name = "VoxelViewer"
	viewer.view_distance = 48
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	player.add_child(viewer)

	world = WorldAdapter.new()
	world.name = "World"
	add_child(world)
	var world_result := world.initialize(session_data.working_database, player.position, snapshot.get("world", {}), world_bounds_override)
	if not world_result.get("ok", false):
		return world_result
	world.revision = int(snapshot.get("world", {}).get("revision", 0))
	defense = DefenseService.new()
	defense.name = "DefenseService"
	add_child(defense)
	defense.initialize(world, inventory, registry, workstations, snapshot.get("defense", {}))
	core_defense = CoreDefenseService.new()
	core_defense.name = "CoreDefenseService"
	add_child(core_defense)
	core_defense.initialize(world, registry, workstations, snapshot.get("core_defense", {}))
	core_defense.player = player
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)
	fire_service = FireService.new()
	fire_service.name = "FireService"
	add_child(fire_service)
	fire_service.initialize(world, workstations, _fire_damage_at, int(open_data.get("snapshot", {}).get("world", {}).get("seed", 41026)))
	fire_service.feedback.connect(_on_interaction_feedback)
	siege_defense = SiegeDefenseService.new()
	siege_defense.name = "SiegeDefenseService"
	add_child(siege_defense)
	siege_defense.initialize(workstations, core_defense, fire_service, world)
	siege_defense.feedback.connect(_on_interaction_feedback)
	siege_defense.storage_reloaded.connect(_on_storage_reloaded)
	siege_defense.state_changed.connect(_on_defense_state_changed)
	miner_service = MinerService.new()
	miner_service.name = "MinerService"
	add_child(miner_service)
	miner_service.initialize(world, workstations, registry)
	interaction = InteractionService.new(world, inventory, player.get_body_aabb, registry, workstations, _raycast_station, _defense_interact)
	interaction.restore_stamps(open_data.get("snapshot", {}).get("blueprints", {}).get("stamps", []))
	_restore_drops(open_data.get("snapshot", {}).get("drops", []))
	interaction.auto_clear = track_auto_clear
	interaction.rider_cells = _rider_cells
	player.interaction = interaction
	player.primary_action = _player_primary_action
	world.spawn_area_ready.connect(_on_spawn_area_ready)
	if settings_view_distance > 0:
		world.set_view_distance(settings_view_distance)
	world.attach_viewer(player.camera)
	world.status_changed.connect(status_changed.emit)
	inventory.changed.connect(_on_inventory_changed)
	interaction.result_reported.connect(_on_interaction_result)
	workstations.station_changed.connect(_on_station_changed)
	workstations.job_completed.connect(_on_job_completed)
	defense.state_changed.connect(_on_defense_state_changed)
	defense.feedback.connect(_on_interaction_feedback)
	core_defense.state_changed.connect(_on_defense_state_changed)
	core_defense.feedback.connect(_on_interaction_feedback)
	player.interaction_feedback.connect(_on_interaction_feedback)
	player.boundary_feedback.connect(_on_boundary_feedback)
	player.deactivate()
	_on_inventory_changed(inventory.snapshot())
	set_process(true)
	return {"ok": true}


func _process(delta: float) -> void:
	if _held_item_view != null:
		_held_item_view.set_gameplay_visible(world_ready and not simulation_paused and not saving and not menu_open and not player.third_person and not is_riding())
	_update_placement_preview()
	if defense != null:
		defense.advance(delta, simulation_paused or saving)
	if core_defense != null:
		core_defense.advance(delta, simulation_paused or saving)
	if siege_defense != null:
		siege_defense.advance(delta, simulation_paused or saving)
	if coaster_carts != null:
		coaster_carts.advance(delta, simulation_paused or saving)
	if coaster_ride != null:
		coaster_ride.advance(delta)
	if fire_service != null:
		fire_service.advance(delta, simulation_paused or saving)
	if miner_service != null:
		miner_service.advance(delta, simulation_paused or saving or not world_ready)
		_spin_miner_drills(delta)
	if not simulation_paused and not saving and world_ready:
		_advance_drops(delta)
	if not simulation_paused:
		_melee_cooldown = maxf(0.0, _melee_cooldown - delta)
		if player != null and world_ready:
			player.advance_health(delta)
	if workstations != null and not saving:
		workstations.advance(delta, simulation_paused)
		_ensure_enemy_core(delta)
	if foundry != null and not saving and world_ready:
		foundry.advance(delta, simulation_paused)
	if clock != null and not saving:
		var clock_advanced := clock.advance(delta, simulation_paused)
		_update_sun_visual()
		if clock_advanced:
			var visual_minute := (clock.day_index - 1) * DayNightClock.MINUTES_PER_DAY + clock.current_minutes()
			if visual_minute != _last_visual_minute:
				_last_visual_minute = visual_minute
				clock.apply_visuals(_environment, _sun)
				_emit_hud()
	if world_ready and not simulation_paused:
		_navigation_elapsed += delta
		if _navigation_elapsed >= 0.25:
			_navigation_elapsed = 0.0
			_emit_navigation()


func apply_input_settings(settings_store: SettingsStore) -> void:
	if player != null:
		player.configure_input(settings_store.mouse_sensitivity, settings_store.invert_y)


func apply_world_settings(time_hhmm: String, cycle_enabled: bool) -> Dictionary:
	if clock == null:
		return {"ok": false, "reason": "NO_ACTIVE_WORLD"}
	var time_result := clock.set_time_hhmm(time_hhmm)
	if not time_result.get("ok", false):
		return time_result
	clock.set_cycle_enabled(cycle_enabled)
	clock.apply_visuals(_environment, _sun)
	_update_sun_visual()
	_last_visual_minute = (clock.day_index - 1) * DayNightClock.MINUTES_PER_DAY + clock.current_minutes()
	_emit_hud()
	return {
		"ok": true,
		"reason": "OK",
		"time": clock.time_input_text(),
		"time_label": clock.time_label(),
		"period": clock.period_label(),
		"cycle_enabled": clock.cycle_enabled,
	}


func inventory_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for item_id: String in registry.items:
		var amount := inventory.count(item_id)
		if amount > 0:
			lines.append("%s  × %d" % [registry.display_name(item_id), amount])
	return "Inventory empty" if lines.is_empty() else "\n".join(lines)


func inventory_snapshot() -> Dictionary:
	return inventory.snapshot()


func recipes_for(station_type: String) -> Array[Dictionary]:
	return registry.recipes_for(station_type)


func recipe_status(recipe_id: String, station_type: String, station_id: String = "") -> Dictionary:
	var recipe := registry.recipe(recipe_id)
	if recipe.is_empty() or str(recipe.get("station", "")) != station_type:
		return {"ok": false, "reason": "WRONG_WORKSTATION"}
	if station_type != "hand":
		var station_record := workstations.station(station_id)
		if station_record.is_empty() or str(station_record.get("entity_id", "")) != station_type:
			return {"ok": false, "reason": "WRONG_WORKSTATION"}
	if station_type == "furnace":
		return workstations.furnace_recipe_availability(station_id, recipe_id)
	return crafting.check_recipe(recipe_id, station_type)


func try_craft(recipe_id: String, station_type: String, station_id: String = "", batches: int = 1) -> Dictionary:
	if station_type == "furnace" and batches != 1:
		return {"ok": false, "reason": "TIMED_RECIPE_BATCH_UNAVAILABLE"}
	if station_type == "furnace":
		var furnace_result := workstations.try_start_furnace(station_id, recipe_id)
		_on_interaction_feedback(str(furnace_result.get("reason", "CRAFT_FAILED")))
		return furnace_result
	var checked := recipe_status(recipe_id, station_type, station_id)
	if batches > 1 and station_type != "furnace":
		checked = crafting.check_recipe(recipe_id, station_type, batches)
	if not checked.get("ok", false):
		_on_interaction_feedback(str(checked.get("reason", "CRAFT_FAILED")))
		return checked
	var result := crafting.try_craft_many(recipe_id, station_type, batches)
	_on_interaction_feedback(str(result.get("reason", "CRAFT_FAILED")))
	return result


func load_furnace_recipe(station_id: String, recipe_id: String) -> Dictionary:
	return workstations.try_load_furnace_recipe(station_id, recipe_id)


func transfer_inventory_stack_to_furnace(station_id: String, inventory_index: int) -> Dictionary:
	return workstations.try_transfer_inventory_stack_to_furnace(station_id, inventory_index)


func collect_furnace_stack(station_id: String, slot_name: String) -> Dictionary:
	return workstations.try_collect_furnace_stack(station_id, slot_name)


func start_defense_drill() -> Dictionary:
	if defense == null or not world_ready:
		return {"ok": false, "reason": "WORLD_NOT_READY"}
	if core_defense != null and core_defense.is_active():
		return {"ok": false, "reason": "DEFENSE_ALREADY_ACTIVE"}
	if core_defense != null:
		core_defense.clear_for_other_mode()
	var result := defense.start_drill()
	if not result.get("ok", false):
		_on_interaction_feedback(str(result.get("reason", "DEFENSE_START_FAILED")))
	return result


## `options` (P4D): {"raiders": n, "brutes": b, "spawn_distance": cells}.
func start_core_defense_prototype(options: Dictionary = {}) -> Dictionary:
	if core_defense == null or not world_ready:
		return {"ok": false, "reason": "WORLD_NOT_READY"}
	if defense != null and defense.is_active():
		return {"ok": false, "reason": "DEFENSE_ALREADY_ACTIVE"}
	if defense != null:
		defense.clear_for_other_mode()
	var result := core_defense.start_prototype(options)
	if not result.get("ok", false):
		_on_interaction_feedback(str(result.get("reason", "DEFENSE_START_FAILED")))
	return result


func select_hotbar(index: int) -> Dictionary:
	var result := inventory.select_hotbar(index)
	if result.get("ok", false):
		var item_id := str(result.get("item_id", ""))
		_on_interaction_feedback("Selected slot %d%s" % [index + 1, " — " + registry.display_name(item_id) if not item_id.is_empty() else " — empty"])
		# Coaster pieces carry their controls on screen (owner could not find
		# the loop gesture without them).
		if item_id == CoasterRails.LOOP:
			_on_interaction_feedback("RAIL LOOP: aim at the ground where the entry goes, HOLD Right Mouse — the loop ghost appears; hold Shift and aim further away to size it (or 4-9 / X / C), W / R turn it, L classic loop; let go to build it (red = does not fit) — it heads the way you face; U / Ctrl+Z undoes")
		elif item_id == CoasterRails.FLAT:
			_on_interaction_feedback("RAIL: right-drag lays a line; rails shape themselves — two straights meeting at a corner become an elbow, three rails then three one lane over become a lane shift (no extra piece); U / Ctrl+Z undoes")
		elif item_id == CoasterRails.SLOPE:
			_on_interaction_feedback("RAIL SLOPE: the arrow end climbs one block — W / R turns it; put a Rail on the block it climbs to")
		elif item_id == CoasterRails.CLIMB:
			_on_interaction_feedback("CLIMB: aim at the ground where the climb starts, HOLD Right Mouse — the whole climb ghosts (slope-in, grade, slope-out); hold Shift and aim where it should land (a hilltop, or below for a descent) to set its length and rise (or 4-9 / X / C for the rise), W / R turn it; let go to build it (red = does not fit) — it heads the way you face; U / Ctrl+Z undoes")
		elif interaction != null and interaction.is_smooth_bend_item(item_id):
			_on_interaction_feedback("RAIL SWITCH: aim where the entry goes, HOLD Right Mouse — the smooth S-bend ghost appears (4 long, one lane right); hold Shift and aim where the exit goes (forward = length, sideways = lanes, left or right), or 4-9 / X / C for the length; W / R turn it; let go to lay it (one item per piece, red = does not fit) — it heads the way you face; U / Ctrl+Z undoes")
		elif interaction != null and interaction.is_rail_cross_item(item_id):
			_on_interaction_feedback("CROSSING: aim where the first entry goes, HOLD Right Mouse — two S-bends that swap lanes appear; hold Shift and aim where the first exit goes (forward = length, sideways = lanes), or 4-9 / X / C for the length; W / R turn it; let go to lay it (one item per piece, red = does not fit) — it heads the way you face; U / Ctrl+Z undoes")
		elif item_id == "foundry":
			_on_interaction_feedback("FOUNDRY: place it touching a Warehouse (2 x 1, W / R turn it); right-click it to pick the ingot it smelts - it takes ore + Coal from the Warehouse every 10 s and puts the ingot back")
		elif item_id == "warehouse":
			_on_interaction_feedback("WAREHOUSE: 2 x 2 store with 27 slots; right-click it to store ore and Coal (or take ingots) - a Foundry touching it smelts on its own")
		elif item_id == "rail_curve":
			_on_interaction_feedback("CURVE: aim at the ground where the entry goes, HOLD Right Mouse — the curve ghost appears (90°, radius 4, bending right); hold Shift and aim where it should go: ahead-right = 45°, right = 90°, behind-right = 135°, behind = U-turn, aim LEFT to bend left, further = wider (or 4-9 / X / C); W / R turn the entry; let go to build it (red = does not fit); one Curve per piece — it heads the way you face; U / Ctrl+Z undoes")
	return result


## P4G: the red enemy core stands on the enemy base clearing. It is placed
## through the ordinary station path the first time the base's cells are
## loaded (the player wandered there), on a stone slab levelled for it.
var _enemy_core_timer := 0.0
func _ensure_enemy_core(delta: float) -> void:
	if coastercraft or development or not world_ready or simulation_paused or registry.entity("enemy_core").is_empty():
		return
	_enemy_core_timer -= delta
	if _enemy_core_timer > 0.0:
		return
	_enemy_core_timer = 2.0
	for record: Dictionary in workstations.stations.values():
		if str(record.get("entity_id", "")) == "enemy_core":
			return
	if not world.terrain.generator is P1TerrainGenerator:
		return
	var base: Vector3i = world.terrain.generator.enemy_base_cell()
	var anchor := base - Vector3i(1, 0, 1)
	for x in range(3):
		for z in range(3):
			var cell := anchor + Vector3i(x, 0, z)
			if str(world.query_cell(cell).get("state", "")) != "LOADED" or str(world.query_cell(cell + Vector3i.DOWN).get("state", "")) != "LOADED":
				return
	# Level a stone slab under the footprint and clear its column.
	for x in range(3):
		for z in range(3):
			var cell := anchor + Vector3i(x, 0, z)
			world.set_cell(cell + Vector3i.DOWN, WorldAdapter.BLOCK_NAMES.find("castle_stone"))
			for y in range(5):
				world.set_cell(cell + Vector3i(0, y, 0), 0)
	inventory.try_transaction({}, {"enemy_core": 1})
	var placed := workstations.try_place("enemy_core", anchor, world.query_cell, AABB(), 0)
	if not placed.get("ok", false):
		inventory.try_transaction({"enemy_core": 1}, {})
		_enemy_core_timer = 10.0
		return
	_on_interaction_feedback("The enemy Core of Power stands here. Their raids come from this base.")


func _on_spawn_area_ready() -> void:
	if world_ready:
		return
	restore_skipped.clear()
	if not _pending_workstation_snapshot.is_empty():
		var restored := workstations.restore(_pending_workstation_snapshot, world.query_cell)
		if not restored.get("ok", false):
			# Only a snapshot that cannot be read at all lands here (single
			# records are dropped, not fatal): report it and leave the loading
			# screen instead of spinning forever.
			status_changed.emit("Station restore failed: %s" % restored.get("reason", "UNKNOWN"))
			load_failed.emit(str(restored.get("reason", "INVALID_STATION_SNAPSHOT")))
			return
		var skipped: Array = restored.get("details", {}).get("skipped", [])
		for entry in skipped:
			if entry is Dictionary:
				restore_skipped.append(entry)
		if not restore_skipped.is_empty():
			print("STATION_RESTORE_SKIPPED %s" % JSON.stringify(restore_skipped))
		for record: Dictionary in workstations.stations.values():
			_spawn_station_visual(record)
	var defense_restore := defense.restore_after_world_ready()
	if not defense_restore.get("ok", false):
		# A broken drill record must never brick a save (as for the core
		# drill below): drop the drill and go on.
		defense.clear_for_other_mode()
		_on_interaction_feedback("The saved barricade drill could not be restored (%s); it was cleared." % str(defense_restore.get("reason", "UNKNOWN")))
	var core_restore := core_defense.restore_after_world_ready()
	if not core_restore.get("ok", false):
		# A broken drill record must never brick a save: drop the drill and go on.
		core_defense.clear_for_other_mode()
		_on_interaction_feedback("The saved defense drill could not be restored (%s); it was cleared." % str(core_restore.get("reason", "UNKNOWN")))
	world_ready = true
	if not coastercraft and not development:
		_spawn_starter_resource_markers()
	simulation_paused = false
	player.activate(not DisplayServer.get_name().contains("headless"))
	status_changed.emit("Ready — Tab inventory, B hand crafting, right-click stations, W/R rotate castle previews")
	_emit_navigation()
	ready_for_play.emit()


func freeze_for_save() -> void:
	saving = true
	if player != null:
		player.deactivate()


func recover_from_failed_save() -> void:
	if world != null:
		world.resume_streaming_after_failed_save()
	saving = false
	simulation_paused = true
	if player != null:
		player.deactivate()


func pause_game(paused: bool) -> void:
	if player == null or saving:
		return
	if paused:
		simulation_paused = true
		player.deactivate()
	else:
		simulation_paused = false
		_release_player()


## A menu (Tab inventory, B hand build, any station panel) opened or closed:
## the body freezes and the pointer is freed, the simulation keeps running -
## machines finish, raiders keep coming, the clock ticks. Compare pause_game.
func set_menu_open(open: bool) -> void:
	if player == null or saving:
		return
	menu_open = open
	if open:
		player.deactivate()
		_hide_placement_preview()
	elif not simulation_paused:
		_release_player()


func _release_player() -> void:
	if is_riding():
		# The rider stays seated: the body stays parked, only the pointer returns.
		if not DisplayServer.get_name().contains("headless"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		player.activate(not DisplayServer.get_name().contains("headless"))


# --- Coaster car and hero (docs/COASTER_CAR_AND_HERO.md). ---------------------


func is_riding() -> bool:
	return coaster_ride != null and coaster_ride.is_riding()


## Shift on a parked coaster car: seat the player and start the ride.
func board_coaster_car(instance_id: String) -> Dictionary:
	if coaster_ride == null or coaster_carts == null or not world_ready:
		return {"ok": false, "reason": "NO_CAR"}
	var body: Node3D = _station_visuals.get(instance_id)
	var result := coaster_ride.board(instance_id, body, coaster_carts, not DisplayServer.get_name().contains("headless"))
	if result.get("ok", false):
		_boarded_frame = Engine.get_process_frames()
		_hide_placement_preview()
		_emit_hud()
	return result


## Frame of the last boarding: the Shift press that boarded also reaches this
## node's _unhandled_input, which must not read it as "leave" (owner playtest
## 2026-09-20: "I get in and out simultaneously").
var _boarded_frame := -1


## Shift or Escape while riding: park the car, stand beside it.
func leave_coaster_car() -> Dictionary:
	if not is_riding():
		return {"ok": false, "reason": "NOT_RIDING"}
	var result := coaster_ride.leave(not simulation_paused and not saving, not DisplayServer.get_name().contains("headless"))
	_emit_hud()
	return result


## Number keys while riding: 1..9 cells per second.
func set_ride_speed(level: int) -> Dictionary:
	if not is_riding():
		return {"ok": false, "reason": "NOT_RIDING"}
	var result := coaster_ride.set_speed_level(level)
	_emit_hud()
	_on_interaction_feedback("Coaster speed %d / %d" % [coaster_ride.speed_level, CoasterRide.MAX_SPEED_LEVEL])
	return result


## V on foot: first person <-> chase camera with the hero model visible.
func toggle_third_person() -> bool:
	if player == null or is_riding():
		return player != null and player.third_person
	player.set_third_person(not player.third_person)
	_on_interaction_feedback("Third person: %s (V toggles)" % ("on" if player.third_person else "off"))
	return player.third_person


## Pause-menu "Hero: Armour on/off" (persisted by the app in settings.cfg).
func set_hero_armored(armored: bool) -> void:
	hero_armored = armored
	if player != null:
		player.set_hero_armored(armored)
	if coaster_ride != null:
		coaster_ride.set_armored(armored)


## Sets the world clock to "HH:MM" and repaints sky, sun and light for it.
## Development Start uses it once on a fresh Expo so the world opens in
## readable daylight; the cycle keeps running from there.
func set_clock_time(value: String) -> Dictionary:
	if clock == null:
		return {"ok": false, "reason": "NO_CLOCK"}
	var result := clock.set_time_hhmm(value)
	if result.get("ok", false):
		clock.apply_visuals(_environment, _sun)
		_update_sun_visual()
	return result


## Pause-menu "Track auto-clear on/off" (persisted by the app in settings.cfg).
func set_track_auto_clear(enabled: bool) -> void:
	track_auto_clear = enabled
	if interaction != null:
		interaction.auto_clear = enabled


func snapshot() -> Dictionary:
	var saved := {
		"schema_version": SaveCoordinator.SAVE_SCHEMA,
		"content_version": SaveCoordinator.CONTENT_VERSION,
		"mode": "coastercraft" if coastercraft else ("development" if development else "game"),
		"world": world.snapshot(),
		"inventory": inventory.snapshot(),
		"workstations": workstations.snapshot(),
		"defense": defense.snapshot(),
		"core_defense": core_defense.snapshot(),
		"blueprints": {"stamps": interaction.stamps_snapshot()} if interaction != null else {"stamps": []},
		"clock": clock.snapshot(),
		"drops": drops_snapshot(),
		"player": _player_snapshot(),
		"session_id": open_data.get("session_id", ""),
	}
	if development:
		# Development Expo: the mode and the canonical fixture the world was
		# built from, so a later session can spot an outdated Expo.
		saved["expo"] = {"fixture_version": expo_fixture_version}
	return saved


## The saved game in `snapshot` is over: the Core of Power the player
## defended is gone and no core stands in the world. The main menu reads this
## from the checkpoint before it offers Continue (docs/DEVELOPMENT_EXPO.md);
## nothing here ever writes to the save or re-creates a core.
static func game_over_report(snapshot_data: Dictionary) -> Dictionary:
	var core_present := false
	var instance_ids: Dictionary = {}
	var stations: Variant = snapshot_data.get("workstations", {}).get("stations", [])
	if stations is Array:
		for value in stations:
			if not value is Dictionary:
				continue
			instance_ids[str(value.get("instance_id", ""))] = true
			if str(value.get("entity_id", "")) == "core_of_power":
				core_present = true
	var core_defense_data: Variant = snapshot_data.get("core_defense", {})
	var state := ""
	var defended_id := ""
	if core_defense_data is Dictionary:
		state = str(core_defense_data.get("state", CoreDefenseService.IDLE))
		defended_id = str(core_defense_data.get("core_station_id", ""))
	var defended_missing: bool = not defended_id.is_empty() and not instance_ids.has(defended_id)
	var over: bool = not core_present and (state == CoreDefenseService.FAILED or defended_missing)
	return {"game_over": over, "reason": "CORE_DESTROYED" if over else "", "core_present": core_present, "core_defense_state": state, "defended_core_missing": defended_missing}


## While riding the saved player stands beside the car (the ride itself is
## not persisted: on load the player is on foot and the car is parked).
func _player_snapshot() -> Dictionary:
	var data := player.snapshot()
	if is_riding():
		var landing := coaster_ride.dismount_position()
		data["position"] = [landing.x, landing.y, landing.z]
	return data


func _on_inventory_changed(data: Dictionary) -> void:
	if _held_item_view != null:
		_held_item_view.present(inventory.active_item_id())
	_emit_hud()
	inventory_changed.emit(data)


func _emit_hud() -> void:
	if inventory == null or registry == null or clock == null:
		return
	var selected := inventory.active_item_id()
	var selected_text := "Empty" if selected.is_empty() else registry.display_name(selected)
	var cycle_text := "" if clock.cycle_enabled else " · cycle paused"
	var health_text := "HP %d/%d   |   " % [player.health, PlayerController.MAX_HEALTH] if player != null else ""
	if is_riding():
		hud_changed.emit("%s%s   |   %s · %s%s" % [health_text, coaster_ride.hud_text(), clock.period_label(), clock.time_label(), cycle_text])
		return
	if inventory.selected_hotbar < 0:
		hud_changed.emit("%sHands empty   |   %s · %s%s" % [health_text, clock.period_label(), clock.time_label(), cycle_text])
		return
	hud_changed.emit("%sSlot %d: %s   |   %s · %s%s" % [health_text, inventory.selected_hotbar + 1, selected_text, clock.period_label(), clock.time_label(), cycle_text])


func _on_player_health_changed(_health: int, _max_health: int) -> void:
	_emit_hud()


## Death: back to the core (or home) with full health after a short pause.
func _on_player_died() -> void:
	if is_riding():
		leave_coaster_car()
	_on_interaction_feedback("You fell. You wake at your core.")
	var respawn := WorldAdapter.SPAWN_FEET
	for record: Dictionary in workstations.stations.values():
		if str(record.get("entity_id", "")) == "core_of_power":
			var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
			respawn = Vector3(anchor) + Vector3(1.5, 1.0, -1.0)
	player.global_position = respawn
	player.velocity = Vector3.ZERO
	player.restore_health()
	player_died.emit()


func _emit_navigation() -> void:
	if player == null:
		return
	var offset := Vector2(WorldAdapter.SPAWN_FEET.x - player.global_position.x, WorldAdapter.SPAWN_FEET.z - player.global_position.z)
	var distance := offset.length()
	if coastercraft:
		var mode_directions: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
		var mode_direction: String = mode_directions[posmod(roundi(atan2(offset.x, -offset.y) / (PI / 4.0)), 8)]
		navigation_changed.emit("COASTERCRAFT  ·  infinite stock  ·  Shift on a car to ride, 1-9 speed  ·  spawn %d m %s" % [roundi(distance), mode_direction])
		return
	if development:
		# The Expo names itself; the enemy-base bearing is hidden with it.
		var expo_directions: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
		var expo_direction: String = expo_directions[posmod(roundi(atan2(offset.x, -offset.y) / (PI / 4.0)), 8)]
		navigation_changed.emit("DEVELOPMENT EXPO  ·  plaza %d m %s" % [roundi(distance), expo_direction])
		return
	if distance <= 8.0:
		var iron_distance := Vector2(STARTER_IRON_MARKER.x - player.global_position.x, STARTER_IRON_MARKER.z - player.global_position.z).length()
		navigation_changed.emit("HOME CLEARING  ·  IRON MARKER %d m" % roundi(iron_distance))
		return
	var angle := atan2(offset.x, -offset.y)
	var directions := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var direction_index := posmod(roundi(angle / (PI / 4.0)), 8)
	navigation_changed.emit("HOME  %d m  %s%s" % [roundi(distance), directions[direction_index], _enemy_base_hint(directions)])


## "· ENEMY BASE 160 m NW" from the generator's seed-chosen base site.
func _enemy_base_hint(directions: Array) -> String:
	if coastercraft or development or world == null or world.terrain == null or not world.terrain.generator is P1TerrainGenerator:
		return ""
	var base: Vector3i = world.terrain.generator.enemy_base_cell()
	var offset := Vector2(float(base.x) + 0.5 - player.global_position.x, float(base.z) + 0.5 - player.global_position.z)
	var angle := atan2(offset.x, -offset.y)
	return "  ·  ENEMY BASE %d m %s" % [roundi(offset.length()), directions[posmod(roundi(angle / (PI / 4.0)), 8)]]


func _create_sun_visual() -> void:
	_sun_visual = MeshInstance3D.new()
	_sun_visual.name = "VisibleSun"
	var sphere := SphereMesh.new()
	sphere.radius = 6.0
	sphere.height = 12.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("fff2b0")
	material.emission_enabled = true
	material.emission = Color("ffd76a")
	material.emission_energy_multiplier = 2.2
	sphere.material = material
	_sun_visual.mesh = sphere
	_sun_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sun_visual)


func _update_sun_visual() -> void:
	if _sun_visual == null or player == null or clock == null:
		return
	_sun_visual.visible = clock.sun_is_visible()
	_sun_visual.global_position = player.global_position + clock.sun_direction() * 180.0


## Dropped items (owner 2026-09-21, "drop an item is needed, use Y"): Y
## drops one of the held item (Shift+Y the stack) a little ahead of the
## player, as a bobbing icon on the ground; walking within DROP_PICKUP_REACH
## picks it up (what fits in the pack). Drops are saved with the session.
const DROP_PICKUP_REACH := 1.3
const DROP_AHEAD := 1.2
const DROP_ICON_HEIGHT := 0.45
var _drops: Array[Dictionary] = []
var _drop_nodes: Dictionary = {}
var _next_drop := 1
var _drop_spin := 0.0


func drops_snapshot() -> Array:
	var out: Array = []
	for drop: Dictionary in _drops:
		out.append(drop.duplicate())
	return out


func _restore_drops(saved: Array) -> void:
	for entry in saved:
		if not (entry is Dictionary):
			continue
		var drop: Dictionary = entry
		var position: Variant = drop.get("position")
		if not (position is Array) or (position as Array).size() != 3 or str(drop.get("item_id", "")).is_empty():
			continue
		_add_drop(str(drop.item_id), int(drop.get("count", 1)), Vector3(float(position[0]), float(position[1]), float(position[2])))


func drop_held_item(whole_stack: bool = false) -> Dictionary:
	if is_riding():
		return {"ok": false, "reason": "RIDING"}
	var slot := inventory.selected_hotbar
	var item_id := inventory.active_item_id()
	if slot < 0 or item_id.is_empty():
		_on_interaction_feedback("Nothing in hand to drop.")
		return {"ok": false, "reason": "NOTHING_HELD"}
	var in_slot := int(inventory.slots[slot].get("count", 0))
	var amount := in_slot if whole_stack else 1
	var taken := inventory.take_from_slot(slot, amount)
	if not taken.get("ok", false):
		return taken
	var forward := -player.camera.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.05:
		forward = Vector3.FORWARD
	var target := player.global_position + forward.normalized() * DROP_AHEAD
	var landing := target
	var hit := world.raycast(target + Vector3.UP * 1.5, Vector3.DOWN, 6.0)
	if hit != null:
		landing = Vector3(target.x, float(hit.previous_position.y), target.z)
	var drop := _add_drop(item_id, amount, landing)
	_on_interaction_feedback("Dropped %d %s (walk over it to pick it up)." % [amount, registry.display_name(item_id)])
	_emit_hud()
	return {"ok": true, "reason": "DROPPED", "drop": drop}


func _add_drop(item_id: String, count: int, position: Vector3) -> Dictionary:
	var drop := {"id": "drop_%04d" % _next_drop, "item_id": item_id, "count": count, "position": [position.x, position.y, position.z]}
	_next_drop += 1
	_drops.append(drop)
	var node := Node3D.new()
	node.name = str(drop.id)
	node.position = position + Vector3.UP * (DROP_ICON_HEIGHT * 0.6)
	var texture := ItemIconCatalog.texture_for(item_id) if DisplayServer.get_name() != "headless" else null
	if texture != null:
		var sprite := Sprite3D.new()
		sprite.texture = texture
		sprite.pixel_size = DROP_ICON_HEIGHT / maxf(1.0, texture.get_size().y)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.shaded = false
		node.add_child(sprite)
	add_child(node)
	_drop_nodes[str(drop.id)] = node
	return drop


func _advance_drops(delta: float) -> void:
	if _drops.is_empty() or player == null:
		return
	_drop_spin += delta
	var feet := player.global_position
	var index := _drops.size() - 1
	while index >= 0:
		var drop: Dictionary = _drops[index]
		var node: Node3D = _drop_nodes.get(str(drop.id))
		var position: Array = drop.position
		var at := Vector3(float(position[0]), float(position[1]), float(position[2]))
		if node != null:
			node.position.y = at.y + DROP_ICON_HEIGHT * 0.6 + sin(_drop_spin * 2.0) * 0.05
		if not is_riding() and feet.distance_to(at) <= DROP_PICKUP_REACH:
			var item_id := str(drop.item_id)
			var count := int(drop.count)
			var fits := count
			while fits > 0 and not inventory.can_transaction({}, {item_id: fits}):
				fits -= 1
			if fits > 0 and inventory.try_transaction({}, {item_id: fits}).get("ok", false):
				if fits >= count:
					_drops.remove_at(index)
					_drop_nodes.erase(str(drop.id))
					if node != null:
						node.queue_free()
				else:
					drop.count = count - fits
				_on_interaction_feedback("Picked up %d %s." % [fits, registry.display_name(item_id)])
				_emit_hud()
		index -= 1


## Flight (owner 2026-09-23): a double tap of Right Shift within
## FLIGHT_DOUBLE_TAP_MSEC toggles it. Not while riding a coaster car.
const FLIGHT_DOUBLE_TAP_MSEC := 400
var _right_shift_msec := -FLIGHT_DOUBLE_TAP_MSEC


func toggle_flight() -> bool:
	if player == null or is_riding():
		return false
	var flying := not player.flying
	player.set_flying(flying)
	if flying:
		_on_interaction_feedback("Flight on - the keys follow your view, Space rises, Z drops, A is faster. Double-tap Right Shift to land.")
	else:
		_on_interaction_feedback("Flight off.")
	return flying


## U / Ctrl+Z: reverse the newest placement (InteractionService.undo_last).
func undo_last_placement() -> Dictionary:
	if interaction == null:
		return {"ok": false, "reason": "NO_SESSION"}
	if interaction.drag_active():
		_update_drag_preview(interaction.cancel_drag_place())
	var undone := interaction.undo_last()
	if not undone.get("ok", false):
		_on_interaction_feedback("Nothing to undo.")
		return undone
	var changes: Dictionary = undone.get("changes", {})
	var parts: Array[String] = []
	if int(changes.get("removed", 0)) > 0:
		parts.append("%d piece%s removed" % [int(changes.removed), "" if int(changes.removed) == 1 else "s"])
	if int(changes.get("restored", 0)) > 0:
		parts.append("%d block%s restored" % [int(changes.restored), "" if int(changes.restored) == 1 else "s"])
	var refunds: Dictionary = changes.get("refunds", {})
	for item_id: String in refunds:
		parts.append("%d %s back" % [int(refunds[item_id]), registry.display_name(item_id)])
	_on_interaction_feedback("Undone: %s (%d more to undo; U or Ctrl+Z)" % [", ".join(parts) if not parts.is_empty() else "nothing changed", int(changes.get("remaining", 0))])
	_emit_hud()
	return undone


## The track cells every cart and rail-riding kettle is on (the auto-shape
## pass never reshapes a rail under a rider).
func _rider_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if coaster_carts != null:
		cells.append_array(coaster_carts.rider_cells())
	if siege_defense != null:
		cells.append_array(siege_defense.rail_rider_cells())
	return cells


func _on_interaction_feedback(message: String) -> void:
	var friendly := str(REASON_TEXT.get(message, message if message.contains(" ") else message.replace("_", " ").capitalize()))
	if message == "BEND_PLACED" and _bend_lanes_laid != 0:
		# The Rail Switch's report names the shift it laid (owner 2026-09-20).
		friendly = "Lane switcher laid: the track shifts %d lane%s to the %s. Rails join its entry (behind) and its exit (ahead, on the new lane)." % [absi(_bend_lanes_laid), "" if absi(_bend_lanes_laid) == 1 else "s", "right" if _bend_lanes_laid > 0 else "left"]
		_bend_lanes_laid = 0
	if _cleared_for_track > 0:
		friendly += " Cleared %d blocks for the track." % _cleared_for_track
		_cleared_for_track = 0
	status_changed.emit(friendly)
	feedback_changed.emit(friendly)


func _on_boundary_feedback(message: String) -> void:
	status_changed.emit(message)
	feedback_changed.emit(message)


func _unhandled_input(event: InputEvent) -> void:
	if not world_ready or simulation_paused or saving or menu_open:
		return
	if is_riding():
		# Coaster car: the mouse turns the head in the seat, the number keys
		# set the speed (never the hotbar), the arrows pick an outside view
		# and Shift leaves; everything else is swallowed while seated.
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			coaster_ride.apply_mouse_look(event.relative)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var wanted := ""
			match event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode:
				KEY_UP:
					wanted = "back"
				KEY_DOWN:
					wanted = "front"
				KEY_LEFT:
					wanted = "left"
				KEY_RIGHT:
					wanted = "right"
			if not wanted.is_empty():
				var shown := coaster_ride.select_view(wanted)
				_on_interaction_feedback("Ride view: %s" % ("seat" if shown == CoasterRide.VIEW_SEAT else "from the " + shown))
				_emit_hud()
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("interact"):
			if Engine.get_process_frames() != _boarded_frame:
				_on_interaction_feedback(str(leave_coaster_car().get("reason", "NOT_RIDING")))
			get_viewport().set_input_as_handled()
			return
		for index in range(F0Inventory.HOTBAR_COUNT):
			if event.is_action_pressed("hotbar_%d" % (index + 1)):
				set_ride_speed(index + 1)
				get_viewport().set_input_as_handled()
				return
		return
	if interaction != null and interaction.drag_active() and not interaction.curve_tool_mode().is_empty():
		# Rail Switch / Crossing ghost: 4-9 set the length instead of the hotbar.
		for size in range(4, 10):
			if event.is_action_pressed("hotbar_%d" % size):
				interaction.set_curve_length(size)
				_on_interaction_feedback("Length %d, lanes %d (4-9 / X / C length; Shift-aim sets length and lanes)" % [interaction.curve_length(), interaction.curve_lanes()])
				get_viewport().set_input_as_handled()
				return
	if interaction != null and interaction.drag_active() and str(interaction.drag_state().get("mode", "")) == "loop_element":
		# Loop element ghost: 4-9 set the base width instead of the hotbar.
		for size in range(InteractionService.LOOP_SIZE_MIN, InteractionService.LOOP_SIZE_MAX + 1):
			if event.is_action_pressed("hotbar_%d" % size):
				interaction.set_loop_size(size)
				_on_interaction_feedback("Loop size %d (4-9 while the ghost shows; X / C too; Shift-drag for any size)" % size)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_L or event.keycode == KEY_L):
			var true_loop := interaction.toggle_loop_kind()
			_on_interaction_feedback("Loop kind: %s (L toggles)" % ("TRUE LOOP - touches the ground at its entry and exit only; Shift-drag or 4-9 / X / C size it" if true_loop else "classic foundation loop (switchers, slopes, ring)"))
			_emit_hud()
			get_viewport().set_input_as_handled()
			return
	if interaction != null and interaction.drag_active() and str(interaction.drag_state().get("mode", "")) == "climb":
		# Climb ghost: 4-9 set the rise in cells instead of the hotbar.
		for rise in range(4, 10):
			if event.is_action_pressed("hotbar_%d" % rise):
				interaction.set_climb_rise(rise)
				_on_interaction_feedback("Climb rise %d, length %d (4-9 / X / C set the rise while the ghost shows; Shift-aim at the landing for any length and rise, below the entry for a descent)" % [interaction.climb_rise, interaction.climb_length])
	if interaction != null and interaction.drag_active() and str(interaction.drag_state().get("mode", "")) == "curve":
		# Curve ghost: 4-9 set the radius instead of the hotbar.
		for radius in range(4, 10):
			if event.is_action_pressed("hotbar_%d" % radius):
				interaction.set_curve_radius(radius)
				_on_interaction_feedback("Curve radius %d (4-9 while the ghost shows; X / C too; Shift-aim for any size and the sweep)" % int(interaction.drag_state().get("curve_radius", radius)))
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and not event.echo and ((event.physical_keycode == KEY_U or event.keycode == KEY_U) or ((event.physical_keycode == KEY_Z or event.keycode == KEY_Z) and event.ctrl_pressed)):
		# Undo (owner 2026-09-20): U or Ctrl+Z takes back the last placement -
		# a whole lay (loop, curve, climb, switch, crossing, rail line) or a
		# single piece / block - pieces gone, terrain restored, items back.
		undo_last_placement()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_SHIFT or event.keycode == KEY_SHIFT) and event.location == KEY_LOCATION_RIGHT:
		# Double-tap Right Shift: flight on / off (owner 2026-09-23). The
		# first tap still does its ordinary Interact; only the second tap of
		# a double is swallowed.
		var now := Time.get_ticks_msec()
		if now - _right_shift_msec <= FLIGHT_DOUBLE_TAP_MSEC:
			_right_shift_msec = -FLIGHT_DOUBLE_TAP_MSEC
			toggle_flight()
			get_viewport().set_input_as_handled()
			return
		_right_shift_msec = now
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_V or event.keycode == KEY_V):
		# Coaster car and hero: V toggles the chase camera (raw key, like X / C).
		toggle_third_person()
		get_viewport().set_input_as_handled()
		return
	var rotation_direction := 1 if event.is_action_pressed("rotate_build_clockwise") else -1 if event.is_action_pressed("rotate_build_counterclockwise") else 0
	if rotation_direction != 0:
		var rotation := interaction.rotate_placement(rotation_direction)
		_placement_preview_key = ""
		_on_interaction_feedback("Build orientation: %s" % ["North", "East", "South", "West"][rotation])
		get_viewport().set_input_as_handled()
		return
	for index in range(F0Inventory.HOTBAR_COUNT):
		if event.is_action_pressed("hotbar_%d" % (index + 1)):
			if inventory.selected_hotbar == index:
				# The held slot's key again empties the hands (owner 2026-09-21).
				inventory.deselect_hotbar()
				_on_interaction_feedback("Hands empty (press a slot key to hold something).")
				_emit_hud()
			else:
				select_hotbar(index)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_Y or event.keycode == KEY_Y):
		# Y drops one of the held item in front of the player (Shift+Y the
		# whole stack); walking over a drop picks it up.
		drop_held_item(event.shift_pressed)
		get_viewport().set_input_as_handled()
		return


func _on_interaction_result(result: Dictionary) -> void:
	if _held_item_view != null and str(result.get("reason", "")) != "OPEN_STATION":
		_held_item_view.play_use()
	var changes: Dictionary = result.get("changes", {})
	if result.get("ok", false) and int(changes.get("cleared", 0)) > 0:
		# Track auto-clear: the player's own report of this result (which
		# follows) carries the count.
		_cleared_for_track = int(changes.cleared)
	if result.get("ok", false) and str(result.get("reason", "")) == "BEND_PLACED":
		_bend_lanes_laid = int(changes.get("lanes", 0))
	if result.get("ok", false) and str(result.get("reason", "")) == "OPEN_STATION":
		var station_record: Dictionary = changes.get("station", {})
		if str(station_record.get("entity_id", "")) == MinerService.MINER_ENTITY and miner_service != null:
			# A miner has no menu: right-click reports what it is doing.
			_on_interaction_feedback(miner_status_line(str(changes.get("instance_id", ""))))
			return
		if str(station_record.get("entity_id", "")) == WorkstationService.GATE_ENTITY:
			# Defence sets: a gate has no menu - right-click works the leaf.
			var toggled := workstations.toggle_gate(str(changes.get("instance_id", "")))
			_on_interaction_feedback(str(toggled.get("reason", "NOT_A_GATE")))
			return
		if str(station_record.get("entity_id", "")) == CoasterRails.CAR:
			# Right-click on a coaster car boards it (owner 2026-09-20).
			var boarded := board_coaster_car(str(changes.get("instance_id", "")))
			_on_interaction_feedback(str(boarded.get("reason", "NO_CAR")))
			return
		workstation_requested.emit(str(changes.get("instance_id", "")), str(station_record.get("entity_id", "")))


func _on_station_changed(result: Dictionary) -> void:
	if not result.get("ok", false):
		return
	var details: Dictionary = result.get("details", {})
	if defense != null:
		defense.notify_placed_entity_cells(details.get("occupied_cells", []))
	if core_defense != null:
		core_defense.notify_placed_entity_cells(details.get("occupied_cells", []))
		core_defense.notify_core_station_changed(details)
	if details.has("station"):
		_spawn_station_visual(details.station)
		if CoasterRails.is_track_id(str(details.station.get("entity_id", ""))):
			_refresh_rail_neighbours(details.station.get("anchor", Vector3i.ZERO))
	elif details.has("instance_id") and (details.has("returned_item") or bool(details.get("destroyed", false))):
		_remove_station_visual(str(details.instance_id))
		var released: Array = details.get("occupied_cells", [])
		if CoasterRails.is_track_id(str(details.get("entity_id", ""))) and released.size() > 0 and released[0] is Vector3i:
			_refresh_rail_neighbours(released[0])
	elif details.has("instance_id") and details.has("gate_open"):
		_apply_gate_state(str(details.instance_id), bool(details.gate_open), true)
	elif details.has("instance_id") and details.has("integrity"):
		_update_station_visual(str(details.instance_id), int(details.integrity), int(details.get("max_integrity", 1)))
	elif details.has("instance_id") and details.has("container_slots"):
		_refresh_ore_heap(str(details.instance_id))
		_refresh_container_visual(str(details.instance_id))


## The foundry's glowing mouth follows its status (docs/INDUSTRY.md).
func _on_foundry_changed(instance_id: String, state: Dictionary) -> void:
	var body: Node3D = _station_visuals.get(instance_id)
	if body == null:
		return
	var glow := body.get_node_or_null("Glow")
	if glow != null:
		glow.visible = bool(state.get("working", false))


## Warehouse: the crate stack shows when it holds anything (rebuilt on every
## container change; a chest keeps its fixed look).
func _refresh_container_visual(instance_id: String) -> void:
	var body: Node3D = _station_visuals.get(instance_id)
	if body == null or str(workstations.station(instance_id).get("entity_id", "")) != "warehouse":
		return
	var old := body.get_node_or_null("Crates")
	if old != null:
		body.remove_child(old)
		old.queue_free()
	_build_warehouse_crates(body, _container_item_count(instance_id))


func _container_item_count(instance_id: String) -> int:
	var total := 0
	for stack in workstations.container_slots(instance_id):
		total += int(stack.get("count", 0))
	return total


func _on_job_completed(result: Dictionary) -> void:
	_on_interaction_feedback(str(result.get("reason", "JOB_COMPLETED")))


func _spawn_station_visual(record: Dictionary) -> void:
	var instance_id := str(record.get("instance_id", ""))
	if instance_id.is_empty() or _station_visuals.has(instance_id):
		return
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var definition := registry.entity(str(record.get("entity_id", "")))
	if definition.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PlacedEntity_" + instance_id
	body.position = Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	body.rotation.y = -float(int(record.get("rotation_quarters", 0))) * PI / 2.0
	body.set_meta("station_instance_id", instance_id)
	var material := StandardMaterial3D.new()
	var visual: Dictionary = definition.get("visual", {})
	material.albedo_color = Color(str(visual.get("color", "8b929d")))
	material.roughness = 0.9
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var texture_path := str(visual.get("texture", ""))
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path)
	if not definition.get("defense", {}).is_empty():
		body.set_meta("defense_structure_id", instance_id)
	var entity_id := str(record.get("entity_id", ""))
	if entity_id == "workbench":
		_build_workbench_visual(body)
	elif entity_id == "furnace":
		_build_furnace_visual(body)
	elif entity_id == "coastercraft_shop":
		_build_coastercraft_shop_visual(body)
	elif entity_id == "warehouse":
		_build_warehouse_visual(body)
		_build_warehouse_crates(body, _container_item_count(instance_id))
	elif entity_id == "foundry":
		_build_foundry_visual(body)
	elif entity_id == "ballista":
		_build_ballista_visual(body)
		_wrap_siege_turret(body, definition)
	elif entity_id == "catapult":
		_build_catapult_visual(body)
		_wrap_siege_turret(body, definition)
	elif entity_id == "turret_catapult":
		_build_turret_catapult_visual(body)
		_wrap_siege_turret(body, definition)
	elif entity_id == "turret_catapult_mk2":
		_build_turret_catapult_mk2_visual(body)
		_wrap_siege_turret(body, definition)
	elif entity_id == "cannon":
		_build_cannon_visual(body)
		_wrap_siege_turret(body, definition)
	elif entity_id == "kettle":
		_build_kettle_visual(body)
		_wrap_siege_turret(body, definition)
	elif entity_id == WorkstationService.GATE_ENTITY:
		_build_gate_visual(body)
	elif entity_id == "rail_turret":
		_build_rail_turret_visual(body)
		_wrap_siege_turret(body, definition)
	elif entity_id == "rail":
		_build_rail_visual(body, record)
	elif entity_id == CoasterRails.SLOPE:
		_build_rail_slope_visual(body, record)
	elif entity_id == CoasterRails.LOOP:
		_build_rail_loop_visual(body, record)
	elif entity_id == CoasterRails.SWITCH:
		_build_rail_switch_visual(body, record)
	elif entity_id == "mine_cart":
		_build_mine_cart_visual(body, record.get("cargo", {}))
	elif entity_id == CoasterRails.CAR:
		_build_coaster_car_visual(body)
	elif entity_id == "core_of_power":
		_build_core_of_power_visual(body, registry.entity_attributes(entity_id))
	elif entity_id == "enemy_core":
		_build_enemy_core_visual(body, registry.entity_attributes(entity_id))
	elif entity_id == WorkstationService.SIGN_ENTITY:
		_build_sign_visual(body, record)
	elif entity_id == "torch":
		_build_torch_visual(body, registry.entity_attributes(entity_id))
	elif entity_id == "wall_lantern":
		_build_wall_lantern_visual(body, registry.entity_attributes(entity_id))
	elif entity_id == "post_lantern":
		_build_post_lantern_visual(body, registry.entity_attributes(entity_id))
	elif entity_id == "campfire":
		_build_campfire_visual(body, registry.entity_attributes(entity_id))
	elif entity_id == "light_block_blue":
		_build_light_block_visual(body, registry.entity_attributes(entity_id), Color("4c9dff"))
	elif entity_id == "light_block_red":
		_build_light_block_visual(body, registry.entity_attributes(entity_id), Color("ff3030"))
	elif entity_id == MinerService.MINER_ENTITY:
		_build_miner_visual(body, instance_id)
	elif entity_id == MinerService.BIN_ENTITY:
		_build_ore_bin_visual(body)
	else:
		_add_visual_parts(body, visual.get("parts", []), material, true)
	add_child(body)
	_station_visuals[instance_id] = body
	_station_visual_materials[instance_id] = material
	if entity_id == MinerService.BIN_ENTITY:
		_refresh_ore_heap(instance_id)
	if siege_defense != null and not definition.get("siege", {}).is_empty():
		siege_defense.register_visual(instance_id, body)
	if entity_id == "mine_cart" or entity_id == CoasterRails.CAR:
		if coaster_carts == null:
			coaster_carts = CoasterCartService.new()
			coaster_carts.name = "CoasterCartService"
			coaster_carts.initialize(workstations)
			coaster_carts.cargo_changed.connect(_on_cart_cargo_changed)
			add_child(coaster_carts)
		# A coaster car waits, parked, for a rider (docs/COASTER_CAR_AND_HERO.md).
		coaster_carts.register_cart(instance_id, body, entity_id == CoasterRails.CAR)
	if record.has("gate_open"):
		# A restored gate stands where it was left, without replaying the slide.
		_apply_gate_state(instance_id, bool(record.gate_open), false)
	if record.has("integrity"):
		_update_station_visual(instance_id, int(record.integrity), int(definition.get("defense", {}).get("max_integrity", 1)))


func _add_visual_parts(parent: Node3D, part_values: Array, material: Material, add_collision: bool) -> void:
	for value in part_values:
		if not value is Dictionary:
			continue
		var offset := _vector3_from_array(value.get("offset", []), Vector3.ZERO)
		var size := _vector3_from_array(value.get("size", []), Vector3.ONE)
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			continue
		if add_collision:
			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size
			collision.shape = box
			collision.position = offset
			parent.add_child(collision)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_instance.mesh = mesh
		mesh_instance.position = offset
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not add_collision else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mesh_instance)


func _build_workbench_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(0.90, 0.90, 0.90), Vector3.ZERO)
	var wood := _visual_material(Color("b9783f"), "res://assets/blocks/planks.svg")
	var dark_wood := _visual_material(Color("744326"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("9ca7ad"))
	_add_mesh_box(parent, Vector3(0.94, 0.16, 0.94), Vector3(0.0, 0.34, 0.0), wood)
	for x in [-0.34, 0.34]:
		for z in [-0.34, 0.34]:
			_add_mesh_box(parent, Vector3(0.14, 0.70, 0.14), Vector3(x, -0.09, z), dark_wood)
	_add_mesh_box(parent, Vector3(0.72, 0.10, 0.12), Vector3(0.0, -0.05, 0.34), dark_wood)
	_add_mesh_box(parent, Vector3(0.12, 0.10, 0.72), Vector3(0.34, -0.05, 0.0), dark_wood)
	var hammer := Node3D.new()
	hammer.position = Vector3(0.02, 0.46, 0.02)
	hammer.rotation = Vector3(0.0, -0.58, 0.0)
	parent.add_child(hammer)
	_add_mesh_box(hammer, Vector3(0.07, 0.07, 0.46), Vector3(0.0, 0.0, 0.0), dark_wood)
	_add_mesh_box(hammer, Vector3(0.34, 0.13, 0.13), Vector3(0.0, 0.0, -0.20), iron)


func _build_furnace_visual(parent: Node3D) -> void:
	# P3H.4: masonry skin matching the catalog icon — castle-stone bricks, a
	# stepped dark arch on the front face and an emissive ember bed inside it.
	_add_collision_box(parent, Vector3(0.90, 0.90, 0.90), Vector3.ZERO)
	var masonry := _visual_material(Color("d9dde0"), "res://assets/blocks/castle_stone.svg")
	var mortar := _visual_material(Color("6b7178"), "res://assets/blocks/stone.svg")
	var dark := _visual_material(Color("14181c"))
	var ember := _visual_material(Color("ff7a1f"), "", Color("ff4a0c"))
	var flame := _visual_material(Color("ffd25a"), "", Color("ffb020"))
	_add_mesh_box(parent, Vector3(0.90, 0.90, 0.90), Vector3.ZERO, masonry)
	_add_mesh_box(parent, Vector3(0.96, 0.10, 0.96), Vector3(0.0, 0.40, 0.0), mortar)
	_add_mesh_box(parent, Vector3(0.96, 0.06, 0.96), Vector3(0.0, -0.42, 0.0), mortar)
	# Stepped arch: wide lower opening plus a narrower crown block.
	_add_mesh_box(parent, Vector3(0.50, 0.36, 0.05), Vector3(0.0, -0.14, 0.455), dark)
	_add_mesh_box(parent, Vector3(0.30, 0.12, 0.05), Vector3(0.0, 0.10, 0.455), dark)
	_add_mesh_box(parent, Vector3(0.40, 0.14, 0.06), Vector3(0.0, -0.22, 0.462), ember)
	_add_mesh_box(parent, Vector3(0.18, 0.10, 0.07), Vector3(0.0, -0.10, 0.466), flame)


## CoasterCraft Shop (docs/INDUSTRY_PLAN.md, wave 1): the coaster parts
## foundry, a 2 x 1 machine in the coaster style - a castle-stone base under
## an oak bench on dark-oak legs, a short length of iron rail on oak sleepers
## along the bench with a small cart body parked on it, gold studs at the
## bench corners. The body sits at the anchor cell; +x is the second cell.
func _build_coastercraft_shop_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(1.90, 0.90, 0.90), Vector3(0.5, 0.0, 0.0))
	var stone := _visual_material(Color("8c9298"), "res://assets/blocks/castle_stone.svg")
	var stone_dark := _visual_material(Color("5d646b"))
	var oak := _visual_material(Color("b9783f"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("744326"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("7b838c"))
	var dark_iron := _visual_material(Color("2f353b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	# Stone base slab with a darker plinth line.
	_add_mesh_box(parent, Vector3(1.92, 0.30, 0.92), Vector3(0.5, -0.35, 0.0), stone)
	_add_mesh_box(parent, Vector3(1.96, 0.06, 0.96), Vector3(0.5, -0.47, 0.0), stone_dark)
	# Bench: four dark-oak legs and an oak top.
	for x in [-0.34, 1.34]:
		for z in [-0.34, 0.34]:
			_add_mesh_box(parent, Vector3(0.14, 0.40, 0.14), Vector3(x, -0.02, z), dark_oak)
	_add_mesh_box(parent, Vector3(1.94, 0.14, 0.94), Vector3(0.5, 0.22, 0.0), oak)
	for x in [-0.40, 1.40]:
		for z in [-0.38, 0.38]:
			_add_stud(parent, Vector3(x, 0.30, z), gold, Vector3(0.0, 0.0, PI / 2.0))
	# A short length of track along the bench: sleepers, two rails.
	for x in [-0.20, 0.30, 0.80, 1.20]:
		_add_mesh_box(parent, Vector3(0.12, 0.05, 0.70), Vector3(x, 0.315, 0.0), dark_oak)
	for z in [-0.22, 0.22]:
		_add_mesh_box(parent, Vector3(1.60, 0.06, 0.07), Vector3(0.5, 0.36, z), iron)
	# A small cart body parked on the rail (open top, iron rim, two wheels a side).
	var cart := Node3D.new()
	cart.name = "ShopCart"
	cart.position = Vector3(0.95, 0.40, 0.0)
	parent.add_child(cart)
	for x in [-0.16, 0.16]:
		for z in [-0.24, 0.24]:
			_add_mesh_cylinder(cart, 0.07, 0.05, Vector3(x, 0.0, z), Vector3(PI / 2.0, 0.0, 0.0), dark_iron, "ShopCartWheel")
	_add_mesh_box(cart, Vector3(0.50, 0.06, 0.34), Vector3(0.0, 0.05, 0.0), dark_iron)
	_add_mesh_box(cart, Vector3(0.46, 0.22, 0.30), Vector3(0.0, 0.18, 0.0), oak)
	_add_mesh_box(cart, Vector3(0.52, 0.04, 0.36), Vector3(0.0, 0.30, 0.0), iron)
	_add_stud(cart, Vector3(0.0, 0.33, 0.0), gold, Vector3(0.0, 0.0, PI / 2.0))
	# Bench tools: a hammer and a spare rail end waiting on the near end.
	var hammer := Node3D.new()
	hammer.position = Vector3(-0.10, 0.34, 0.30)
	hammer.rotation = Vector3(0.0, 0.42, 0.0)
	parent.add_child(hammer)
	_add_mesh_box(hammer, Vector3(0.06, 0.06, 0.34), Vector3.ZERO, dark_oak)
	_add_mesh_box(hammer, Vector3(0.24, 0.10, 0.10), Vector3(0.0, 0.0, -0.14), iron)


## Industry wave 1 (docs/INDUSTRY.md): the miner. A stone base slab with
## gold studs, two steel posts and a crossbar, a dark motor block and an iron
## drill cone pointing down under the node "Drill" (spun while it works).
func _build_miner_visual(parent: Node3D, instance_id: String) -> void:
	_add_collision_box(parent, Vector3(0.90, 0.90, 0.90), Vector3.ZERO)
	var stone := _visual_material(Color("8c9298"), "res://assets/blocks/castle_stone.svg")
	var steel := _visual_material(Color("7b838c"))
	var dark_iron := _visual_material(Color("2f353b"))
	var iron := _visual_material(Color("aeb7bd"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	_add_mesh_box(parent, Vector3(0.92, 0.16, 0.92), Vector3(0.0, -0.42, 0.0), stone)
	for x in [-0.36, 0.36]:
		for z in [-0.36, 0.36]:
			_add_stud(parent, Vector3(x, -0.33, z), gold, Vector3.ZERO)
	for x in [-0.32, 0.32]:
		_add_mesh_box(parent, Vector3(0.12, 0.84, 0.12), Vector3(x, 0.08, 0.0), steel)
	_add_mesh_box(parent, Vector3(0.80, 0.12, 0.16), Vector3(0.0, 0.44, 0.0), steel)
	_add_mesh_box(parent, Vector3(0.30, 0.22, 0.30), Vector3(0.0, 0.27, 0.0), dark_iron)
	var drill := Node3D.new()
	drill.name = "Drill"
	drill.position = Vector3(0.0, -0.05, 0.0)
	parent.add_child(drill)
	# The cone points down: CylinderMesh's tip is +y, so flip it.
	_add_mesh_cone(drill, 0.17, 0.42, Vector3.ZERO, Vector3(PI, 0.0, 0.0), iron)
	for step in range(3):
		var fin := _add_mesh_box(drill, Vector3(0.30 - 0.07 * step, 0.03, 0.06), Vector3(0.0, 0.12 - 0.11 * step, 0.0), dark_iron)
		fin.rotation.y = 0.6 * step
	_miner_drills[instance_id] = drill


## Industry wave 1 (docs/INDUSTRY.md): the ore bin, an open oak crate with iron
## bands. The "OreHeap" node on top shows a heap of ore-coloured lumps while
## the bin holds items (rebuilt on every container change).
func _build_ore_bin_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(0.90, 0.80, 0.90), Vector3(0.0, -0.10, 0.0))
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("7b838c"))
	_add_mesh_box(parent, Vector3(0.86, 0.08, 0.86), Vector3(0.0, -0.46, 0.0), dark_oak)
	for x in [-0.42, 0.42]:
		_add_mesh_box(parent, Vector3(0.06, 0.80, 0.90), Vector3(x, -0.10, 0.0), oak)
	for z in [-0.42, 0.42]:
		_add_mesh_box(parent, Vector3(0.90, 0.80, 0.06), Vector3(0.0, -0.10, z), oak)
	for y in [-0.36, 0.20]:
		_add_mesh_box(parent, Vector3(0.94, 0.06, 0.94), Vector3(0.0, y, 0.0), iron)
	var heap := Node3D.new()
	heap.name = "OreHeap"
	heap.position = Vector3(0.0, 0.16, 0.0)
	parent.add_child(heap)


## Rebuilds a bin's heap: more lumps the fuller the bin (up to seven),
## coloured by the ore it holds (iron grey, gold yellow, coal black); none
## while the bin is empty.
func _refresh_ore_heap(instance_id: String) -> void:
	if not _station_visuals.has(instance_id) or workstations == null or not workstations.is_container(instance_id):
		return
	var body: Node = _station_visuals[instance_id]
	var heap: Node3D = body.get_node_or_null("OreHeap") as Node3D
	if heap == null:
		return
	for child in heap.get_children():
		child.queue_free()
	var colours: Array[Color] = []
	var total := 0
	var capacity := 0
	for stack in workstations.container_slots(instance_id):
		var item_id := str(stack.get("item_id", ""))
		var count := int(stack.get("count", 0))
		capacity += registry.max_stack(item_id) if not item_id.is_empty() else registry.max_stack("iron_ore")
		if item_id.is_empty() or count <= 0:
			continue
		total += count
		colours.append(_ore_lump_colour(item_id))
	if total <= 0 or colours.is_empty():
		return
	var lumps := clampi(ceili(float(total) * 7.0 / float(maxi(capacity, 1))), 1, 7)
	var spots: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(-0.22, -0.04, -0.18), Vector3(0.22, -0.04, 0.16), Vector3(-0.20, -0.04, 0.20), Vector3(0.20, -0.04, -0.20), Vector3(0.0, 0.14, -0.10), Vector3(0.02, 0.16, 0.12)]
	for index in range(lumps):
		var lump := _add_mesh_box(heap, Vector3(0.24, 0.22, 0.24), spots[index], _visual_material(colours[index % colours.size()]))
		lump.rotation = Vector3(0.3 * index, 0.5 + 0.7 * index, 0.2)


func _ore_lump_colour(item_id: String) -> Color:
	match item_id:
		"gold_ore":
			return Color("e0b13a")
		"coal":
			return Color("23262a")
		"iron_ore":
			return Color("9a8f86")
	return Color("8f969d")


## Spins every working miner's drill; a stalled miner (no ore, no bin, bin
## full) stands still, which reads from a distance.
func _spin_miner_drills(delta: float) -> void:
	if simulation_paused or saving or not world_ready or _miner_drills.is_empty():
		return
	for instance_id: String in _miner_drills.keys():
		var drill: Node3D = _miner_drills[instance_id]
		if not is_instance_valid(drill):
			_miner_drills.erase(instance_id)
			continue
		if miner_service.is_working(instance_id):
			drill.rotate_y(delta * 9.0)


## "Miner: 3 ore mined, drilling iron ore 2 m away." plus a hint while stalled.
func miner_status_line(instance_id: String) -> String:
	if miner_service == null:
		return str(REASON_TEXT.get("OPEN_STATION", ""))
	var line := miner_service.status_text(instance_id) + "."
	var status := str(miner_service.miner_state(instance_id).get("status", ""))
	if status == MinerService.STATUS_NO_BIN:
		line += " " + str(REASON_TEXT.get("MINER_NO_BIN_HINT", ""))
	elif status == MinerService.STATUS_BIN_FULL:
		line += " " + str(REASON_TEXT.get("MINER_BIN_FULL_HINT", ""))
	elif status == MinerService.STATUS_NO_ORE:
		line += " " + str(REASON_TEXT.get("MINER_NO_ORE_HINT", ""))
	return line


func _build_warehouse_visual(parent: Node3D) -> void:
	# Industry wave 1: a stone-footed oak shed over the 2 x 2 footprint (the
	# body sits at the anchor cell's centre; the shed spans +x / +z), a door
	# on the +z face, a gable roof of dark oak and a gold latch.
	var stone := _visual_material(Color("8b929d"), "res://assets/blocks/stone.svg")
	var wood := _visual_material(Color("b9783f"), "res://assets/blocks/planks.svg")
	var dark_wood := _visual_material(Color("744326"), "res://assets/blocks/log.svg")
	var gold := _visual_material(Color("e2aa2c"), "", Color("7a5210"))
	var centre := Vector3(0.5, 0.0, 0.5)
	_add_collision_box(parent, Vector3(1.96, 1.0, 1.96), centre)
	_add_mesh_box(parent, Vector3(1.96, 0.16, 1.96), centre + Vector3(0.0, -0.42, 0.0), stone)
	_add_mesh_box(parent, Vector3(1.84, 0.78, 1.84), centre + Vector3(0.0, 0.05, 0.0), wood)
	for x in [-0.86, 0.86]:
		for z in [-0.86, 0.86]:
			_add_mesh_box(parent, Vector3(0.14, 0.86, 0.14), centre + Vector3(x, 0.02, z), dark_wood)
	# Gable roof: two leaning slabs and a ridge beam.
	for side in [-1.0, 1.0]:
		var slab := _add_mesh_box(parent, Vector3(1.24, 0.08, 2.08), centre + Vector3(side * 0.48, 0.66, 0.0), dark_wood)
		slab.rotation.z = -side * 0.42
	_add_mesh_box(parent, Vector3(0.14, 0.14, 2.12), centre + Vector3(0.0, 0.94, 0.0), dark_wood)
	# Door on the +z face with a gold latch.
	_add_mesh_box(parent, Vector3(0.46, 0.66, 0.06), centre + Vector3(0.0, -0.04, 0.94), dark_wood)
	_add_stud(parent, centre + Vector3(0.16, -0.06, 0.98), gold, Vector3.ZERO)


## The crate stack outside the door: one crate per 9 items held (up to four).
func _build_warehouse_crates(parent: Node3D, item_count: int) -> void:
	var crates := Node3D.new()
	crates.name = "Crates"
	parent.add_child(crates)
	if item_count <= 0:
		return
	var crate_wood := _visual_material(Color("a0642f"), "res://assets/blocks/planks.svg")
	var band := _visual_material(Color("744326"), "res://assets/blocks/log.svg")
	var count := clampi((item_count + 8) / 9, 1, 4)
	var spots: Array[Vector3] = [Vector3(1.22, -0.2, 1.62), Vector3(1.22, -0.2, 1.22), Vector3(1.22, 0.18, 1.42), Vector3(0.82, -0.2, 1.62)]
	for index in range(count):
		var crate := _add_mesh_box(crates, Vector3(0.36, 0.36, 0.36), spots[index], crate_wood)
		_add_mesh_box(crate, Vector3(0.38, 0.06, 0.38), Vector3.ZERO, band)


func _build_foundry_visual(parent: Node3D) -> void:
	# Industry wave 1: a castle-stone furnace body over the 2 x 1 footprint
	# (spanning +x from the anchor), an iron chimney on the far cell, a wide
	# mouth on the +z face whose glow shows while smelting, a mould tray of
	# iron with gold studs on the near cell's top.
	var masonry := _visual_material(Color("d9dde0"), "res://assets/blocks/castle_stone.svg")
	var mortar := _visual_material(Color("6b7178"), "res://assets/blocks/stone.svg")
	var iron := _visual_material(Color("4a5259"))
	var dark := _visual_material(Color("14181c"))
	var ember := _visual_material(Color("ff7a1f"), "", Color("ff4a0c"))
	var gold := _visual_material(Color("e2aa2c"), "", Color("7a5210"))
	var centre := Vector3(0.5, 0.0, 0.0)
	_add_collision_box(parent, Vector3(1.9, 0.9, 0.9), centre)
	_add_mesh_box(parent, Vector3(1.9, 0.9, 0.9), centre, masonry)
	_add_mesh_box(parent, Vector3(1.96, 0.08, 0.96), centre + Vector3(0.0, 0.42, 0.0), mortar)
	_add_mesh_box(parent, Vector3(1.96, 0.06, 0.96), centre + Vector3(0.0, -0.42, 0.0), mortar)
	# Iron chimney on the far cell.
	_add_mesh_cylinder(parent, 0.14, 0.9, Vector3(1.1, 0.85, 0.0), Vector3.ZERO, iron, "Chimney")
	_add_mesh_box(parent, Vector3(0.4, 0.08, 0.4), Vector3(1.1, 1.3, 0.0), iron)
	# Mouth on the -z face: dark opening, the glow toggles with the status.
	_add_mesh_box(parent, Vector3(0.7, 0.4, 0.05), Vector3(0.0, -0.12, 0.455), dark)
	_add_mesh_box(parent, Vector3(0.5, 0.16, 0.06), Vector3(0.0, -0.22, 0.462), ember, "Glow").visible = false
	# Mould tray with gold studs on the near cell's top.
	_add_mesh_box(parent, Vector3(0.62, 0.08, 0.46), Vector3(0.0, 0.5, 0.0), iron)
	for x in [-0.18, 0.18]:
		_add_stud(parent, Vector3(x, 0.56, 0.0), gold, Vector3.ZERO)


func _build_ballista_visual(parent: Node3D) -> void:
	# Remodelled from the owner's reference (2026-09-19): an iron pedestal on
	# a dark-oak base, a turntable, a heavy oak stock with an iron slider that
	# draws back over the reload, two forward-swept bow arms with iron tips, a
	# rope string laid from each tip to the slider nock, and a loaded bolt
	# shown only while the machine holds ammunition. Forward (shot) is -z.
	_add_collision_box(parent, Vector3(1.90, 1.10, 1.90), Vector3(0.5, 0.02, 0.5))
	var oak := _visual_material(Color("a96532"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("5b321e"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("aeb7bd"))
	var dark_iron := _visual_material(Color("4a5158"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var rope := _visual_material(Color("c9b17a"))
	# Base, pedestal and turntable.
	_add_mesh_box(parent, Vector3(1.72, 0.18, 1.72), Vector3(0.5, -0.40, 0.5), dark_oak)
	for corner in [Vector3(-0.28, -0.24, -0.28), Vector3(1.28, -0.24, -0.28), Vector3(-0.28, -0.24, 1.28), Vector3(1.28, -0.24, 1.28)]:
		_add_stud(parent, corner, gold, Vector3.ZERO)
	_add_mesh_cylinder(parent, 0.20, 0.52, Vector3(0.5, -0.06, 0.5), Vector3.ZERO, iron, "BallistaPedestal")
	_add_mesh_cylinder(parent, 0.46, 0.08, Vector3(0.5, 0.22, 0.5), Vector3.ZERO, dark_iron, "BallistaTurntable")
	# Stock: long oak beam with an iron channel on top and a rear grip.
	_add_mesh_box(parent, Vector3(0.36, 0.16, 1.90), Vector3(0.5, 0.34, 0.40), oak)
	_add_mesh_box(parent, Vector3(0.14, 0.05, 1.86), Vector3(0.5, 0.445, 0.40), dark_iron)
	_add_mesh_box(parent, Vector3(0.14, 0.24, 0.16), Vector3(0.5, 0.22, 1.30), dark_oak)
	for z in [0.05, 0.60, 1.10]:
		_add_mesh_box(parent, Vector3(0.40, 0.20, 0.10), Vector3(0.5, 0.34, z), dark_iron)
		_add_stud(parent, Vector3(0.72, 0.34, z), gold, Vector3(0.0, 0.0, PI / 2.0))
		_add_stud(parent, Vector3(0.28, 0.34, z), gold, Vector3(0.0, 0.0, PI / 2.0))
	# Bow: iron bracket at the front of the stock and two swept arms.
	var bow := Node3D.new()
	bow.name = "BallistaBow"
	bow.position = Vector3(0.5, 0.40, -0.40)
	parent.add_child(bow)
	_add_mesh_box(bow, Vector3(0.50, 0.30, 0.22), Vector3.ZERO, dark_iron)
	for side in [-1.0, 1.0]:
		var arm := _add_mesh_box(bow, Vector3(1.05, 0.12, 0.14), Vector3(side * 0.66, 0.0, -0.14), oak)
		arm.rotation.y = side * 0.42
		var tip := Node3D.new()
		tip.name = "BallistaTip_%s" % ("L" if side < 0.0 else "R")
		tip.position = Vector3(side * 1.14, 0.0, -0.36)
		bow.add_child(tip)
		_add_mesh_box(tip, Vector3(0.12, 0.18, 0.12), Vector3.ZERO, iron)
		var string_pivot := Node3D.new()
		string_pivot.name = "BallistaString_%s" % ("L" if side < 0.0 else "R")
		tip.add_child(string_pivot)
		_add_mesh_box(string_pivot, Vector3(0.04, 0.04, 1.0), Vector3(0.0, 0.0, 0.5), rope)
	# Slider: iron carriage that rides the stock channel; the bolt sits on it.
	var slider := Node3D.new()
	slider.name = "BallistaSlider"
	slider.position = Vector3(0.5, 0.50, 0.55)
	parent.add_child(slider)
	_add_mesh_box(slider, Vector3(0.22, 0.10, 0.34), Vector3.ZERO, dark_iron)
	_add_mesh_box(slider, Vector3(0.06, 0.12, 0.06), Vector3(0.0, 0.08, 0.10), iron)
	var bolt := _add_mesh_cylinder(slider, 0.035, 0.90, Vector3(0.0, 0.08, -0.32), Vector3(PI / 2.0, 0.0, 0.0), _visual_material(Color("f2d18b")), "BallistaBolt")
	_add_mesh_cone(bolt, 0.06, 0.16, Vector3(0.0, 0.52, 0.0), Vector3.ZERO, iron)
	var muzzle := Node3D.new()
	muzzle.name = "SiegeMuzzle"
	muzzle.position = Vector3(0.5, 0.56, -0.55)
	parent.add_child(muzzle)


func _build_catapult_visual(parent: Node3D) -> void:
	# Modelled from the owner's reference (2026-09-19): iron-banded oak chassis
	# with gold studs, four spoked wheels with iron rims and gold hub spikes,
	# an A-frame with blue banners, an axle-hinged throwing arm wrapped in rope
	# and an iron bucket. Footprint 2 wide (x 0..1) by 4 long (z 0..3): wheels and
	# chassis on the front rows, armature and bucket over the rear rows. Local
	# origin is the anchor cell centre; forward (throw) is -z, rear is +z.
	_add_collision_box(parent, Vector3(1.96, 0.80, 3.90), Vector3(0.5, -0.10, 1.50))
	_add_collision_box(parent, Vector3(1.60, 1.30, 1.10), Vector3(0.5, 0.75, 0.95))
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("6f7880"))
	var dark_iron := _visual_material(Color("474e55"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var rope := _visual_material(Color("c9b17a"))
	var banner := _visual_material(Color("1f4fb3"))
	var bucket_iron := _visual_material(Color("5c656d"))

	# Chassis: two long side rails, a front bumper and three cross beams.
	for x in [-0.32, 1.32]:
		_add_mesh_box(parent, Vector3(0.24, 0.24, 3.60), Vector3(x, -0.20, 1.40), oak)
		for z in [-0.20, 1.10, 2.30, 3.00]:
			_add_mesh_box(parent, Vector3(0.28, 0.28, 0.14), Vector3(x, -0.20, z), dark_iron)
			_add_stud(parent, Vector3(x + (0.15 if x > 0.5 else -0.15), -0.20, z), gold, Vector3(0.0, 0.0, PI / 2.0))
	_add_mesh_box(parent, Vector3(1.64, 0.22, 0.22), Vector3(0.5, -0.20, -0.30), oak)
	_add_mesh_box(parent, Vector3(1.64, 0.22, 0.22), Vector3(0.5, -0.20, 1.60), oak)
	_add_mesh_box(parent, Vector3(1.64, 0.22, 0.22), Vector3(0.5, -0.20, 3.05), oak)
	_add_mesh_box(parent, Vector3(0.60, 0.16, 0.60), Vector3(0.5, -0.22, 0.55), dark_oak)

	# Wheels: oak disc, iron rim (torus), gold hub spike, three iron studs.
	var wheel_index := 0
	for x in [-0.36, 1.36]:
		for z in [0.10, 1.35]:
			var wheel := _add_mesh_cylinder(parent, 0.44, 0.16, Vector3(x, -0.06, z), Vector3(0.0, 0.0, PI / 2.0), oak, "CatapultWheel_%d" % wheel_index)
			_add_mesh_torus(wheel, 0.38, 0.48, Vector3.ZERO, Vector3.ZERO, iron)
			var hub_direction := 1.0 if x > 0.5 else -1.0
			_add_mesh_cone(parent, 0.10, 0.22, Vector3(x + hub_direction * 0.16, -0.06, z), Vector3(0.0, 0.0, -hub_direction * PI / 2.0), gold)
			for angle in [0.0, 2.094, 4.189]:
				var stud_offset := Vector3(0.0, cos(angle) * 0.30, sin(angle) * 0.30)
				_add_mesh_box(wheel, Vector3(0.08, 0.08, 0.20), Vector3(0.0, stud_offset.y, stud_offset.z), dark_iron).rotation.x = angle
			wheel_index += 1

	# A-frame: two leaning uprights per side meeting at the axle, banners on the
	# front faces, gold diamond studs on iron caps.
	var apex := Vector3(0.5, 1.05, 0.95)
	for x in [0.06, 0.94]:
		var lean := -0.34 if x < 0.5 else 0.34
		var front_leg := _add_mesh_box(parent, Vector3(0.18, 1.60, 0.18), Vector3(x, 0.42, 0.45), oak)
		front_leg.rotation = Vector3(0.36, 0.0, lean)
		var rear_leg := _add_mesh_box(parent, Vector3(0.18, 1.60, 0.18), Vector3(x, 0.42, 1.45), oak)
		rear_leg.rotation = Vector3(-0.36, 0.0, lean)
		var flag := _add_mesh_box(parent, Vector3(0.05, 0.62, 0.30), Vector3(x + (-0.16 if x < 0.5 else 0.16), 0.30, 0.55), banner)
		flag.rotation = Vector3(0.36, 0.0, lean)
		_add_mesh_box(flag, Vector3(0.02, 0.18, 0.14), Vector3(-0.03 if x < 0.5 else 0.03, 0.08, 0.0), gold)
		var cap := _add_mesh_box(parent, Vector3(0.26, 0.24, 0.26), Vector3(x - (0.10 if x < 0.5 else -0.10), 1.10, 0.95), dark_iron)
		_add_stud(parent, Vector3(cap.position.x + (-0.14 if x < 0.5 else 0.14), 1.10, 0.95), gold, Vector3(0.0, 0.0, PI / 2.0))
	_add_mesh_cylinder(parent, 0.09, 1.50, apex, Vector3(0.0, 0.0, PI / 2.0), iron, "CatapultAxle")
	_add_mesh_cylinder(parent, 0.16, 0.24, Vector3(1.30, apex.y, apex.z), Vector3(0.0, 0.0, PI / 2.0), dark_iron, "CatapultAxleNut")

	# Rear armature: two braces from the rails to a cross bar the arm rests on.
	for x in [-0.20, 1.20]:
		var brace := _add_mesh_box(parent, Vector3(0.16, 1.10, 0.16), Vector3(x, 0.25, 2.55), oak)
		brace.rotation.x = 0.28
	_add_mesh_box(parent, Vector3(1.70, 0.16, 0.16), Vector3(0.5, 0.74, 2.70), oak)
	_add_mesh_box(parent, Vector3(0.20, 0.22, 0.20), Vector3(-0.20, 0.74, 2.70), dark_iron)
	_add_mesh_box(parent, Vector3(0.20, 0.22, 0.20), Vector3(1.20, 0.74, 2.70), dark_iron)

	# Throwing arm on a hinge at the axle (rotates about x for P4 animation):
	# rope-wrapped beam rising to the rear, iron bucket at the tip, counter-stub
	# forward of the axle.
	var arm := Node3D.new()
	arm.name = "CatapultArm"
	arm.position = apex
	arm.rotation.x = -0.40
	parent.add_child(arm)
	_add_mesh_box(arm, Vector3(0.20, 0.20, 2.30), Vector3(0.0, 0.0, 0.85), oak)
	_add_mesh_box(arm, Vector3(0.26, 0.26, 0.40), Vector3(0.0, 0.0, -0.35), dark_oak)
	for z in [0.05, 0.20, 0.35]:
		_add_mesh_cylinder(arm, 0.17, 0.10, Vector3(0.0, 0.0, z), Vector3(PI / 2.0, 0.0, 0.0), rope, "CatapultRope")
	for z in [1.55, 1.68]:
		_add_mesh_cylinder(arm, 0.16, 0.09, Vector3(0.0, 0.0, z), Vector3(PI / 2.0, 0.0, 0.0), rope, "CatapultRope")
	for z in [0.70, 1.15]:
		_add_mesh_box(arm, Vector3(0.24, 0.24, 0.12), Vector3(0.0, 0.0, z), dark_iron)
		_add_stud(arm, Vector3(0.0, 0.14, z), gold, Vector3.ZERO)
	var bucket := Node3D.new()
	bucket.name = "CatapultBucket"
	bucket.position = Vector3(0.0, 0.16, 2.02)
	arm.add_child(bucket)
	_add_mesh_cylinder(bucket, 0.36, 0.30, Vector3.ZERO, Vector3.ZERO, bucket_iron, "CatapultBucketWall")
	_add_mesh_cylinder(bucket, 0.30, 0.34, Vector3(0.0, 0.03, 0.0), Vector3.ZERO, dark_iron, "CatapultBucketBowl")
	_add_mesh_torus(bucket, 0.30, 0.40, Vector3(0.0, 0.15, 0.0), Vector3.ZERO, iron)
	for angle in [0.0, 1.571, 3.142, 4.712]:
		_add_stud(bucket, Vector3(cos(angle) * 0.37, 0.05, sin(angle) * 0.37), gold, Vector3(0.0, -angle, 0.0))
	_add_mesh_cylinder(bucket, 0.18, 0.20, Vector3(0.0, 0.10, 0.0), Vector3.ZERO, _visual_material(Color("8f969d"), "res://assets/blocks/stone.svg"), "CatapultStone")


## Moves every mesh part of a siege visual under a "SiegeTurret" node placed
## at the footprint centre so the machine can turn to face its target without
## touching occupancy or collision (P4a-1). Collision shapes stay on the body.
func _wrap_siege_turret(body: Node3D, definition: Dictionary) -> void:
	var cells: Array = definition.get("occupied_offsets", [])
	var centre := Vector3.ZERO
	if not cells.is_empty():
		var minimum := Vector3(INF, 0.0, INF)
		var maximum := Vector3(-INF, 0.0, -INF)
		for value in cells:
			var offset := _vector3_from_array(value, Vector3.ZERO)
			minimum.x = minf(minimum.x, offset.x)
			minimum.z = minf(minimum.z, offset.z)
			maximum.x = maxf(maximum.x, offset.x)
			maximum.z = maxf(maximum.z, offset.z)
		centre = Vector3((minimum.x + maximum.x) * 0.5, 0.0, (minimum.z + maximum.z) * 0.5)
	var turret := Node3D.new()
	turret.name = "SiegeTurret"
	turret.position = centre
	var parts: Array[Node] = []
	for child in body.get_children():
		if child is Node3D and not child is CollisionShape3D:
			parts.append(child)
	body.add_child(turret)
	for part in parts:
		body.remove_child(part)
		turret.add_child(part)
		part.position -= centre


## Compact tower-top catapult (2x2): stone pedestal, iron turntable, short
## A-frame and a hinged arm. Node names match the field catapult so the same
## wind-back/throw animation drives it. Throw direction is -z.
func _build_turret_catapult_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(1.90, 0.60, 1.90), Vector3(0.5, -0.20, 0.5))
	_add_collision_box(parent, Vector3(1.20, 1.20, 1.20), Vector3(0.5, 0.60, 0.5))
	var stone := _visual_material(Color("8b929d"), "res://assets/blocks/castle_stone.svg")
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("6f7880"))
	var dark_iron := _visual_material(Color("474e55"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var rope := _visual_material(Color("c9b17a"))
	_add_mesh_box(parent, Vector3(1.90, 0.40, 1.90), Vector3(0.5, -0.30, 0.5), stone)
	_add_mesh_cylinder(parent, 0.78, 0.12, Vector3(0.5, -0.04, 0.5), Vector3.ZERO, dark_iron, "TurretRing")
	_add_mesh_cylinder(parent, 0.62, 0.16, Vector3(0.5, 0.06, 0.5), Vector3.ZERO, iron, "TurretPlate")
	for angle in [0.0, 1.571, 3.142, 4.712]:
		_add_stud(parent, Vector3(0.5 + cos(angle) * 0.70, 0.02, 0.5 + sin(angle) * 0.70), gold, Vector3(0.0, -angle, 0.0))
	# Deck and A-frame.
	_add_mesh_box(parent, Vector3(1.30, 0.14, 1.30), Vector3(0.5, 0.20, 0.5), oak)
	var apex := Vector3(0.5, 1.02, 0.35)
	for x in [0.05, 0.95]:
		var lean := -0.30 if x < 0.5 else 0.30
		var front_leg := _add_mesh_box(parent, Vector3(0.16, 1.10, 0.16), Vector3(x, 0.62, 0.05), oak)
		front_leg.rotation = Vector3(0.34, 0.0, lean)
		var rear_leg := _add_mesh_box(parent, Vector3(0.16, 1.10, 0.16), Vector3(x, 0.62, 0.65), oak)
		rear_leg.rotation = Vector3(-0.34, 0.0, lean)
		_add_mesh_box(parent, Vector3(0.22, 0.20, 0.22), Vector3(x - (0.08 if x < 0.5 else -0.08), 1.02, 0.35), dark_iron)
	_add_mesh_cylinder(parent, 0.08, 1.20, apex, Vector3(0.0, 0.0, PI / 2.0), iron, "CatapultAxle")
	_add_mesh_box(parent, Vector3(1.20, 0.14, 0.14), Vector3(0.5, 0.62, 1.05), oak)
	# Arm with bucket (same names as the field catapult).
	var arm := Node3D.new()
	arm.name = "CatapultArm"
	arm.position = apex
	arm.rotation.x = -0.40
	parent.add_child(arm)
	_add_mesh_box(arm, Vector3(0.18, 0.18, 1.70), Vector3(0.0, 0.0, 0.55), oak)
	_add_mesh_box(arm, Vector3(0.24, 0.24, 0.30), Vector3(0.0, 0.0, -0.30), dark_oak)
	for z in [0.10, 0.25]:
		_add_mesh_cylinder(arm, 0.15, 0.09, Vector3(0.0, 0.0, z), Vector3(PI / 2.0, 0.0, 0.0), rope, "CatapultRope")
	var bucket := Node3D.new()
	bucket.name = "CatapultBucket"
	bucket.position = Vector3(0.0, 0.14, 1.36)
	arm.add_child(bucket)
	_add_mesh_cylinder(bucket, 0.30, 0.26, Vector3.ZERO, Vector3.ZERO, _visual_material(Color("5c656d")), "CatapultBucketWall")
	_add_mesh_torus(bucket, 0.25, 0.34, Vector3(0.0, 0.13, 0.0), Vector3.ZERO, iron)
	_add_mesh_cylinder(bucket, 0.16, 0.18, Vector3(0.0, 0.10, 0.0), Vector3.ZERO, _visual_material(Color("8f969d"), "res://assets/blocks/stone.svg"), "CatapultStone")


## Cannon (2x2) from the owner's reference art (2026-09-19): a studded oak
## platform with iron corner caps and a blue banner, an iron turntable ring,
## two oak cheek plates with big hex bolts, and a black iron barrel with gold
## bands and studs pitched up on trunnions. Bore is -z; `CannonBarrel` recoils.
func _build_cannon_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(1.96, 0.50, 1.96), Vector3(0.5, -0.25, 0.5))
	_add_collision_box(parent, Vector3(1.10, 1.10, 1.30), Vector3(0.5, 0.55, 0.55))
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("7b838c"))
	var dark_iron := _visual_material(Color("2f353b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	_add_siege_platform(parent, Vector3(0.5, -0.30, 0.5), 1.96, 1.96, oak, iron, gold)
	# Turntable ring and hub.
	_add_mesh_cylinder(parent, 0.78, 0.14, Vector3(0.5, -0.03, 0.5), Vector3.ZERO, dark_iron, "CannonRing")
	_add_mesh_cylinder(parent, 0.66, 0.16, Vector3(0.5, 0.06, 0.5), Vector3.ZERO, iron, "CannonPlate")
	for angle in [0.4, 1.6, 2.7, 3.9, 5.1]:
		_add_stud(parent, Vector3(0.5 + cos(angle) * 0.72, 0.02, 0.5 + sin(angle) * 0.72), gold, Vector3(0.0, -angle, 0.0))
	_add_mesh_cylinder(parent, 0.34, 0.20, Vector3(0.5, 0.20, 0.55), Vector3.ZERO, dark_oak, "CannonHub")
	# Cheek plates: oak trapezoids (a tall box plus a leaning brace) with hex bolts.
	for x in [0.14, 0.86]:
		var side := -1.0 if x < 0.5 else 1.0
		_add_mesh_box(parent, Vector3(0.20, 0.82, 0.72), Vector3(x, 0.52, 0.62), oak)
		var brace := _add_mesh_box(parent, Vector3(0.20, 0.70, 0.24), Vector3(x, 0.40, 0.20), oak)
		brace.rotation.x = -0.55
		_add_mesh_box(parent, Vector3(0.24, 0.16, 0.80), Vector3(x, 0.94, 0.62), dark_iron)
		_add_mesh_cylinder(parent, 0.13, 0.10, Vector3(x + side * 0.14, 0.70, 0.62), Vector3(0.0, 0.0, PI / 2.0), iron, "CannonBolt")
		_add_mesh_cylinder(parent, 0.10, 0.10, Vector3(x + side * 0.14, 0.34, 0.86), Vector3(0.0, 0.0, PI / 2.0), iron, "CannonBolt")
		_add_stud(parent, Vector3(x + side * 0.14, 0.52, 0.30), gold, Vector3(0.0, 0.0, PI / 2.0))
	# Barrel on trunnions, pitched up like the reference.
	var barrel := Node3D.new()
	barrel.name = "CannonBarrel"
	barrel.position = Vector3(0.5, 0.78, 0.62)
	barrel.rotation.x = 0.30
	parent.add_child(barrel)
	_add_mesh_cylinder(barrel, 0.24, 1.80, Vector3(0.0, 0.0, -0.45), Vector3(PI / 2.0, 0.0, 0.0), dark_iron, "CannonTube")
	_add_mesh_cylinder(barrel, 0.27, 0.34, Vector3(0.0, 0.0, 0.30), Vector3(PI / 2.0, 0.0, 0.0), dark_iron, "CannonBreechBand")
	for z in [0.12, -0.55, -1.10]:
		_add_mesh_cylinder(barrel, 0.29, 0.10, Vector3(0.0, 0.0, z), Vector3(PI / 2.0, 0.0, 0.0), gold, "CannonGoldBand")
		for angle in [0.0, 1.571, 3.142, 4.712]:
			_add_stud(barrel, Vector3(cos(angle) * 0.29, sin(angle) * 0.29, z), gold, Vector3(0.0, 0.0, angle))
	_add_mesh_cylinder(barrel, 0.31, 0.22, Vector3(0.0, 0.0, -1.30), Vector3(PI / 2.0, 0.0, 0.0), iron, "CannonMuzzleRing")
	_add_mesh_cylinder(barrel, 0.20, 0.06, Vector3(0.0, 0.0, -1.42), Vector3(PI / 2.0, 0.0, 0.0), _visual_material(Color("101214")), "CannonBore")
	_add_mesh_cylinder(barrel, 0.08, 1.30, Vector3.ZERO, Vector3(0.0, 0.0, PI / 2.0), iron, "CannonTrunnion")
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.12
	knob_mesh.height = 0.24
	knob.mesh = knob_mesh
	knob.material_override = iron
	knob.position = Vector3(0.0, 0.0, 0.56)
	barrel.add_child(knob)
	_add_mesh_box(barrel, Vector3(0.10, 0.22, 0.10), Vector3(0.0, 0.30, 0.25), gold)
	var loaded := MeshInstance3D.new()
	loaded.name = "CannonBall"
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.16
	ball_mesh.height = 0.32
	loaded.mesh = ball_mesh
	loaded.material_override = dark_iron
	loaded.position = Vector3(0.0, 0.0, -1.28)
	barrel.add_child(loaded)
	var muzzle := Node3D.new()
	muzzle.name = "SiegeMuzzle"
	muzzle.position = Vector3(0.0, 0.0, -1.46)
	barrel.add_child(muzzle)


## Rebuilds the track visuals around `anchor` (the 3x3x3 neighbourhood, so
## slopes and loop pieces one level up or down re-shape too) when a piece is
## laid or removed.
func _refresh_rail_neighbours(anchor: Vector3i) -> void:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var offset := Vector3i(dx, dy, dz)
				if offset == Vector3i.ZERO:
					continue
				var neighbour := workstations.station_at_cell(anchor + offset)
				if neighbour.is_empty() or not CoasterRails.is_track_id(str(workstations.station(neighbour).get("entity_id", ""))):
					continue
				_remove_station_visual(neighbour)
				_spawn_station_visual(workstations.station(neighbour))
	# Trestle supports: a floating piece higher in this column may have
	# grown (or now needs) a post that lands on this cell.
	for drop in range(2, SUPPORT_MAX_DROP + 1):
		var above := workstations.station_at_cell(anchor + Vector3i(0, drop, 0))
		if above.is_empty() or str(workstations.station(above).get("entity_id", "")) != CoasterRails.LOOP:
			continue
		_remove_station_visual(above)
		_spawn_station_visual(workstations.station(above))


## One track style for every rail piece (owner playtest 2026-09-21: "I
## would like them updated to match the newer 'curvable' pieces"): plain
## rails, slopes and the classic loop's grounded `rail_switch` pieces draw
## with the loop renderer's style - two iron rails at +/-TRACK_GAUGE_HALF,
## TRACK_RAIL_SIZE square, an oak tie and a stone spine under each section
## (`_add_track_run`) - so a rail meets a curve, a climb or a loop in the
## same gauge, rail size, rail-top height (the ride point) and materials.
## No oak deck, no stone posts, no studs. Every joint meets at one point
## (`_track_meeting_point`) computed the same way from both sides.
const TRACK_GAUGE_HALF := 0.22
const TRACK_RAIL_SIZE := 0.10
const TRACK_CORNER_SECTIONS := 8
const TRACK_SLOPE_SECTIONS := 5


## Rail-top height of a flat piece over its cell floor (`CoasterRails.ride_point`).
const TRACK_RAIL_TOP := 0.55


## The materials every track piece is drawn with: {iron, oak, stone}.
func _track_materials() -> Dictionary:
	return {"iron": _visual_material(Color("8a939b")), "oak": _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg"), "stone": _visual_material(Color("8b929d"), "res://assets/blocks/castle_stone.svg")}


## Where a slope's rails end on the side facing `from_cell` (world): the low
## edge at rail-top height (anchor.y + 0.55) or the high edge one cell
## higher (anchor.y + 1.55) - the 45-degree line through the slope's ride
## point (anchor + (0.5, 1.05, 0.5)). Both ends sit at a plain rail's
## rail-top on their level, so rails on either level meet the slope flush.
## (`CoasterRails.slope_rail_corner` is the classic ring's tangent height,
## SLOPE_RAIL_TOP; fit C's lift of 0.5 brings the ring up to this high end.)
func _slope_rail_end(slope: Dictionary, from_cell: Vector3i) -> Vector3:
	var anchor: Vector3i = slope.get("anchor", Vector3i.ZERO)
	var high := CoasterRails.slope_high_direction(int(slope.get("rotation_quarters", 0)))
	var offset := from_cell - anchor
	var centre := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	if offset.x * high.x + offset.z * high.z > 0:
		return centre + Vector3(high) * 0.5 + Vector3.UP * (TRACK_RAIL_TOP + 0.5)
	return centre - Vector3(high) * 0.5 + Vector3.UP * (TRACK_RAIL_TOP - 0.5)


## The world point where `record`'s track toward its joined neighbour
## `other` ends - and where `other`'s track toward `record` starts, since
## both sides call this with the roles swapped: a slope's rail end on the
## other's side, else halfway between the two ride points (the shared edge's
## midpoint for two flat rails, the cell corner for a diagonal step, the
## quarter-cell shift of a lane switcher's middle).
func _track_meeting_point(record: Dictionary, other: Dictionary) -> Vector3:
	if str(other.get("entity_id", "")) == CoasterRails.SLOPE:
		return _slope_rail_end(other, record.get("anchor", Vector3i.ZERO))
	if str(record.get("entity_id", "")) == CoasterRails.SLOPE:
		return _slope_rail_end(record, other.get("anchor", Vector3i.ZERO))
	# An auto-shaped curve (elbow, lane shift) starts and ends ON the face it
	# shares with the plain rail beyond: both sides meet at the curve's end.
	var record_end := _curve_face_end(record, other)
	if record_end >= 0.0:
		return TrackCurve.point(record.get("curve", {}), record_end)
	var other_end := _curve_face_end(other, record)
	if other_end >= 0.0:
		return TrackCurve.point(other.get("curve", {}), other_end)
	return (CoasterRails.ride_point(record) + CoasterRails.ride_point(other)) * 0.5


## The parameter (0.0 or 1.0) of `record`'s curve end that lies on the face
## it shares with `other`, when `other` is the joint recorded at that end
## and the end point sits on that face (within 0.01); -1.0 otherwise (the
## curve tools' curves start and end at cell centres, so they never match).
func _curve_face_end(record: Dictionary, other: Dictionary) -> float:
	var curve: Dictionary = record.get("curve", {})
	if curve.is_empty() or other.has("curve"):
		return -1.0
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var other_anchor: Vector3i = other.get("anchor", Vector3i.ZERO)
	var offset := other_anchor - anchor
	if offset.y != 0 or absi(offset.x) + absi(offset.z) != 1:
		return -1.0
	var joints: Array = record.get("coaster_joints", [])
	for index in range(mini(2, joints.size())):
		var joint: Variant = joints[index]
		if not (joint is Array) or (joint as Array).size() != 3 or Vector3i(int(joint[0]), int(joint[1]), int(joint[2])) != offset:
			continue
		var end_t := 0.0 if index == 0 else 1.0
		if (index == 0 and float(record.get("t0", 1.0)) > 0.001) or (index == 1 and float(record.get("t1", 0.0)) < 0.999):
			continue
		var end_point := TrackCurve.point(curve, end_t)
		var face := float(anchor.x + (1 if offset.x > 0 else 0)) if offset.x != 0 else float(anchor.z + (1 if offset.z > 0 else 0))
		var along_face := end_point.x if offset.x != 0 else end_point.z
		if absf(along_face - face) < 0.01:
			return end_t
	return -1.0


## One run of track through `points` (world), drawn under `undo` (a node
## whose rotation cancels the body's, so world directions hold): two iron
## rails spread along `across` (zero = the horizontal perpendicular of the
## run at each point), a stone spine and oak ties on the side away from
## `lean` (below the rails for flat track: lean = a point above; outside the
## ring for a loop: lean = its centre).
##
## Smooth sweep (owner playtest 2026-09-21, "in these corners, the rails are
## segmented"): the rails and the spine are ONE swept mesh per run
## (`_add_track_sweep`) whose cross-section rides a frame at every point -
## tangent (the polyline's average direction there), across, up = across x
## tangent - so consecutive rings share their vertices and the twist runs
## continuously along the curve. `across_points` (one per point; empty =
## `across` everywhere) lets a curve piece hand in its binormal at each
## sampled t. Each section between two points keeps a Node3D carrying the
## meta `rail_length` (the automation's joint probe reads the rail ends from
## it) and `rail_across` ([across at its start, across at its end], world)
## with the section's oak tie under it.
func _add_track_run(undo: Node3D, body_origin: Vector3, points: Array[Vector3], across: Vector3, lean: Vector3, materials: Dictionary, across_points: Array[Vector3] = []) -> int:
	var run: Array[Vector3] = []
	var run_across: Array[Vector3] = []
	for index in range(points.size()):
		if not run.is_empty() and run[run.size() - 1].distance_to(points[index]) < 0.001:
			continue
		run.append(points[index])
		run_across.append(across_points[index] if across_points.size() == points.size() else across)
	if run.size() < 2:
		return 0
	var count := run.size()
	var tangents: Array[Vector3] = []
	var frames: Array[Vector3] = []
	for index in range(count):
		var tangent: Vector3 = run[mini(index + 1, count - 1)] - run[maxi(index - 1, 0)]
		if tangent.length() < 0.000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		tangents.append(tangent)
		var point_across: Vector3 = run_across[index]
		if point_across.length() < 0.05 or absf(point_across.normalized().dot(tangent)) > 0.95:
			point_across = tangent.cross(Vector3.UP)
			if point_across.length() < 0.05:
				point_across = Vector3.RIGHT if absf(tangent.x) < 0.95 else Vector3.FORWARD
		point_across = point_across - tangent * point_across.dot(tangent)
		point_across = point_across.normalized()
		# The profile is symmetric in across, so its sign is free: keep it
		# continuous along the run (a flat binormal follows the polyline's
		# direction, a curve's binormal its t direction - they can oppose).
		if not frames.is_empty() and point_across.dot(frames[frames.size() - 1]) < 0.0:
			point_across = -point_across
		frames.append(point_across)
	# The spine's side, once per run: away from `lean` (down for flat track,
	# outward for a ring), measured at the run's middle so it never flips
	# between rings.
	var middle := count / 2
	var up_middle: Vector3 = frames[middle].cross(tangents[middle])
	var outward := (run[middle] - lean).normalized()
	var spine_up := -1.0 if (-up_middle).dot(outward) >= 0.0 else 1.0
	_add_track_sweep(undo, body_origin, run, tangents, frames, spine_up, materials)
	var oak: Material = materials.oak
	var sections := 0
	for index in range(1, count):
		var from_point: Vector3 = run[index - 1]
		var to_point: Vector3 = run[index]
		var direction := (to_point - from_point).normalized()
		var length := from_point.distance_to(to_point)
		var section_across: Vector3 = (frames[index - 1] + frames[index])
		if section_across.length() < 0.05 or absf(section_across.normalized().dot(direction)) > 0.95:
			section_across = frames[index - 1]
		section_across = (section_across - direction * section_across.dot(direction)).normalized()
		var piece := Node3D.new()
		piece.position = (from_point + to_point) * 0.5 - body_origin
		piece.basis = Basis.looking_at(direction, section_across)
		piece.set_meta("rail_length", length)
		piece.set_meta("rail_across", [frames[index - 1], frames[index]])
		undo.add_child(piece)
		# The tie: local X is -up (looking_at puts `across` on Y), so the
		# spine's side is -spine_up along X.
		_add_mesh_box(piece, Vector3(0.10, 0.54, 0.10), Vector3(-spine_up * 0.12, 0.0, 0.0), oak)
		sections += 1
	return sections


## The swept rails and spine of one run: one ArrayMesh with three surfaces
## (left rail, right rail, spine - iron, iron, stone), each a rectangular
## cross-section swept through `points` with the frame (tangents[i],
## across[i], up[i] = across[i] x tangents[i]) at every point; the spine
## sits 0.30 along up x `spine_up`. Flat-shaded faces (four side strips
## plus end caps) built as indexed arrays: every strip shares its two
## vertices per ring between the segments on either side, so the rings
## coincide and the twist is continuous.
func _add_track_sweep(undo: Node3D, body_origin: Vector3, points: Array[Vector3], tangents: Array[Vector3], across: Array[Vector3], spine_up: float, materials: Dictionary) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var half_rail := TRACK_RAIL_SIZE * 0.5
	var profiles: Array[Array] = [[-TRACK_GAUGE_HALF, 0.0, half_rail, half_rail, materials.iron], [TRACK_GAUGE_HALF, 0.0, half_rail, half_rail, materials.iron], [0.0, spine_up * 0.30, 0.08, 0.08, materials.stone]]
	var count := points.size()
	var ups: Array[Vector3] = []
	var distances: PackedFloat32Array = [0.0]
	for index in range(count):
		ups.append(across[index].cross(tangents[index]))
		if index > 0:
			distances.append(distances[index - 1] + points[index - 1].distance_to(points[index]))
	# Godot's front faces wind clockwise seen from the front: the strip
	# order is fixed by the frame's handedness, checked once on the first
	# segment's top face.
	var flip := false
	if count >= 2:
		var a := points[0] + across[0] * half_rail + ups[0] * half_rail
		var b := points[0] - across[0] * half_rail + ups[0] * half_rail
		var c := points[1] + across[1] * half_rail + ups[1] * half_rail
		flip = (c - a).cross(b - a).dot(ups[0]) > 0.0
	for profile: Array in profiles:
		var centre_across := float(profile[0])
		var centre_up := float(profile[1])
		var half_across := float(profile[2])
		var half_up := float(profile[3])
		var corners: Array[Vector2] = [Vector2(half_across, half_up), Vector2(-half_across, half_up), Vector2(-half_across, -half_up), Vector2(half_across, -half_up)]
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		# Four side strips: two vertices per ring each, quads between rings.
		for face in range(4):
			var next_corner := (face + 1) % 4
			var base := vertices.size()
			for ring in range(count):
				var origin: Vector3 = points[ring] - body_origin + across[ring] * centre_across + ups[ring] * centre_up
				var normal: Vector3 = [ups[ring], -across[ring], -ups[ring], across[ring]][face]
				vertices.append(origin + across[ring] * corners[face].x + ups[ring] * corners[face].y)
				vertices.append(origin + across[ring] * corners[next_corner].x + ups[ring] * corners[next_corner].y)
				normals.append(normal)
				normals.append(normal)
				uvs.append(Vector2(distances[ring], 0.0))
				uvs.append(Vector2(distances[ring], 1.0))
			for ring in range(1, count):
				var a := base + (ring - 1) * 2
				var b := a + 1
				var c := base + ring * 2
				var d := c + 1
				if flip:
					indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
				else:
					indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
		# End caps.
		for cap: Array in [[0, -1.0], [count - 1, 1.0]]:
			var ring: int = cap[0]
			var cap_sign: float = cap[1]
			var origin: Vector3 = points[ring] - body_origin + across[ring] * centre_across + ups[ring] * centre_up
			var normal: Vector3 = tangents[ring] * cap_sign
			var base := vertices.size()
			for corner: Vector2 in corners:
				vertices.append(origin + across[ring] * corner.x + ups[ring] * corner.y)
				normals.append(normal)
				uvs.append(corner)
			var outward: bool = (vertices[base + 1] - vertices[base]).cross(vertices[base + 2] - vertices[base]).dot(normal) > 0.0
			if outward:
				indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
			else:
				indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, profile[4] as Material)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TrackSweep"
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	undo.add_child(mesh_instance)
	return mesh_instance



## Flat rail piece (`rail`, a flat `rail_loop` piece, a grounded
## `rail_switch`): the track style along the piece's path. From its ride
## point a run to the meeting point with every joined neighbour (the shared
## edge, a diagonal step's corner, a slope's rail end at this level, a lane
## switcher's shifted midpoint); a piece with no neighbour draws a straight
## along its placement rotation, one neighbour mirrors it. Exactly two
## neighbours at right angles on the cell's edges draw a quarter arc of
## radius 0.5 centred on the inner corner (TRACK_CORNER_SECTIONS sections,
## no centre plate) so a plain-rail corner is round like a curve piece.
## Three or four neighbours draw straight arms and a small iron plate at the
## centre so the rails read as a junction. The collision box is the rail
## block's (the player walks on rails; carts ride by the service).
func _build_rail_visual(parent: Node3D, record: Dictionary, node_name: String = "RailTrack") -> void:
	_add_collision_box(parent, Vector3(0.98, 0.56, 0.98), Vector3(0.0, -0.22, 0.0))
	if parent.get_node_or_null("Support") == null:
		_add_track_supports(parent, record)
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var tracks := CoasterRails.track_records(workstations.stations)
	var own_point := CoasterRails.ride_point(record)
	var body_origin := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	var materials := _track_materials()
	var undo := Node3D.new()
	undo.name = node_name
	undo.rotation.y = -parent.rotation.y
	parent.add_child(undo)
	var ends: Array[Vector3] = []
	var axes: Array[Vector3i] = []
	for cell: Vector3i in CoasterRails.connected_cells(record, tracks):
		var other: Dictionary = tracks.get(cell, {"anchor": cell, "entity_id": CoasterRails.FLAT})
		if CoasterRails.has_second_curve(other):
			other = CoasterRails.pair_for(other, anchor)
		ends.append(_track_meeting_point(record, other))
		var offset := cell - anchor
		axes.append(Vector3i(offset.x, 0, offset.z))
	if ends.is_empty():
		var along := Vector3(CoasterRails.switch_along(int(record.get("rotation_quarters", 0))))
		ends.append(own_point + along * 0.5)
		ends.append(own_point - along * 0.5)
	elif ends.size() == 1:
		ends.append(own_point - (ends[0] - own_point))
	var lean := own_point + Vector3.UP
	# A round corner: two edge-midpoint ends on perpendicular axes.
	if ends.size() == 2 and axes.size() == 2 and axes[0].length_squared() == 1 and axes[1].length_squared() == 1 and axes[0].x * axes[1].x + axes[0].z * axes[1].z == 0:
		var a := Vector3(axes[0])
		var b := Vector3(axes[1])
		if ends[0].is_equal_approx(own_point + a * 0.5) and ends[1].is_equal_approx(own_point + b * 0.5):
			var corner := own_point + (a + b) * 0.5
			var arc: Array[Vector3] = []
			for section in range(TRACK_CORNER_SECTIONS + 1):
				var angle := PI * 0.5 * float(section) / float(TRACK_CORNER_SECTIONS)
				arc.append(corner - b * 0.5 * cos(angle) - a * 0.5 * sin(angle))
			_add_track_run(undo, body_origin, arc, Vector3.ZERO, lean, materials)
			return
	if ends.size() == 2:
		# One run end to end through the ride point: a straight, or a mitred
		# bend at the centre for a diagonal step, in one swept mesh.
		var through: Array[Vector3] = [ends[0], own_point, ends[1]]
		_add_track_run(undo, body_origin, through, Vector3.ZERO, lean, materials)
		return
	for end: Vector3 in ends:
		var run: Array[Vector3] = [own_point, end]
		_add_track_run(undo, body_origin, run, Vector3.ZERO, lean, materials)
	if ends.size() >= 3:
		_add_mesh_box(undo, Vector3(0.54, 0.06, 0.54), own_point - body_origin + Vector3(0.0, -0.02, 0.0), materials.iron, "JunctionPlate")


## Lane Switcher piece (owner 2026-09-20; one track style 2026-09-21): the
## rail renderer along the piece's ride line - the middles' ride point is a
## quarter cell onto the diagonal (`CoasterRails.switch_mid_shift`), so the
## four pieces read as one track shifting a lane. The middles' node keeps
## the name "SwitchRails".
func _build_rail_switch_visual(parent: Node3D, record: Dictionary) -> void:
	var role := str(record.get("switch_role", ""))
	_build_rail_visual(parent, record, "SwitchRails" if role == "mid_a" or role == "mid_b" else "RailTrack")


## Rail slope (one track style 2026-09-21): the rails, ties and spine along
## the 45-degree incline from the low edge (rail-top height of this level) to
## the high edge (rail-top height one level up), in TRACK_SLOPE_SECTIONS
## sections (a tie every ~0.3), so the flat rails on both levels meet it
## flush; a short trestle bent near the high end (`_add_track_supports`). The
## collision incline lets the player walk up it.
func _build_rail_slope_visual(parent: Node3D, record: Dictionary) -> void:
	var incline := _add_collision_box(parent, Vector3(0.90, 0.30, 1.30), Vector3(0.0, 0.55, 0.0))
	incline.rotation.x = PI / 4.0
	_add_track_supports(parent, record)
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var high := CoasterRails.slope_high_direction(int(record.get("rotation_quarters", 0)))
	var low_end := _slope_rail_end(record, anchor - high)
	var high_end := _slope_rail_end(record, anchor + high)
	var body_origin := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	var undo := Node3D.new()
	undo.name = "RailTrack"
	undo.rotation.y = -parent.rotation.y
	parent.add_child(undo)
	var points: Array[Vector3] = []
	for section in range(TRACK_SLOPE_SECTIONS + 1):
		points.append(low_end.lerp(high_end, float(section) / float(TRACK_SLOPE_SECTIONS)))
	_add_track_run(undo, body_origin, points, Vector3.ZERO, CoasterRails.ride_point(record) + Vector3.UP, _track_materials())


## Coaster rails side project: a loop piece draws a short pair of rails from
## its centre toward every track piece it joins (CoasterRails joints), pitched
## to the joint's direction, so a ring of pieces reads as a polygonal loop.
## A piece whose joints all lie flat is drawn as an ordinary rail block.
## A snapped arch piece (owner 2026-09-20): its rails follow the loop's true
## circle from halfway to the previous piece to halfway to the next, as a
## few short straight sections, so the loop reads as a smooth ring instead
## of a cell-centre zigzag. Wooden ties every section; a post at the centre.
const LOOP_ARC_SECTIONS := 8


## A loop-element piece (owner 2026-09-20, "prettier"): two iron rails
## with wooden ties and a stone spine on the outer side (`_add_track_run`),
## running from the piece's own point to halfway toward each neighbour -
## along the curve for same-curve pieces, along the true circle for ring
## pieces (short sections), to the shared meeting point (`_track_meeting_
## point`) for anything else - and, for the classic ring, all the way to a
## slope's rail corner so the ring continues the slope's incline without a
## kink. No posts or blocks. Plain rails, slopes and switches draw with the
## same run helper (one track style, 2026-09-21).
## `record` is the one-curve view to draw (`CoasterRails.pair_for`: a
## crossing's shared cell is drawn once per curve, as "LoopTrack" and
## "LoopTrackB"); `joined` the joined cells of that curve.
func _build_loop_track_visual(parent: Node3D, record: Dictionary, joined: Array[Vector3i], node_name: String = "LoopTrack") -> void:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var tracks := CoasterRails.track_records(workstations.stations)
	if parent.get_node_or_null("LoopTrack") == null:
		_add_collision_box(parent, Vector3(0.70, 0.70, 0.70), Vector3.ZERO)
	var materials := _track_materials()
	var undo := Node3D.new()
	undo.name = node_name
	undo.rotation.y = -parent.rotation.y
	parent.add_child(undo)
	var body_origin := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	var own_point := CoasterRails.ride_point(record)
	var lean := CoasterRails.lean_center(record)
	var curve: Dictionary = record.get("curve", {})
	var pair_key := str(record.get("pair", "a"))
	if not curve.is_empty():
		# Lean straight at the curve's centre of curvature (any bank).
		lean = own_point + TrackCurve.up_at(curve, TrackCurve.piece_t(record))
	var round := record.has("loop_center")
	# Odd quarters: the loop lies in the x-y plane (axis x, normal z).
	var plane_axis := Vector3(1.0, 0.0, 0.0) if int(record.get("rotation_quarters", 0)) % 2 == 1 else Vector3(0.0, 0.0, 1.0)
	var across := Vector3(0.0, 0.0, 1.0) if plane_axis.x != 0.0 else Vector3(1.0, 0.0, 0.0)
	if not curve.is_empty():
		# Any curve (a flat bend as much as a loop): the rails spread along
		# the curve's binormal (tangent x rider up), so a banked flat curve
		# tilts its rails into the bend and a loop keeps its plane normal.
		var piece_t := TrackCurve.piece_t(record)
		var binormal := TrackCurve.tangent(curve, piece_t).cross(TrackCurve.up_at(curve, piece_t))
		if binormal.length() > 0.05:
			across = binormal.normalized()
	var plane_across := plane_axis
	# Every run starts at the piece's own point with the piece's across
	# (the binormal at piece_t for a curve); each further point carries its
	# own across - the curve's binormal at that t for a same-curve neighbour,
	# zero (= the flat binormal of the run there) at the meeting point with
	# anything else - so the frame twists continuously along the curve and
	# matches the neighbour's frame at the shared point. Two runs (the usual
	# piece) merge end to end into one sweep through the own point.
	var runs: Array[Array] = []
	for cell: Vector3i in joined:
		var other: Dictionary = tracks.get(cell, {"anchor": cell, "entity_id": CoasterRails.FLAT})
		if CoasterRails.has_second_curve(other):
			# A crossing's shared neighbour: the curve of the pair this cell is on.
			other = CoasterRails.pair_for(other, anchor, pair_key)
		var points: Array[Vector3] = [own_point]
		var frames: Array[Vector3] = [across]
		if round and str(other.get("entity_id", "")) == CoasterRails.SLOPE:
			# The classic ring (fit B / C) meets the slope a little above its
			# tangent corner; the last bit of rail bridges the lift.
			points.append(CoasterRails.slope_rail_corner(other) + Vector3.UP * float(record.get("loop_lift", 0.0)))
			points.append(CoasterRails.slope_rail_corner(other))
			frames.append(across)
			frames.append(across)
		elif not curve.is_empty() and other.has("curve") and str(JSON.stringify(other.get("curve"))) == str(JSON.stringify(curve)):
			# Same curve: follow it from this piece's t halfway to the other's,
			# the binormal at every sampled t (both pieces sample the same
			# halfway t, so their end rings coincide).
			var own_t := TrackCurve.piece_t(record)
			var other_t := TrackCurve.piece_t(other)
			for section in range(1, LOOP_ARC_SECTIONS + 1):
				var t := own_t + (other_t - own_t) * 0.5 * float(section) / float(LOOP_ARC_SECTIONS)
				points.append(TrackCurve.point(curve, t))
				var binormal := TrackCurve.tangent(curve, t).cross(TrackCurve.up_at(curve, t))
				frames.append(binormal.normalized() if binormal.length() > 0.05 else across)
		elif round:
			var other_angle := CoasterRails.arc_angle(record, CoasterRails.arc_point(record, CoasterRails.ride_point(other)))
			var own_angle := CoasterRails.arc_angle(record, own_point)
			var delta := wrapf(other_angle - own_angle, -PI, PI)
			var arc := CoasterRails.arc_of(record)
			for section in range(1, LOOP_ARC_SECTIONS + 1):
				var angle := own_angle + delta * 0.5 * float(section) / float(LOOP_ARC_SECTIONS)
				var spoke := plane_across * cos(angle) + Vector3.UP * sin(angle)
				points.append(Vector3(arc.center) + spoke * float(arc.radius))
				frames.append(across)
		else:
			# Any other neighbour (a plain rail, a slope's rail end, another
			# tool's piece): a straight to the shared meeting point, met
			# upright (the flat binormal there, as the neighbour draws it) -
			# along the curve first when it ends on the shared face
			# (auto-shaped elbows and lane shifts).
			var face_end := _curve_face_end(record, other) if not curve.is_empty() else -1.0
			if face_end >= 0.0:
				var own_t := TrackCurve.piece_t(record)
				for section in range(1, LOOP_ARC_SECTIONS + 1):
					var t := own_t + (face_end - own_t) * float(section) / float(LOOP_ARC_SECTIONS)
					points.append(TrackCurve.point(curve, t))
					var binormal := TrackCurve.tangent(curve, t).cross(TrackCurve.up_at(curve, t))
					frames.append(binormal.normalized() if binormal.length() > 0.05 else across)
			else:
				points.append(_track_meeting_point(record, other))
				frames.append(across if round or curve.is_empty() else Vector3.ZERO)
		runs.append([points, frames])
	if runs.size() == 2:
		var merged_points: Array[Vector3] = []
		var merged_frames: Array[Vector3] = []
		var first_points: Array[Vector3] = runs[0][0]
		var first_frames: Array[Vector3] = runs[0][1]
		for index in range(first_points.size() - 1, -1, -1):
			merged_points.append(first_points[index])
			merged_frames.append(first_frames[index])
		var second_points: Array[Vector3] = runs[1][0]
		var second_frames: Array[Vector3] = runs[1][1]
		for index in range(1, second_points.size()):
			merged_points.append(second_points[index])
			merged_frames.append(second_frames[index])
		_add_track_run(undo, body_origin, merged_points, across, lean, materials, merged_frames)
		return
	for run: Array in runs:
		var run_points: Array[Vector3] = run[0]
		var run_frames: Array[Vector3] = run[1]
		_add_track_run(undo, body_origin, run_points, across, lean, materials, run_frames)


func _build_loop_arc_visual(parent: Node3D, record: Dictionary, joined: Array[Vector3i]) -> void:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var tracks := CoasterRails.track_records(workstations.stations)
	_add_collision_box(parent, Vector3(0.70, 0.70, 0.70), Vector3.ZERO)
	var iron := _visual_material(Color("8a939b"))
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var undo := Node3D.new()
	undo.name = "LoopArc"
	undo.rotation.y = -parent.rotation.y
	parent.add_child(undo)
	var body_origin := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	var own_point := CoasterRails.ride_point(record)
	var own_angle := CoasterRails.arc_angle(record, own_point)
	var across := Vector3(1.0, 0.0, 0.0) if int(record.get("rotation_quarters", 0)) % 2 == 1 else Vector3(0.0, 0.0, 1.0)
	_add_mesh_box(undo, Vector3(0.16, 0.16, 0.16), own_point - body_origin, iron)
	_add_stud(undo, own_point - body_origin + Vector3(0.0, 0.10, 0.0), gold, Vector3.ZERO)
	for cell: Vector3i in joined:
		var other: Dictionary = tracks.get(cell, {"anchor": cell, "entity_id": CoasterRails.FLAT})
		var other_point := CoasterRails.arc_point(record, CoasterRails.ride_point(other))
		var other_angle := CoasterRails.arc_angle(record, other_point)
		var delta := wrapf(other_angle - own_angle, -PI, PI)
		# From this piece's point to halfway toward the neighbour, in sections.
		var previous_point := own_point
		for section in range(1, LOOP_ARC_SECTIONS + 1):
			var angle := own_angle + delta * 0.5 * float(section) / float(LOOP_ARC_SECTIONS)
			var arc := CoasterRails.arc_of(record)
			var spoke := across * cos(angle) + Vector3.UP * sin(angle)
			var point: Vector3 = arc.center + spoke * float(arc.radius)
			var direction := point - previous_point
			var length := direction.length()
			if length < 0.001:
				continue
			direction = direction.normalized()
			var side := direction.cross(Vector3.UP)
			if side.length() < 0.01:
				side = across
			var piece := Node3D.new()
			piece.position = (previous_point + point) * 0.5 - body_origin
			piece.basis = Basis.looking_at(direction, side.normalized())
			undo.add_child(piece)
			for offset in [-0.22, 0.22]:
				_add_mesh_box(piece, Vector3(0.10, 0.10, length + 0.02), Vector3(0.0, offset, 0.0), iron)
			if section % 2 == 0:
				_add_mesh_box(piece, Vector3(0.08, 0.60, 0.10), Vector3.ZERO, oak)
			previous_point = point


## Automatic trestle supports (CoasterCraft card 8; real trusses after the
## owner playtest 2026-09-20 item 7, docs/COASTER_RAILS.md): a floating
## curve piece grows a timber/steel trestle BENT from its rails straight down
## to the first solid voxel or track cell below (at most SUPPORT_MAX_DROP
## cells; none when nothing is found): two stone legs, one under each rail
## (+/-SUPPORT_LEG_OFFSET across the piece's travel direction), a stone pad
## under each on the floor, a gold stud where each leg meets the rail, and
## steel sway bracing between the legs every SUPPORT_BRACE_EVERY cells from
## the floor up (a horizontal tie and an X of two diagonals per panel) plus
## a cap tie just under the rails. Bents taller than SUPPORT_SPLAY_MIN_HEIGHT
## splay their legs outward toward the floor (SUPPORT_SPLAY_PER_CELL per cell
## of height; the top stays under the rails). Longitudinal bracing ties a
## bent to the NEXT bent along the curve (the piece's forward joint, drawn
## once per bay): a stringer per tie level on each side and one diagonal per
## bay, alternating direction bay to bay. Skipped for inverted pieces (their
## up more than 90 degrees from world up - the legs would cross the loop)
## and for pieces standing within two cells above another piece of the same
## curve. Visual only, no collision; the bent lives in a `Support` node
## under the piece's node (children `Post` / `Post2`, `Tie`, `Diagonal`,
## `Stringer`, `Pad`) so dismantling removes it. One BoxMesh is shared per
## strut size (`_support_meshes`).
const SUPPORT_MAX_DROP := 24
const SUPPORT_BRACE_EVERY := 2
const SUPPORT_LEG_OFFSET := 0.32
const SUPPORT_SPLAY_MIN_HEIGHT := 4.0
const SUPPORT_SPLAY_PER_CELL := 0.06
const SUPPORT_CAP_DROP := 0.14
const SUPPORT_LEG_SIZE := 0.10
const SUPPORT_BRACE_SIZE := 0.07
var _support_meshes: Dictionary = {}


## The bent a floating piece would stand on: {point, floor_y, top_y, height,
## side, along, splay, levels (tie heights above the floor, the cap last)}
## or {} when the piece gets no support (see _add_track_supports). `tracks`
## is CoasterRails.track_records(...) so a neighbour's bent can be found
## without building it.
func _support_bent(record: Dictionary, tracks: Dictionary) -> Dictionary:
	var entity_id := str(record.get("entity_id", ""))
	if not CoasterRails.is_track_id(entity_id):
		return {}
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var curve: Dictionary = record.get("curve", {})
	var point := CoasterRails.ride_point(record)
	var up := Vector3.UP
	var along := Vector3.ZERO
	if entity_id == CoasterRails.SLOPE:
		# One track style (2026-09-21): a slope's bent stands near its high
		# end, on the 45-degree rail line (its low end rests on the ground).
		var high := Vector3(CoasterRails.slope_high_direction(int(record.get("rotation_quarters", 0))))
		point += high * 0.3 + Vector3.UP * 0.3
		along = high
	elif entity_id != CoasterRails.LOOP and curve.is_empty():
		# A plain rail or switch piece: along its first horizontal joint, else
		# its placement rotation (grounded pieces skip the bent anyway).
		along = Vector3(CoasterRails.switch_along(int(record.get("rotation_quarters", 0))))
		for cell: Vector3i in CoasterRails.connected_cells(record, tracks):
			var offset := Vector3(cell - anchor)
			offset.y = 0.0
			if offset.length() > 0.5:
				along = offset.normalized()
				break
	if not curve.is_empty():
		var t := TrackCurve.piece_t(record)
		up = TrackCurve.up_at(curve, t)
		var tangent := TrackCurve.tangent(curve, t)
		along = Vector3(tangent.x, 0.0, tangent.z)
		if along.length() < 0.05:
			var curve_along := TrackCurve.along_of(curve)
			along = Vector3(curve_along.x, 0.0, curve_along.z)
	elif CoasterRails.lean_center(record) != Vector3.INF:
		up = (CoasterRails.lean_center(record) - point).normalized()
	if up.dot(Vector3.UP) < 0.0:
		return {}
	var side := Vector3.RIGHT
	if along.length() >= 0.05:
		along = along.normalized()
		side = Vector3(-along.z, 0.0, along.x)
	else:
		# A ring piece travels in its loop's plane: the lateral direction is
		# the plane axis.
		side = Vector3(CoasterRails.loop_plane_axis(int(record.get("rotation_quarters", 0))))
		along = Vector3(-side.z, 0.0, side.x)
	var column := Vector3i(floori(point.x), anchor.y, floori(point.z))
	var floor_y := INF
	var own_curve := JSON.stringify(curve) if not curve.is_empty() else ""
	for drop in range(1, SUPPORT_MAX_DROP + 1):
		var cell := column + Vector3i(0, -drop, 0)
		var other: Dictionary = tracks.get(cell, {})
		if not other.is_empty():
			if drop <= 2 and not curve.is_empty() and other.has("curve") and str(JSON.stringify(other.get("curve"))) == own_curve:
				return {}
			# Owner 2026-09-21: a track below is never stood on - no bent here
			# (a hole in the truss with room for a cart and rider).
			return {}
		# The same for track within a cell sideways of the column (a cart
		# and rider need the room), unless it is this piece's own curve.
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var beside: Dictionary = tracks.get(cell + Vector3i(dx, 0, dz), {})
				if beside.is_empty():
					continue
				if beside.has("curve") and str(JSON.stringify(beside.get("curve"))) == own_curve:
					continue
				return {}
		var query := world.query_cell(cell)
		if query.get("state") != "LOADED":
			return {}
		var voxel_id := int(query.get("voxel_id", 0))
		if voxel_id != 0 and not WorldAdapter.PASSABLE_BLOCKS.has(WorldAdapter.BLOCK_NAMES[voxel_id]):
			floor_y = float(cell.y) + 1.0
			break
	if floor_y == INF:
		return {}
	var top_y := point.y - 0.08
	var height := top_y - floor_y
	if height < 0.5:
		return {}
	var levels: Array[float] = []
	var level := float(SUPPORT_BRACE_EVERY)
	while level < height - 0.7:
		levels.append(level)
		level += float(SUPPORT_BRACE_EVERY)
	levels.append(height - SUPPORT_CAP_DROP)
	var splay := SUPPORT_SPLAY_PER_CELL if height > SUPPORT_SPLAY_MIN_HEIGHT else 0.0
	return {"point": point, "floor_y": floor_y, "top_y": top_y, "height": height, "side": side, "along": along, "splay": splay, "levels": levels}


## World point on a bent's leg (`lateral` -1 left / +1 right of travel) at
## `rise` cells above the bent's floor: the legs splay outward toward the
## floor, the top stays SUPPORT_LEG_OFFSET from the track centre.
func _bent_leg_point(bent: Dictionary, lateral: float, rise: float) -> Vector3:
	var point: Vector3 = bent.point
	var height: float = bent.height
	var offset: float = SUPPORT_LEG_OFFSET + float(bent.splay) * maxf(height - rise, 0.0)
	var side: Vector3 = bent.side
	return Vector3(point.x, float(bent.floor_y) + rise, point.z) + side * lateral * offset


func _add_track_supports(parent: Node3D, record: Dictionary) -> void:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var tracks := CoasterRails.track_records(workstations.stations)
	var bent := _support_bent(record, tracks)
	if bent.is_empty():
		return
	var rig := Node3D.new()
	rig.name = "Support"
	rig.rotation.y = -parent.rotation.y
	parent.add_child(rig)
	var body_origin := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	var names: Dictionary = {}
	var stone := _visual_material(Color("8b929d"), "res://assets/blocks/castle_stone.svg")
	var steel := _visual_material(Color("545a63"), "")
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var height: float = bent.height
	var levels: Array[float] = bent.levels
	var along: Vector3 = bent.along
	var side: Vector3 = bent.side
	# The two legs, their pads and studs.
	for lateral: float in [-1.0, 1.0]:
		var foot := _bent_leg_point(bent, lateral, 0.0)
		var top := _bent_leg_point(bent, lateral, height)
		_add_support_strut(rig, foot - body_origin, top - body_origin, SUPPORT_LEG_SIZE, stone, _support_name(names, "Post"), along)
		_add_mesh_box(rig, Vector3(0.4, 0.15, 0.4), foot - body_origin + Vector3(0.0, 0.075, 0.0), stone, _support_name(names, "Pad"), _support_mesh(Vector3(0.4, 0.15, 0.4)))
		_add_stud(rig, top - body_origin + Vector3(0.0, 0.02, 0.0), gold, Vector3.ZERO)
	# Sway bracing between the legs: a tie per level and an X per panel
	# (floor to first tie, then tie to tie).
	var previous := 0.0
	for level: float in levels:
		_add_support_strut(rig, _bent_leg_point(bent, -1.0, level) - body_origin, _bent_leg_point(bent, 1.0, level) - body_origin, SUPPORT_BRACE_SIZE, steel, _support_name(names, "Tie"), along)
		if level - previous > 0.6:
			_add_support_strut(rig, _bent_leg_point(bent, -1.0, previous) - body_origin, _bent_leg_point(bent, 1.0, level) - body_origin, SUPPORT_BRACE_SIZE, steel, _support_name(names, "Diagonal"), along)
			_add_support_strut(rig, _bent_leg_point(bent, 1.0, previous) - body_origin, _bent_leg_point(bent, -1.0, level) - body_origin, SUPPORT_BRACE_SIZE, steel, _support_name(names, "Diagonal"), along)
		previous = level
	# No longitudinal bracing (owner 2026-09-21: "stick to vertical truss
	# only") - each bent stands alone; a piece over other track has none.



## Unique child names for a bent's struts: "Tie", "Tie2", "Tie3"... (a
## repeated name would be replaced by "@MeshInstance3D@<id>").
func _support_name(names: Dictionary, base: String) -> String:
	var count := int(names.get(base, 0)) + 1
	names[base] = count
	return base if count == 1 else base + str(count)


## One BoxMesh per strut size for the trestles (a tall climb is ~1000 struts).
func _support_mesh(size: Vector3) -> BoxMesh:
	var key := Vector3(snappedf(size.x, 0.001), snappedf(size.y, 0.001), snappedf(size.z, 0.001))
	var cached: BoxMesh = _support_meshes.get(key)
	if cached == null:
		cached = BoxMesh.new()
		cached.size = key
		_support_meshes[key] = cached
	return cached


## A square strut of `thickness` from `from` to `to` (rig-local), its box's
## Y along the strut and its X across `reference` (a direction perpendicular
## to the strut's plane, so the faces line up with the trestle).
func _add_support_strut(rig: Node3D, from: Vector3, to: Vector3, thickness: float, material: Material, node_name: String, reference: Vector3) -> MeshInstance3D:
	var delta := to - from
	var length := delta.length()
	var box := _add_mesh_box(rig, Vector3(thickness, length, thickness), (from + to) * 0.5, material, node_name, _support_mesh(Vector3(thickness, length, thickness)))
	if length < 0.001:
		return box
	var y := delta / length
	var ref := reference
	if absf(ref.dot(y)) > 0.95:
		ref = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	box.basis = Basis(x, y, z)
	return box


func _build_rail_loop_visual(parent: Node3D, record: Dictionary) -> void:
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	_add_track_supports(parent, record)
	var joined := CoasterRails.connected_cells(record, CoasterRails.track_records(workstations.stations))
	# Curve pieces (TrackCurve) and classic loop-ring pieces share one track
	# style.
	if CoasterRails.has_second_curve(record):
		# A crossing's shared cell: both curves, each with its own joints.
		for pair_key in ["a", "b"]:
			var pair := CoasterRails.pair_for(record, Vector3i.MAX, pair_key)
			var pair_joined: Array[Vector3i] = []
			for cell: Vector3i in joined:
				if (pair.joints as Array).has(cell):
					pair_joined.append(cell)
			_build_loop_track_visual(parent, pair, pair_joined, "LoopTrack" if pair_key == "a" else "LoopTrackB")
		return
	if record.has("curve") or CoasterRails.lean_center(record) != Vector3.INF:
		_build_loop_track_visual(parent, record, joined)
		return
	# Straight or cornered on one level: an ordinary rail. A diagonal joint
	# (the 45-degree step into or out of a loop) or a climb draws arms.
	var flat := true
	for cell: Vector3i in joined:
		if cell.y != anchor.y:
			flat = false
	if flat:
		_build_rail_visual(parent, record)
		return
	_add_collision_box(parent, Vector3(0.70, 0.70, 0.70), Vector3.ZERO)
	var iron := _visual_material(Color("8a939b"))
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var across := Vector3(Vector3i(1, 0, 0) if CoasterRails.loop_plane_axis(int(record.get("rotation_quarters", 0))).x == 0 else Vector3i(0, 0, 1))
	# The body may carry a placement rotation; undo it so world-axis arms line up.
	var undo := Node3D.new()
	undo.name = "LoopArms"
	undo.rotation.y = -parent.rotation.y
	parent.add_child(undo)
	_add_mesh_box(undo, Vector3(0.20, 0.20, 0.20), Vector3.ZERO, iron)
	_add_stud(undo, Vector3(0.0, 0.12, 0.0), gold, Vector3.ZERO)
	for cell: Vector3i in joined:
		var direction := Vector3(cell - anchor)
		var length := direction.length() * 0.5
		direction = direction.normalized()
		var side := direction.cross(Vector3.UP)
		if side.length() < 0.01:
			side = across
		side = side.normalized()
		var arm := Node3D.new()
		arm.basis = Basis.looking_at(direction, side)
		undo.add_child(arm)
		for offset in [-0.22, 0.22]:
			_add_mesh_box(arm, Vector3(0.10, 0.10, length), Vector3(0.0, offset, -length * 0.5), iron)
		_add_mesh_box(arm, Vector3(0.08, 0.60, 0.10), Vector3(0.0, 0.0, -length * 0.55), oak)


## Coaster rails side project: an oak-and-iron mine cart on four wheels under
## a "CartRig" node that CoasterCartService moves along the track. The rig's
## origin is the wheel contact point; the model faces -z.
func _build_mine_cart_visual(parent: Node3D, cargo: Dictionary = {}) -> void:
	_add_collision_box(parent, Vector3(0.90, 0.90, 0.90), Vector3(0.0, -0.30, 0.0))
	var rig := Node3D.new()
	rig.name = "CartRig"
	# The body centre sits 1.5 over the rail cell floor; the rail top is 0.55.
	rig.position = Vector3(0.0, -0.95, 0.0)
	parent.add_child(rig)
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var iron := _visual_material(Color("7b838c"))
	var dark_iron := _visual_material(Color("2f353b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	for x in [-0.26, 0.26]:
		for z in [-0.28, 0.28]:
			_add_mesh_cylinder(rig, 0.12, 0.08, Vector3(x, 0.12, z), Vector3(0.0, 0.0, PI / 2.0), dark_iron, "CartWheel")
	_add_mesh_box(rig, Vector3(0.60, 0.08, 0.72), Vector3(0.0, 0.22, 0.0), dark_iron)
	_add_mesh_box(rig, Vector3(0.56, 0.08, 0.76), Vector3(0.0, 0.30, 0.0), oak)
	for x in [-0.33, 0.33]:
		var wall := _add_mesh_box(rig, Vector3(0.06, 0.42, 0.80), Vector3(x, 0.52, 0.0), oak)
		wall.rotation.z = -0.12 if x > 0.0 else 0.12
	for z in [-0.40, 0.40]:
		var end_wall := _add_mesh_box(rig, Vector3(0.74, 0.42, 0.06), Vector3(0.0, 0.52, z), oak)
		end_wall.rotation.x = 0.12 if z > 0.0 else -0.12
	_add_mesh_box(rig, Vector3(0.82, 0.06, 0.92), Vector3(0.0, 0.72, 0.0), iron)
	_add_mesh_box(rig, Vector3(0.82, 0.06, 0.92), Vector3(0.0, 0.40, 0.0), iron)
	for x in [-0.42, 0.42]:
		for z in [-0.30, 0.30]:
			_add_stud(rig, Vector3(x, 0.72, z), gold, Vector3(0.0, 0.0, PI / 2.0))
	# The cargo heap (docs/INDUSTRY.md): under the rig so it rides along.
	var heap := Node3D.new()
	heap.name = "Cargo"
	heap.position = Vector3(0.0, 0.44, 0.0)
	rig.add_child(heap)
	_fill_cart_cargo_visual(heap, cargo)


## Ore colours for the cargo heap, by the dominant item; other items grey.
const CARGO_COLORS := {"iron_ore": Color("8a6f5c"), "gold_ore": Color("d9b23a"), "coal": Color("232528")}


## Rebuilds the heap's lumps for `cargo` ({item_id: count}): colour from the
## dominant item, size from the fill (0..CART_CARGO); hidden when empty. The
## three lumps stay as nodes even when empty so the cart's part count holds.
func _fill_cart_cargo_visual(heap: Node3D, cargo: Dictionary) -> void:
	for child in heap.get_children():
		heap.remove_child(child)
		child.queue_free()
	var total := 0
	var dominant := ""
	var dominant_count := 0
	for item_id: String in cargo.keys():
		var count := int(cargo[item_id])
		total += count
		if count > dominant_count:
			dominant = item_id
			dominant_count = count
	var fill := clampf(float(total) / float(CoasterCartService.CART_CARGO), 0.0, 1.0)
	var color: Color = CARGO_COLORS.get(dominant, Color("7d8288"))
	var texture := "res://assets/blocks/iron_ore.svg" if dominant == "iron_ore" else ""
	var ore := _visual_material(color, texture)
	var scale := 0.55 + 0.45 * fill
	for lump in [Vector3(-0.14, 0.18, -0.16), Vector3(0.12, 0.22, 0.10), Vector3(0.02, 0.16, -0.02)]:
		var stone := _add_mesh_box(heap, Vector3(0.22, 0.22, 0.22), Vector3(lump.x, lump.y * scale, lump.z), ore, "CargoLump")
		stone.rotation = Vector3(0.4, 0.6, 0.2)
		stone.scale = Vector3.ONE * scale
	heap.visible = total > 0


## Storage network card: a siege weapon took munitions from the storage beside
## it - say so on the HUD when the weapon is near the player (once per reload).
func _on_storage_reloaded(_instance_id: String, anchor: Vector3i, message: String) -> void:
	if player == null or (Vector3(anchor) + Vector3(0.5, 0.5, 0.5)).distance_to(player.global_position) > HAUL_NOTICE_RANGE:
		return
	_on_interaction_feedback(message)


## A cart loaded or unloaded (CoasterCartService.cargo_changed): rebuild the
## heap and, near the player, say so on the HUD (one line per second).
func _on_cart_cargo_changed(instance_id: String, moved: Dictionary, loaded: bool, cell: Vector3i) -> void:
	var body: Node3D = _station_visuals.get(instance_id)
	if body != null and is_instance_valid(body):
		var heap: Node3D = body.get_node_or_null("CartRig/Cargo")
		if heap != null:
			_fill_cart_cargo_visual(heap, workstations.station(instance_id).get("cargo", {}))
	if player == null or (Vector3(cell) + Vector3(0.5, 0.5, 0.5)).distance_to(player.global_position) > HAUL_NOTICE_RANGE:
		return
	var now := Time.get_ticks_msec()
	if now - _haul_notice_msec < 1000:
		return
	_haul_notice_msec = now
	var parts: Array[String] = []
	for item_id: String in moved.keys():
		parts.append("%d %s" % [int(moved[item_id]), registry.display_name(item_id).to_lower()])
	_on_interaction_feedback("Cart %s %s" % ["loaded" if loaded else "unloaded", ", ".join(parts)])


## Coaster car and hero (docs/COASTER_CAR_AND_HERO.md), from the owner's
## coaster_car.webp: a grey stone-framed wooden ride car with gold studs, a
## blue banner with a gold diamond on the stone nose, a gold spike, four
## gold-hub wheels and a gold safety bar, under a "CartRig" node that
## CoasterCartService moves along the track (rig origin at the wheel contact
## point; the model faces -z). The rig's "Seat" node is where the riding hero
## sits, in the cavity between the bar and the high seat back.
func _build_coaster_car_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(0.90, 0.90, 0.90), Vector3(0.0, -0.30, 0.0))
	var rig := Node3D.new()
	rig.name = "CartRig"
	rig.position = Vector3(0.0, -0.95, 0.0)
	parent.add_child(rig)
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var oak_dark := _visual_material(Color("7d4a20"), "res://assets/blocks/planks.svg")
	var stone := _visual_material(Color("8c9298"), "res://assets/blocks/castle_stone.svg")
	var stone_dark := _visual_material(Color("5d646b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var banner := _visual_material(Color("2a58c8"), "", Color("1d3f96"))
	# Wheels: stone discs with gold hubs.
	for x in [-0.31, 0.31]:
		for z in [-0.28, 0.30]:
			_add_mesh_cylinder(rig, 0.14, 0.08, Vector3(x, 0.14, z), Vector3(0.0, 0.0, PI / 2.0), stone_dark, "CarWheel")
			_add_mesh_cylinder(rig, 0.06, 0.10, Vector3(x, 0.14, z), Vector3(0.0, 0.0, PI / 2.0), gold, "CarHub")
	# Chassis and floor.
	_add_mesh_box(rig, Vector3(0.62, 0.08, 0.90), Vector3(0.0, 0.24, 0.0), stone_dark)
	_add_mesh_box(rig, Vector3(0.58, 0.06, 0.78), Vector3(0.0, 0.31, 0.04), oak)
	# Wooden body: side walls, a high seat back framed in stone.
	for x in [-0.30, 0.30]:
		_add_mesh_box(rig, Vector3(0.06, 0.34, 0.60), Vector3(x, 0.50, 0.06), oak, "CarSide")
		_add_mesh_box(rig, Vector3(0.09, 0.08, 0.66), Vector3(x, 0.69, 0.06), stone, "CarSideRail")
		_add_mesh_box(rig, Vector3(0.12, 0.50, 0.12), Vector3(x * 1.08, 0.60, 0.38), stone, "CarRearPost")
		_add_mesh_box(rig, Vector3(0.12, 0.40, 0.12), Vector3(x * 1.08, 0.50, -0.22), stone, "CarFrontPost")
		_add_stud(rig, Vector3(x * 1.30, 0.66, 0.38), gold, Vector3(0.0, 0.0, PI / 2.0))
		_add_stud(rig, Vector3(x * 1.26, 0.56, -0.22), gold, Vector3(0.0, 0.0, PI / 2.0))
		_add_stud(rig, Vector3(x * 1.20, 0.52, 0.08), gold, Vector3(0.0, 0.0, PI / 2.0))
	_add_mesh_box(rig, Vector3(0.60, 0.50, 0.06), Vector3(0.0, 0.62, 0.38), oak_dark, "CarSeatBack")
	_add_mesh_box(rig, Vector3(0.70, 0.10, 0.12), Vector3(0.0, 0.90, 0.38), stone, "CarBackFrame")
	_add_stud(rig, Vector3(0.0, 0.90, 0.45), gold, Vector3(PI / 2.0, 0.0, 0.0))
	# The seat cavity: a bench and the rider's seat node.
	_add_mesh_box(rig, Vector3(0.48, 0.08, 0.30), Vector3(0.0, 0.40, 0.18), oak_dark, "CarBench")
	var seat := Node3D.new()
	seat.name = "Seat"
	seat.position = Vector3(0.0, 0.44, 0.14)
	rig.add_child(seat)
	# Gold safety bar on stone brackets across the front of the cavity.
	for x in [-0.27, 0.27]:
		_add_mesh_box(rig, Vector3(0.06, 0.18, 0.06), Vector3(x, 0.72, -0.14), stone_dark)
	_add_mesh_cylinder(rig, 0.03, 0.58, Vector3(0.0, 0.80, -0.14), Vector3(0.0, 0.0, PI / 2.0), gold, "CarBar")
	# Stone nose sloping down to the front, with the blue banner and gold spike.
	var nose := _add_mesh_box(rig, Vector3(0.60, 0.34, 0.34), Vector3(0.0, 0.46, -0.50), stone, "CarNose")
	nose.rotation.x = 0.55
	_add_mesh_box(rig, Vector3(0.54, 0.16, 0.22), Vector3(0.0, 0.30, -0.66), stone, "CarNoseLip")
	var banner_plate := _add_mesh_box(rig, Vector3(0.36, 0.26, 0.03), Vector3(0.0, 0.54, -0.66), banner, "CarBanner")
	banner_plate.rotation.x = 0.55
	for offset in [Vector3(-0.19, 0.54, -0.66), Vector3(0.19, 0.54, -0.66)]:
		var edge := _add_mesh_box(rig, Vector3(0.03, 0.28, 0.035), offset, gold)
		edge.rotation.x = 0.55
	var top_edge := _add_mesh_box(rig, Vector3(0.40, 0.03, 0.035), Vector3(0.0, 0.66, -0.59), gold)
	top_edge.rotation.x = 0.55
	var diamond := _add_mesh_box(rig, Vector3(0.13, 0.13, 0.05), Vector3(0.0, 0.52, -0.685), gold)
	diamond.name = "CarBannerDiamond"
	diamond.rotation = Vector3(0.55, 0.0, PI / 4.0)
	var spike := _add_mesh_cone(rig, 0.07, 0.24, Vector3(0.0, 0.30, -0.86), Vector3(-PI / 2.0, 0.0, 0.0), gold)
	spike.name = "CarSpike"


## Kettle on rails from the owner's reference art: an iron trolley riding the
## rail block below on four wheels, oak A-brackets with iron caps and gold
## studs on both sides, a big black iron cauldron with a gold studded band
## and a wide rim, a gold crank. The pot tilts toward -z to pour. Node names:
## KettlePot (tilts), KettleOil (shown while loaded), SiegeMuzzle (the lip).
func _build_kettle_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(0.96, 1.10, 0.96), Vector3(0.0, -0.40, 0.0))
	# The rail block below tops out 0.5 under this cell's floor line, so the
	# whole trolley hangs 0.5 lower to rest its wheels on the rails.
	var frame := Node3D.new()
	frame.name = "KettleFrame"
	frame.position = Vector3(0.0, -0.50, 0.0)
	parent.add_child(frame)
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var iron := _visual_material(Color("7b838c"))
	var dark_iron := _visual_material(Color("2f353b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	# Trolley: wheels on the rails (rail top sits at -0.45 in this cell), an
	# iron chassis and an oak bed.
	for x in [-0.22, 0.22]:
		for z in [-0.30, 0.30]:
			_add_mesh_cylinder(frame, 0.11, 0.10, Vector3(x, -0.34, z), Vector3(0.0, 0.0, PI / 2.0), dark_iron, "KettleWheel")
	_add_mesh_box(frame, Vector3(0.80, 0.10, 0.90), Vector3(0.0, -0.24, 0.0), dark_iron)
	_add_mesh_box(frame, Vector3(0.90, 0.12, 0.80), Vector3(0.0, -0.14, 0.0), oak)
	# A-brackets: two leaning oak beams per side meeting at the axle cap.
	for x in [-0.42, 0.42]:
		for z in [-0.26, 0.26]:
			var beam := _add_mesh_box(frame, Vector3(0.14, 0.78, 0.14), Vector3(x, 0.22, z * 0.55), oak)
			beam.rotation.x = -0.42 if z < 0.0 else 0.42
		_add_mesh_box(frame, Vector3(0.20, 0.20, 0.20), Vector3(x, 0.56, 0.0), iron)
		_add_stud(frame, Vector3(x + (0.12 if x > 0.0 else -0.12), 0.56, 0.0), gold, Vector3(0.0, 0.0, PI / 2.0))
		_add_stud(frame, Vector3(x + (0.09 if x > 0.0 else -0.09), 0.12, 0.0), gold, Vector3(0.0, 0.0, PI / 2.0))
	_add_mesh_cylinder(frame, 0.05, 0.96, Vector3(0.0, 0.56, 0.0), Vector3(0.0, 0.0, PI / 2.0), iron, "KettleAxle")
	_add_mesh_box(frame, Vector3(0.08, 0.08, 0.16), Vector3(0.56, 0.62, -0.10), gold)
	_add_mesh_box(frame, Vector3(0.08, 0.18, 0.08), Vector3(0.56, 0.72, -0.16), gold)
	# Cauldron on the axle.
	var pot := Node3D.new()
	pot.name = "KettlePot"
	pot.position = Vector3(0.0, 0.56, 0.0)
	frame.add_child(pot)
	_add_mesh_cylinder(pot, 0.34, 0.52, Vector3(0.0, 0.0, 0.0), Vector3.ZERO, dark_iron, "KettleBody")
	_add_mesh_cylinder(pot, 0.30, 0.16, Vector3(0.0, -0.32, 0.0), Vector3.ZERO, dark_iron, "KettleBottom")
	_add_mesh_cylinder(pot, 0.37, 0.09, Vector3(0.0, 0.02, 0.0), Vector3.ZERO, gold, "KettleBand")
	for angle in [0.0, 1.047, 2.094, 3.142, 4.189, 5.236]:
		_add_stud(pot, Vector3(cos(angle) * 0.37, 0.02, sin(angle) * 0.37), gold, Vector3(0.0, -angle, 0.0))
	_add_mesh_torus(pot, 0.30, 0.42, Vector3(0.0, 0.28, 0.0), Vector3.ZERO, iron)
	_add_mesh_cylinder(pot, 0.31, 0.04, Vector3(0.0, 0.25, 0.0), Vector3.ZERO, _visual_material(Color("d98a1e"), "", Color("ff9a1e")), "KettleOil")
	_add_mesh_box(pot, Vector3(0.18, 0.06, 0.14), Vector3(0.0, 0.29, -0.42), iron)
	var muzzle := Node3D.new()
	muzzle.name = "SiegeMuzzle"
	muzzle.position = Vector3(0.0, 0.30, -0.46)
	pot.add_child(muzzle)


## The owner's siege platform (reference art 2026-09-19): an oak plank deck
## with iron corner caps carrying gold diamonds, iron strap plates mid-edge,
## and a blue banner with a gold fleur on the front (-z) face. `centre` is the
## deck centre; `width`/`depth` its plan size.
func _add_siege_platform(parent: Node3D, centre: Vector3, width: float, depth: float, oak: Material, iron: Material, gold: Material) -> void:
	var banner := _visual_material(Color("1f4fb3"))
	_add_mesh_box(parent, Vector3(width, 0.40, depth), centre, oak)
	for z in [-0.40, 0.40]:
		_add_mesh_box(parent, Vector3(width + 0.02, 0.06, 0.08), centre + Vector3(0.0, 0.0, z * depth * 0.5), _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := centre + Vector3(sx * (width * 0.5 - 0.20), 0.10, sz * (depth * 0.5 - 0.20))
			_add_mesh_box(parent, Vector3(0.40, 0.58, 0.40), corner, iron)
			_add_stud(parent, corner + Vector3(sx * 0.21, 0.06, 0.0), gold, Vector3(0.0, 0.0, PI / 2.0))
			_add_stud(parent, corner + Vector3(0.0, 0.06, sz * 0.21), gold, Vector3(PI / 2.0, 0.0, 0.0))
	for sx in [-1.0, 1.0]:
		_add_mesh_box(parent, Vector3(0.12, 0.46, 0.26), centre + Vector3(sx * (width * 0.5 + 0.02), 0.04, 0.0), iron)
	for sz in [-1.0, 1.0]:
		_add_mesh_box(parent, Vector3(0.26, 0.46, 0.12), centre + Vector3(0.0, 0.04, sz * (depth * 0.5 + 0.02)), iron)
	var flag := _add_mesh_box(parent, Vector3(0.34, 0.50, 0.05), centre + Vector3(0.30, -0.10, -(depth * 0.5 + 0.09)), banner)
	_add_mesh_box(flag, Vector3(0.14, 0.18, 0.02), Vector3(0.0, 0.04, -0.03), gold)


## Turret catapult mk2 from the owner's reference art: the siege platform, an
## iron turntable ring, an oak A-frame with iron caps and gold studs, a rope
## winch drum with a gold crank between the front legs, and a rope-wrapped
## throwing arm ending in an iron bucket with gold studs. Shares the catapult
## node names (CatapultArm / CatapultBucket / CatapultStone) for its animation.
func _build_turret_catapult_mk2_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(1.96, 0.50, 1.96), Vector3(0.5, -0.25, 0.5))
	_add_collision_box(parent, Vector3(1.30, 1.30, 1.40), Vector3(0.5, 0.60, 0.55))
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("7b838c"))
	var dark_iron := _visual_material(Color("2f353b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var rope := _visual_material(Color("c9b17a"))
	_add_siege_platform(parent, Vector3(0.5, -0.30, 0.5), 1.96, 1.96, oak, iron, gold)
	_add_mesh_cylinder(parent, 0.80, 0.14, Vector3(0.5, -0.03, 0.5), Vector3.ZERO, dark_iron, "TurretRing")
	_add_mesh_cylinder(parent, 0.70, 0.14, Vector3(0.5, 0.06, 0.5), Vector3.ZERO, iron, "TurretPlate")
	for angle in [0.5, 1.7, 2.9, 4.1, 5.3]:
		_add_stud(parent, Vector3(0.5 + cos(angle) * 0.74, 0.02, 0.5 + sin(angle) * 0.74), gold, Vector3(0.0, -angle, 0.0))
	_add_mesh_box(parent, Vector3(1.20, 0.14, 1.30), Vector3(0.5, 0.20, 0.55), oak)
	# A-frame: two leaning legs per side to an iron cap at the axle.
	var apex := Vector3(0.5, 1.05, 0.45)
	for x in [0.02, 0.98]:
		var lean := -0.30 if x < 0.5 else 0.30
		var front_leg := _add_mesh_box(parent, Vector3(0.18, 1.12, 0.18), Vector3(x, 0.62, 0.05), oak)
		front_leg.rotation = Vector3(0.36, 0.0, lean)
		var rear_leg := _add_mesh_box(parent, Vector3(0.18, 1.12, 0.18), Vector3(x, 0.62, 0.85), oak)
		rear_leg.rotation = Vector3(-0.36, 0.0, lean)
		var cap := _add_mesh_box(parent, Vector3(0.26, 0.26, 0.26), Vector3(x - (0.10 if x < 0.5 else -0.10), 1.05, 0.45), dark_iron)
		_add_stud(parent, Vector3(cap.position.x + (-0.15 if x < 0.5 else 0.15), 1.05, 0.45), gold, Vector3(0.0, 0.0, PI / 2.0))
		_add_mesh_box(parent, Vector3(0.22, 0.22, 0.22), Vector3(x - (0.06 if x < 0.5 else -0.06), 0.40, 0.05), dark_iron)
		_add_stud(parent, Vector3(x + (-0.14 if x < 0.5 else 0.14), 0.40, 0.05), gold, Vector3(0.0, 0.0, PI / 2.0))
	_add_mesh_cylinder(parent, 0.09, 1.40, apex, Vector3(0.0, 0.0, PI / 2.0), iron, "CatapultAxle")
	_add_mesh_cylinder(parent, 0.16, 0.18, Vector3(1.22, apex.y, apex.z), Vector3(0.0, 0.0, PI / 2.0), dark_iron, "CatapultAxleNut")
	# Winch drum with rope and a gold crank on the left.
	_add_mesh_cylinder(parent, 0.20, 0.90, Vector3(0.5, 0.55, 0.05), Vector3(0.0, 0.0, PI / 2.0), rope, "CatapultWinch")
	_add_mesh_cylinder(parent, 0.06, 1.30, Vector3(0.5, 0.55, 0.05), Vector3(0.0, 0.0, PI / 2.0), iron, "CatapultWinchAxle")
	_add_mesh_box(parent, Vector3(0.08, 0.08, 0.30), Vector3(-0.20, 0.55, 0.16), iron)
	_add_mesh_box(parent, Vector3(0.10, 0.22, 0.10), Vector3(-0.20, 0.62, 0.30), gold)
	_add_mesh_box(parent, Vector3(0.10, 0.10, 0.10), Vector3(-0.20, 0.55, 0.02), gold)
	# Rear cross bar the arm rests on.
	_add_mesh_box(parent, Vector3(1.30, 0.14, 0.14), Vector3(0.5, 0.66, 1.05), oak)
	# Arm with rope wraps and a studded iron bucket.
	var arm := Node3D.new()
	arm.name = "CatapultArm"
	arm.position = apex
	arm.rotation.x = -0.40
	parent.add_child(arm)
	_add_mesh_box(arm, Vector3(0.20, 0.20, 1.90), Vector3(0.0, 0.0, 0.60), oak)
	_add_mesh_box(arm, Vector3(0.26, 0.26, 0.30), Vector3(0.0, 0.0, -0.30), dark_oak)
	for z in [0.55, 0.68, 0.81, 0.94]:
		_add_mesh_cylinder(arm, 0.16, 0.09, Vector3(0.0, 0.0, z), Vector3(PI / 2.0, 0.0, 0.0), rope, "CatapultRope")
	var bucket := Node3D.new()
	bucket.name = "CatapultBucket"
	bucket.position = Vector3(0.0, 0.14, 1.52)
	arm.add_child(bucket)
	_add_mesh_cylinder(bucket, 0.32, 0.30, Vector3.ZERO, Vector3.ZERO, dark_iron, "CatapultBucketWall")
	_add_mesh_torus(bucket, 0.28, 0.38, Vector3(0.0, 0.15, 0.0), Vector3.ZERO, iron)
	for angle in [0.0, 1.571, 3.142, 4.712]:
		_add_stud(bucket, Vector3(cos(angle) * 0.36, 0.08, sin(angle) * 0.36), gold, Vector3(0.0, -angle, 0.0))
	_add_mesh_cylinder(bucket, 0.17, 0.18, Vector3(0.0, 0.10, 0.0), Vector3.ZERO, _visual_material(Color("8f969d"), "res://assets/blocks/stone.svg"), "CatapultStone")


## P4G — Core of Power and light sources (owner art, 2026-09-19).
##
## Every light entity carries its light in content (`attributes.light`);
## `_add_entity_light` turns that into one OmniLight3D named `EntityLight`.
## Lights never go out: nothing here ever removes or dims a light except the
## cosmetic flicker Tween on torches and campfires.
const ENTITY_LIGHT_NAME := "EntityLight"
const LIGHT_FLICKER_AMPLITUDE := 0.15
const LIGHT_FLICKER_SECONDS := 0.42


func _add_entity_light(parent: Node3D, attributes: Dictionary, offset: Vector3 = Vector3.ZERO) -> OmniLight3D:
	var light_value: Variant = attributes.get("light", null)
	if not light_value is Dictionary:
		return null
	var light_definition: Dictionary = light_value
	var light := OmniLight3D.new()
	light.name = ENTITY_LIGHT_NAME
	light.light_color = Color(str(light_definition.get("color", "ffffff")))
	light.light_energy = float(light_definition.get("energy", 1.0))
	light.omni_range = float(light_definition.get("range", 6.0))
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = offset
	parent.add_child(light)
	if bool(light_definition.get("flicker", false)):
		_start_light_flicker(light)
	return light


## Cheap flicker: one looping Tween moves the energy ±15 % around its base
## value with a sine ease. Bound to the light so it dies with it.
func _start_light_flicker(light: OmniLight3D) -> void:
	var base_energy := light.light_energy
	var tween := get_tree().create_tween().bind_node(light).set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(light, "light_energy", base_energy * (1.0 + LIGHT_FLICKER_AMPLITUDE), LIGHT_FLICKER_SECONDS)
	tween.tween_property(light, "light_energy", base_energy * (1.0 - LIGHT_FLICKER_AMPLITUDE), LIGHT_FLICKER_SECONDS * 0.8)
	tween.tween_property(light, "light_energy", base_energy, LIGHT_FLICKER_SECONDS * 0.6)


## Flame tongues like FireService._show: emissive unshaded cones, largest in the
## middle. `scale_y` stretches the tallest tongue for campfires.
func _add_flames(parent: Node3D, offset: Vector3, radius: float, height: float, node_name: String) -> Node3D:
	var flames := Node3D.new()
	flames.name = node_name
	flames.position = offset
	parent.add_child(flames)
	var outer := _flame_material(Color(1.0, 0.45, 0.10, 0.85), Color(1.0, 0.40, 0.08))
	var inner := _flame_material(Color(1.0, 0.82, 0.30, 0.95), Color(1.0, 0.75, 0.20))
	var spread := radius * 0.9
	for index in range(3):
		var tongue_height := height * (1.0 - index * 0.22)
		var tongue_radius := radius * (1.0 - index * 0.2)
		var tongue := _add_mesh_cone(flames, tongue_radius, tongue_height, Vector3(index * spread - spread, tongue_height * 0.5, index * spread * 0.6 - spread * 0.6), Vector3.ZERO, outer)
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := _add_mesh_cone(flames, radius * 0.55, height * 0.65, Vector3(0.0, height * 0.32, 0.0), Vector3.ZERO, inner)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pulse := get_tree().create_tween().bind_node(flames).set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(flames, "scale", Vector3(0.94, 1.10, 0.94), LIGHT_FLICKER_SECONDS)
	pulse.tween_property(flames, "scale", Vector3(1.05, 0.92, 1.05), LIGHT_FLICKER_SECONDS * 0.9)
	pulse.tween_property(flames, "scale", Vector3.ONE, LIGHT_FLICKER_SECONDS * 0.7)
	return flames


func _flame_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Glowing rune material: unshaded, strongly emissive, used for rune lines,
## gems and the light-block cores.
func _rune_material(color: Color, energy: float = 2.2) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _add_mesh_sphere(parent: Node3D, radius: float, offset: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


## Stepped stone slab shared by both cores (3×3 footprint, centre at x=z=1):
## a wide lower tier with rune strips on every face, a narrower upper tier,
## four corner posts capped with gold and a glowing gem, gold corner blocks.
func _add_core_slab(parent: Node3D, stone: Material, dark_stone: Material, gold: Material, rune: Material, gem: Material) -> void:
	var centre := Vector3(1.0, 0.0, 1.0)
	_add_collision_box(parent, Vector3(2.90, 0.40, 2.90), centre + Vector3(0.0, -0.30, 0.0))
	_add_collision_box(parent, Vector3(2.10, 0.36, 2.10), centre + Vector3(0.0, 0.04, 0.0))
	_add_mesh_box(parent, Vector3(2.90, 0.40, 2.90), centre + Vector3(0.0, -0.30, 0.0), stone)
	_add_mesh_box(parent, Vector3(2.96, 0.08, 2.96), centre + Vector3(0.0, -0.46, 0.0), dark_stone)
	_add_mesh_box(parent, Vector3(2.10, 0.36, 2.10), centre + Vector3(0.0, 0.04, 0.0), stone)
	_add_mesh_box(parent, Vector3(2.16, 0.06, 2.16), centre + Vector3(0.0, -0.11, 0.0), dark_stone)
	# Rune strips along the four lower faces and the upper tier.
	for side in [-1.0, 1.0]:
		for run in [-0.72, 0.0, 0.72]:
			_add_mesh_box(parent, Vector3(0.34, 0.08, 0.03), centre + Vector3(run, -0.28, side * 1.46), rune)
			_add_mesh_box(parent, Vector3(0.03, 0.08, 0.34), centre + Vector3(side * 1.46, -0.28, run), rune)
		_add_mesh_box(parent, Vector3(1.40, 0.05, 0.03), centre + Vector3(0.0, 0.06, side * 1.06), rune)
		_add_mesh_box(parent, Vector3(0.03, 0.05, 1.40), centre + Vector3(side * 1.06, 0.06, 0.0), rune)
	# Corner posts with a gold cap and a gem; gold blocks on the lower corners.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := centre + Vector3(sx * 1.16, 0.02, sz * 1.16)
			_add_mesh_box(parent, Vector3(0.46, 0.64, 0.46), post, dark_stone)
			_add_mesh_box(parent, Vector3(0.50, 0.08, 0.50), post + Vector3(0.0, 0.30, 0.0), gold)
			_add_mesh_cone(parent, 0.16, 0.30, post + Vector3(0.0, 0.48, 0.0), Vector3.ZERO, gem)
			_add_mesh_box(parent, Vector3(0.05, 0.36, 0.05), post + Vector3(sx * 0.24, -0.06, sz * 0.24), rune)
			_add_mesh_box(parent, Vector3(0.30, 0.22, 0.30), centre + Vector3(sx * 1.32, -0.20, sz * 1.32), gold)
	# Gold wedges mid-face on the lower tier.
	for side in [-1.0, 1.0]:
		_add_mesh_box(parent, Vector3(0.28, 0.26, 0.12), centre + Vector3(0.0, -0.22, side * 1.48), gold)
		_add_mesh_box(parent, Vector3(0.12, 0.26, 0.28), centre + Vector3(side * 1.48, -0.22, 0.0), gold)


## Core of Power (blue): the shared slab carrying a tapering stone monolith
## with two gold bands, a vertical rune line and diamond gems on each face,
## capped by a stone spire; the blue light sits inside the shaft.
func _build_core_of_power_visual(parent: Node3D, attributes: Dictionary) -> void:
	var stone := _visual_material(Color("6a7079"), "res://assets/blocks/castle_stone.svg")
	var dark_stone := _visual_material(Color("3e444c"), "res://assets/blocks/stone.svg")
	var gold := _visual_material(Color("d9a134"), "", Color("e8b040"))
	var glow := Color("4c9dff")
	var rune := _rune_material(glow, 2.4)
	var gem := _rune_material(Color("7fc0ff"), 2.8)
	_add_core_slab(parent, stone, dark_stone, gold, rune, gem)
	var centre := Vector3(1.0, 0.0, 1.0)
	_add_collision_box(parent, Vector3(1.00, 3.10, 1.00), centre + Vector3(0.0, 1.90, 0.0))
	# Monolith: plinth, shaft, shoulder and spire.
	_add_mesh_box(parent, Vector3(1.16, 0.46, 1.16), centre + Vector3(0.0, 0.44, 0.0), dark_stone)
	_add_mesh_box(parent, Vector3(0.88, 1.70, 0.88), centre + Vector3(0.0, 1.50, 0.0), stone)
	_add_mesh_box(parent, Vector3(0.66, 0.80, 0.66), centre + Vector3(0.0, 2.72, 0.0), stone)
	_add_mesh_cone(parent, 0.40, 0.52, centre + Vector3(0.0, 3.36, 0.0), Vector3.ZERO, dark_stone)
	_add_mesh_box(parent, Vector3(0.96, 0.14, 0.96), centre + Vector3(0.0, 0.76, 0.0), gold)
	_add_mesh_box(parent, Vector3(0.74, 0.12, 0.74), centre + Vector3(0.0, 2.36, 0.0), gold)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_mesh_box(parent, Vector3(0.18, 0.22, 0.18), centre + Vector3(sx * 0.46, 0.76, sz * 0.46), gold)
			_add_mesh_box(parent, Vector3(0.14, 0.18, 0.14), centre + Vector3(sx * 0.36, 2.36, sz * 0.36), gold)
	# Rune lines and gems on the four shaft faces.
	for side in [-1.0, 1.0]:
		_add_mesh_box(parent, Vector3(0.06, 1.30, 0.03), centre + Vector3(0.0, 1.50, side * 0.455), rune)
		_add_mesh_box(parent, Vector3(0.03, 1.30, 0.06), centre + Vector3(side * 0.455, 1.50, 0.0), rune)
		_add_mesh_box(parent, Vector3(0.30, 0.04, 0.03), centre + Vector3(0.0, 1.10, side * 0.455), rune)
		_add_mesh_box(parent, Vector3(0.03, 0.04, 0.30), centre + Vector3(side * 0.455, 1.10, 0.0), rune)
		_add_stud(parent, centre + Vector3(0.0, 1.92, side * 0.47), gem, Vector3(PI / 2.0, 0.0, 0.0))
		_add_stud(parent, centre + Vector3(side * 0.47, 1.92, 0.0), gem, Vector3(0.0, 0.0, PI / 2.0))
		_add_stud(parent, centre + Vector3(0.0, 2.72, side * 0.36), gem, Vector3(PI / 2.0, 0.0, 0.0))
		_add_stud(parent, centre + Vector3(side * 0.36, 2.72, 0.0), gem, Vector3(0.0, 0.0, PI / 2.0))
		_add_mesh_box(parent, Vector3(0.04, 0.60, 0.03), centre + Vector3(0.0, 2.75, side * 0.345), rune)
		_add_mesh_box(parent, Vector3(0.03, 0.60, 0.04), centre + Vector3(side * 0.345, 2.75, 0.0), rune)
	# Large diamond gem on the plinth front, with a gold frame.
	var frame := _add_mesh_box(parent, Vector3(0.34, 0.34, 0.06), centre + Vector3(0.0, 0.46, 0.60), gold)
	frame.rotation.z = PI / 4.0
	var jewel := _add_mesh_box(parent, Vector3(0.22, 0.22, 0.08), centre + Vector3(0.0, 0.46, 0.62), gem)
	jewel.rotation.z = PI / 4.0
	_add_entity_light(parent, attributes, centre + Vector3(0.0, 1.80, 0.0))


## Enemy core (red): the shared slab in black stone with bronze spikes on
## every corner and mid-face, a red rune ring on the upper tier, a cracked
## dark orb held above the slab by a bronze crown of shards, and a red light
## inside the orb.
func _build_enemy_core_visual(parent: Node3D, attributes: Dictionary) -> void:
	var stone := _visual_material(Color("3a3236"), "res://assets/blocks/stone.svg")
	var dark_stone := _visual_material(Color("221c20"))
	var bronze := _visual_material(Color("8a6a3c"), "", Color("5a3f1c"))
	var glow := Color("ff3030")
	var rune := _rune_material(glow, 2.4)
	var gem := _rune_material(Color("ff6a5a"), 2.8)
	_add_core_slab(parent, stone, dark_stone, bronze, rune, gem)
	var centre := Vector3(1.0, 0.0, 1.0)
	_add_collision_box(parent, Vector3(1.40, 2.60, 1.40), centre + Vector3(0.0, 1.90, 0.0))
	# Spikes on the lower tier rim.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_mesh_cone(parent, 0.14, 0.60, centre + Vector3(sx * 1.32, 0.16, sz * 1.32), Vector3.ZERO, bronze)
	for side in [-1.0, 1.0]:
		for run in [-0.60, 0.60]:
			_add_mesh_cone(parent, 0.10, 0.44, centre + Vector3(run, -0.02, side * 1.36), Vector3.ZERO, bronze)
			_add_mesh_cone(parent, 0.10, 0.44, centre + Vector3(side * 1.36, -0.02, run), Vector3.ZERO, bronze)
	# Rune ring on the upper tier and a dark pedestal.
	_add_mesh_torus(parent, 0.62, 0.78, centre + Vector3(0.0, 0.23, 0.0), Vector3.ZERO, rune)
	_add_mesh_cylinder(parent, 0.40, 0.50, centre + Vector3(0.0, 0.46, 0.0), Vector3.ZERO, dark_stone, "EnemyCorePedestal")
	_add_mesh_torus(parent, 0.30, 0.44, centre + Vector3(0.0, 0.72, 0.0), Vector3.ZERO, rune)
	# Crown of bronze shards leaning in around the orb.
	for index in range(6):
		var angle := float(index) * TAU / 6.0
		var shard := _add_mesh_cone(parent, 0.14, 1.30, centre + Vector3(cos(angle) * 0.92, 1.30, sin(angle) * 0.92), Vector3.ZERO, bronze)
		shard.rotation = Vector3(sin(angle) * 0.34, 0.0, -cos(angle) * 0.34)
		var shard_gem := _add_mesh_box(parent, Vector3(0.08, 0.30, 0.08), centre + Vector3(cos(angle) * 0.86, 1.10, sin(angle) * 0.86), gem)
		shard_gem.rotation = shard.rotation
	# The orb: dark cracked stone with a red glow seam and floating shards.
	var orb := _add_mesh_sphere(parent, 0.64, centre + Vector3(0.0, 2.10, 0.0), _visual_material(Color("2a0f14"), "", Color("ff2020")), "EnemyCoreOrb")
	_add_mesh_torus(orb, 0.56, 0.68, Vector3.ZERO, Vector3(PI / 2.0, 0.0, 0.0), rune)
	_add_mesh_torus(orb, 0.56, 0.68, Vector3.ZERO, Vector3(0.0, 0.0, PI / 2.0), rune)
	for index in range(4):
		var angle := float(index) * TAU / 4.0 + 0.4
		var plate := _add_mesh_box(orb, Vector3(0.36, 0.44, 0.14), Vector3(cos(angle) * 0.60, 0.10, sin(angle) * 0.60), dark_stone)
		plate.rotation.y = -angle + PI / 2.0
		_add_mesh_box(parent, Vector3(0.14, 0.22, 0.14), centre + Vector3(cos(angle + 0.8) * 0.95, 1.55, sin(angle + 0.8) * 0.95), dark_stone)
	_add_mesh_cone(parent, 0.16, 0.54, centre + Vector3(0.0, 2.98, 0.0), Vector3.ZERO, bronze)
	_add_mesh_cone(parent, 0.14, 0.40, centre + Vector3(0.0, 1.26, 0.0), Vector3(PI, 0.0, 0.0), bronze)
	_add_entity_light(parent, attributes, centre + Vector3(0.0, 2.10, 0.0))


## Torch: a wooden shaft wrapped in leather with an iron foot cone and iron
## ring, an iron cage of four studded slats holding split wood, and flames.
func _build_torch_visual(parent: Node3D, attributes: Dictionary) -> void:
	_add_collision_box(parent, Vector3(0.30, 0.96, 0.30), Vector3(0.0, 0.0, 0.0))
	var wood := _visual_material(Color("b0723a"), "res://assets/blocks/planks.svg")
	var leather := _visual_material(Color("7a3428"))
	var iron := _visual_material(Color("8b939b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	_add_mesh_cylinder(parent, 0.055, 0.66, Vector3(0.0, -0.16, 0.0), Vector3.ZERO, wood, "TorchShaft")
	_add_mesh_cone(parent, 0.09, 0.12, Vector3(0.0, -0.49, 0.0), Vector3(PI, 0.0, 0.0), iron)
	_add_mesh_cylinder(parent, 0.085, 0.10, Vector3(0.0, -0.40, 0.0), Vector3.ZERO, iron, "TorchFoot")
	_add_stud(parent, Vector3(0.0, -0.40, 0.09), gold, Vector3(PI / 2.0, 0.0, 0.0))
	for y in [-0.30, -0.22, -0.14]:
		var wrap := _add_mesh_cylinder(parent, 0.072, 0.05, Vector3(0.0, y, 0.0), Vector3.ZERO, leather, "TorchWrap")
		wrap.rotation.x = 0.16
	_add_mesh_cylinder(parent, 0.09, 0.08, Vector3(0.0, 0.02, 0.0), Vector3.ZERO, iron, "TorchRing")
	_add_stud(parent, Vector3(0.0, 0.02, 0.095), gold, Vector3(PI / 2.0, 0.0, 0.0))
	_add_mesh_cylinder(parent, 0.13, 0.10, Vector3(0.0, 0.16, 0.0), Vector3.ZERO, iron, "TorchCollar")
	for angle in [0.0, PI / 2.0, PI, PI * 1.5]:
		var slat := _add_mesh_box(parent, Vector3(0.05, 0.30, 0.04), Vector3(cos(angle) * 0.14, 0.30, sin(angle) * 0.14), iron)
		slat.rotation.y = -angle
		_add_stud(parent, Vector3(cos(angle) * 0.16, 0.30, sin(angle) * 0.16), gold, Vector3(0.0, -angle, PI / 2.0))
		var billet := _add_mesh_box(parent, Vector3(0.07, 0.34, 0.07), Vector3(cos(angle + 0.785) * 0.08, 0.30, sin(angle + 0.785) * 0.08), wood)
		billet.rotation.y = -angle
	_add_mesh_torus(parent, 0.13, 0.17, Vector3(0.0, 0.44, 0.0), Vector3.ZERO, iron)
	_add_flames(parent, Vector3(0.0, 0.36, 0.0), 0.11, 0.42, "TorchFlames")
	_add_entity_light(parent, attributes, Vector3(0.0, 0.62, 0.0))


## Iron lantern body shared by the wall and post lanterns: an iron roof with
## a gold finial, four corner rails with gold studs, a glowing amber pane and
## a bottom plate with a gold drop. `centre` is the pane centre.
func _add_lantern_body(parent: Node3D, centre: Vector3, iron: Material, gold: Material, pane: Material) -> void:
	_add_mesh_box(parent, Vector3(0.30, 0.34, 0.30), centre, pane)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_mesh_box(parent, Vector3(0.06, 0.40, 0.06), centre + Vector3(sx * 0.16, 0.0, sz * 0.16), iron)
	for side in [-1.0, 1.0]:
		var cross_a := _add_mesh_box(parent, Vector3(0.04, 0.42, 0.02), centre + Vector3(0.0, 0.0, side * 0.165), iron)
		cross_a.rotation.z = 0.62
		var cross_b := _add_mesh_box(parent, Vector3(0.04, 0.42, 0.02), centre + Vector3(0.0, 0.0, side * 0.165), iron)
		cross_b.rotation.z = -0.62
		var cross_c := _add_mesh_box(parent, Vector3(0.02, 0.42, 0.04), centre + Vector3(side * 0.165, 0.0, 0.0), iron)
		cross_c.rotation.x = 0.62
		var cross_d := _add_mesh_box(parent, Vector3(0.02, 0.42, 0.04), centre + Vector3(side * 0.165, 0.0, 0.0), iron)
		cross_d.rotation.x = -0.62
		_add_stud(parent, centre + Vector3(0.0, 0.0, side * 0.18), gold, Vector3(PI / 2.0, 0.0, 0.0))
		_add_stud(parent, centre + Vector3(side * 0.18, 0.0, 0.0), gold, Vector3(0.0, 0.0, PI / 2.0))
	_add_mesh_box(parent, Vector3(0.40, 0.08, 0.40), centre + Vector3(0.0, 0.24, 0.0), iron)
	_add_mesh_cone(parent, 0.26, 0.16, centre + Vector3(0.0, 0.34, 0.0), Vector3.ZERO, iron)
	_add_mesh_cylinder(parent, 0.05, 0.08, centre + Vector3(0.0, 0.44, 0.0), Vector3.ZERO, iron, "LanternNeck")
	_add_mesh_box(parent, Vector3(0.40, 0.07, 0.40), centre + Vector3(0.0, -0.24, 0.0), iron)
	_add_mesh_cone(parent, 0.08, 0.14, centre + Vector3(0.0, -0.33, 0.0), Vector3(PI, 0.0, 0.0), gold)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_stud(parent, centre + Vector3(sx * 0.20, 0.24, sz * 0.20), gold, Vector3.ZERO)


## Wall lantern: an iron-capped oak post with gold studs, an arm and a brace,
## a chain and the shared lantern body hanging from the arm. Stands on any
## solid top; set it on a wall top or beside a wall to read as a bracket.
## Sign (docs/SIGNS.md): an oak board carrying the player's text or item list.
## The ground variant stands on a stone-footed oak post; the wall variant hangs
## flat on the block behind it with no post. Both keep every part inside the
## sign's own logical cell, so a thin board can never cover a neighbouring one.
## The board faces local +X: the wall mount rotates the body so that is away
## from the wall, and a ground sign turns with the ordinary build rotation.
const SIGN_BOARD_WIDTH := 0.92
const SIGN_BOARD_HEIGHT := 0.86
const SIGN_BOARD_THICKNESS := 0.07
## The smallest cap height a board will shrink its text to.
const SIGN_MIN_LINE_HEIGHT := 0.022


func _build_sign_visual(parent: Node3D, record: Dictionary) -> void:
	var wall := str(record.get("mount", "ground")) == "wall"
	var oak := _visual_material(Color("b07a41"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg")
	var stone := _visual_material(Color("8b929d"))
	var iron := _visual_material(Color("6f777f"))
	var board_x := -0.34 if wall else 0.0
	var board_y := 0.04 if wall else 0.06
	_add_collision_box(parent, Vector3(0.24, SIGN_BOARD_HEIGHT, SIGN_BOARD_WIDTH), Vector3(board_x, board_y, 0.0))
	if not wall:
		_add_mesh_box(parent, Vector3(0.12, 0.44, 0.12), Vector3(0.0, -0.30, 0.0), dark_oak)
		_add_mesh_box(parent, Vector3(0.44, 0.14, 0.44), Vector3(0.0, -0.45, 0.0), stone)
		_add_collision_box(parent, Vector3(0.44, 0.60, 0.44), Vector3(0.0, -0.32, 0.0))
	else:
		# Two short brackets hold the board off the wall behind it.
		for z: float in [-0.28, 0.28]:
			_add_mesh_box(parent, Vector3(0.12, 0.10, 0.10), Vector3(-0.44, board_y, z), iron)
	_add_mesh_box(parent, Vector3(SIGN_BOARD_THICKNESS, SIGN_BOARD_HEIGHT, SIGN_BOARD_WIDTH), Vector3(board_x, board_y, 0.0), oak)
	for z: float in [-SIGN_BOARD_WIDTH / 2.0 + 0.04, SIGN_BOARD_WIDTH / 2.0 - 0.04]:
		_add_mesh_box(parent, Vector3(SIGN_BOARD_THICKNESS + 0.01, SIGN_BOARD_HEIGHT, 0.07), Vector3(board_x, board_y, z), dark_oak)
	var face := Node3D.new()
	face.name = "SignFace"
	# The face's own +Z is the board's +X, so its contents lay out in plain
	# local X (board width) and Y (board height).
	face.position = Vector3(board_x + SIGN_BOARD_THICKNESS / 2.0 + 0.012, board_y, 0.0)
	face.rotation.y = PI / 2.0
	parent.add_child(face)
	_populate_sign_face(face, workstations.sanitized_sign(record.get("sign", {}) if record.get("sign") is Dictionary else {}))


## Rebuilds the board's contents after the editor (or another system) changed
## the sign; the board, post and collision stay as they are.
func _refresh_sign_face(instance_id: String) -> void:
	var body: Node3D = _station_visuals.get(instance_id)
	if body == null or workstations == null:
		return
	var face: Node3D = body.get_node_or_null("SignFace") as Node3D
	if face == null:
		return
	for child in face.get_children():
		face.remove_child(child)
		child.queue_free()
	_populate_sign_face(face, workstations.sign_data(instance_id))


func _populate_sign_face(face: Node3D, data: Dictionary) -> void:
	var mode := str(data.get("mode", "text"))
	var width := SIGN_BOARD_WIDTH - 0.08
	var height := SIGN_BOARD_HEIGHT - 0.08
	var text_a := str(data.get("text_a", ""))
	var text_b := str(data.get("text_b", ""))
	match mode:
		"split":
			var divider := _add_mesh_box(face, Vector3(0.02, height, 0.01), Vector3.ZERO, _visual_material(Color("6b3d1f")))
			divider.rotation.y = -PI / 2.0
			var column := width / 2.0 - 0.03
			_add_sign_label(face, text_a, Vector3(-width / 4.0, 0.0, 0.0), column, _fitted_line_height(text_a, column, height, 0.10))
			_add_sign_label(face, text_b, Vector3(width / 4.0, 0.0, 0.0), column, _fitted_line_height(text_b, column, height, 0.10))
		"items":
			_add_sign_item_grid(face, _sign_items(data), Vector3(0.0, 0.0, 0.0), width, height)
		"header_items":
			_add_sign_label(face, text_a, Vector3(0.0, height / 2.0 - 0.09, 0.0), width, _fitted_line_height(text_a, width, 0.18, 0.10))
			_add_sign_item_grid(face, _sign_items(data), Vector3(0.0, -0.09, 0.0), width, height - 0.18)
		_:
			_add_sign_label(face, text_a, Vector3.ZERO, width, _fitted_line_height(text_a, width, height, 0.13))


## The cap height at which `text` still wraps inside `width` x `height` on the
## board, never bigger than `preferred`. A hand-typed heading keeps its size;
## an authored board carrying a whole paragraph (the Expo's district and
## exhibit signs) shrinks to fit instead of spilling off the panel.
static func _fitted_line_height(text: String, width: float, height: float, preferred: float) -> float:
	if text.is_empty() or width <= 0.0 or height <= 0.0:
		return preferred
	var line_height := preferred
	while line_height > SIGN_MIN_LINE_HEIGHT:
		# This font runs about 0.62 of the cap height per character (measured
		# generously so a long word still lands inside the column), and the
		# rows sit 1.3 cap heights apart.
		var per_line := maxi(1, int(width / (line_height * 0.62)))
		var rows := 0
		for paragraph: String in text.split(String.chr(10)):  # newline
			rows += maxi(1, ceili(float(paragraph.length()) / float(per_line)))
		if float(rows) * line_height * 1.3 <= height:
			return line_height
		line_height -= 0.004
	return SIGN_MIN_LINE_HEIGHT


func _sign_items(data: Dictionary) -> Array:
	var value: Variant = data.get("items", [])
	return value if value is Array else []


## One line (or wrapped block) of sign text. `line_height` is the cap height in
## metres, so the same call reads at 3-6 m whatever the board carries.
func _add_sign_label(parent: Node3D, text: String, offset: Vector3, width: float, line_height: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = line_height / 64.0
	label.width = maxf(width, 0.05) / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color("2a1a0c")
	# A pale outline keeps the small grid captions readable on the oak grain.
	label.outline_size = 14
	label.outline_modulate = Color("f0dcb8")
	label.shaded = false
	label.double_sided = false
	label.position = offset
	parent.add_child(label)
	return label


## The 4-row x 2-column item grid (section 9): each entry is its icon above its
## readable name, in the record's order, filling left column then right.
func _add_sign_item_grid(parent: Node3D, items: Array, offset: Vector3, width: float, height: float) -> void:
	var rows := 4
	var columns := 2
	var cell_width := width / float(columns)
	var cell_height := height / float(rows)
	for index in range(mini(items.size(), rows * columns)):
		var item_id := str(items[index])
		if item_id.is_empty():
			continue
		var column := index / rows
		var row := index % rows
		var centre := offset + Vector3(
			(float(column) + 0.5) * cell_width - width / 2.0,
			height / 2.0 - (float(row) + 0.5) * cell_height,
			0.0)
		var icon_height := cell_height * 0.46
		var texture := ItemIconCatalog.texture_for(item_id) if DisplayServer.get_name() != "headless" else null
		if texture != null:
			var sprite := Sprite3D.new()
			sprite.texture = texture
			sprite.pixel_size = icon_height / maxf(1.0, texture.get_size().y)
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sprite.shaded = false
			sprite.double_sided = false
			sprite.position = centre + Vector3(0.0, cell_height * 0.20, 0.001)
			parent.add_child(sprite)
		_add_sign_label(parent, registry.display_name(item_id), centre + Vector3(0.0, -cell_height * 0.30, 0.0), cell_width - 0.01, cell_height * 0.34)


## Sign content API (docs/SIGNS.md). Other systems - the Expo's Supply Depot
## and district signs - author a sign through these two calls; the record they
## write is stable ids and text, saved with the station.
func configure_sign(instance_id: String, data: Dictionary) -> Dictionary:
	if workstations == null:
		return {"ok": false, "reason": "NO_SERVICE"}
	var result := workstations.configure_sign(instance_id, data)
	if result.get("ok", false):
		_refresh_sign_face(instance_id)
	return result


func sign_data(instance_id: String) -> Dictionary:
	return workstations.sign_data(instance_id) if workstations != null else {}


func _build_wall_lantern_visual(parent: Node3D, attributes: Dictionary) -> void:
	_add_collision_box(parent, Vector3(0.90, 0.96, 0.44), Vector3(0.02, 0.0, 0.0))
	var oak := _visual_material(Color("a96532"), "res://assets/blocks/planks.svg")
	var iron := _visual_material(Color("8b939b"))
	var dark_iron := _visual_material(Color("4a5158"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var pane := _rune_material(Color("ffb050"), 1.8)
	_add_mesh_box(parent, Vector3(0.16, 0.86, 0.16), Vector3(-0.36, -0.02, 0.0), oak)
	_add_mesh_box(parent, Vector3(0.22, 0.14, 0.22), Vector3(-0.36, 0.42, 0.0), iron)
	_add_mesh_box(parent, Vector3(0.22, 0.12, 0.22), Vector3(-0.36, -0.44, 0.0), iron)
	_add_mesh_cone(parent, 0.12, 0.10, Vector3(-0.36, -0.55, 0.0), Vector3(PI, 0.0, 0.0), dark_iron)
	_add_stud(parent, Vector3(-0.36, 0.42, 0.12), gold, Vector3(PI / 2.0, 0.0, 0.0))
	_add_stud(parent, Vector3(-0.36, -0.44, 0.12), gold, Vector3(PI / 2.0, 0.0, 0.0))
	_add_mesh_box(parent, Vector3(0.20, 0.10, 0.20), Vector3(-0.36, 0.08, 0.0), iron)
	_add_mesh_box(parent, Vector3(0.70, 0.12, 0.12), Vector3(0.0, 0.34, 0.0), oak)
	_add_mesh_box(parent, Vector3(0.16, 0.18, 0.16), Vector3(0.30, 0.34, 0.0), iron)
	_add_stud(parent, Vector3(0.30, 0.34, 0.09), gold, Vector3(PI / 2.0, 0.0, 0.0))
	_add_stud(parent, Vector3(0.30, 0.44, 0.0), gold, Vector3.ZERO)
	var brace := _add_mesh_box(parent, Vector3(0.10, 0.48, 0.10), Vector3(-0.12, 0.14, 0.0), oak)
	brace.rotation.z = 0.78
	_add_mesh_torus(parent, 0.03, 0.06, Vector3(0.30, 0.20, 0.0), Vector3(0.0, 0.0, 0.0), dark_iron)
	_add_mesh_torus(parent, 0.03, 0.06, Vector3(0.30, 0.13, 0.0), Vector3(PI / 2.0, 0.0, 0.0), dark_iron)
	_add_lantern_body(parent, Vector3(0.30, -0.16, 0.0), iron, gold, pane)
	_add_entity_light(parent, attributes, Vector3(0.30, -0.10, 0.0))


## Post lantern (three cells tall): an oak base ringed by iron wedges with
## gold studs, a banded post with a gold finial, an arm with a brace and the
## shared lantern body hanging on a chain at head height.
func _build_post_lantern_visual(parent: Node3D, attributes: Dictionary) -> void:
	_add_collision_box(parent, Vector3(0.84, 0.36, 0.84), Vector3(0.0, -0.32, 0.0))
	_add_collision_box(parent, Vector3(0.26, 2.60, 0.26), Vector3(0.0, 1.10, 0.0))
	var oak := _visual_material(Color("a96532"), "res://assets/blocks/planks.svg")
	var dark_oak := _visual_material(Color("6b3d1f"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("8b939b"))
	var dark_iron := _visual_material(Color("4a5158"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var pane := _rune_material(Color("ffb050"), 1.8)
	_add_mesh_box(parent, Vector3(0.80, 0.34, 0.80), Vector3(0.0, -0.33, 0.0), dark_oak)
	for angle in [0.0, PI / 2.0, PI, PI * 1.5]:
		var wedge := _add_mesh_box(parent, Vector3(0.28, 0.44, 0.22), Vector3(cos(angle) * 0.34, -0.26, sin(angle) * 0.34), iron)
		wedge.rotation.y = -angle
		_add_stud(parent, Vector3(cos(angle) * 0.46, -0.26, sin(angle) * 0.46), gold, Vector3(0.0, -angle, PI / 2.0))
	_add_mesh_box(parent, Vector3(0.36, 0.30, 0.36), Vector3(0.0, 0.02, 0.0), iron)
	_add_mesh_box(parent, Vector3(0.24, 2.30, 0.24), Vector3(0.0, 1.10, 0.0), oak)
	for y in [0.70, 1.72]:
		_add_mesh_box(parent, Vector3(0.32, 0.18, 0.32), Vector3(0.0, y, 0.0), iron)
		for angle in [0.0, PI / 2.0, PI, PI * 1.5]:
			_add_stud(parent, Vector3(cos(angle) * 0.17, y, sin(angle) * 0.17), gold, Vector3(0.0, -angle, PI / 2.0))
	_add_mesh_box(parent, Vector3(0.34, 0.16, 0.34), Vector3(0.0, 2.30, 0.0), iron)
	_add_mesh_cone(parent, 0.13, 0.20, Vector3(0.0, 2.46, 0.0), Vector3.ZERO, gold)
	_add_mesh_box(parent, Vector3(0.80, 0.14, 0.14), Vector3(0.36, 2.06, 0.0), oak)
	_add_mesh_box(parent, Vector3(0.18, 0.20, 0.18), Vector3(0.70, 2.06, 0.0), iron)
	_add_stud(parent, Vector3(0.70, 2.06, 0.10), gold, Vector3(PI / 2.0, 0.0, 0.0))
	var brace := _add_mesh_box(parent, Vector3(0.10, 0.52, 0.10), Vector3(0.30, 1.80, 0.0), oak)
	brace.rotation.z = 0.78
	_add_mesh_torus(parent, 0.03, 0.06, Vector3(0.70, 1.90, 0.0), Vector3.ZERO, gold)
	_add_mesh_torus(parent, 0.03, 0.06, Vector3(0.70, 1.83, 0.0), Vector3(PI / 2.0, 0.0, 0.0), dark_iron)
	_add_lantern_body(parent, Vector3(0.70, 1.50, 0.0), iron, gold, pane)
	_add_entity_light(parent, attributes, Vector3(0.70, 1.56, 0.0))


## Campfire (3×3): a ring of rough stones with four gold-banded blocks, an
## ember bed, three crossed logs and flames; the light flickers.
func _build_campfire_visual(parent: Node3D, attributes: Dictionary) -> void:
	var centre := Vector3(1.0, 0.0, 1.0)
	_add_collision_box(parent, Vector3(2.90, 0.50, 2.90), centre + Vector3(0.0, -0.25, 0.0))
	var stone := _visual_material(Color("7d848d"), "res://assets/blocks/stone.svg")
	var dark_stone := _visual_material(Color("4a5058"))
	var gold := _visual_material(Color("d9a134"), "", Color("e8b040"))
	var log_material := _visual_material(Color("8c5a2c"), "res://assets/blocks/log.svg")
	var char_material := _visual_material(Color("2a2320"))
	var ember := _rune_material(Color("ff5a14"), 1.6)
	for index in range(12):
		var angle := float(index) * TAU / 12.0
		var spot := centre + Vector3(cos(angle) * 1.12, -0.28, sin(angle) * 1.12)
		if index % 3 == 0:
			var block := _add_mesh_box(parent, Vector3(0.44, 0.46, 0.50), spot + Vector3(0.0, 0.02, 0.0), gold)
			block.rotation.y = -angle
			_add_stud(parent, centre + Vector3(cos(angle) * 1.38, -0.24, sin(angle) * 1.38), dark_stone, Vector3(0.0, -angle, PI / 2.0))
		else:
			var rock := _add_mesh_box(parent, Vector3(0.52, 0.40, 0.46), spot, stone)
			rock.rotation.y = -angle + 0.12
			var cap := _add_mesh_box(parent, Vector3(0.40, 0.14, 0.34), spot + Vector3(0.0, 0.24, 0.0), dark_stone)
			cap.rotation.y = -angle - 0.10
	_add_mesh_cylinder(parent, 0.86, 0.10, centre + Vector3(0.0, -0.44, 0.0), Vector3.ZERO, ember, "CampfireEmbers")
	for index in range(7):
		var angle := float(index) * TAU / 7.0
		_add_mesh_box(parent, Vector3(0.20, 0.14, 0.16), centre + Vector3(cos(angle) * 0.55, -0.36, sin(angle) * 0.55), char_material)
	for index in range(3):
		var angle := float(index) * TAU / 3.0 + 0.3
		var log_piece := _add_mesh_cylinder(parent, 0.13, 1.30, centre + Vector3(cos(angle) * 0.22, -0.02, sin(angle) * 0.22), Vector3.ZERO, log_material, "CampfireLog")
		log_piece.rotation = Vector3(0.0, -angle, 1.10)
	_add_flames(parent, centre + Vector3(0.0, -0.10, 0.0), 0.30, 1.10, "CampfireFlames")
	_add_entity_light(parent, attributes, centre + Vector3(0.0, 0.70, 0.0))


## Light block: a stone frame of twelve edge bars and eight studded corners
## around a glowing cube, with gold trim and a rune diamond on each face.
func _build_light_block_visual(parent: Node3D, attributes: Dictionary, glow: Color) -> void:
	_add_collision_box(parent, Vector3(1.0, 1.0, 1.0), Vector3.ZERO)
	var stone := _visual_material(Color("5d646c"), "res://assets/blocks/castle_stone.svg")
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	var core := _rune_material(glow, 1.6)
	var rune := _rune_material(glow.lightened(0.45), 2.4)
	_add_mesh_box(parent, Vector3(0.92, 0.92, 0.92), Vector3.ZERO, core)
	for axis in range(3):
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				var size := Vector3(0.16, 0.16, 0.16)
				var offset := Vector3.ZERO
				size[axis] = 1.0
				offset[(axis + 1) % 3] = a * 0.42
				offset[(axis + 2) % 3] = b * 0.42
				_add_mesh_box(parent, size, offset, stone)
				var trim_size := Vector3(0.05, 0.05, 0.05)
				var trim_offset := Vector3.ZERO
				trim_size[axis] = 0.70
				trim_offset[(axis + 1) % 3] = a * 0.475
				trim_offset[(axis + 2) % 3] = b * 0.34
				_add_mesh_box(parent, trim_size, trim_offset, gold)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_add_mesh_box(parent, Vector3(0.24, 0.24, 0.24), Vector3(sx * 0.40, sy * 0.40, sz * 0.40), stone)
				_add_stud(parent, Vector3(sx * 0.53, sy * 0.40, sz * 0.40), gold, Vector3(0.0, 0.0, PI / 2.0))
				_add_stud(parent, Vector3(sx * 0.40, sy * 0.40, sz * 0.53), gold, Vector3(PI / 2.0, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		var diamond_z := _add_mesh_box(parent, Vector3(0.22, 0.22, 0.03), Vector3(0.0, 0.0, side * 0.475), rune)
		diamond_z.rotation.z = PI / 4.0
		var diamond_x := _add_mesh_box(parent, Vector3(0.03, 0.22, 0.22), Vector3(side * 0.475, 0.0, 0.0), rune)
		diamond_x.rotation.x = PI / 4.0
		var diamond_y := _add_mesh_box(parent, Vector3(0.22, 0.03, 0.22), Vector3(0.0, side * 0.475, 0.0), rune)
		diamond_y.rotation.y = PI / 4.0
	_add_entity_light(parent, attributes, Vector3.ZERO)


## A small gold diamond: a cube rotated 45 degrees about the given axis.
func _add_stud(parent: Node3D, offset: Vector3, material: Material, axis_rotation: Vector3) -> MeshInstance3D:
	var stud := _add_mesh_box(parent, Vector3(0.10, 0.10, 0.10), offset, material)
	stud.rotation = axis_rotation + Vector3(0.0, 0.785, 0.0)
	return stud


func _add_mesh_torus(parent: Node3D, inner_radius: float, outer_radius: float, offset: Vector3, rotation: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 24
	mesh.ring_segments = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.rotation = rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_mesh_cone(parent: Node3D, radius: float, height: float, offset: Vector3, rotation: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.rotation = rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


## Defence sets (docs/DEFENSE_SETS.md): a portcullis leaf filling the gate
## frame's one-cell opening. Every mesh hangs under a `GateLeaf` pivot so the
## open/close slide moves one node (the station-visual idiom `_wrap_siege_turret`
## and `KettlePot` use); the two blocking boxes stay direct children of the
## StaticBody3D, because Godot only reads a CollisionShape3D there, and are
## disabled instead of moved while the gate stands open.
func _build_gate_visual(parent: Node3D) -> void:
	var iron := _visual_material(Color("6f7780"))
	var dark_iron := _visual_material(Color("3f454c"))
	for cell in range(2):
		var blocker := _add_collision_box(parent, Vector3(0.96, 0.98, 0.26), Vector3(0.0, float(cell), 0.0))
		blocker.name = "GateBlocker_%d" % cell
	var leaf := Node3D.new()
	leaf.name = GATE_LEAF_NODE
	leaf.position = Vector3(0.0, 0.5, 0.0)
	parent.add_child(leaf)
	# Three stiles, three cross rails and a row of spiked feet.
	for x in [-0.34, 0.0, 0.34]:
		_add_mesh_box(leaf, Vector3(0.13, 1.96, 0.22), Vector3(x, 0.0, 0.0), iron)
		_add_mesh_box(leaf, Vector3(0.09, 0.16, 0.16), Vector3(x, -1.02, 0.0), dark_iron)
	for y in [-0.88, 0.0, 0.88]:
		_add_mesh_box(leaf, Vector3(0.94, 0.13, 0.22), Vector3(0.0, y, 0.0), dark_iron)
	# The channel the leaf runs in, so a closed gate reads as fitted, not stacked.
	_add_mesh_box(leaf, Vector3(1.0, 0.12, 0.3), Vector3(0.0, 1.04, 0.0), dark_iron)


## Defence sets: the turret catapult on a rail carriage. The arm, bucket and
## stone keep the field catapult's node names, so SiegeDefenseService's
## wind-back and throw animation and its muzzle lookup work unchanged.
func _build_rail_turret_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(0.9, 0.88, 0.9), Vector3(0.0, -0.05, 0.0))
	var iron := _visual_material(Color("8d959d"))
	var dark_iron := _visual_material(Color("474e55"))
	var oak := _visual_material(Color("b9783f"), "res://assets/blocks/planks.svg")
	# Carriage: a plank deck on an iron underframe with four wheels that sit
	# down in the rail cell, exactly as the kettle's trolley does.
	_add_mesh_box(parent, Vector3(0.9, 0.14, 0.9), Vector3(0.0, -0.3, 0.0), oak)
	_add_mesh_box(parent, Vector3(0.94, 0.1, 0.94), Vector3(0.0, -0.4, 0.0), dark_iron)
	for x in [-0.3, 0.3]:
		for z in [-0.32, 0.32]:
			_add_mesh_box(parent, Vector3(0.16, 0.16, 0.1), Vector3(x, -0.52, z), dark_iron)
	# Turntable and A-frame.
	_add_mesh_box(parent, Vector3(0.62, 0.1, 0.62), Vector3(0.0, -0.18, 0.0), iron)
	for x in [-0.24, 0.24]:
		_add_mesh_box(parent, Vector3(0.1, 0.52, 0.1), Vector3(x, 0.12, -0.08), oak)
	_add_mesh_box(parent, Vector3(0.62, 0.1, 0.12), Vector3(0.0, 0.38, -0.08), oak)
	var arm := Node3D.new()
	arm.name = "CatapultArm"
	arm.position = Vector3(0.0, 0.34, -0.08)
	parent.add_child(arm)
	_add_mesh_box(arm, Vector3(0.12, 0.12, 0.78), Vector3(0.0, 0.0, 0.34), oak)
	var bucket := Node3D.new()
	bucket.name = "CatapultBucket"
	bucket.position = Vector3(0.0, 0.06, 0.7)
	arm.add_child(bucket)
	_add_mesh_box(bucket, Vector3(0.28, 0.2, 0.28), Vector3.ZERO, dark_iron)
	_add_mesh_box(bucket, Vector3(0.18, 0.18, 0.18), Vector3(0.0, 0.14, 0.0), iron, "CatapultStone")
	var muzzle := Node3D.new()
	muzzle.name = "SiegeMuzzle"
	muzzle.position = Vector3(0.0, 0.16, 0.0)
	bucket.add_child(muzzle)


## Defence sets: the leaf slides clear of the opening (into the frame's jamb)
## and drops back. Pathing has already changed by the time this runs - the
## slide is presentation, the blockers switch with the state.
func _apply_gate_state(instance_id: String, open: bool, animate: bool) -> void:
	var body: Node3D = _station_visuals.get(instance_id)
	if body == null or not is_instance_valid(body):
		return
	var leaf: Node3D = body.get_node_or_null(GATE_LEAF_NODE)
	if leaf == null:
		return
	var target := Vector3(GATE_LEAF_OPEN_X if open else 0.0, 0.5, 0.0)
	if animate:
		var tween := create_tween()
		tween.tween_property(leaf, "position", target, WorkstationService.GATE_SLIDE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		leaf.position = target
	for child in body.get_children():
		if child is CollisionShape3D and str(child.name).begins_with("GateBlocker"):
			child.disabled = open


func _add_collision_box(parent: Node3D, size: Vector3, offset: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = offset
	parent.add_child(collision)
	return collision


func _add_mesh_box(parent: Node3D, size: Vector3, offset: Vector3, material: Material, node_name: String = "", shared_mesh: BoxMesh = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	if not node_name.is_empty():
		mesh_instance.name = node_name
	var mesh := shared_mesh
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_mesh_cylinder(parent: Node3D, radius: float, height: float, offset: Vector3, rotation: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.rotation = rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


func _visual_material(color: Color, texture_path: String = "", emission: Color = Color.TRANSPARENT) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path)
	if emission.a > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.2
	return material


func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _update_placement_preview() -> void:
	if not world_ready or simulation_paused or saving or menu_open or player == null or player.camera == null:
		_hide_placement_preview()
		return
	if interaction.drag_active():
		# Coaster rails side project: X / C resize a loop while its drag is active.
		interaction.coaster_loop_keys(Input.is_key_pressed(KEY_X), Input.is_key_pressed(KEY_C))
		interaction.curve_keys(Input.is_key_pressed(KEY_X), Input.is_key_pressed(KEY_C))
		_update_drag_preview(interaction.update_drag_place(player.view_origin(), -player.camera.global_basis.z, Input.is_action_pressed("interact")))
		return
	var preview := interaction.placement_preview_from_view(player.view_origin(), -player.camera.global_basis.z)
	if not preview.get("visible", false):
		_hide_placement_preview()
		return
	var anchor: Vector3i = preview.anchor
	var kind := str(preview.get("kind", "entity"))
	var clearing := int(preview.get("clear", 0)) > 0
	var key := "%s|%s|%s|%d|%s|%s" % [kind, str(preview.get("entity_id", preview.get("voxel_id", 0))), anchor, int(preview.rotation_quarters), str(preview.ok), str(clearing)]
	if key == _placement_preview_key:
		return
	_hide_placement_preview()
	_placement_preview = Node3D.new()
	_placement_preview.name = "PlacementPreview"
	_placement_preview.position = Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	_placement_preview.rotation.y = -float(int(preview.rotation_quarters)) * PI / 2.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = (Color(1.0, 0.52, 0.10, 0.55) if clearing else Color(0.2, 0.9, 0.45, 0.48)) if preview.ok else Color(0.95, 0.2, 0.2, 0.48)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	if kind == "block":
		var voxel_id := int(preview.get("voxel_id", 0))
		if voxel_id > 0 and voxel_id < WorldAdapter.BLOCK_NAMES.size():
			var texture_path := "res://assets/blocks/%s.svg" % WorldAdapter.BLOCK_NAMES[voxel_id]
			if ResourceLoader.exists(texture_path):
				material.albedo_texture = load(texture_path)
		_add_visual_parts(_placement_preview, [{"offset": [0.0, 0.0, 0.0], "size": [0.96, 0.96, 0.96]}], material, false)
	else:
		var definition := registry.entity(str(preview.get("entity_id", "")))
		if definition.is_empty():
			_hide_placement_preview()
			return
		_add_visual_parts(_placement_preview, definition.get("visual", {}).get("parts", []), material, false)
	add_child(_placement_preview)
	_placement_preview_key = key


## P3J: ghost every planned drag cell — green buildable, amber beyond the carried
## count, red blocked — so the player sees exactly what release will build.
func _update_drag_preview(drag: Dictionary) -> void:
	if not drag.get("active", false):
		_snap_announced = ""
		_hide_placement_preview()
		return
	var snap: Dictionary = drag.get("snap", {})
	var snap_key := ""
	if not snap.is_empty():
		snap_key = "%s@%s" % [str(snap.get("instance_id", "")), str(snap.get("next", Vector3i.ZERO))]
	if snap_key.is_empty():
		_snap_announced = ""
	elif snap_key != _snap_announced:
		_snap_announced = snap_key
		_on_interaction_feedback("TRACK_SNAPPED")
	var key := "drag|%s|%d|%s|%s|%d|%d|%s" % [str(drag.get("blueprint_id", "")), int(drag.voxel_id), drag.anchor, drag.end, int(drag.get("rotation_quarters", 0)), int(drag.affordable), snap_key]
	for entry in drag.cells:
		key += "|" + str(entry.state)[0]
	if key == _placement_preview_key:
		return
	_hide_placement_preview()
	_placement_preview = Node3D.new()
	_placement_preview.name = "DragPreview"
	if not snap.is_empty():
		_add_snap_hint(_placement_preview, str(snap.get("instance_id", "")))
	# P3K: plans may mix block types (blueprints), so "ok" materials are keyed
	# by the cell's own voxel so each ghost shows the block it will become.
	var materials := {}
	# "clear" (track auto-clear, CoasterCraft card 6): terrain the track will
	# mine away on release - amber-orange, apart from the paler "unaffordable".
	for state in ["unaffordable", "blocked", "clear"]:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color(1.0, 0.8, 0.25, 0.55) if state == "unaffordable" else (Color(1.0, 0.52, 0.10, 0.62) if state == "clear" else Color(1.0, 0.25, 0.25, 0.55))
		materials[state] = material
	for entry in drag.cells:
		var entry_voxel := int(entry.get("voxel_id", drag.voxel_id))
		var ok_key := "ok:%d" % entry_voxel
		if materials.has(ok_key):
			continue
		var ok_material := StandardMaterial3D.new()
		ok_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ok_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ok_material.no_depth_test = true
		ok_material.albedo_color = Color(0.35, 1.0, 0.6, 0.62)
		if entry_voxel > 0 and entry_voxel < WorldAdapter.BLOCK_NAMES.size():
			var texture_path := "res://assets/blocks/%s.svg" % WorldAdapter.BLOCK_NAMES[entry_voxel]
			if ResourceLoader.exists(texture_path):
				ok_material.albedo_texture = load(texture_path)
		materials[ok_key] = ok_material
	# A dark translucent frame around each cell keeps the plan readable against
	# grass, where a green tint alone disappears.
	var frame_material := StandardMaterial3D.new()
	frame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_material.no_depth_test = true
	frame_material.cull_mode = BaseMaterial3D.CULL_FRONT
	frame_material.albedo_color = Color(0.05, 0.08, 0.1, 0.55)
	for entry in drag.cells:
		var cell: Vector3i = entry.cell
		var holder := Node3D.new()
		holder.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		_placement_preview.add_child(holder)
		_add_visual_parts(holder, [{"offset": [0.0, 0.0, 0.0], "size": [1.0, 1.0, 1.0]}], frame_material, false)
		var state_key := str(entry.state)
		if state_key == "ok":
			state_key = "ok:%d" % int(entry.get("voxel_id", drag.voxel_id))
		_add_visual_parts(holder, [{"offset": [0.0, 0.0, 0.0], "size": [0.9, 0.9, 0.9]}], materials[state_key], false)
	add_child(_placement_preview)
	_placement_preview_key = key


## Snap to a track end (owner playtest 2026-09-21 item 2): a translucent
## yellow glow around the piece the ghost will join, under the preview root
## (never under the piece's body, so it is not baked into the piece).
func _add_snap_hint(parent: Node3D, instance_id: String) -> void:
	var record := workstations.station(instance_id)
	if record.is_empty():
		return
	var material := _visual_material(Color(1.0, 0.86, 0.2, 0.45), "", Color(1.0, 0.78, 0.1))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hint := _add_mesh_box(parent, Vector3(1.04, 0.7, 1.04), CoasterRails.ride_point(record), material, "SnapHint")
	hint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _hide_placement_preview() -> void:
	if _placement_preview != null:
		_placement_preview.queue_free()
		_placement_preview = null
	_placement_preview_key = ""


func _remove_station_visual(instance_id: String) -> void:
	if not _station_visuals.has(instance_id):
		return
	var body: Node = _station_visuals[instance_id]
	if is_riding() and coaster_ride.car_id == instance_id:
		_on_interaction_feedback(str(leave_coaster_car().get("reason", "COASTER_LEFT")))
	body.queue_free()
	_miner_drills.erase(instance_id)
	if siege_defense != null:
		siege_defense.unregister_visual(instance_id)
	if coaster_carts != null:
		coaster_carts.unregister_cart(instance_id)
		if coaster_carts.cart_count() == 0:
			coaster_carts.queue_free()
			coaster_carts = null
	_station_visuals.erase(instance_id)
	_station_visual_materials.erase(instance_id)


func _update_station_visual(instance_id: String, integrity: int, max_integrity: int) -> void:
	if not _station_visual_materials.has(instance_id) or max_integrity <= 0:
		return
	var material: StandardMaterial3D = _station_visual_materials[instance_id]
	var definition := registry.entity(str(workstations.station(instance_id).get("entity_id", "")))
	var base_color := Color(str(definition.get("visual", {}).get("color", "8b929d")))
	var ratio := clampf(float(integrity) / float(max_integrity), 0.0, 1.0)
	material.albedo_color = base_color.lerp(Color("c64a3c"), 1.0 - ratio)


func _raycast_station(origin: Vector3, direction: Vector3) -> String:
	if not is_inside_tree():
		return ""
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 5.0, 1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta("station_instance_id"):
		return str(collider.get_meta("station_instance_id"))
	return ""


func _defense_interact(origin: Vector3, direction: Vector3) -> Dictionary:
	if defense == null or not is_inside_tree():
		return {"handled": false}
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 5.0, 1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# Coaster car and hero: Shift on a coaster car boards it (repair of a car
	# is not offered; dismantle and re-place it instead). Owner 2026-09-20:
	# the aim often lands on the rail or the ground under the car, so a car
	# standing within reach of the hit point counts too; a car parked up in
	# a loop has nothing behind it to hit, so the aim line itself is sampled.
	var car_id := ""
	if hit.is_empty():
		for metres in range(1, 6):
			car_id = _coaster_car_near(origin + direction.normalized() * float(metres), null)
			if not car_id.is_empty():
				break
	else:
		car_id = _coaster_car_near(hit.get("position", origin), hit.get("collider"))
	if not car_id.is_empty():
		var boarded := board_coaster_car(car_id)
		return {"handled": true, "ok": bool(boarded.get("ok", false)), "reason": str(boarded.get("reason", "NO_CAR"))}
	if hit.is_empty():
		return {"handled": false}
	var collider: Object = hit.get("collider")
	if collider == null:
		return {"handled": false}
	if not collider.has_meta("defense_structure_id"):
		return {"handled": false}
	var structure_id := str(collider.get_meta("defense_structure_id"))
	if structure_id == "training_wall":
		return defense.try_repair(structure_id)
	return workstations.try_repair_structure(structure_id)


## The coaster car the aim hit, or the nearest one within BOARD_REACH of the
## hit point (its parked body sits on top of a rail piece).
const BOARD_REACH := 1.6


func _coaster_car_near(point: Vector3, collider: Object) -> String:
	if collider != null and collider.has_meta("station_instance_id"):
		var hit_id := str(collider.get_meta("station_instance_id"))
		if str(workstations.station(hit_id).get("entity_id", "")) == CoasterRails.CAR:
			return hit_id
	var best_id := ""
	var best_distance := BOARD_REACH
	for station_id: String in _station_visuals:
		if str(workstations.station(station_id).get("entity_id", "")) != CoasterRails.CAR:
			continue
		var body: Node3D = _station_visuals[station_id]
		if body == null or not is_instance_valid(body):
			continue
		var rig: Node3D = body.get_node_or_null("CartRig")
		var car_point := rig.global_position if rig != null else body.global_position
		var distance := car_point.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best_id = station_id
	return best_id


## Fire damage callback: a raider standing in a burning cell takes damage.
func _fire_damage_at(cell: Vector3i, damage: int) -> void:
	if core_defense == null:
		return
	core_defense.damage_raiders_in_cell(cell, damage, "fire")


func _player_primary_action(origin: Vector3, direction: Vector3) -> Dictionary:
	var item_id := inventory.active_item_id()
	var item := registry.item(item_id)
	var weapon: Dictionary = item.get("weapon", {})
	if str(weapon.get("kind", "")) != "melee":
		return {"handled": false}
	if _melee_cooldown > 0.0:
		return {"handled": true, "ok": false, "reason": "MELEE_COOLDOWN", "remaining_seconds": _melee_cooldown}
	_melee_cooldown = maxf(0.05, float(weapon.get("cooldown_seconds", 0.55)))
	_spawn_sword_swing()
	if core_defense == null or core_defense.living_raider_count() == 0:
		return {"handled": true, "ok": false, "reason": "SWORD_MISS"}
	var reach := float(weapon.get("range", 3.25))
	var aim_direction := direction.normalized()
	# First: whatever body the swing ray touches (raiders live on layer 4).
	var swing := PhysicsRayQueryParameters3D.create(origin, origin + aim_direction * reach, 1 | 4)
	swing.exclude = [player.get_rid()]
	var struck: Variant = null
	var swing_hit := get_world_3d().direct_space_state.intersect_ray(swing)
	if not swing_hit.is_empty() and core_defense.is_raider_node(swing_hit.get("collider")):
		struck = swing_hit.get("collider")
	if struck == null:
		# Otherwise the nearest raider inside the reach cone, with nothing solid
		# closer than its own bulk in between.
		var target_position := core_defense.nearest_raider_position(origin)
		var target_offset := target_position - origin
		if not target_position.is_finite() or target_offset.length() > reach or aim_direction.dot(target_offset.normalized()) < 0.80:
			return {"handled": true, "ok": false, "reason": "SWORD_MISS"}
		var query := PhysicsRayQueryParameters3D.create(origin, target_position, 1 | 4)
		query.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and not core_defense.is_raider_node(hit.get("collider")) and Vector3(hit.get("position", target_position)).distance_to(target_position) > 0.9:
			return {"handled": true, "ok": false, "reason": "SWORD_MISS"}
		for node in core_defense.raider_nodes():
			if (node.global_position + Vector3.UP * 0.65).distance_to(target_position) < 0.01:
				struck = node
	var result: Dictionary
	if struck != null and core_defense.is_raider_node(struck):
		result = core_defense.try_damage_raider_node(struck, int(weapon.get("damage", 0)), item_id)
	else:
		result = core_defense.try_damage_raider(int(weapon.get("damage", 0)), item_id)
	if result.get("ok", false) and struck != null:
		core_defense.notify_raider_provoked(struck, "player")
	result["handled"] = true
	return result


func _spawn_sword_swing() -> void:
	if _held_item_view != null:
		_held_item_view.play_use()


func _spawn_starter_resource_markers() -> void:
	if _resource_markers != null:
		return
	_resource_markers = Node3D.new()
	_resource_markers.name = "StarterResourceMarkers"
	_resource_markers.position = STARTER_IRON_MARKER
	add_child(_resource_markers)
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color("d98145")
	marker_material.emission_enabled = true
	marker_material.emission = Color("8e3f24")
	marker_material.emission_energy_multiplier = 0.55
	for x_offset in [-0.52, 0.52]:
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.045
		post_mesh.bottom_radius = 0.065
		post_mesh.height = 1.15
		post.mesh = post_mesh
		post.position = Vector3(x_offset, 0.58, 0.0)
		post.material_override = marker_material
		_resource_markers.add_child(post)
	var crossbar := MeshInstance3D.new()
	var crossbar_mesh := BoxMesh.new()
	crossbar_mesh.size = Vector3(1.15, 0.10, 0.10)
	crossbar.mesh = crossbar_mesh
	crossbar.position = Vector3(0.0, 1.05, 0.0)
	crossbar.material_override = marker_material
	_resource_markers.add_child(crossbar)
	var label := Label3D.new()
	label.text = "IRON VEIN\nDIG 2 BLOCKS"
	label.position = Vector3(0.0, 1.55, 0.0)
	label.font_size = 34
	label.outline_size = 8
	label.modulate = Color("ffd1a3")
	label.outline_modulate = Color(0.08, 0.03, 0.02, 0.94)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	_resource_markers.add_child(label)


func _on_defense_state_changed(_text: String) -> void:
	if coastercraft or development:
		defense_changed.emit("")
	elif core_defense != null and (core_defense.is_active() or core_defense.state == CoreDefenseService.FAILED):
		defense_changed.emit(core_defense.hud_text() + (siege_defense.hud_suffix() if siege_defense != null else ""))
	elif core_defense != null and core_defense.state == CoreDefenseService.WON:
		defense_changed.emit(core_defense.hud_text() + (siege_defense.hud_suffix() if siege_defense != null else ""))
	elif defense != null:
		defense_changed.emit(defense.hud_text())
