# P3F — recipe progression order and held visual catalog

Status: OWNER ACCEPTED 2026-09-14

## Outcome

Keep basic and inexpensive recipes at the front of the recipe book, make the ordering stable as the content catalog grows, give every carried item a transparent first-person identity matching its inventory art, and make placed voxel blocks use their complete authored face textures.

## Recipe-book contract

- Every current recipe owns an explicit nonnegative `recipe_book_order` within its station context. Lower values appear first.
- The Workbench still includes hand recipes, so Planks, Sticks and Workbench remain at the beginning before wooden tools, stone/castle construction, iron equipment and siege content.
- Name is only a deterministic tie-breaker. A new recipe should normally receive a later progression order unless its accepted gameplay tier places it among earlier fundamentals.
- Search and paging still expose the complete current catalog. Manual pattern recognition remains independent of recipe selection.
- This ordering prepares for discovery without inventing unlock triggers. All current recipes remain visible until a separate discovery contract defines how recipes are learned, saved and migrated.

## Held and block visual contract

- All 26 registered item identities resolve through one transparent 6×4 held-item atlas that preserves the inventory atlas cell mapping.
- Tools and the sword render raised; blocks, materials, stations and siege pieces render lower for placement/carrying.
- No held item uses an opaque inventory-card background or the old emergency box-built pick, axe, sword or block representation.
- Voxel cube models retain their existing stable block IDs and authored SVG face textures. Each declares its actual 1×1 atlas geometry so Voxel Tools maps the full texture rather than a nearly uniform corner.
- Nearest mipmapped filtering keeps masonry, ore, wood and dirt patterns legible without changing the accepted Compatibility renderer or saved world data.

## Gates

| Test | Required evidence |
|---|---|
| T90 — recipe progression order | Exact Workbench order begins with basic hand recipes and ends with siege recipes; order values are strictly increasing. |
| T91 — held and block identity | All 26 items resolve one transparent held sprite; all registered voxel cube models declare 1×1 atlas geometry. |
| T92 — presentation | One rendered contact sheet shows Wood Pick, Sticks, textured placed/held Castle Stone, Dirt, Ballista and Catapult without opaque cards. |

## Boundaries

No recipe unlock/discovery rules, final 3D equipment models, hand/arm rig, attack animation set, dedicated ammunition icons, block normal maps, material PBR overhaul or save schema change is claimed here.
