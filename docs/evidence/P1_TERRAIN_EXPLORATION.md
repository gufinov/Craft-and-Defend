# Evidence — P1 terrain and exploration — 2026-09-12

STATUS: PARTIAL — implementation, matching export and automated/runtime gates pass; owner 3440×1440 terrain/pacing acceptance remains pending.

DONE:

- Added versioned deterministic `terrain_p1_1` generation using immutable FastNoiseLite settings inside the Voxel Tools generator callback.
- Added a flat home clearing, blended surrounding height variation, procedural trees/leaves, deterministic ore clusters and the preserved Foundation starter resources.
- Added an updating home distance/compass cue.
- Persisted generator version/seed and retained an explicit `flat_fixture_1` path for metadata-free pre-P1 saves.
- Added leaf voxel ID 10 without reordering IDs 0–9.
- Preserved VoxelTerrain, VoxelMesherBlocky, VoxelStreamSQLite, Compatibility renderer and the pinned custom engine/template.

EXPECT:

New saves reproduce the P1 landscape from seed 41026 while SQLite continues to store edits. Old saves remain visually unchanged because missing generation metadata selects the old flat generator. The player can leave the safe clearing, locate distributed resources, return using the HUD cue, save an edit and Continue in a new process.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T37 | Versioned routing and exact seed | New snapshot selected `terrain_p1_1/41026`; missing metadata selected `flat_fixture_1`; unknown ID returned `UNSUPPORTED_GENERATOR_VERSION` | PASS | `artifacts/p1-export/phase1.log` |
| T38 | Reproducible varied terrain/resources and safe clearing | Repeated generator matched; sampled surface -4..2; 16 tree roots; 702 coal and 237 iron samples; clearing and fixed fixtures passed | PASS | same log |
| T39 | Exploration/return cue | At the test point HUD showed `HOME 45 m SW`; at spawn it showed `HOME CLEARING` | PASS | same log |
| T40 | Coherent save/full restart/Continue | Terrain edit restored as air; player restored within 0.05 units; generator version/seed exactly restored | PASS | `artifacts/p1-export/phase1.log`, `phase2.log` |
| T41 | Readable landscape and acceptable exploration pacing | Exported 1280×720 landscape rendered and was visually inspected; owner 3440×1440/pacing review not yet run | PARTIAL | `artifacts/p1-export-visual/p1-terrain.png`, `visual.log` |
| F0 regression | Menu, movement/collision, break/place/reject, rebind, unload/reload and Continue | Export phase1/phase2 all assertions PASS | PASS | `artifacts/export-regression/f0/phase1.log`, `phase2.log` |
| F1 regression | Controls, UI isolation, focus/display, boundaries and atomic rejection | Editor phase1/phase2 PASS | PASS | `artifacts/regression/f1/phase1.log`, `phase2.log` |
| F2 regression | Empty-inventory progression, crafting, stations and Continue | Editor and exported gate/Continue PASS | PASS | `artifacts/export-regression/f2/gate.log`, `continue.log` |
| F3 regression | Slot isolation, interruption recovery and mid-job persistence | Editor phase1/phase2 PASS | PASS | `artifacts/regression/f3/phase1.log`, `phase2.log` |
| F4 regression | Clock/settings, capture and measured fixed scenario | Graphical phase1/phase2 PASS; average 19.536 ms, p95 20.271 ms, 100 edits average 0.00263 ms, save 170 ms/23,408 bytes | PASS | `artifacts/regression/f4-gui/phase1.log`, `phase2.log` |
| F5 regression | Graphics defaults and three-panel crafting interactions | Editor phase1/phase2 PASS | PASS | `artifacts/regression/f5/phase1.log`, `phase2.log` |
| Static | Canonical/runtime contracts and rejection tests | Validator PASS; 22/22 unittests PASS | PASS | commands below |
| Windows export | Matching custom release template; editor closed runtime | Export PASS; P1/F0/F2 tests and P1 graphical capture ran with zero editor processes | PASS | `builds/CraftAndDefend/build_manifest.json` |

Commands:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
& .\builds\CraftAndDefend\CraftAndDefend.exe --headless --log-file <log> -- --f0-data-root=<isolated-root> --p1-automation=phase1
& .\builds\CraftAndDefend\CraftAndDefend.exe --headless --log-file <log> -- --f0-data-root=<same-root> --p1-automation=phase2
& .\builds\CraftAndDefend\CraftAndDefend.exe --log-file <log> -- --f0-data-root=<isolated-root> --p1-automation=visual
```

LIMITATIONS/FAILURES:

- Owner ultrawide exploration, perceived terrain quality, tree/ore density and gather/return pacing are not automatable and remain pending.
- The finite terrain is a bounded first P1 slice: no water, caves, biome system or procedural expansion.
- Castle structural pieces were not guessed while tower-cap footprint, positional recipe, rotation/snapping and collapse decisions remain open.
- The direct custom editor can crash while opening its default Godot user log in this restricted session; explicit `--log-file` is the proven test route.
- Godot emitted a nonblocking Windows root-certificate warning; the tested application makes no network request.

NEXT:

Tony starts a new expendable slot from `D:\CODEX\Craft_and_Defend\worktrees\p1-terrain\START_GAME.cmd`, explores, gathers, returns, edits, saves and Continues at 3440×1440. Address owner findings before the P1 castle-structure slice or promotion.

GIT/REPRODUCIBILITY:

- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`; clean `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\p1-terrain`; `feature/p1-terrain-exploration`.
- Implementation/export source: `a6a25e8ed65956257a061b2b748d66367e3617ce`; game tree `b8a95f1168f9a015a4ae2ef169537ef7abb1e4c5`; F5 base `da1b6ee0e4d2161db11baf2c4aed5ff6631272fe`.
- Platform: Windows 11 Pro `10.0.26200`; AMD Ryzen 9 7900X3D; 64 GB RAM; NVIDIA GeForce RTX 5090 driver 610.88; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine/Voxel Tools: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; extracted editor SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Export EXE SHA-256: `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256: `cc18219812e84773973f80d73fb535faedfb246398bb8cc1113d2067c444d48f`; built UTC `2026-09-11T17:47:29.6094196Z`.
- Seed/world/content: `41026`; half-open 64×32×128; `terrain_p1_1`; content `foundation-1`.
- Normal saves: `%APPDATA%\CraftAndDefend`; automation used ignored isolated roots below `artifacts`.
- Clean-process restart: PASS. Editor-closed exported runtime: PASS. No merge, push or release performed.
