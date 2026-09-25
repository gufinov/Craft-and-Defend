# Minion encampments — the game's first ambient pressure

Owner (2026-09-25): "The evil presence has minion encampments spreading through the land. They roam radius zones. If they discover something, they disrupt or destroy, depending on what they encounter. For example, a mine rail — destroy a track and leave, it stops the rail. Or a tower — attack it until destroyed, then continue patrols. Encampments sit at a fire at night, but in the day patrol a radius zone."

Card E1, branch `feature/encampments`. Until now nothing in the world moved unless the player called a drill: the automation in [INDUSTRY](INDUSTRY.md) was safe simply because no wave was running. It is not any more.

Nothing here is a second AI. The whole card is composed from what already exists:

| What it needs | What it reuses |
|---|---|
| Bodies | `BasicRaider` (orc / brute / troll), configured and spawned exactly as [P4C](P4C_SIEGE_UNITS_AND_WAVES.md) spawns a wave's extras |
| Walking | `LocalGridPathfinder.find_route` over a `NavigationSnapshot` captured through the new public `CoreDefenseService.world_navigation_cell` — the same cell reading a drill plans over, minus the prototype-core special case, so a patrol obeys the breach rules of [RAIDER_PATHING](RAIDER_PATHING.md) |
| Damage to what it finds | `WorkstationService.try_damage` — the structure damage every raider already uses |
| Damage taken | `CoreDefenseService.try_damage_raider_node` / `damage_raiders_within` / `damage_raiders_in_cell`, through a new `foreign_damage` / `foreign_nodes` seam |
| The fire | the existing `campfire` entity, which already lights and flickers |
| Day and night | `DayNightClock` (`SUNRISE_MINUTES` 08:00, `SUNSET_MINUTES` 20:00) |
| World placement | the `_pick_enemy_base` pattern of [P4E](P4E_WORLD_AND_ENEMY_BASE.md): seeded, deterministic, materialised when its ground streams in |

## The model

`game/scripts/defense/encampment_service.gd` (`EncampmentService`, a `Node3D` under `GameSession`, advanced with the other services and paused with the simulation).

A **camp** is a record:

