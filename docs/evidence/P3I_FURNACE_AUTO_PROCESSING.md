# Evidence — P3I Furnace auto-processing — 2026-09-18

STATUS: PASS (candidate) — exported provenance-matched gates pass; owner playtest pending.

DONE: Implemented [the P3I contract](../P3I_FURNACE_AUTO_PROCESSING.md): `WorkstationService._auto_start_idle_furnaces()` runs at the top of `advance()`; furnace panel button relabelled **Load from Inventory**; idle label explains automatic processing. T107 added to the P3G gate. Repaired the stale F2_KEYBIND_UI test (it rebound to R, which has been the rotate key since P1).

EXPECT: Right-click a placed Furnace, drop ore into Raw Input and coal into Fuel (or press Load from Inventory), close the panel and walk away. The progress bar advances on its own and each ore becomes an ingot in Output until the ore runs out. While paused, nothing advances.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | validation + unittest | 127 links; 44/44 | PASS | commit `34c7328` |
| T107 | auto-start on tick, not while paused, 2 ore → 2 ingots, idle after | all conditions true | PASS | `artifacts/manual-p3g-furnace-568724137/gate/gate.log` |
| T93–T98 | P3G furnace usability, exported | unchanged | PASS | same folder |
| T84–T89 | P3E containers, exported | unchanged | PASS | `artifacts/manual-p3e-furnace-570723092` |
| F2 gate, F3 phase1 | editor headless | F2_KEYBIND_UI (repaired), T19–T22, F2_CHECKPOINT, T24 | PASS | `artifacts/dev-p3i-f2-automation`, `artifacts/dev-p3i-f3-automation` |
| Owner playtest | load and walk away | pending | NOT RUN | — |

ROUND 2 (owner playtest, same day): fuel model 2 (burning Coal stays until burnt out, legacy restore migration), chained-time carry in `advance()`, +1/+5 click gestures, Load ×1/×5 button. Exported at commit `620b368`, PCK SHA-256 `f0c296b2832f8b4c719037152a6d93c5ff717691f03126180895fd5f6cd81ab7`: `TEST_P3G` T93–T98 + T107 PASS (`artifacts/manual-p3g-furnace-2406315692`); `TEST_P3H` T99–T102 PASS incl. T100 counted fuel through save/restore (`artifacts/manual-p3h-balance-2408214646`); `TEST_P3E` T84–T89 PASS (`artifacts/manual-p3e-furnace-2412212555`). Editor headless: F2 gate, F3 phase1 PASS. The +1/+5 click gestures are exercised at the service level (counted transfer in T107); the panel click routing is not driven by automation and is owner-verified.

ROUND 3 (owner playtest, same day; commit `COMMIT_HASH`): (1) fuel timing — the lit Coal now leaves Fuel when its last job completes (`furnace_fuel_burning` persisted, legacy restore); (2) the crafting modal fits 1280×720 in furnace and workbench modes (help moved to tooltips, two-line caps, smaller buttons); (3) select-then-add — gold-border highlight on the selected tile, furnace-specific selection message, recipe inferred without the recipe book, additive Load ×1/×5 (`try_load_furnace_batches`). Editor headless (engine `4.6.stable.custom_build.89cea1439`): P3G gate T93–T97, T107, **T110** PASS (`artifacts/dev-agent-r3-p3g-gate-1`); P3G visual T98 (furnace clear-button bottom 615, message bottom 664; workbench 621/670, all ≤ 720) and **T111** real-click path (ore tile → Raw Input +1 → Shift+click +3 of 3 remaining) PASS (`artifacts/dev-agent-r3-p3g-visual-3`, screenshots `p3g-furnace-autoload-progress.png`, `p3g-workbench-modal-fit.png`, `p3g-furnace-select-then-add.png`); P3H gate T99–T102 PASS incl. T100 (`artifacts/dev-agent-r3-p3h-gate-1`); P3E gate T84–T88 PASS after T87 moved its "persist" check to the help tooltip (`artifacts/dev-agent-r3-p3e-gate-2`); P3E visual PASS (`artifacts/dev-agent-r3-p3e-visual-1`); F2 gate T19–T22 PASS (`artifacts/dev-agent-r3-f2-gate-1`); F3 phase1 PASS (`artifacts/dev-agent-r3-f3-phase1-1`); `validate_foundation.py` PASS, unittest 44/44. Exported (`TEST_P3G`, `TEST_P3H`, `TEST_P3E`): NOT RUN — integrator export pending. Owner playtest of round 3: NOT RUN.

LIMITATIONS/FAILURES: Auto-start attempts once per tick per idle Furnace; with one furnace recipe this is negligible, but if the recipe list grows a per-station dirty flag would be cheaper. `GameSession.try_craft` still allows a direct furnace start for diagnostics.

NEXT: Owner playtest; P3J drag building.

GIT/REPRODUCIBILITY: worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, commits `00826eb` + `34c7328`; engine `4.6.stable.custom_build.89cea1439`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `0f02a11192f473ee2a8854990d668cc54a69d4f99408b9204108b9f29856e670`. Editor-closed export tested: yes.
