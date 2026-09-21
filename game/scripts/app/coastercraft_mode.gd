class_name CoasterCraftMode
extends Node

## CoasterCraft (docs/COASTERCRAFT_MODE.md): the coaster building game mode
## behind the main menu's CoasterCraft button. A fresh world on the fixed
## seed with a bare 60 x 100 stone plate beside the spawn, creative placement,
## a pack that refills every second with rails, carts, cars, kettles, blocks
## and tools, no raids, no drills. Its saves live in their own
## `<data root>/coastercraft/` coordinator so the real game's slots are
## untouched (settings stay shared). The owner test sandbox
## (`--coaster-sandbox`, CoasterSandbox) is this mode plus its demo tracks.

const SAVE_DIR := "coastercraft"
const TOP_UP_SECONDS := 1.0
## Hotbar order, then the rest of the pack.
const STOCK: Array[String] = ["rail", "rail_slope", "rail_loop", "rail_switch", "rail_cross", "rail_curve", "rail_climb", "mine_cart", "coaster_car", "kettle", "castle_stone", "planks", "iron_pick", "iron_sword", "stone_shot", "flame_shot", "torch", "chest", "wood_axe", "dirt", "stone", "coastercraft_shop"]
## The plate: x -29..30, z 22..121, floor at y 0 (stone), cleared above.
const PLATE_ORIGIN := Vector3i(-29, 0, 22)
const PLATE_WIDTH := 60
const PLATE_DEPTH := 100
## The card levels y 1..13; the far end of the plate reaches terrain that
## may carry mountains (surface up to y 24 plus 20 of rock) and lakes (down
## to y -8), so the clear goes to the world's ceiling and the plate is
## underpinned with stone down to PLATE_FILL_BOTTOM where the ground was air
## or water. Nothing floats over or under the plate.
const PLATE_CLEAR_TOP := 32
const PLATE_FILL_BOTTOM := -8
## Columns levelled per frame once the session is up (terrain streams in
## over seconds; a column waits until its chunks are loaded).
const LEVEL_COLUMNS_PER_FRAME := 120
const WATER := 12
const STONE := 3

var app: CraftAndDefendApp
var saves: SaveCoordinator
## True from the moment New / Continue is pressed until the session leaves
## the mode (exit to menu, quit).
var active := false
var _top_up_left := 0.0
## Plate columns (x, z) still to level, drained a budget per frame.
var _pending_columns: Array[Vector2i] = []
var _levelled_columns := 0


func setup(application: CraftAndDefendApp) -> void:
	app = application
	saves = SaveCoordinator.new(app.data_root.path_join(SAVE_DIR))
	# The fixed default seed: the plate and the sandbox demos are deterministic.
	saves.random_world_seed = false


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
	_pending_columns.clear()
	_levelled_columns = 0


## Called by the app once the world is ready: creative placement, the pack,
## and the plate (a continued save re-levels as a no-op on the saved plate
## and finishes any far end that was never streamed in).
func on_session_ready(fresh: bool) -> void:
	if app.session == null:
		return
	app.session.interaction.creative = true
	app.session.workstations.creative = true
	_pending_columns.clear()
	for x in range(PLATE_WIDTH):
		for z in range(PLATE_DEPTH):
			_pending_columns.append(Vector2i(PLATE_ORIGIN.x + x, PLATE_ORIGIN.z + z))
	_levelled_columns = 0
	# The spawn's corner of the plate right now, and the player lifted onto
	# it: the natural clearing's surface is one lower than the plate, so a
	# player who landed before the stone went in would stand inside it.
	level_area_now(Vector3i(-4, PLATE_ORIGIN.y, 36), 9, 9)
	var player: PlayerController = app.session.player
	if player.global_position.y < float(PLATE_ORIGIN.y + 1) and _on_plate(player.global_position):
		player.global_position.y = float(PLATE_ORIGIN.y) + 1.05
	stock_pack(fresh)
	_top_up_left = TOP_UP_SECONDS


func _process(delta: float) -> void:
	if not active or app == null or app.session == null or not app.session.world_ready or app.session.saving:
		return
	_top_up_left -= delta
	if _top_up_left <= 0.0:
		_top_up_left = TOP_UP_SECONDS
		stock_pack(false)
	_level_pending(LEVEL_COLUMNS_PER_FRAME)


## Levels the plate columns inside the given rectangle right now (the
## sandbox lays its demos on the old 30 x 50 area before its chunks would
## be reached by the per-frame budget) and drops them from the pending list.
func level_area_now(origin: Vector3i, width: int, depth: int) -> void:
	var drop: Dictionary = {}
	for x in range(width):
		for z in range(depth):
			var column := Vector2i(origin.x + x, origin.z + z)
			if _level_column(column):
				drop[column] = true
	if drop.is_empty():
		return
	var remaining: Array[Vector2i] = []
	for column: Vector2i in _pending_columns:
		if not drop.has(column):
			remaining.append(column)
	_pending_columns = remaining


