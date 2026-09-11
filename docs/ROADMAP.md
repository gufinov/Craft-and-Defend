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
| F5 — crafting interface | Tab-only inventory, B hand crafting, right-click station menus, 2×2/3×3 recipe presentation; castle-system plan | T31–T34 plus F2–F4 regression | Candidate implementation PASS; owner 3440×1440 graphical acceptance pending |
| P1 — terrain/exploration | Hills, trees, ore placement, exploration/return pacing | Playtest gather/build loop before attacks | Not started |
| P2 — navigation risk spike | One attacker routes around, through and against edited structures | Separate bounded pathfinding benchmark | Not started |
| P3 — defense slice | One warned wave, one stationary trap/weapon, repair loop | Defense is readable and fun | Not started |
| P4 — campaign systems | Threat sources, rifts, escalation, wizard final siege | Balance/scaling evidence; scope review | Not started |
| Later | Automation/templates, more biomes/content, packaging/store | Separate decisions based on tests | Not started |

The final world size, wave count, unit count, attack cadence and commercial scope are not fixed. A small navigation experiment may reveal a need to revise terrain or enemy capabilities before P3. Do not promise globally perfect pathfinding over unrestricted player edits.

The castle-building content track is staged rather than dumped into one inventory: structural masonry and access pieces accompany P1; defensive mounts and one stationary weapon join P3; player equipment follows an explicit combat contract; magic remains a later reviewed track. See [Castle construction and crafting plan](CASTLE_CONSTRUCTION_AND_CRAFTING.md).
