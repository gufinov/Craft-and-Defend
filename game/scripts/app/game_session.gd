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
}

const STARTER_IRON_MARKER := Vector3(-6.5, 0.0, 36.5)

var world: WorldAdapter
var player: PlayerController
var registry: ContentRegistry
var inventory: F0Inventory
var crafting: CraftingService
var workstations: WorkstationService
var interaction: InteractionService
var clock: DayNightClock
var defense: DefenseService
var core_defense: CoreDefenseService
var siege_defense: SiegeDefenseService
var open_data: Dictionary
var world_ready := false
var saving := false
var simulation_paused := true
var _pending_workstation_snapshot: Dictionary = {}
var _station_visuals: Dictionary = {}
var _station_visual_materials: Dictionary = {}
var _placement_preview: Node3D
var _placement_preview_key := ""
var _held_item_view: HeldItemView
var fire_service: FireService
## Set by the app before initialize(): Settings > Graphics terrain view distance.
var settings_view_distance := 0
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
	var world_result := world.initialize(session_data.working_database, player.position, snapshot.get("world", {}))
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
	siege_defense.state_changed.connect(_on_defense_state_changed)
	interaction = InteractionService.new(world, inventory, player.get_body_aabb, registry, workstations, _raycast_station, _defense_interact)
	interaction.restore_stamps(open_data.get("snapshot", {}).get("blueprints", {}).get("stamps", []))
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
		_held_item_view.set_gameplay_visible(world_ready and not simulation_paused and not saving)
	_update_placement_preview()
	if defense != null:
		defense.advance(delta, simulation_paused or saving)
	if core_defense != null:
		core_defense.advance(delta, simulation_paused or saving)
	if siege_defense != null:
		siege_defense.advance(delta, simulation_paused or saving)
		fire_service.advance(delta, simulation_paused or saving)
	if not simulation_paused:
		_melee_cooldown = maxf(0.0, _melee_cooldown - delta)
		if player != null and world_ready:
			player.advance_health(delta)
	if workstations != null and not saving:
		workstations.advance(delta, simulation_paused)
		_ensure_enemy_core(delta)
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
	return result


## P4G: the red enemy core stands on the enemy base clearing. It is placed
## through the ordinary station path the first time the base's cells are
## loaded (the player wandered there), on a stone slab levelled for it.
var _enemy_core_timer := 0.0
func _ensure_enemy_core(delta: float) -> void:
	if not world_ready or simulation_paused or registry.entity("enemy_core").is_empty():
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
	if not _pending_workstation_snapshot.is_empty():
		var restored := workstations.restore(_pending_workstation_snapshot, world.query_cell)
		if not restored.get("ok", false):
			status_changed.emit("Station restore failed: %s" % restored.get("reason", "UNKNOWN"))
			return
		for record: Dictionary in workstations.stations.values():
			_spawn_station_visual(record)
	var defense_restore := defense.restore_after_world_ready()
	if not defense_restore.get("ok", false):
		status_changed.emit("Defense restore failed: %s" % defense_restore.get("reason", "UNKNOWN"))
		return
	var core_restore := core_defense.restore_after_world_ready()
	if not core_restore.get("ok", false):
		# A broken drill record must never brick a save: drop the drill and go on.
		core_defense.clear_for_other_mode()
		_on_interaction_feedback("The saved defense drill could not be restored (%s); it was cleared." % str(core_restore.get("reason", "UNKNOWN")))
	world_ready = true
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
		player.activate(not DisplayServer.get_name().contains("headless"))


