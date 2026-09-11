# Foundation tools

Python 3.11+ standard library only; no pip install or game engine required for static checks.

```shell
python tools/validate_foundation.py
python -m unittest discover -s tests -v
python tools/verify_toolchain.py --archive-dir /path/to/already-downloaded-archives
```

The validator reads canonical JSON, verifies references/defaults/bounds/placement examples and proves coarse crafting capability reachability. It also checks original-report bytes and local Markdown link targets. It does not validate anchors, external URL availability, runtime semantics, spatial resource accessibility, resource quantities, Godot collision, save behavior or Windows export.

The archive verifier checks both recorded archives independently, using publisher-reported size and SHA-256 from `versions.json`. A missing/corrupt file returns nonzero. It never downloads, installs, changes PATH or updates the manifest. The verifier's automated tests use small synthetic bytes.

`contracts/` is the source of proposed data, not a compiled game asset bundle. The runtime content loader deliberately reads/converts it. Keep stable IDs and update tests/docs together when changing fixtures.

`build_windows_f0.ps1` creates the verified Windows export and an ignored `build_manifest.json` containing the tracked `game` tree identity, source commit, engine version and artifact hashes. `start_game.ps1` is the provenance guard used by `START_GAME.cmd`: in a Git checkout it rebuilds when the package is missing, unversioned, the tracked game tree differs, or game files are dirty. Use `-PrepareOnly` to validate/prepare the package without launching it.
