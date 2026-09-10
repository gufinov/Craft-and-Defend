"""Validate design fixtures and repository integrity, not the game runtime."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT_SHA = "f238c37f3f9509b2a152e632503b7a4e16ab8fd4377dcc32122717e30c13cebd"


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
        require(not ("places_block" in item and "places_entity" in item), "ambiguous placeable item")
        if "places_block" in item:
            target = numeric.get(item["places_block"])
            require(target and target["solid"] and not target["protected"], "invalid placeable voxel")
        if "places_entity" in item:
            require(item["places_entity"] in entities, "unknown placeable entity")
        if "pick_tier" in item:
            require(integer(item["pick_tier"], 1) and item["max_stack"] == 1, "invalid tool")
    for entity in entities.values():
        offsets = entity["occupied_offsets"]
        require(offsets and all(vector(v) for v in offsets + entity["support_offsets"]), "invalid entity offsets")
        require(len({tuple(v) for v in offsets}) == len(offsets), "duplicate occupied offset")
        require([0, 0, 0] in offsets, "entity anchor must be occupied")
        require(not ({tuple(v) for v in offsets} & {tuple(v) for v in entity["support_offsets"]}), "support overlaps entity")
    for recipe in content["recipes"]:
        require(recipe["station"] == "hand" or recipe["station"] in entities, "unknown recipe station")
        require(type(recipe["duration_seconds"]) in (int, float) and recipe["duration_seconds"] >= 0, "invalid recipe time")
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
                "sprint": "A", "crouch": "Z", "jump": "Space", "interact": "Shift", "inventory": "Tab", "pause": "Escape",
                "reload": "G", "primary": "MouseLeft", "secondary": "MouseRight"}
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
            "recipes": len(bundle["content"]["recipes"]), "placement_cases": len(bundle["placement_cases"]["cases"]), "local_links": links}


if __name__ == "__main__":
    try:
        print("PASS: foundation static validation", json.dumps(validate_repo(), sort_keys=True))
        runtime_gate = read_json(ROOT / "tools/versions.json")["windows_runtime_gate"]
        print(f"Recorded runtime, Windows export and gameplay gate: {runtime_gate}")
    except (ValidationError, KeyError, TypeError, OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
