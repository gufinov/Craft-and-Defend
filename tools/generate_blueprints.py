"""Generate the castle blueprint catalogue.

Blueprints stamp ordinary blocks (owner decision 2026-09-18): each piece is a
list of block cells relative to an anchor (the footprint's minimum corner) plus
typed sockets other pieces can attach to. Once stamped, the world holds plain
voxels — removable, replaceable and understood by pathfinding and breaching.

Writes ``contracts/blueprints.json`` and its runtime mirror
``game/data/blueprints.json``. Dependency-free; ``tests/test_blueprints.py``
validates the output.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = [ROOT / "contracts" / "blueprints.json", ROOT / "game" / "data" / "blueprints.json"]

CASTLE = "castle_stone"
STONE = "stone"
PLANKS = "planks"


def cell(x: int, y: int, z: int, block: str) -> dict:
    return {"offset": [x, y, z], "block": block}


def foundation(size: int) -> list[dict]:
    """One full course of castle stone: levels ground and carries a segment."""
    return [cell(x, 0, z, CASTLE) for x in range(size) for z in range(size)]


def ring(size: int, y: int, block: str) -> list[dict]:
    cells = []
    for x in range(size):
        for z in range(size):
            if x in (0, size - 1) or z in (0, size - 1):
                cells.append(cell(x, y, z, block))
    return cells


def tower_segment(size: int, height: int) -> list[dict]:
    """A hollow ring `height` courses tall with a spiral of stone steps inside.

    Steps climb one course per step along the inner wall, so stacking segments
    continues the spiral; the top step sits one below the segment's top.
    """
    cells = []
    for y in range(height):
        cells.extend(ring(size, y, CASTLE))
    inner = size - 2
    # Inner perimeter path, clockwise from the corner nearest the anchor.
    path = []
    for i in range(inner):
        path.append((1 + i, 1))
    for i in range(1, inner):
        path.append((size - 2, 1 + i))
    for i in range(1, inner):
        path.append((size - 2 - i, size - 2))
    for i in range(1, inner - 1):
        path.append((1, size - 2 - i))
    for step, (x, z) in enumerate(path):
        y = step % height
        if y == 0 and step > 0:
            continue
        cells.append(cell(x, y, z, STONE))
    return cells


def parapet(size: int, y: int) -> list[dict]:
    """Crenellated ring: merlons on every other cell so archers can see out."""
    cells = []
    for x in range(size):
        for z in range(size):
            on_edge = x in (0, size - 1) or z in (0, size - 1)
            if not on_edge:
                continue
            corner = x in (0, size - 1) and z in (0, size - 1)
            merlon = corner or ((x + z) % 2 == 0)
            if merlon:
                cells.append(cell(x, y, z, CASTLE))
    return cells


def cap(size: int) -> list[dict]:
    """Floor of planks on castle stone edging plus a one-course parapet ring."""
    cells = []
    for x in range(size):
        for z in range(size):
            edge = x in (0, size - 1) or z in (0, size - 1)
            cells.append(cell(x, 0, z, CASTLE if edge else PLANKS))
    cells.extend(parapet(size, 1))
    return cells


def wall(length: int, height: int) -> list[dict]:
    return [cell(x, y, 0, CASTLE) for x in range(length) for y in range(height)]


def entity(x: int, y: int, z: int, entity_id: str, rotation: int = 0) -> dict:
    """One castle-kit entity cell of a kit blueprint.

    Blocks stamp voxels; these stamp the one-cell castle-kit entities
    (wall-walk slab, merlon, stone stair) that have no voxel form. `rotation`
    is the piece's own quarter turn inside the kit, added to the kit's.
    """
    return {"offset": [x, y, z], "entity": entity_id, "rotation": rotation}


def wall_kit(length: int) -> tuple[list[dict], list[dict]]:
    """A finished defensive wall section, in one stamp (docs/DEFENSE_SETS.md).

    Two courses of castle stone carry a wall-walk one cell higher, merlons
    crenellate it every other cell, and a pair of stone stairs at each end
    climbs the two half-steps from the ground to the walk. The stairs stand a
    cell in front of the wall (z = 1) and face the approach, so the whole kit
    is a wall you can actually get onto.
    """
    blocks = [cell(x, y, 0, CASTLE) for x in range(length) for y in range(2)]
    pieces = [entity(x, 2, 0, "wall_walk_slab") for x in range(length)]
    pieces += [entity(x, 3, 0, "parapet_merlon") for x in range(length) if x % 2 == 0]
    for x in (0, length - 1):
        pieces += [entity(x, 0, 1, "stone_stair", 2), entity(x, 1, 1, "stone_stair", 2)]
    return blocks, pieces


def sockets_for(size_x: int, size_y: int, size_z: int, top: bool, sides: bool) -> list[dict]:
    sockets = []
    if top:
        sockets.append({"id": "top", "type": "top", "offset": [0, size_y, 0]})
    if sides:
        sockets.append({"id": "east", "type": "side", "offset": [size_x, 0, 0]})
        sockets.append({"id": "west", "type": "side", "offset": [-1, 0, 0]})
        sockets.append({"id": "south", "type": "side", "offset": [0, 0, size_z]})
        sockets.append({"id": "north", "type": "side", "offset": [0, 0, -1]})
    return sockets


def blueprint(id_: str, name: str, size: tuple[int, int, int], blocks: list[dict], top: bool, sides: bool, note: str, entities: list[dict] | None = None) -> dict:
    return {
        "id": id_,
        "display_name": name,
        "size": list(size),
        "sockets": sockets_for(size[0], size[1], size[2], top, sides),
        "blocks": blocks,
        "entities": entities or [],
        "note": note,
    }


def main() -> int:
    catalogue = {
        "schema_version": 1,
        "blueprints": [
            blueprint("foundation_4", "Foundation 4×4", (4, 1, 4), foundation(4), True, True,
                      "Levels a 4×4 base course; a tower segment stacks on its top socket."),
            blueprint("tower_segment_4", "Tower Segment 4×4", (4, 3, 4), tower_segment(4, 3), True, True,
                      "Hollow castle-stone ring three courses tall with a spiral of stone steps; stack to climb."),
            blueprint("cap_4", "Tower Cap 4×4", (4, 2, 4), cap(4), False, True,
                      "Plank floor with castle-stone edge and a crenellated parapet."),
            blueprint("cap_6", "Tower Cap 6×6", (6, 2, 6), cap(6), False, True,
                      "Cap with a 4×4 interior floor; fits a ballista."),
            blueprint("cap_8", "Tower Cap 8×8", (8, 2, 8), cap(8), False, True,
                      "Cap with a 6×6 interior floor; fits a catapult and a ballista together."),
            blueprint("wall_4", "Wall Segment 4×3", (4, 3, 1), wall(4, 3), True, True,
                      "Four castle-stone columns three courses tall; drag-build fills longer runs."),
            blueprint("wall_kit_8", "Wall Kit 8", (8, 4, 2), wall_kit(8)[0], True, True,
                      "A whole defensive section in one stamp: two courses of castle stone, a wall-walk,"
                      " merlons every other cell and stone stairs up at both ends.",
                      wall_kit(8)[1]),
        ],
    }
    text = json.dumps(catalogue, indent=2) + "\n"
    for path in OUTPUTS:
        path.write_text(text, encoding="utf-8")
    for entry in catalogue["blueprints"]:
        counts: dict[str, int] = {}
        for block in entry["blocks"]:
            counts[block["block"]] = counts.get(block["block"], 0) + 1
        for piece in entry.get("entities", []):
            counts[piece["entity"]] = counts.get(piece["entity"], 0) + 1
        print(f"{entry['id']:16s} {entry['size']} {counts}")
    print(f"wrote {len(OUTPUTS)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
