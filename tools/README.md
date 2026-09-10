# Foundation tools

Python 3.11+ standard library only; no pip install or game engine required for static checks.

```shell
python tools/validate_foundation.py
python -m unittest discover -s tests -v
python tools/verify_toolchain.py --archive-dir /path/to/already-downloaded-archives
```

The validator reads canonical JSON, verifies references/defaults/bounds/placement examples and proves coarse crafting capability reachability. It also checks original-report bytes and local Markdown link targets. It does not validate anchors, external URL availability, runtime semantics, spatial resource accessibility, resource quantities, Godot collision, save behavior or Windows export.

The archive verifier checks both recorded archives independently, using publisher-reported size and SHA-256 from `versions.json`. A missing/corrupt file returns nonzero. It never downloads, installs, changes PATH or updates the manifest. Real engine archive verification remains NOT RUN until the local agent supplies them. The verifier's automated tests use small synthetic bytes.

`contracts/` is the source of proposed data, not a compiled game asset bundle. The runtime content loader must deliberately read/convert it. Keep stable IDs and update tests/docs together when changing fixtures. There is no tested run/export script until the local agent creates the Godot project and actual export preset.
