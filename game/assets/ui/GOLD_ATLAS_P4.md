# P4b gold placeholder atlas provenance

- Active asset: `gold_atlas_p4.png`
- Dimensions: 512×256 RGBA; two 256×256 cells (`gold_ore` left, `gold_ingot` right), objects centred
- SHA-256: `653e6c24a695bb55a3cade9b65276cfe3fcb2d7f9821c05379f50ed005f29030`
- Method: derived, not generated. `tools/make_gold_atlas_p4.py` copies the measured `iron_ore` and `iron_ingot` regions out of `item_atlas_p3h2.png` (regions from `data/item_atlas_regions.json`) and re-hues them to warm gold (hue 44°) in HSV. Alpha is untouched. For the ore, only pixels with saturation ≥ 0.22 (the ore flecks) change so the stone matrix stays grey; the ingot is tinted throughout with saturation scaled by value so shading survives.
- Deterministic: re-running the tool reproduces the same bytes from the same inputs. Re-run `tools/measure_item_atlas.py` afterwards; the `gold` atlas key measures the two centred cells.

This is a placeholder so every content item has a measured icon (`tests/test_item_atlas_regions.py`). Replace it with original gold art in the same style as the P3H.2 atlas when art time is available; the icon catalogue only needs the atlas key `gold` and re-measured regions.
