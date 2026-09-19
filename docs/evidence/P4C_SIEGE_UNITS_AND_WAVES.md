# Evidence — P4C siege units and wave drills — 2026-09-19

STATUS: CANDIDATE — editor gate and visual PASS; exported `TEST_P4_SIEGE_UNITS.cmd` PASS (T130–T136, T141, T142) on PCK `19bab7cb…` (evidence `artifacts/manual-p4-siege-units-106913565`); owner playtest NOT RUN (owner away; built autonomously on the standing "keep working" instruction).

DONE: Implemented [the P4C contract](../P4C_SIEGE_UNITS_AND_WAVES.md): content for `turret_catapult`, `cannon`, `rail`, `kettle`, munitions `cannonball` and `hot_oil`, recipes (hot oil at the Furnace from logs), validator rules for `dump` weapons and `rail_speed`, `tools/format_content.py` (record-per-line writer for both content mirrors); 3D models in `game_session.gd` (`_build_ballista_visual` remodel, `_build_turret_catapult_visual`, `_build_cannon_visual`, `_build_rail_visual`, `_build_kettle_visual`); `SiegeDefenseService` per-weapon targeting (`_target_for`), `dump` trajectories, rail riding (`_ride_rails`, `_rail_chain`, `_rail_step`, `rail_rider_cell`), `_animate_fire` (throw / slider release / barrel recoil + muzzle flash / pot tilt), `_lay_ballista_strings`, cannonball and oil projectiles, generic HUD suffix; `CoreDefenseService` waves (`start_prototype(options)`, `extra_raiders`, brutes, `damage_raiders_within`, `damage_raiders_in_cell`, `nearest_raider_position`, `is_raider_node`, snapshot/restore of extras); `BasicRaider.configure(kind)`; `GameSession` fire and sword against any raider, `start_core_defense_prototype(options)`; `app.gd` **Start Wave Drill** button and `--p4-siege-units-automation` registration; `P4SiegeUnitsAutomation` T130–T136; `TEST_P4_SIEGE_UNITS.cmd`; stale expectations repaired (T66 barricade-first, T73/T78 recipe pages, T90 order list).

EXPECT: Craft and place a Cannon on flat ground, a Turret Catapult on a Tower Platform, Rails along a wall top and a Kettle on one rail. Right-click each for its panel (cannonball / stone or flame shot / hot oil). Pause → Start Wave Drill: six raiders (one purple brute) enter from 22 cells out; machines turn to their nearest raider; the kettle slides along its rails to whoever reaches the wall foot and pours burning oil; the drill is won when all six are down.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | validation + unittest | 154 links, 34 items, 29 recipes; 49/49 | PASS | this worktree |
| Parse | `--check-only` on every touched script | clean | PASS | — |
| T130 | new content registered | icons present, cannonball 14, hot oil fire, furnace input `log` → `hot_oil`, kettle `dump` with `rail_speed` 2.5 | PASS | scratch gate log |
| T131 | cannon | placed OK, `CannonBarrel` present, muzzle = `SiegeMuzzle`, shot RAIDER_DAMAGED, ammo 2 → 1, damage 14 | PASS | same |
| T132 | turret catapult on socket | tower OK, mount `light_siege`, `CatapultArm` present, shot RAIDER_DAMAGED, ammo 4 → 3, damage 9 | PASS | same |
| T133 | rails + kettle | 6 rails OK; off-rail kettle `INVALID_MOUNT`; on-rail `rail_mount`; `TARGET_TOO_FAR` before riding; rider reached the rail above the raider; fired at frame 27; ammo 2 → 1; 9 cells burning; damage 6 | PASS | same |
| T134 | ballista presentation | slider present, bolt visible loaded, strand 2.41 long, hidden after unload | PASS | same |
| T135 | wave drill | 4 raiders (1 brute) at z −20, nearest and brute filter correct, splash hit 4, WON after all 4 defeated, snapshot wave_size 4 | PASS | same |
| T136 | rendered units | 78 mesh parts across cannon/turret/kettle; `p4-siege-units.png` shows all five machines (ballista strings re-laid, kettle resting on its rails) | PASS | scratch visual `p4-siege-units.png` |
| Regressions (editor) | P3C phase1/save/restore, P3B phase1/save/restore, P3 phase1, P3D phase1, P3E, P3F, P3G, P3H, P3K, P4 weapon panel, castle kit, F3 | all PASS after the expectation repairs | PASS | scratch gate logs |
| T141 | wave persistence | save: 3 raiders, lead 11, brute 25; clean-process restore: 3 living (brute 25), lead 11, wave 3, distance 14 | PASS | `artifacts/manual-p4-siege-units-106913565/phase1/save.log`, `restore.log` |
| T142 | far spawn on natural ground | 3 raiders on the surface 28 cells out, all routed OK after ~38 frames of terrain streaming | PASS | same gate.log |
| Exported | `TEST_P4_SIEGE_UNITS.cmd` | gate T130–T135 + T142 PASS, save/restore T141 PASS, visual T136 PASS, `p4-siege-units.png` produced | PASS | `artifacts/manual-p4-siege-units-106913565` |
| Owner playtest | place the four machines, run the wave drill | NOT RUN | NOT RUN | — |

LIMITATIONS/FAILURES: Raiders do not attack rails, kettles or machines (only barricades and the core). Brutes use the basic capability (step 1). The kettle's ride is visual-only (its cell never moves) so its panel opens at the anchor cell. Cannon damage to castle stone is not modelled. The wave button's numbers (6 raiders, 1 brute, 22 cells) are a first balance guess for the owner to tune. The units were modelled without the reference images at hand for this final pass (the images were reviewed earlier in the session); expect the owner to ask for proportion changes.

NEXT: owner playtest of the four machines and the wave drill; then P3K slice 2 (blueprint menu), raiders vs machines/rails, cannon vs stone, province/market.

GIT/REPRODUCIBILITY: branch `feature/p3d-tools-world-feedback` on top of `547ce2c` (weapon panels). Engine `D:\CODEX\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe` (4.6.stable.custom_build.89cea1439).
