# Current checkpoint — 2026-09-11

**STATUS:** **F3 IMPLEMENTATION PASS on an isolated worktree; owner playtest and promotion pending.** Tony confirmed the F2 harvesting, hotbar placement and inventory loop. The Print Screen focus repair remains included and passes automation. Canonical `main` remains clean and unchanged at its accepted F1 checkpoint.

**DONE:** Implemented independent Slot A/B selection and status on the native menu; timestamped coherent checkpoints with atomic pointer backup/fallback; two-complete-checkpoint retention; recoverable Retry/Return-to-Pause save errors; refusal of malformed, newer-schema and missing-content saves without replacement; copy-only migration from legacy `slots/default` to Slot A; and full workstation/job persistence across restart. Kept the exact engine, Voxel Tools edition, architecture, ESDF defaults and F2 game loop.

**EXPECT:** Each slot restores only its own terrain, inventory, player and workstation/job state. A failed write or interrupted publication leaves the previous complete checkpoint loadable. Unsupported data is explained and unchanged. A furnace saved with 3.0 seconds remaining completes once after restart. Print Screen must no longer expose or stick the Pause menu; ordinary focus loss must still pause.

**TEST:** PASS on Windows 11 `10.0.26200`, Godot `4.6.stable.custom_build.89cea1439`, Voxel Tools `1.6.0 Module`, OpenGL Compatibility on NVIDIA GeForce RTX 5090. T23–T26 pass in the pinned editor and provenance-matched export; exported F2, F1 and F0 gates also pass in fresh processes with the matching editor closed. Foundation validator and 18/18 Python tests pass. Rendered 1280×720 menu/gameplay/pause captures pass. See [F3 evidence](evidence/F3_PERSISTENCE_HARDENING.md).

**LIMITATIONS/FAILURES:** Tony must test the real Windows Print Screen/Snipping Tool path because automation cannot invoke that OS overlay. F3 save-error UX and A/B selection need owner graphical acceptance. Injected failure points prove application recovery boundaries, not physical power-loss durability or final large-world performance. Two verified orphaned headless editor processes from an earlier parse-error run were terminated; no matching editor process remained during exported regression. No engine/content substitution occurred.

**NEXT:** Tony double-clicks `START_GAME.cmd` in the F3 worktree and performs the short T23–T26/Print Screen playtest. Fix any F3 defect before promotion. Do not begin F4, merge, push or publish without explicit authority.

**GIT/REPRODUCIBILITY:** Main path `D:\CODEX\Craft_and_Defend\main`, clean `main` and `origin/main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`. F3 worktree `D:\CODEX\Craft_and_Defend\worktrees\f3-persistence`, branch `feature/f3-persistence-hardening`; built game commit `00d278ee3aef4093c78cf6b3fb3de5456d2f57db`, game tree `0b70ad5edbd699de90e58110b0801ab7690124df`. No merge, push or release performed.
