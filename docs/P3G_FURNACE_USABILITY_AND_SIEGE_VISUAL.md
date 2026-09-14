# P3G — Furnace usability and placed siege identity

Status: CANDIDATE / OWNER PLAYTEST PENDING

## Outcome

Make the Furnace understandable and usable for repeated production without removing manual inventory learning, and give the placed Catapult a recognizable world form consistent with its catalog identity.

## Furnace interaction contract

- Shift+Click is the quick-transfer gesture in inventory/container surfaces. From player inventory it moves the maximum compatible amount into the Furnace Raw Input or Fuel slot; from a Furnace slot it moves the maximum amount that fits back into player inventory.
- Existing drag/drop, right-click half-stack pickup, single-item right-click deposit and right-drag distribution remain available.
- The 0–64 Auto-load target moves each selected recipe ingredient toward that batch quantity independently. If one ingredient is scarce, that ingredient stops at its available amount while the other may reach the requested target.
- Lowering the target returns excess staged input/fuel to player inventory transactionally. If inventory cannot accept the return, the station and inventory remain unchanged.
- Auto-load changes only the Furnace's persistent input/fuel stacks. It never creates ingredients, collects Output or changes an active item's already-consumed ingredients.

## Processing contract

- Start Processing consumes one recipe batch and creates one persisted timed job.
- While the Furnace modal is open, only its appliance clock advances. World time, enemies and player simulation remain paused.
- The modal shows one per-item progress bar with percentage and remaining time. Completion adds exactly one recipe output batch to the retained Output slot.
- If another complete batch is already loaded and Output has capacity, the Furnace immediately starts the next item and resets the progress bar. It stops on missing input, missing fuel or blocked Output.
- Output remains in the placed Furnace until the player manually transfers it. Save compatibility remains within the existing station slots/jobs schema.

## Placed siege identity

- The Catapult keeps its stable item/entity ID, 2×2 footprint, support, placement, save and ballistic combat rules.
- Its world model now has a wheeled chassis, axle, braced frame, throwing arm, basket and stone projectile rather than the former generic box assembly.
- This is an original low-poly prototype model, not final production art or animation.

## Gates

| Test | Required evidence |
|---|---|
| T93 — Shift quick transfer | Maximum legal amount moves both directions without loss or duplication. |
| T94 — transactional auto-load | A 15 target with 15 Ore/10 Coal loads 15/10; lowering returns excess and conserves totals. |
| T95 — per-item sequence | Progress reaches 50%, one Output is deposited, and the next loaded item starts at 0%. |
| T96 — live modal | Progress advances while the Furnace panel is open and the rest of the scene tree remains paused. |
| T97 — Catapult identity | Placed Catapult has four wheels and the complete recognizable prototype assembly. |
| T98 — presentation | Rendered evidence shows the Furnace controls/progress and revised placed Catapult. |

## Boundaries

No transport automation, hopper/chest network, recipe unlock behavior, parallel jobs, offline catch-up, final furnace VFX/audio, final 3D art, siege animation or campaign expansion is claimed here.
