# Evidence — F0 Windows integration — 2026-09-10

STATUS: PASS

## DONE

Built and executed the bounded F0 Windows integration spike on the required implementation worktree. The exact exported artifact passed the native menu/Start lifecycle, finite voxel world, collision-ready ESDF controller, raycast break/place accounting, invalid placement rejection, pause, keybind UI persistence, chunk unload/reload, coherent normal checkpoint, full restart/Continue, matching custom-template export, real WM_CLOSE, visible save failure and rendered visual checks. No F1+ content was implemented.

## EXPECT

Double-click `START_F0.cmd`. The app opens on its native main menu; it does not auto-enter gameplay. Start loads the finite test world. Escape opens the pause menu. Save and Quit publishes one terrain/gameplay checkpoint; relaunch and Continue restore the saved edits, exact dirt count and player/input state.

## TEST

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T01 | Exact editor/template, module classes, renderer; wrong editor fails clearly | Both archives matched recorded size/SHA-256; Godot 4.6 and all required classes passed; official Godot 4.7.2 reported `FATAL_TOOLCHAIN_MISMATCH` with five missing classes | PASS | `artifacts/toolchain_probe.log`, `artifacts/wrong_engine.log` |
| T02 | Menu first; explicit Start; Quit route | Fresh processes reported menu state with no session; Start signal created the session; native menu and Quit were rendered; process quit returned 0 | PASS | `artifacts/default_data_root.log`, `artifacts/runtime-visual-final4/menu.png` |
| T03 | Correct finite bounds and collision-ready spawn | Bounds `AABB(-32,-16,-64; 64,32,128)`; player settled at Y `0.000139` and never fell through | PASS | `artifacts/export_final4_phase1.log` |
| T04 | ESDF, jump and mouse look; pause/resume input remains usable | Forward action moved Z `40.5 → 38.83336`; jump raised Y; mouse-look changed yaw `0 → -0.075`; resume returned to PLAYING | PASS | `artifacts/export_final4_phase1.log` |
| T05 | Break/gather/place with exact accounting | `VoxelTool.raycast` break removed `(0,-1,38)` and added one dirt; raycast placement wrote dirt at `(1,0,38)` and consumed one; second break left exactly one | PASS | `artifacts/export_final4_phase1.log` |
| T06 | Reject out-of-bounds, occupied and player-overlap without mutation | Returned `OUT_OF_BOUNDS`, `OCCUPIED`, and `PLAYER_OVERLAP`; world revision and inventory snapshot remained unchanged | PASS | `artifacts/export_final4_phase1.log` |
| T07 | Escape pause and responsive menu; Resume restores state | PAUSED and scene-tree pause asserted; keybind menu operated while paused; Resume returned PLAYING | PASS | `artifacts/export_final4_phase1.log`, `artifacts/runtime-visual-final4/pause.png` |
| T08 | Persistent runtime key rebind with conflict handling | Keybind UI rejected physical D conflict, saved Forward as physical R, and a fresh process restored `R - Physical` | PASS | `artifacts/export_final4_phase1.log`, `artifacts/export_final4_phase2.log` |
| T09 | Coherent terrain/inventory/transform restart and Continue | Checkpoint published only after tracker/drain/close; new process restored all three edited cells, dirt `1`, inventory revision `3`, position, yaw and pitch exactly | PASS | `artifacts/export_final4_phase1.log`, `artifacts/export_final4_phase2.log` |
| T10 | Edited chunk unload/reload and subsequent restart persistence | Edited chunk reached `UNLOADED`, returned `LOADED` with edit intact, then T09 restart retained it | PASS | `artifacts/export_final4_phase1.log` |
| T11 | Matching custom release export; repeat outside editor | Custom release template export succeeded; EXE/PCK phase 1 and phase 2 both exited 0 with `passed:true`; no Godot editor process was running | PASS | `artifacts/windows_export.log`, `artifacts/export_final4_phase1.log`, `artifacts/export_final4_phase2.log` |
| T12 | Real window close saves coherently; failure stays visible | Windows `CloseMainWindow()` returned true; app checkpointed and exited 0; fresh process validated it. Missing working DB injection stayed open in ERROR with `Save failed: WORKING_DATABASE_MISSING` | PASS | `artifacts/export_final4_close.log`, `artifacts/export_final4_close_verify.log`, `artifacts/export_final4_close_failure.log` |

Static checks, rerun after implementation:

