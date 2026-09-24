"""Measure tight per-item regions in the UI item atlases.

Writes ``game/data/item_atlas_regions.json`` from the alpha channel of the
active atlases so icon centring and held-item hinges follow the art instead
of fixed grid cells. Re-run after replacing any atlas PNG.

Requires Pillow (``pip install pillow``). The repository unit tests validate
the produced JSON without Pillow.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - guidance only
    sys.exit("Pillow is required: python -m pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "game" / "assets" / "ui"
OUTPUT = ROOT / "game" / "data" / "item_atlas_regions.json"

ALPHA_THRESHOLD = 128
CELL = 256
ATLASES = {
    "item": "item_atlas_p3h2.png",
    "ammunition": "ammunition_atlas_p3h3.png",
    "derived": "derived_atlas_p4.png",
    "gold": "gold_atlas_p4.png",
}
# Derived placeholder icons (tools/generate_derived_icons.py): 256 px cells, 6 per row.
DERIVED_ORDER = [
    "flame_shot", "chest", "cannon", "cannonball", "turret_catapult", "hot_oil",
    "kettle", "rail", "turret_catapult_mk2", "wood_axe_flipped",
    "core_of_power", "enemy_core", "torch", "wall_lantern", "post_lantern", "campfire",
    "light_block_blue", "light_block_red",
    "rail_slope", "rail_loop", "mine_cart",
    "coaster_car", "rail_switch",
    "rail_climb",
    "rail_cross",
    "rail_curve",
    "coastercraft_shop",
    "miner", "ore_bin",
    "warehouse", "foundry",
    "sign", "sign_board",
    "gate", "rail_turret",
    "sign_board_large",
]
# Nominal search cells. Row heights for the item atlas follow the shipped
# ItemIconCatalog grid; the ammunition atlas is two square halves.
ITEM_ORDER = [
    "dirt", "stone", "log", "planks", "castle_stone", "stick",
    "coal", "iron_ore", "iron_ingot", "wood_pick", "stone_pick", "iron_pick",
    "workbench", "furnace", "stone_stair", "wall_walk_slab", "parapet_merlon", "tower_platform",
    "gate_frame", "wood_barricade", "iron_sword", "wood_axe", "ballista", "catapult",
]
# The bolt's spearhead crosses the midline, so it is searched across the full
# width; the longest occupied column run still selects the bolt, not the shot.
AMMUNITION_CELLS = {
    "ballista_bolt": (0, 0, 1774, 887),
    "stone_shot": (887, 0, 887, 887),
}
# P4b gold placeholders derived from the iron art (tools/make_gold_atlas_p4.py):
# two centred 256x256 cells.
GOLD_CELLS = {
    "gold_ore": (0, 0, CELL, CELL),
    "gold_ingot": (CELL, 0, CELL, CELL),
}


def item_cell(index: int) -> tuple[int, int, int, int]:
    column, row = index % 6, index // 6
    if row == 2:
        return column * CELL, 512, CELL, 224
    if row == 3:
        return column * CELL, 736, CELL, 288
    return column * CELL, row * CELL, CELL, CELL


def longest_run(flags: list[bool]) -> tuple[int, int]:
    """Return [start, end) of the longest contiguous True run."""
    best = (0, 0)
    start = None
    for index, flag in enumerate(flags + [False]):
        if flag and start is None:
            start = index
        elif not flag and start is not None:
            if index - start > best[1] - best[0]:
                best = (start, index)
            start = None
    return best


def measure(solid: Image.Image, cell: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """Tight bounds of the dominant blob inside ``cell`` (atlas coordinates).

    Neighbouring slivers and drop shadows that cross a cell edge form short
    separate runs; taking the longest run of occupied columns, then rows,
    keeps only the intended object.
    """
    x, y, w, h = cell
    crop = solid.crop((x, y, x + w, y + h))
    pixels = crop.load()
    columns = [any(pixels[cx, cy] for cy in range(h)) for cx in range(w)]
    left, right = longest_run(columns)
    rows = [any(pixels[cx, cy] for cx in range(left, right)) for cy in range(h)]
    top, bottom = longest_run(rows)
    return x + left, y + top, right - left, bottom - top


def main() -> int:
    regions: dict[str, dict] = {}
    sizes: dict[str, list[int]] = {}
    for atlas_key, filename in ATLASES.items():
        image = Image.open(UI / filename).convert("RGBA")
        sizes[atlas_key] = list(image.size)
        solid = image.split()[3].point(lambda v: 255 if v > ALPHA_THRESHOLD else 0)
        if atlas_key == "item":
            cells = {item: item_cell(i) for i, item in enumerate(ITEM_ORDER)}
        elif atlas_key == "derived":
            cells = {item: ((i % 6) * CELL, (i // 6) * CELL, CELL, CELL) for i, item in enumerate(DERIVED_ORDER)}
        elif atlas_key == "gold":
            cells = GOLD_CELLS
        else:
            cells = AMMUNITION_CELLS
        for item_id, cell in cells.items():
            rect = measure(solid, cell)
            regions[item_id] = {"atlas": atlas_key, "rect": list(rect)}
    payload = {
        "schema_version": 1,
        "alpha_threshold": ALPHA_THRESHOLD,
        "atlases": {key: {"file": name, "size": sizes[key]} for key, name in ATLASES.items()},
        "regions": regions,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    for item_id, entry in regions.items():
        print(f"{item_id:15s} {entry['atlas']:11s} {entry['rect']}")
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({len(regions)} regions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
