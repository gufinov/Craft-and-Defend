# Defense, targeting and castle-obstacle contract

Status: accepted product direction; P3 is accepted and the bounded P3B core/breach candidate passes automated/export gates with owner playtest pending.

This contract separates what the current practice drill proves from the castle-defense behavior that still needs implementation. It does not convert a temporary fixture into a production wall, weapon, wave or core.

## Player-facing objective

The player is the king. Attackers ultimately threaten the king or the castle's protected core. The exact core fiction—throne, power source or another original object—remains a product decision, but it must become one stable placed entity with an explicit footprint, health/state, save identity and clear presentation before campaign waves depend on it.

## Attacker target priority

1. An attacker begins with the castle core as its strategic destination.
2. If the king enters that unit's bounded detection area and the unit has legitimate perception and a reachable combat path, the unit may aggro to the king.
3. Navigation prefers an open entrance, gate, breach or route around a structure. A unit must not attack a wall merely because a wall is nearby when an open route reaches the strategic target.
4. When no permitted route exists, the planner may return a specific blocking cell/entity. The unit attacks it only when its capability can damage that material. Current basic raiders can damage earth and wood but not castle stone; a later siege-capable unit may damage fortifications.
5. Ranged attackers may engage an active defense when their role and perception permit it, but should continue toward the core when a usable entrance makes that defense irrelevant. A nearby king or attacker that corners the unit can become the immediate combat target.
6. Losing perception, route validity, the target, or an opening forces a bounded re-evaluation. Target changes must not duplicate units, damage or rewards.

Line of sight is not omniscience. Perception and weapon targeting use physics/world obstruction checks. Detection radii, memory duration and aggro-return rules require a later balance pass.

## Player-built castle structures

Castle-stone voxels and placed castle-kit entities already occupy navigation space. In the current P3 drill they can block or alter the bounded route, but they do **not** yet share one production damage/repair system. The brown/red object is a labelled `training_wall` fixture made from ten temporary physical cells.

Before a real wave can attack a player-built castle, implementation must add:

- stable defensive-structure identity for voxel regions and placed entities;
- material capability and durability rules without one scene node per voxel;
- persisted damage/repair state and coherent edit transactions;
- breach creation that updates occupancy and navigation exactly once;
- opening preference and obstruction selection tests using player-built gates, walls and tower pieces;
- dismantle, drop/refund and repair rules that cannot duplicate inventory.

The expected answer to “does my castle-stone wall count?” is therefore staged: it counts as a solid navigation obstacle now; after the production structure-damage slice it will be an attackable fortification only for units whose capability permits it.

## Defensive weapons

### Ballista

- Direct-fire, long-range weapon.
- May be placed on valid ground support or on a compatible typed `light_siege` tower/platform socket.
- Must have a clear physics line from muzzle to the target hit volume before consuming ammunition or applying damage.
- Terrain, walls and placed entities block the shot. No damage or ammunition is committed when occluded.
- A visible aiming/firing action and projectile/impact cue are required.
- Range, traverse, reload, ammunition storage and crew/power requirements remain balance decisions.

### Catapult or trebuchet

- Indirect ballistic weapon that may arc over walls when the sampled trajectory remains clear.
- Has a meaningful minimum range as well as a maximum range, so it cannot solve nearby threats.
- Requires a different targeting and trajectory contract from the ballista; a simple direct ray is insufficient.
- Area damage, friendly damage, ammunition and structure effects require explicit later decisions.

## Waves

The P3 drill deliberately contains one raider. Production defense requires a wave director with warning, spawn boundary/lanes, multiple simultaneous units, composition, pacing, completion/failure, save/resume and deterministic test control. Threats should enter from the field/world side and travel toward the castle—not materialize behind the protected home position.

## Current bounded P3 revision

The immediate owner-feedback revision adds:

- a persistent nine-cell held hotbar at the bottom of live gameplay;
- available original block artwork plus named fallbacks in each held slot;
- a field-side approach across the home clearing;
- an elevated, clearly labelled practice ballista;
- physical line-of-sight rejection with no ammunition or damage on a blocked ray;
- a visible travelling bolt for a successful shot;
- a clearly labelled temporary practice barricade.

This revision does not implement the king/core hierarchy, production castle durability, catapults or multi-unit waves.

## Active P3B boundary

P3B uses a deliberately labelled `strategic_core_prototype` fixture so targeting can be tested without deciding whether the final fiction is a throne, power source or another object. It adds one player-craftable `wood_barricade` entity with stable persisted integrity. The basic raider must prefer any open route to the core approach; only a complete local blockage permits it to attack one exact wooden barricade. Destroying that entity releases its whole two-cell footprint without an inventory refund and triggers one exact navigation update. Castle stone remains immune to the basic raider. Player aggro, waves, voxel-region durability and final core fiction remain later decisions.

The P3B candidate implements and passes this bounded behavior in the pinned runtime and matching editor-closed export. This is implementation evidence for the prototype only; it does not promote the remaining later decisions into active scope.
