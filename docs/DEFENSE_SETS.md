# Defence sets — a working gate, a wall kit and a turret on rails

The Construction Yard already showed the castle pieces. This card makes them a
**system**: a defensive line you build in one gesture, open and close where you
choose, and fight from while it moves. It adds no enemy or weapon class, no
fighting mechanic and no win condition — every piece rides machinery that was
already here ([P3J drag building](P3J_DRAG_BUILDING.md), [P3K blueprints](P3K_BLUEPRINTS.md),
[P4C siege units](P4C_SIEGE_UNITS_AND_WAVES.md), [raider pathing](RAIDER_PATHING.md),
[the castle kit plan](CASTLE_CONSTRUCTION_AND_CRAFTING.md)).

## 1. The gate

`gate_frame` has always been a three-wide, three-high frame with its middle
column deliberately unoccupied — "doors, portcullises and drawbridges remain
later mechanisms" ([castle plan](CASTLE_CONSTRUCTION_AND_CRAFTING.md)). The
**Gate** is the leaf that hangs in that column.

| | |
|---|---|
| Entity | `gate`, 1 × 2 cells (`occupied_offsets` `[0,0,0]`, `[0,1,0]`) |
| Mount | `gate_mount` — a new socket `gate_channel` on `gate_frame` at offset `[1,0,0]`; the leaf's `support_offsets` are the two jambs beside it, so the only place it fits is a frame's opening |
| Recipe | Workbench, order 219: 6 castle stone + 2 iron ingot → 1 |
| Integrity | 120, repaired with castle stone (+20 a piece), like the rest of the kit |
| Control | **Right-click** the leaf. No lever, no plate (out of scope by the card) |

**Closed is a wall.** `WorkstationService.navigation_cell_data` reports the
gate's cells `solid`, tagged `stone` + `fortification` with the gate's live
integrity — exactly what a player-built castle piece has always reported. So a
raider with another way round takes it, and a raider with none picks the gate
as an `ATTACK_OBSTRUCTION` and chews it at a third of its damage per hit, the
same rule `LocalGridPathfinder._damage_for` already applied to castle stone.
Nothing in the planner or in `BasicRaider` changed.

**Open is a hole.** The same function returns the open gate's cells as
LOADED-and-not-solid air, so `_is_standable` walks straight through them and
the raiders stream in where you decided they should. The toggle emits
`station_changed` carrying `occupied_cells`, which is how a destroyed barricade
already invalidates the navigation snapshot — `notify_placed_entity_cells`
refreshes those cells and re-plans every raider in the same frame.

**The leaf.** `GameSession._build_gate_visual` hangs three stiles, three cross
rails and a row of spiked feet under a `GateLeaf` pivot; opening tweens that
pivot one cell sideways into the jamb over 0.55 s, and drops it back on close.
The two blocking `CollisionShape3D`s stay direct children of the `StaticBody3D`
(Godot reads them nowhere else) and are disabled while the gate is open. This
is the station-visual idiom `_wrap_siege_turret` and the kettle's `KettlePot`
already use.

**Persistence.** `gate_open` is an ordinary bool on the station record, so the
existing checkpoint carries it; `_restored_station` normalises a record from
before the field existed to shut, and `_spawn_station_visual` puts a restored
leaf where it was left without replaying the slide.

**Destroying a gate leaves the frame.** They are separate entities: the leaf is
released, the frame stands, and the gateway is open.

### Calls made

- **The frame is now damageable.** `gate_frame` had `navigation` but no
  `defense`, so a raider that picked one of its cells as a breach target hit
  `NO_PERMITTED_BREACH` and stalled forever. It now carries
  `defense: {180, castle_stone, 20}`, matching its navigation integrity. That
  is a bug fix the gate made unavoidable, not new scope.
- **The leaf turns itself to the frame.** A gate's `rotation_from_mount` flag
  makes `WorkstationService` try each quarter turn from the one the player
  holds and take the first whose supports reach the jambs, rather than making
  them hunt for it with W / R. A gate that fits nowhere keeps the player's own
  rotation, so the refusal they see is the real one.
- **It slides, it does not swing.** A swinging leaf would put its collision a
  cell outside the frame, through whatever stands there. Sliding into the jamb
  is honest and stays inside the frame's own footprint.

## 2. The wall kit

`wall_kit_8` is a new blueprint in the existing catalogue
(`tools/generate_blueprints.py` → `contracts/blueprints.json`), stamped through
the P3K machinery with no new building system:

| | |
|---|---|
| Base course | 16 `castle_stone`, two courses, eight cells long |
| Walkway | 8 `wall_walk_slab` on top |
| Crenellations | 4 `parapet_merlon`, every other cell |
| Stairs | 4 `stone_stair`, a stacked pair at each end, one cell in front and facing the approach — ground → 0.5 → 1.0 → the walk at 1.5 |

The slab, merlon and stair are **entities**, not voxels, and the blueprint
engine was block-only. A blueprint may now carry an `entities` list
(`{offset, entity, rotation}`) beside its `blocks`:

