# Evidence — P3 bounded defense slice — 2026-09-13

STATUS: CANDIDATE PASS — automated/runtime/export gates pass; owner readability/fun playtest pending

DONE:

- Added one explicit paused-menu Defense Drill with a five-second warning.
- Added one physical 1×2 basic raider driven by the selected P2 bounded local planner.
- Added a stationary mounted practice ballista with four visible bolts and deterministic five-damage shots.
- Added a damageable/reddening plank barricade and Shift-use repair through the real physics raycast; one Planks restores six integrity atomically.
- Added exact placed-entity occupied-cell propagation for navigation refresh.
- Added coherent defense save data and live-raider reconstruction on Continue.

EXPECT:

The bounded drill proves whether one warned attack, one stationary defense and one repair interaction are readable enough to justify deeper P3 content. It does not claim production combat, campaign balance or craftable siege deployment.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T57 | Explicit warning and one ballista fixture | Pause action created one clear lane, barricade, mounted ballista with four bolts and five-second warning | PASS | `artifacts/exported-p3-defense-final-phase1/phase1.log` |
| T58 | Physical P2 route and exact entity invalidation | One CharacterBody raider received a five-cell `ATTACK_OBSTRUCTION` approach; parapet add/remove refreshed two exact events | PASS | `artifacts/exported-p3-defense-final-phase1/phase1.log` |
| T59 | Atomic player repair | Real physics ray hit the damaged wall; one Planks restored 18→24, and a full-wall retry did not consume another | PASS | `artifacts/exported-p3-defense-final-phase1/phase1.log` |
| T60 | Finite stationary ammunition | Four bolts produced four 5-damage hits, reduced 20 HP to zero and retained wall damage | PASS | `artifacts/exported-p3-defense-final-phase1/phase1.log` |
| T61 | Service save envelope | Phase, arena, 18/24 wall, zero remaining bolts and navigation revision round-tripped exactly without a duplicate raider | PASS | `artifacts/automated-p3-defense-navrev/phase1.log` |
| T62 | Real checkpoint/full restart | Export saved an attacking drill at wall 12/24, 3 bolts and raider 15/20; a second process Continue restored those exact values and one physical raider | PASS | `artifacts/exported-p3-defense-final-checkpoint/save.log`, `restore.log` |
| T63 | Rendered feature evidence | 1280×720 frame contains the damaged wall, practice ballista, physical raider and live defense HUD | PASS | `artifacts/exported-p3-defense-final-visual/p3-defense-slice.png`, `visual.log` |
| Regression | Preserve accepted game | Final export's F0–F5, P1 terrain/castle and P2 phase suites all exited 0 and reported PASS | PASS | `artifacts/exported-regression-p3-final2/` |

Static verification:

- `python tools/validate_foundation.py` — PASS.
- `python -m unittest discover -s tests -v` — 28/28 PASS.
- Pinned runtime T57–T63 — PASS.
- Matching custom-template Windows export — PASS.
- Matching exported executable with pinned editor closed — PASS.

LIMITATIONS/FAILURES:

- The ballista, platform and four bolts are bounded drill fixtures. They are not yet craftable/placeable content connected to the P1 `light_siege` socket.
- No player health/death, armor, drops, attack animation, sound, multi-wave logic, multiple attackers, global path sharing or campaign balance exists.
- Initial physical-route execution failed with `INVALID_ENDPOINT` because subtracting the exact capsule-center height crossed an integer voxel boundary through floating-point rounding. The logical feet-cell uses a stable interior offset now; T58 passes.
- One F4 regression attempt incorrectly used the headless display driver for a rendered capture and timed out. The isolated process was stopped; F4 phase1/phase2 passed with the required hidden Windows render window.

NEXT:

Tony runs the graphical playtest from `D:\CODEX\Craft_and_Defend\worktrees\p3-defense\START_GAME.cmd`. Accept P3 only if warning, target readability, ballista cadence, wall damage and Shift repair are understandable and feel promising. Craftable siege integration or wider combat requires the next reviewed contract.

GIT/REPRODUCIBILITY:

- Repo, branch, commit, worktree: `D:\CODEX\Craft_and_Defend`; `feature/p3-defense-slice`; implementation/export source `e0b9a75ac9b80482d6e51e1ec74098c119810157`; game tree `295511b957636152c54f6192baae45dbadd5e972`; `D:\CODEX\Craft_and_Defend\worktrees\p3-defense`.
- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`, clean `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- OS / CPU / GPU / RAM / resolution / renderer: Windows 11 Pro 10.0.26200; AMD Ryzen 9 7900X3D; NVIDIA RTX 5090 driver 610.88; 64 GB; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine executable version and SHA-256: `4.6.stable.custom_build.89cea1439`; extracted editor `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`; editor archive `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`.
- Export template version and SHA-256: Voxel Tools `1.6.0 Module` matching custom release template; extracted template `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`; archive `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`.
- Build artifact SHA-256: EXE `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `9e9972a4eadf319b5d79f2fb745b983c3a9e2de8770b701787dda50102e80900`; built UTC `2026-09-13T07:17:06.0403868Z`.
- Commands, seed, world bounds, content version, save root: project build script `tools/build_windows_f0.ps1`; P3 modes `phase1`, `save`, `restore`, `visual`; seed `41026`; bounds min `(-32,-16,-64)`, size `(64,32,128)`; content `foundation-1`; isolated roots under `artifacts/exported-p3-defense-*`.
- Clean-process restart and editor-closed export tested: yes. Editor process absence was checked before exported gates; save and restore used separate executable processes.

No merge, push or release was performed.
