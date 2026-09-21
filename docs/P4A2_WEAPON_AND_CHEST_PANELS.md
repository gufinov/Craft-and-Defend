# P4a-2 — weapon and chest panels

## Outcome

Owner direction ([design direction §11](DESIGN_DIRECTION_2026-09-18.md)): a placed siege weapon is interactable. Right-click opens its own panel with an ammunition slot, stance and target controls and a readout of the chests it can reload from; the player loads it to its limit and keeps chests nearby. This card is the UI over the P4a-2..4 service logic (`WorkstationService.siege_*` and `container_*`). The UI requests commands; it never mutates weapon or chest state itself.

## Entry point

- `GameSession` reports `OPEN_STATION` for a right-clicked Ballista, Catapult (station type `siege`) or Chest (station type `chest`). `CraftAndDefendApp._show_workstation` accepts the station type or the entity id and resolves the real type through `WorkstationService.station_type`, so siege weapons and Chests open their own panels instead of falling back to hand crafting.
- `_show_crafting(station_id, "siege" | "chest")` reuses the crafting modal shell: title, "Back to Game", the inventory column on the left with the same `CraftingItemSlot` tiles, the shared `crafting_message` label, Escape / Back closing, game paused while open.
- `CRAFTING_STATION_TYPES = ["workbench", "furnace", "siege", "chest"]`; anything else is hand crafting.

## Weapon panel (`SiegeWeaponPanel`, `game/scripts/ui/siege_weapon_panel.gd`)

Middle column, refreshed every frame while open (ammo and cooldown change when the weapon fires or auto-reloads):

- Weapon name and stats: range min–max, damage of the loaded munition (weapon damage when empty), splash radius, reload seconds, Ready / Cooling.
- **Ammunition** slot: a `CraftingItemSlot` (source and target kind `siege_ammo`) showing the loaded munition × count with "ammo / capacity" beside it. Gestures, all through `siege_load(id, item_id, amount)`:
  - select an inventory tile then click the slot → +1; Shift+click the slot → +5;
  - Shift+click an inventory munition tile → +5; double-click an inventory munition tile → as many as fit;
  - drag an inventory tile onto the slot → as many as fit;
  - double-click / Shift+click the slot with nothing selected, or drag the slot onto the inventory → `siege_unload`.
- **Unload** button (`siege_unload`), disabled when empty.
- **Stance** toggles "Fire at will" / "Hold" (`siege_set_stance`).
- **Target** `OptionButton` any / raider / brute / structure (`siege_set_target_filter`).
- **Supply** readout: `siege_supply(id)` lines "Chest 4.5 m · Stone Shot ×12" (nearest first, up to three) or "No chest with <munition|munitions> within N blocks" (N = `definition.supply_radius`; the loaded munition is named because a loaded weapon reloads only its own type).

Right column: a **Munitions** legend with one row per `definition.ammo_items` entry — icon, name, carried count, damage, splash, effect ("impact" or "fire — burns N s, spreads on wood").

Messages (shared label): `WRONG_AMMUNITION` → "That is not ammunition this weapon can fire."; `AMMO_TYPE_LOADED` → "Unload the loaded munition before switching to another type."; `WEAPON_FULL` → "The weapon is fully loaded."; `WEAPON_EMPTY` → "The weapon is empty — nothing to unload."; `NO_RESOURCE` → "None of that item is left to move." Selecting a non-munition tile says which munitions the weapon takes.

## Chest panel (`ChestPanel`, `game/scripts/ui/chest_panel.gd`)

Middle column (fills the modal width): header "CHEST · N/9 SLOTS USED" and the container slots as a 3 × 3 grid of `CraftingItemSlot` tiles (kind `chest`). Gestures:

- drag an inventory tile onto any chest tile → `container_deposit` of the whole stack;
- select an inventory tile, then click a chest tile → deposit 1; Shift → 5; double-click → all carried;
- Shift+click / double-click an inventory tile → deposit 5 / the whole stack;
- plain click a chest tile with nothing selected → `container_withdraw` 1; Shift+click / double-click → the whole stack; drag a chest tile onto the inventory → the whole stack.
- `CONTAINER_FULL` → "The chest has no room for that."

## Plain-click routing

`CraftingItemSlot._gui_input` only intercepts right-clicks, double-clicks, Shift-clicks and clicks while a cursor stack is held; a plain left click reaches the Button `pressed` signal. The ammo slot connects `pressed` → `_on_siege_ammo_slot_pressed`, each chest tile `pressed` → `_on_chest_slot_pressed(index)`, and `stack_gesture` / `item_dropped` route through `_on_crafting_stack_gesture` / `_on_crafting_item_dropped`, which branch on the station type before the furnace logic. Right-click and cursor-stack gestures on inventory tiles keep their inventory behaviour (`_handle_inventory_cursor_gesture`).

## Layout

The modal keeps its 1220 × 680 shell inside the 1280 × 720 canvas. The grid and recipe cards hide for siege / chest; the message label is reparented to the bottom of the visible middle column. T123 asserts message, supply, legend and chest-grid bottoms ≤ 720.

## Acceptance

- T121 weapon panel through the app handlers, T121_SUPPLY_READOUT with a stocked chest in range, T122 chest panel, T123 rendered PNGs (`p4-weapon-panel.png`, `p4-chest-panel.png`) with real viewport clicks.
- `TEST_P4_WEAPON_PANEL.cmd` runs gate (headless) then visual on the exported build.
- Regression: P3G gate + visual (furnace / workbench modal fit, T114/T115 click path), P3E gate, P3C phase1.

## Boundary and next

No cursor-stack pickup from the weapon or chest tiles (right-click on a chest tile takes 1; the cursor stack stays an inventory-only gesture here). No ammunition trough entity. Storage network (2026-09-22, [INDUSTRY.md](INDUSTRY.md#storage-network)): a chest **touching** a weapon (four sides, same level or one up / down) is its ammunition store — a weapon below its clip tops up from it every `SIEGE_AUTO_RELOAD_SECONDS` (2 s), "reloaded from storage" on the HUD; the nearest-chest-in-radius reload for an empty weapon stays as the fallback. Ballista shares the panel unchanged (one munition). Next: P4a-4 fire spread evidence in the world, chest inventory in the HUD look-hint, and the auto-distribution rule for foundry queues.
