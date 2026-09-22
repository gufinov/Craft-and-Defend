# P4b-1 — resource distribution and the gold chain

**Status: candidate (2026-09-19).** Answers "how are mineable resources distributed in the world" with one data table and adds the gold chain the [design direction §5](DESIGN_DIRECTION_2026-09-18.md) needs (gold ore → Furnace → gold ingot). No Foundry, market, commission or purchase class yet.

## Ore distribution table

`world.json → terrain.ores` (canonical [contracts/world.json](../contracts/world.json), mirrored at `game/data/world.json`; `tools/validate_foundation.py` enforces identity) replaces the two P1 magic numbers `coal_cluster_per_thousand` / `iron_cluster_per_thousand`:

| block | min_depth | max_depth | cluster_per_thousand | cluster_size | resulting roll band |
|---|---|---|---|---|---|
| iron_ore | 6 | 32 | 18 | 2 | [0, 18) |
| coal_ore | 3 | 32 | 37 | 2 | [18, 55) |
| gold_ore | 12 | 32 | 5 | 2 | [55, 60) |

Semantics, as implemented in `P1TerrainGenerator._ore_at`:

- **depth = surface − y**, where `surface` is the grass cell of that column (`surface_height`). Depth 1–2 is always dirt, so no ore row may start above depth 3 (validator rule). Bedrock (y = −16) never carries ore, and the world is 32 cells tall, so `max_depth ≤ 32`.
- **cluster_size** groups cells into `size³` clusters (`floor(cell / size)` per axis). One roll in [0, 1000) is hashed per cluster from the world seed (`_roll_3d`, unchanged from P1), so whole clusters become one ore.
- **cluster_per_thousand** is the row's true frequency: the share of clusters that become that ore where its depth band applies. Rows own **cumulative bands** in table order (`band_start`/`band_end` in the compiled table): row *n* matches when `band_start ≤ roll < band_end`. Rows that share a `cluster_size` share the same roll, so their bands are mutually exclusive and the frequencies simply add. The validator requires the widths to sum below 1000 so stone remains.
- Outside a row's depth band its band is skipped and the cell falls through to later rows, then to stone. That is why a roll in [0, 18) at depth 3–5 is stone, not coal: the P1 layout behaved the same way.
- Fixed starter veins (`_starter_resource_at`, the coal and iron patches beside the clearing) and the flat safe clearing keep priority over the table, exactly as before.

Block ids are stable strings; the generator resolves them through `WorldAdapter.BLOCK_NAMES` once in `_init` (`compile_ores`) into an immutable `Array[Dictionary]` that worker threads only read. There is no shared mutable state and no global random stream. Two generators with the same seed and table are cell-for-cell identical (T137); a different seed differs.

### Why `terrain_p1_1` is kept

The table above reproduces the shipped P1 coal/iron layout **cell for cell**: iron was `roll < 18` from depth 6, coal was `18 ≤ roll < 55` from depth 3, cluster size 2, same hash. T138 compares the new generator against a re-implementation of the old formula over 24,439 sampled stone-band cells and finds zero mismatches; gold only appears where P1 produced stone at depth ≥ 12. Existing `terrain_p1_1` saves therefore keep their coal, iron, trees and heights. The only visible change in an existing save is **additive**: untouched chunks (VoxelStreamSQLite stores only edited blocks) now show gold ore deep down where there was stone. Decision: no `generator_version` bump; `WorldAdapter.resolve_generation` and `docs/PERSISTENCE.md` are unchanged. Any future row that changes coal or iron bands, cluster sizes or the hash **must** bump the version and be routed in `resolve_generation`.

## Gold chain

| Piece | Definition |
|---|---|
| Block `gold_ore` | voxel_id **11** (additive, after leaves 10), drops item `gold_ore`, `min_pick_tier` **3** (Iron Pick). Iron ore stays tier 2 (Stone Pick); gold deliberately sits one tier higher so the Iron Pick has a purpose and gold cannot be reached before iron. Texture `assets/blocks/gold_ore.svg` (original placeholder: stone with gold flecks, same construction as `iron_ore.svg`). `WorldAdapter.BLOCK_NAMES[11] = "gold_ore"`, colour `c9a640`. |
| Item `gold_ore` | category resource, max stack 64. |
| Item `gold_ingot` | category resource, max stack 64. The valuable / currency unit of §5; nothing consumes it yet. |
| Recipe `gold_ingot` | station furnace, inputs `gold_ore` 1 + `coal` 1, output `gold_ingot` 1, **8 s** (iron is 5 s), `recipe_book_order` 10 (after iron ingot at 0). Auto-processing infers it from staged Gold Ore like any furnace recipe. |
| Progression goal | `gold_ingot` is added after `iron_pick`; `reachable_items` now counts ore-table blocks as present so the static proof covers gold: Iron Pick → gold ore → Furnace → gold ingot. |
| Icons | `assets/ui/gold_atlas_p4.png` (atlas key `gold`), measured regions in `data/item_atlas_regions.json`; provenance in [`GOLD_ATLAS_P4.md`](../game/assets/ui/GOLD_ATLAS_P4.md). |

Display names come from `ContentRegistry.display_name` ("Gold Ore", "Gold Ingot"); no name table needed.

## Validation

- `tools/validate_foundation.py → validate_ores`: nonempty table; every block exists, is solid, unprotected and droppable; no duplicate block; `3 ≤ min_depth ≤ max_depth ≤ world height`; `1 ≤ cluster_per_thousand < 1000`, sum < 1000; `1 ≤ cluster_size ≤ 8`. Unit tests in `tests/test_foundation.py` (`test_ore_*`, band preservation, gold reachability).
- Runtime gate `--p4-resources-automation=gate` (`P4ResourcesAutomation`, `tools\runners\TEST_P4_RESOURCES.cmd`): T137 depth bands and rarity order, T138 P1 layout preservation, T139 gold mining (Stone Pick refused, Iron Pick drops one Gold Ore from a *generated* gold cell near the clearing), T140 gold smelting. See [evidence](evidence/P4B_RESOURCE_DISTRIBUTION.md).

## Boundaries

No Foundry, market, commission or purchase cost class; no gold consumer; no ore veins/noise shapes beyond hashed cubic clusters; no per-biome tables; gold art is a re-hued iron placeholder.
