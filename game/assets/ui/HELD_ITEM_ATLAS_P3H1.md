# P3H.1 held-item alignment atlas provenance

- Committed asset: `held_item_atlas_p3h1.png`
- Actual dimensions: 1536×1024 RGBA, 6×4 cells nominally 256×256
- SHA-256: `96e18558628e170a9ee763287c4291e81c417c4b52e86e41dbe37c174bec5f84`
- Tool mode: OpenAI built-in image generation, reference-based background extraction from the aligned P3H.1 RGB atlas
- Preserved generated output: `C:\Users\Tony\.codex\generated_images\01a08ad8-79e6-7ba0-b0ab-5e5f561faf52\exec-853eb15a-6e2b-4de4-b90a-d5feb9f10091.png`

Prompt:

> Create a transparent-background companion atlas from this exact 1536 x 1024, 6-column by 4-row item atlas. Preserve every one of the 24 item designs, their exact order, scale, position, colors, lighting, and all complete silhouettes. Remove only the dark gradient background and ambient background glow so every pixel not belonging to an item or its natural contact shadow is fully transparent. Keep each item within its same invisible 256 x 256 cell; do not move, resize, redraw, crop, duplicate, omit, or relabel anything. Do not add checkerboard, grid lines, separators, text, borders, card backgrounds, or new objects. Output exactly one RGBA PNG at 1536 x 1024 with genuine alpha transparency.

The original P3F held atlas remains preserved. Runtime filter-clips every region and uses a deliberate 288-pixel-tall recovery window for bottom-row gate, weapon and siege silhouettes. Raised and low-held anchors are independently framed by the first-person presentation code.

This is a prototype first-person identity atlas, not a modeled hand/equipment rig or final animation set.
