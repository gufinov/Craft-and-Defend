# Evidence — F1 interaction hardening — 2026-09-10

STATUS: PASS — automated Windows candidate; owner graphical acceptance pending

DONE:

Implemented the bounded F1 shell and interaction card without adding gameplay content. The keybind screen now edits all 21 implemented actions, captures keyboard and mouse input, explains conflicts, resets every documented default, persists across a full restart and recovers a corrupt conflicting stored map. Settings now cover mouse sensitivity, inverted vertical look, master volume, window mode and resolution with an explicit ten-second confirmation/rollback. Inventory and settings own input while open, focus loss pauses, explicit Resume alone recaptures the mouse, and visible stable reason text covers world boundaries and rejected edits. A standalone footprint service atomically reserves, rotates and releases multi-cell ownership.

EXPECT:

Double-click `START_GAME.cmd`. The native menu remains the first state. Keybinds is a scrollable complete action list; selecting Change accepts the next keyboard or mouse press, while Escape cancels. Conflicts do not mutate either action. Tab inventory and settings block world edits. Unconfirmed display changes revert. Closing the Windows app saves coherently. Existing F0 movement, voxel edits and Continue work exactly as before.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | Foundation contracts remain valid | Validator passed; all 16 unit tests passed | PASS | command output in this session |
| T13 | Complete persistent binds; conflict/cancel/reset; no UI input leak | 21 rows; keyboard and mouse capture persisted; conflict named Move Backward; Escape cancelled; corrupt map reset safely; UI caused no mutation | PASS | `artifacts/f1_final_export_phase1.log`, `artifacts/f1_final_export_phase2.log` |
| T14 | Inventory/settings/focus loss pause; explicit resume restores capture | Inventory paused and blocked edits; close resumed; focus loss paused without auto-resume; explicit Resume restored play | PASS | `artifacts/f1_final_export_phase1.log` |
| T15 | Half-open world bounds and protected bottom | Six faces/corners and negative floor conversion passed; bottom removal rejected; player clamped with visible boundary feedback | PASS | `artifacts/f1_final_export_phase1.log` |
| T16 | Rejected/rapid edits never duplicate or lose resources | Stale, full-inventory and wrong-tool requests made no transactional change; duplicate request awarded exactly one item | PASS | `artifacts/f1_final_export_phase1.log` |
| T17 | Multi-cell footprints reserve/reject/release atomically | Rotated 2×2×2 reservation owned eight cells; partial overlap, unloaded, player, support and boundary cases rejected; release cleared all cells once | PASS | `artifacts/f1_final_export_phase1.log` |
| T18 | Display rollback; usable 16:9, ultrawide and high-DPI UI | App countdown rolled preview back; confirmed 1600×900 persisted; exported render passed 1280×720, simulated 150% and 1720×720; captures visually legible and unclipped | PASS | `artifacts/f1_final_export_phase1.log`, `artifacts/f1_final_export_phase2.log`, `artifacts/f1_final_export_visual.log`, `artifacts/runtime-f1-final-export-visual/*.png` |
| F0 regression | Prior native shell, world, movement, editing and coherent Continue remain valid | Exact final export passed both F0 processes; terrain edits, dirt, transform and InputMap restored | PASS | `artifacts/f0_final_regression_phase1.log`, `artifacts/f0_final_regression_phase2.log` |
| Windows close | Real WM_CLOSE saves/exits; save failure remains visible | `CloseMainWindow()` returned true with a nonzero handle; process exited 0; fresh process found checkpoint; injected missing DB stayed open in ERROR with exact reason | PASS | `artifacts/f1_final_wmclose.log`, `artifacts/f1_final_wmclose_verify.log`, `artifacts/f1_final_close_failure.log` |
| Export | Matching custom release template produces runnable package with editor closed | Export succeeded; all exported automation and visual paths ran with no Godot editor process | PASS | `artifacts/windows_export.log`, hashes below |

LIMITATIONS/FAILURES:

- Owner hands-on acceptance is pending; this is not yet the accepted `main` state.
- Inventory intentionally exposes only the F1 dirt summary. Slots, stacks, hotbar selection, tools and workstations belong to F2.
- Entity footprints have deterministic synthetic contract coverage but no gameplay entity consumes the service yet.
- The custom executable emitted `Failed to read the root certificate store` during sandboxed headless runs; local gameplay is offline and every affected run passed.
- One editor startup crashed during log rotation with `Failed to open 'user://logs/...'`; rerunning with an explicit worktree log path passed. The failed process was terminated without project mutation.
- One exported automation attempt omitted Godot's `--` user-argument separator, opened headlessly at the normal user-data root, and was immediately terminated before Start or any save call. The corrected isolated-root run passed; no user save mutation was observed.
- The ordinary system `python`/launcher was unavailable at closeout, so static tests used Codex's pinned bundled Python 3.12.14 executable. This does not affect the shipped game.

NEXT:

1. Tony performs the short graphical test from `START_GAME.cmd`.
2. If accepted, promote `feature/f1-interaction-hardening` through the normal merge path.
3. Begin F2 only after that acceptance; keep later enemies, waves, rifts, workers and automation out of scope.

GIT/REPRODUCIBILITY:

- Repo: `gufinov/Craft-and-Defend`.
- Canonical F0 checkout: `D:\CODEX\Craft_and_Defend\main`, `main`, `466579e9df7570aa174836895e65082cda765b3a`.
- F1 worktree: `D:\CODEX\Craft_and_Defend\worktrees\f1-interaction`; branch `feature/f1-interaction-hardening`; runtime checkpoint `805c3bc` plus the commit containing this evidence.
- OS / hardware / renderer: Windows 11 Pro build 26200; Ryzen 9 7900X3D; 63.2 GB RAM; NVIDIA GeForce RTX 5090 driver 610.88; OpenGL Compatibility. Tested viewports: 1280×720, simulated 150% scale, 1720×720 ultrawide.
- Engine: Godot `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; single-precision Windows x86-64.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; installed editor executable SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; installed template executable SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Final export: `builds\CraftAndDefend\CraftAndDefend.exe` SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; `CraftAndDefend.pck` SHA-256 `673b091e99243b527028dc98d215fc72cded75ade25867d7efe49159d4dcaa2b`.
- Commands: `tools/build_windows_f0.ps1`; exported `--f1-automation=phase1`, `phase2`, `visual`; exported F0 `phase1`, `phase2`, `wait-close`, `verify-close`, `close-failure`; `tools/validate_foundation.py`; `python -m unittest discover -s tests -v`. All runtime data roots were isolated under ignored `artifacts/`.
- World/content baseline: deterministic seed and registry from the accepted F0 project; minimum `[-32, -16, -64]` inclusive and maximum `[32, 16, 64)` exclusive; settings schema 2.
- Clean-process restart and editor-closed export tested: yes. Build outputs, logs, screenshots and test saves are intentionally ignored. No release was published and no engine version/edition changed.
