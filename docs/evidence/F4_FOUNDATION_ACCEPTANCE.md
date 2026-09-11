# Evidence — F4 Foundation acceptance package — 2026-09-11

STATUS: PASS — implementation, matching Windows export, full prior regression and copied-folder portability gates complete; owner graphical acceptance pending.

DONE:

- Added a simulation clock sourced from the canonical world contract. Day phase advances only during active play, freezes in inventory/pause/save, persists its phase/day and resumes without wall-clock catch-up.
- Added readable day/night sky, ambient and directional lighting plus a HUD day/time label.
- Added `capture_screenshot`, default F2, to the complete searchable/resettable keybind editor and global `settings.cfg`. It captures only the rendered game viewport to the global `screenshots` folder after a completed frame without changing app state, tree pause, simulation pause, player activity or mouse capture.
- Kept Windows Print Screen/Snipping Tool behavior separate from in-game capture.
- Added an explicit five-file portable package with a standalone `START_GAME.cmd` and local README. The build script copies both and preserves exact source/game-tree provenance.
- Kept the documented Godot/Voxel Tools boundary, exact ESDF defaults, stable content identities and all accepted F0–F3 behavior.

EXPECT:

F2 captures gameplay in the background while play continues and may be rebound globally. Day/night uses simulation time only and restores the saved phase. Terrain remains readable at night. Fullscreen fills the active 3440×1440 monitor; supported windowed sizes remain centered inside that monitor. The copied portable folder runs with Godot Editor closed and without Git, repository tools or source files.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T27 clock | Advance only in active simulation; freeze in overlays/pause | Phase `0.25 → 0.35`; explicit pause and inventory both remained `0.35` | PASS | `artifacts/f4-export-final-phase1.log` |
| T27 restart | Restore phase/day with no offline catch-up, then resume | Saved/restored phase both `0.751106512777778`, day `3`; advanced on subsequent frames | PASS | `artifacts/f4-export-final-phase2.log` |
| T27 night | Terrain remains visible at night | Night ambient `0.58`, dark-blue sky; 1280×720 GPU capture produced | PASS | `artifacts/f4-export-final/screenshots/CraftAndDefend_2026-09-11_18-08-01.png` |
| T28 presentation | Distinct resources, selection/key/time help and craft feedback | Nine non-air colors and imported assets resolved; HUD showed slot, night/time, ESDF and F2; missing-material feedback visible | PASS | `artifacts/f4-export-final-phase1.log` |
| T28 capture | One action writes exact viewport without pausing | F2 wrote 1280×720 PNG; physics advanced `23 → 25`; tree/session remained unpaused | PASS | `artifacts/f4-export-final-phase1.log` |
| T28 key persistence | Rebind persists across restart and Reset restores F2 | F8 persisted in a new process, successfully captured, then per-action Reset restored F2 | PASS | `artifacts/f4-capture-gpu-phase1.log`, `artifacts/f4-capture-gpu-phase2.log` |
| T28 UI layouts | 16:9, 150% scale and ultrawide UI remain readable | Keybind, Settings and Inventory PNGs rendered at 1280×720 and 1720×720 with no clipping observed | PASS | `artifacts/f4-ui-visual/*`, `artifacts/f4-ui-visual.log` |
| Display regression | Native fullscreen and centered window modes remain correct | 3440×1440 filled both edges; 1920×1080, 1280×720 and 1600×900 decorated frames remained inside active monitor | PASS | `artifacts/f4-display-runtime.log` |
| T29 frame | Record fixed 60-frame graphical sample | Average `19.4898 ms`, p95 `20.321 ms`, max `20.655 ms` at 1280×720 Compatibility | PASS | `artifacts/f4-export-final-phase1.log` |
| T29 edit | Record 100 loaded-cell edit operations | `0.188 ms` total; `0.00188 ms` average; all 100 succeeded and final voxel restored | PASS | same log |
| T29 memory | Record actual release-process memory | Working set `181,637,120`; peak `181,637,120`; private bytes `258,379,776`; editor count `0` | PASS | `artifacts/f4-memory-measurement.json`, `artifacts/f4-memory-probe.stdout.log` |
| T29 save | Record coherent save latency/size | `170 ms`; `23,339` checkpoint bytes | PASS | `artifacts/f4-export-final-phase1.log` |
| T30 package isolation | Copy only distributable files; no repo/tool dependency | EXE, PCK, manifest, launcher and README only; `.git=False`, `tools=False`; hashes matched source package | PASS | console record and final manifest |
| T30 portable run | Full F4 gate and Continue work from copied folder with editor closed | Copied EXE passed phase1/phase2; exact copied `START_GAME.cmd` also captured, persisted F8 and exited with zero remaining processes | PASS | `artifacts/f4-portable-phase1.log`, `artifacts/f4-portable-phase2.log`; `T30_PORTABLE_LAUNCHER_PASS` |
| Repository launcher | Owner-facing double-click path selects the provenance-matched package | Exact F4 `START_GAME.cmd` reported matching provenance, launched one visible F4 process, and the test closed only that process | PASS | `F4_ROOT_START_GAME_PASS` |
| F0 regression | Menu, ESDF, collision, edit/reject/save/restart | Phase1/phase2 payloads `passed:true` | PASS | `artifacts/f4-regression-f0-*.log` |
| F1 regression | Complete controls/settings/focus/boundaries/transactions | Phase1/phase2 PASS with 22 implemented keybind rows; Print Screen path PASS | PASS | `artifacts/f4-regression-f1-*.log` |
| F2 regression | Empty-inventory progression, crafting, workstations, Continue | `F2_AUTOMATION_PASS T19-T22` in gate and second process | PASS | `artifacts/f4-regression-f2-*.log` |
| F3 regression | Slots, failure recovery, refusal/migration, exact-once furnace | Phase1, phase2 and validation all `F3_AUTOMATION_PASS T23-T26` | PASS | `artifacts/f4-regression-f3-*.log` |
| Static | Contracts/docs/tooling remain valid | Foundation validator PASS; 20/20 unittest PASS | PASS | commands below |
| Windows export | Matching custom release template exports current committed game tree | Export PASS; final manifest source `8db32f9`, game tree `30eea92`; graphical/runtime gates ran with editor count `0` | PASS | `builds/CraftAndDefend/build_manifest.json` |

