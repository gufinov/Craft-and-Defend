# Coding-agent backlog

G0 and the owner-accepted F0 integration slice exist on `main`. The F1 candidate is isolated on its implementation worktree. Each card is independently reviewable with a checkpoint and evidence. Do not rebuild these documents or create a second bootstrap.

## F0 — Windows integration spike (PASS 2026-09-10)

**Recorded result:** T01–T12 passed on the recorded Windows machine. See [the F0 evidence record](evidence/F0_WINDOWS_INTEGRATION.md). Stop for owner review before F1.

**Objective:** prove the stack can support the intended loop before content investment.

1. Inspect Windows/repo state; establish the implementation worktree from the foundation branch. Validate starter files.
2. Acquire exact candidate editor and release template from the recorded release; verify archives with `tools/verify_toolchain.py`; record executable version, SHA-256, class availability and template path.
3. Study pinned Voxel Tools docs and minimal `voxelgame/project/blocky_game` patterns. Check sample compatibility before copying; record source commit/notices for any copied code.
4. Create `game/project.godot`, boot/menu, input actions and a lightweight first-person controller.
5. Set up finite VoxelTerrain, block library, deterministic layered generator, collision-ready spawning and dirt gathering/placement through an inventory transaction.
6. Implement the minimal save coordinator and coherent checkpoint experiment; resolve the actual stream drain/snapshot barrier from source/API evidence.
7. Implement pause, one runtime rebind and persistence; clean exit/reopen.
8. Configure a Windows export preset using the matching custom release template. Export and repeat the loop outside the editor.

**Outputs:** small runtime, exact setup/export commands, F0 evidence, source notices, status checkpoint. **Tests:** T01–T12. **Stop condition:** unexplained save corruption, missing module export, or collision failure. Preserve the reproduction; avoid crafting to conceal the blocker.

## F1 — shell and interaction hardening (CORRECTIVE CANDIDATE PASS; OWNER FULLSCREEN RETEST PENDING 2026-09-11)

Complete keybind UI/reset/conflicts, settings with display rollback, mouse capture/focus loss, window close, inventory overlay, boundary feedback and edit reason codes. Add entity footprint service with synthetic tests. Run T13–T18. Deliver no new content beyond that needed to validate contracts.

**Recorded candidate result:** Tony confirmed all non-display F1 behavior. His 3440×1440 screenshots found pillarboxing that the original T18 harness could not detect. The corrected export explicitly expands the canvas, disables the windowed-size selector in fullscreen, measures real 1600×900 window sizing and verifies a native 3440×1440 framebuffer with game content at both edges. The complete F1/F0 regressions and static tests pass. See [F1 evidence](evidence/F1_INTERACTION_HARDENING.md). Do not merge or begin F2 until owner retest.

## F2 — inventory, progression and workstations

Load the canonical registry; implement slots/stacks/hotbar as one inventory, reachable crafting, workstation placement, immediate bench recipes and timed furnace jobs. Add original distinguishable placeholder textures. Test empty-inventory progression without debug grants, insufficient tool/capacity and double-click duplication. Run T19–T22.

## F3 — persistence hardening

Persist all Foundation state and settings. Exercise independent slots, checkpoint recovery, furnace job continuation and invalid/newer saves. Retain prior complete checkpoint on failure. Record storage/latency measurements and safe close semantics. Run T23–T26 plus T09–T12. Never add an untested migration to recover a sole user save.

## F4 — Foundation acceptance package

Add basic day/night tied to simulation time; keep terrain readable at night. Review UI on 16:9 and ultrawide, confirm no input leaks. Produce a portable Windows folder and fresh-machine-style launch without editor dependence. Run T27–T30 and prior acceptance. Optional wall preview follows required checks only.

## P2 — later navigation spike brief

Before raids, compare the pinned version's experimental voxel pathfinding with a small local-grid approach. Inspect current official API/source at that time. Use one 1×2-cell agent, terrain edits, corridor/wall, trench, stairs, bridge removal and tunnel. Define block damage by enemy capability. Measure recomputation time, stuck cases and memory; a blocked agent should deliberately attack an allowed obstruction or report no route. Scale to a small group only after one agent works. Hybrid sector/local routing is a hypothesis, not a decided architecture.

## Card completion discipline

Update relevant contracts/tests, source ledger and `docs/STATUS.md`; record exact commands/results/limitations; commit a coherent increment. Future systems remain backlog items until their gate is active. Do not automatically merge or publish builds.
