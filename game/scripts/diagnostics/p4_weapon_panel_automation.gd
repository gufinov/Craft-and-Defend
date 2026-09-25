class_name P4WeaponPanelAutomation
extends Node

## P4a-2 diagnostics: the siege weapon panel (T121), the Chest panel (T122)
## and their rendered layout inside the 1280x720 canvas (T123). The gate
## drives the app's real handlers (select-then-click, Shift gesture, Unload,
## stance, filter, deposit/withdraw); the visual mode also pushes real mouse
## presses through the viewport and saves PNG evidence.

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"gate":
			await _run_gate()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p4_weapon_panel_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P4_WEAPON_PANEL_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P4_WEAPON_PANEL_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var fixture := _place_fixture()
	var catapult_id := str(fixture.catapult_id)
	var chest_id := str(fixture.chest_id)
	var ws: WorkstationService = app.session.workstations

	# ---- T121: weapon panel -------------------------------------------------
	app.state = app.AppState.PLAYING
	app._show_workstation(catapult_id, "catapult")
	var opened_as_siege: bool = app._crafting_station_type == "siege" and app.siege_card.visible and app.siege_legend_card.visible and not app.crafting_grid_card.visible and not app.crafting_recipe_card.visible
	var title_text := str(app.crafting_title_label.text)
	var empty_ammo_text := str(app.siege_panel.ammo_slot._presentation_name)
	var legend_rows := app.siege_legend_list.get_child_count()
	var flame_slot := _slot_for(app.session.inventory, "flame_shot")
	app._select_crafting_inventory_slot(flame_slot)
	var selection_message := str(app.crafting_message.text)
	var flame_highlighted: bool = app.crafting_inventory_slots[flame_slot].is_selected()
	app._on_siege_ammo_slot_pressed()
	var after_one: Dictionary = ws.siege_status(catapult_id).get("details", {})
	var load_one_message := str(app.crafting_message.text)
	app._on_crafting_stack_gesture("siege_ammo", 0, MOUSE_BUTTON_LEFT, false, false, true)
	var after_shift: Dictionary = ws.siege_status(catapult_id).get("details", {})
	var capacity := int(after_shift.get("capacity", 0))
	var full_message := ""
	app._on_siege_ammo_slot_pressed()
	full_message = str(app.crafting_message.text)
	var ammo_tile_text := "%s ×%d" % [app.siege_panel.ammo_slot._presentation_name, app.siege_panel.ammo_slot._presentation_count]
	var stone_slot := _slot_for(app.session.inventory, "stone_shot")
	app._select_crafting_inventory_slot(stone_slot)
	app._on_siege_ammo_slot_pressed()
	var mixed_message := str(app.crafting_message.text)
	var flame_before_unload := app.session.inventory.count("flame_shot")
	app._on_siege_unload_pressed()
	var after_unload: Dictionary = ws.siege_status(catapult_id).get("details", {})
	var flame_after_unload := app.session.inventory.count("flame_shot")
	var unload_disabled_when_empty: bool = app.siege_panel.unload_button.disabled
	app._on_siege_unload_pressed()
	var empty_message := str(app.crafting_message.text)
	app._select_crafting_inventory_slot(_slot_for(app.session.inventory, "planks"))
	var wrong_selection_message := str(app.crafting_message.text)
	app._on_siege_ammo_slot_pressed()
	var wrong_load_message := str(app.crafting_message.text)
	app._on_siege_stance_requested("hold")
	var stance_after_hold := str(ws.siege_status(catapult_id).get("details", {}).get("stance", ""))
	var hold_pressed: bool = app.siege_panel.hold_button.button_pressed and not app.siege_panel.fire_button.button_pressed
	app._on_siege_stance_requested("fire_at_will")
	var stance_after_fire := str(ws.siege_status(catapult_id).get("details", {}).get("stance", ""))
	app.siege_panel.filter_option.select(1)
	app.siege_panel._on_filter_selected(1)
	var filter_after_raider := str(ws.siege_status(catapult_id).get("details", {}).get("target_filter", ""))
	var filter_option_index := app.siege_panel.filter_option.selected
	var supply_empty_text := str(app.siege_panel.supply_label.text)
	# Dragging an inventory tile onto the slot loads as many as fit.
	app._on_crafting_item_dropped("siege_ammo", 0, {"kind": "crafting_item", "source_kind": "inventory", "source_index": _slot_for(app.session.inventory, "stone_shot"), "item_id": "stone_shot"})
	var after_drop: Dictionary = ws.siege_status(catapult_id).get("details", {})
	app._on_siege_unload_pressed()
	# Double-click on a munition tile also loads as many as fit.
	app._on_crafting_stack_gesture("inventory", _slot_for(app.session.inventory, "stone_shot"), MOUSE_BUTTON_LEFT, true, false, false)
	var after_double: Dictionary = ws.siege_status(catapult_id).get("details", {})
	app._on_siege_unload_pressed()
	var closed_by_escape := false
	app._handle_escape_recovery()
	closed_by_escape = app.state == app.AppState.PLAYING and not app.crafting_panel.visible
	var weapon_ok: bool = fixture.ok and opened_as_siege and title_text == "CATAPULT" and empty_ammo_text == "Empty" and legend_rows == 2 \
		and selection_message == "Flame Shot selected — click the Ammunition slot to load 1, Shift+Click loads 5" and flame_highlighted \
		and str(after_one.get("ammo_item", "")) == "flame_shot" and int(after_one.get("ammo", 0)) == 1 and load_one_message.begins_with("Loaded 1 Flame Shot") \
		and int(after_shift.get("ammo", 0)) == capacity and capacity == 5 and full_message == "The weapon is fully loaded." and ammo_tile_text == "Flame Shot ×5" \
		and mixed_message == "Unload the loaded munition before switching to another type." \
		and int(after_unload.get("ammo", 0)) == 0 and flame_after_unload == flame_before_unload + 5 and unload_disabled_when_empty \
		and empty_message == "The weapon is empty — nothing to unload." \
		and wrong_selection_message == "Planks is not ammunition for this weapon. Select Stone Shot or Flame Shot." and wrong_load_message == "That is not ammunition this weapon can fire." \
		and stance_after_hold == "hold" and hold_pressed and stance_after_fire == "fire_at_will" \
		and filter_after_raider == "raider" and filter_option_index == 1 and supply_empty_text == "No chest with munitions within 8 blocks" \
		and str(after_drop.get("ammo_item", "")) == "stone_shot" and int(after_drop.get("ammo", 0)) == 5 and int(after_double.get("ammo", 0)) == 5 and closed_by_escape
	_record("T121_WEAPON_PANEL", weapon_ok, "right-clicking a Catapult opens the weapon panel (title, empty slot, two-row munition legend); selecting Flame Shot then clicking the slot loads 1, Shift loads up to the capacity of 5, a full weapon and a mixed type are refused with readable text, Unload returns every shot and disables when empty, non-ammunition is refused, Hold/Fire at will and the raider filter reach siege_status, the supply readout reports no chest, drag and double-click load as many as fit, and Escape closes the panel", {"opened_as_siege": opened_as_siege, "title": title_text, "legend_rows": legend_rows, "selection_message": selection_message, "after_one": {"ammo": after_one.get("ammo"), "item": after_one.get("ammo_item")}, "load_one_message": load_one_message, "after_shift": after_shift.get("ammo"), "full_message": full_message, "ammo_tile": ammo_tile_text, "mixed_message": mixed_message, "after_unload": after_unload.get("ammo"), "flame_back": flame_after_unload - flame_before_unload, "unload_disabled": unload_disabled_when_empty, "empty_message": empty_message, "wrong_selection_message": wrong_selection_message, "wrong_load_message": wrong_load_message, "stance_hold": stance_after_hold, "hold_pressed": hold_pressed, "stance_fire": stance_after_fire, "filter": filter_after_raider, "filter_index": filter_option_index, "supply_empty": supply_empty_text, "after_drop": after_drop.get("ammo"), "after_double": after_double.get("ammo"), "closed_by_escape": closed_by_escape})

	# ---- T122: chest panel --------------------------------------------------
	app.state = app.AppState.PLAYING
	app._show_workstation(chest_id, "chest")
	var opened_as_chest: bool = app._crafting_station_type == "chest" and app.chest_card.visible and not app.siege_card.visible and not app.crafting_grid_card.visible
	var tile_count := app.chest_panel.slots.size()
	var header_empty := str(app.chest_panel.heading.text)
	var stone_before := app.session.inventory.count("stone_shot")
	var stone_tile := _slot_for(app.session.inventory, "stone_shot")
	app._select_crafting_inventory_slot(stone_tile)
	var chest_selection_message := str(app.crafting_message.text)
	app._on_chest_slot_pressed(4)
	var chest_after_one := ws.container_count(chest_id, "stone_shot")
	app._on_crafting_stack_gesture("chest", 0, MOUSE_BUTTON_LEFT, false, false, true)
	var chest_after_shift := ws.container_count(chest_id, "stone_shot")
	var header_after_deposit := str(app.chest_panel.heading.text)
	var first_tile_text := "%s ×%d" % [app.chest_panel.slots[0]._presentation_name, app.chest_panel.slots[0]._presentation_count]
	# Withdraw 1 with nothing selected (plain click on the chest tile).
	app._crafting_selected_inventory_item = ""
	app._refresh_crafting_panel()
	app._on_chest_slot_pressed(0)
	var chest_after_withdraw_one := ws.container_count(chest_id, "stone_shot")
	var stone_after_withdraw_one := app.session.inventory.count("stone_shot")
	# Deposit 4 more by dragging the inventory stack, then withdraw all by Shift.
	var stone_stack_count := int(app.session.inventory.slots[_slot_for(app.session.inventory, "stone_shot")].get("count", 0))
	app._on_crafting_item_dropped("chest", 3, {"kind": "crafting_item", "source_kind": "inventory", "source_index": _slot_for(app.session.inventory, "stone_shot"), "item_id": "stone_shot"})
	var chest_after_drop := ws.container_count(chest_id, "stone_shot")
	app._on_crafting_stack_gesture("chest", 0, MOUSE_BUTTON_LEFT, false, false, true)
	var chest_after_take_all := ws.container_count(chest_id, "stone_shot")
	var stone_after_take_all := app.session.inventory.count("stone_shot")
	var empty_click_message := ""
	app._on_chest_slot_pressed(8)
	empty_click_message = str(app.crafting_message.text)
	# Leave 4 Stone Shot in the chest for the supply readout.
	app._select_crafting_inventory_slot(_slot_for(app.session.inventory, "stone_shot"))
	app._on_chest_slot_pressed(0)
	app._on_chest_slot_pressed(0)
	app._on_chest_slot_pressed(0)
	app._on_chest_slot_pressed(0)
	app._crafting_selected_inventory_item = ""
	app._on_chest_slot_pressed(0)
	var chest_final := ws.container_count(chest_id, "stone_shot")
	var chest_final_stone_in_pack := app.session.inventory.count("stone_shot")
	app._close_crafting()
	var chest_ok: bool = opened_as_chest and tile_count == 9 and header_empty == "CHEST · 0/9 SLOTS USED" \
		and chest_selection_message == "Stone Shot selected — click a chest tile to store 1, Shift+Click stores 5, double-click stores all" \
		and chest_after_one == 1 and chest_after_shift == 6 and header_after_deposit == "CHEST · 1/9 SLOTS USED" and first_tile_text == "Stone Shot ×6" \
		and chest_after_withdraw_one == 5 and stone_after_withdraw_one == stone_before - 5 \
		and chest_after_drop == 5 + stone_stack_count and chest_after_take_all == 0 and stone_after_take_all == stone_before \
		and empty_click_message == "Chest slot 9 is empty. Select an inventory tile, then click here to store it." \
		and chest_final == 3 and chest_final_stone_in_pack == stone_before - 3
	_record("T122_CHEST_PANEL", chest_ok, "right-clicking a Chest opens a 3 x 3 tile grid with a slots-used header; select-then-click stores 1 and Shift stores 5 into one stack; a plain click on a chest tile takes 1; dragging an inventory stack stores all of it; Shift on the chest tile takes the whole stack back; an empty tile explains itself; totals are conserved", {"opened_as_chest": opened_as_chest, "tiles": tile_count, "header_empty": header_empty, "selection_message": chest_selection_message, "after_one": chest_after_one, "after_shift": chest_after_shift, "header_after_deposit": header_after_deposit, "first_tile": first_tile_text, "after_withdraw_one": chest_after_withdraw_one, "stone_after_withdraw_one": stone_after_withdraw_one, "stone_before": stone_before, "stack_dropped": stone_stack_count, "after_drop": chest_after_drop, "after_take_all": chest_after_take_all, "stone_after_take_all": stone_after_take_all, "empty_click_message": empty_click_message, "chest_final": chest_final, "pack_final": chest_final_stone_in_pack})

	# Supply readout names the chest (4 Stone Shot left, ~4.5 blocks away).
	app.state = app.AppState.PLAYING
	app._show_crafting(catapult_id, "siege")
	var supply_text := str(app.siege_panel.supply_label.text)
	var supply_list := ws.siege_supply(catapult_id)
	app._close_crafting()
	var supply_ok: bool = supply_list.size() == 1 and supply_text.begins_with("Chest ") and supply_text.ends_with("Stone Shot ×3") and supply_text.contains(" m · ")
	_record("T121_SUPPLY_READOUT", supply_ok, "with Stone Shot stored in a chest inside the supply radius the weapon panel lists that chest with its distance and count", {"supply_text": supply_text, "supply": supply_list})


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	# The panel is read as a still, so the simulation is held the way _run_gate
	# holds it. Left running, `siege_defense.advance` reloads the Catapult from
	# the chest four blocks away ("Catapult reloaded 5 stone shot from a nearby
	# chest") between the fixture and the click, and T123's ammunition counts
	# then measure the storage network's reflexes instead of the click's:
	# `ammo_after_click: 5` instead of 4, seen once in a sweep on 2026-09-25.
	app.session.simulation_paused = true
	var fixture := _place_fixture()
	var catapult_id := str(fixture.catapult_id)
	var chest_id := str(fixture.chest_id)
	var ws: WorkstationService = app.session.workstations
	ws.container_deposit(chest_id, "stone_shot", 12)
	ws.siege_load(catapult_id, "flame_shot", 3)
	var viewport_height := get_viewport().get_visible_rect().size.y
	app.state = app.AppState.PLAYING
	app._show_crafting(catapult_id, "siege")
	await _settle_frames(2)
	# Real click path: press the Flame Shot tile, then the Ammunition slot.
	var flame_tile: CraftingItemSlot = app.crafting_inventory_slots[_slot_for(app.session.inventory, "flame_shot")]
	await _click_at(flame_tile.get_global_rect().get_center(), false)
	var clicked_selected := str(app._crafting_selected_inventory_item)
	await _click_at(app.siege_panel.ammo_slot.get_global_rect().get_center(), false)
	var ammo_after_click := int(ws.siege_status(catapult_id).get("details", {}).get("ammo", 0))
	await _click_at(app.siege_panel.ammo_slot.get_global_rect().get_center(), true)
	var ammo_after_shift_click := int(ws.siege_status(catapult_id).get("details", {}).get("ammo", 0))
	await _settle_frames(4)
	var weapon_path := app.data_root.path_join("p4-weapon-panel.png")
	var weapon_saved := await _save_viewport(weapon_path)
	var weapon_message_bottom := app.crafting_message.get_global_rect().end.y
	var weapon_supply_bottom := app.siege_panel.supply_label.get_global_rect().end.y
	var weapon_legend_bottom := app.siege_legend_card.get_global_rect().end.y
	var weapon_fits := weapon_message_bottom <= viewport_height and weapon_supply_bottom <= viewport_height and weapon_legend_bottom <= viewport_height
	app._close_crafting()
	app._show_crafting(chest_id, "chest")
	await _settle_frames(2)
	var stone_tile: CraftingItemSlot = app.crafting_inventory_slots[_slot_for(app.session.inventory, "stone_shot")]
	await _click_at(stone_tile.get_global_rect().get_center(), false)
	var chest_tile: CraftingItemSlot = app.chest_panel.slots[4]
	await _click_at(chest_tile.get_global_rect().get_center(), false)
	var chest_after_click := ws.container_count(chest_id, "stone_shot")
	await _settle_frames(4)
	var chest_path := app.data_root.path_join("p4-chest-panel.png")
	var chest_saved := await _save_viewport(chest_path)
	var chest_message_bottom := app.crafting_message.get_global_rect().end.y
	var chest_grid_bottom := app.chest_panel.grid.get_global_rect().end.y
	var chest_fits := chest_message_bottom <= viewport_height and chest_grid_bottom <= viewport_height
	app._close_crafting()
	var render_ok: bool = fixture.ok and weapon_saved and chest_saved and weapon_fits and chest_fits and clicked_selected == "flame_shot" and ammo_after_click == 4 and ammo_after_shift_click == 5 and chest_after_click == 13
	_record("T123_PANEL_RENDERS", render_ok, "rendered evidence shows the weapon panel (loaded Flame Shot, stance, filter, supply listing the chest, munition legend) and the Chest panel; real viewport clicks select-then-load through CraftingItemSlot; every column ends inside the 720-unit canvas", {"weapon_path": weapon_path, "chest_path": chest_path, "size": get_viewport().get_visible_rect().size, "weapon_message_bottom": weapon_message_bottom, "weapon_supply_bottom": weapon_supply_bottom, "weapon_legend_bottom": weapon_legend_bottom, "chest_message_bottom": chest_message_bottom, "chest_grid_bottom": chest_grid_bottom, "clicked_selected": clicked_selected, "ammo_after_click": ammo_after_click, "ammo_after_shift_click": ammo_after_shift_click, "chest_after_click": chest_after_click})


