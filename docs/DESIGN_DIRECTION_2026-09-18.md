# Design direction — 2026-09-18 (owner vision, proposals attached)

**Authority:** the *Owner direction* paragraphs are Tony's stated intent from the 2026-09-18 playtest and are the product target. The *Proposal* paragraphs are Claude's suggested shapes for implementing that intent and are **not commissioned** until Tony accepts them and a backlog card names them. Existing accepted contracts (`ARCHITECTURE.md`, `DEFENSE_TARGETING_CONTRACT.md`, `CONTENT_AND_CRAFTING.md`, `BALANCE_ECOLOGY_AND_SIEGE_SYSTEMS.md`) remain law until a card amends them.

## 1. The game in one paragraph (owner direction)

The player is dropped into the world and must build a castle to fend off ever-increasing, evolving hordes. Survival should feel hard: a wave every day starting small, occasional zombie and animal attacks, roaming patrols and stray NPCs between waves. The player mines resources to build, refines gold to buy from a market, or manufactures at a Foundry. Food is a struggle, not just defence. It borrows from RTS: resources are always needed to build and survive. Minecraft is the reference for feel but is "too easy".

## 2. Held-tool strike (owner direction — implemented as P3H.4 round 3)

The game logs a hit where the crosshair is; the animation is relative to the facing direction. A real strike goes outward toward the opponent, then down and away to the lower-left, disappearing behind the hotbar left of centre, fast enough that detail is not readable. It approaches the crosshair but never covers it, so the player can still see.

*Implemented:* `HeldItemView.TOOL_SWING_KEYS` is a three-key path (toward crosshair, whip down-left out of sight, rise back) in fractions of the visible half-extents, so it scales with aspect ratio. Tunable without code changes elsewhere.

## 3. Tower caps (owner direction)

The current 2×2 Tower Platform is too small now that siege footprints are known. Caps should come in sizes; some accommodate a catapult, others cannot. Catapult needs 6 long × 2 wide, so a cap must be **8×8** to hold a catapult and a ballista; offer **4×4** and **8×8**. Caps are helper blocks — players can always build their own.

*Proposal:* keep Tower Platform's entity model (data-owned occupied/support offsets, mount sockets) and add `tower_cap_4` and `tower_cap_8` definitions with masonry parts and typed mount sockets sized for the P4 siege footprints (6 cells + 2-cell trough). Cost scales with area. This is a P4 dependency, so it belongs in the P4 card.

## 4. Construction menu (owner direction)

Building should not block the view with a menu. Rust-style FPS games use an overlay/dial: open, quickly pick a piece, place it. The hotbar already is this, always present; construction could be split into its own quick menu. Walls are built by click-and-drag while block inventory lasts (P3J). Castle Stone is required for castle walls but not for stone, dirt or wood walls; castle blocks are decorative or carry a purpose such as higher HP.

*Proposal:* a held-key radial ("build wheel") over the viewport with eight slots populated from **placeable entities currently in inventory** (stations, castle kit, siege), leaving the hotbar for blocks, tools and weapons. Selecting a wedge equips that entity into a transient "construction hand" slot; placement then uses the existing preview/rotate/commit contract. No new inventory model. Dirt/stone/planks/castle walls all use the P3J drag-build; castle stone gets a higher `navigation.integrity` so it costs attackers more.

## 5. Economy: ingredients vs valuables (owner direction)

Siege weapons and similar assets are not crafted from ordinary recipes; they are **bought with gold**, giving gold a real purpose. Some things need ingredients, some need valuables. A **Foundry** may be where siege weapons are made, requiring ingredients *and* gold: iron, wood planks, rope, stone, gold. A **market** sells certain assets for gold.

*Proposal — two cost classes in `content.json`:*

| Class | Where | Consumes | Examples |
|---|---|---|---|
| `recipe` (existing) | hand / Workbench / Furnace | ingredients only | tools, blocks, castle kit, ammunition |
| `commission` (new) | Foundry (placed station) | ingredients **+ gold ingots**, timed like a Furnace job | Ballista, Catapult, later machines |
| `purchase` (new) | Market (a placed stall now; a travelling trader later) | gold only, limited stock per day | rope, seeds, livestock, rare parts, repairs |

Gold chain: gold ore (new voxel, deeper/rarer than iron) → Furnace → gold ingot (valuable, also the currency unit). Rope becomes an ingredient (from sticks/plant fibre) so the Foundry recipe has a non-mineral input. Keeps the "resources always needed" RTS pressure: iron for tools, gold for weapons, food for time.

## 6. Threat model (owner direction)

Near-constant pressure: a wave every day starting small and evolving; occasional zombie and animal attacks; roaming patrols; stray NPCs. Attackers do not need a special wall type. Any block wall at least **2 high** stops small/non-climbing monsters. With no path, units **destroy blocks**; how well depends on the monster, its weapon and the block material. They must clear a path that fits their size. Most creatures step over 1 block, some 2. Spiders climb walls and reach the core easily.