Commands:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
& .\builds\CraftAndDefend\CraftAndDefend.exe -- --f0-data-root=<isolated-root> --f4-automation=phase1
& .\builds\CraftAndDefend\CraftAndDefend.exe -- --f0-data-root=<same-root> --f4-automation=phase2
```

LIMITATIONS/FAILURES:

- Godot's headless renderer has no viewport image, so in-game screenshot capture intentionally requires a graphical runtime. The required OpenGL Compatibility editor and exported-executable paths pass.
- Release allocator counters returned unavailable (`0`); T29 therefore uses the actual Windows process working set/private-byte measurement. This diagnostic difference does not affect gameplay.
- The 20-minute clock was advanced deterministically for the phase/freeze gate rather than waiting through an entire real-time cycle.
- Portable isolation was tested in a fresh folder on the recorded Windows PC, not on a second physical machine or clean Windows installation.
- No installer, signing or store package was requested. No P1 terrain expansion, enemies, waves or later systems were started.

NEXT:

Tony launches `D:\CODEX\Craft_and_Defend\worktrees\f4-foundation\START_GAME.cmd`, confirms F2 capture while moving, checks the saved PNG under `%APPDATA%\CraftAndDefend\screenshots`, optionally rebinds it, and observes day/night/pause behavior. Fix any owner-found F4 defect before promotion. Do not merge, push or publish without explicit authority.

GIT/REPRODUCIBILITY:

- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`; clean `main` and `origin/main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\f4-foundation`; `feature/f4-foundation-acceptance`.
- Built source commit: `8db32f97740a53f582aa5e4b84d5f87f9c3632a3`; game tree `30eea92f8bb7d90251e85ab1b0a66b4ae4d607c6`; rollback/accepted F3 `6e8838fc3112589f2fcf59291b02a0a040245729`.
- OS/hardware: Windows 11 Pro `10.0.26200`; AMD Ryzen 9 7900X3D; 64 GB RAM; NVIDIA GeForce RTX 5090 driver `32.0.16.1088`; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine/Voxel Tools: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`, source commit `595f52ee4e23203a865eeb981f115909f7aa92f4`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; extracted editor SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Export EXE SHA-256: `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; export PCK SHA-256: `710c611a70f069dd60b8eb86fded6b7f51bada77bea8b79b4b1aa789a6e90538`.
- Seed/world/content: seed `41026`; half-open bounds 64×32×128; day length `1200` seconds; initial phase `0.25`; content version `foundation-1`.
- Normal data root: `%APPDATA%\CraftAndDefend`; screenshots: `%APPDATA%\CraftAndDefend\screenshots`; automation used isolated ignored roots under `artifacts`.
- Windows export PASS. Matching editor closed during exported and copied-folder acceptance: PASS. Clean-process restart: PASS. No merge, push or release performed.
