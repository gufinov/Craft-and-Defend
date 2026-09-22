# P4G — Core of Power and light sources

## Outcome

Owner direction (2026-09-19, eight reference renders in `docs/reference/owner_art/`): each player has a **Core of Power** — a rune stone/monolith glowing with magic aura and light, blue for the player and red for the enemy, placed in the open on a slab of stone. The goal is to protect the core by building around it. Every new 3D asset gets a value and attributes (effects, defense, offense, lighting, mounting, space, cost). **Light sources never extinguish** (no micromanagement); campfires need no ignition.

This card adds the two cores and six light sources as ordinary placed entities on the existing placement, footprint, defense and visual services, an **asset attribute sheet** in content that the validator enforces, owner-art card icons, models with real `OmniLight3D` lights, a diagnostic and a runner. It replaces the "Market as core" idea of [design direction §9](DESIGN_DIRECTION_2026-09-18.md) (owner decision 2026-09-19).

## Asset attribute sheet (`contracts/content.json → entities[].attributes`)

Each entity below carries `attributes`: `{"value": int, "role": "core|light|decor", "light": {"color", "energy", "range", "flicker"} | null, "mount": "ground|wall|ceiling|any_solid_top|block", "space": [w, h, d], "notes": "…"}`. `tools/validate_foundation.py` requires the block on these eight entities (`ATTRIBUTE_ENTITIES`), checks every field's type and range, that `space` equals the occupied extent, that cores mount on the ground only, that cores and lights carry a light plus `defense` and `navigation` blocks whose integrities agree, and that `defense.repair_item` is an item. `ContentRegistry.entity_attributes(id)` exposes the block at runtime.

| Entity | Value | Role | Footprint / space | Mount | Cost (Workbench recipe, book order) | Integrity / defense | Offense | Light (colour · energy · range · flicker) | Lighting notes | Limitations |
|---|---|---|---|---|---|---|---|---|---|---|
| `core_of_power` | 500 | core | 3×3 base + centre column, 4 tall (`space` 3×4×3, 12 cells) | ground only, 9 supports | 8 castle stone + 2 gold ingot (203) | 240; tags `stone, core, fortification`; repair castle stone +12 | none | `4c9dff` · 2.5 · 12 · steady | blue light inside the shaft (y +1.8); rune lines, gems and corner gems are emissive | crafted (there is no starting grant in the new-game inventory); the wave drill still uses `CoreDefenseService`'s abstract core cell (another card wires the drill to the placed core) |
| `enemy_core` | 0 | core | same as the core (3×4×3) | ground only | none — `hidden` item, no recipe, never in the book; placed by the game through `WorkstationService.try_place` | 400; tags `stone, core, enemy`; repair castle stone +12 | none | `ff3030` · 2.5 · 12 · steady | red light inside the orb (y +2.1); rune ring and orb seams emissive | no enemy camp places it yet (diagnostics only); the item must be granted to place it |
| `torch` | 2 | light | 1×1×1 | any solid top (ground, wall top, block, placed entity) | 1 stick + 1 coal → 2 (197) | 4; tags `wood, breachable_wood`; repair stick +2 | none | `ffa040` · 1.6 · 7 · **flicker** | flames as emissive cones (`TorchFlames`), light at y +0.62 | wall side-face mounting not implemented — stands on a top |
| `wall_lantern` | 12 | light | 1×1×1 | any solid top | 2 iron ingot + 1 coal (198) | 12; tags `iron, breachable_wood`; repair iron ingot +4 | none | `ffb050` · 1.8 · 9 · steady | amber pane emissive; light at the pane | designed as a wall bracket: this slice stands the bracket post on any solid top (set it on a wall top or beside a wall) |
| `post_lantern` | 18 | light | 1×3×1 (three cells tall) | ground / any solid top, 1 support | 3 planks + 2 iron ingot + 1 coal (199) | 20; tags `wood, breachable_wood`; repair planks +6 | none | `ffb050` · 2.2 · 12 · steady | lantern hangs at y +1.5; light there | needs three free cells above the support |
| `campfire` | 10 | light | 3×1×3 (9 cells) | ground only, 9 supports | 4 stone + 2 log + 2 stick (200) | 20; tags `wood, breachable_wood`; repair log +6 | none | `ff8a30` · 2.6 · 11 · **flicker** | flames (`CampfireFlames`) and ember bed emissive; light at y +0.7 | never burns out; no ignition, no fuel, no cooking yet |
| `light_block_blue` | 25 | light | 1×1×1 — block-sized | block: exactly one cell, any solid top | 4 castle stone + 1 gold ingot + 1 coal (201) | 30; tags `stone, fortification`; repair castle stone +6 | none | `4c9dff` · 2.0 · 10 · steady | glowing core cube and face runes emissive; light at the centre | an entity, not a voxel: the pick does not mine it, dismantle returns it |
| `light_block_red` | 25 | light | 1×1×1 — block-sized | block | 4 castle stone + 1 gold ingot + 1 coal (202) | 30; tags `stone, fortification`; repair castle stone +6 | none | `ff3030` · 2.0 · 10 · steady | as the blue block | as the blue block |