*Existing fit (verified in code):* `LocalGridPathfinder` already routes one agent with a capability dictionary — `max_step_up`, `max_drop_down` and `damage_per_hit` keyed by **material tag** — and returns `ATTACK_OBSTRUCTION` with the cell to breach when no route exists. Blocks and entities already carry `navigation.material_tags` and `integrity`. Tony's monster matrix maps onto this directly:

| Creature (proposal) | step-up | size (w×h cells) | can climb | damage per hit by tag |
|---|---|---|---|---|
| Raider | 1 | 1×2 | no | wood 6, dirt 4, stone 2, castle 1 |
| Brute | 2 | 2×3 | no | wood 12, dirt 8, stone 5, castle 3 |
| Zombie | 1 | 1×2 | no | wood 2, dirt 2, stone 0 |
| Wolf/boar | 1 | 1×1 | no | none (targets player/livestock) |
| Spider | 1 | 1×1 | **yes** | none (ignores walls, threatens core/player) |

Missing pieces, in order: (a) breaking voxel blocks, not only placed entities (the pathfinder emits the intent; `CoreDefenseService` only damages entities today); (b) agent footprint > 1×2; (c) climbing as a traversal capability; (d) a **wave director** that owns the daily clock, composition and escalation, spawning through one consolidated encounter service (audit debt 2). MinionClash's "plain state is authority, scenes project it" pattern is the model for the director.

## 7. Food and survival (owner direction)

Eating is a struggle. *Proposal:* hunger meter that drains with time and sprinting; sources in escalating effort — foraged berries, hunted animals (cooked at the Furnace), then farmed crops behind the walls, so defending food becomes part of defending the castle. Starvation slows and then damages the player; it never blocks building, to keep the loop fair.

## 9. Owner follow-up (2026-09-18, accepted)

**One game, three tiers.** The survival-castle loop is the game; the empire (outposts, biomes with indigenous species, supply wagons between townships, a distant growing evil whose bastion must be destroyed, co-op) is what the same systems become at scale. Each tier reuses the same army director, blueprints, economy and threat model with more entities and a bigger map. Co-op is a Tier 3 horizon: not built now, not foreclosed — every action is already a command against plain state.

**Loss is a pillar.** The Market can fall and the game continues: the player keeps their pack, the ruins remain to reclaim. Difficulty scales wave size and night lethality, which sets how often the player hides instead of fights.

**Decisions locked.**
1. *Blueprints stamp ordinary blocks.* Castle pieces (foundation, tower segment, cap, wall, stairs, gatehouse) are lists of blocks relative to an anchor; once stamped they are just blocks — removable, replaceable, understood by pathfinding and breaching. **Player templates** are the same list captured from a world selection and saved with the player's block choices and adornments. The Tower Platform entity retires. **Exception:** machines and mechanics such as Ballista and Catapult remain entities — they are visual upgrades that do not fit the voxel style, with their own footprints, troughs and animations.
2. *Market as core.* The player starts with a Market charter; nothing else works until it is placed. Market HP is the objective; Market levels gate stock, hires (archers on wall posts, swordsmen escorting siege) and Foundry commissions. Valuables tier: gold (currency), gems (unlocks/upgrades), biome trade goods.
   **Superseded (owner decision 2026-09-19):** the objective is the **Core of Power** — a rune monolith glowing blue (red for the enemy) placed in the open on a stone slab and protected by building around it; see [P4G](P4G_CORE_AND_LIGHTS.md). The Market remains a later economy building (stock, hires, commissions), not the thing that falls.
3. *Vast, growing province with a neglect leash.* Finite but large, sector-generated, multiple biomes; enemy camps spawn at increasing distance and clearing them pushes the frontier out. Leaving the province warns, never blocks. Distance is not the leash — **neglect** is: waves keep striking the Market while the player is away (resolved abstractly out of range, physically when near); a weak home pulls the player back. Disrepair over time is a later horizon. Mini-map and compass (pointing home) are required HUD.

**Building up (Rust-style).** Blueprints expose typed sockets (`top`, `side`). Looking at a socket with the materials for a compatible piece shows its ghost; click stamps it. Foundation → segment → stand inside and build up until the spiral stair must be climbed → cap from inside → walk down. Wall-walks attach to `side` sockets; **parapets auto-connect** like fences, opening the merlons where a walkway meets them. Caps offer 4×4, 6×6 and 8×8 floors plus the parapet ring; 8×8 mounts a catapult and a ballista.

## 10. Held items should be 3D (proposal, 2026-09-18 round 5)

