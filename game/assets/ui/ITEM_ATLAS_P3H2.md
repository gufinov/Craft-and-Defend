# P3H.2 unified alpha item atlas provenance

- Active asset: `item_atlas_p3h2.png`
- Dimensions: 1536×1024 RGBA, 6×4 nominal 256×256 cells
- SHA-256: `96e18558628e170a9ee763287c4291e81c417c4b52e86e41dbe37c174bec5f84`
- Accepted construction: non-destructive versioned copy of the machine-verified true-alpha P3H.1 held atlas
- Preserved source: `held_item_atlas_p3h1.png`

The single P3H.2 asset is now the source for inventory, recipe and first-person item cutouts. This removes the earlier split in which most inventory cards used an RGB atlas while held items used its transparent companion. Empty corner pixels were verified as alpha 0 and the PNG IHDR color type is 6 (RGBA).

Two OpenAI built-in image-generation edits were evaluated before the deterministic source copy was selected. They preserved the designs but baked visible checker pixels into RGB PNGs, so neither generated file is committed or used by the game:

- `C:\Users\Tony\.codex\generated_images\01a08ad8-79e6-7ba0-b0ab-5e5f561faf52\exec-8fe2e8d7-1dbf-4f60-83d3-bb1f6bf81890.png`
- `C:\Users\Tony\.codex\generated_images\01a08ad8-79e6-7ba0-b0ab-5e5f561faf52\exec-bdb59c1e-bb06-4f92-8040-528bd466915a.png`

Rejected first prompt:

> Edit this exact 6-column by 4-row voxel-fantasy game item atlas into one clean production-ready transparent PNG sprite atlas. Preserve the existing 24 item designs, their order, color palette, three-quarter viewing angles, and recognizability: dirt, stone, log, planks, castle stone, sticks; coal, iron ore, iron ingot, wooden pick, stone pick, iron pick; workbench, furnace, stone stair, wall-walk slab, parapet merlon, tower platform; gate frame, wood barricade, iron sword, wood axe, ballista, catapult. REMOVE the entire dark gradient/card background, all rectangular card panels, and all external scene shadows. Output true alpha transparency (RGBA; alpha 0 everywhere outside the item silhouettes). Keep subtle shading only on the objects themselves. Center every item completely inside its own exact 256x256 cell on a 1536x1024 canvas with generous transparent padding; no item may cross a cell edge, touch a neighboring cell, be clipped, or include part of another item. Long sword, axe, gate, ballista and catapult must be fully visible within their own cells. Do not add text, labels, borders, glow, ground plane, hands, UI, or new objects. Pixel-art / polished voxel-render style, crisp clean silhouette edges, transparent background.

Rejected transparency-correction prompt:

> Transparency correction only. Preserve the 24 existing item silhouettes exactly in their current 6x4 positions, sizes, designs, colors and angles. Remove every gray-and-white checkerboard pixel and all background pixels completely. The output MUST be a genuine RGBA PNG with alpha channel and alpha=0 everywhere outside the item silhouettes—not a visible checkerboard, not white, not gray, not a card, not a gradient. Keep only the item pixels with clean anti-aliased alpha edges. No background, no ground shadow, no glow, no text, no borders, no additions. Exact canvas 1536x1024.

This remains prototype raster identity art, not a modeled hand/equipment rig or final animation set.
