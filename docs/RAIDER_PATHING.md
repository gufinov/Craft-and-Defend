# Raider pathing: watchdogs, step-ups and the stall cases

Owner (2026-09-21, [INDUSTRY_PLAN](INDUSTRY_PLAN.md)): "… fighting mechanics, **AI that gets stuck**, and much more." This is the wave-1 card `feature/raiders-unstuck`. It extends the pathing notes in [P4E](P4E_WORLD_AND_ENEMY_BASE.md) (1.6 s watchdog, sidestep, far march) and the breach rules in [P4C](P4C_SIEGE_UNITS_AND_WAVES.md).

## How a raider moves (today)

- **Planner** (`LocalGridPathfinder`): 4-neighbour A* over a `NavigationSnapshot` captured around the arena (`CoreDefenseService._capture_navigation`: near drills 11 × 5 × 21 cells, far drills 41 × 24 × 41). A cell is standable when feet and head are loaded air and the floor is solid; transitions allow one step up and one drop down. When no route exists `plan_next` picks a breachable obstruction next to a visited cell (`ATTACK_OBSTRUCTION`) using the raider's `damage_per_hit` per material tag (wood at full damage, `fortification` slowly; water and bedrock are protected and never breached).
- **Body** (`BasicRaider`, a `CharacterBody3D` on layer 4 colliding with the world only): walks cell centre to cell centre at 2.8 m/s, a soft separation push keeps bodies out of each other (they never collide), a 1.6 s **route watchdog** (`stuck`) fires when the distance to the next route cell stops shrinking; the drill answers with a back-up-and-sidestep, then a re-plan from where the body stands. Over unloaded ground a far marcher ghost-walks its surface route.
- **Drill** (`CoreDefenseService`): the primary raider drives the state machine, extras carry their own `phase`; with no permitted route the body is parked and re-planned every 2 s (`_stall`, "the enemy never gives up").

## What was built (wave 1)

### Progress watchdog (`BasicRaider.set_goal / clear_goal / progress_stalled`)

