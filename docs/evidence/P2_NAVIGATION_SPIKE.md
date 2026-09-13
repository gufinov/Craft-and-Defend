# Evidence — P2 bounded navigation risk spike — 2026-09-13

STATUS: PASS — automated and exported-runtime spike gates; owner review pending

DONE:

- Compared the pinned experimental `VoxelAStarGrid3D` with a project-owned bounded snapshot/grid planner under the same 13×5×13 terrain fixture.
- Exercised one 1×2-cell cardinal agent against corridor detour, trench, placed stair, two-height tunnel, bridge removal and capability-blocked walls.
- Added exact voxel cell-change events and one-cell snapshot refresh without making UI or navigation code authoritative for world mutation.
- Proved a basic raider returns an explicit plank attack, destroys the real two-cell diagnostic wall after eight hits, then receives a valid route; it refuses castle stone while the siege candidate can target it.
- Added `VIEW_NAVIGATION_SPIKE.cmd` for a one-click Windows-rendered evidence path.

EXPECT:

Prototype P3 with one physical attacker using bounded local snapshots plus event-driven invalidation. Keep the pinned helper as a terrain-only performance benchmark. Do not scale to groups or claim production combat until entity-change invalidation, physics movement and actual attack transactions pass their own gates.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T51 | Pinned API and 1×2 local contract are explicit | All six inspected v1.6 API methods present; cardinal 1×2 agent with one-cell step/drop loaded from mirrored contract | PASS | `artifacts/p2-export-final.console.log`, `contracts/navigation_spike.json` |
| T52 | One agent detours; placed entity and clearance are represented | Local corridor route 17 cells / 0 stuck; pinned corridor route 10 cells; local stair route reaches Y=1 while terrain-only pinned route remains Y=0; two-cell tunnel passes | PASS | `artifacts/p2-export-final/p2_navigation_results.json` |
| T53 | Unsafe trench/headroom and removed bridge refuse routes | Both planners returned `NO_ROUTE`; exact bridge cell invalidated; one-cell local refresh 7 µs | PASS | `artifacts/p2-export-final.console.log` |
| T54 | Capability decides attack versus no route | Unarmed `NO_ROUTE`; basic raider 4 hits per plank cell / 8 total actual diagnostic hits; basic refuses castle stone; siege candidate estimates 18 hits | PASS | `artifacts/p2-export-final/p2_navigation_results.json` |
| T55 | Bounded timing, visited and scale evidence recorded | Local corridor 981 µs median / 1321 µs p95 / 77 visited; pinned 51 / 57 µs / 85 visited; 845-cell snapshot 6837 µs and explicitly estimated 81,120 bytes; bridge no-route local 945 µs vs pinned 76 µs median | PASS | `artifacts/p2-export-final/p2_navigation_results.json` |
| T56 | Rendered diagnostic is legible and truthful | 1280×720 export image shows wall, cyan detour, green start, red goal and yellow 1×2 probe; route 17 cells / 0 stuck; labels state diagnostic only | PASS | `artifacts/p2-export-final-visual/p2-navigation-spike.png`, `artifacts/p2-export-final-visual.console.log` |
| Static | Contracts/source/docs remain coherent | Validator PASS; 28/28 Python tests PASS; `git diff --check` PASS | PASS | terminal run 2026-09-13 |
| Export regression | Existing accepted slices remain intact | Final exported F0, F1, F2, F5 and castle phase1/phase2 runs all exited 0 and reported PASS from isolated roots | PASS | `artifacts/p2-final-regress-*.console.log` |

LIMITATIONS/FAILURES:

- `VoxelAStarGrid3D` is markedly faster in this small terrain-only fixture, but it does not observe placed non-voxel castle entities and cannot express capability-specific obstruction attacks.
- Local full snapshot capture ranged by scenario and must not be performed indiscriminately in critical frames; the final corridor capture was 6837 µs. Incremental single-cell refresh was 7 µs in the final bridge case.
- The 81,120-byte figure is deliberately labelled `estimated_snapshot_bytes`; it is not a heap allocation measurement. `Performance.MEMORY_STATIC` deltas were zero at this scale and are not used as proof of zero cost.
- The visual probe is moved along logical waypoints for evidence. It is not a CharacterBody enemy, physics-following result, raid, combat loop or army-scale proof.
- Voxel edits emit exact change events. Placed-entity placement/dismantle does not yet emit an equivalent navigation invalidation signal; P3 must add it before live use.
- Initial iterations exposed and preserved: GDScript diagnostic type errors, a trench fixture that allowed an unintended edge detour, and local query-copy overhead. Corrected runs are in `artifacts/p2-phase1-final.log`.
- First exported launch omitted Godot's `--` separator and failed before game code while opening its default log. The first F0 regression then reused a prior settings root and failed its default-E precondition. Final reruns used explicit project-local logs and new data roots and passed.
- The pinned Windows runtime reports a non-fatal root-certificate warning; restricted test execution also reports non-fatal GLES shader-cache save warnings during rendered capture.

NEXT:

1. Owner runs `VIEW_NAVIGATION_SPIKE.cmd` and confirms the evidence image/labels are understandable.
2. If accepted, open P3 with one physical attacker only: add placed-entity invalidation, consume the planner result, traverse waypoints under physics and execute obstruction attacks through authoritative world transactions.
3. Measure the live attacker before considering shared paths, asynchronous work, sectors or a small group. Hybrid sector/local routing remains a hypothesis.

GIT/REPRODUCIBILITY:

- Repo: `D:\CODEX\Craft_and_Defend\main`
- Worktree: `D:\CODEX\Craft_and_Defend\worktrees\p2-navigation`
- Branch: `feature/p2-navigation-spike`
- Base P1 checkpoint: `4d41c49849ee77330446481f16b371c339e785a5`
- Implementation/export source: `62c70b08784f56d864fb0110c2b95d3d3c6e42e3`
- Game tree: `44fadfd5d1d604d38beeeed2c8b51b18d685adbb`
- Canonical main: clean `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`
- Platform: Windows 11 Pro `10.0.26200`; AMD Ryzen 9 7900X3D; 64 GB RAM; NVIDIA GeForce RTX 5090 driver 610.88; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`.
- Editor executable: `D:\CODEX\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe`; SHA-256 `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template SHA-256 `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Windows export: PASS; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `d2ec9ccfb47dd0857b782f0f53d6ad48d15e3edeb0c746f8037ac155ca9fa6d6`; built UTC `2026-09-13T05:36:50.2548798Z`.
- Final P2 data roots: `artifacts\p2-export-final` and `artifacts\p2-export-final-visual`; world fixture `AABB(-6,-2,32; 13,5,13)`; start `(0,0,43)`; goal `(0,0,33)`; 20 iterations per benchmark.
- Matching pinned editor processes: zero before final exported phase1 and visual runs. Exported executable: PASS with editor closed.
- No merge, push or release performed.
