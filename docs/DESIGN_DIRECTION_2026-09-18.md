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

## 8. Suggested sequencing

1. **P3I** Furnace auto-processing (small; also needed so refining gold is hands-off).
2. **P3J** drag building (walls are the primary defence in this vision).
3. **P4a** siege rework + tower caps 4×4/8×8 (footprints, troughs, animations, 3 s reload).
4. **P4b** economy: gold ore/ingot, rope, Foundry commissions, Market purchases.
5. **P4c** encounter consolidation + wave director + voxel breaching + creature capability table.
6. **P4d** build wheel; **P4e** food.

Each becomes its own backlog card with a design contract, tests and evidence before implementation; this document is the source of intent for those cards.
