# Evidence — P3K blueprints slice 1 — 2026-09-18

STATUS: PASS (candidate, editor headless) — exported provenance-matched run pending merge with the furnace round-3 work on `feature/p3d-tools-world-feedback`.

DONE: Implemented [the P3K contract](../P3K_BLUEPRINTS.md) slice 1 on branch `feature/p3k-blueprints` (worktree `D:\CODEX\Craft_and_Defend\worktrees\p3k-blueprints`): generated catalogue, stamp engine in `InteractionService` (generalised from P3J with per-cell block types, fixpoint support ordering, per-type budgets, one inventory transaction), per-cell ghost textures, `P3KBlueprintAutomation` (T110–T113), `TEST_P3K_BLUEPRINTS.cmd`, `tests/test_blueprints.py`.

EXPECT (service level; no player entry point yet): stamping `foundation_4` then `tower_segment_4` on its top socket then `cap_4` yields a castle-stone tower with a plank-floored crenellated cap made of ordinary voxels; costs are exact per block type; short stock trims only that type; occupied cells are skipped; cancel builds nothing.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | validation + unittest | 138 links; 45/45 | PASS | commit `7b2271f` |
| T110 | catalogue + rotation | 6 ids, all blocks resolve, wall rotates onto z | PASS | `artifacts/dev-p3k-gate/run.log` |
| T111 | tower stack through sockets | 16 / 39 (36 castle + 3 stone) / 24 (20 castle + 4 planks) cells; inventory exact; steps and interior verified | PASS | same |
| T112 | trim / block / cancel on cap_8 | 1 blocked, 7 unaffordable planks, 72 stamped, cancel unchanged | PASS | same |
| T113 | rendered tower + ghost | `p3k-stamped-tower.png`, `p3k-blueprint-ghost.png` | PASS | `artifacts/dev-p3k-visual/` |
| T79–T83, T108 | P3D drag regression after generalisation | PASS | PASS | `artifacts/dev-p3k-p3d-usability-automation` |
| T42–T45/T50 | castle kit regression | PASS | PASS | `artifacts/dev-p3k-castle-kit-automation` |
| Exported | `TEST_P3K_BLUEPRINTS.cmd` on a provenance-matched build | NOT RUN (pending merge) | NOT RUN | — |
| Owner playtest | not possible yet — no entry point | NOT RUN | NOT RUN | — |

LIMITATIONS/FAILURES: No player-facing entry point in this slice (deliberate: `app.gd` is concurrently being changed for the furnace round; the entry point is slice 2). Spiral steps are full blocks (jumpable), not stone-stair entities. No parapet auto-connect block yet; caps use a fixed crenellation pattern. The first `--check-only` in a fresh worktree fails until `godot --headless --path game --import` has built the class cache — recorded in the P3K contract's tooling notes.

NEXT: merge with `feature/p3d-tools-world-feedback` after the furnace round lands; slice 2: B-menu "Blueprints" page (or build wheel) with W/R rotation and the existing right-click commit; socket ghosting on look; parapet block; Tower Platform retirement.

GIT/REPRODUCIBILITY: branch `feature/p3k-blueprints` from `cab0cb5`; commits `7b2271f` + runner title; engine `4.6.stable.custom_build.89cea1439`. Not yet exported.