func snapshot() -> Dictionary:
	return {
		"schema_version": SaveCoordinator.SAVE_SCHEMA,
		"content_version": SaveCoordinator.CONTENT_VERSION,
		"world": world.snapshot(),
		"inventory": inventory.snapshot(),
		"workstations": workstations.snapshot(),
		"defense": defense.snapshot(),
		"core_defense": core_defense.snapshot(),
		"blueprints": {"stamps": interaction.stamps_snapshot()} if interaction != null else {"stamps": []},
		"clock": clock.snapshot(),
		"player": player.snapshot(),
		"session_id": open_data.get("session_id", ""),
	}


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
	hud_changed.emit("%sSlot %d: %s   |   %s · %s%s" % [health_text, inventory.selected_hotbar + 1, selected_text, clock.period_label(), clock.time_label(), cycle_text])


func _on_player_health_changed(_health: int, _max_health: int) -> void:
	_emit_hud()


## Death: back to the core (or home) with full health after a short pause.
func _on_player_died() -> void:
	_on_interaction_feedback("You fell. You wake at your core.")
	var respawn := WorldAdapter.SPAWN_FEET
	for record: Dictionary in workstations.stations.values():
		if str(record.get("entity_id", "")) == "core_of_power":
			var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
			respawn = Vector3(anchor) + Vector3(1.5, 1.0, -1.0)
	player.global_position = respawn
	player.velocity = Vector3.ZERO
	player.restore_health()


func _emit_navigation() -> void:
	if player == null:
		return
	var offset := Vector2(WorldAdapter.SPAWN_FEET.x - player.global_position.x, WorldAdapter.SPAWN_FEET.z - player.global_position.z)
	var distance := offset.length()
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
	if world == null or world.terrain == null or not world.terrain.generator is P1TerrainGenerator:
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


func _on_interaction_feedback(message: String) -> void:
	var friendly := str(REASON_TEXT.get(message, message if message.contains(" ") else message.replace("_", " ").capitalize()))
	status_changed.emit(friendly)
	feedback_changed.emit(friendly)


func _on_boundary_feedback(message: String) -> void:
	status_changed.emit(message)
	feedback_changed.emit(message)


func _unhandled_input(event: InputEvent) -> void:
	if not world_ready or simulation_paused or saving:
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
			select_hotbar(index)
			get_viewport().set_input_as_handled()
			return


func _on_interaction_result(result: Dictionary) -> void:
	if _held_item_view != null and str(result.get("reason", "")) != "OPEN_STATION":
		_held_item_view.play_use()
	var changes: Dictionary = result.get("changes", {})
	if result.get("ok", false) and str(result.get("reason", "")) == "OPEN_STATION":
		var station_record: Dictionary = changes.get("station", {})
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
		if str(details.station.get("entity_id", "")) == "rail":
			_refresh_rail_neighbours(details.station.get("anchor", Vector3i.ZERO))
	elif details.has("instance_id") and (details.has("returned_item") or bool(details.get("destroyed", false))):
		_remove_station_visual(str(details.instance_id))
		var released: Array = details.get("occupied_cells", [])
		if str(details.get("entity_id", "")) == "rail" and released.size() > 0 and released[0] is Vector3i:
			_refresh_rail_neighbours(released[0])
	elif details.has("instance_id") and details.has("integrity"):
		_update_station_visual(str(details.instance_id), int(details.integrity), int(details.get("max_integrity", 1)))


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
	elif entity_id == "rail":
		_build_rail_visual(body, _rail_neighbour_mask(anchor))
	elif entity_id == "core_of_power":
		_build_core_of_power_visual(body, registry.entity_attributes(entity_id))
	elif entity_id == "enemy_core":
		_build_enemy_core_visual(body, registry.entity_attributes(entity_id))
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
	else:
		_add_visual_parts(body, visual.get("parts", []), material, true)
	add_child(body)
	_station_visuals[instance_id] = body
	_station_visual_materials[instance_id] = material
	if siege_defense != null and not definition.get("siege", {}).is_empty():
		siege_defense.register_visual(instance_id, body)
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


