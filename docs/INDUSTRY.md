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
- Power / fuel for the Foundry (wave 2), a progress bar in the modal, live status while the modal is open (the simulation pauses under modals), refunding a Warehouse's contents on dismantle, a wider adjacency (diagonals, other levels).
