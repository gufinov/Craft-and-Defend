# Evidence — P3 bounded defense slice — 2026-09-13

STATUS: OWNER-FEEDBACK REVISION CANDIDATE PASS — automated/runtime/export gates pass; owner retest pending

DONE:

- Added one explicit paused-menu Defense Drill with a five-second warning.
- Added one physical 1×2 basic raider driven by the selected P2 bounded local planner.
- Added a stationary mounted practice ballista with four visible bolts and deterministic five-damage shots.
- Added a damageable/reddening plank barricade and Shift-use repair through the real physics raycast; one Planks restores six integrity atomically.
- Added exact placed-entity occupied-cell propagation for navigation refresh.
- Added coherent defense save data and live-raider reconstruction on Continue.
- Added a persistent nine-slot held hotbar that mirrors authoritative item IDs, counts and selection, with original block artwork where available.
- Reoriented the drill so the raider enters from the field side, raised and labelled the practice ballista, and labelled the temporary barricade.
- Added direct physics-ray line-of-sight gating and a visible travelling bolt. A blocked ray consumes no ammunition and causes no damage.
- Recorded the accepted future king/core/opening/breach and direct-versus-ballistic siege rules in `docs/DEFENSE_TARGETING_CONTRACT.md` without representing them as implemented.

EXPECT:

The bounded drill proves whether one warned attack, one stationary defense and one repair interaction are readable enough to justify deeper P3 content. It does not claim production combat, campaign balance or craftable siege deployment.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T57 | Explicit warning and one ballista fixture | Pause action created one clear lane, labelled barricade, elevated ballista with four bolts and five-second warning | PASS | `artifacts/exported-p3-defense-revision-final/phase1.log` |
| T58 | Physical P2 route and exact entity invalidation | One CharacterBody raider entered from the field side on a seven-cell `ATTACK_OBSTRUCTION` route; parapet add/remove refreshed two exact events | PASS | `artifacts/exported-p3-defense-revision-final/phase1.log` |
| T59 | Atomic player repair | Real physics ray hit the damaged wall; one Planks restored 18→24, and a full-wall retry did not consume another | PASS | `artifacts/exported-p3-defense-revision-final/phase1.log` |
| T60 | Finite stationary ammunition | Four clear-ray bolts produced four 5-damage hits, reduced 20 HP to zero and retained wall damage | PASS | `artifacts/exported-p3-defense-revision-final/phase1.log` |
| T61 | Service save envelope | Phase, arena, 18/24 wall, zero remaining bolts and navigation revision round-tripped exactly without a duplicate raider | PASS | `artifacts/exported-p3-defense-revision-final/phase1.log` |
| T62 | Real checkpoint/full restart | Export saved an attacking drill at wall 12/24, 3 bolts and raider 15/20 in 23,779 bytes/48 ms; a second process Continue restored those exact values and one physical raider | PASS | `artifacts/exported-p3-defense-revision-checkpoint/save.log`, `restore.log` |
| T63 | Rendered feature evidence | 1280×720 frame contains the live hotbar, labelled damaged barricade, elevated ballista, visible gold bolt and physical raider | PASS | `artifacts/exported-p3-defense-revision-visual/p3-defense-slice.png`, `visual.log` |
| T64 | Live held hotbar | All nine gameplay slots rendered; selected slot 1 showed Dirt and selection matched the authoritative inventory snapshot | PASS | `artifacts/exported-p3-defense-revision-final/phase1.log` |
| T65 | Direct-fire line of sight | Clear ray first hit `BasicRaider`; an inserted solid blocker returned `LINE_OF_SIGHT_BLOCKED` with no health/ammunition mutation; removing it allowed one visible travelling bolt | PASS | `artifacts/exported-p3-defense-revision-final/phase1.log` |
| Regression | Preserve accepted game | Correctly serialized final export F0, F2, P1 terrain, P1 castle and P2 navigation phases all exited 0 and reported no failure marker | PASS | `artifacts/exported-regression-p3-revision-final/` |

Static verification:

- `python tools/validate_foundation.py` — PASS.
- `python -m unittest discover -s tests -v` — 28/28 PASS.
- Pinned runtime T57–T65 — PASS.
- Matching custom-template Windows export — PASS.
- Matching exported executable with pinned editor closed — PASS.

LIMITATIONS/FAILURES:

- The ballista, platform and four bolts are bounded drill fixtures. They are not yet craftable/placeable content connected to the P1 `light_siege` socket.
- No player health/death, armor, drops, attack animation, sound, multi-wave logic, multiple attackers, global path sharing or campaign balance exists.
- Initial physical-route execution failed with `INVALID_ENDPOINT` because subtracting the exact capsule-center height crossed an integer voxel boundary through floating-point rounding. The logical feet-cell uses a stable interior offset now; T58 passes.
- One F4 regression attempt incorrectly used the headless display driver for a rendered capture and timed out. The isolated process was stopped; F4 phase1/phase2 passed with the required hidden Windows render window.
- The first owner-feedback diagnostic exposed a strict inferred-boolean parse error and then a genuine wall-boundary line-of-sight collision. The type was made explicit and the elevated muzzle/upper-torso aim was corrected; the blocker test was retained and now passes.
- An initial broad exported regression was invalid because GUI-subsystem processes were launched concurrently; a later command also used shortened castle/navigation flags. Neither is counted as product evidence. The final record waits for every process and uses the actual flags.
- Player-built castle pieces currently block navigation, but they do not yet share the practice barricade's durability/repair contract. King/core targeting, opening-first live target switching, waves and catapult ballistics are recorded direction, not implemented claims.

NEXT:

Tony runs the graphical playtest from `D:\CODEX\Craft_and_Defend\worktrees\p3-defense\START_GAME.cmd`. Accept the revision only if the nine-slot held display, field-side approach, visible direct-fire behavior, wall occlusion and Shift repair are understandable and feel promising. Craftable siege integration or wider combat requires the next reviewed contract.

GIT/REPRODUCIBILITY:

- Repo, branch, commit, worktree: `D:\CODEX\Craft_and_Defend`; `feature/p3-defense-slice`; implementation/export source `134fc685141f3c92dc79d44ec75802b84faa5b58`; game tree `4aba2fbf7d550d67e286d11044ee2362b266ee97`; `D:\CODEX\Craft_and_Defend\worktrees\p3-defense`.
- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`, clean `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- OS / CPU / GPU / RAM / resolution / renderer: Windows 11 Pro 10.0.26200; AMD Ryzen 9 7900X3D; NVIDIA RTX 5090 driver 610.88; 64 GB; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine executable version and SHA-256: `4.6.stable.custom_build.89cea1439`; extracted editor `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`; editor archive `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`.
- Export template version and SHA-256: Voxel Tools `1.6.0 Module` matching custom release template; extracted template `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`; archive `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`.
- Build artifact SHA-256: EXE `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `9368b67af0f1e6aa7350f45d022cb778aff4a75b8674c23c9d6eb3c44a8167d1`; built UTC `2026-09-13T08:27:19.2020057Z`.
- Commands, seed, world bounds, content version, save root: project build script `tools/build_windows_f0.ps1`; P3 modes `phase1`, `save`, `restore`, `visual`; seed `41026`; bounds min `(-32,-16,-64)`, size `(64,32,128)`; content `foundation-1`; isolated roots under `artifacts/exported-p3-defense-*`.
- Clean-process restart and editor-closed export tested: yes. Editor process absence was checked before exported gates; save and restore used separate executable processes.

No merge, push or release was performed.
