"""Derive the P4b gold placeholder atlas from the iron art in the item atlas.

Copies the measured ``iron_ore`` and ``iron_ingot`` regions out of
``item_atlas_p3h2.png`` (regions from ``game/data/item_atlas_regions.json``),
re-hues them to warm gold and writes two 256x256 cells side by side to
``game/assets/ui/gold_atlas_p4.png``. Alpha is preserved untouched. Re-run
``tools/measure_item_atlas.py`` afterwards. Requires Pillow.

Deterministic: the same inputs always produce byte-identical output.
"""
from __future__ import annotations

import colorsys
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - guidance only
    sys.exit("Pillow is required: python -m pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "game" / "assets" / "ui"
SOURCE = UI / "item_atlas_p3h2.png"
REGIONS = ROOT / "game" / "data" / "item_atlas_regions.json"
OUTPUT = UI / "gold_atlas_p4.png"
CELL = 256
GOLD_HUE = 44.0 / 360.0
# (source item, output cell, tint mode)
CELLS = [("iron_ore", 0, "flecks"), ("iron_ingot", 1, "solid")]


def gold(r: int, g: int, b: int, mode: str) -> tuple[int, int, int]:
    h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    if mode == "flecks" and s < 0.22:
        return r, g, b  # grey stone matrix stays stone; only the ore flecks turn gold
    if mode == "flecks":
        s = min(1.0, s * 1.35 + 0.15)
        v = min(1.0, v * 1.12 + 0.05)
    else:
        s = min(1.0, 0.55 + 0.35 * v)
        v = min(1.0, v * 1.08 + 0.04)
    nr, ng, nb = colorsys.hsv_to_rgb(GOLD_HUE, s, v)
    return round(nr * 255), round(ng * 255), round(nb * 255)


def main() -> int:
    regions = json.loads(REGIONS.read_text(encoding="utf-8"))["regions"]
    source = Image.open(SOURCE).convert("RGBA")
    atlas = Image.new("RGBA", (CELL * len(CELLS), CELL), (0, 0, 0, 0))
    for item_id, cell_index, mode in CELLS:
        x, y, w, h = regions[item_id]["rect"]
        crop = source.crop((x, y, x + w, y + h))
        pixels = crop.load()
        for cy in range(h):
            for cx in range(w):
                r, g, b, a = pixels[cx, cy]
                if a == 0:
                    continue
                pixels[cx, cy] = (*gold(r, g, b, mode), a)
        offset = (cell_index * CELL + (CELL - w) // 2, (CELL - h) // 2)
        atlas.paste(crop, offset)
    atlas.save(OUTPUT, optimize=True)
    print(f"wrote {OUTPUT.relative_to(ROOT)} {atlas.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
