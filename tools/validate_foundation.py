"""Validate design fixtures and repository integrity, not the game runtime."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT_SHA = "f238c37f3f9509b2a152e632503b7a4e16ab8fd4377dcc32122717e30c13cebd"
ITEM_CATEGORIES = {"resource", "building", "tool", "station", "food"}
NAVIGATION_SCENARIOS = {"corridor_detour", "trench", "two_step_stair", "bridge_removal", "two_cell_tunnel", "capability_blocked_wall"}


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
            for name in ("content", "world", "keybinds", "placement_cases")}


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


def validate_bundle(bundle):
    for name, data in bundle.items():
        require(data["schema_version"] == 1, f"{name}: unsupported schema")
    content, world, keys, placements = (bundle[n] for n in
        ("content", "world", "keybinds", "placement_cases"))
    blocks = index(content["blocks"], "id", "blocks")
    numeric = index(content["blocks"], "voxel_id", "blocks")
    items = index(content["items"], "id", "items")
    entities = index(content["entities"], "id", "entities")
    index(content["recipes"], "id", "recipes")
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
        station_type = entity.get("station_type")
        require(station_type is None or station_type == entity["id"], "invalid station type")
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
                    and all(value == "ground" or value in mount_types for value in allowed), "invalid entity mount")
        siege = entity.get("siege")
        if siege is not None:
            require(isinstance(siege, dict) and siege.get("fire_mode") in ("direct", "ballistic")
                    and integer(siege.get("damage"), 1)
                    and type(siege.get("minimum_range")) in (int, float) and siege["minimum_range"] >= 0
                    and type(siege.get("maximum_range")) in (int, float) and siege["maximum_range"] > siege["minimum_range"]
                    and type(siege.get("cooldown_seconds")) in (int, float) and siege["cooldown_seconds"] > 0
                    and integer(siege.get("starting_ammo"), 1)
                    and siege.get("ammo_item") in items
                    and numeric_vector(siege.get("muzzle_offset", [])), "invalid siege definition")
            if siege["fire_mode"] == "ballistic":
                require(type(siege.get("arc_height")) in (int, float) and siege["arc_height"] > 0,
                        "invalid siege arc")
    for recipe in content["recipes"]:
        require(recipe["station"] == "hand" or recipe["station"] in entities, "unknown recipe station")
        require(type(recipe["duration_seconds"]) in (int, float) and recipe["duration_seconds"] >= 0, "invalid recipe time")
        require("recipe_book_order" not in recipe or integer(recipe["recipe_book_order"]), "invalid recipe book order")
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
        for key in ("coal_cluster_per_thousand", "iron_cluster_per_thousand"):
            require(integer(terrain.get(key), 0) and terrain[key] <= 1000, "invalid ore frequency")
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
                "sprint": "A", "crouch": "Z", "jump": "Space", "interact": "Shift", "inventory": "Tab", "build": "B", "rotate_build": "X", "pause": "Escape",
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