Items: `core_of_power` (stack 1), `enemy_core` (stack 1, `"hidden": true`), `torch` (32), `wall_lantern` (16), `post_lantern` (8), `campfire` (4), `light_block_blue` (16), `light_block_red` (16); all `category: "building"` with `places_entity`. Hidden items may not be recipe outputs (validator) and `ContentRegistry.recipes_for` drops any recipe that would output one, so no book can show them. The Workbench book now holds 35 entries on three pages (T73 / T103 expectations unchanged).

## Models (`GameSession._build_*_visual`, one per entity, dispatched in `_spawn_station_visual`)

- **Shared slab** (`_add_core_slab`): two stepped stone tiers with emissive rune strips on every face, four corner posts with a gold cap and a glowing gem cone, gold corner blocks and mid-face wedges.
- **Core of Power**: the slab in castle stone with gold; a plinth, an 0.88-wide shaft, a shoulder and a spire (3.6 tall); two gold bands with corner blocks; a vertical rune line, a crossbar and diamond gems on each face; a gold-framed diamond jewel on the plinth front.
- **Enemy core**: the slab in black stone with bronze; bronze spikes on the rim, a red rune ring and pedestal, six bronze shards leaning in like a crown with red gems, a dark red-emissive orb (`EnemyCoreOrb`) girdled by two rune rings with black stone plates and floating shards, a crown spike above and a drop spike below.
- **Torch**: wrapped oak shaft with leather bands, iron foot cone and ring with gold studs, an iron collar, four studded cage slats around split wood, a top ring and flames.
- **Lantern body** (`_add_lantern_body`, shared): amber emissive pane, four corner rails, crossed iron straps with gold studs on every face, iron roof cone with a neck, bottom plate with a gold drop, gold corner studs.
- **Wall lantern**: an iron-capped oak post with gold studs, an arm with an iron end block, a diagonal brace, two chain links and the lantern body. **Post lantern**: an oak base with four iron wedges and gold studs, a 2.3-tall banded post with a gold finial, an arm, a brace, a chain and the lantern body at y +1.5.
- **Campfire**: twelve ring stones (every third a gold-banded block with a dark stud), an emissive ember disc, seven charred coals, three crossed logs and tall flames.
- **Light block**: a 0.92 emissive core cube, twelve stone edge bars with gold trim, eight studded corner cubes and a rune diamond on each of the six faces.

**Lights.** `_add_entity_light(parent, attributes, offset)` reads `attributes.light` and adds one `OmniLight3D` named `EntityLight` (`omni_attenuation` 1.4, no shadows) — the only light source; it is never removed or dimmed. With `flicker: true` one looping Tween (`_start_light_flicker`) moves the energy ±15 % with a sine ease (0.42 s up, 0.34 s down, 0.25 s back); flames (`_add_flames`) pulse their scale with a second looping Tween. Both Tweens are bound to their node and die with it. `FireService`'s fire visuals are unrelated and unchanged.

## Icons

`tools/generate_derived_icons.py` uses the eight owner renders as the card icons (`OWNER_ICONS`). Six of them were delivered on an opaque black backdrop: `key_black_backdrop` floods the backdrop from the four corners (threshold 34, so dark iron inside the object survives) and feathers pixels darker than 96 so glow halos fade instead of ending in a black fringe. Cells 10–17 of `derived_atlas_p4.png` (three rows now); `tools/measure_item_atlas.py` records the regions.

## Acceptance

- `--p4-assets-automation=gate` (headless): **T148** asset attributes (every new entity has the attribute block with a light, a ghost visual, navigation and defense; the seven craftable recipes are workbench recipes ordered after the chest; the enemy core is hidden and absent from the book; `ItemIconCatalog.missing_item_ids` is empty; the core is role `core`, value 500, ground, 3×4×3, blue, 12 cells; the enemy core is red, value 0, 400; torch and campfire flicker, the lantern does not), **T149** placement and light (all eight place on levelled ground with one `EntityLight` of the attribute colour and range; the core owns its 3×3 base and centre column only; `defense_status` reports 240 / 400 / 4; a torch over air is `UNSUPPORTED`, a torch on a light block places; the torch energy moves within 0.5 s while the lantern's holds).
- `--p4-assets-automation=visual` (windowed): **T150** renders `p4-assets.png` (1280×720) at 20:30 (`apply_world_settings("2030", false)`) with both cores, the campfire, both lanterns, the torch and both light blocks; eight lights, ≥ 300 mesh parts.
- `tools\runners\TEST_P4_ASSETS.cmd` runs gate then visual on the export.
- Regression: P3F gate (`EXPECTED_WORKBENCH_ORDER` extended), P3C phase1, P4 siege units gate, P3G gate, P3E gate stay PASS.

## Boundary and next

Wall/ceiling side-face mounting is not implemented (every entity needs its support cells below it). The placed Core of Power is not yet the wave drill's objective (`CoreDefenseService` keeps its abstract core cell; another engineer is wiring the drill to the placed core). No enemy camp places the enemy core. Lights have no gameplay effect on enemies (no fear, no reveal); the campfire does not cook. Values are gold values for a later market/foundry; nothing spends them yet. Next: drill objective = placed core, enemy camps with a red core, light-driven night behaviour, wall brackets.