```text
Python 3.12.14
PASS: foundation static validation {"blocks": 10, "items": 14, "local_links": 67, "placement_cases": 11, "recipes": 9}
Recorded runtime, Windows export and gameplay gate: PASS_2026-09-10
16 unit tests: OK
```

Visual capture from the exported executable used the actual Windows/OpenGL renderer at 1280×720. Menu, gameplay and pause PNGs were opened and inspected; controls were legible and unclipped.

### Owner physical acceptance — 2026-09-10

Tony ran the Windows build directly and reported the F0 slice “100% working.” He verified navigation into and out of the game and world, running, movement, jumping and collision. Four supplied screenshots visibly confirm the native main menu, active ESDF world, pause menu, and a subsequent main menu with Continue enabled after saving. The screenshots remain in Tony's personal screenshots folder and are not copied into the repository.

## Toolchain and hashes

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `godot.windows.editor.x86_64.exe.zip` | 83,340,016 | `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c` |
| `godot.windows.template_release.x86_64.exe.zip` | 30,773,070 | `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857` |
| extracted custom editor | 181,016,064 | `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b` |
| extracted custom release template | 86,435,840 | `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b` |
| `CraftAndDefend.exe` | 86,295,040 | `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2` |
| `CraftAndDefend.pck` | 57,944 | `b26a6a058dc850256a683bcf02a4e121e51d47f1b9a452e18f0dc090e228dd60` |

Engine identity: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; source `595f52ee4e23203a865eeb981f115909f7aa92f4`; renderer `gl_compatibility` / Windows log `OpenGL API 3.3.0 NVIDIA 610.88 - Compatibility`.

## Commands and data

Repository checks used Codex-bundled Python because `python`/`py` were absent from PATH:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
```

World seed `41026`; bounds minimum `(-32,-16,-64)`; size `(64,32,128)`; content version `foundation-1`. Normal save root resolved to `C:\Users\Tony\AppData\Roaming\CraftAndDefend\`. Acceptance used disposable roots under `artifacts\runtime-*`.

The normal checkpoint barrier froze gameplay/stream loading, awaited `VoxelSaveCompletionTracker`, polled Voxel Engine streaming tasks to zero for three frames, detached the terrain, closed the fresh per-session SQLite stream, copied the closed DB and gameplay JSON into a new checkpoint directory, hashed both, then atomically renamed the pointer file. The final edited-world save reported tracker task count zero because the tested chunk-unload cycle had already flushed its edits; the explicit tracker and streaming-idle barriers still ran before publication.

Pinned Voxel Tools source/API was inspected at `595f52e`. `voxelgame` blocky patterns were inspected at `4cf747a8456375e527c8c976c50fb24446f9d18f` (Godot 4.4 reference); no upstream code or assets were copied.

## LIMITATIONS / FAILURES

- This proves coherent normal saves and prior-checkpoint refusal behavior for the F0 path; it is not a power-loss/filesystem durability guarantee. Denied writes, full disk, interrupted publication, A/B slots and migrations remain F3.
- Automated Windows input/action events, actual rendered output and Tony's hands-on Windows playtest were verified.
- The world is intentionally flat and functionally colored. Art production, richer terrain and performance targets are outside F0.
- The first class-probe script used a reserved loop variable and failed parsing; it was corrected and rerun. The first export wrapper exited early on an unset native exit code; explicit `Start-Process -Wait` fixed it. The first hidden WM_CLOSE attempt had handle `0` and was terminated; a visible real-window run accepted WM_CLOSE and passed.

## NEXT

1. Stop at F0 for Tony's review and short graphical playtest.
2. Start F1 only with explicit authorization.
3. Preserve the exact toolchain unless a documented defect triggers the ADR review path.

## GIT / REPRODUCIBILITY

- Repo: `gufinov/Craft-and-Defend`.
- Accepted checkout: `D:\CODEX\Craft_and_Defend\main`; the commit containing this file is the owner-accepted F0 main checkpoint.
- Development lineage: `prototype/foundation`, based on `origin/docs/foundation-groundwork` `c72c9bb084fe4487fb36f068d52be63a6f459c5d`.
- Checkpoints: `57f5676` toolchain probe, `07211b7` gameplay/persistence, `81f075a` export/lifecycle, `c92c091` automated evidence closeout, followed by this owner-acceptance checkpoint.
- Export and local runtime artifacts are intentionally ignored; no release or engine repin occurred.
