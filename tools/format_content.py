"""Rewrites contracts/content.json and its game/data mirror record-per-line.

Top-level scalars and short dictionaries stay on one line; every record in a
list (blocks, items, entities, recipes) and every entry of a keyed table
(balance, munitions) gets its own line so diffs read per record. Run after any
hand edit; validate_foundation.py checks the two files parse identically.
"""
from __future__ import annotations

import io
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PATHS = [ROOT / "contracts" / "content.json", ROOT / "game" / "data" / "content.json"]


def _compact(value) -> str:
    return json.dumps(value, separators=(", ", ": "))


def format_content(content: dict) -> str:
    lines = ["{"]
    keys = list(content.keys())
    for index, key in enumerate(keys):
        value = content[key]
        comma = "," if index < len(keys) - 1 else ""
        if isinstance(value, list) and value and all(isinstance(item, dict) for item in value):
            lines.append("  %s: [" % json.dumps(key))
            for record_index, record in enumerate(value):
                record_comma = "," if record_index < len(value) - 1 else ""
                lines.append("    %s%s" % (_compact(record), record_comma))
            lines.append("  ]%s" % comma)
        elif isinstance(value, dict) and value and all(isinstance(item, dict) for item in value.values()):
            lines.append("  %s: {" % json.dumps(key))
            entries = list(value.items())
            for entry_index, (entry_key, entry) in enumerate(entries):
                entry_comma = "," if entry_index < len(entries) - 1 else ""
                lines.append("    %s: %s%s" % (json.dumps(entry_key), _compact(entry), entry_comma))
            lines.append("  }%s" % comma)
        else:
            lines.append("  %s: %s%s" % (json.dumps(key), _compact(value), comma))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    source = PATHS[0]
    content = json.loads(io.open(source, encoding="utf-8").read())
    text = format_content(content)
    for path in PATHS:
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
        print("wrote", path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