- `InteractionService.blueprint_cells` resolves those rows alongside the block
  rows, carrying the entity id and its rotation (the piece's own quarter turn
  plus the stamp's).
- `_replan_blueprint` plans them through the **same** per-cell rules and the
  same per-item budget, so an entity cell blocks, defers for support or goes
  unaffordable exactly as a block cell does, and `drag_state().costs` already
  totals the real items.
- The commit writes the voxels, then places the entity pieces bottom-up with
  `{"_free": true}`, then runs **one** `inventory.try_transaction` that pays for
  blocks and pieces together. Anything that refuses takes the whole stamp back
  out (`_revert_stamped_pieces` plus the existing voxel rollback). `_free` here
  is not a free build: the single transaction is the price.
- Undo needed nothing new — `_undo_record` already diffs created stations,
  changed voxels and the pack's net change, so one U / Ctrl+Z removes the whole
  section and hands every item back. It now also forgets the stamp
  (`stamps_before`), which it previously left behind for the socket snapper.

Ghosting: entity cells are previewed as castle stone, since that is what the
castle kit is cut from. The preview path is otherwise untouched.

## 3. The turret on rails

`rail_turret` is one new entity and **no new weapon class**. It is the turret
catapult's `siege` block with `rail_speed`, mounted on `rail_mount`:

| | |
|---|---|
| Fire mode | `ballistic` (the existing class), 8 damage, 4–26 cells, 3.0 s, arc 6 |
| Munitions | stone shot or flame shot, capacity 4 (and `starting_ammo` 4 — see below) |
| Rail speed | 1.6 cells/s |
| Recipe | Workbench, order 220: 3 planks + 3 iron ingot + 2 stone → 1 |
| Integrity | 40, repaired with planks |

Everything else is already built: `SiegeDefenseService.advance` rides the rails
of any weapon with `rail_speed > 0` before it turns and fires, so the carriage
throws **while it moves**; `_rail_chain` / `_rail_step` follow corners and keep
straight at a junction; the `patrol` stance (P4C) rides to each end of the
chain and back; `hold` parks it on its home rail; and the weapon panel already
shows Patrol for any rail weapon. The visual reuses `CatapultArm` /
`CatapultBucket` / `CatapultStone` / `SiegeMuzzle`, so the wind-back, throw and
muzzle lookup work unchanged.

### Supply while it moves

`_poll_storage_reload` asked `StorageNetwork.network_of(instance_id)` — the
containers touching the weapon's **anchor**. A carriage eight cells down the
line was still shopping at home. `_supply_network` now adds the containers
touching the rail cell it is riding right now, so a magazine anywhere along the
line feeds it. Ground weapons are unaffected: they have no rider entry.

### Two persistence bugs this exposed

- `_restored_station` accepted only `fire_at_will` and `hold`, so a weapon saved
  while **patrolling** was silently dropped on load. `patrol` is now accepted.
  This was a live kettle bug, not only a new-entity one.
- The same branch validates saved ammunition against `starting_ammo` rather
  than `capacity`, so a weapon loaded above its opening clip is dropped. The
  rail turret dodges it by opening at capacity; the underlying check is left
  alone as out of scope, and is recorded here.

## Expo

| District | Exhibit | Shows |
|---|---|---|
| Construction Yard | `cy_gate` | A gate hung in a frame, with the sign that tells you to right-click it |
| Construction Yard | `cy_wall_kit` | What one stamp leaves behind: course, walk, merlons, stairs |
| Defense Range | `dr_rail_turret` | The carriage on its rail with a stone-shot chest beside it |
| Battlefield | `battlefield_fortification` | The curtain wall's gateway now carries a real gate, hung **shut** |

`ExpoResetService._restore_standing` hangs every gate inside the reset group
shut again, so **RESET BATTLEFIELD** restores the fortification's gate closed
along with its integrity and its magazines. `ExpoBuilder.stamp_blueprint` also
queues a kit blueprint's entity pieces after its blocks, which is how the Wall
Kit exhibit is built.

The Defense Range grew one booth wider (48 → 55 cells) into the corridor it had
reserved for exactly this; its expansion corridor moved to the range's south
side, where nothing else stands.

## Acceptance

- `--p4-siege-units-automation=gate`: **T226_GATE**, **T228_RAIL_TURRET**
- `--p3k-blueprint-automation=gate`: **T227_WALL_KIT**
- `python -m unittest discover -s tests` guards the kit blueprint's entity rows
  and the finished section's contents; `python tools/validate_foundation.py`
  covers the content, icons and the Expo manifest.

## Boundary and next

No lever, plate or drawbridge; no gate wider than one cell; no portcullis that
drops on a timer. The wall kit is a single eight-cell length — no dragged run
of kits, and no player-authored kits. The rail turret does not route through
loop or slope joints any better than the kettle does, and its rail position is
still not saved (it re-homes to its anchor on load, as the kettle always has).
Raiders still do not seek out a gate they cannot see a route through; they
breach it only when it is the cheapest obstruction in their way.
