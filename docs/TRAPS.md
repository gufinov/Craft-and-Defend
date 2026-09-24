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
| `mount` | `floor`, `wall` or `ceiling`. It decides where the trap catches somebody when the block does not say: a floor trap catches whoever stands in its own cells, a ceiling trap reaches `reach` cells down, a wall trap catches the cell **directly in front of the wall it hangs on** and the cell under that one (so a trap hung a block up still reaches the feet walking past beneath it). A `wall` or `ceiling` trap must also carry the matching `mount.allowed` entry, because that is what `WorkstationService` hangs it by |
| `trigger` | `pressure` (a raider's feet cell is in the trigger set) or `proximity` (a raider within `radius` m of the trap centre, ±2 cells vertically) |
| `effect` | `damage` (applied at once), `slow` (`slow_factor`, `slow_seconds`) or `push` (`push_speed`, `push_lift`) |
| `damage` | Damage per firing |
| `radius` | 0 = only the trigger cells; > 0 = every raider within that many metres (`CoreDefenseService.damage_raiders_within`) |
| `reset_seconds` | How long the trap is disarmed after it fires. This is the balance knob rule 2 asks for |
| `fire_seconds` | How long the sprung state lasts (the visual window) |
| `blocks_movement` | `false` (the default) = the cell stays walkable and routes run over it; `true` = the trap is a solid obstacle and catches whoever stands **on** it |
| `trigger_offsets` | Optional explicit trigger cells, rotated with the entity, instead of the `mount` default |
| `reach` | Ceiling mounts only: how far down it reaches (3) |
| `action_travel` | Optional `[x, y, z]` the visual's moving part travels when sprung (default `[0, 0.55, 0]`) |
| `push_speed` | `push` only: how fast the body leaves along the trap's facing |
| `push_lift` | Optional upward part of that impulse, so the body is thrown clear instead of skidding |
| `affects_player` | Optional: the trigger catches the player as well as the raiders (the Spring Plate) |
| `ignite` | Optional `{munition, radius}`: after the effect, the trigger cells are lit through `FireService` by a fire munition that already exists |

The key set is **closed**: `tools/validate_foundation.py` refuses a `trap`
block with a key outside that list, so a typo in a tuning value is a failed
gate rather than a trap that quietly does nothing.

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

### The four traps of card 2 — the attribute grammar, worked

Nothing below is code. Each trap is one row of `contracts/content.json`, one
item, one workbench recipe, one icon and one `_build_*_visual` with the
`TrapAction` / `TrapLamp` nodes the service already drives. `TrapService`
gained no branch that names any of them.

**Tar Patch** (recipe 230, 2 coal + 1 planks; 16 integrity, repaired with
coal; `siege_and_defense`):

```json
"trap": {"mount": "floor", "trigger": "pressure", "effect": "slow",
         "damage": 0, "radius": 0.0, "reset_seconds": 4.0, "fire_seconds": 1.5,
         "blocks_movement": false, "slow_factor": 0.4, "slow_seconds": 5.0,
         "action_travel": [0.0, 0.08, 0.0]}
```

The seam the first card left open. `BasicRaider.apply_slow(factor, seconds)`
is now real: `slow_factor` multiplies `move_speed` through one accessor,
`walk_speed()`, so every path that moves a body — the walk, the shuffle, the
ghost walk of a far marcher — is slowed by the same number. The strongest
slow in force wins and the longer clock is kept, so a second tar cell never
makes a raider faster. It clears itself, and it is simulation state: a live
slow rides in the wave snapshot (`raider_slow`, and `slow` per extra raider)
and comes back with the body.

**Wall Blades** (recipe 231, 3 iron ingot + 1 planks; 28 integrity, repaired
with iron ingots; `mount.allowed` `["wall"]`):

```json
"trap": {"mount": "wall", "trigger": "pressure", "effect": "damage",
         "damage": 10, "radius": 0.0, "reset_seconds": 5.0, "fire_seconds": 0.9,
         "blocks_movement": false, "action_travel": [0.62, 0.0, 0.0]}
```

Placement already turns a wall-mounted entity to face away from its wall, so
"the cells in front" is `rotate_offset([1, 0, 0], rotation_quarters)` and
needs no new idea. `action_travel` sweeps the blade wheel out along that same
local +x when the trap fires.

**Spring Plate** (recipe 232, 2 iron ingot + 2 planks; 20 integrity):

```json
"trap": {"mount": "floor", "trigger": "pressure", "effect": "push",
         "damage": 0, "radius": 0.0, "reset_seconds": 3.0, "fire_seconds": 0.6,
         "blocks_movement": false, "push_speed": 5.5, "push_lift": 5.0,
         "affects_player": true, "action_travel": [0.0, 0.50, 0.0]}
```

`push` is the one new effect verb. It is one impulse along the plate's own
facing plus `push_lift` straight up, handed to whoever answers `apply_push` —
`BasicRaider` and, because of `affects_player`, `PlayerController` too. While
the impulse runs the body is under gravity alone and its route does not steer
it; when it lands it emits **`displaced`**, and `CoreDefenseService` answers
by re-capturing the navigation snapshot and re-planning from the cell it came
down in. That is deliberately not the `stuck` signal: a thrown body has
nothing to sidestep out of, it is simply not where its plan thought it was.

**Ceiling Pitch Dropper** (recipe 233, 2 iron ingot + 2 coal + 1 planks; 22
integrity; `mount.allowed` `["ceiling"]`):

```json
"trap": {"mount": "ceiling", "trigger": "pressure", "effect": "damage",
         "damage": 6, "radius": 0.0, "reset_seconds": 8.0, "fire_seconds": 1.4,
         "blocks_movement": false, "reach": 3,
         "ignite": {"munition": "hot_oil", "radius": 1.0},
         "action_travel": [0.0, -0.45, 0.0]}
```

`ignite` is a sub-block, not a second fire system: it names a munition that
already exists in `contracts/content.json` (the validator checks it is there
and that its effect is `fire`) and the session hands `FireService.ignite` to
the service as one callable. The dropper is the trap that needed the ceiling
mount.

## 1b. The ceiling mount

`WorkstationService._wall_side` scanned the four horizontal neighbours, which
was the only reason a ceiling did not work. `_ceiling_side` sits beside it and
hangs an entity whose `mount.allowed` carries `ceiling` under the solid block
above its anchor. Precedence is **ground > wall > ceiling**: `_ceiling_side`
is consulted only after `_wall_side` returned nothing, and it stands aside for
ground it could have stood on and for a wall it could also have taken. The
record is written with `mount: "ceiling"`, which is what makes `restore` skip
the support offsets — a hanging trap has nothing under it, and without that a
loaded save would drop it. Aiming needed nothing: `placement_anchor_from_view`
already returns the last free cell along the ray, so looking up at a ceiling
answers the cell under it. `ATTRIBUTE_MOUNTS` already carried an inert
`"ceiling"`; the entity mount grammar now accepts it too.
[P4G](P4G_CORE_AND_LIGHTS.md) recorded a "no wall/ceiling mounting" boundary
whose wall half had already been superseded; that note now says so in writing
for both halves rather than contradicting the code in silence.

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
mouth — plus (since card 2) the parcel that was signed and empty for exactly this,
now claimed: a signed bay for the **Tar Patch**, the **Wall Blades**, the
**Spring Plate** and the **Ceiling Pitch Dropper**, each holding three of its
trap, and a **combo bay** where a row of Spring Plates faces a spike bed. A
bay is built from the trap's own `trap.mount` and not from its id — a floor
trap goes in the floor, a wall trap gets a three-high stub of castle stone to
hang on, a ceiling trap gets four posts and a slab roof to hang under — so a
fifth trap needs no new builder code. The same pair sits **at the mouth of the
funnel itself**: three Spring Plates facing up the lane, inside the
`trap_range` reset group, so START ATTACK at the pedestal demonstrates the
combo live rather than only describing it on a board.

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
| **T240_TAR_AND_SLOW** | `--p4-siege-units-automation=gate` — a raider crossing tar takes no damage and covers under 60 % of its clear distance over the same second, then recovers on the patch's own clock; the live slow rides in the wave snapshot and restores from it |
| **T241_WALL_BLADES** | `--p4-siege-units-automation=gate` — the blades hang on a wall face (placement and record both `wall`) and refuse bare ground; 10 damage to the cell they face, then their 5 s reset with no second sweep inside it; a routed raider never names them |
| **T242_SPRING_PLATE** | `--p4-siege-units-automation=gate` — a raider is thrown at least two cells along the facing for no damage and re-plans from where it lands; the plate-into-spikes combo kills a raider that neither trap kills alone |
| **T243_CEILING_DROPPER** | `--p4-siege-units-automation=gate` — placed through the player's own aim ray under a roof, refused where there is no ceiling, 6 damage and burning pitch below, and the record still says `ceiling` after a station save round trip |

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
- **Effect `slow` is declared but unimplemented.** (Card 1.) Closed by card 2:
  `BasicRaider.apply_slow` is real and the Tar Patch uses it.
- **The save test is in-process.** T237 round-trips the real
  `GameSession.snapshot()` payload through `TrapService.restore`; the
  cross-process Continue path is already gated for stations and waves by T141
  and T226.
- **No `docs/DIRECTION_DEFENCE_AND_RTS.md`.** The card names it, but that file
  does not exist at `b472d16`; this document records what the card implemented
  and [the design direction](DESIGN_DIRECTION_2026-09-18.md) gained a section
  pointing at it.

## 8. Calls made by card 2

- **Two new attribute keys, no new service branch per trap.** `push` is the
  only new effect verb; `ignite`, `affects_player`, `push_speed` and
  `push_lift` are tuning. The service dispatches on the vocabulary and never on
  an entity id, and the validator's key set is closed so the grammar cannot
  drift.
- **`ignite` names an existing munition.** The dropper burns through
  `FireService` with `hot_oil`, the kettle's own munition, rather than
  inventing a fire model or a new munition row. Radius, burn time and fire
  damage per second are already that munition's.
- **A damage trap hits each caught body once, not once per trigger cell.**
  `CoreDefenseService.damage_raiders_in_cell` forgives a cell of vertical
  slack, so a ceiling trap reaching three cells down used to hit the same
  raider three times. The effect now damages the feet cell of each body the
  trigger actually caught.
- **`displaced` rather than `stuck`.** A thrown body is not wedged; the
  sidestep that answers `stuck` would be wrong for it. The new signal re-plans
  from where it landed and leaves the digging and stall clocks alone.
- **Every new trap is tagged `breachable_wood`.** Rule 3 only works if a
  blocked raider can actually beat the trap down, and that is the tag the
  Spike Trap proved. Iron and stone tags are a balance question for a later
  card, not a silent experiment in this one.
- **The player is pushed but not otherwise caught.** `affects_player` widens
  the *trigger* to the player body; the node-applied effects (push, and slow if
  a trap ever asks for it) reach them, and a damage trap would hurt them
  through `take_damage`. No trap in this card damages the player, because the
  owner's traps are the player's own.
- **The combo bay is a bay and a live demonstration.** A parcel with its own
  sign that the owner can read, plus the same pair inside the funnel where the
  pedestal's wave walks into it. A separate scenario with its own Core and
  pedestal would have given the Trap Range two cores in one reset group.
- **The reserved parcel was claimed, not widened.** The manifest's own
  instruction; `future_district_reserved` still satisfies the validator's
  "at least one visible reserved parcel" rule.
- **T234's What's new no longer names the wall-kit exhibit.** That assertion
  only held while the defence sets card was the newest stamp in the manifest.
  It now asserts what the panel actually promises: a non-empty list, all of it
  at the newest stamp, shorter than the unfiltered one.

