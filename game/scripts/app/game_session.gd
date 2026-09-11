class_name GameSession
extends Node3D

signal ready_for_play
signal hud_changed(text: String)
signal status_changed(message: String)
signal feedback_changed(message: String)
signal inventory_changed(snapshot: Dictionary)
signal workstation_requested(instance_id: String, station_type: String)

const REASON_TEXT := {
	"OK": "Edit complete.",
	"OUT_OF_BOUNDS": "World boundary — that cell is outside the finite test world.",
	"UNLOADED": "That area is still loading; try again in a moment.",
	"OCCUPIED": "Placement rejected — that cell is occupied.",
	"PLAYER_OVERLAP": "Placement rejected — move out of the target cell.",
	"UNSUPPORTED": "Placement rejected — the block needs support below it.",
	"WRONG_TOOL": "That block needs a different tool.",
	"OUT_OF_REACH": "That target is out of reach.",
	"NO_RESOURCE": "No dirt is available to place.",
	"INVENTORY_FULL": "Inventory is full; the block was not removed.",
	"STALE_REVISION": "The world changed before that edit; try again.",
	"PROTECTED": "The bottom bedrock layer is protected.",
	"NO_TARGET": "No editable block is targeted.",
	"MISSING_CONTENT": "That content definition is unavailable.",
	"NOT_PLACEABLE": "The selected hotbar item cannot be placed.",
	"NO_STATION": "Aim at a workbench or furnace, then interact.",
	"OPEN_STATION": "Workstation opened.",
	"WRONG_WORKSTATION": "That recipe needs a different workstation.",
	"INSUFFICIENT_INPUT": "Missing recipe materials.",
	"STATION_BUSY": "That furnace is already working.",
	"SUPPORT_IN_USE": "Dismantle the workstation before removing its support.",
	"JOB_STARTED": "Furnace started; input and fuel were consumed once.",
	"JOB_COMPLETED": "Furnace finished and delivered its reserved output.",
}

var world: WorldAdapter
var player: PlayerController
var registry: ContentRegistry
var inventory: F0Inventory
var crafting: CraftingService
var workstations: WorkstationService
var interaction: InteractionService
var open_data: Dictionary
var world_ready := false
var saving := false
var simulation_paused := false
var _pending_workstation_snapshot: Dictionary = {}
var _station_visuals: Dictionary = {}


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

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("91b8d4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c8dded")
	environment.ambient_light_energy = 0.65
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
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
	var world_result := world.initialize(session_data.working_database, player.position)
	if not world_result.get("ok", false):
		return world_result
	world.revision = int(snapshot.get("world", {}).get("revision", 0))
	interaction = InteractionService.new(world, inventory, player.get_body_aabb, registry, workstations, _raycast_station)
	player.interaction = interaction
	world.spawn_area_ready.connect(_on_spawn_area_ready)
	world.status_changed.connect(status_changed.emit)
	inventory.changed.connect(_on_inventory_changed)
	interaction.result_reported.connect(_on_interaction_result)
	workstations.station_changed.connect(_on_station_changed)
	workstations.job_completed.connect(_on_job_completed)
	player.interaction_feedback.connect(_on_interaction_feedback)
	player.boundary_feedback.connect(_on_boundary_feedback)
	player.deactivate()
	_on_inventory_changed(inventory.snapshot())
	set_process(true)
	return {"ok": true}


func _process(delta: float) -> void:
	if workstations != null and not saving:
		workstations.advance(delta, simulation_paused)


func apply_input_settings(settings_store: SettingsStore) -> void:
	if player != null:
		player.configure_input(settings_store.mouse_sensitivity, settings_store.invert_y)


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
		if station_id.is_empty() or workstations.jobs.has(station_id):
			return {"ok": false, "reason": "STATION_BUSY" if workstations.jobs.has(station_id) else "WRONG_WORKSTATION"}
		return inventory._simulate(recipe.inputs, recipe.outputs)
	return crafting.check_recipe(recipe_id, station_type)


func try_craft(recipe_id: String, station_type: String, station_id: String = "") -> Dictionary:
	var checked := recipe_status(recipe_id, station_type, station_id)
	if not checked.get("ok", false):
		_on_interaction_feedback(str(checked.get("reason", "CRAFT_FAILED")))
		return checked
	var result := workstations.try_start_furnace(station_id, recipe_id) if station_type == "furnace" else crafting.try_craft(recipe_id, station_type)
	_on_interaction_feedback(str(result.get("reason", "CRAFT_FAILED")))
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
	world_ready = true
	player.activate(not DisplayServer.get_name().contains("headless"))
	status_changed.emit("Ready — mine resources, craft in Tab, select hotbar items, place with right click, interact with Shift")
	ready_for_play.emit()


func freeze_for_save() -> void:
	saving = true
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
		"player": player.snapshot(),
		"session_id": open_data.get("session_id", ""),
	}


func _on_inventory_changed(data: Dictionary) -> void:
	var selected := inventory.active_item_id()
	var selected_text := "Empty" if selected.is_empty() else registry.display_name(selected)
	hud_changed.emit("Slot %d: %s   |   ESDF move · A sprint · Z crouch · Shift use · Tab inventory · Esc pause" % [inventory.selected_hotbar + 1, selected_text])
	inventory_changed.emit(data)


func _on_interaction_feedback(message: String) -> void:
	var friendly := str(REASON_TEXT.get(message, message.replace("_", " ").capitalize()))
	status_changed.emit(friendly)
	feedback_changed.emit(friendly)


func _on_boundary_feedback(message: String) -> void:
	status_changed.emit(message)
	feedback_changed.emit(message)


func _unhandled_input(event: InputEvent) -> void:
	if not world_ready or simulation_paused or saving:
		return
	for index in range(F0Inventory.HOTBAR_COUNT):
		if event.is_action_pressed("hotbar_%d" % (index + 1)):
			select_hotbar(index)
			get_viewport().set_input_as_handled()
			return


func _on_interaction_result(result: Dictionary) -> void:
	var changes: Dictionary = result.get("changes", {})
	if result.get("ok", false) and str(result.get("reason", "")) == "OPEN_STATION":
		var station_record: Dictionary = changes.get("station", {})
		workstation_requested.emit(str(changes.get("instance_id", "")), str(station_record.get("entity_id", "")))


func _on_station_changed(result: Dictionary) -> void:
	if not result.get("ok", false):
		return
	var details: Dictionary = result.get("details", {})
	if details.has("station"):
		_spawn_station_visual(details.station)
	elif details.has("instance_id") and details.has("returned_item"):
		_remove_station_visual(str(details.instance_id))


func _on_job_completed(result: Dictionary) -> void:
	_on_interaction_feedback(str(result.get("reason", "JOB_COMPLETED")))


func _spawn_station_visual(record: Dictionary) -> void:
	var instance_id := str(record.get("instance_id", ""))
	if instance_id.is_empty() or _station_visuals.has(instance_id):
		return
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	var body := StaticBody3D.new()
	body.name = "Station_" + instance_id
	body.position = Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	body.set_meta("station_instance_id", instance_id)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	collision.shape = box
	body.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.9, 0.9)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d98b3a") if str(record.get("entity_id", "")) == "workbench" else Color("52616b")
	material.roughness = 0.9
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)
	_station_visuals[instance_id] = body


func _remove_station_visual(instance_id: String) -> void:
	if not _station_visuals.has(instance_id):
		return
	var body: Node = _station_visuals[instance_id]
	body.queue_free()
	_station_visuals.erase(instance_id)


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
