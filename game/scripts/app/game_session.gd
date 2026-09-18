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
	if not inventory.restore(snapshot.get("inventory", {"dirt": 0, "revision": 0})):
		return {"ok": false, "reason": "INVALID_INVENTORY_SNAPSHOT"}
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
	siege_defense = SiegeDefenseService.new()
	siege_defense.name = "SiegeDefenseService"
	add_child(siege_defense)
	siege_defense.initialize(workstations, core_defense)
	siege_defense.feedback.connect(_on_interaction_feedback)
	siege_defense.state_changed.connect(_on_defense_state_changed)
	interaction = InteractionService.new(world, inventory, player.get_body_aabb, registry, workstations, _raycast_station, _defense_interact)
	player.interaction = interaction
	player.primary_action = _player_primary_action
	world.spawn_area_ready.connect(_on_spawn_area_ready)
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
	if not simulation_paused:
		_melee_cooldown = maxf(0.0, _melee_cooldown - delta)
	if workstations != null and not saving:
		workstations.advance(delta, simulation_paused)
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


func start_core_defense_prototype() -> Dictionary:
	if core_defense == null or not world_ready:
		return {"ok": false, "reason": "WORLD_NOT_READY"}
	if defense != null and defense.is_active():
		return {"ok": false, "reason": "DEFENSE_ALREADY_ACTIVE"}
	if defense != null:
		defense.clear_for_other_mode()
	var result := core_defense.start_prototype()
	if not result.get("ok", false):
		_on_interaction_feedback(str(result.get("reason", "DEFENSE_START_FAILED")))
	return result


func select_hotbar(index: int) -> Dictionary:
	var result := inventory.select_hotbar(index)
	if result.get("ok", false):
		var item_id := str(result.get("item_id", ""))
		_on_interaction_feedback("Selected slot %d%s" % [index + 1, " — " + registry.display_name(item_id) if not item_id.is_empty() else " — empty"])
	return result


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
		status_changed.emit("Core-defense restore failed: %s" % core_restore.get("reason", "UNKNOWN"))
		return
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
	hud_changed.emit("Slot %d: %s   |   %s · %s%s" % [inventory.selected_hotbar + 1, selected_text, clock.period_label(), clock.time_label(), cycle_text])


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
	navigation_changed.emit("HOME  %d m  %s" % [roundi(distance), directions[direction_index]])


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
	if details.has("station"):
		_spawn_station_visual(details.station)
	elif details.has("instance_id") and (details.has("returned_item") or bool(details.get("destroyed", false))):
		_remove_station_visual(str(details.instance_id))
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
	elif entity_id == "catapult":
		_build_catapult_visual(body)
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
	_add_collision_box(parent, Vector3(1.90, 1.10, 1.90), Vector3(0.5, 0.02, 0.5))
	var wood := _visual_material(Color("a96532"), "res://assets/blocks/planks.svg")
	var dark_wood := _visual_material(Color("5b321e"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("aeb7bd"))
	_add_mesh_box(parent, Vector3(1.72, 0.18, 1.16), Vector3(0.5, -0.28, 0.52), dark_wood)
	_add_mesh_box(parent, Vector3(0.22, 0.62, 0.22), Vector3(0.5, 0.02, 0.52), iron)
	_add_mesh_box(parent, Vector3(0.34, 0.14, 1.68), Vector3(0.5, 0.36, 0.28), wood)
	var bow := Node3D.new()
	bow.name = "BallistaBow"
	bow.position = Vector3(0.5, 0.42, -0.20)
	parent.add_child(bow)
	var left_arm := _add_mesh_box(bow, Vector3(0.98, 0.13, 0.17), Vector3(-0.42, 0.0, 0.08), wood)
	left_arm.rotation.y = -0.18
	var right_arm := _add_mesh_box(bow, Vector3(0.98, 0.13, 0.17), Vector3(0.42, 0.0, 0.08), wood)
	right_arm.rotation.y = 0.18
	_add_mesh_box(parent, Vector3(0.07, 0.07, 1.72), Vector3(0.5, 0.48, -0.18), iron)
	_add_mesh_box(parent, Vector3(0.28, 0.05, 0.07), Vector3(0.5, 0.48, -1.02), iron)


func _build_catapult_visual(parent: Node3D) -> void:
	_add_collision_box(parent, Vector3(1.90, 1.55, 1.90), Vector3(0.5, 0.22, 0.5))
	var wood := _visual_material(Color("9b5f30"), "res://assets/blocks/planks.svg")
	var dark_wood := _visual_material(Color("56301d"), "res://assets/blocks/log.svg")
	var iron := _visual_material(Color("737d84"))
	var stone := _visual_material(Color("8f969d"), "res://assets/blocks/stone.svg")
	_add_mesh_box(parent, Vector3(1.74, 0.20, 1.26), Vector3(0.5, -0.28, 0.52), dark_wood)
	_add_mesh_box(parent, Vector3(1.56, 0.12, 0.18), Vector3(0.5, -0.05, 0.12), wood)
	_add_mesh_box(parent, Vector3(1.56, 0.12, 0.18), Vector3(0.5, -0.05, 0.92), wood)
	var wheel_index := 0
	for x in [-0.18, 1.18]:
		for z in [0.08, 0.96]:
			_add_mesh_cylinder(parent, 0.25, 0.16, Vector3(x, -0.30, z), Vector3(0.0, 0.0, PI / 2.0), dark_wood, "CatapultWheel_%d" % wheel_index)
			wheel_index += 1
	for x in [0.05, 0.95]:
		var upright := _add_mesh_box(parent, Vector3(0.16, 1.10, 0.16), Vector3(x, 0.25, 0.52), wood)
		upright.rotation.z = -0.20 if x < 0.5 else 0.20
	_add_mesh_cylinder(parent, 0.10, 1.24, Vector3(0.5, 0.46, 0.52), Vector3(0.0, 0.0, PI / 2.0), iron, "CatapultAxle")
	var arm := _add_mesh_box(parent, Vector3(0.18, 0.18, 1.86), Vector3(0.5, 0.78, 0.34), wood)
	arm.rotation.x = -0.52
	_add_mesh_box(parent, Vector3(0.58, 0.16, 0.52), Vector3(0.5, 1.25, 1.05), dark_wood)
	_add_mesh_cylinder(parent, 0.20, 0.34, Vector3(0.5, 1.38, 1.05), Vector3.ZERO, stone, "CatapultStone")


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
	if core_defense == null or not is_instance_valid(core_defense.raider):
		return {"handled": true, "ok": false, "reason": "SWORD_MISS"}
	var reach := float(weapon.get("range", 3.25))
	var aim_direction := direction.normalized()
	var target_position := core_defense.raider_target_position()
	var target_offset := target_position - origin
	if target_offset.length() > reach or aim_direction.dot(target_offset.normalized()) < 0.94:
		return {"handled": true, "ok": false, "reason": "SWORD_MISS"}
	# Trace to the raider's center instead of past its capsule. This keeps walls as
	# blockers while remaining stable when a diagnostic moves the body directly.
	var query := PhysicsRayQueryParameters3D.create(origin, target_position, 1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.get("collider") != core_defense.raider:
		return {"handled": true, "ok": false, "reason": "SWORD_MISS"}
	var result := core_defense.try_damage_raider(int(weapon.get("damage", 0)), item_id)
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