func _on_plate(position: Vector3) -> bool:
	return position.x >= float(PLATE_ORIGIN.x) and position.x < float(PLATE_ORIGIN.x + PLATE_WIDTH) and position.z >= float(PLATE_ORIGIN.z) and position.z < float(PLATE_ORIGIN.z + PLATE_DEPTH)


func pending_columns() -> int:
	return _pending_columns.size()


func levelled_columns() -> int:
	return _levelled_columns


func _level_pending(budget: int) -> void:
	if _pending_columns.is_empty():
		return
	var remaining: Array[Vector2i] = []
	var checked := 0
	for column: Vector2i in _pending_columns:
		if checked >= budget:
			remaining.append(column)
			continue
		checked += 1
		if not _level_column(column):
			remaining.append(column)
	_pending_columns = remaining


## One plate column: stone at y 0, air above to the ceiling, stone under it
## where the ground was air or water. False while its chunks are not loaded.
func _level_column(column: Vector2i) -> bool:
	var world: WorldAdapter = app.session.world
	var floor_cell := Vector3i(column.x, PLATE_ORIGIN.y, column.y)
	if str(world.query_cell(floor_cell).get("state", "")) != "LOADED" or str(world.query_cell(Vector3i(column.x, PLATE_CLEAR_TOP - 1, column.y)).get("state", "")) != "LOADED" or str(world.query_cell(Vector3i(column.x, PLATE_FILL_BOTTOM, column.y)).get("state", "")) != "LOADED":
		return false
	if not world.set_cell(floor_cell, STONE):
		return false
	for y in range(PLATE_ORIGIN.y + 1, PLATE_CLEAR_TOP):
		world.set_cell(Vector3i(column.x, y, column.y), 0)
	for y in range(PLATE_FILL_BOTTOM, PLATE_ORIGIN.y):
		var cell := Vector3i(column.x, y, column.y)
		var voxel := int(world.query_cell(cell).get("voxel_id", STONE))
		if voxel == 0 or voxel == WATER:
			world.set_cell(cell, STONE)
	_levelled_columns += 1
	return true


## Fills every STOCK item to its stack size; with `arrange` the hotbar is
## put in STOCK order (a new plate; a continued save keeps the player's).
func stock_pack(arrange: bool) -> void:
	var inventory: F0Inventory = app.session.inventory
	var registry: ContentRegistry = app.session.registry
	for item_id in STOCK:
		var maximum := registry.max_stack(item_id)
		var have := inventory.count(item_id)
		if maximum > 0 and have < maximum:
			inventory.try_transaction({}, {item_id: maximum - have})
	if not arrange:
		return
	for hotbar_index in range(mini(F0Inventory.HOTBAR_COUNT, STOCK.size())):
		var wanted := STOCK[hotbar_index]
		if str(inventory.slots[hotbar_index].get("item_id", "")) == wanted:
			continue
		for slot_index in range(F0Inventory.SLOT_COUNT):
			if slot_index != hotbar_index and str(inventory.slots[slot_index].get("item_id", "")) == wanted:
				inventory.swap_slots(hotbar_index, slot_index)
				break
	inventory.select_hotbar(0)


## True when the plate reads bare across a sample grid: stone at y 0, air
## at y 1 and y 2, and no station anywhere (the check and T191).
static func plate_bare_report(session: GameSession, step: int = 5) -> Dictionary:
	var sampled := 0
	var stone := 0
	var air := 0
	var unloaded := 0
	for x in range(0, PLATE_WIDTH, step):
		for z in range(0, PLATE_DEPTH, step):
			var floor_cell := PLATE_ORIGIN + Vector3i(x, 0, z)
			var floor_query := session.world.query_cell(floor_cell)
			if str(floor_query.get("state", "")) != "LOADED":
				unloaded += 1
				continue
			sampled += 1
			if int(floor_query.get("voxel_id", 0)) == STONE:
				stone += 1
			if int(session.world.query_cell(floor_cell + Vector3i(0, 1, 0)).get("voxel_id", 1)) == 0 and int(session.world.query_cell(floor_cell + Vector3i(0, 2, 0)).get("voxel_id", 1)) == 0:
				air += 1
	var stations := session.workstations.stations.size()
	return {"ok": sampled > 0 and stone == sampled and air == sampled and stations == 0, "sampled": sampled, "stone": stone, "air": air, "unloaded": unloaded, "stations": stations}