## Rail block from the owner's reference art: castle-stone corner posts with
## gold studs, an oak plank deck between them and two iron rails along z with
## small iron ties. Rails chain along a wall top; the kettle rides them.
## Rail neighbours as a bit mask: 1 +x, 2 -x, 4 +z, 8 -z (world axes; the
## rail body is never rotated for its shape).
func _rail_neighbour_mask(anchor: Vector3i) -> int:
	var mask := 0
	var sides := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for index in range(sides.size()):
		var neighbour := workstations.station_at_cell(anchor + sides[index])
		if not neighbour.is_empty() and str(workstations.station(neighbour).get("entity_id", "")) == "rail":
			mask |= 1 << index
	return mask


## Rebuilds the rail visuals around `anchor` so corners, T's and crossroads
## re-shape when a neighbouring rail is laid or removed.
func _refresh_rail_neighbours(anchor: Vector3i) -> void:
	for side in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var neighbour := workstations.station_at_cell(anchor + side)
		if neighbour.is_empty() or str(workstations.station(neighbour).get("entity_id", "")) != "rail":
			continue
		_remove_station_visual(neighbour)
		_spawn_station_visual(workstations.station(neighbour))


## Rail block: stone corner posts with gold studs, an oak deck and iron rails
## laid toward every connected neighbour — a straight, a 90-degree corner, a
## T or a crossroads follow from the neighbour mask. Ties sit under the rails.
func _build_rail_visual(parent: Node3D, mask: int = 0) -> void:
	_add_collision_box(parent, Vector3(0.98, 0.56, 0.98), Vector3(0.0, -0.22, 0.0))
	var oak := _visual_material(Color("a5672f"), "res://assets/blocks/planks.svg")
	var stone := _visual_material(Color("8b929d"), "res://assets/blocks/castle_stone.svg")
	var iron := _visual_material(Color("8a939b"))
	var gold := _visual_material(Color("e0a72c"), "", Color("f2b33a"))
	_add_mesh_box(parent, Vector3(0.96, 0.36, 0.96), Vector3(0.0, -0.32, 0.0), oak)
	for x in [-0.38, 0.38]:
		for z in [-0.38, 0.38]:
			_add_mesh_box(parent, Vector3(0.22, 0.56, 0.22), Vector3(x, -0.22, z), stone)
			_add_stud(parent, Vector3(x, 0.02, z), gold, Vector3.ZERO)
	# The body may carry a placement rotation; undo it so world-axis arms line up.
	var undo := Node3D.new()
	undo.name = "RailArms"
	undo.rotation.y = -parent.rotation.y
	parent.add_child(undo)
	var along_x := (mask & 3) != 0
	var along_z := (mask & 12) != 0
	if mask == 0:
		along_z = parent.rotation.y == 0.0 or absf(parent.rotation.y) > 3.0
		along_x = not along_z
	var arms: Array[Vector3i] = []
	for index in range(4):
		if mask & (1 << index):
			arms.append([Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)][index])
	if arms.is_empty():
		if along_z:
			arms.append(Vector3i(0, 0, 1))
			arms.append(Vector3i(0, 0, -1))
		else:
			arms.append(Vector3i(1, 0, 0))
			arms.append(Vector3i(-1, 0, 0))
	elif arms.size() == 1:
		arms.append(-arms[0])
	# Two parallel rails per arm from the centre to the cell edge, and ties.
	for arm in arms:
		var direction := Vector3(arm)
		var side := Vector3(direction.z, 0.0, -direction.x)
		for offset in [-0.22, 0.22]:
			_add_mesh_box(undo, Vector3(0.10, 0.10, 0.10) + direction.abs() * 0.40, direction * 0.25 + side * offset, iron)
		_add_mesh_box(undo, Vector3(0.10, 0.06, 0.10) + side.abs() * 0.52, direction * 0.32 + Vector3(0.0, -0.11, 0.0), iron)
	# Centre piece: a plate on corners and junctions so the rails join cleanly.
	if arms.size() >= 2 and not (arms.size() == 2 and arms[0] == -arms[1]):
		_add_mesh_box(undo, Vector3(0.54, 0.10, 0.54), Vector3(0.0, 0.0, 0.0), iron)
	elif not along_x or not along_z:
		_add_mesh_box(undo, Vector3(0.62, 0.06, 0.10) if along_x else Vector3(0.10, 0.06, 0.62), Vector3(0.0, -0.11, 0.0), iron)


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


