class_name GameSession
extends Node3D

signal ready_for_play
signal hud_changed(text: String)
signal status_changed(message: String)

var world: WorldAdapter
var player: PlayerController
var inventory := F0Inventory.new()
var interaction: InteractionService
var open_data: Dictionary
var world_ready := false
var saving := false


func initialize(session_data: Dictionary) -> Dictionary:
	open_data = session_data
	var snapshot: Dictionary = session_data.get("snapshot", {})
	if not inventory.restore(snapshot.get("inventory", {"dirt": 0, "revision": 0})):
		return {"ok": false, "reason": "INVALID_INVENTORY_SNAPSHOT"}

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
	interaction = InteractionService.new(world, inventory, player.get_body_aabb)
	player.interaction = interaction
	world.spawn_area_ready.connect(_on_spawn_area_ready)
	world.status_changed.connect(status_changed.emit)
	inventory.changed.connect(_on_inventory_changed)
	player.interaction_feedback.connect(_on_interaction_feedback)
	player.deactivate()
	_on_inventory_changed(inventory.snapshot())
	return {"ok": true}


func _on_spawn_area_ready() -> void:
	if world_ready:
		return
	world_ready = true
	player.activate(not DisplayServer.get_name().contains("headless"))
	status_changed.emit("Ready — left click breaks dirt; right click places it")
	ready_for_play.emit()


func freeze_for_save() -> void:
	saving = true
	if player != null:
		player.deactivate()


func pause_game(paused: bool) -> void:
	if player == null or saving:
		return
	if paused:
		player.deactivate()
	else:
		player.activate(not DisplayServer.get_name().contains("headless"))


func snapshot() -> Dictionary:
	return {
		"schema_version": SaveCoordinator.SAVE_SCHEMA,
		"content_version": SaveCoordinator.CONTENT_VERSION,
		"world": world.snapshot(),
		"inventory": inventory.snapshot(),
		"player": player.snapshot(),
		"session_id": open_data.get("session_id", ""),
	}


func _on_inventory_changed(data: Dictionary) -> void:
	hud_changed.emit("Dirt: %d   |   ESDF move · Space jump · Esc pause" % int(data.get("dirt", 0)))


func _on_interaction_feedback(message: String) -> void:
	status_changed.emit(message.replace("_", " ").capitalize())
