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
    # Coaster rails side project (docs/COASTER_RAILS.md): drawn placeholders.
    "rail_slope", "rail_loop", "mine_cart",
    # Coaster car and hero (docs/COASTER_CAR_AND_HERO.md): owner art.
    "coaster_car", "rail_switch",
    # CoasterCraft tracks (docs/COASTERCRAFT_TRACKS.md): the Climb tool.
    "rail_climb",
    # CoasterCraft card 3 (docs/COASTERCRAFT_TRACKS.md): drawn placeholder.
    "rail_cross",
    # CoasterCraft tracks (docs/COASTERCRAFT_TRACKS.md): drawn placeholders.
    "rail_curve",
    # Industry wave 1 (docs/INDUSTRY_PLAN.md): drawn placeholders, appended in
    # the plan's fixed order: coastercraft_shop, miner, ore_bin, warehouse, foundry.
    "coastercraft_shop",
    "miner", "ore_bin",
    "warehouse", "foundry",
    # Development Expo (docs/DEVELOPMENT_EXPO_HANDOFF.md section 9): the Sign.
    "sign",
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
    "coaster_car": "coaster_car.webp",
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


def icon_rail_slope() -> Image.Image:
    """The rail icon leaning 45 degrees: rails rising to the right on ties."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    for step in range(5):
        x = 44 + step * 36
        y = 196 - step * 36
        draw.rectangle([x, y - 10, x + 30, y + 10], fill=(139, 82, 38, 255))
    for offset in (-22, 22):
        draw.line([(40 + offset, 214 + offset), (216 + offset, 38 + offset)], fill=(110, 118, 126, 255), width=18)
    return canvas


def icon_rail_loop() -> Image.Image:
    """A vertical loop: two concentric rail rings on a short lead-in."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([16, 196, 240, 214], fill=(110, 118, 126, 255))
    draw.ellipse([56, 30, 200, 174], outline=(110, 118, 126, 255), width=14)
    draw.ellipse([78, 52, 178, 152], outline=(139, 82, 38, 255), width=8)
    for x in (40, 96, 152, 208):
        draw.rectangle([x, 186, x + 18, 224], fill=(139, 82, 38, 255))
    return canvas


def icon_rail_climb() -> Image.Image:
    """Rails running flat, curving up a grade and levelling out on a landing."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    # The profile: flat lead-in, slope-in, straight grade, slope-out, landing.
    profile = [(20, 210), (60, 210), (84, 200), (108, 172), (148, 108), (172, 80), (196, 66), (236, 66)]
    ties = [(40, 210), (74, 206), (100, 184), (128, 140), (156, 96), (184, 72), (216, 66)]
    for x, y in ties:
        draw.rectangle([x - 6, y - 26, x + 6, y + 26], fill=(139, 82, 38, 255))
    for offset in (-16, 16):
        draw.line([(x, y + offset) for x, y in profile], fill=(110, 118, 126, 255), width=14, joint="curve")
    return canvas


def _s_bend_points(x0: int, y0: int, x1: int, y1: int, steps: int = 24) -> list:
    """A smoothstep S-curve from (x0, y0) at the bottom to (x1, y1) at the top."""
    points = []
    for index in range(steps + 1):
        t = index / steps
        blend = t * t * (3.0 - 2.0 * t)
        points.append((x0 + (x1 - x0) * blend, y0 + (y1 - y0) * t))
    return points


def icon_rail_switch() -> Image.Image:
    """Rail Switch (the smooth lane switcher): two rails sweeping in one S-bend from the bottom left to the top right."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    centre = _s_bend_points(72, 236, 184, 20)
    for index in range(0, len(centre), 4):
        x, y = centre[index]
        draw.rectangle([x - 34, y - 7, x + 34, y + 7], fill=(139, 82, 38, 255))
    for offset in (-20, 20):
        draw.line([(x + offset, y) for x, y in centre], fill=(110, 118, 126, 255), width=14, joint="curve")
    return canvas


def icon_rail_cross() -> Image.Image:
    """Crossing: two S-bends whose lanes swap, crossing in the middle."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    track_a = _s_bend_points(60, 236, 196, 20)
    track_b = _s_bend_points(196, 236, 60, 20)
    for track in (track_a, track_b):
        for index in range(0, len(track), 4):
            x, y = track[index]
            draw.rectangle([x - 30, y - 6, x + 30, y + 6], fill=(139, 82, 38, 255))
    for track in (track_a, track_b):
        for offset in (-18, 18):
            draw.line([(x + offset, y) for x, y in track], fill=(110, 118, 126, 255), width=12, joint="curve")
    return canvas


def icon_rail_curve() -> Image.Image:
    """Two rails entering at the bottom, bending 90 degrees to the right on ties."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    # The arc's centre is at the top right; the rails are two concentric quarter circles.
    center = (236, 20)
    for radius, width in ((176, 14), (136, 14)):
        box = [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius]
        draw.arc(box, 90, 180, fill=(110, 118, 126, 255), width=width)
    import math
    for step in range(5):
        angle = math.radians(96 + step * 18)
        inner = (center[0] + 120 * math.cos(angle), center[1] + 120 * math.sin(angle))
        outer = (center[0] + 194 * math.cos(angle), center[1] + 194 * math.sin(angle))
        draw.line([inner, outer], fill=(139, 82, 38, 255), width=16)
    return canvas