*Fact:* placed machines and stations (catapult, ballista, furnace, workbench, castle kit) are true 3D box-mesh assemblies driven by data-owned part lists. Held items are flat camera-facing billboards cut from the 2D icon atlas. Every held-item orientation/position defect this day came from that mismatch: a 2D icon has no pivot, no facing and one fixed silhouette.

*Proposal:* give held items their own 3D presentation built from the same box-part system the catapult uses: tools and weapons as small part assemblies (handle, head, edge) with a real pivot at the grip and a facing that can be rotated toward the crosshair; held blocks as a textured cube; ammunition and stations as scaled copies of their placed models. Icons stay 2D atlas art for the UI. Owner-authored art then targets one thing each: icons for menus, part lists (or later meshes) for the hand. The hinge/strike path already exists in 3D space, so only the sprite is replaced.

## 11. Siege weapons that act (owner direction 2026-09-19)

*Owner direction.* A placed weapon must **turn to face the enemy it targets** and **swing its armature to throw**. Weapons need an **ammunition supply**: either a radius rule (shot lying on the ground or in a nearby chest/bin) and/or — preferred — the weapon is **interactable**: right-click opens its own inventory with action controls (hold, fire at will, target unit type "x"); the player loads it to its limit and keeps chests nearby for reload; an **auto-reload** feature may pull from chests within "x" blocks. Larger idea: the player dumps resources into chests and the system **auto-distributes** to places that need them (weapons, foundries with a build queue) so the player does not micro-manage; requiring the chest to be near the consumer keeps it challenging. Because the world is 3D, actions need **motion**: shooting, reloading. Shot types differ: **stone** vs **flame** — a flame shot lights the night, explodes into fire on impact; fire burns "x" seconds on non-flammable ground but on wood it has fuel and keeps burning until the fuel is gone (fence, door, wooden wall) and **spreads to nearby structures** — a wooden town can be razed.

*Implemented now (P4a-1):* turntable facing at a turn rate, throw animation on fire, wind-back over the reload, bucket stone shown only when loaded, shot launched from the bucket's real position.

*Proposals for the cards:*
- **P4a-2 weapon panel**: right-click a siege weapon → panel with an ammunition slot (its trough), stance (Hold / Fire at will), target filter (unit type), and a *supply radius* readout listing chests in range. Data: `siege.stance`, `siege.target_filter`, `siege.supply_radius`.
- **P4a-3 supply**: a **Chest** entity (2×1 like the trough) and an **auto-reload** rule: an empty weapon takes ammunition from the nearest chest within `supply_radius` that holds its `ammo_item`. Same rule later feeds foundry queues — "auto-distribution" is this rule generalised to any consumer with a need list.
- **P4a-4 shot types**: `stone_shot` (impact damage) and `flame_shot` (impact fire). Fire is a world effect: a burning cell lights, damages entities on it, expires after `burn_seconds` on non-flammable material, and on `flammable` material (planks, log, barricade, gate) consumes the block over `fuel_seconds` then spreads to flammable neighbours with probability per tick. Needs the voxel-breaching path (P4c) since fire removes blocks.

## 12. Traps (owner direction 2026-09-24, implemented)

Traps are **undetected**: an attacker with a route never targets one and never
damages one walking over it. They are **persistent, not consumable** — each has
a balanced reset time after it fires, like Orcs Must Die. An attacker a trap
leaves with no route to the core **attacks the weakest obstacle it can reach**,
comparing integrity and not type, and that is the only state in which a trap is
attacked at all.

The wave-1 card built the whole spine — `TrapService`, the Spike Trap, both
raider rules and a Trap Range in the Development Expo — with every trap's
tuning in a `trap` attribute block on its content sheet, so tar, wall blades, a
spring plate and a ceiling dropper are content. See [Traps](TRAPS.md). (The
card named a `DIRECTION_DEFENCE_AND_RTS.md` sections C and F; that document
does not exist in the repository, so this section and TRAPS.md carry the
direction.)

## 8. Suggested sequencing

1. **P3I** Furnace auto-processing (small; also needed so refining gold is hands-off).
2. **P3J** drag building (walls are the primary defence in this vision).
3. **P3K** parapet auto-connect + first blueprints with sockets (foundation, segment, cap, wall, stairs); Tower Platform retires.
4. **P4a** siege rework as entities on stamped caps (footprints, troughs, animations, 3 s reload).
5. **P4b** Market-as-core, gold/gems, Foundry commissions, Market purchases, hires.
6. **P4c** encounter consolidation → army director (waves, neglect resolution, camps, hires, offense) + voxel breaching + creature capability table.
7. **P4d** build wheel and player templates; **P4e** HUD mini-map/compass; **P4f** food; then biomes and the Tier 2/3 horizon.

Each becomes its own backlog card with a design contract, tests and evidence before implementation; this document is the source of intent for those cards.
