# Balance, ecology and siege systems

Status: APPROVED DIRECTION / STAGED IMPLEMENTATION REQUIRED

This records Tony's accepted product direction without claiming that the systems below already exist. Each capability needs its own bounded implementation gate and owner playtest.

## Shared balance authority

Every live adjustable mechanic must have a stable content ID and named, validated tuning values. Code owns behavior; content data owns balance. Save files store durable instance state such as current health, durability, ammunition, fuel work and cooldown progress. They should not copy mutable catalogue tuning unless replay determinism or migration requires a versioned snapshot.

The catalogue expands with the mechanic that consumes it:

- tools and resources: tool tier, strike power, durability cost, repair material/amount, resource hardness, drops and compatible tool tags;
- player and units: health, armor, attack damage, reach, recovery, movement speed, detection/retarget range and resistances;
- structures: maximum integrity, material class, repair rules, breach capability and defensive value;
- ranged and siege: ammunition, damage, reload, traverse arc, minimum/maximum range, projectile speed, accuracy model, area effect and target priorities;
- ecology: species, trunk/leaves relationship, decay schedule and drop tables.

Values remain prototype tuning until play evidence supports them. “Sword recovering” and “sword broken” are separate states: recovery is the short interval between attacks; durability is a later persistent wear/repair system with distinct feedback.

## Next siege-servicing slice

`Left Shift` is the general Interact action. A targeted Catapult or Ballista should open its own station panel through Interact, exposing ammunition storage, compatible ammunition, upgrades, condition and dismantle/move controls. Loading must use the established drag, right-click split/deposit and Shift+Click transfer contracts. Large weapons are moved by a deliberate dismantle/refund and new placement, not by silently teleporting an active instance.

Initial ammunition roles:

- Catapult stone shot: arcing, minimum range, broad anti-group/structure role.
- Catapult fire shot: a crafted tar/fire projectile with emitted light during flight, ignition-capable impact behavior and its own damage-over-time/AoE contract.
- Ballista bolt: direct line of sight, long range and strong single-target role; blocked shots do not consume ammunition.

Friendly-fire and castle-protection rules must be explicit. “Never fire backward” becomes a validated forward traverse arc tied to the weapon base. The mounted weapon rotates toward a legal target only within that arc.

## Catapult articulation and projectile lifecycle

The Catapult model should expose named parts: base/yaw pivot, throwing-arm pivot, basket or sling socket and loaded projectile. Its deterministic state machine is `EMPTY → LOADED → AIMING → RELEASE → RECOVERING`.

On fire, the base first faces a legal direction, the throwing arm accelerates through a visible arc, and the projectile detaches from the moving socket at the release frame. From then on a projectile entity owns the ballistic path, light/VFX and collision. The arm completes its swing and returns during recovery; a projectile must never merely appear downrange.

Impact shape is ammunition behavior, not an animation shortcut. A steep near-vertical explosive impact can be radial. Tony's desired downrange cone is a candidate for rolling debris, flame spread or directional fragmentation and needs a visual/gameplay spike; ordinary kinetic impact should not silently pretend to have a cone without that mechanism.

Accuracy uses deterministic, seeded variation around a predicted intercept. Prediction considers target position, velocity, projectile flight time and weapon traverse/reload state. Catapults normally prioritize large, slow groups and structures; Ballistas and archers are better against faster or narrower targets. Pure random hit percentages should not replace visible projectile physics.

## Ecology slice

Trees need a stable root/species identity. When no connected trunk remains, leaves enter a bounded decay queue and disappear over time rather than all at once. Drops come from species data: sticks for ordinary foliage, apples for apple trees, and optional petals/blossoms for cherry trees. The implementation should batch decay work and avoid one expensive process node per leaf.

## Wave and army direction

Campaign combat starts attackers at verified far-field entries opposite the defended home/core, giving defenses useful engagement distance. A later wave director owns compositions and pacing across melee, ranged, cavalry, siege and eventually magic. Units seek open paths toward the strategic core, may retarget a nearby visible player, bypass defenses when a route is open, and fight/breach only when necessary or cornered according to capability.

Archers placed along walls, multiple allied defenders and army management are P4-scale systems. They require group pathing/performance budgets, target ownership and save contracts before implementation. This document does not authorize an unbounded jump from the current single-raider prototype to production army simulation.

## Ordered gates

1. P3I — storage containers: small and large placeable chests, persistent contents, lossless transfers and safe dismantle.
2. P3J — siege servicing: Shift interaction, persistent ammo slots, legal loading, upgrades scaffold and safe dismantle/move.
3. P3K — articulated Catapult shot: facing/traverse limit, arm release, visible ballistic projectile, minimum range and deterministic impact.
4. P3L — durability and harvest balance: tool condition/repair plus data-owned resource strike requirements.
5. P3M — tree ecology: root loss, gradual leaf decay and species drops.
6. P4 — wave/army systems: far-field entries, multiple roles, player/core aggro, predictive targeting and performance evidence.
