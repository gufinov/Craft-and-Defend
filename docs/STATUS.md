# Current checkpoint — 2026-09-11

**STATUS:** **F4 IMPLEMENTATION IN PROGRESS on an isolated worktree.** F3 is preserved at owner-accepted commit `6e8838f`. The F4 candidate now has a persisted simulation-time day/night clock, rebindable non-pausing game-viewport capture (default F2), and explicit standalone portable-package files. Canonical `main` remains clean and unchanged at its accepted F1 checkpoint.

**DONE:** Preserved all accepted F0–F3 behavior. Added the runtime world-clock configuration, day/night lighting with readable ambient floor, phase/day persistence without wall-clock catch-up, visible HUD time, F2 game-viewport PNG capture under the global data root, complete keybind integration, and portable launcher/instructions copied by the Windows builder.

**EXPECT:** Time advances only while gameplay simulation runs, freezes during pause/inventory/save, restores its saved phase and never catches up from wall time. F2 captures the game viewport without stopping play and persists/rebinds globally across slots. The portable folder launches without Git or Godot Editor while preserving the complete Foundation loop.

**TEST:** Current editor-runtime T27–T29 checks pass at 1280×720 on the pinned GPU stack. Capture produced exact-size PNGs while physics, player and simulation stayed active; a fresh process retained a replacement F8 binding and per-action Reset restored F2. Day phase froze in overlay/pause, night remained lit, and Continue restored the exact saved phase before advancing. Fixed-scenario measurements and final export/regressions are still pending. Foundation validator PASS; 20/20 Python tests PASS.

**LIMITATIONS/FAILURES:** A headless screenshot attempt correctly failed because headless rendering provides no GPU image; the same gate passes in OpenGL Compatibility and will be repeated from the exported executable. The full F0–F3 regression and fresh copied-folder T30 launch remain pending. No engine/content substitution occurred.

**NEXT:** Commit the F4 implementation checkpoint, export it with the matching custom release template, run T27–T30 plus prior regressions with the editor closed, inspect final visual evidence, then record the result. Do not merge, push or publish without separate authority.

**GIT/REPRODUCIBILITY:** Main path `D:\CODEX\Craft_and_Defend\main`, clean `main` and `origin/main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`. F4 worktree `D:\CODEX\Craft_and_Defend\worktrees\f4-foundation`, branch `feature/f4-foundation-acceptance`, based on clean F3 acceptance commit `6e8838fc3112589f2fcf59291b02a0a040245729`. No merge, push or release performed.