Beside the route watchdog the body now tracks the **best horizontal distance to its goal** (the core's centre, or the obstruction it is going to breach; the arena centre while marching). The drill sets the goal whenever it hands out a route or parks the body without one, and clears it while the body deliberately stands (attacking, chasing, a troll shooting, a brute smashing). A re-plan toward the same goal keeps the clock; a new goal resets it. No gain of 0.05 m for:

| Seconds | Stage | Drill response (`_handle_progress_stall`) |
|---|---|---|
| 6 | 1 | Re-capture with a **wider region** (+8 / +4 / +8 cells each side, `_capture_wide`, kept for the rest of the drill) and re-plan with **digging enabled**: the body may now breach natural earth and wood at full damage and natural stone slowly (`stuck_breach` meta, cleared once it reaches the core). Marchers re-march. |
| 12 | 2 | **Unstick hop**: from the body's 8 neighbour cells (one up, level or one down) the walkable cell nearest the goal that is closer than the body stands now; the body is moved there (at most ~1.4 m, never through the goal) and re-plans. Marchers re-march. |
| 20 | 3 | **Stalled out**: the body stands down (no more 2 s retries), one `push_warning` with its position and target (`stall_warnings` counts them, one per body for its whole life), HUD "lead raider stalled". Marchers never stall out (they re-march and restart their clock). |

A stalled-out body gets a fresh chance whenever the world changes inside the snapshot (the player opens a way). Once **no other raider is still fighting** (`_resolve_stalled_out`, from `advance`): a near-drill body that has not been sent back yet is **respawned at the wave's spawn** (if that cell is walkable and moves it) and re-plans; otherwise it **retires** as defeated ("a hopelessly stuck raider gave up") and the drill ends `WON` when it was the last one. No immortal stuck raider holds a wave open.

### Movement

- **One-block step-ups** (`_try_step_up`, 1.02 m with a 0.1 m floor probe, the player's probe pattern): a body whose horizontal motion is blocked, with free space one block up, free motion from there and a floor within reach, is lifted onto the block and snapped down. The old upward impulse (which reached 0.89 m and relied on the capsule sliding over the edge) is now only a fallback after half a second without gain.
- **Shuffle**: standing still (under 15 % of a step) while the separation push is non-zero for 1 s starts a 0.45 s sideways nudge (alternating sides) instead of leaning into the other body. No shoving: only the shuffling body moves.
- `step_ups` and `shuffles` counters on the body for diagnostics.

## Stall cases found (reading the code) and where they stand

| Case | Before | Now | Remains |
|---|---|---|---|
| A 1-block step treated as a wall | Planner allowed it; the body jumped with a 5 m/s impulse that peaks below one block and depended on the capsule sliding over the edge | Step-up assist lifts the body deterministically (T196) | Two-block ledges are walls (by design: `max_step_up` 1) |
| Diagonal squeeze between two blocks | Routes are 4-neighbour, but the body aims straight at the next cell centre; pushed off-centre by separation it clips a block corner; only the 1.6 s watchdog + sidestep helped | 6 s wide re-plan, 12 s hop out of the corner | Routes are not smoothed; corner clipping still costs seconds |
| Target cell on a raised slab / over a void | `_core_approach_cell` checks feet and head air but not a solid floor (a legacy arena uses a fixed cell): the goal is not standable → `INVALID_ENDPOINT` → parked forever with 2 s retries | 20 s stall-out → respawn once → retire, so the wave ends | The approach search should widen to a ring of standable cells (deferred) |
| A one-cell doorway with another raider in it | Raiders never collide; the separation push (≤ 2.2 m/s against 2.8 m/s walking) slows a follower but a frozen body in the gap was frozen for good | A body without progress is re-planned at 6 s (T197); a follower pressed still for 1 s shuffles sideways | Bodies pass through each other (unchanged, intended) |
| Water edges | Water is solid + protected for the planner (never routed, never breached); physically it is walk-through, so a body pushed into water stands in a "solid" cell → `INVALID_ENDPOINT` → parked | 12 s hop to the nearest walkable bank cell; deeper than one cell → stall-out → respawn / retire | No wading, no swimming |
| A destroyed target | Structure gone → `try_damage` fails → re-plan; a broken voxel → re-plan; a chased machine gone → chase ends | Unchanged (covered) | — |
| Far march hand-over point unloaded | Primary: `WAITING_FOR_TERRAIN` retries 40 × 0.5 s then the drill **fails** (`NAVIGATION_CAPTURE_FAILED`); extras: `_plan_extra` returns silently and the body stands forever in phase `marching` | Extras re-march every 6 s until the capture succeeds; marchers never stall out | The primary's 20 s capture limit still fails the drill when the player is far from the core (deferred: keep waiting while the wave is out of the local area) |
| Standing on a rail / slope piece | Entity cells are solid for the planner (`navigation_cell_data`): feet on a rail → `INVALID_ENDPOINT` → parked | 12 s hop to a neighbour, then a normal route | — |
| Pushed onto a block top by another raider | Separation cannot lift a body, but a body pushed sideways into a block is now stepped up; from a 1-high top the route drops down; from a 2-high top no route exists | Wide re-plan → hop (only one down) → stall-out → respawn / retire | A 2-high top with no way down retires the body |
| Walled in by unbreachable blocks (bedrock, water, protected) | Parked with 2 s retries forever | Stall-out at 20 s, one warning, respawn once, then retire; the wave can end (T198) | — |
| Parked by the drill without a route (`_stall`) | Retries every 2 s forever | The progress clock keeps running while parked, so the stages above apply | — |

## Calls made

- The goal for a body heading to breach is the obstruction cell, not the core, so digging in place counts as progress once the cell breaks (the next plan sets the core again).
- "Once a digger, always a digger": `stuck_breach` stays on until the body reaches the core, so a body in a dirt pit does not have to wait 6 s again after every cell.
- The hop considers one down as well as level and one up (the card names "8 neighbours + one up"); a drop of one is walkable by every raider.
- Far-mode stalled-out bodies retire instead of respawning at the enemy base (a 150-cell march for a body the player never saw).
- Time in the fixture tests runs at `Engine.time_scale` 4 with 240 physics ticks per second, so every physics step is still 1/60 s and 20 s of raider time take 5 s of the gate.

## Acceptance

T196 (step-up), T197 (pocket + frozen raider), T198 (stall recovery) in `--p4-siege-units-automation=gate`; T155 (sidestep), T143 (never gives up), T151/T152 keep passing; `--p2-navigation-automation=phase1` unchanged (the planner API is untouched).