- a **cell** (the fire's centre column) and a **patrol radius**;
- a **fire**: a `campfire` station placed through the ordinary `try_place(..., {"_free": true})` path on a levelled pad. Breaking it is breaking the camp;
- a **garrison** of `BasicRaider` bodies built from the content `garrison` table (2 orcs + 1 brute by default);
- a **state**: `patrolling` between sunrise and sunset, `camping` otherwise — driven by nothing but the clock;
- **cooldowns**: per target kind, after a `break_one`;
- `cleared`: the camp is gone for good (see below).

Each garrison body carries a **phase**: `camping`, `patrolling`, `travelling` (walking to what it found), `sabotaging` (hitting it). A camp state change re-tasks every body.

**Patrol by day.** A body picks a standable cell inside the radius, routes to it, walks it, and picks another when it arrives or when `patrol_leg_seconds` runs out. A body that the route watchdog reports `stuck` simply abandons that leg and picks another next tick — the drill's sidestep / wide-replan / unstick-hop ladder belongs to a wave with a core to reach, not to a patrol.

**Camp by night.** At dusk every body walks back and sits within two cells of the fire, facing it, and stands there (its `active` flag off) until sunrise.

**Discovery.** While patrolling, a body looks around every `patrol_interval_seconds`. It notices the **nearest placed station** inside its **sight radius** that

1. the sabotage table names with a verb other than `ignore`,
2. carries a `defense` sheet (so it can actually be beaten down),
3. is not a camp's own fire,
4. is not under this camp's cooldown, and
5. **is loaded** — `world.query_cell(anchor).state == "LOADED"`.

**Line of sight is deliberately not required on this card.** Distance plus "is loaded" is the whole rule; a wall between a minion and a rail does not hide it. That is a knowingly cheap first cut, and it is written here rather than implied.

**Sabotage.** The body routes to a cell beside the target, and once it is within `STRIKE_REACH` (2.6 m) it hits the target every `attack_interval_seconds` with its own kind's damage, through `WorkstationService.try_damage`. No new damage rules and no new integrity: a rail is 30, a Ballista is 40, a wall is whatever its sheet says.

## The sabotage table

`contracts/content.json` → `encampments.sabotage`: **entity id → verb**. Three verbs:

| Verb | What a patrol does |
|---|---|
| `break_one` | Walks to the **nearest single piece**, destroys that one piece and goes straight back on patrol. The camp then leaves that kind alone for `sabotage_cooldown_seconds`. This is the owner's mine rail: one track gone, the cart stops, the ore stops moving, and the camp does not unpick the whole line in an afternoon. |
| `destroy` | Attacks that structure until it is destroyed, then resumes patrolling — the owner's tower. |
| `ignore` | Never a target. |

**Anything the table does not name is ignored.** A new entity is therefore safe by default and becomes a target only when the owner writes it into the table.

The table as it ships:

| Verb | Entities |
|---|---|
| `break_one` | `rail`, `rail_slope`, `rail_switch`, `rail_loop`, `ore_bin`, `chest`, `mine_cart` |
| `destroy` | `wood_barricade`, `gate`, `double_gate`, `great_gate`, `ballista`, `catapult`, `turret_catapult`, `turret_catapult_mk2`, `cannon`, `kettle`, `miner`, `warehouse` |
| `ignore` | `campfire`, `torch`, `sign`, `foundry` |

`tools/validate_foundation.py` (`validate_encampments`) refuses a table that names an unknown entity, an unknown verb, or a target with no `defense` sheet.

## The knobs (content, not code)

`contracts/content.json` → `encampments`, mirrored to `game/data/content.json` by `tools/format_content.py`:

| Key | Ships as | Meaning |
|---|---|---|
| `enabled` | `true` | Turns the whole system off without a build. |
| `patrol_radius` | `14` | How far a patrol loop wanders from the fire. |
| `sight_radius` | `10` | How far a patrolling minion notices something built. |
| `notice_range` | `80.0` | How far from the player a discovery or a break still puts a line on the HUD. |
| `patrol_leg_seconds` | `18.0` | How long one leg of a patrol loop may take before a new one is picked. |
| `patrol_interval_seconds` | `6.0` | How often a patrolling minion looks around. |
| `sabotage_cooldown_seconds` | `45.0` | How long a camp leaves a kind alone after a `break_one`. |
| `attack_interval_seconds` | `1.4` | Seconds between blows while sabotaging. |
| `garrison` | 2 `raider` + 1 `brute` | Who a camp musters. Only `raider`, `brute`, `troll`. |
| `world` | count 3, band 70–140, separation 48, margin 24, home clear 40 | Where world-generated camps stand. |

`contracts/world.json` → `terrain.encampments` carries the same placement keys and **overrides** the content block, because where camps stand is world generation and belongs beside `terrain.enemy_base`.

## World placement

`EncampmentService.world_sites()` draws `count` sites from an RNG seeded off the world seed: a bearing and a distance in the band, clamped inside the bounds by `margin`, rejected when the column is water, when it is nearer the home clearing than `home_clear_radius`, or within `min_separation` of the enemy base or another camp. The same seed always yields the same camps.

A site is **materialised lazily**, exactly the way `GameSession._ensure_enemy_core` places the enemy core: every two seconds the service checks whether the 3 × 3 pad under a camp has streamed in, and only then levels it, lights the fire and musters the garrison. A camp the player has never walked near costs nothing.

## Clearing a camp for good

Kill the garrison (any weapon — the sword, a trap, a siege splash, all through `CoreDefenseService`'s one damage API) **and** break the fire, and the camp record is marked `cleared`: no garrison, no fire, and nothing ever re-musters it. `cleared` is in the save, so the land stays cleared across a reload. The HUD says so once.

## What the player sees

- **HUD lines** through the ordinary feedback line, whenever a discovery or a break happens within `notice_range`: "A raider is going for your rail — 41 m NNE." / "A brute broke your ballista — 22 m W." A bearing is one of the eight compass points.
- **Minimap**: a camp whose fire is standing is drawn as an orange dot (`MinimapOverlay.encampments`), beside the home and enemy-base markers. Only in a normal game — CoasterCraft and Development hide it exactly as they hide the enemy base.
- **A defeat line** per garrison body, and one line when a camp is cleared.

## Modes

| Mode | Ambient camps |
|---|---|
| Normal game | Yes: `world_sites()` camps, lazily materialised. |
| CoasterCraft | None (`ambient = false`). |
| Development Expo | **None by default** (`ambient = false`). The Frontier exhibit's camp is *registered* by the builder and stays **inert** — no fire, no garrison, nothing patrolling — until its control pedestal's **START ENCAMPMENT**, exactly like the Battlefield and Trap Range controls. `--development-check` asserts it (`no_ambient_waves`). |

## The Expo's Frontier district

`contracts/development_expo.json` → district `frontier` (origin `[104, -1, 60]`, size `[56, 14, 26]`, east of the Trap Range), with:

- **`fr_encampment`** (terrain `frontier_camp`, reset group `frontier`): a levelled dirt clearing with the camp site in the middle, a **12-piece player rail line** eight cells away — inside the camp's sight radius — the control pedestal beside the entrance, and a wide board explaining the rules.
- **`fr_more_camps_reserved`**: a signed, empty parcel for the next ambient-pressure card.

The pedestal is the existing `battlefield_control` entity and the existing panel; `CraftAndDefendApp.control_group()` resolves it to `frontier`, so the panel reads **FRONTIER CONTROL** with **START ENCAMPMENT** and **RESET FRONTIER**. START calls `EncampmentService.start_camp`; RESET goes through `ExpoResetService`, which now stops every camp inside the group's boundary before the fixture is rebuilt — garrison gone, fire out, camp inert, rail line whole.

## Calls made on this card

- **A camp is the existing `campfire` station plus a record**, not a new entity. That keeps the card free of a new item, a new icon, a new recipe-book slot and a new Supply Depot classification, and it makes "break the camp" mean something the player can already do with a pick.
- **Line of sight is not checked** (the card says so): distance plus "is loaded". A minion notices a rail through a wall. Deferred.
- **`break_one` versus `destroy`** differ by what happens *after* the piece falls: `break_one` sets a per-camp, per-kind cooldown and leaves; `destroy` goes back on patrol free to pick the next thing. Per single station the blow-by-blow is identical, because it is the same damage rule.
- **The garrison does not count towards a drill.** `CoreDefenseService.raider_nodes()` is still the drill's own list, so WON, the HUD line and the wave snapshot are untouched; only `damage_raiders_within`, `damage_raiders_in_cell` and `try_damage_raider_node` see camp bodies, through `foreign_nodes` / `foreign_damage`.
- **Siege weapons do not auto-target camp minions.** `nearest_raider_position` is deliberately left drill-only, so a turret does not start shooting at a patrol crossing its arc. A splash that lands on one still hurts it. Deferred to the wave-scheduler card.
- **A stuck patrol just picks another leg.** No sidestep, no wide re-capture, no unstick hop: a patrol has nowhere it must be.
- **The navigation capture is per camp and cached** for two seconds (`CAPTURE_SECONDS`), a box of `radius + 4` cells a side and 22 high. Re-plans are rare (one per patrol leg), so the cost is small.
- **Camps do not fight the player.** They do not chase, and they do not attack the player's body. Aggro on a camp minion is deferred to the next card; killing one is entirely the player's choice for now.

## Tests

`--p4-enemy-units-automation=gate` (all on a levelled plate near spawn, with the world's own camps dropped first so nothing else moves):

| Id | What it proves |
|---|---|
| **T248_ENCAMPMENT_CYCLE** | A camp lit at 12:00 patrols with its campfire standing and all three garrison bodies on patrol; at 22:00 the same clock puts the whole garrison back at the fire; 10:00 sends it out again. |
| **T249_SABOTAGE_RAIL** | A patrol that notices a 9-piece rail line breaks **exactly one** piece (5 blows at 6 damage into 30 integrity), goes straight back on patrol, and the chain walked from the line's near end now stops at the gap. The camp's `rail` cooldown is set. |
| **T250_SABOTAGE_STRUCTURE** | A Ballista is the `destroy` verb: seven blows through `try_damage`, the station is gone, the minion resumes patrolling. |
| **T251_SABOTAGE_TABLE** | With `rail` set to `ignore` the same line is no longer a target, and a Workbench (a kind the table never names) is no target either. |
| **T252_ENCAMPMENT_CLEARED** | Killing all three bodies through the one damage API and breaking the fire clears the camp; a JSON save round trip brings it back cleared, with no fire, no garrison and nothing that re-musters. |

`--development-expo-automation=gate`: **T253_FRONTIER_ENCAMPMENT** — the exhibit stands signed with its rail line and its pedestal, the camp is registered and **inert**, the pedestal's START lights it (fire standing, three bodies out) and **RESET FRONTIER** puts it straight back to inert.

`--development-check`: `no_ambient_waves` now also asserts that no camp is lit or patrolling and that ambient generation is off in Development mode (T211).

## Boundary and next

No wave scheduler (separate card). No new enemy classes. No espionage UI and no player-issued unit commands. Camps do not spread, do not rebuild what they broke, do not garrison a tower they took, and do not grow between days — "spreading through the land" is world generation for now, not a live process. No line of sight. No aggro from a camp onto the player. Next: camps that react to being attacked, camps that spread, and the wave scheduler that decides when a camp escalates into a raid.
