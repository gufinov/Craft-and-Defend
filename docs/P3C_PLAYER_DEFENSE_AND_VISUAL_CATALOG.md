# P3C — player defense and visual catalog

Status: AUTHORIZED / IMPLEMENTATION ACTIVE

## Outcome

Make the established crafting and defense foundation usable as a game rather than a text-heavy diagnostic. P3C delivers an original icon-first catalogue, one direct player weapon, and two player-built siege devices which obey the already accepted direct-fire and ballistic-fire rules.

## Player-visible contract

- Inventory remains three distinct areas: 18 carried slots, the nine-key held hotbar, and the reserved armor loadout.
- Every implemented item has a stable visual identity. Counts, held state, drag/swap state and filters remain legible without requiring the item name to carry the whole interface.
- Crafting retains inventory, input grid and recipe book as three distinct panels.
- The recipe book is a fixed square-card page, not a vertical scrolling list. Search filters the catalogue; Previous and Next change pages; a page indicator reports position. Selecting a card fills the staged input only when the ingredients exist.
- The workbench exposes the basic recipes plus the new sword, ammunition and siege-device recipes.

## Player combat contract

- `iron_sword` is a single-stack hotbar tool crafted at the workbench.
- Primary use while the sword is held first checks the center-view raider target. A valid hit requires a clear physics ray within 3.25 metres and a 0.55-second cooldown.
- A valid swing deals 7 damage once and does not also mine terrain or dismantle a structure.
- Misses and cooldown rejection do not mutate raider, terrain, structures or inventory.
- Killing the active core raider produces an explicit defense victory and stops its attack.

## Player-built siege contract

- `ballista` and `catapult` are stable placeable entities crafted at a workbench.
- Both occupy a 2 × 2 footprint, carry finite construction-provided ammunition in their persisted instance record and expose their remaining ammunition in the defense HUD.
- Ballista placement accepts fully supported terrain or the existing typed `light_siege` tower-platform mount. It is long-range direct fire. A clear physics ray to the raider is mandatory before ammunition or damage is consumed.
- Catapult placement accepts fully supported terrain. It is indirect fire with a visible sampled arc, a meaningful 8-metre minimum and 34-metre maximum range. Every sampled arc segment must be clear before ammunition or damage is consumed.
- Devices acquire only the active P3B core-defense raider in this slice. They do not invent waves, global army targeting or campaign progression.

## Data and persistence

- New item/entity/recipe IDs are registry-owned and mirrored exactly from `contracts/content.json` to `game/data/content.json`.
- Siege ammunition and cooldown state live inside the existing placed-entity snapshot envelope.
- Existing accepted saves remain readable because absent siege fields receive entity defaults and no accepted IDs are renamed.

## Gates

| Test | Required evidence |
|---|---|
| T72 — visual catalogue | All registered items resolve a real atlas region; inventory and crafting present icon-first square tiles. |
| T73 — paged recipe book | Fixed 12-card maximum, deterministic search, Previous/Next bounds and page indicator; no vertical recipe scroll. |
| T74 — sword combat | Craft/equip; clear in-range hit causes exactly 7 damage; miss/cooldown cause none; lethal hit wins. |
| T75 — ballista | Craft/place; terrain and typed socket accepted; occlusion costs nothing; clear shot visibly travels and damages. |
| T76 — catapult | Craft/place; below-minimum/beyond-maximum/blocked arc costs nothing; valid clear arc visibly travels and damages. |
| T77 — persistence | Inventory plus placed weapon identity, ammunition and cooldown survive atomic save and clean-process Continue. |
| T78 — presentation | Rendered 1280 × 720 and owner ultrawide paths keep catalogue, counts, paging and combat feedback usable. |

## Boundaries

No player health, armor stats, enemy player-aggro, waves, drops, melee animation rig, audio, final balance, castle collapse, magic or campaign systems are claimed here. Armor slots stay explicitly reserved rather than pretending to work.
