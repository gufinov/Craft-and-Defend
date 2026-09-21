# Industry chain — wave 1

Owner (2026-09-21): "diggers and miners near ore auto-extract to a container; connect that container to tracks and lead it to a warehouse; a foundry produces whatever ingots you want automatically." The plan and the five cards are in [INDUSTRY_PLAN.md](INDUSTRY_PLAN.md); each card writes its section here (integration merges them).

## Warehouse and foundry

Branch `feature/storage-foundry`. Suite: `--p3e-container-automation=gate` (T194).

### What the player gets
- **Warehouse** (workbench, `recipe_book_order` 216: 7 Planks + 2 Iron Ingot): a 2 × 2 stone-footed oak shed (door and gold latch on the +z face, gable roof) with **27 slots**. Right-click opens the Chest panel titled WAREHOUSE — the same store / take gestures as a Chest. A stack of crates appears outside the door while it holds anything (one crate per 9 items, up to four; rebuilt on every container change). Siege weapons in supply range reload from it like from a Chest. Hotbar hint on selecting the item.
- **Foundry** (workbench, order 217: 6 Castle Stone + 3 Iron Ingot): a 2 × 1 castle-stone furnace body (spanning +x from the anchor; W / R turn it) with an iron chimney on the far cell, a mouth on the +z face and a mould tray with gold studs. Placed so that any cell **beside** its footprint (same level, four sides) belongs to a Warehouse, it smelts on its own: every **`FOUNDRY_SECONDS` = 10 s** it takes one furnace ingot recipe's inputs (Iron Ingot = Iron Ore + Coal; Gold Ingot = Gold Ore + Coal — read from the registry, not hardcoded) out of the Warehouse and puts the ingot back in. Needs no fuel of its own in wave 1 (the Coal in the recipe is the fuel).
- **Foundry modal** (right-click): title FOUNDRY, one button per target — **Any**, **Iron Ingot**, **Gold Ingot** (the pressed one is current; the list follows the registry) — the status line ("Smelting Iron Ingot · 7 s · made 3", "Waiting for Iron Ore + Coal + Gold Ore", "Warehouse full", "No warehouse") and a Close button. Escape closes. The inventory column is hidden for this panel. **Any** = the first ingot recipe in book order whose inputs the Warehouse holds (iron before gold).
- **Shift** (interact) on either station explains that right-click opens it; selecting the item in the hotbar prints what it does.
- The foundry's mouth glows (node `Glow`) while it is smelting; it goes dark when idle.

### Contracts and calls made
- `game/scripts/industry/foundry_service.gd` (`FoundryService`, RefCounted): `recipes()` (furnace recipes whose output id ends in `_ingot`, sorted by `recipe_book_order` — Hot Oil stays a hand-loaded Furnace job), `targets()`, `state(id)`, `set_target(id, target)`, `warehouse_for(id)`, `advance(delta, paused)` → one event per batch, signal `foundry_changed(id, state)`. Created by `GameSession` beside `workstations`, advanced from `_process`, paused with the simulation (and while any modal is open).
- Per-station state lives in the station record: `"foundry": {"target": "any" | "<recipe id>", "made": n, "elapsed": s, "status": "…", "working": bool}` — saved and restored by `workstations.snapshot()` / `restore()` with no extra service snapshot. `elapsed` is the running cycle; a missing or corrupt block is rebuilt with defaults on first use.
- One batch per `advance` call at most: a long absence does not empty the Warehouse in one frame. The timer resets when the Foundry idles (no warehouse, missing inputs, no room).
- `WorkstationService` gained `container_room(id, item)` and `container_put(id, item, amount)` (a producer adds without touching the player inventory; `CONTAINER_FULL` when nothing fits) and `container_take` now announces its change (`station_changed` with `container_slots`) so container visuals follow it. The session refreshes a Warehouse's crates on any `station_changed` that carries `container_slots`.
- `tools/validate_foundation.py`: containers may carry `station_type` in `CONTAINER_STATION_TYPES = ("chest", "warehouse", "ore_bin")` (the validator needs `station_type == id`, and the old rule pinned containers to `chest`; `ore_bin` is pre-registered for the mining card). `app._show_workstation` opens the Chest panel for **any** container (`is_container`), titled with the entity's display name.
- Recipes deviate from the card (12 Planks + 2 Iron; 8 Castle Stone + 4 Iron): the validator caps workbench recipes at 9 input items (the 3 × 3 grid), so they are 7 + 2 and 6 + 3.
- Icons `icon_warehouse` / `icon_foundry` appended after `rail_curve` in `tools/generate_derived_icons.py` and `tools/measure_item_atlas.py` (the plan's `coastercraft_shop`, `miner`, `ore_bin` were not yet in this worktree; integration reconciles the order).
- Dismantling a Warehouse follows the Chest rule (the entity item comes back; contents are not refunded) — unchanged behaviour, flagged for wave 2.

### Test path (owner)
Workbench → craft Warehouse and Foundry (Iron Ingots from the Furnace) → place the Warehouse on flat ground, the Foundry touching one of its sides → right-click the Warehouse, store Iron Ore and Coal → right-click the Foundry, pick Iron Ingot (or leave Any) → Close; the mouth glows and every 10 s an ingot appears in the Warehouse (crates stack up outside its door). Save, reload: the target and the "made" count are kept.

### Deferred
- Power / fuel for the Foundry (wave 2), a progress bar in the modal, live status while the modal is open (the simulation pauses under modals), refunding a Warehouse's contents on dismantle, a wider adjacency (diagonals, other levels).
