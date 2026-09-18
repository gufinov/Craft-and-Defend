# Evidence — P3J drag building — 2026-09-18

STATUS: PASS (candidate) — exported provenance-matched gates pass three times in a row; owner playtest pending.

DONE: Implemented [the P3J contract](../P3J_DRAG_BUILDING.md): drag planning/commit/cancel in `InteractionService`, press/release/cancel routing in `PlayerController`, framed multi-cell ghost and feedback text in `GameSession`. T108 (gate) and T109 (render) added to the P3D suite; the P3D visual checks now wait for the ghost instead of a fixed frame count because the export runs more frames per second than the editor.

EXPECT: Hold a block, right-press on the ground and drag sideways → a row of green framed ghosts; drag upward → a column; both → a wall. Amber cells are beyond what you carry, red cells are blocked. Release builds the green cells and consumes exactly that many blocks; a left-click while still holding right cancels and builds nothing. A plain right-click still places one block.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | validation + unittest | 131 links; 44/44 | PASS | commit `b61890b` |
| T108 | row 6 / column 3 / wall 4×3 with 1 blocked + 1 unaffordable / cancel | all conditions true; inventory 30→24→21→(11 removed)→0; cancel leaves revision and 5 dirt | PASS | `artifacts/manual-p3d-usability-883220165/phase1/phase1.log` |
| T109 | rendered drag ghost ≥ 2 cells | row of 4 framed cells | PASS | `…/visual/p3j-drag-build-ghost.png` |
| T79–T83 | P3D usability, exported ×3 | unchanged | PASS | three folders `manual-p3d-usability-88*` |
| T72–T78 | P3C player defense, exported | unchanged | PASS | `artifacts/manual-p3c-player-defense-851526145` |
| T42–T45/T50, T90/T91/T105 | castle kit, P3F, editor headless | unchanged | PASS | `artifacts/dev-p3j-gate-*` |
| Owner playtest | drag feel, wall building, cancel | pending | NOT RUN | — |

LIMITATIONS/FAILURES: Before the wait fix, T83/T109 failed intermittently on the export (1 of 3, then 2 of 3 runs) purely from sampling before terrain streaming finished; after the fix three consecutive exported runs pass. A plain click now places on release rather than press. No drag for entities or for breaking. The ghost's green fill is dim in shadowed grass; the dark frame carries legibility.

NEXT: Owner playtest; P3K parapet auto-connect and first blueprints.

GIT/REPRODUCIBILITY: worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, commits `f9f4624` + `b61890b`; engine `4.6.stable.custom_build.89cea1439`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `954cb607081eaec4dfcc6940abc010a61d8e6679fb289fa6cb7834bd1e1872ea`. Editor-closed export tested: yes.