def icon_miner() -> Image.Image:
    """Miner: an iron drill cone pointing down from a steel frame on a stone base, gold studs."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    stone = (128, 134, 140, 255)
    steel = (110, 118, 126, 255)
    dark = (58, 62, 68, 255)
    gold = (226, 170, 44, 255)
    # Stone base slab with gold studs at the corners.
    draw.rectangle([28, 196, 228, 236], fill=stone, outline=dark, width=5)
    for x in (48, 208):
        draw.rectangle([x - 9, 206, x + 9, 224], fill=gold)
    # Two frame posts and the crossbar carrying the drill.
    for x in (64, 192):
        draw.rectangle([x - 12, 60, x + 12, 200], fill=steel, outline=dark, width=4)
    draw.rectangle([44, 44, 212, 76], fill=steel, outline=dark, width=4)
    # The motor block hanging from the crossbar, then the drill cone.
    draw.rectangle([98, 76, 158, 118], fill=dark)
    draw.polygon([(88, 118), (168, 118), (128, 196)], fill=steel, outline=dark)
    for y in (134, 152, 170):
        half = (196 - y) * 40 // 78
        draw.line([(128 - half, y), (128 + half, y)], fill=dark, width=5)
    return canvas


def icon_ore_bin() -> Image.Image:
    """Ore Bin: an open oak crate with iron bands, heaped with iron ore lumps."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    wood = (139, 82, 38, 255)
    dark = (92, 52, 24, 255)
    iron = (110, 118, 126, 255)
    ore = (150, 156, 162, 255)
    rust = (196, 120, 70, 255)
    draw.polygon([(40, 112), (216, 112), (204, 228), (52, 228)], fill=wood, outline=dark)
    for x in (72, 128, 184):
        draw.rectangle([x - 7, 112, x + 7, 228], fill=iron)
    draw.rectangle([36, 104, 220, 122], fill=dark)
    for cx, cy, r in ((72, 100, 30), (128, 84, 36), (184, 100, 30), (100, 114, 24), (156, 114, 24)):
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ore, outline=(70, 74, 80, 255), width=4)
        draw.ellipse([cx - r // 2, cy - r // 2, cx + r // 3, cy + r // 3], fill=rust)
    return canvas


def icon_mine_cart() -> Image.Image:
    """An oak cart with iron bands on two wheels, seen from the side."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.polygon([(44, 80), (212, 80), (188, 186), (68, 186)], fill=(139, 82, 38, 255), outline=(70, 40, 18, 255))
    draw.rectangle([40, 74, 216, 92], fill=(110, 118, 126, 255))
    draw.rectangle([60, 130, 196, 142], fill=(110, 118, 126, 255))
    for x in (84, 172):
        draw.ellipse([x - 26, 176, x + 26, 228], fill=(58, 62, 68, 255), outline=(30, 32, 36, 255), width=5)
        draw.ellipse([x - 8, 194, x + 8, 210], fill=(226, 170, 44, 255))
    return canvas


def icon_coastercraft_shop() -> Image.Image:
    """The coaster parts foundry: an oak bench on a stone base with a short
    rail and a small cart body on top, seen from the side."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    stone = (118, 126, 134, 255)
    stone_dark = (78, 84, 92, 255)
    wood = (139, 82, 38, 255)
    wood_dark = (92, 52, 24, 255)
    iron = (110, 118, 126, 255)
    gold = (226, 170, 44, 255)
    # Stone base and oak bench top with two legs.
    draw.rectangle([28, 182, 228, 222], fill=stone, outline=stone_dark, width=5)
    draw.rectangle([48, 124, 76, 184], fill=wood_dark)
    draw.rectangle([180, 124, 208, 184], fill=wood_dark)
    draw.rectangle([24, 104, 232, 128], fill=wood, outline=wood_dark, width=5)
    # A short rail on the bench: two iron rails over three oak sleepers.
    for x in (70, 128, 186):
        draw.rectangle([x - 9, 78, x + 9, 106], fill=wood_dark)
    draw.rectangle([40, 82, 216, 90], fill=iron)
    draw.rectangle([40, 96, 216, 104], fill=iron)
    # A small cart body sitting on the rail.
    draw.polygon([(88, 34), (168, 34), (158, 80), (98, 80)], fill=wood, outline=wood_dark)
    draw.rectangle([84, 30, 172, 42], fill=iron)
    for x in (100, 156):
        draw.ellipse([x - 12, 70, x + 12, 94], fill=(58, 62, 68, 255), outline=(30, 32, 36, 255), width=3)
    for x in (44, 212):
        draw.rectangle([x - 6, 110, x + 6, 122], fill=gold)
    draw.rectangle([122, 48, 134, 60], fill=gold)
    return canvas


def icon_warehouse() -> Image.Image:
    """A wide stone-footed oak shed: gable roof, a door and a crate beside it."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    wood = (139, 82, 38, 255)
    dark = (92, 52, 24, 255)
    stone = (110, 118, 126, 255)
    draw.rectangle([24, 196, 232, 224], fill=stone, outline=(70, 74, 80, 255), width=4)
    draw.rectangle([36, 112, 220, 200], fill=wood, outline=dark, width=6)
    for y in (140, 168):
        draw.line([(40, y), (216, y)], fill=dark, width=4)
    draw.polygon([(20, 116), (128, 44), (236, 116)], fill=dark)
    draw.polygon([(40, 112), (128, 56), (216, 112)], fill=(120, 68, 30, 255))
    draw.rectangle([104, 136, 152, 200], fill=dark)
    draw.rectangle([140, 164, 148, 172], fill=(226, 170, 44, 255))
    draw.rectangle([160, 156, 208, 200], fill=(160, 100, 48, 255), outline=dark, width=4)
    draw.line([(160, 156), (208, 200)], fill=dark, width=4)
    draw.line([(208, 156), (160, 200)], fill=dark, width=4)
    return canvas


def icon_foundry() -> Image.Image:
    """A castle-stone furnace body with an iron chimney and a mould tray."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    masonry = (200, 204, 208, 255)
    mortar = (110, 118, 126, 255)
    iron = (58, 62, 68, 255)
    draw.rectangle([40, 108, 176, 216], fill=masonry, outline=mortar, width=6)
    for y in (140, 172):
        draw.line([(44, y), (172, y)], fill=mortar, width=4)
    draw.rectangle([130, 36, 162, 112], fill=iron, outline=(30, 32, 36, 255), width=4)
    draw.rectangle([122, 28, 170, 44], fill=iron)
    for cx, r in ((146, 12), (156, 16)):
        draw.ellipse([cx - r, 20 - r - 8, cx + r, 20 + r - 8], fill=(150, 156, 160, 160))
    draw.rectangle([70, 150, 146, 204], fill=(20, 24, 28, 255))
    draw.rectangle([78, 172, 138, 200], fill=(255, 122, 31, 255))
    draw.rectangle([92, 160, 124, 186], fill=(255, 210, 90, 255))
    draw.rectangle([184, 176, 236, 216], fill=iron, outline=(30, 32, 36, 255), width=4)
    for x in (196, 220):
        draw.rectangle([x - 8, 186, x + 8, 206], fill=(226, 170, 44, 255))
    draw.rectangle([40, 216, 236, 230], fill=mortar)
    return canvas


def icon_sign() -> Image.Image:
    """An oak board on a post with two written lines."""
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    oak = (166, 114, 62, 255)
    dark = (104, 66, 32, 255)
    ink = (58, 40, 22, 255)
    draw.rectangle([116, 150, 140, 236], fill=dark)
    draw.polygon([(96, 236), (160, 236), (150, 246), (106, 246)], fill=dark)
    draw.rectangle([28, 40, 228, 158], fill=oak, outline=dark, width=7)
    for y in (74, 104):
        draw.line([(28, y), (228, y)], fill=(148, 100, 54, 255), width=3)
    for y in (66, 96, 126):
        draw.line([(56, y), (200, y)], fill=ink, width=8)
    draw.line([(56, 126), (152, 126)], fill=ink, width=8)
    for x in (44, 212):
        draw.ellipse([x - 7, 46, x + 7, 60], fill=(110, 118, 126, 255))
    return canvas


BUILDERS = {
    "flame_shot": icon_flame_shot, "chest": icon_chest, "cannon": icon_cannon, "cannonball": icon_cannonball,
    "turret_catapult": icon_turret_catapult, "hot_oil": icon_hot_oil, "kettle": icon_kettle, "rail": icon_rail,
    "turret_catapult_mk2": lambda: owner_icon("turret_catapult_mk2"), "wood_axe_flipped": icon_wood_axe_flipped,
    "core_of_power": lambda: owner_icon("core_of_power"), "enemy_core": lambda: owner_icon("enemy_core"),
    "torch": lambda: owner_icon("torch"), "wall_lantern": lambda: owner_icon("wall_lantern"),
    "post_lantern": lambda: owner_icon("post_lantern"), "campfire": lambda: owner_icon("campfire"),
    "light_block_blue": lambda: owner_icon("light_block_blue"), "light_block_red": lambda: owner_icon("light_block_red"),
    "rail_slope": icon_rail_slope, "rail_loop": icon_rail_loop, "mine_cart": icon_mine_cart, "rail_switch": icon_rail_switch,
    "coaster_car": lambda: owner_icon("coaster_car"), "rail_climb": icon_rail_climb,
    "rail_cross": icon_rail_cross,
    "rail_curve": icon_rail_curve,
    "coastercraft_shop": icon_coastercraft_shop,
    "miner": icon_miner, "ore_bin": icon_ore_bin,
    "warehouse": icon_warehouse, "foundry": icon_foundry,
    "sign": icon_sign,
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
