# Evidence — P1B first castle kit — 2026-09-12

STATUS: PARTIAL — implementation, matching export and automated gates pass; owner ultrawide building/collision acceptance remains pending.

DONE:

- Added stable workbench items/entities for stone stair, wall-walk slab, parapet merlon, 2×2 tower platform and open gate frame; existing castle stone remains the full wall voxel.
- Added data-driven multi-part visuals and matching collision, explicit occupied/support offsets and saved quarter-turn orientation.
- Added non-mutating green/red placement previews and a persistent, conflict-checked Rotate Build Preview action on physical X.
- Added a typed `light_siege` center mount socket to the tower platform without implementing a weapon.
- Preserved station interaction: only definitions with `station_type` open crafting/processing UI.
- Preserved exact ESDF defaults, VoxelTerrain/VoxelStreamSQLite, Compatibility rendering and the pinned engine/template pair.

EXPECT:

The workbench recipe book exposes the five structural pieces. Selecting one shows a validity-colored preview; X rotates the complete piece; right click commits only after full support/occupancy/player checks. Structures collide with the player, dismantle as one entity, refund one item and return exactly once after Save/Continue. The gate opening remains passable and the platform requires all four cells below it.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T42 | Stable recipes and future mount contract | All five item/entity/recipe IDs loaded; platform socket was `center_mount/light_siege` | PASS | `artifacts/castle-phase1.log`, `artifacts/export-castle-final-phase1.log` |
| T43 | Non-mutating preview and rotated full-footprint validation | Preview left reservation count unchanged; unsupported platform rejected; 90-degree 2×2 cells rotated and committed atomically | PASS | same logs |
| T44 | Preview/rotation/placement/collision usable in game | Five pieces placed with requested rotation and visual/collision nodes; owner physical preview/collision review pending | PARTIAL | `artifacts/castle-phase1.log`, source automation, owner test below |
| T45 | Coherent save/restart/Continue and whole dismantle | Separate processes restored five unique records/visuals with exact rotations; gate frame released once and refunded one | PASS | `artifacts/castle-phase2.log`, `artifacts/export-castle-final-phase2.log` |
| T46 | Readable/useful first kit | 1280×720 Windows-rendered capture passed and was visually inspected; owner 3440×1440 building-feel review pending | PARTIAL | `artifacts/castle-kit-visualdata/p1-castle-kit.png`, `artifacts/castle-visual.log` |
| F2 regression | Progression, recipes, station priority/jobs and Continue unchanged | T19–T22, T31/T32, checkpoint and clean-process Continue all passed with 24 keybind rows and expanded recipe list | PASS | `artifacts/regression-f2-gate.log`, `artifacts/regression-f2-continue.log` |
| F5 regression | Input/graphics/crafting split unchanged | Phase1/phase2 passed, including B persistence, graphics and crafting staging | PASS | `artifacts/regression-f5-phase1.log`, `artifacts/regression-f5-phase2.log` |
| P1A regression | Generator/routing/exploration/save identity unchanged | T37–T40 phase1/phase2 passed | PASS | `artifacts/regression-p1-phase1.log`, `artifacts/regression-p1-phase2.log` |
| Static | Contract equality, structure validation and rejection tests | Validator PASS; 24/24 unit tests PASS | PASS | commands below |
| Windows export | Matching release template and editor-closed runtime | Export PASS; zero editor/game processes before EXE phase1; separate EXE phase2 restored/dismantled correctly | PASS | `builds/CraftAndDefend/build_manifest.json`, export logs above |

Commands:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
& .\builds\CraftAndDefend\CraftAndDefend.exe --headless --log-file <log> -- --f0-data-root=<isolated-root> --castle-kit-automation=phase1
& .\builds\CraftAndDefend\CraftAndDefend.exe --headless --log-file <log> -- --f0-data-root=<same-root> --castle-kit-automation=phase2
```

LIMITATIONS/FAILURES:

- Owner 3440×1440 placement-preview, stair walking, slab/platform collision, gate passage and construction usefulness remain unverified.
- The first phase-one fixture initially failed because rotated test supports were supplied at unrotated cells and a gate test overlapped the preserved starter tree. The implementation correctly rejected both. The fixture was corrected to the rotated support coordinates and a clear gate location; the complete test then passed in editor and export.
- A dummy/headless visual run waited indefinitely for `frame_post_draw`; it was stopped and rerun through the Windows OpenGL renderer, which passed and produced the inspected image.
- A direct headless editor start without explicit repository-local logging reproduced the known custom-build crash while opening its default user log. Running outside the restricted filesystem with explicit logs passed.
- Prototype geometry uses box parts and prototype recipe quantities. The slab owns one logical cell even though it is half height. The gate has no moving door/portcullis; the platform socket has no weapon. No collapse, durability, partial salvage, pathfinding or combat is implemented.

NEXT:

Tony launches `D:\CODEX\Craft_and_Defend\worktrees\p1-castle-kit\START_GAME.cmd`, uses an expendable slot, crafts the five pieces at a workbench, validates green/red preview and X rotation, builds and walks a small wall/tower/gate arrangement, dismantles one piece, saves/exits and Continues. Address findings before P2 navigation work or integration.

GIT/REPRODUCIBILITY:

- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`; clean `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\p1-castle-kit`; `feature/p1-castle-kit`.
- Implementation/export source: `4e33cfa31187f02d3f75c6a20f4d8c7a93ddf489`; game tree `37d063aa8797fb3fa23102b2430d88f8060bde1e`; accepted terrain base `9a38a3321c23c0816dabec74056c1017a6129d28`.
- Platform: Windows 11 Pro `10.0.26200`; AMD Ryzen 9 7900X3D; 64 GB RAM; NVIDIA GeForce RTX 5090 driver 610.88; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine/Voxel Tools: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; extracted editor SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Export EXE SHA-256: `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256: `7ded311bf57f0ae2b9cbdb751f3a43275350b8c1b9089ec645494b8bb776ead3`; built UTC `2026-09-12T11:33:15.7264440Z`.
- Seed/world/content: `41026`; half-open 64×32×128; `terrain_p1_1`; content `foundation-1` with additive stable P1B IDs.
- Normal saves: `%APPDATA%\CraftAndDefend`; automation used ignored isolated roots under `artifacts`.
- Clean-process restart: PASS. Editor-closed exported runtime: PASS. No merge, push or release performed.
