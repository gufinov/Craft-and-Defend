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
| P1 — terrain/exploration | Seeded hills/valleys, distributed trees and ore, safe home clearing, exploration/return cue, generator-compatible saves | T37–T41 plus F0–F5 regression and owner playtest | Active candidate |
| P2 — navigation risk spike | One attacker routes around, through and against edited structures | Separate bounded pathfinding benchmark | Not started |
| P3 — defense slice | One warned wave, one stationary trap/weapon, repair loop | Defense is readable and fun | Not started |
| P4 — campaign systems | Threat sources, rifts, escalation, wizard final siege | Balance/scaling evidence; scope review | Not started |
| Later | Automation/templates, more biomes/content, packaging/store | Separate decisions based on tests | Not started |

The final world size, wave count, unit count, attack cadence and commercial scope are not fixed. A small navigation experiment may reveal a need to revise terrain or enemy capabilities before P3. Do not promise globally perfect pathfinding over unrestricted player edits.

The first P1 slice establishes dependable terrain and exploration before multiplying construction content. Structural masonry and access pieces remain the next P1 content slice after footprint, rotation, recipe-shape and collapse-policy decisions; defensive mounts and one stationary weapon join P3; player equipment follows an explicit combat contract; magic remains a later reviewed track. See [Castle construction and crafting plan](CASTLE_CONSTRUCTION_AND_CRAFTING.md).
