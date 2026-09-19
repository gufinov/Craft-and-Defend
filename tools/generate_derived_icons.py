"""Derive placeholder icons for items that have no atlas art.

Writes ``game/assets/ui/derived_atlas_p4.png`` (256 px cells, 6 per row) with
icons built from existing atlas art (tinted copies) or simple drawn shapes,
then ``tools/measure_item_atlas.py`` measures them like any other atlas.
Original placeholder art only; replace with commissioned art later.

Requires Pillow.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageEnhance, ImageOps
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python -m pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "game" / "assets" / "ui"
OUTPUT = UI / "derived_atlas_p4.png"
REGIONS = ROOT / "game" / "data" / "item_atlas_regions.json"
CELL = 256
COLUMNS = 6

# Order defines cell index. Keep appending; never reorder existing entries.
DERIVED = [
    "flame_shot", "chest", "cannon", "cannonball", "turret_catapult", "hot_oil",
    "kettle", "rail", "turret_catapult_mk2", "wood_axe_flipped",
    # P4G core and light sources (owner art, 2026-09-19).
    "core_of_power", "enemy_core", "torch", "wall_lantern", "post_lantern", "campfire",
    "light_block_blue", "light_block_red",
]

# Owner-drawn reference art (docs/reference/owner_art, transparent WebP). When
# present it IS the icon: trimmed to its alpha bounds and fitted into the cell.
OWNER_ART = ROOT / "docs" / "reference" / "owner_art"
OWNER_ICONS = {
    "cannon": "cannon.webp",
    "kettle": "kettle_on_rails.webp",
    "rail": "rail_block.webp",
    "turret_catapult_mk2": "turret_catapult.webp",
    "core_of_power": "core_of_power_blue.webp",
    "enemy_core": "enemy_core_red.webp",
    "torch": "torch.webp",
    "wall_lantern": "wall_lantern.webp",
    "post_lantern": "post_lantern.webp",
    "campfire": "campfire.webp",
    "light_block_blue": "light_block_blue.webp",
    "light_block_red": "light_block_red.webp",
}
# Renders delivered on an opaque black backdrop: the backdrop is keyed out by a
# flood fill from the corners (dark iron inside the object is not connected to
# the corners, so it survives) with a soft edge for glow halos.
BLACK_KEY_THRESHOLD = 34
BLACK_KEY_FEATHER = 96


def key_black_backdrop(art: Image.Image) -> Image.Image:
    """Return ``art`` with its connected black backdrop made transparent.

    Only used when the render has no transparency at all. The corner flood
    fill marks the backdrop; pixels of the backdrop region keep an alpha
    proportional to their brightness so glow halos fade out instead of
    ending in a hard black fringe.
    """
    alpha = art.split()[3]
    if alpha.getextrema()[0] < 255:
        return art
    marker = art.convert("RGB")
    key = (255, 0, 255)
    width, height = marker.size
    for corner in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
        if marker.getpixel(corner) != key:
            ImageDraw.floodfill(marker, corner, key, thresh=BLACK_KEY_THRESHOLD)
    source = art.load()
    marked = marker.load()
    keyed = art.copy()
    target = keyed.load()
    for y in range(height):
        for x in range(width):
            if marked[x, y] != key:
                continue
            r, g, b, _a = source[x, y]
            brightness = max(r, g, b)
            target[x, y] = (r, g, b, min(255, brightness * 255 // BLACK_KEY_FEATHER))
    return keyed


def owner_icon(item_id: str) -> Image.Image | None:
    path = OWNER_ART / OWNER_ICONS.get(item_id, "")
    if not OWNER_ICONS.get(item_id) or not path.exists():
        return None
    art = key_black_backdrop(Image.open(path).convert("RGBA"))
    art = art.crop(art.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox())
    art = fit(art, 236)
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((CELL - art.width) // 2, (CELL - art.height) // 2))
    return canvas


def source_region(item_id: str) -> Image.Image:
    regions = json.loads(REGIONS.read_text(encoding="utf-8"))
    entry = regions["regions"][item_id]
    atlas_file = regions["atlases"][entry["atlas"]]["file"]
    x, y, w, h = entry["rect"]
    return Image.open(UI / atlas_file).convert("RGBA").crop((x, y, x + w, y + h))


def fit(image: Image.Image, size: int = 200) -> Image.Image:
    image = image.copy()
    image.thumbnail((size, size), Image.LANCZOS)
    return image


def tint(image: Image.Image, color: tuple[int, int, int], strength: float = 0.55) -> Image.Image:
    rgb = image.convert("RGB")
    grey = ImageOps.grayscale(rgb)
    coloured = ImageOps.colorize(grey, (0, 0, 0), color)
    blended = Image.blend(rgb, coloured, strength)
    blended.putalpha(image.split()[3])
    return blended


def icon_flame_shot() -> Image.Image:
    shot = tint(fit(source_region("stone_shot"), 170), (255, 120, 30), 0.6)
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    # Flame tongues above the shot.
    for dx, height, colour in ((-30, 90, (255, 90, 20, 255)), (0, 120, (255, 160, 40, 255)), (30, 80, (255, 220, 90, 255))):
        cx = CELL // 2 + dx
        draw.polygon([(cx - 22, 120), (cx, 120 - height), (cx + 22, 120)], fill=colour)
    canvas.alpha_composite(shot, ((CELL - shot.width) // 2, 128 - shot.height // 2 + 30))
    return canvas


def icon_chest() -> Image.Image:
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    wood = (139, 82, 38, 255)
    dark = (92, 52, 24, 255)
    iron = (110, 118, 126, 255)
    draw.rectangle([36, 104, 220, 210], fill=wood, outline=dark, width=6)
    draw.rectangle([36, 76, 220, 112], fill=dark, outline=dark, width=6)
    for x in (70, 128, 186):
        draw.rectangle([x - 8, 76, x + 8, 210], fill=iron)
    draw.rectangle([116, 104, 140, 132], fill=(226, 170, 44, 255))
    return canvas


def icon_cannon() -> Image.Image:
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.polygon([(30, 190), (110, 190), (70, 120)], fill=(139, 82, 38, 255))
    draw.rounded_rectangle([60, 96, 236, 150], radius=26, fill=(74, 80, 88, 255), outline=(40, 44, 48, 255), width=5)
    draw.ellipse([204, 96, 244, 150], fill=(30, 32, 36, 255))
    draw.rectangle([150, 92, 166, 154], fill=(226, 170, 44, 255))
    draw.ellipse([28, 176, 84, 232], fill=(74, 80, 88, 255), outline=(40, 44, 48, 255), width=4)
    return canvas


def icon_cannonball() -> Image.Image:
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse([58, 58, 198, 198], fill=(58, 62, 68, 255), outline=(30, 32, 36, 255), width=6)
    draw.ellipse([88, 82, 124, 118], fill=(120, 126, 134, 255))
    return canvas


def icon_turret_catapult() -> Image.Image:
    # Pedestal catapult: the catapult art without its wheel row, on an iron
    # turntable over a stone slab (matches the placed pedestal model).
    base = fit(source_region("catapult"), 190)
    base = base.crop((0, 0, base.width, int(base.height * 0.72)))
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([28, 196, 228, 236], fill=(139, 146, 157, 255), outline=(80, 86, 94, 255), width=4)
    draw.ellipse([56, 176, 200, 212], fill=(110, 118, 126, 255), outline=(60, 66, 72, 255), width=5)
    canvas.alpha_composite(base, ((CELL - base.width) // 2, 40))
    return canvas


def icon_wood_axe_flipped() -> Image.Image:
    # Card icon of the axe mirrored so its blade faces the same way as the
    # picks (owner playtest 2026-09-19); the held view keeps the original.
    axe = ImageOps.mirror(fit(source_region("wood_axe"), 220))
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    canvas.alpha_composite(axe, ((CELL - axe.width) // 2, (CELL - axe.height) // 2))
    return canvas


def icon_hot_oil() -> Image.Image:
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle([76, 60, 180, 220], radius=30, fill=(86, 60, 30, 255), outline=(50, 34, 18, 255), width=6)
    draw.rectangle([104, 40, 152, 72], fill=(60, 40, 22, 255))
    draw.ellipse([92, 84, 164, 124], fill=(240, 150, 40, 255))
    return canvas


def icon_kettle() -> Image.Image:
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse([48, 60, 208, 220], fill=(58, 62, 68, 255), outline=(30, 32, 36, 255), width=6)
    draw.ellipse([64, 52, 192, 108], fill=(40, 44, 48, 255), outline=(226, 170, 44, 255), width=6)
    draw.rectangle([30, 196, 226, 214], fill=(110, 118, 126, 255))
    draw.rectangle([30, 220, 226, 232], fill=(110, 118, 126, 255))
    return canvas


def icon_rail() -> Image.Image:
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    for y in (70, 118, 166):
        draw.rectangle([40, y, 216, y + 22], fill=(139, 82, 38, 255))
    draw.rectangle([72, 50, 96, 210], fill=(110, 118, 126, 255))
    draw.rectangle([160, 50, 184, 210], fill=(110, 118, 126, 255))
    return canvas


BUILDERS = {
    "flame_shot": icon_flame_shot, "chest": icon_chest, "cannon": icon_cannon, "cannonball": icon_cannonball,
    "turret_catapult": icon_turret_catapult, "hot_oil": icon_hot_oil, "kettle": icon_kettle, "rail": icon_rail,
    "turret_catapult_mk2": lambda: owner_icon("turret_catapult_mk2"), "wood_axe_flipped": icon_wood_axe_flipped,
    "core_of_power": lambda: owner_icon("core_of_power"), "enemy_core": lambda: owner_icon("enemy_core"),
    "torch": lambda: owner_icon("torch"), "wall_lantern": lambda: owner_icon("wall_lantern"),
    "post_lantern": lambda: owner_icon("post_lantern"), "campfire": lambda: owner_icon("campfire"),
    "light_block_blue": lambda: owner_icon("light_block_blue"), "light_block_red": lambda: owner_icon("light_block_red"),
}


def main() -> int:
    rows = (len(DERIVED) + COLUMNS - 1) // COLUMNS
    atlas = Image.new("RGBA", (CELL * COLUMNS, CELL * rows), (0, 0, 0, 0))
    for index, item_id in enumerate(DERIVED):
        icon = owner_icon(item_id) or BUILDERS[item_id]()
        atlas.alpha_composite(icon, ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL))
        print(f"{index:2d} {item_id}")
    atlas.save(OUTPUT)
    print(f"wrote {OUTPUT.relative_to(ROOT)} {atlas.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
