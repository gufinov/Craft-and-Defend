# Current checkpoint — 2026-09-11

**STATUS:** **F2 ACTIVE on an isolated worktree; F1 launcher recovery owner-verified.** Tony confirmed the canonical launcher is working again on 2026-09-11 and authorized the next objective. F2 starts from synchronized `origin/main` commit `c085c013d39b2b64321ea6c5a696b96fe2efd45c` on `feature/f2-inventory-progression`; canonical `main` remains unchanged.

**DONE:** Preserved the accepted F1 history and completed the provenance-guarded launcher recovery at `c085c01`; Tony's fresh graphical relaunch verified the recovery. Re-ran foundation validation and all 18 Python tests before F2 edits. Inspected MinionClash M01 at commit `8457e9e` as read-only design evidence: its grouped/searchable keybind list, per-row reset, clear capture state, centered responsive work column, explicit focus styling and staged changes are useful patterns. Its repository instructions, conflict policy, branding and dirty working changes are not Craft-and-Defend authority and will not be copied as product decisions.

**EXPECT:** F2 loads the canonical Foundation content registry, replaces the single dirt counter with one 27-slot inventory/9-slot hotbar, exposes reachable hand/workbench/furnace crafting, places and dismantles one-cell workstations through occupancy/inventory transactions, and completes timed furnace work exactly once. The keybind screen becomes a compact grouped editor with search, per-row reset and explicit unsaved/capture/conflict feedback while preserving Craft-and-Defend's exact ESDF defaults and conflict-rejection contract.

**TEST:** F2 preflight PASS on Windows 11: Godot `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; foundation validator PASS and 18/18 Python tests PASS using the bundled Codex Python because Python is not on the current shell PATH. F2 runtime gates T19–T22 are NOT RUN until implementation exists.

**LIMITATIONS/FAILURES:** MinionClash's M01 worktree is dirty, so it is evidence of current local UI experiments rather than an accepted reusable baseline; no files there will be modified. F2 has not yet earned a PASS. No engine/content substitution occurred.

**NEXT:** Implement and verify F2 T19–T22, then export the exact Windows package and run prior F0/F1 regression automation before requesting owner playtest. Do not begin F3.

**GIT/REPRODUCIBILITY:** Main path `D:\CODEX\Craft_and_Defend\main`, clean `main` at local/remote `c085c013d39b2b64321ea6c5a696b96fe2efd45c`. Active worktree `D:\CODEX\Craft_and_Defend\worktrees\f2-inventory`, branch `feature/f2-inventory-progression`, based on that exact commit. MinionClash reference path `D:\CODEX\MinionClash\worktrees\milestone-01-move-look-bind-place`, HEAD `8457e9e4f68d26f6f291eb5e1df9465d542991c0`, with pre-existing uncommitted changes preserved. No merge, push or release is authorized for F2.
