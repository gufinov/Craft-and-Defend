# Evidence — P4F enemy units: orc melee and troll ranged — 2026-09-19

STATUS: CANDIDATE — editor gate (T144, T145) and windowed visual (T146) PASS; regression suites PASS in the editor; `TEST_P4_ENEMY_UNITS.cmd` on the export NOT RUN (no export built on this branch); owner playtest NOT RUN.

DONE: Implemented [the P4F contract](../P4F_ENEMY_UNITS.md): `BasicRaider` rebuilt as box/cylinder/cone models (orc melee with two cleavers and a pauldron; brute = purple orc scaled 1.25; troll ranged with crossbow, quiver, topknot; `KIND_TROLL`, `is_ranged()`, `muzzle_position()`, `face_point()`, `play_attack()`, distance-driven walk bob, melee chop and crossbow kick via Tweens; collision capsule kept as a direct root child; `feet_cell()` and `revive()`/`die()` semantics kept); `CoreDefenseService` troll stats from `balance.core_defense` (`troll_health`, `troll_damage`, `troll_range`, `troll_attack_interval_seconds`), `"trolls"` wave option, per-entry `ranged`/`range`/`attack_interval`, `_ranged_target_in_range` / `_engage_ranged` / `_fire_ranged` / `_spawn_troll_bolt`, `ranged_shots`, melee `play_attack` on every hit; `app.gd` wave/siege drills with trolls and `--p4-enemy-units-automation=` registration; `troll` target filter in `SiegeWeaponPanel` and `WorkstationService.siege_set_target_filter`; content mirrors reformatted; validator accepts the troll keys; `P4EnemyUnitsAutomation` T144–T146; `TEST_P4_ENEMY_UNITS.cmd`; docs (contract, evidence, INDEX, BACKLOG, TEST_PLAN).

EXPECT: Pause → **Start Wave Drill**: an orc leads, followed by a purple brute, a blue-grey troll with a crossbow and three more orcs from 22 cells out. Orcs walk with swinging legs and cleavers, chop when they reach a barricade or the core. The troll stops about nine cells short of whatever it is heading for, turns and fires a bolt every two seconds (core −5 per bolt; barricades take 5 per bolt); it never walks up to melee. Weapon panels offer **Trolls** as a target filter. **Start Siege Drill**: 12 units with three brutes and three trolls from 28 cells out.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | `python tools/validate_foundation.py`; `python -m unittest discover -s tests -q` | PASS (174 links, 36 items, 30 recipes); 60/60 | PASS | this worktree |
| Parse | `--check-only` on `basic_raider.gd`, `core_defense_service.gd`, `app.gd`, `siege_weapon_panel.gd`, `workstation_service.gd`, `p4_enemy_units_automation.gd` | clean | PASS | — |
| T144 | enemy unit models | 3 living: orc 60 mesh parts with `OrcSwordL/R` and `OrcPauldron`; brute `Model.scale` 1.25 with cleavers; troll 78 parts with `TrollCrossbow`, `TrollQuiver`, `TrollTopknot`, no swords; one direct collision shape each; brute 40/10, troll 28/5 ranged 9.0 / 2.0 s, lead 20; troll speed 2.4 | PASS | scratch `agent-units/gate1/run.log` |
| T145 | troll ranged attack | at 14 cells: phase `routing`, 0 shots, integrity 30; at 6 cells: phase `attacking_core`, stopped, 1 shot → 25 with a `TrollBolt` node in the tree, after 2 more seconds 2 shots → 20; drill still ROUTING | PASS | same |
| T146 | rendered units (windowed) | `p4-enemy-units.png` 1280×720, 198 mesh parts over the three bodies; orc, purple brute and troll with crossbow side by side | PASS | scratch `agent-units/visual2/p4-enemy-units.png` |
| Regression | `--p4-siege-units-automation=gate`, `save` then `restore`, `--p3c-player-defense-automation=phase1`, `--p3b-core-defense-automation=phase1` | all `*_AUTOMATION_PASS`, no script errors in any log | PASS | scratch `agent-units/siege-gate`, `siege-sr`, `p3c`, `p3b` |
| Exported | `TEST_P4_ENEMY_UNITS.cmd` | NOT RUN (no export on this branch) | NOT RUN | — |
| Owner playtest | wave drill with trolls | NOT RUN | NOT RUN | — |

LIMITATIONS/FAILURES: No line of sight — a troll shoots through walls once its target is within nine cells. The bolt is presentation only: damage lands with the attack timer, not when the bolt arrives. Trolls take the melee planner's target (the core, or the barricade it would breach); they do not pick machines or the player. The practice `DefenseService` raider uses the orc model but no troll. Model proportions follow the reference images as box parts; expect proportion notes from the owner (the ears and the low sun can read as a hat brim in the evidence render). `TEST_P4_SIEGE_UNITS.cmd` (pre-existing) contains stray CR bytes in its restore/visual log paths — not touched here.

NEXT: owner playtest; export and run `TEST_P4_ENEMY_UNITS.cmd`; line of sight / cover for trolls; trolls targeting siege machines; merge decision with the P4 branch.

GIT/REPRODUCIBILITY: worktree `D:\CODEX\Craft_and_Defend\worktrees\p4-enemy-units`, branch `feature/p4-enemy-units` on top of `6ba89ed` (`feature/p3d-tools-world-feedback`); not pushed, not merged. Engine `D:\CODEX\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe` (4.6.stable.custom_build.89cea1439, Voxel Tools 1.6). Commands: `godot --headless --path game --import`; `godot --headless --path game --log-file <dir>\run.log -- --f0-data-root=<dir> --p4-enemy-units-automation=gate`; the same without `--headless` and `=visual`.
