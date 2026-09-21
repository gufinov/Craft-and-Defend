# Industry — machines, bins and how to chain them (wave 1, 2026-09-21)

Owner: "we'll also need 'diggers' and 'miners' — place them near ore and they auto extract to a container." This is the mining card of `docs/INDUSTRY_PLAN.md` (wave 1). The other wave-1 cards add the CoasterCraft Shop, the warehouse + foundry and hauling carts; this doc describes the miner and the ore bin and names the seams the other cards plug into.

## The pieces

| Piece | Item / entity | Recipe (Workbench) | What it does |
|---|---|---|---|
| **Miner** | `miner` (1 × 1, `station_type: "miner"`, stands on any solid top) | 4 Iron Ingot, 3 Planks, 2 Stick → 1 (book order 214) | Every `MINER_SECONDS` (8 s) it drills the nearest ore voxel within radius 3 (Chebyshev box, the miner's level and two levels above / below): the voxel becomes stone (voxel 3) and its drop (`iron_ore`, `gold_ore`, `coal` — any block whose `drop` is one of those) goes into an adjacent Ore Bin. No fuel in wave 1 (wave 2: power). |
| **Ore Bin** | `ore_bin` (1 × 1 container, `station_type: "ore_bin"`, `container_slots: 9`) | 6 Planks, 1 Iron Ingot → 1 (book order 215) | An open oak crate. Miners fill it; right-click opens the Chest grid (the same panel as a Chest) to take ore out. A heap of ore-coloured lumps sits on top while it holds anything (more lumps the fuller it is; iron grey, gold yellow, coal black). |

The miner's recipe on the card was 4 / 4 / 2 (ten inputs); the Workbench grid holds nine, so it is 4 Iron Ingot, 3 Planks, 2 Stick.

## How a miner picks its bin

1. The four cells beside the miner (±x, ±z on its level) — the first bin found there with room for the ore.
2. Else any bin whose footprint lies within one cell of the miner (diagonals, one up, one down).

A bin is "full" for an ore when no matching stack has room and no slot is empty (`WorkstationService.container_room`). With no bin the miner idles with **no bin**; with only full bins, **bin full**; with no ore in range, **no ore**. It re-checks every tick, so placing a bin or emptying it is enough — nothing to restart.

## What you see

- **Miner**: a stone base slab with gold studs, two steel posts, a crossbar, a dark motor block and an iron drill cone pointing down. The drill (`Drill` node) spins while the miner's last tick drilled ore and stands still while it is stalled — readable from a distance.
- **Ore Bin**: an oak crate with two iron bands; the heap on top (`OreHeap` node) is rebuilt on every container change (miner insert, cart load, player deposit / withdraw).
- **Right-click a miner**: "Miner: 3 ore mined, drilling iron ore 2 m away." — or "…, no bin. Place an Ore Bin in a cell beside the miner." / "…, bin full. Empty the Ore Bin (right-click it) or let a mine cart collect from it." / "…, no ore. No ore within 3 cells; move the miner next to iron, gold or coal ore." The miner has no menu.
- **Right-click a bin**: the Chest grid. **Shift (interact)** on either says "Use right click to open this station." like other stations.
- Hotbar icons: `icon_miner` (a drill head on a stand), `icon_ore_bin` (an open crate heaped with ore), derived atlas cells 26 and 27 (after `rail_curve`; the wave-1 fixed order is `coastercraft_shop`, `miner`, `ore_bin`, `warehouse`, `foundry` — integration reconciles the cells).

## Chaining (the plan's flow: ore → bin → cart → warehouse → foundry)

1. Find ore (iron shows from depth 6, coal from depth 3, gold from 12 — `docs/P4B_RESOURCE_DISTRIBUTION.md`). Dig a shelf beside the vein: the miner needs a solid top and ore within 3 cells, up to two levels above or below it, so a miner on a ledge above a vein works.
2. Place the miner, then an Ore Bin in a cell beside it. Watch the drill spin; right-click for the count.
3. **Hauling card**: a mine cart passing a cell adjacent to the bin loads up to `CART_CARGO` (16) and unloads at a warehouse. Lay the loop past the bin.
4. **Storage + foundry card**: a foundry beside the warehouse smelts the ore into the ingot you pick.
5. Until those cards land, right-click the bin and carry the ore to a Furnace by hand.

## Code map

- `game/scripts/industry/miner_service.gd` — `MinerService` (`MINER_SECONDS`, `RADIUS`, `LEVELS`, `nearest_ore`, `bins_beside`, `miner_state`, `status_text`, `is_working`; signal `mined(instance_id, cell, item_id, bin_id)`). Created in `GameSession.initialize`, advanced from `GameSession._process` with the other services, paused with the simulation and while saving.
- Per-miner state is in the station record: `"miner": {"cooldown": s, "mined": n, "status": "…"}` — saved by `WorkstationService.snapshot()`, no separate service snapshot. A record without the key (a freshly placed miner, or an old save) starts at a full cooldown, 0 mined, "no ore".
- `WorkstationService.container_room(id, item)` and `container_insert(id, item, amount)` — producer-side container API (no player inventory involved); `container_insert` emits `station_changed` with `INSERTED` so the visual refreshes. The hauling card can use the same pair plus `container_take`.
- `GameSession._build_miner_visual`, `_build_ore_bin_visual`, `_refresh_ore_heap`, `_spin_miner_drills`, `miner_status_line`; `REASON_TEXT` keys `MINER_NO_BIN_HINT`, `MINER_BIN_FULL_HINT`, `MINER_NO_ORE_HINT`.
- `CraftAndDefendApp._show_workstation`: any container station (`workstations.is_container`) that is not a crafting station type opens the Chest grid — this is the seam the warehouse uses too.
- `tools/validate_foundation.py`: attribute roles `machine` and `storage`; a container entity's `station_type` is `chest` or its own id.

## Calls made on this card

- `station_type` is `"ore_bin"` (the validator requires a station type to equal the entity id); the Chest grid is reached through `is_container`, not by adding `ore_bin` to every `== "chest"` check in the app.
- "Six horizontal neighbours" in the card reads as the four side cells first, then the 26-cell shell (which covers the cells above and below).
- The miner's status keeps "drilling …" until the next tick decides otherwise, so the drill spins for one more period after the last ore in range is gone.
- The miner's `navigation.material_tags` are `["iron", "breachable_wood"]` (the raider damage table knows `breachable_wood` and `fortification` only), integrity 40, repaired with one Iron Ingot.

## Tests

`T193_MINER` in `game/scripts/diagnostics/p4_resources_automation.gd` (`--p4-resources-automation=gate`): on a levelled plate near spawn three iron ore voxels within radius 3, a miner and a bin beside it; the service is advanced directly (`advance(MINER_SECONDS + 0.1)`) three times → the bin holds 3 iron ore, the voxels are stone, a far ore stays, a fourth tick changes nothing and the status is "no ore"; the status line and the heap; a bin-less miner reports "no bin" and leaves the ore; a JSON save round-trip through `WorkstationService.restore` keeps the bin's ore and the miner's counter. Recipe book order: `T90` in the p3f presentation gate.
