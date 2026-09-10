# Risks, assumptions and decisions

| ID | Risk / unresolved point | Consequence if wrong | Smallest validation / owner |
|---|---|---|---|
| K01 | Custom editor/template pairing | Export fails or voxel classes absent | F0 archive/hash/class/export proof; local agent |
| K02 | Terrain and game-state coherence | Item duplication/loss or corrupted progress | F0 snapshot barrier; F3 interruption/slot tests |
| K03 | Streaming physics readiness | Falling through terrain or editing unloaded data | Spawn/border/chunk-edge integration tests |
| K04 | Runtime key input/pause ownership | Player cannot exit or actions leak through menus | F0/F1 Windows input tests |
| K05 | Progression has hidden resource/station deadlock | Cannot reach intended tools | Static reachability + actual empty-inventory playthrough |
| K06 | Multi-cell/support semantics | Orphaned entities and duplicate refunds | Synthetic footprint tests, then real workstation tests |
| K07 | Mutable terrain navigation | Enemies stuck or costly global recomputation | P2 single-agent geometry benchmark before raids |
| K08 | World size/performance unknown | Unusable frame time or saves | Fixed small fixture measurements, then controlled scaling |
| K09 | Reference code drift/license mixing | API mismatch or improper redistribution | Immutable compatible commits and per-file provenance |
| K10 | Exploration versus wave pressure unsettled | Frustrating off-screen destruction | P3 warned-wave/excursion playtest |
| K11 | Save backup disk cost | Save stalls or disk growth | Measure two-generation checkpoint cost; revise for larger worlds |
| K12 | Engine release age | Relevant bug/security fixes missed | Check release notes before local install; document a repin if warranted |

## Adopted choices

Single player, Windows-first; menus before world; GDScript + Module candidate; finite editable terrain with depth; ESDF defaults; no initial allied workers; game-specific resource transactions; original art; worktrees and explicit gates; final wizard-led siege is current campaign direction.

## Proposals, not locked design

64×32×128 fixture, 1-unit cells, sea-level zero, +Z friendly side, 27 inventory slots, 64 item stacks, 5-unit interaction reach, 5-second smelting, 20-minute day, static structural support, two-generation checkpoint approach and Compatibility renderer. Change these through a documented small test, not an engine rewrite.

## Still open

Final title, full world size/biomes, resource scarcity, tool durability, health/hunger, player death/defeat/recovery, exploration warnings and attack schedule, difficulty, late-game equipment/magic, exact enemy classes/navigation, post-victory play, minimum PC spec, accessibility/gamepad scope, installer/store/monetization, project license and asset budget.

Do not interrupt Foundation for optional branding or late-game questions. Ask when a decision materially blocks the active gate; make reversible prototype choices explicit otherwise.
