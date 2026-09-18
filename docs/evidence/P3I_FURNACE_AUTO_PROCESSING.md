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

LIMITATIONS/FAILURES: Auto-start attempts once per tick per idle Furnace; with one furnace recipe this is negligible, but if the recipe list grows a per-station dirty flag would be cheaper. `GameSession.try_craft` still allows a direct furnace start for diagnostics.

NEXT: Owner playtest; P3J drag building.

GIT/REPRODUCIBILITY: worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, commits `00826eb` + `34c7328`; engine `4.6.stable.custom_build.89cea1439`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `0f02a11192f473ee2a8854990d668cc54a69d4f99408b9204108b9f29856e670`. Editor-closed export tested: yes.
