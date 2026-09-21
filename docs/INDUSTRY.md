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

Branch `feature/storage-foundry` (first pass, T194); rewritten by `feature/storage-network` (owner 2026-09-22, T200). Suite: `--p3e-container-automation=gate`.

Owner: "The Foundry seems to work, but I have no visual reference other than text. There should be a bar similar to the furnace and a time. Also, the foundry needs fuel and ore to function. I want all ore and coal that goes to the warehouse to move to the foundry, but only 1 slot for each till the slot is full … Any remaining must stay in the warehouse."

### What the player gets
- **Warehouse** (workbench, `recipe_book_order` 216: 7 Planks + 2 Iron Ingot): a 2 × 2 stone-footed oak shed with **27 slots**. Right-click opens the Chest panel titled WAREHOUSE. A stack of crates appears outside the door while it holds anything. Chests placed beside it, and warehouses beside each other, join its [storage network](#storage-network).
- **Foundry** (workbench, order 217: 6 Castle Stone + 3 Iron Ingot): a 2 × 1 castle-stone furnace body with an iron chimney. It has **three slots like a Furnace — Ore, Fuel, Output — 64 each** (`foundry_slots` in the station record). Placed so that any cell **beside** its footprint (four sides, same level or one up / down) belongs to a container, it works on its own:
  1. **Pull**: every tick it tops the Fuel slot up with Coal and the Ore slot up with the target's ore from the storage network beside it, each up to 64. The rest stays in the storage. Once the Ore slot holds a kind it only tops up that kind until the slot is empty (so "Any" does not mix ores).
  2. **Smelt**: one ingot per job — the furnace recipe's `duration_seconds` (Iron Ingot 5 s, Gold Ingot 8 s; `FOUNDRY_JOB_SECONDS` = 6 s when a recipe has none) — consuming 1 ore + 1 Coal from its own slots into the Output slot.
  3. **Push**: the Output slot goes back into the storage network whenever there is room (ingots land in the Warehouse; a chest beside it takes the overflow). With no room the Output slot fills to 64 and the foundry pauses with **output full**.
- **Status**: **smelting Iron Ingot · 3 s** while a job runs (the mouth `Glow` is lit); **no fuel** / **no ore** when a slot is empty and the storage has none to give; **output full**; **no storage** when nothing touches it and the slots are empty. A foundry with no storage still smelts what you load by hand.
- **Foundry panel** (right-click): title FOUNDRY; the **three slots drawn as the Furnace's** (icons + counts, the same gestures — click a selected ore / Coal then the slot adds 1, Shift+Click 5, double-click collects, right-click picks half / deposits one, drag; "Return Ore + Fuel" empties the input slots into the pack); a **progress bar and time label** ("Iron Ingot · 42% · 2.9 s") for the running job; the inventory column; the target buttons **Any / Iron Ingot / Gold Ingot** (pressed = current; the list follows the registry); the status line with the made count; Close. The panel **polls every 0.25 s** (`FOUNDRY_POLL_SECONDS`) so the slots fill and the bar runs while it is open (it advances nothing itself — the world runs, or not, on its own; while the simulation still pauses under menus the bar holds still). Escape closes.
- **Shift** (interact) on either station explains that right-click opens it; selecting the item in the hotbar prints what it does.

### Contracts and calls made
- `game/scripts/industry/foundry_service.gd` (`FoundryService`, RefCounted, owns a `StorageNetwork`): `recipes()` (furnace recipes whose output id ends in `_ingot`, book order), `targets()`, `state(id)`, `slots(id)` (the live `{ore, fuel, output}` stacks), `set_target(id, target)`, `network_for(id)`, `warehouse_for(id)` (the nearest container, kept for the first pass's callers), `job_seconds(recipe)`, `job_status(id)` (`{active, progress, remaining_seconds, duration_seconds, recipe_id}` — the shape of `WorkstationService.furnace_job_status`), `advance(delta, paused)` → one event per ingot, signal `foundry_changed(id, state)`. Created by `GameSession` beside `workstations`, advanced from `_process`, paused with the simulation.
- Record state: `"foundry": {"target", "made", "elapsed", "recipe_id", "status", "working"}` and `"foundry_slots": {"ore": {item_id, count}, "fuel": …, "output": …}` — saved and restored by `workstations.snapshot()` / `restore()`. `restore` validates the slots (a stack in `ore` must be a furnace-recipe ore, `fuel` the fuel item); a record from before the slots existed (the first pass) gets empty slots.
- One ingot per `advance` call at most (the time over the job length carries, capped at one job). The timer resets when the recipe changes or the foundry idles.
- **Slot gestures are shared with the Furnace**: `WorkstationService.furnace_slots(id)` reads a foundry's `foundry_slots` with `ore` presented as `input`, `_write_furnace_slots` writes them back, so `try_collect_furnace_stack`, `cursor_pick_furnace_stack`, `cursor_deposit_furnace_stack`, `try_transfer_inventory_item_to_furnace` and `try_transfer_inventory_stack_to_furnace` accept a foundry id unchanged; the app's furnace handlers key on `_uses_furnace_slots()` (`furnace` or `foundry`). The Furnace-only pieces (auto-load slider, fuel operations, `try_start_furnace`) stay Furnace-only.
- The foundry also **feeds Furnaces**: `FoundryService.advance` tops any Furnace's Fuel and Raw Input slots up from the storage network beside it the same way (only an empty slot or one holding the same item; the ore is the first furnace-recipe input the storage holds, book order). Pull only — the Furnace keeps its output (the owner did not ask for a push there).
- Recipes deviate from the first card (12 Planks + 2 Iron; 8 Castle Stone + 4 Iron): the validator caps workbench recipes at 9 input items, so they are 7 + 2 and 6 + 3.
- Dismantling a Warehouse follows the Chest rule (the entity item comes back; contents are not refunded) — unchanged, flagged for wave 2.

### Test path (owner)
Workbench → craft Warehouse and Foundry → place the Warehouse on flat ground, the Foundry touching one of its sides → right-click the Warehouse, store Iron Ore and Coal (70 of each if you like) → right-click the Foundry: within a moment the Ore and Fuel slots read 64 and the bar runs (Iron Ingot · 5 s); leave the panel open and watch the ingots go back — right-click the Warehouse: 6 ore and 6 Coal stayed, the ingots pile up. Pick Gold Ingot to switch (the Ore slot empties its iron first). Put a Chest beside the Warehouse: when the Warehouse is full the ingots go into the Chest. Save, reload: the target, the count and the slots are kept.

### Deferred
- Power / fuel for the Foundry (wave 2), a progress bar in the modal, refunding a Warehouse's contents on dismantle, a wider adjacency (diagonals, other levels). (Live status while the modal is open landed with "Machines run while you are in a menu" below.)
- Power for the Foundry (wave 2), live slots while a cart docks with the Chest panel open, refunding a Warehouse's contents on dismantle, a wider adjacency (diagonals), a per-foundry "keep N in the warehouse" reserve.

## Storage network

Branch `feature/storage-network`. Suite: `--p3e-container-automation=gate` (T201, T202). Owner (2026-09-22): "The user can put chests next to a warehouse and that will provide more storage. User can also daisy chain warehouses for even more storage. In the game world, placing any type of storage unit next to something that uses or produces something will provide storage for it. Example, a chest next to a catapult can provide shot, or next to a ballista can provide bolts."

### The rule
`game/scripts/industry/storage_network.gd` (`StorageNetwork`, RefCounted helper over `WorkstationService`): **`network_for(cells) -> Array[String]`** = every container station (`chest`, `ore_bin`, `warehouse` — any record with `container_slots`) whose footprint **touches** any of `cells` (a side neighbour on the four sides, same level or one level above / below), then flood-filled through container-to-container adjacency by the same rule (chests beside a warehouse join it; warehouses daisy-chain; a chest beside that chest joins too). Stations that own the query cells are never members. Order is deterministic: the containers touching the cells nearest the cells' centre first, then the flood in the same order, ties by instance id — so "nearest first" is what `take` drains and `put` fills first. `network_of(instance_id)` = the network around a station's own footprint. `count`, `room`, **`take(network, item, amount) -> taken`** (nearest first), **`put(network, item, amount) -> remaining`** (a full container overflows into the next), `first_present(network, candidates)`. A per-frame cache keyed by the query cells, dropped on every `station_changed`.

### Who uses it
| User / producer | Behaviour |
|---|---|
| **Foundry** | Pulls Coal + ore into its slots, pushes ingots out — see above. |
| **Furnace** | Pulls Coal + ore into its slots (pull only; output stays). |
| **Siege weapons** (catapult, turret catapults, cannon, ballista, kettle) | A weapon **below its clip** asks its network once per `SiegeDefenseService.SIEGE_AUTO_RELOAD_SECONDS` (2 s) for its munition — the loaded kind when any is loaded, else the first of its `ammo_items` the storage holds — and takes up to its capacity (one clip per reload; `WorkstationService.siege_receive_ammo`). The HUD says "Catapult reloaded from storage: 5 stone shot." once per reload when the weapon is within `HAUL_NOTICE_RANGE` (12 m) of the player (signal `storage_reloaded` → `GameSession._on_storage_reloaded`). A chest with the wrong munition does nothing. The older radius rule (an **empty** weapon reloads from the nearest chest within `supply_radius` 8 m, `siege_auto_reload`, 1 s poll) still runs after it. |
| **Miner** | With no `ore_bin` beside it, the ore goes into its network (any chest / warehouse touching it); bins keep priority. |
| **Carts** | Unload into every non-bin container beside the track cell (chests too, and what they chain to) through `StorageNetwork.put` — a full warehouse overflows into the chest beside it; loading stays `ore_bin` only. (The dock now also sees a container one level **above** the track cell, the network rule.) |

### Calls made
- "Adjacent" means the four sides on the same level or one level up / down, nowhere diagonal — the same rule for every user so the owner learns it once.
- `ore_bin` is a container, so it is a network member: a bin beside a warehouse pools with it (the foundry could pull ore straight from a bin beside it). Carts still never unload into bins.
- The foundry's status names the missing thing (**no fuel** / **no ore**) rather than "waiting for …", and **no storage** replaces "no warehouse".

### Tests
- **T200_FOUNDRY_SLOTS** — warehouse with 70 Iron Ore + 70 Coal beside a foundry: one tick → slots 64 / 64, warehouse 6 / 6; one iron job (5.1 s) → one Iron Ingot in the warehouse, slots 63 / 63; state has status / elapsed / working; 2 s later `job_status` is active (> 30 %) and the FOUNDRY panel (three cells, inventory column, no auto-load slider) shows the bar with `value` > 0 and a time; the slots topped back up to 64 (warehouse 5 / 5); `try_collect_furnace_stack(foundry, "input")` hands the 64 ore to the pack and the next tick refills 5; a `WorkstationService` restore keeps the slots.
- **T201_STORAGE_NETWORK** — a chest beside a warehouse beside another warehouse: `network_for` from a cell touching the first lists all three (the first first) and not a chest three cells off; `put` of 10 into a full first warehouse overflows into the rest; `take` drains 1738 across them; `room` counts all three.
- **T202_ADJACENT_AMMO** — an empty catapult beside a chest with 5 Stone Shot and an empty ballista beside a chest with 3 bolts: one `SiegeDefenseService.advance(2.1)` loads 5 and 3 (the chests empty, two "reloaded from storage" lines); a cannon beside a chest of Stone Shot stays empty and the chest keeps its 4.
- T194 keeps covering the first-pass flow (any = iron before gold, target switch, save round-trip, the modals) on the new slots.

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

