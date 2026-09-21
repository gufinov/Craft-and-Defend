# CoasterCraft mode and the industry chain — plan (owner 2026-09-21)

Owner: "add CoasterCraft as a game mode … clear the foundation, double its size, continue or start new, its own menu … no monsters. Back to the real game: rails and carts need their own foundry — a CoasterCraft Shop you unlock and build; diggers and miners near ore auto-extract to a container; connect that container to tracks and lead it to a warehouse; a foundry produces whatever ingots you want automatically. Then mining resources, storage, building defenses, fighting mechanics, AI that gets stuck, and much more."

## What we can do now (wave 1, five cards in parallel)

| Card | Branch | Delivers |
|---|---|---|
| CoasterCraft mode | `feature/coastercraft-mode` | Main-menu **CoasterCraft**: its own saves (`<data root>/coastercraft/`), **Continue / New**, a bare 60 × 100 stone plate (nothing on it), infinite stock, no waves / drills, its own pause menu (Resume, Save, Restart, Exit to menu, Quit). The test sandbox (`--coaster-sandbox`) keeps its demos for the gates. |
| CoasterCraft Shop | `feature/coastercraft-shop` | Workstation `coastercraft_shop` (workbench recipe; a 2 × 1 machine with the coaster look). Rails, slopes, loops, switches, crossings, curves, climbs, mine carts and coaster cars move from the workbench book to the shop's book. Nothing coaster is craftable until the shop is built. |
| Mining machines | `feature/mining-machines` | `miner` (a digger: 1 × 1 machine with a drill head) placed within 2 cells of ore: every `MINER_SECONDS` it mines the nearest ore voxel in radius 3 (the voxel becomes stone) into an adjacent **`ore_bin`** (1 × 1 container, 9 slots, chest UI). Full bin = idle. Needs no fuel (wave 2: power). |
| Storage + foundry | `feature/storage-foundry` | **`warehouse`** (2 × 2 container, 27 slots, chest UI). **`foundry`** (2 × 1): adjacent to a warehouse, pulls ore + coal from it and smelts the chosen ingot (pick the recipe in its modal; "any" = whatever ore is there) every `FOUNDRY_SECONDS`, output back into the warehouse. |
| Hauling carts | `feature/hauling` | A mine cart passing a cell adjacent to an `ore_bin` **loads** up to `CART_CARGO` (16) items; passing a `warehouse` **unloads**. Cargo drawn in the cart. Kettles unchanged. Circuits: bin ↔ warehouse on a loop with a lane switch. |
| Raiders unstuck | `feature/raiders-unstuck` | Raider stuck handling: second watchdog (6 s without progress → re-plan from scratch with a wider search; 12 s → step to the nearest reachable cell toward the target); one-block step-ups; a `T` test with a raider boxed by a fence gap. |

Contracts shared between the cards (fixed here so they can run in parallel): container entities carry `"station_type": "chest"`-style slots (`container_slots`), reusing `WorkstationService` container APIs; item ids `ore_bin`, `warehouse`, `foundry`, `miner`, `coastercraft_shop`; recipe orders 213–217; icons appended in that order in `tools/generate_derived_icons.py` / `tools/measure_item_atlas.py`; `COASTER_TOOLS` unchanged.

## What we cannot do yet (wave 2+, after the owner plays wave 1)
- Powered machines (fuel / power lines) — miners and foundries run free in wave 1.
- Cart routing choices at junctions (a cart goes straight through a "+" and follows lane switches); a real dispatcher / station stop signals.
- Fighting mechanics (blocking, combos, ranged aim assist), defense building sets (walls kit, gates, turrets on rails) — owner to pick the first pieces.
- Enemy camp props / patrols, win condition.
- Save migration for old saves that contain workbench-crafted coaster items: they stay usable (items are items); only the recipes move.

## Owner test path after wave 1
`worktrees\p3d-tools-world-feedback` → `START_GAME` → main menu **CoasterCraft** (bare plate, New / Continue, its pause menu) and the real game: craft the CoasterCraft Shop at the workbench, place it, craft rails / carts there; place a miner by iron ore with an ore bin beside it; lay a loop past the bin to a warehouse with a mine cart; put a foundry beside the warehouse and pick Iron Ingot; watch ore flow to ingots.
