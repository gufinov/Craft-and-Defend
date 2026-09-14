# Roadmap

Advance on evidence, not elapsed time. Estimates are intentionally not presented as delivery commitments.

| Stage | Outcome | Gate | Status |
|---|---|---|---|
| G0 — groundwork | Repo docs, contracts, validator, handoff | Static checks; source and status review | Complete |
| F0 — integration spike | Menu, movement, editable world, coherent save/restart, Windows export | T01–T12 | Owner accepted on `main` |
| F1 — interaction hardening | Full controls/settings, boundaries, occupancy, recovery edges | T13–T18 plus F0 regression | PASS; owner accepted 2026-09-11 |
| F2 — gathering/crafting | Small reachable tool/resource loop, inventory, workbench/furnace | T19–T22 | PASS; owner confirmed 2026-09-11 |
| F3 — persistence hardening | Slot isolation, checkpoint interruption recovery, workstations | T23–T26 plus save regression | PASS; owner accepted 2026-09-11 |
| F4 — Foundation acceptance | Visible sun/day/night with per-slot controls, material readability, UI/resolution review, portable package, rebindable in-game capture | T27–T30 and full acceptance | PASS; owner accepted side-face placement repair 2026-09-11 |
| F5 — crafting interface and presentation quality | Tab-only inventory, B hand crafting, right-click station menus, three-panel 2×2/3×3 crafting, stable camera/sun presentation; castle-system plan | T31–T36 plus F2–F4 regression | Owner accepted as current baseline 2026-09-12 |
| P1A — terrain/exploration | Seeded hills/valleys, distributed trees and ore, safe home clearing, exploration/return cue, generator-compatible saves | T37–T41 plus F0–F5 regression and owner playtest | Owner accepted 2026-09-12 |
| P1B — first castle kit | Wall masonry plus stair, wall-walk slab, parapet merlon, 2×2 tower platform and open gate frame; preview, rotation, support, dismantle and save | T42–T50 plus construction playtest | Owner accepted 2026-09-13 |
| P2 — navigation risk spike | One attacker routes around, through and against edited structures | T51–T56 bounded comparison and visual diagnostic | PASS; owner accepted 2026-09-13 |
| P3 — defense slice | One warned attack, field-side approach, one direct-fire stationary weapon, repair loop and live held hotbar | T57–T65 plus owner readability/fun playtest | Owner accepted 2026-09-13 |
| P3B — core and breach prototype | One strategic-core prototype, opening-first targeting, one player-built wooden defense with persisted damage/repair/breach | T66–T71 plus P3 regression and owner playtest | Owner accepted 2026-09-13 |
| P3C — player defense and visual catalog | Paged icon-first inventory/recipe UX, one usable sword, craftable ballista and catapult with distinct targeting contracts | T72–T78 plus P3B/P3/F5 regression and owner playtest | Owner accepted 2026-09-14 |
| P3D — tools and world feedback | Atomic five-batch craft shortcut, first-person held items, block ghosts, Wood Axe and discoverable starter iron | T79–T83 plus P3C/P3B/F5 regression and owner playtest | Owner accepted 2026-09-14 |
| P3E — furnace containers and visual identity | Persistent Furnace input/fuel/output, retained results, familiar stack gestures, manual recipe discovery and closer icon/world identity | T84–T89 plus F2/F3/F5/P3D/P3C regression and owner playtest | Owner accepted 2026-09-14 |
| P3F — recipe order and held visual catalog | Basic-to-advanced recipe order, transparent first-person art for every carried item, and complete voxel face UVs | T90–T92 plus P3C/P3D/P3E regression and owner playtest | Owner accepted 2026-09-14 |
| P3G — Furnace usability and placed siege identity | Shift-transfer, reversible auto-load, per-item progress/continuation and recognizable placed Catapult | T93–T98 plus P3E/P3F regression and owner playtest | Candidate PASS; owner playtest pending |
| P3H — balance, fuel and controls | Named live balance catalogue, counted 1:3 Furnace fuel, W/R directional preview rotation and clearer sword recovery | T99–T102 plus P3E/P3G regression and owner playtest | Candidate PASS; owner playtest pending |
| P3I–P3L — siege servicing, artillery, durability and ecology | Interactable ammo/upgrades; articulated projectiles; tunable wear/harvesting; species-aware tree decay | Separate bounded gates and owner playtests | Planned; not started |
| P4 — campaign systems | Threat sources, rifts, escalation, wizard final siege | Balance/scaling evidence; scope review | Not started |
| Later | Automation/templates, more biomes/content, packaging/store | Separate decisions based on tests | Not started |

The final world size, wave count, unit count, attack cadence and commercial scope are not fixed. Do not promise globally perfect pathfinding over unrestricted player edits. P3C supplies one sword and two player-built defenses against the single active P3B raider. P3D adds immediate-loop feedback and one bounded forestry tool; it does not authorize P4 waves or campaign scope.

P1A established dependable terrain and exploration. P1B established the first original structural kit and reusable placement contract; Tony accepted its two-step stair and ordinary forward traversal on 2026-09-13. Tony accepted the P2 bounded navigation result and P3/P3B defense checkpoints on 2026-09-13, then accepted P3C–P3F through live crafting, held-item, siege, Furnace and presentation tests on 2026-09-14. P3G and P3H are the current isolated candidates: P3H supersedes P3G's former one-Coal-per-item assumption with counted 1:3 fuel. The pinned experimental `VoxelAStarGrid3D` remains a terrain-only benchmark, not gameplay authority. Targeting rules remain in [the defense targeting contract](DEFENSE_TARGETING_CONTRACT.md); future balance, ecology and siege sequencing is in [the balance/ecology/siege contract](BALANCE_ECOLOGY_AND_SIEGE_SYSTEMS.md). Recipe unlock triggers, reloading, durability, armor behavior, waves and magic remain later reviewed tracks.
