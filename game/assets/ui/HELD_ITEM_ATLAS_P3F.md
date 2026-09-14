# P3F held-item atlas provenance

- Committed asset: `held_item_atlas_p3f.png`
- Actual dimensions: 1536×1024 RGBA, 6×4 cells at 256×256
- SHA-256: `7e5269144f0e7bdf3b8b29067472c7aafb0da52fb164068536c71806a6d721bc`
- Tool mode: OpenAI built-in image generation, reference-based background extraction from `item_icon_atlas_p3d.png`
- Preserved original output: `C:\Users\Tony\.codex\generated_images\01a08ad8-79e6-7ba0-b0ab-5e5f561faf52\exec-c5e8d63c-f108-4af0-83f6-82b671dda550.png`

Prompt:

> Extract the twenty-four item objects from this exact 6-column by 4-row game icon atlas into a new PNG sprite sheet with a genuinely transparent alpha background. Preserve the exact object order, 6×4 grid, 1536×1024 dimensions, object silhouettes, colors, lighting, three-quarter perspectives, and generous separation. Remove every part of the brown/green/gray background field and every floor/drop shadow that extends outside each object silhouette. Do not add checkerboard pixels, replacement background, text, labels, borders, UI cards, watermark, or new objects. Keep each isolated object centered inside its original 256×256 cell and do not let any object cross a cell boundary. Output must be RGBA PNG with true alpha transparency outside the object silhouettes.

The generated image was verified as RGBA with transparent corners and 59.96% fully transparent pixels before repository integration. Runtime slices it with the same stable item-to-cell map as the inventory atlas. Ballista Bolt and Stone Shot intentionally continue to share the established Stick and Stone identities until they receive dedicated catalog entries.

This is a prototype first-person identity atlas, not final modeled equipment, rigging, animation or texture art.