## Catapult at (7,0,38) on levelled ground plus a Chest 4 blocks away (inside
## the 8-block supply radius) and a pack of munitions and planks.
func _place_fixture() -> Dictionary:
	app.session.inventory.try_transaction({}, {"catapult": 1, "chest": 1, "flame_shot": 8, "stone_shot": 14, "planks": 4})
	var catapult_anchor := Vector3i(7, 0, 38)
	_level_ground(catapult_anchor, 2, 4)
	var chest_anchor := Vector3i(3, 0, 36)
	_level_ground(chest_anchor, 2, 1)
	var catapult := app.session.workstations.try_place("catapult", catapult_anchor, app.session.world.query_cell, app.session.player.get_body_aabb())
	var chest := app.session.workstations.try_place("chest", chest_anchor, app.session.world.query_cell, app.session.player.get_body_aabb())
	var catapult_id := str(catapult.get("details", {}).get("station", {}).get("instance_id", ""))
	var chest_id := str(chest.get("details", {}).get("station", {}).get("instance_id", ""))
	# The Catapult starts with its starting_ammo; empty it so the tests begin
	# from a known state.
	app.session.workstations.siege_unload(catapult_id)
	var ok: bool = catapult.get("ok", false) and chest.get("ok", false)
	if not ok:
		failures.append("fixture placement failed: catapult=%s chest=%s" % [catapult.get("reason"), chest.get("reason")])
	return {"ok": ok, "catapult_id": catapult_id, "chest_id": chest_id}


func _level_ground(anchor: Vector3i, width: int, depth: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(anchor + Vector3i(x, -1, z), 3)
			for y in range(3):
				app.session.world.set_cell(anchor + Vector3i(x, y, z), 0)


## Motion, press and release go in one frame: a frame between press and
## release let the real OS pointer leaving the window send MOUSE_EXIT to the
## hovered button, which cancels `pressed` (the flaky run seen after the
## coaster merge).
func _click_at(global_position: Vector2, shift: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = global_position
	motion.global_position = global_position
	get_viewport().push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.shift_pressed = shift
		event.position = global_position
		event.global_position = global_position
		get_viewport().push_input(event)
	await get_tree().process_frame
	await _settle_frames(2)


func _slot_for(inventory: F0Inventory, item_id: String) -> int:
	for index in range(F0Inventory.SLOT_COUNT):
		if str(inventory.slots[index].get("item_id", "")) == item_id:
			return index
	return -1


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


func _settle_frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _save_viewport(path: String) -> bool:
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	return image != null and image.get_size() == Vector2i(1280, 720) and image.save_png(path) == OK


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
