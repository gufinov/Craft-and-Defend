# Coding-agent handoff

> **Checkpoint update (2026-09-14):** This was the original F0 commission and is retained for provenance. F0–F5 and P1–P3F are owner-accepted. P3G Furnace usability and placed Catapult identity is the current isolated candidate. Use [current status](STATUS.md), [roadmap](ROADMAP.md), [P3G contract](P3G_FURNACE_USABILITY_AND_SIEGE_VISUAL.md), [castle construction and crafting plan](CASTLE_CONSTRUCTION_AND_CRAFTING.md) and recorded evidence for current truth. The historical instructions below are not a fresh commission.

You are implementing Craft-and-Defend, an independent first-person voxel survival fortress game. This repo already contains the supervisory foundation. **Do not restart Deep Research or rewrite the groundwork before implementing the next gate.**

## First actions

1. Read `AGENTS.md`, `docs/STATUS.md`, `docs/ENGINE_DECISION.md`, `docs/PROTOTYPE_SCOPE.md`, `docs/WINDOWS_SETUP.md`, and the F0 card in `docs/BACKLOG.md`.
2. Inspect local folders, Git state, hardware and installed tools read-only. Standard layout: `D:\CODEX\Craft-and-Defend\main` and `D:\CODEX\Craft-and-Defend\worktrees`.
3. Create/reuse `prototype/foundation` in the `foundation` worktree from `origin/docs/foundation-groundwork` while that PR is open; use validated `origin/main` after it is merged. Preserve unrelated local changes.
4. Run the repository checks. Review `contracts/` and the module docs, particularly persistence and occupancy.
5. Verify the candidate toolchain archives/version/classes. Begin F0 only, with checkpoints. No unvalidated gameplay goes into main.

## Technical starting point

Godot 4.6 custom build + Voxel Tools 1.6 **Module**, GDScript, Windows x86-64, standard precision. This is the research candidate, not a runtime-proven pair for the project. Use VoxelTerrain for bounded blocky terrain, VoxelMesherBlocky/VoxelBlockyLibrary for blocks, a collision-enabled viewer and a simple CharacterBody3D. Use fresh runtime VoxelStreamSQLite instances per session. Do not silently substitute Babylon, Minecraft, another engine or another edition/version.

Study upstream voxelgame's blocky example and pinned Voxel Tools APIs before reimplementing voxel infrastructure. Pin any copied code to a compatible source commit and preserve notices. Original placeholder textures only.

## Deliver the smallest real proof

Create the game shell first: main menu → explicit Start → finite world. Walk using E/D/S/F. Break/gather/place dirt with correct accounting and placement rejection. Pause, change a movement binding, save a coherent terrain/inventory checkpoint, exit completely, relaunch and Continue. Export with the matching Windows release template and repeat with the editor closed. See T01–T12. The safe async database checkpoint/teardown barrier is a testable risk; do not assume a save tracker makes separate files atomic.

Stop at a recorded F0 result before content expansion. If blocked, retain the smallest reproduction, exact errors, source assumptions and attempted fix. Do not hide a failure behind more features. After F0 passes, F1–F4 cover interaction/settings hardening, crafting/workstations, recovery and day/night. Enemy/pathfinding/wave work is later.

## Constraints and acceptance

No initial allied workers, monsters, rifts, multiplayer, cloud services, rolling weapons or sophisticated machines. Finite terrain has depth; a flat F0 surface does not make the product surface-only. Preserve one logical occupant per cell, future multi-cell footprints, explicit transactions and versioned saves. Tab inventory, Escape pause, Space jump, A sprint, Z crouch, Shift interact, 1–9 hotbar and reserved G supplement ESDF.

At every checkpoint update `docs/STATUS.md` and evidence with **STATUS, DONE, EXPECT, TEST, LIMITATIONS/FAILURES, NEXT, GIT/REPRODUCIBILITY**. Give Tony the runnable artifact only once it is actually built and tested. Do not merge or publish automatically.

## Short kickoff prompt

> Open `gufinov/Craft-and-Defend`, fetch `docs/foundation-groundwork`, and read `AGENTS.md`, `docs/STATUS.md` and `docs/CODING_AGENT_HANDOFF.md`. Follow the Windows worktree setup and begin only the F0 integration spike. Preserve ESDF controls and the Godot/Voxel Tools decision. Report actual Windows save/restart/export evidence before expanding scope; keep main unchanged.
