# Evidence — F4 side-face block placement repair — 2026-09-11

STATUS: PASS — implementation and matching Windows export; owner graphical retest pending.

DONE:

- Replaced ordinary voxel blocks' below-only support rule with support from any loaded solid voxel on the destination's six orthogonal faces.
- Preserved atomic inventory/world accounting and all existing target occupancy, player-overlap, bounds and load-state checks.
- Preserved explicit floor support for workbenches and furnaces; this repair does not add structural collapse.
- Updated the player-facing rejection text to describe neighboring-face support.

EXPECT:

Placing against the side of a block succeeds even when the destination has air below. A truly floating block with no solid neighboring face remains rejected without consuming inventory or changing terrain. The edit and inventory persist through the existing coherent save and Continue path.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T05 side-face placement | Place at `(2,0,38)` beside the solid block at `(1,0,38)` while `(2,-1,38)` is air | Placement succeeded, consumed one dirt, cleanup returned exactly one dirt | PASS | `artifacts/f4-side-place-v2-phase1.log` |
| T06 unsupported floating | No solid voxel on any of six neighboring faces | Returned `UNSUPPORTED`; world revision, inventory revision and dirt count remained unchanged | PASS | same log |
| T06 prior rejection | Out of bounds, occupied and player-overlap requests remain atomic | All three returned their original stable reasons with no mutation | PASS | same log |
| T09 clean restart | Save, terminate, start a new process and Continue | Terrain, exact inventory/revision, transform and persisted binding restored | PASS | `artifacts/f4-side-place-v2-phase1.log`, `artifacts/f4-side-place-v2-phase2.log` |
| F4 regression | Sunrise/time controls, readable night, F2 capture and clean-process clock Continue remain intact | F4 phase1 and phase2 both reported `F4_CAPTURE_AUTOMATION_PASS` | PASS | `artifacts/f4-side-place-f4-phase1.log`, `artifacts/f4-side-place-f4-phase2.log` |
| Static | Contracts, links and launcher behavior remain valid | Foundation validator PASS; 20/20 Python tests PASS; `git diff --check` PASS | PASS | recorded commands |
| Windows export | Matching custom release template exports the committed repair | Source `c91f0f2`, game tree `51c4aa8`; export PASS with editor closed | PASS | `builds/CraftAndDefend/build_manifest.json` |

LIMITATIONS/FAILURES:

- The automation proves one horizontal side direction. The implementation evaluates all six orthogonal offsets through the same loop; Tony's graphical test remains the user-facing acceptance for camera targeting and presentation.
- Removing a supporting voxel does not trigger general structural collapse; that remains outside Foundation scope.
- Godot emitted the previously recorded Windows root-certificate-store warning. The offline runtime continued and every asserted gate passed.

NEXT:

Tony launches `D:\CODEX\Craft_and_Defend\worktrees\f4-foundation\START_GAME.cmd`, attaches a block to a vertical side face with air below, then saves, fully exits and Continues. Fix any owner-found defect before F4 promotion. Do not merge, push or publish without explicit authority.

GIT/REPRODUCIBILITY:

- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`; clean `main` and `origin/main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\f4-foundation`; `feature/f4-foundation-acceptance`.
- Repair/export source: `c91f0f294510d4f979cd913f9267d1a75fcb3d56`; game tree `51c4aa8e4db470c7716270dc8fa0e3b8aed6f261`.
- Engine/Voxel Tools: Godot `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; extracted editor SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Export EXE SHA-256: `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; export PCK SHA-256: `bd98ca422f6ca3c7fa8ee37ba91102581e83f286775e7c9fe5eaa31c3be78da3`.
- Seed/world/content: seed `41026`; half-open bounds 64×32×128; content version `foundation-1`; isolated roots under ignored `artifacts`.
- Windows export PASS; editor count zero during exported gates; clean-process restart PASS. No merge, push or release performed.