func _add_collision_box(parent: Node3D, size: Vector3, offset: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = offset
	parent.add_child(collision)


func _add_mesh_box(parent: Node3D, size: Vector3, offset: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
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
	if not world_ready or simulation_paused or saving or player == null or player.camera == null:
		_hide_placement_preview()
		return
	if interaction.drag_active():
		_update_drag_preview(interaction.update_drag_place(player.camera.global_position, -player.camera.global_basis.z, Input.is_action_pressed("interact")))
		return
	var preview := interaction.placement_preview_from_view(player.camera.global_position, -player.camera.global_basis.z)
	if not preview.get("visible", false):
		_hide_placement_preview()
		return
	var anchor: Vector3i = preview.anchor
	var kind := str(preview.get("kind", "entity"))
	var key := "%s|%s|%s|%d|%s" % [kind, str(preview.get("entity_id", preview.get("voxel_id", 0))), anchor, int(preview.rotation_quarters), str(preview.ok)]
	if key == _placement_preview_key:
		return
	_hide_placement_preview()
	_placement_preview = Node3D.new()
	_placement_preview.name = "PlacementPreview"
	_placement_preview.position = Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	_placement_preview.rotation.y = -float(int(preview.rotation_quarters)) * PI / 2.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.2, 0.9, 0.45, 0.48) if preview.ok else Color(0.95, 0.2, 0.2, 0.48)
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
		_hide_placement_preview()
		return
	var key := "drag|%s|%d|%s|%s|%d|%d" % [str(drag.get("blueprint_id", "")), int(drag.voxel_id), drag.anchor, drag.end, int(drag.get("rotation_quarters", 0)), int(drag.affordable)]
	for entry in drag.cells:
		key += "|" + str(entry.state)[0]
	if key == _placement_preview_key:
		return
	_hide_placement_preview()
	_placement_preview = Node3D.new()
	_placement_preview.name = "DragPreview"
	# P3K: plans may mix block types (blueprints), so "ok" materials are keyed
	# by the cell's own voxel so each ghost shows the block it will become.
	var materials := {}
	for state in ["unaffordable", "blocked"]:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color(1.0, 0.8, 0.25, 0.55) if state == "unaffordable" else Color(1.0, 0.25, 0.25, 0.55)
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


func _hide_placement_preview() -> void:
	if _placement_preview != null:
		_placement_preview.queue_free()
		_placement_preview = null
	_placement_preview_key = ""


func _remove_station_visual(instance_id: String) -> void:
	if not _station_visuals.has(instance_id):
		return
	var body: Node = _station_visuals[instance_id]
	body.queue_free()
	if siege_defense != null:
		siege_defense.unregister_visual(instance_id)
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
	if hit.is_empty():
		return {"handled": false}
	var collider: Object = hit.get("collider")
	if collider == null or not collider.has_meta("defense_structure_id"):
		return {"handled": false}
	var structure_id := str(collider.get_meta("defense_structure_id"))
	if structure_id == "training_wall":
		return defense.try_repair(structure_id)
	return workstations.try_repair_structure(structure_id)


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
	if core_defense != null and (core_defense.is_active() or core_defense.state == CoreDefenseService.FAILED):
		defense_changed.emit(core_defense.hud_text() + (siege_defense.hud_suffix() if siege_defense != null else ""))
	elif core_defense != null and core_defense.state == CoreDefenseService.WON:
		defense_changed.emit(core_defense.hud_text() + (siege_defense.hud_suffix() if siege_defense != null else ""))
	elif defense != null:
		defense_changed.emit(defense.hud_text())
