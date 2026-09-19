# P4C — siege units (cannon, turret catapult, kettle on rails, ballista remodel) and wave drills

## Outcome

Owner direction (2026-09-19, four reference images and [design direction §11](DESIGN_DIRECTION_2026-09-18.md)): more 3D siege machines, each with a menu, munition types and munition functions; better attack simulations with more units and farther spawns. This card adds four machines as ordinary siege stations on the P4a-2..4 service (`WorkstationService.siege_*`, `SiegeDefenseService`, `FireService`), so every one of them already has the weapon panel, load/unload, stance, target filter, chest supply and auto-reload without new UI code. It also generalises the core-defense drill to waves.

## Content (`contracts/content.json`, mirrored to `game/data/content.json`; keep both with `tools/format_content.py`)

| Entity | Footprint | Mount | Fire mode | Munitions (capacity) | Range | Damage | Reload |
|---|---|---|---|---|---|---|---|
| `ballista` (remodelled) | 2×2 | ground, `light_siege` | direct | ballista_bolt (8) | 4–28 | 6 | 1.5 s |
| `catapult` | 2×4 | ground | ballistic | stone_shot, flame_shot (5) | 8–34 | 9 / 4+fire | 3.2 s |
| `turret_catapult` **new** | 2×2 | ground, `light_siege` (tower platform socket) | ballistic | stone_shot, flame_shot (4) | 6–30 | 9 / 4+fire | 2.8 s |
| `cannon` **new** | 2×3 | ground, `light_siege` | direct | cannonball (4) | 3–32 | 14, splash 1.5 | 4.0 s |
| `rail` **new** | 1×1 | any solid top (wall tops) | — | — | — | — | — |
| `kettle` **new** | 1×1 | `rail_mount` only (on a rail) | **dump** | hot_oil (3) | 0–2.5 horizontal | 6 + fire | 5.0 s |

Munitions table: `cannonball` (14, splash 1.5, impact) and `hot_oil` (6, splash 1.5, fire: burns 6 s, fuel 5 s, spread 0.2, 4 fire damage/s). Items: `cannonball` (stack 16), `hot_oil` (stack 8), `turret_catapult`, `cannon`, `rail` (stack 32), `kettle`. Recipes (Workbench unless noted): cannonball (1 iron ingot + 1 stone → 2, order 176), **hot_oil at the Furnace** (2 logs + 1 coal → 2, 4 s, order 10 — logs are now a furnace input), turret_catapult (4 planks, 2 iron, 3 stone; 191), cannon (6 iron, 4 planks, 2 stone; 192), rail (1 iron + 2 planks → 4; 193), kettle (4 iron + 2 planks; 194). The Workbench book is now three pages (27 recipes).

Validator: `fire_mode` may be `dump`; a dump weapon must carry `rail_speed > 0` and mount only on `rail_mount`. `station_type: "siege"` for every machine.

## Models (`GameSession._build_*_visual`, all turned by `_wrap_siege_turret`)

- **Ballista remodel**: dark-oak base with gold studs, iron pedestal and turntable, oak stock with an iron channel, a `BallistaSlider` carriage that draws back over the reload (`SLIDER_RELEASED_Z` → `SLIDER_DRAWN_Z`) and snaps forward on the shot, `BallistaBolt` shown only while loaded, two forward-swept arms with iron tips and rope strings (`BallistaString_L/R` pivots re-laid each frame from tip to nock), `SiegeMuzzle` at the stock front.
- **Turret catapult**: castle-stone pedestal, iron ring and plate with gold studs, oak deck, short A-frame, `CatapultArm` / `CatapultBucket` / `CatapultStone` — the same node names as the field catapult, so the wind-back and throw animation is shared.
- **Cannon**: oak cheeks and trails with iron bands, two spoked wheels with iron rims and gold hub spikes, an iron `CannonBarrel` on trunnions (rings, breech knob, muzzle bell) that recoils `CANNON_RECOIL` on the shot, a `CannonBall` shown while loaded, `SiegeMuzzle` at the bore; a muzzle flash (light + smoke puffs) spawns at the bore.
- **Rail**: three sleepers and two iron rails along z; chains along a wall top.
- **Kettle**: iron trolley on four wheels (dropped 0.70 into its cell so the wheels rest on the rail), two uprights, an axle, a tilting `KettlePot` with a rim, `KettleOil` (shown while loaded) and a brazier glow; `SiegeMuzzle` at the pouring lip. The pot tilts `POT_DUMP_TILT` on a dump and rights itself.

