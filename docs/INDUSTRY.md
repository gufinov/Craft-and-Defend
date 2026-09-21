# Industry chain — wave 1

Owner (2026-09-21): "diggers and miners near ore auto-extract to a container; connect that container to tracks and lead it to a warehouse; a foundry produces whatever ingots you want automatically." The plan and the five cards are in [INDUSTRY_PLAN.md](INDUSTRY_PLAN.md); each card writes its section here (integration merges them).

## Mining: miners and ore bins

Branch `feature/mining-machines`. Suite: `--p4-resources-automation=gate` (T193).

Owner: "we'll also need 'diggers' and 'miners' — place them near ore and they auto extract to a container." This is the mining card of `docs/INDUSTRY_PLAN.md` (wave 1). The other wave-1 cards add the CoasterCraft Shop, the warehouse + foundry and hauling carts; this doc describes the miner and the ore bin and names the seams the other cards plug into.

### The pieces

| Piece | Item / entity | Recipe (Workbench) | What it does |
|---|---|---|---|
| **Miner** | `miner` (1 × 1, `station_type: "miner"`, stands on any solid top) | 4 Iron Ingot, 3 Planks, 2 Stick → 1 (book order 214) | Every `MINER_SECONDS` (8 s) it drills the nearest ore voxel within radius 3 (Chebyshev box, the miner's level and two levels above / below): the voxel becomes stone (voxel 3) and its drop (`iron_ore`, `gold_ore`, `coal` — any block whose `drop` is one of those) goes into an adjacent Ore Bin. No fuel in wave 1 (wave 2: power). |
| **Ore Bin** | `ore_bin` (1 × 1 container, `station_type: "ore_bin"`, `container_slots: 9`) | 6 Planks, 1 Iron Ingot → 1 (book order 215) | An open oak crate. Miners fill it; right-click opens the Chest grid (the same panel as a Chest) to take ore out. A heap of ore-coloured lumps sits on top while it holds anything (more lumps the fuller it is; iron grey, gold yellow, coal black). |

The miner's recipe on the card was 4 / 4 / 2 (ten inputs); the Workbench grid holds nine, so it is 4 Iron Ingot, 3 Planks, 2 Stick.

### How a miner picks its bin

1. The four cells beside the miner (±x, ±z on its level) — the first bin found there with room for the ore.
2. Else any bin whose footprint lies within one cell of the miner (diagonals, one up, one down).

A bin is "full" for an ore when no matching stack has room and no slot is empty (`WorkstationService.container_room`). With no bin the miner idles with **no bin**; with only full bins, **bin full**; with no ore in range, **no ore**. It re-checks every tick, so placing a bin or emptying it is enough — nothing to restart.

### What you see

- **Miner**: a stone base slab with gold studs, two steel posts, a crossbar, a dark motor block and an iron drill cone pointing down. The drill (`Drill` node) spins while the miner's last tick drilled ore and stands still while it is stalled — readable from a distance.
- **Ore Bin**: an oak crate with two iron bands; the heap on top (`OreHeap` node) is rebuilt on every container change (miner insert, cart load, player deposit / withdraw).
- **Right-click a miner**: "Miner: 3 ore mined, drilling iron ore 2 m away." — or "…, no bin. Place an Ore Bin in a cell beside the miner." / "…, bin full. Empty the Ore Bin (right-click it) or let a mine cart collect from it." / "…, no ore. No ore within 3 cells; move the miner next to iron, gold or coal ore." The miner has no menu.
- **Right-click a bin**: the Chest grid. **Shift (interact)** on either says "Use right click to open this station." like other stations.
- Hotbar icons: `icon_miner` (a drill head on a stand), `icon_ore_bin` (an open crate heaped with ore), derived atlas cells 26 and 27 (after `rail_curve`; the wave-1 fixed order is `coastercraft_shop`, `miner`, `ore_bin`, `warehouse`, `foundry` — integration reconciles the cells).

### Chaining (the plan's flow: ore → bin → cart → warehouse → foundry)

1. Find ore (iron shows from depth 6, coal from depth 3, gold from 12 — `docs/P4B_RESOURCE_DISTRIBUTION.md`). Dig a shelf beside the vein: the miner needs a solid top and ore within 3 cells, up to two levels above or below it, so a miner on a ledge above a vein works.
2. Place the miner, then an Ore Bin in a cell beside it. Watch the drill spin; right-click for the count.
3. **Hauling card**: a mine cart passing a cell adjacent to the bin loads up to `CART_CARGO` (16) and unloads at a warehouse. Lay the loop past the bin.
4. **Storage + foundry card**: a foundry beside the warehouse smelts the ore into the ingot you pick.
5. Until those cards land, right-click the bin and carry the ore to a Furnace by hand.

### Code map

- `game/scripts/industry/miner_service.gd` — `MinerService` (`MINER_SECONDS`, `RADIUS`, `LEVELS`, `nearest_ore`, `bins_beside`, `miner_state`, `status_text`, `is_working`; signal `mined(instance_id, cell, item_id, bin_id)`). Created in `GameSession.initialize`, advanced from `GameSession._process` with the other services, paused with the simulation and while saving.
- Per-miner state is in the station record: `"miner": {"cooldown": s, "mined": n, "status": "…"}` — saved by `WorkstationService.snapshot()`, no separate service snapshot. A record without the key (a freshly placed miner, or an old save) starts at a full cooldown, 0 mined, "no ore".
- `WorkstationService.container_room(id, item)` and `container_insert(id, item, amount)` — producer-side container API (no player inventory involved); `container_insert` emits `station_changed` with `INSERTED` so the visual refreshes. The hauling card can use the same pair plus `container_take`.
- `GameSession._build_miner_visual`, `_build_ore_bin_visual`, `_refresh_ore_heap`, `_spin_miner_drills`, `miner_status_line`; `REASON_TEXT` keys `MINER_NO_BIN_HINT`, `MINER_BIN_FULL_HINT`, `MINER_NO_ORE_HINT`.
- `CraftAndDefendApp._show_workstation`: any container station (`workstations.is_container`) that is not a crafting station type opens the Chest grid — this is the seam the warehouse uses too.
- `tools/validate_foundation.py`: attribute roles `machine` and `storage`; a container entity's `station_type` is `chest` or its own id.

### Calls made on this card

- `station_type` is `"ore_bin"` (the validator requires a station type to equal the entity id); the Chest grid is reached through `is_container`, not by adding `ore_bin` to every `== "chest"` check in the app.
- "Six horizontal neighbours" in the card reads as the four side cells first, then the 26-cell shell (which covers the cells above and below).
- The miner's status keeps "drilling …" until the next tick decides otherwise, so the drill spins for one more period after the last ore in range is gone.
- The miner's `navigation.material_tags` are `["iron", "breachable_wood"]` (the raider damage table knows `breachable_wood` and `fortification` only), integrity 40, repaired with one Iron Ingot.

### Tests

`T193_MINER` in `game/scripts/diagnostics/p4_resources_automation.gd` (`--p4-resources-automation=gate`): on a levelled plate near spawn three iron ore voxels within radius 3, a miner and a bin beside it; the service is advanced directly (`advance(MINER_SECONDS + 0.1)`) three times → the bin holds 3 iron ore, the voxels are stone, a far ore stays, a fourth tick changes nothing and the status is "no ore"; the status line and the heap; a bin-less miner reports "no bin" and leaves the ore; a JSON save round-trip through `WorkstationService.restore` keeps the bin's ore and the miner's counter. Recipe book order: `T90` in the p3f presentation gate.

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
- Power / fuel for the Foundry (wave 2), a progress bar in the modal, refunding a Warehouse's contents on dismantle, a wider adjacency (diagonals, other levels). (Live status while the modal is open landed with "Machines run while you are in a menu" below.)

## Hauling

Branch `feature/hauling` (`CoasterCartService`). Suite: `--coaster-car-automation=gate` (T195).

A **mine cart** (`mine_cart`) is a hauler; the rideable `coaster_car` never hauls. Its station record carries `"cargo": {item_id: count}` (saved with `workstations.snapshot()`, validated on restore: known item ids, counts ≥ 0, empty entries dropped), at most `CoasterCartService.CART_CARGO` = 16 items in total, any mix.

Docking happens the moment the cart's rider reaches a track cell (`_dock`, from `_ride` when the target cell is reached): the four horizontal neighbours of that cell, on the same level and one level below, are looked up through `WorkstationService.footprints.owner_at`. An **`ore_bin`** there is a source: the cart takes what the bin holds, stack by stack, up to its free space (`container_take`). A **`warehouse`** there is a sink: the cart puts everything that fits (`container_put`, the new counterpart of `container_take`; `container_room` measures free space). Unloading runs before loading, so a cell with both beside it empties the cart before refilling it. Nothing ever goes from a cart into a bin. Loading and unloading are instant.

One transfer per pass: after a transfer the cell is remembered as the rider's `last_dock`, and no dock is attempted until the cart's cell is at least `REDOCK_CELLS` = 3 cells (straight-line distance) from it. A cart that turns around at a dead end therefore reloads from a bin it left ≥ 3 cells behind, but does not double-dock on a 2 × 2 warehouse that touches two consecutive cells. `last_dock` is rider state (not saved): a loaded game starts the cart at its home cell with a clean slate.

Feedback: `cargo_changed(instance_id, moved, loaded, cell)` is emitted per transfer (unload and load separately). `GameSession._on_cart_cargo_changed` rebuilds the heap and, when the dock cell is within `HAUL_NOTICE_RANGE` = 12 m of the player, puts "Cart loaded 10 iron ore" / "Cart unloaded 10 iron ore" (several items comma-joined, display names lower-cased) on the HUD through the ordinary feedback line, throttled to one line per second (`_haul_notice_msec`). An open Chest panel on the bin or warehouse does not refresh live while the cart docks (it refreshes on the next click); deferred.

Visual: the cart bed's three ore lumps became a `Cargo` node (a `Node3D` under `CartRig`, so it rides; the lumps are `CargoLump` meshes inside it). `_fill_cart_cargo_visual` rebuilds it on every change: colour by the dominant item (iron ore grey-brown with the ore texture, gold ore yellow, coal black, anything else grey), lump scale 0.55 + 0.45 × fill (fill = items / 16), hidden when empty. The lumps stay as nodes when empty so the cart's mesh count (T163's `cart_parts ≥ 18`) holds. `cargo(id)` / `cargo_count(id)` read the cargo for diagnostics.

Placeholders: the hauling branch carried `_wave1_placeholder` `ore_bin` / `warehouse` entities so its test could run alone; integration dropped them (the Mining and Warehouse sections above own the real entries, same ids and slot counts) and `tools/validate_foundation.py` keeps one container rule (`CONTAINER_STATION_TYPES`).

Test: **T195_HAULING** in `--coaster-car-automation=gate` (plate at (−40, 0, 60), a 12-cell straight, the bin beside cell 3, the warehouse beside cell 9): 10 iron ore ride bin → cart (HUD line, heap shown) → warehouse (HUD line, heap hidden); a bin with 20 gives 16 and keeps 4; a mid-haul snapshot/restore keeps the 16; the warehouse ends at 26; a coaster car riding the same straight moves nothing.

Not done (wave 2+): routing choices at junctions, station stop signals, a dispatcher, per-item filters on bins/warehouses. (Live Chest-panel refresh while a cart docks landed with "Machines run while you are in a menu" below.)

## Machines run while you are in a menu

Branch `feature/live-modals`. Owner (2026-09-22): "The furnace does not run when I am inside another menu ... all actions and world events stop when I am in a menu. But they should not stop. Only the game menu should stop the world from continuing."

- **What changed**: the inventory (Tab), the hand-build modal (B) and every station panel no longer pause the simulation or the scene tree. `GameSession.menu_open` (set by `set_menu_open`) freezes the player body (`player.deactivate()`, pointer freed, placement preview hidden, world input swallowed) while `simulation_paused` stays false: the clock ticks, furnace jobs finish, miners fill bins, carts haul, the foundry smelts, fires burn, raiders walk and hit. Only the pause menu (`pause_game(true)`), saving (`saving`) and the error screens pause. The app used to advance the furnace itself while its panel was open (`app._process`); the session does that now, the app only refreshes panels.
- **Live panels** (`app._advance_live_panel`): the furnace bar / timer and the siege column refresh every frame; the Chest / Warehouse / Ore Bin grid and the Foundry status re-read their station every `LIVE_PANEL_REFRESH_SECONDS` (0.25 s); a `station_changed` on the open station with `container_slots` / `furnace_slots` and a `job_completed` on an open furnace rebuild the panel at once.
- **Safety**: no placement / breaking / held-item use / boarding from a menu (the body is inactive, `_unhandled_input` returns while `menu_open`). A raider's hit shows in the open panel's message row (the HUD is hidden under menus); when health reaches 0 the session emits `player_died`, the menu closes (a held cursor stack stays held — it persists) and the respawn runs. **Tab / B are ignored while riding a Coaster Car** ("Leave the coaster car first (Shift).") — the seat moves the body every frame and a menu over the ride would desync it.
- **Calls made**: the message-row mirror only carries damage lines (" hit you "), not every world line, so a panel's own feedback ("Placed the held stack.") is not overwritten by machine chatter. The Shop panel has no timed state and gets no poll. Nothing new is saved: `menu_open` is UI state.
- **Tests**: T199 in `--p3e-container-automation=gate`; T14 (f1), T31 (f5) and T96 (p3g) now assert the new contract (tree not paused, `menu_open`, body inactive).
- **Owner test path**: load a furnace with ore and coal, open the inventory (Tab), wait — the ingot appears and the clock on the HUD has moved when you close; open the furnace panel and watch the bar move; press Escape in the open world — the pause menu freezes everything.

