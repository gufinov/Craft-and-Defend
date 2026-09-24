# Traps: the service, the attribute block and the two raider rules

Owner direction (2026-09-24, the wave-1 trap card):

1. **Traps cannot be targeted by enemies.** "They are traps by nature and that
   means undetected." A raider never picks a trap as a breach target and never
   attacks one on its way past.
2. **Traps are persistent**, not consumable: each has a **balanced reset time**
   after it fires, like Orcs Must Die. No charges to refill.
3. **If a trap immobilises an enemy** so it cannot reach the core, the enemy
   **attacks the weakest obstacle it can reach** — wall, trap or barricade,
   always the weakest. So a trap *is* attackable once a raider is stuck; rule 1
   governs a raider that still has a route.

This card built the spine — `TrapService`, the Spike Trap, both rules and a
Trap Range in the Development Expo. The next card adds tar, wall blades, a
spring plate and a ceiling dropper by **filling in the attribute block**:
nothing in the service knows what a spike is.

---

## 1. A trap is content

A trap is an ordinary placed entity whose content sheet carries a `trap`
block. That block is the whole tuning, and `tools/validate_foundation.py`
checks it (`TRAP_MOUNTS`, `TRAP_TRIGGERS`, `TRAP_EFFECTS`):

| Key | Meaning |
|---|---|
| `mount` | `floor`, `wall` or `ceiling`. It decides where the trap catches somebody when the block does not say: a floor trap catches whoever stands in its own cells, a ceiling trap reaches `reach` cells down, a wall trap catches the cells it faces |
| `trigger` | `pressure` (a raider's feet cell is in the trigger set) or `proximity` (a raider within `radius` m of the trap centre, ±2 cells vertically) |
| `effect` | `damage` (applied at once) or `slow` (`slow_factor`, `slow_seconds`; needs `BasicRaider.apply_slow`, which the next card adds) |
| `damage` | Damage per firing |
| `radius` | 0 = only the trigger cells; > 0 = every raider within that many metres (`CoreDefenseService.damage_raiders_within`) |
| `reset_seconds` | How long the trap is disarmed after it fires. This is the balance knob rule 2 asks for |
| `fire_seconds` | How long the sprung state lasts (the visual window) |
| `blocks_movement` | `false` (the default) = the cell stays walkable and routes run over it; `true` = the trap is a solid obstacle and catches whoever stands **on** it |
| `trigger_offsets` | Optional explicit trigger cells, rotated with the entity, instead of the `mount` default |
| `reach` | Ceiling mounts only: how far down it reaches (3) |
| `action_travel` | Optional `[x, y, z]` the visual's moving part travels when sprung (default `[0, 0.55, 0]`) |

A trap must also carry a `defense` block (integrity, repair item and amount)
and a `navigation.material_tags` list, because rule 3 makes it attackable and
repairable like any other station. The validator enforces that.

### The Spike Trap

`spike_trap`: floor mount, pressure trigger on its own cell, 8 damage, 24
integrity, **6 s reset**, 1.2 s sprung, repaired with planks. Workbench recipe
229 (2 planks, 2 iron ingots), `siege_and_defense` in the Supply Depot.

Its body has no collision at all — the player and the raiders walk over it —
and two named nodes the service drives: `TrapAction` (the spike bed, hidden
under the floor of its own cell at rest, 0.95 m up when sprung) and `TrapLamp`
(the bead lit only while the trap is armed). Any trap visual that uses those
two names is animated for free; one that does not still works.

## 2. `TrapService` — `game/scripts/defense/trap_service.gd`

Modelled on `FireService`: an `instance_id -> trap state` map ticked every
`TICK_SECONDS` (0.1 s — a raider walking at 2.8 m/s covers 0.28 m in a tick, so
it cannot step over a one-cell trap unseen) from `GameSession._process`, frozen
with the simulation and with a save.

- **Sync.** The map follows what stands in the world: it subscribes to
  `WorkstationService.station_changed` and re-reads the stations on the next
  tick. A newly placed trap arrives armed; a destroyed one leaves.
- **Trigger.** Arithmetic over `CoreDefenseService.raider_nodes()` feet cells —
  **no collision layer and no Area3D** (the repo has neither, and this card
  adds neither).
- **Fire.** The effect is applied, the trap disarms, its own `reset_seconds`
  clock starts. Nothing is consumed (rule 2).
- **State.** `armed`, `reset_seconds_left`, `fire_seconds_left` and
  `fired_count` per trap, written into the session snapshot under `traps` and
  restored from it. Stations come back later than the rest of a save, so a
  restored record waits in `_pending_restore` until its trap is standing
  (`GameSession._on_spawn_area_ready` calls `sync()`).
- **Presentation.** `register_visual(instance_id, body)` from
  `GameSession._spawn_station_visual`; `advance` moves `TrapAction` toward its
  sprung or resting position at `ACTION_SPEED` and lights `TrapLamp` only while
  the trap is armed. Armed / fired / resetting is therefore readable on the
  ground.

## 3. Rule 1 — a trap is undetected

Two things together:

- A trap cell is **walkable**. `WorkstationService.navigation_cell_data`
  returns a trap (unless `blocks_movement`) as a non-solid cell that still
  carries its tags, its **current integrity** and a `trap: true` flag. Routes
  run straight over traps, which is the point of them.
- The obstruction search that picks a breach target
  (`LocalGridPathfinder._best_attack_action`) only ever runs when **no route to
  the goal exists**. A raider with a route never reaches it, so it can never
  name a trap — or anything else — as a target. Walking over a trap and taking
  its damage does not provoke the raider either:
  `damage_raiders_in_cell` deliberately does not call `notify_raider_provoked`,
  so a trap never draws the retaliation a player or a machine does.

## 4. Rule 3 — the weakest obstacle a blocked raider can reach

`CoreDefenseService._basic_raider_capability` asks for `prefer_weakest`, and
the planner then ranks the obstructions around the visited frontier by
**current integrity**, not by type or distance — a trap at 24 is chosen over a
barricade at 30 and over 90-integrity castle stone; beat the barricade down to
5 and the same raider switches to the barricade. Ties break on the old
distance-to-goal score and then on the cell coordinates, so the choice is
deterministic. It costs one pass over the frontier the failed route already
produced: no extra pathfinding pass, nothing per frame.

`prefer_weakest` is also what makes a trap eligible at all, and it excludes a
placed entity with **no `defense` sheet** from the candidates — such a thing
cannot be beaten down however little "integrity" its navigation cell reports,
and choosing one used to strand a blocked raider on `NO_PERMITTED_BREACH`.

Once chosen, a trap is an ordinary structure target: the raider routes to the
cell beside it and `WorkstationService.try_damage` beats it down, so a trap can
be destroyed, repaired with its `repair_item` and restored by an Expo scenario
reset like any other station. A raider standing next to a trap it is chewing on
is of course still standing in a trap.

## 5. The Trap Range (Development Expo)

A new district, `trap_range` (x 56..96, z 60..86), built like any other from
[the manifest](DEVELOPMENT_EXPO.md): one `scenario` exhibit,
`tr_spike_funnel`, whose `trap_range` composite terrain authors a walled lane —
two 3-high castle-stone walls, **three rows of three Spike Traps** in its
floor, the Core of Power capping the far end and a control pedestal beside the
mouth — plus a signed, empty parcel for the four traps that do not exist yet.

The pedestal is the Battlefield's own `battlefield_control` entity. Since this
card the panel follows **whichever pedestal was opened**: it reads the reset
group whose boundary contains that pedestal (`CraftAndDefendApp.control_group`)
and starts that scenario's wave at that scenario's Core — three attackers on
the short line for the Trap Range, the Battlefield's mixed six for the
Battlefield — and RESET restores only that group. With no pedestal open (the
gates call the API directly) it is the Battlefield, exactly as before.

The lane sits east of the CoasterCraft avenue on purpose: an avenue is levelled
when *its* district is built, and a district built later would otherwise clear
walls raised by an earlier one.

## 6. Tests

| Test | Gate |
|---|---|
| **T237_SPIKE_TRAP** | `--p4-siege-units-automation=gate` — a raider standing on an armed trap takes its 8 damage and the trap disarms for its 6 s reset; a second raider standing on it inside that window is unharmed; it re-arms itself and springs on the next body; the armed state, the reset clock and the fired count are in the session save snapshot and restore from it |
| **T238_TRAPS_UNTARGETED** | `--p4-siege-units-automation=gate` — a raider whose only way through a wall is over a trap routes straight over it, never names it (or the wall) as a target, takes its damage in passing and reaches the core with the trap still at full integrity |
| **T239_BLOCKED_RAIDER** | `--p4-siege-units-automation=gate` — a raider sealed in castle stone with no route picks the weakest obstacle it can reach (the trap at 24 over the barricade at 30 and the stone at 90) and really damages it; with the barricade beaten down to 5 it picks the barricade instead |
| **T239_TRAP_RANGE** | `--development-expo-automation=gate` — the Trap Range stands as its manifest record describes it: 33 castle-stone cells a side, nine Spike Traps armed as placed and walkable to the planner, the Core at the far end, the pedestal beside the mouth, both parcels signed, the reserved parcel empty, and the pedestal's scenario resolving to this Core rather than the Battlefield's |
| **T239V_TRAP_RANGE_VIEW** | `--development-expo-automation=visual` — the same lane mid-attack, with a wave coming down it |

`--development-expo-automation=gate` also covers the new district and the new
item through T213 (layout), T215 (signs) and T223 (the Supply Depot).

## 7. Calls made

- **A trap is content, not a subclass.** One `trap` block, one service, one
  validator rule. The next four traps add no branch to `TrapService` beyond an
  `effect` the vocabulary already names.
- **No Area3D and no collision layer.** The card forbids them and the repo has
  none; feet-cell arithmetic at 10 Hz is enough and stays deterministic in the
  gates.
- **The trap cell is walkable rather than invisible.** Making traps invisible to
  the world would have meant a second occupancy model; a walkable cell that
  still reports its integrity gives rule 1 and rule 3 from the same record.
- **`prefer_weakest` is a capability flag, not the planner's new default.** The
  raiders ask for it; `--p2-navigation-automation` and any other caller keep the
  old distance-scored choice, so the navigation contract is untouched.
- **Effect `slow` is declared but unimplemented.** It is the seam tar needs;
  `BasicRaider` has no speed factor yet, so a `slow` trap would count its
  victims and do nothing. The validator accepts it, the service dispatches it,
  and the next card adds `apply_slow`.
- **The save test is in-process.** T237 round-trips the real
  `GameSession.snapshot()` payload through `TrapService.restore`; the
  cross-process Continue path is already gated for stations and waves by T141
  and T226.
- **No `docs/DIRECTION_DEFENCE_AND_RTS.md`.** The card names it, but that file
  does not exist at `b472d16`; this document records what the card implemented
  and [the design direction](DESIGN_DIRECTION_2026-09-18.md) gained a section
  pointing at it.