`SiegeDefenseService._muzzle_position` prefers a `SiegeMuzzle` node, then `CatapultBucket`, then the content `muzzle_offset`.

## Service logic (`SiegeDefenseService`)

- Every weapon picks its own target: `_target_for` → `CoreDefenseService.nearest_raider_position(muzzle, target_filter)` (filters `any` / `raider` / `brute`; `structure` engages nothing yet).
- Fire modes: `direct` (ray; cannonball projectile when the loaded munition is `cannonball`, otherwise the bolt), `ballistic` (arc), **`dump`** (`_dump_trajectory`: target must be at least 0.5 below the lip and within `maximum_range` horizontally; the oil falls to the ground under the target).
- **Rail riding** (`_ride_rails`): a weapon with `rail_speed` collects the connected rail cells under and beside its own rail (`_rail_chain`, 4-neighbours on one level) and moves its turret along the shortest chain path (`_rail_step`) to the cell nearest the target at `rail_speed` cells/s; with no target or no ammunition it returns home. `rail_rider_cell(id)` exposes the current cell. Occupancy never moves — the kettle's cell stays its anchor.
- Impacts resolve where the munition lands: `damage_raiders_within(point, max(splash, 0.9))` hits every raider in the radius; fire munitions light the ground through `FireService.ignite`.
- `hud_suffix` lists every siege entity type present ("cannon 1/2 · kettle 1/3 …").

## Waves (`CoreDefenseService`, P4D)

- `start_prototype(options)` accepts `raiders` (wave size), `brutes` (how many are brutes: 40 health, 10 damage, 0.7× speed, purple with iron pauldrons) and `spawn_distance` (8–28 cells from the arena centre). The arena check also probes the requested spawn cell; the navigation capture widens to cover the spawn line.
- The primary raider keeps the old fields (`raider`, `raider_health`, `try_damage_raider`); extra raiders live in `extra_raiders` with their own health, target, attack timer and phase. Each plans its own route (`_plan_extra`), breaches permitted barricades and hits the core with its own damage. A replan re-routes every raider.
- Damage API: `try_damage_raider_node`, `damage_raiders_within`, `damage_raiders_in_cell` (fire), `nearest_raider_position(from, filter)`, `raider_nodes`, `is_raider_node`, `living_raider_count`. WON only when every raider is down; FAILED halts all of them. The sword strikes whichever raider the ray hits.
- Snapshot adds `spawn_distance`, `wave_size` and `extra_raiders` (kind, health, position); restore respawns and re-plans them.
- Pause menu: **Start Wave Drill (5 raiders + 1 brute, far spawn)** → `{"raiders": 6, "brutes": 1, "spawn_distance": 22}`; the single-raider prototype is unchanged.

## Acceptance

- `--p4-siege-units-automation=gate`: T130 content, T131 cannon, T132 turret catapult on a tower socket, T133 rails + kettle ride + hot-oil dump, T134 ballista presentation, T135 wave drill; `visual`: T136 `p4-siege-units.png` (all five machines in one view).
- `TEST_P4_SIEGE_UNITS.cmd` runs gate then visual on the export.
- Updated expectations: T73/T78 (three recipe pages, search "kettle"), T66 (progression-ordered book; barricade found by search), T90 order list.

## Boundary and next

Raiders do not attack rails or machines. The kettle does not yet refill from chests placed on the wall top automatically beyond the generic supply rule (a chest within 8 cells). No cannon breach damage against stone. Brutes share the raider capability (step 1); a ladder/ram is future. Next: P3K slice 2 (blueprint menu), province/market, raiders targeting structures other than barricades, cannon vs castle stone.
