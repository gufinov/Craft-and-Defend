# P3H.1 item-icon alignment atlas provenance

- Committed asset: `item_icon_atlas_p3h1.png`
- Actual dimensions: 1536×1024 RGB, 6×4 cells nominally 256×256
- SHA-256: `8d7ea0f17cf153668338525e0989a0ea3800951c854619b9c7aa4c0e04912611`
- Tool mode: OpenAI built-in image generation, reference-based precision edit of the earlier P3H.1 candidate atlas
- Preserved generated output: `C:\Users\Tony\.codex\generated_images\01a08ad8-79e6-7ba0-b0ab-5e5f561faf52\exec-704c4457-d8d7-4002-80d4-4854ecaab4dd.png`

Prompt:

> Edit this exact 1536 x 1024 inventory icon atlas while preserving the same 6 columns by 4 rows, exact item order, overall voxel-art style, lighting, and continuous dark warm card background. This is a precise alignment correction, not a redesign. Every item must fit completely inside its own invisible 256 x 256 cell with at least 18 pixels of empty background on all four sides; no object, shadow, glow, highlight, or fragment may cross a cell boundary. In particular, move and if needed uniformly shrink all six bottom-row items (gate frame, wood barricade, iron sword, wood axe, ballista, catapult) so their highest visible pixel is below y=786 and their lowest visible pixel is above y=1006. The iron sword blade and gate towers must be fully visible inside the bottom row. Also ensure each third-row item ends above y=750. Keep every object centered in its cell. Do not add grid lines, separators, checkerboard, transparency, text, labels, borders, new objects, or crop marks. Output exactly one flat RGB atlas at 1536 x 1024.

The original P3D atlas remains preserved. Runtime also applies filter-clipped safe regions, because generated silhouettes and their antialiased edge pixels are not treated as trustworthy cell-boundary metadata. The transparent companion supplies the taller recovery window for the six long bottom-row silhouettes without carrying a neighboring card background.

This is game-ready prototype icon art, not final production modeling or final texture art.
