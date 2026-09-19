# Foundation prototype scope

Two different deliverables must remain distinct: this **groundwork package** (documents, fixtures, validators) and the future **Foundation playable** (F0–F4). Completion of paperwork is not completion of gameplay.

## F0 — smallest useful integration experiment

A native Windows build boots to a main menu, enters a finite layered 128×32×192 block world (64×32×128 until 2026-09-19), uses ESDF movement, breaks and gathers a hand-mineable block, places it elsewhere, rejects invalid placement, pauses, allows one persistent key rebind, saves a coherent world/inventory checkpoint, quits entirely and reloads it. Run the same sequence from the exported executable with the editor closed. No crafted tools or procedural world required yet.

Stop and record a clear pass/fail at F0. A menu plus a rendered cube is insufficient. The test must exercise real voxel editing, physics, state accounting, save lifecycle and export.

## Full Foundation — F1–F4

| Included | Acceptance outcome |
|---|---|
| Complete application shell | New/Continue, settings, keybinds, pause/resume, save-exit, quit, window-close handling |
| First person | Walk, strafe, sprint, jump, crouch, mouse look and input capture |
| Finite editable terrain | Dimensions configurable per new world; below/above sea-level space; mining, filling and repeated edits |
| Resources | Log, dirt/grass, stone, coal ore, iron ore, planks; protected bottom |
| Inventory/hotbar | 27 proposed slots including 9 hotbar slots; no negative or duplicate counts |
| Crafting | Reachable wood → stone → iron pick progression; simple recipe list |
| Workstations | Place/interact/dismantle workbench and furnace; furnace job timer persists |
| Local persistence | Coherent terrain/player/inventory/station/time checkpoints; settings independent; recovery tests |
| Day/night | Visible sun and readable lighting/clock; per-slot time and cycle controls; frozen during pause and restored on load; no attack schedule |
| Original placeholder art | Distinct materials sufficient to identify blocks, with provenance |
| Portable Windows build | Works outside editor and tool directories; no installer required |

Optional after required gates: one costed wall-line template preview. It does not delay Foundation acceptance. Rich hills, vegetation, water, structural collapse, tool durability and health/survival tuning are subsequent work.

## Excluded

Enemies, waves, rifts, wizard combat, armies, allied NPC workers, advanced machines, mobile siege weapons, multiplayer, cloud services, accounts, streaming infinity, complex fluid simulation, full art production, monetization, installer/store publishing, and universal engine portability. Document future boundaries without building their implementations.

## Definition of done

All mandatory rows in [TEST_PLAN.md](TEST_PLAN.md) for the current gate have evidence, no unresolved data-loss/item-duplication/input-escape failures, and reproducible build/setup instructions exist. Windows testing must be actual Windows execution. Performance figures must name hardware, build, renderer, resolution and scenario. Tony can then playtest the intended slice; `main` is updated only through the agreed review/merge workflow.
