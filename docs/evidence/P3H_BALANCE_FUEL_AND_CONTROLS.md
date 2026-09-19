# P3H balance, fuel and controls evidence

Recorded: 2026-09-14

**STATUS:** CANDIDATE PASS / OWNER PLAYTEST PENDING.

**DONE:** Built the named live balance catalogue, counted one-Coal-to-three-operation Furnace model with persisted residual work, independent W/R rotation actions and clarified melee-recovery feedback. Preserved the P3G container/auto-load workflow and old-save fallback.

**EXPECT:** One Coal supports exactly three timed smelts; an interruption after the first smelt restores the remaining work correctly, and no fourth output is created. W and R make opposite quarter turns while Shift remains Interact. The visible Furnace/Keybind panels state these rules.

**TEST:** `TEST_P3H_BALANCE_CONTROLS.cmd` PASS from the provenance-matched Windows export. T99 verified catalogue-driven Furnace/harvesting/defense values. T100 loaded three Ore/one Coal, restored mid-sequence, retained three Ingots and ended with zero input/fuel/residual work. T101 verified W/R/Shift. T102 generated two 1280×720 images, both inspected: the Furnace shows `1 Coal → 3 items · 2 stored`; the filtered Keybind list shows W clockwise and R counterclockwise. P3G T93–T98 and P3E T84–T89 also passed against the same export. Static validator and 40 Python tests passed.

**LIMITATIONS/FAILURES:** The Godot Windows runtime reports a non-blocking root-certificate-store warning under the restricted test environment. No owner ultrawide/manual input test has yet been recorded. Future siege, durability, ecology and wave systems are not represented by this PASS.

**NEXT:** Run the graphical playtest from `START_GAME.cmd`; accept or correct P3H before activating P3I.

**GIT/REPRODUCIBILITY:** Worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`; branch `feature/p3d-tools-world-feedback`; implementation commit `6cd6ca268b3b9281184426c70cd94bd26055eb98`; game tree `d765d843c12106ddcc391b9a47cdaa44e93e30fe`. Export EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `125eb62ad8ef3bff90d444b946d34c48d8df8ecc5681c863cd9c66a3c2bf0a12`. Evidence roots: `artifacts/manual-p3h-balance-2745320451`, `artifacts/manual-p3g-furnace-2747319406`, `artifacts/manual-p3e-furnace-2749629109`.
