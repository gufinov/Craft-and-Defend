"""Validate design fixtures and repository integrity, not the game runtime."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTAINER_STATION_TYPES = ("chest", "warehouse", "ore_bin")
REPORT_SHA = "f238c37f3f9509b2a152e632503b7a4e16ab8fd4377dcc32122717e30c13cebd"
ITEM_CATEGORIES = {"resource", "building", "tool", "station", "food"}
NAVIGATION_SCENARIOS = {"corridor_detour", "trench", "two_step_stair", "bridge_removal", "two_cell_tunnel", "capability_blocked_wall"}
# P4G asset attribute sheet (docs/P4G_CORE_AND_LIGHTS.md): every core and light
# source carries a value, a role, its light, its mounting rule and its space.
ATTRIBUTE_ENTITIES = {"core_of_power", "enemy_core", "torch", "wall_lantern", "post_lantern", "campfire", "light_block_blue", "light_block_red"}
ATTRIBUTE_ROLES = {"core", "light", "decor", "rail", "machine", "storage"}
# Coaster rails side project (docs/COASTER_RAILS.md): track pieces and the cart.
COASTER_TOOLS = {"loop", "climb", "bend", "cross", "curve"}
# `rail_switch` is both the Rail Switch tool (coaster_tool "bend", laying floating
# `rail_loop` curve pieces) and the grounded blocky lane-shift piece the loop
# element lays, so it alone keeps its support.
GROUNDED_COASTER_TOOL_ENTITIES = {"rail_switch"}
ATTRIBUTE_MOUNTS = {"ground", "wall", "ceiling", "any_solid_top", "any_solid_top_or_wall", "block"}
# Development Expo manifest (docs/DEVELOPMENT_EXPO.md). `reserved` is the
# empty-parcel kind the growth rule needs on top of the five exhibit scales.
EXPO_KINDS = {"catalog", "functional", "system_demo", "environmental", "scenario", "showcase", "reserved"}
EXPO_ORIENTATIONS = {"north", "south", "east", "west"}
# Signs card 2: an exhibit may anchor its board instead of taking the parcel
# corner, and a sign block may ask for the two-cell wide board.
EXPO_SIGN_ANCHORS = {"centre", "entrance"}
EXPO_SIGN_BOARDS = {"narrow", "wide"}
EXPO_TERRAIN = {"level", "natural", "tree", "forest", "quarry", "coal_seam", "surface_ore",
                "ore_face", "mountain", "tunnel", "ore_core", "chamber", "pavilion",
                "supply_depot",
                # Card E (Construction Yard, Defense Range, Battlefield): composite
                # parcels the builder authors as one piece - the exhibit's declared
                # entities are placed by the terrain builder, not one per parcel.
                "wall_demo", "blueprint_demo", "castle_demo", "siege_booth",
                "field", "camp", "battery", "fortification", "magazine",
                # Defence sets (docs/DEFENSE_SETS.md): the Wall Kit exhibit,
                # stamped from the kit blueprint like the blueprint demo.
                "wall_kit_demo"}
# Supply Depot (docs/DEVELOPMENT_EXPO.md, handoff sections 8 and 9). The
# categories and the item -> category map are read out of the one runtime
# source, `game/scripts/ui/item_categories.gd`, rather than copied here: the
# depot's whole point is that a newly registered item is either classified
# there or reported, and two copies of the map would let them disagree.
ITEM_CATEGORIES_GD = "game/scripts/ui/item_categories.gd"
SUPPLY_UNASSIGNED = "unassigned"
# Categories that may exist as signage only (mirrors SupplyDepot.RESERVED_CATEGORIES).
SUPPLY_RESERVED_CATEGORIES = ("future_food", "future_armor")
# Depot geometry inside its parcel (mirrors SupplyDepot's constants).
SUPPLY_COLUMN_STRIDE = 4
SUPPLY_ROW_PITCH = 4
SUPPLY_EDGE_INSET = 1
EXPO_PREPARE = {"full", "connect"}
EXPO_CARDS = {"A", "B", "C", "D", "E", "F", "G"}


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def vector(value, positive=False):
    return (isinstance(value, list) and len(value) == 3
            and all(type(v) is int and (not positive or v > 0) for v in value))


def numeric_vector(value, positive=False):
    return (isinstance(value, list) and len(value) == 3
            and all(type(v) in (int, float) and not isinstance(v, bool)
                    and (not positive or v > 0) for v in value))


def index(rows, field, label):
    require(isinstance(rows, list) and rows, f"{label}: nonempty list required")
    result = {}
    for row in rows:
        key = row[field]
        require(key not in result, f"{label}: duplicate {field} {key}")
        result[key] = row
    return result


def load_bundle(root=ROOT):
    return {name: read_json(root / "contracts" / f"{name}.json")
            for name in ("content", "world", "keybinds", "placement_cases", "development_expo")}


def in_bounds(cell, world):
    return all(lo <= c < lo + size
               for c, lo, size in zip(cell, world["min_cell"], world["size"]))


def placement_result(case, world):
    """Specification oracle over cells. Does not test collision, rotation or I/O."""
    cells = [tuple(a + b for a, b in zip(case["anchor"], offset))
             for offset in case["offsets"]]
    if any(not in_bounds(c, world) for c in cells):
        return "OUT_OF_BOUNDS"
    unloaded = {tuple(c) for c in case["unloaded"]}
    if any(c in unloaded for c in cells) or any(tuple(c) in unloaded for c in case["required_support"]):
        return "UNLOADED"
    occupied = {tuple(c) for c in case["occupied"]}
    if any(c in occupied for c in cells):
        return "OCCUPIED"
    player = {tuple(c) for c in case["player_cells"]}
    if any(c in player for c in cells):
        return "PLAYER_OVERLAP"
    if any(not in_bounds(c, world) or tuple(c) not in occupied for c in case["required_support"]):
        return "UNSUPPORTED"
    return "OK"


def reachable_items(content, world):
    """Monotonic capability proof; ignores finite quantities and spatial access."""
    items = {row["id"]: row for row in content["items"]}
    present = {row["block"] for row in world["layers"] + world["patches"]}
    # Procedural ore rows name blocks by stable id; they are generated in stone
    # below the surface, so they count as present for capability reachability.
    block_ids = {row["id"]: row["voxel_id"] for row in content["blocks"]}
    present |= {block_ids[row["block"]] for row in world.get("terrain", {}).get("ores", [])
                if row.get("block") in block_ids}
    available, stations = set(), {"hand"}
    changed = True
    while changed:
        before = (frozenset(available), frozenset(stations))
        tier = max([items[i].get("pick_tier", 0) for i in available] + [0])
        for block in content["blocks"]:
            if (block["voxel_id"] in present and not block["protected"]
                    and block["drop"] and block["min_pick_tier"] <= tier):
                available.add(block["drop"])
        for item in list(available):
            entity = items[item].get("places_entity")
            if entity:
                stations.add(entity)
        for recipe in content["recipes"]:
            if recipe["station"] in stations and set(recipe["inputs"]) <= available:
                available.update(recipe["outputs"])
        changed = before != (frozenset(available), frozenset(stations))
    return available


def validate_attributes(entity):
    """Asset attribute block: value, role, light (or null), mount, space, notes."""
    attributes = entity.get("attributes")
    label = entity["id"]
    require(isinstance(attributes, dict), f"missing attributes: {label}")
    require(set(attributes) == {"value", "role", "light", "mount", "space", "notes"}, f"attributes must hold exactly value/role/light/mount/space/notes: {label}")
    require(integer(attributes["value"], 0), f"invalid attribute value: {label}")
    require(attributes["role"] in ATTRIBUTE_ROLES, f"invalid attribute role: {label}")
    require(attributes["mount"] in ATTRIBUTE_MOUNTS, f"invalid attribute mount: {label}")
    require(vector(attributes["space"], positive=True), f"invalid attribute space: {label}")
    require(isinstance(attributes["notes"], str) and attributes["notes"].strip(), f"attribute notes required: {label}")
    light = attributes["light"]
    if light is not None:
        require(isinstance(light, dict) and set(light) == {"color", "energy", "range", "flicker"}, f"light must hold color/energy/range/flicker: {label}")
        require(isinstance(light["color"], str) and re.fullmatch(r"[a-fA-F0-9]{6}", light["color"]), f"invalid light color: {label}")
        require(all(type(light[k]) in (int, float) and not isinstance(light[k], bool) and light[k] > 0 for k in ("energy", "range")), f"invalid light energy/range: {label}")
        require(type(light["flicker"]) is bool, f"light flicker must be bool: {label}")
    occupied = entity["occupied_offsets"]
    extent = [max(v[axis] for v in occupied) - min(v[axis] for v in occupied) + 1 for axis in range(3)]
    require(attributes["space"] == extent, f"attribute space {attributes['space']} differs from the occupied extent {extent}: {label}")
    if attributes["role"] == "core":
        require(attributes["mount"] == "ground" and entity.get("mount", {}).get("allowed") == ["ground"], f"a core mounts on the ground only: {label}")
    if attributes["role"] in ("core", "light"):
        require(light is not None, f"cores and lights must carry a light: {label}")
        require(isinstance(entity.get("defense"), dict) and isinstance(entity.get("navigation"), dict), f"cores and lights need defense and navigation blocks: {label}")


def validate_ores(ores, blocks, world):
    """Ore distribution table: see docs/P4B_RESOURCE_DISTRIBUTION.md.

    depth = surface - y, so depth 1..2 is always dirt and the deepest possible
    ore sits one cell above bedrock. Rows own cumulative bands of one roll in
    [0, 1000); the widths must therefore sum below 1000 so stone remains.
    """
    require(isinstance(ores, list) and ores, "terrain.ores: nonempty list required")
    world_height = world["size"][1]
    seen = set()
    total = 0
    for row in ores:
        require(isinstance(row, dict), "invalid ore row")
        block = blocks.get(row.get("block"))
        require(block is not None, f"unknown ore block: {row.get('block')}")
        require(row["block"] not in seen, f"duplicate ore block: {row['block']}")
        seen.add(row["block"])
        require(block["solid"] and not block["protected"] and block["drop"] is not None, f"ore block must be solid, unprotected and droppable: {row['block']}")
        require(integer(row.get("min_depth"), 1) and integer(row.get("max_depth"), 1)
                and row["min_depth"] <= row["max_depth"] and row["max_depth"] <= world_height,
                f"invalid ore depth range: {row['block']}")
        require(row["min_depth"] >= 3, f"ore cannot occupy the two soil cells under the surface: {row['block']}")
        require(integer(row.get("cluster_per_thousand"), 1) and row["cluster_per_thousand"] < 1000, f"invalid ore frequency: {row['block']}")
        require(integer(row.get("cluster_size"), 1) and row["cluster_size"] <= 8, f"invalid ore cluster size: {row['block']}")
        total += row["cluster_per_thousand"]
    require(total < 1000, f"ore frequencies sum to {total} per thousand; stone must remain")


def expo_parcels(expo):
    """Python oracle for ExpoLayout's parcel packer (docs/DEVELOPMENT_EXPO.md).

    Exhibits with an explicit `offset` are anchored there; the rest are shelf
    packed in manifest order inside the district's usable rectangle. Must stay
    identical to game/scripts/expo/expo_layout.gd.
    """
    path = expo["local_path_width"]
    parcels = {}
    for district in expo["districts"]:
        origin, size = district["origin"], district["size"]
        usable = (origin[0] + path, origin[2] + path, size[0] - 2 * path, size[2] - 2 * path)
        cursor_x, cursor_z, row_depth = usable[0], usable[1], 0
        for exhibit in district["exhibits"]:
            footprint, clearance = exhibit["footprint"], exhibit["clearance"]
            if "offset" in exhibit:
                offset = exhibit["offset"]
                parcels[exhibit["id"]] = ([origin[0] + offset[0], origin[1] + offset[1], origin[2] + offset[2]],
                                          list(footprint), district["id"])
                continue
            cell_w, cell_d = footprint[0] + 2 * clearance, footprint[2] + 2 * clearance
            if cursor_x + cell_w > usable[0] + usable[2]:
                cursor_x, cursor_z, row_depth = usable[0], cursor_z + row_depth + path, 0
            require(cursor_z + cell_d <= usable[1] + usable[3],
                    f"expo district {district['id']} is full at exhibit {exhibit['id']}")
            parcels[exhibit["id"]] = ([cursor_x + clearance, origin[1] + 1, cursor_z + clearance],
                                      list(footprint), district["id"])
            cursor_x += cell_w + path
            row_depth = max(row_depth, cell_d)
    return parcels


def expo_world_bounds(expo):
    chunk, margin = expo["chunk_size"], expo["expansion_margin"]
    boxes = expo_boxes(expo)
    low = [min(box[0][axis] for box in boxes) for axis in range(3)]
    high = [max(box[0][axis] + box[1][axis] for box in boxes) for axis in range(3)]
    minimum = [low[0] - margin, expo["floor_y"], low[2] - margin]
    maximum = [high[0] + margin, high[1] + expo["vertical_margin"], high[2] + margin]
    minimum = [chunk * (value // chunk) for value in minimum]
    maximum = [chunk * -((-value) // chunk) for value in maximum]
    return minimum, [maximum[axis] - minimum[axis] for axis in range(3)]


def expo_boxes(expo):
    boxes = []
    for district in expo["districts"]:
        boxes.append((district["origin"], district["size"], district["id"]))
        corridor = district["expansion_corridor"]
        boxes.append((corridor["origin"], corridor["size"], district["id"] + " corridor"))
    return boxes


def boxes_overlap(first, second):
    return all(first[0][axis] < second[0][axis] + second[1][axis]
               and second[0][axis] < first[0][axis] + first[1][axis] for axis in range(3))


def item_categories(root=ROOT):
    """(ordered [(id, label)], item id -> category) read out of ItemCategories.

    Parsed rather than duplicated: the runtime map in
    `game/scripts/ui/item_categories.gd` is the single source of truth, and an
    item missing from it must fail here (see `validate_supply_depot`).
    """
    text = (Path(root) / ITEM_CATEGORIES_GD).read_text(encoding="utf-8")
    order = [(SUPPLY_UNASSIGNED if key == "UNASSIGNED" else key.strip('"'), label)
             for key, label in re.findall(r'\{"id":\s*("[a-z0-9_]+"|UNASSIGNED),\s*"label":\s*"([^"]*)"\}', text)]
    require(order, "item categories: CATEGORIES could not be read")
    block = re.search(r"const ITEM_CATEGORY := \{(.*?)\n\}", text, re.S)
    require(block is not None, "item categories: ITEM_CATEGORY could not be read")
    mapping = dict(re.findall(r'"([a-z0-9_]+)":\s*"([a-z0-9_]+)"', block.group(1)))
    known = {key for key, _ in order}
    require(all(value in known for value in mapping.values()), "item categories: ITEM_CATEGORY names an unknown category")
    return order, mapping


def supply_slots(item, units):
    """Chest slots `units` of one item type takes: one per stack, rounded up."""
    return -(-units // max(1, item["max_stack"]))


def supply_catalog(content, expo, root=ROOT):
    """Python oracle of `SupplyDepot.catalog` (game/scripts/expo/supply_depot.gd).

    Category order, then registry order inside a category; a chest takes items
    until the next one would exceed the type or slot budget, then a new chest
    starts. Must stay identical to the GDScript - change one, change the other.
    """
    config = expo.get("supply", {})
    units = config["units_per_item"]
    types_per_chest = config["types_per_chest"]
    slots_per_chest = config["slots_per_chest"]
    whitelist = set(config.get("hidden_whitelist", []))
    order, mapping = item_categories(root)
    visible = [row for row in content["items"] if not row.get("hidden") or row["id"] in whitelist]
    unassigned = [row["id"] for row in visible if mapping.get(row["id"], SUPPLY_UNASSIGNED) == SUPPLY_UNASSIGNED]
    grouped = {}
    for row in visible:
        category = mapping.get(row["id"], SUPPLY_UNASSIGNED)
        if category != SUPPLY_UNASSIGNED:
            grouped.setdefault(category, []).append(row)
    chests, reserved = [], []
    for category, label in order:
        if category == SUPPLY_UNASSIGNED:
            continue
        members = grouped.get(category, [])
        if not members:
            if category in SUPPLY_RESERVED_CATEGORIES:
                reserved.append({"category": category, "label": label})
            continue
        groups, current, used = [], [], 0
        for row in members:
            slots = min(supply_slots(row, units), slots_per_chest)
            if current and (len(current) >= types_per_chest or used + slots > slots_per_chest):
                groups.append((current, used))
                current, used = [], 0
            current.append(row["id"])
            used += slots
        if current:
            groups.append((current, used))
        for part, (group, slots_used) in enumerate(groups, start=1):
            chests.append({"category": category, "label": label, "part": part, "parts": len(groups),
                           "items": group, "slots": slots_used})
    return {"units": units, "types_per_chest": types_per_chest, "slots_per_chest": slots_per_chest,
            "chests": chests, "reserved": reserved, "unassigned": unassigned,
            "visible": [row["id"] for row in visible]}


def supply_capacity(size):
    """Chest stands the depot parcel holds (mirrors SupplyDepot.stand_capacity)."""
    span = size[0] - SUPPLY_EDGE_INSET - 2
    columns = 0 if span < 0 else span // SUPPLY_COLUMN_STRIDE + 1
    return columns * max(0, size[2] // SUPPLY_ROW_PITCH)


def validate_supply_depot(expo, content, exhibits, parcels, root=ROOT):
    """The Supply Depot rules (handoff section 8). Returns the solved catalog."""
    config = expo.get("supply")
    require(isinstance(config, dict), "expo supply: the manifest needs a supply block")
    for field in ("units_per_item", "types_per_chest", "slots_per_chest"):
        require(integer(config.get(field), 1), f"expo supply: invalid {field}")
    whitelist = config.get("hidden_whitelist")
    require(isinstance(whitelist, list) and all(isinstance(value, str) for value in whitelist),
            "expo supply: invalid hidden_whitelist")
    items = {row["id"] for row in content["items"]}
    require(not (set(whitelist) - items), f"expo supply: hidden_whitelist names unknown items: {sorted(set(whitelist) - items)}")
    depot = [name for name, exhibit in exhibits.items() if exhibit["terrain"] == "supply_depot"]
    require(len(depot) == 1, "expo supply: exactly one exhibit carries the supply_depot terrain")
    catalog = supply_catalog(content, expo, root)
    require(not catalog["unassigned"],
            "expo supply: visible items with no Expo category, classify them in "
            f"{ITEM_CATEGORIES_GD}: {catalog['unassigned']}")
    stocked = []
    for chest in catalog["chests"]:
        label = f"{chest['category']} {chest['part']}/{chest['parts']}"
        require(len(chest["items"]) <= catalog["types_per_chest"],
                f"expo supply: chest {label} holds more than {catalog['types_per_chest']} distinct item types")
        require(chest["slots"] <= catalog["slots_per_chest"],
                f"expo supply: chest {label} fills more than {catalog['slots_per_chest']} of its nine slots")
        stocked.extend(chest["items"])
    duplicates = sorted({item for item in stocked if stocked.count(item) > 1})
    require(not duplicates, f"expo supply: items stocked in more than one chest: {duplicates}")
    missing = sorted(set(catalog["visible"]) - set(stocked))
    require(not missing, f"expo supply: visible items missing from the supply catalog: {missing}")
    origin, size, _district = parcels[depot[0]]
    stands = len(catalog["chests"]) + len(catalog["reserved"])
    require(stands <= supply_capacity(size),
            f"expo supply: {stands} chest stands do not fit the depot parcel {size} "
            f"(capacity {supply_capacity(size)}); widen the district or its parcel")
    return catalog


def validate_development_expo(expo, content, root=ROOT):
    """The Development Expo manifest (docs/DEVELOPMENT_EXPO.md, handoff sections 6 and 7)."""
    require(expo.get("status") == "development_expo_1", "expo: unexpected status")
    for field in ("ground_y", "floor_y", "chunk_size", "expansion_margin", "vertical_margin",
                  "avenue_width", "local_path_width", "clear_height", "fill_bottom", "expo_version"):
        require(type(expo.get(field)) is int, f"expo: invalid {field}")
    require(expo["chunk_size"] > 0 and expo["expansion_margin"] >= 0 and expo["avenue_width"] >= 3
            and expo["local_path_width"] >= 1, "expo: invalid campus metrics")
    require(numeric_vector(expo.get("spawn_feet")), "expo: invalid spawn_feet")
    items = {row["id"] for row in content["items"]}
    entities = {row["id"] for row in content["entities"]}
    districts = index(expo["districts"], "id", "expo districts")
    exhibits = {}
    reserved = 0
    for district in expo["districts"]:
        label = district["id"]
        require(vector(district["origin"]) and vector(district["size"], positive=True), f"expo {label}: invalid box")
        require(district["origin"][1] == expo["ground_y"], f"expo {label}: district floor must sit at ground_y")
        require(district["prepare"] in EXPO_PREPARE, f"expo {label}: invalid prepare")
        require(district["terrain"] in EXPO_TERRAIN, f"expo {label}: invalid district terrain")
        require(isinstance(district.get("name"), str) and district["name"], f"expo {label}: missing name")
        require(type(district.get("expansion_priority")) is int and district["expansion_priority"] >= 1,
                f"expo {label}: invalid expansion priority")
        validate_expo_sign(district.get("sign"), items, f"expo {label}")
        for connection in district["connections"]:
            require(connection in districts, f"expo {label}: unknown connection {connection}")
        entrance = district["entrance"]
        require(vector(entrance), f"expo {label}: invalid entrance")
        require(any(entrance[axis] in (district["origin"][axis], district["origin"][axis] + district["size"][axis] - 1)
                    for axis in (0, 2)), f"expo {label}: entrance must sit on the district edge")
        corridor = district["expansion_corridor"]
        require(vector(corridor["origin"]) and vector(corridor["size"], positive=True), f"expo {label}: invalid corridor")
        require(min(corridor["size"][0], corridor["size"][2]) >= expo["avenue_width"],
                f"expo {label}: expansion corridor narrower than an avenue")
        touching = False
        for axis in (0, 2):
            other = 2 if axis == 0 else 0
            flush = (corridor["origin"][axis] + corridor["size"][axis] == district["origin"][axis]
                     or district["origin"][axis] + district["size"][axis] == corridor["origin"][axis])
            overlap = (corridor["origin"][other] < district["origin"][other] + district["size"][other]
                       and district["origin"][other] < corridor["origin"][other] + corridor["size"][other])
            touching = touching or (flush and overlap)
        require(touching, f"expo {label}: expansion corridor must touch its district")
        for exhibit in district["exhibits"]:
            name = exhibit["id"]
            require(name not in exhibits, f"expo: duplicate exhibit {name}")
            exhibits[name] = exhibit
            require(exhibit["kind"] in EXPO_KINDS, f"expo exhibit {name}: invalid kind")
            require(vector(exhibit["footprint"], positive=True), f"expo exhibit {name}: invalid footprint")
            require(type(exhibit["clearance"]) is int and exhibit["clearance"] >= 0, f"expo exhibit {name}: invalid clearance")
            require(exhibit["orientation"] in EXPO_ORIENTATIONS, f"expo exhibit {name}: invalid orientation")
            require(exhibit["terrain"] in EXPO_TERRAIN, f"expo exhibit {name}: invalid terrain")
            require(type(exhibit.get("expansion_priority")) is int and exhibit["expansion_priority"] >= 1,
                    f"expo exhibit {name}: invalid expansion priority")
            require(isinstance(exhibit.get("connections"), list) and exhibit["connections"],
                    f"expo exhibit {name}: missing connection requirement")
            for entity_id in exhibit["entities"]:
                require(entity_id in entities, f"expo exhibit {name}: unknown entity {entity_id}")
            for item_id in exhibit["items"]:
                require(item_id in items, f"expo exhibit {name}: unknown item {item_id}")
            if "offset" in exhibit:
                require(vector(exhibit["offset"]), f"expo exhibit {name}: invalid offset")
            # `placements` pins named fixtures inside the parcel (the Industry
            # chain, the light gallery): the manifest owns those coordinates,
            # the builder only applies them.
            placements = exhibit.get("placements", [])
            require(isinstance(placements, list), f"expo exhibit {name}: invalid placements")
            for placement in placements:
                require(isinstance(placement, dict), f"expo exhibit {name}: invalid placement")
                entity_id = placement.get("entity")
                require(entity_id in entities, f"expo exhibit {name}: placement names unknown entity {entity_id}")
                require(entity_id in exhibit["entities"],
                        f"expo exhibit {name}: placement entity {entity_id} is not listed in entities")
                require(vector(placement.get("offset")), f"expo exhibit {name}: invalid placement offset")
                offset = placement["offset"]
                require(all(0 <= offset[axis] < exhibit["footprint"][axis] for axis in range(3)),
                        f"expo exhibit {name}: placement of {entity_id} falls outside the footprint")
                require(type(placement.get("rotation", 0)) is int and 0 <= placement.get("rotation", 0) <= 3,
                        f"expo exhibit {name}: invalid placement rotation")
            # `added_in` is the What's new stamp the Expo Directory sorts on
            # (docs/DEVELOPMENT_EXPO.md): an ISO date or a zero-padded version,
            # compared as a string, so it has to be a non-empty string.
            if "added_in" in exhibit:
                require(isinstance(exhibit["added_in"], str) and exhibit["added_in"].strip(),
                        f"expo exhibit {name}: invalid added_in stamp")
            if "reset_group" in exhibit:
                require(isinstance(exhibit["reset_group"], str) and exhibit["reset_group"],
                        f"expo exhibit {name}: invalid reset group")
            validate_expo_sign(exhibit.get("sign"), items, f"expo exhibit {name}")
            validate_expo_sign_anchor(exhibit, f"expo exhibit {name}")
            if exhibit["kind"] == "reserved":
                reserved += 1
                require(not exhibit["entities"] and not exhibit["items"],
                        f"expo exhibit {name}: a reserved parcel stays empty")
                require(exhibit.get("sign"), f"expo exhibit {name}: a reserved parcel must be signed")
    for name, exhibit in exhibits.items():
        anchor = exhibit.get("sign_anchor")
        if isinstance(anchor, str) and anchor.startswith("near:"):
            require(anchor[5:] in exhibits,
                    f"expo exhibit {name}: sign anchor names unknown exhibit {anchor[5:]}")
    require(reserved >= 1, "expo: at least one visible reserved future-expansion parcel is required")
    boxes = expo_boxes(expo)
    for first in range(len(boxes)):
        for second in range(first + 1, len(boxes)):
            require(not boxes_overlap(boxes[first], boxes[second]),
                    f"expo: {boxes[first][2]} overlaps {boxes[second][2]}")
    parcels = expo_parcels(expo)
    placed = list(parcels.items())
    for first in range(len(placed)):
        origin, size, district_id = placed[first][1]
        district = districts[district_id]
        require(all(origin[axis] >= district["origin"][axis]
                    and origin[axis] + size[axis] <= district["origin"][axis] + district["size"][axis]
                    for axis in range(3)), f"expo parcel {placed[first][0]} leaves its district")
        # A `nested` parcel is carved inside another exhibit's volume (the mine
        # tunnel inside the mountain), so it is exempt from the overlap rule and
        # instead has to sit wholly inside an ordinary parcel of its district.
        if exhibits[placed[first][0]].get("nested", False):
            require(any(key != placed[first][0] and box[2] == district_id and not exhibits[key].get("nested", False)
                        and all(origin[axis] >= box[0][axis]
                                and origin[axis] + size[axis] <= box[0][axis] + box[1][axis] for axis in range(3))
                        for key, box in placed), f"expo parcel {placed[first][0]}: nested outside every host parcel")
            continue
        for second in range(first + 1, len(placed)):
            if exhibits[placed[second][0]].get("nested", False):
                continue
            require(not boxes_overlap((origin, size), placed[second][1][:2]),
                    f"expo: parcel {placed[first][0]} overlaps {placed[second][0]}")
    minimum, size = expo_world_bounds(expo)
    require(all(value % expo["chunk_size"] == 0 for value in size), "expo: world size is not chunk aligned")
    require(minimum[1] <= expo["floor_y"], "expo: world floor above the configured bedrock level")
    for box in boxes:
        require(all(box[0][axis] >= minimum[axis] and box[0][axis] + box[1][axis] <= minimum[axis] + size[axis]
                    for axis in range(3)), f"expo: {box[2]} falls outside the computed world bounds")
    catalog = validate_supply_depot(expo, content, exhibits, parcels, root)
    # Growth rule (handoff section 6): a newly registered item must be exhibited,
    # stocked in the Supply Depot or explicitly deferred to a named card, never
    # silently absent. The depot covers every classified visible item, so what
    # this rule actually catches now is an item the depot could not classify -
    # `validate_supply_depot` names it first, with the file to classify it in.
    deferred = expo["deferred_items"]
    shown = {item_id for exhibit in exhibits.values() for item_id in exhibit["items"]}
    shown |= {entity_id for exhibit in exhibits.values() for entity_id in exhibit["entities"]}
    shown |= {str(sign.get("item")) for sign in
              [exhibit.get("sign") or {} for exhibit in exhibits.values()] if sign.get("item")}
    shown |= {item_id for chest in catalog["chests"] for item_id in chest["items"]}
    unclassified = sorted(items - shown - set(deferred))
    require(not unclassified, f"expo: items with no exhibit and no deferral: {unclassified}")
    require(all(card in EXPO_CARDS for card in deferred.values()), "expo: deferred item names an unknown card")
    require(not (set(deferred) - items), f"expo: deferral names unknown items: {sorted(set(deferred) - items)}")


def validate_expo_sign_anchor(exhibit, label):
    """The optional `sign_anchor` (docs/DEVELOPMENT_EXPO.md section 1): a cell
    offset inside the footprint, `centre`, `entrance`, or `near:<exhibit id>`.
    The named exhibit is checked after the whole manifest is read."""
    if "sign_anchor" not in exhibit:
        return
    anchor = exhibit["sign_anchor"]
    if isinstance(anchor, list):
        require(vector(anchor), f"{label}: invalid sign anchor")
        require(all(0 <= anchor[axis] < exhibit["footprint"][axis] for axis in range(3)),
                f"{label}: sign anchor falls outside the footprint")
        return
    require(isinstance(anchor, str) and (anchor in EXPO_SIGN_ANCHORS or anchor.startswith("near:")),
            f"{label}: invalid sign anchor {anchor}")


def validate_expo_sign(sign, items, label):
    if sign is None:
        return
    require(isinstance(sign, dict) and isinstance(sign.get("title"), str) and sign["title"], f"{label}: invalid sign title")
    require(isinstance(sign.get("lines", []), list)
            and all(isinstance(line, str) for line in sign.get("lines", [])), f"{label}: invalid sign lines")
    if "item" in sign:
        require(sign["item"] in items, f"{label}: sign names unknown item {sign['item']}")
    if "board" in sign:
        require(sign["board"] in EXPO_SIGN_BOARDS, f"{label}: invalid sign board {sign['board']}")


def validate_bundle(bundle):
    for name, data in bundle.items():
        require(data["schema_version"] == 1, f"{name}: unsupported schema")
    content, world, keys, placements = (bundle[n] for n in
        ("content", "world", "keybinds", "placement_cases"))
    if "development_expo" in bundle:
        validate_development_expo(bundle["development_expo"], content)
    blocks = index(content["blocks"], "id", "blocks")
    numeric = index(content["blocks"], "voxel_id", "blocks")
    items = index(content["items"], "id", "items")
    entities = index(content["entities"], "id", "entities")
    index(content["recipes"], "id", "recipes")
    balance = content.get("balance")
    require(isinstance(balance, dict), "missing balance catalogue")
    furnace_balance = balance.get("furnace", {})
    require(furnace_balance.get("fuel_item") in items
            and integer(furnace_balance.get("operations_per_fuel"), 1), "invalid furnace balance")
    require(any(recipe.get("station") == "furnace"
                and recipe.get("inputs", {}).get(furnace_balance["fuel_item"]) == 1
                for recipe in content["recipes"]), "furnace fuel must be an explicit recipe input")
    harvesting_balance = balance.get("harvesting", {})
    require(integer(harvesting_balance.get("maximum_connected_trunk_blocks"), 1), "invalid harvesting balance")
    for section_name, integer_fields, number_fields in (
        ("practice_defense", ("wall_integrity", "repair_amount", "raider_health", "raider_damage", "ballista_damage", "ballista_starting_bolts"),
         ("warning_seconds", "raider_attack_interval_seconds", "ballista_interval_seconds", "ballista_maximum_range")),
        ("core_defense", ("core_integrity", "raider_health", "raider_damage", "troll_health", "troll_damage"),
         ("warning_seconds", "raider_attack_interval_seconds", "troll_range", "troll_attack_interval_seconds")),
    ):
        section = balance.get(section_name, {})
        require(isinstance(section, dict)
                and all(integer(section.get(field), 1) for field in integer_fields)
                and all(type(section.get(field)) in (int, float) and section[field] > 0 for field in number_fields),
                f"invalid {section_name} balance")
    require(numeric[0]["id"] == "air" and not numeric[0]["solid"], "air must be non-solid ID 0")
    for group in (blocks, items, entities):
        require(all(isinstance(k, str) and re.fullmatch(r"[a-z][a-z0-9_]*", k) for k in group),
                "invalid stable ID")
    for block in blocks.values():
        require(integer(block["voxel_id"]), "voxel ID must be nonnegative integer")
        require(integer(block["min_pick_tier"]), "invalid mining tier")
        require(type(block["protected"]) is bool and type(block["solid"]) is bool, "block flags must be bool")
        require(block["drop"] is None or block["drop"] in items, "unknown block drop")
        require(not block["protected"] or block["drop"] is None, "protected block cannot drop")
    for item in items.values():
        require(integer(item["max_stack"], 1), "invalid stack size")
        require(item.get("category") in ITEM_CATEGORIES, "invalid item category")
        require(not ("places_block" in item and "places_entity" in item), "ambiguous placeable item")
        if "places_block" in item:
            target = numeric.get(item["places_block"])
            require(target and target["solid"] and not target["protected"], "invalid placeable voxel")
        if "places_entity" in item:
            require(item["places_entity"] in entities, "unknown placeable entity")
        if "pick_tier" in item:
            require(integer(item["pick_tier"], 1) and item["max_stack"] == 1, "invalid tool")
        if "hidden" in item:
            # Hidden items never appear in a recipe book: no recipe may produce them.
            require(item["hidden"] is True, "hidden must be true when present")
            require(not any(item["id"] in recipe.get("outputs", {}) for recipe in content["recipes"]), f"hidden item cannot be a recipe output: {item['id']}")
        if "tool_kind" in item:
            require(item["tool_kind"] == "axe" and item["max_stack"] == 1, "invalid specialized tool")
        weapon = item.get("weapon")
        if weapon is not None:
            require(isinstance(weapon, dict) and weapon.get("kind") == "melee"
                    and integer(weapon.get("damage"), 1)
                    and type(weapon.get("range")) in (int, float) and weapon["range"] > 0
                    and type(weapon.get("cooldown_seconds")) in (int, float) and weapon["cooldown_seconds"] > 0
                    and item["max_stack"] == 1, "invalid weapon")
    mount_types = {socket.get("type") for entity in entities.values()
                   for socket in entity.get("mount_sockets", [])
                   if isinstance(socket, dict) and isinstance(socket.get("type"), str)}
    for entity in entities.values():
        offsets = entity["occupied_offsets"]
        require(offsets and all(vector(v) for v in offsets + entity["support_offsets"]), "invalid entity offsets")
        require(len({tuple(v) for v in offsets}) == len(offsets), "duplicate occupied offset")
        require([0, 0, 0] in offsets, "entity anchor must be occupied")
        require(not ({tuple(v) for v in offsets} & {tuple(v) for v in entity["support_offsets"]}), "support overlaps entity")
        visual = entity.get("visual", {})
        require(isinstance(visual, dict) and re.fullmatch(r"[a-fA-F0-9]{6}", visual.get("color", "")), "invalid entity visual")
        parts = visual.get("parts", [])
        require(parts and all(isinstance(part, dict)
                              and numeric_vector(part.get("offset", []))
                              and numeric_vector(part.get("size", []), positive=True)
                              for part in parts), "invalid entity visual")
        require("linear" not in entity or (entity["linear"] is True and len(entity["occupied_offsets"]) == 1), "linear entities are 1x1")
        # Coaster rails: a slope rises exactly one cell over its single cell and
        # is never `linear` (its rotation is its rise direction); the loop tool
        # is a 1x1 floating piece (no support) with its own drag tool; a cart
        # carries a positive rail speed and mounts on rails only.
        require("slope" not in entity or (entity["slope"] == 1 and len(entity["occupied_offsets"]) == 1 and "linear" not in entity), "slope rails are 1x1, rise 1 and are not linear: " + entity["id"])
        require("coaster_tool" not in entity or (entity["coaster_tool"] in COASTER_TOOLS and len(entity["occupied_offsets"]) == 1 and (entity["support_offsets"] == [] or entity["id"] in GROUNDED_COASTER_TOOL_ENTITIES) and "linear" not in entity), "invalid coaster tool entity: " + entity["id"])
        require(("slope" in entity) + ("coaster_tool" in entity) <= 1, "an entity is a slope or a coaster tool, not both: " + entity["id"])
        cart = entity.get("cart")
        require(cart is None or (isinstance(cart, dict) and set(cart) == {"rail_speed"} and type(cart["rail_speed"]) in (int, float)
                                 and not isinstance(cart["rail_speed"], bool) and cart["rail_speed"] > 0
                                 and entity.get("mount", {}).get("allowed") == ["rail_mount"]), "invalid cart entity: " + entity["id"])
        station_type = entity.get("station_type")
        require(station_type is None or station_type == entity["id"] or station_type == "siege" and entity.get("siege") is not None, "invalid station type")
        socket_ids = set()
        for socket in entity.get("mount_sockets", []):
            require(isinstance(socket, dict) and re.fullmatch(r"[a-z][a-z0-9_]*", socket.get("id", ""))
                    and socket["id"] not in socket_ids and re.fullmatch(r"[a-z][a-z0-9_]*", socket.get("type", ""))
                    and numeric_vector(socket.get("offset", [])), "invalid mount socket")
            socket_ids.add(socket["id"])
        mount = entity.get("mount")
        if mount is not None:
            allowed = mount.get("allowed", []) if isinstance(mount, dict) else []
            require(isinstance(allowed, list) and allowed and all(isinstance(value, str) for value in allowed)
                    and len(set(allowed)) == len(allowed)
                    and all(value in ("ground", "wall") or value in mount_types for value in allowed), "invalid entity mount")
        siege = entity.get("siege")
        if siege is not None:
            require(isinstance(siege, dict) and siege.get("fire_mode") in ("direct", "ballistic", "dump")
                    and integer(siege.get("damage"), 1)
                    and type(siege.get("minimum_range")) in (int, float) and siege["minimum_range"] >= 0
                    and type(siege.get("maximum_range")) in (int, float) and siege["maximum_range"] > siege["minimum_range"]
                    and type(siege.get("cooldown_seconds")) in (int, float) and siege["cooldown_seconds"] > 0
                    and integer(siege.get("starting_ammo"), 1)
                    and siege.get("ammo_item") in items
                    and numeric_vector(siege.get("muzzle_offset", [])), "invalid siege definition")
            munitions = content.get("munitions", {})
            require(isinstance(siege.get("ammo_items"), list) and siege["ammo_items"]
                    and siege["ammo_item"] in siege["ammo_items"]
                    and all(a in items and a in munitions for a in siege["ammo_items"])
                    and integer(siege.get("capacity"), 1) and siege["capacity"] >= siege["starting_ammo"]
                    and type(siege.get("supply_radius")) in (int, float) and siege["supply_radius"] > 0, "invalid siege ammunition")
            if siege["fire_mode"] == "ballistic":
                require(type(siege.get("arc_height")) in (int, float) and siege["arc_height"] > 0,
                        "invalid siege arc")
            if siege["fire_mode"] == "dump":
                require(type(siege.get("rail_speed")) in (int, float) and siege["rail_speed"] > 0
                        and entity.get("mount", {}).get("allowed") == ["rail_mount"], "invalid rail weapon")
        if entity.get("container_slots") is not None:
            # Industry wave 1: warehouses and ore bins are chest-style containers
            # (same slot list, same modal) under their own station type.
            require(integer(entity["container_slots"], 1) and entity.get("station_type") in CONTAINER_STATION_TYPES, "invalid container entity")
        defense = entity.get("defense")
        if defense is not None:
            navigation = entity.get("navigation", {})
            require(isinstance(defense, dict) and integer(defense.get("max_integrity"), 1)
                    and defense.get("repair_item") in items and integer(defense.get("repair_amount"), 1)
                    and isinstance(navigation, dict) and navigation.get("integrity") == defense["max_integrity"]
                    and isinstance(navigation.get("material_tags"), list) and navigation["material_tags"]
                    and all(isinstance(tag, str) and tag for tag in navigation["material_tags"]), "invalid defense definition")
        if entity["id"] in ATTRIBUTE_ENTITIES or "attributes" in entity:
            validate_attributes(entity)
    for munition_id, munition in content.get("munitions", {}).items():
        require(munition_id in items and munition.get("effect") in ("impact", "fire")
                and integer(munition.get("damage"), 0)
                and type(munition.get("splash_radius")) in (int, float) and munition["splash_radius"] >= 0, "invalid munition")
        if munition["effect"] == "fire":
            require(all(type(munition.get(k)) in (int, float) and munition[k] > 0 for k in ("burn_seconds", "fuel_seconds", "spread_chance", "fire_damage_per_second"))
                    and munition["spread_chance"] <= 1, "invalid fire munition")
    for recipe in content["recipes"]:
        require(recipe["station"] == "hand" or recipe["station"] in entities, "unknown recipe station")
        require(type(recipe["duration_seconds"]) in (int, float) and recipe["duration_seconds"] >= 0, "invalid recipe time")
        require("recipe_book_order" not in recipe or integer(recipe["recipe_book_order"]), "invalid recipe book order")
        require(recipe["station"] not in ("workbench", "coastercraft_shop") or sum(recipe["inputs"].values()) <= 9, "3x3 station recipe must fit the grid: " + recipe["id"])
        for field in ("inputs", "outputs"):
            require(recipe[field], "recipe cannot have empty inputs or outputs")
            require(all(i in items and integer(n, 1) for i, n in recipe[field].items()), "invalid recipe item/count")
    inv = content["inventory"]
    require(integer(inv["slots"], 1) and inv["hotbar_slots"] == 9 and inv["slots"] >= 9, "invalid inventory capacity")

    require(vector(world["min_cell"]) and vector(world["size"], positive=True), "invalid world bounds")
    require(world["chunk_size"] == 16, "fixture chunk size must be 16")
    require(all(v % 16 == 0 for v in world["min_cell"] + world["size"]), "bounds must align to chunks")
    require(world["min_cell"][1] < world["sea_level"] < world["min_cell"][1] + world["size"][1], "world needs depth above and below sea level")
    require(len(world["spawn_feet"]) == 3 and in_bounds(world["spawn_feet"], world), "spawn outside bounds")
    require(world["interaction_reach"] > 0 and world["day_length_seconds"] > 0, "invalid world timing/reach")
    require(world["generator_version"] in ("flat_fixture_1", "terrain_p1_1"), "unsupported generator version")
    if world["generator_version"] == "terrain_p1_1":
        terrain = world.get("terrain", {})
        require(type(terrain.get("min_surface_y")) is int and type(terrain.get("max_surface_y")) is int and terrain["min_surface_y"] < terrain["max_surface_y"], "invalid terrain height range")
        require(world["min_cell"][1] < terrain["min_surface_y"] and terrain["max_surface_y"] + 7 < world["min_cell"][1] + world["size"][1], "terrain lacks vertical headroom")
        clearing_center = terrain.get("safe_clearing_center", [])
        clearing_half_size = terrain.get("safe_clearing_half_size", [])
        require(isinstance(clearing_center, list) and len(clearing_center) == 2 and all(type(v) is int for v in clearing_center), "invalid safe clearing")
        require(isinstance(clearing_half_size, list) and len(clearing_half_size) == 2 and all(type(v) is int and v > 0 for v in clearing_half_size), "invalid safe clearing")
        require(integer(terrain.get("safe_clearing_blend"), 1) and integer(terrain.get("tree_grid_size"), 5), "invalid terrain spacing")
        require(integer(terrain.get("tree_chance_percent"), 0) and terrain["tree_chance_percent"] <= 100, "invalid tree chance")
        validate_ores(terrain.get("ores"), blocks, world)
        landmark_ids = set()
        for landmark in world.get("landmarks", []):
            require(landmark.get("id") and landmark["id"] not in landmark_ids, "invalid or duplicate landmark")
            landmark_ids.add(landmark["id"])
            require(vector(landmark.get("cell", [])) and in_bounds(landmark["cell"], world), "landmark outside bounds")
            require(integer(landmark.get("safe_radius"), 1), "invalid landmark radius")
    cursor = world["min_cell"][1]
    for layer in world["layers"]:
        require(layer["min_y"] == cursor and layer["max_y_exclusive"] > cursor, "layers gap or overlap")
        require(layer["block"] in numeric, "unknown layer block")
        cursor = layer["max_y_exclusive"]
    require(cursor == world["min_cell"][1] + world["size"][1], "layers do not fill height")
    require(numeric[world["layers"][0]["block"]]["protected"], "bottom must be protected")
    for patch in world["patches"]:
        require(patch["block"] in numeric and vector(patch["min_cell"]) and vector(patch["size"], True), "invalid resource patch")
        last = [a+b-1 for a,b in zip(patch["min_cell"], patch["size"])]
        require(in_bounds(patch["min_cell"], world) and in_bounds(last, world), "patch outside bounds")
    missing = set(content["progression_goals"]) - reachable_items(content, world)
    require(not missing, f"unreachable progression goals: {sorted(missing)}")

    actions = index(keys["actions"], "id", "actions")
    defaults = {"move_forward": "E", "move_backward": "D", "strafe_left": "S", "strafe_right": "F",
                "sprint": "A", "crouch": "Z", "jump": "Space", "interact": "Shift", "inventory": "Tab", "build": "B", "rotate_build_clockwise": "W", "rotate_build_counterclockwise": "R", "pause": "Escape",
                "reload": "G", "primary": "MouseLeft", "secondary": "MouseRight", "capture_screenshot": "F2"}
    defaults.update({f"hotbar_{i}": str(i) for i in range(1, 10)})
    require(keys["escape_recovery"] is True and keys["keyboard_mode"] == "physical_qwerty", "unsafe input recovery/default mode")
    for action, key in defaults.items():
        require(action in actions and actions[action]["key"] == key, f"default binding changed: {action}")
    rows = keys["actions"]
    for i, a in enumerate(rows):
        require(a["context"] in ("system", "gameplay"), "unknown input context")
        for b in rows[i+1:]:
            require(a["key"] != b["key"], f"overlapping active key: {a['key']}")
    index(placements["cases"], "id", "placement cases")
    for case in placements["cases"]:
        require(vector(case["anchor"]), "invalid placement anchor")
        require(case["offsets"], "empty placement footprint")
        for field in ("offsets", "occupied", "unloaded", "player_cells", "required_support"):
            require(all(vector(c) for c in case[field]), "invalid placement coordinate")
        require(len({tuple(c) for c in case["offsets"]}) == len(case["offsets"]), "duplicate placement offset")
        actual = placement_result(case, world)
        require(actual == case["expected"], f"placement {case['id']}: expected {case['expected']}, got {actual}")


def validate_repo(root=ROOT):
    bundle = load_bundle(root)
    validate_bundle(bundle)
    runtime_content = read_json(root / "game" / "data" / "content.json")
    require(runtime_content == bundle["content"],
            "runtime content registry differs from canonical contracts/content.json")
    runtime_world = read_json(root / "game" / "data" / "world.json")
    require(runtime_world == bundle["world"],
            "runtime world configuration differs from canonical contracts/world.json")
    runtime_expo = read_json(root / "game" / "data" / "development_expo.json")
    require(runtime_expo == bundle["development_expo"],
            "runtime Development Expo manifest differs from canonical contracts/development_expo.json")
    navigation = read_json(root / "contracts" / "navigation_spike.json")
    runtime_navigation = read_json(root / "game" / "data" / "navigation_spike.json")
    require(runtime_navigation == navigation,
            "runtime navigation spike differs from canonical contracts/navigation_spike.json")
    require(navigation.get("schema_version") == 1 and navigation.get("status") == "p2_spike_only",
            "invalid navigation spike header")
    agent = navigation.get("agent", {})
    require(agent.get("size_cells") == [1, 2, 1] and agent.get("max_step_up") == 1
            and agent.get("max_drop_down") == 1 and agent.get("cardinal_movement_only") is True,
            "invalid navigation spike agent")
    materials = index(navigation.get("materials", []), "id", "navigation materials")
    require(set(materials) >= {"dirt", "planks", "stone", "castle_stone", "bedrock"},
            "missing navigation material")
    require(all(integer(row.get("integrity"), 0) and isinstance(row.get("tags"), list)
                and row["tags"] and type(row.get("protected")) is bool for row in materials.values()),
            "invalid navigation material")
    capabilities = index(navigation.get("capabilities", []), "id", "navigation capabilities")
    require(set(capabilities) == {"basic_raider", "siege_breaker_candidate"},
            "invalid navigation capability set")
    for capability in capabilities.values():
        require(capability.get("damage_per_hit") and all(isinstance(tag, str) and integer(value, 1)
                for tag, value in capability["damage_per_hit"].items()), "invalid navigation damage capability")
    benchmark = navigation.get("benchmark", {})
    require(benchmark.get("region_size_cells") == [13, 5, 13]
            and integer(benchmark.get("iterations"), 1)
            and set(benchmark.get("scenarios", [])) == NAVIGATION_SCENARIOS,
            "invalid navigation benchmark")
    versions = read_json(root / "tools/versions.json")
    require(versions["edition"] == "module" and versions["precision"] == "single", "unexpected engine edition/precision")
    assets = index(versions["assets"], "name", "release assets")
    require(set(assets) == {"godot.windows.editor.x86_64.exe.zip", "godot.windows.template_release.x86_64.exe.zip"}, "missing paired Windows assets")
    for asset in assets.values():
        require(re.fullmatch(r"[a-f0-9]{64}", asset["sha256"]), "invalid archive digest")
        require(integer(asset["size_bytes"], 1), "invalid archive size")
        require(asset["url"].startswith(versions["release_url"].replace("/tag/", "/download/") + "/"), "asset release mismatch")
    report = root / "docs/research/ORIGINAL_REPORT.md"
    require(hashlib.sha256(report.read_bytes()).hexdigest() == REPORT_SHA, "original report bytes changed")
    paths = [root / "README.md", root / "AGENTS.md"] + list((root / "docs").rglob("*.md")) + list((root / "tools").glob("*.md"))
    links = 0
    for path in paths:
        if path == report:
            continue  # Historical report retains its original external citation syntax.
        text = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8"), flags=re.S)
        for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text):
            if "://" in target or target.startswith(("#", "mailto:")):
                continue
            dest = (path.parent / target.split("#")[0]).resolve()
            require(dest.is_relative_to(root.resolve()), f"link escapes repo: {path.name}: {target}")
            require(dest.exists(), f"broken local link: {path.name}: {target}")
            links += 1
    return {"blocks": len(bundle["content"]["blocks"]), "items": len(bundle["content"]["items"]),
            "recipes": len(bundle["content"]["recipes"]), "placement_cases": len(bundle["placement_cases"]["cases"]),
            "navigation_scenarios": len(benchmark["scenarios"]), "local_links": links}


if __name__ == "__main__":
    try:
        print("PASS: foundation static validation", json.dumps(validate_repo(), sort_keys=True))
        runtime_gate = read_json(ROOT / "tools/versions.json")["windows_runtime_gate"]
        print(f"Recorded runtime, Windows export and gameplay gate: {runtime_gate}")
    except (ValidationError, KeyError, TypeError, OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
