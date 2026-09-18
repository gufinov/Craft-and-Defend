# P3H.3 ammunition atlas provenance

- Active asset: `ammunition_atlas_p3h3.png`
- Dimensions: 1774×887 RGBA; two exact 887×887 regions
- SHA-256: `d34394a5b0a6b10d55996e2d1fffEEb83dc1bee245ef74f571575c5ee2e15db6` (case-insensitive)
- Method: OpenAI built-in image generation using `item_atlas_p3h2.png` as the visual reference
- Preserved generated output: `C:\Users\Tony\.codex\generated_images\01a08ad8-79e6-7ba0-b0ab-5e5f561faf52\exec-8c015874-7d32-4651-ac30-119e0db025af.png`

Prompt:

> Create a new standalone two-item ammunition atlas matching the exact original warm low-poly voxel-fantasy item icon style, lighting, materials, three-quarter camera, and clean silhouette of the referenced Craft and Defend atlas. The canvas must have a genuinely transparent alpha background everywhere except the objects; no gradient, no checkerboard, no floor, no shadow card, no text, no border, no watermark. Place exactly two complete non-overlapping objects with wide transparent separation: LEFT HALF: one single heavy medieval ballista bolt/quarrel, long straight dark wood shaft, one large faceted iron spearhead, small rear fletching; unmistakably one projectile and absolutely not a bundle of sticks or arrows. RIGHT HALF: one roughly spherical faceted stone shot for a catapult, naturally irregular round gray rock/stone ball; unmistakably round and absolutely not a cube, brick, slab, or pile. Keep both objects fully inside their own half with generous transparent margins and similar apparent scale. Output PNG with real alpha transparency.

The copied project asset preserves the generated original. Machine inspection verified `Format32bppArgb`, alpha-zero pixels at all four canvas corners and exact 1774×887 dimensions. Godot imports it as an RGBA texture. The two objects are extracted with filter clipping; no resampling or destructive edit was applied.
