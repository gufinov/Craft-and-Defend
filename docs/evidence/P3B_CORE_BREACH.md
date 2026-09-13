# Evidence — P3B core and player-built breach prototype — 2026-09-13

STATUS: CANDIDATE PASS — automated/runtime/export gates pass; owner ultrawide playtest pending

DONE:

- Added one clearly labelled cyan `strategic_core_prototype` and one field-side physical raider.
- Added the paused-menu **Start Core Defense Prototype** action without replacing the accepted P3 drill.
- Added a 20-second player setup window with explicit field-side barricade guidance.
- Added a Workbench recipe for an original two-cell-high `wood_barricade` placed through the existing inventory/occupancy path.
- Added stable instance-owned current/max integrity, material capability tags, visible damage tint, atomic Planks repair and whole-entity breach without a refund.
- Added opening-first planning: an available core route wins; a wooden obstruction is selected only after every route in the bounded lane closes.
- Added exact occupied-cell invalidation and replan after destruction.
- Added coherent checkpoint state for the core, raider, target and surviving player-built defense integrity.
- Corrected the owner-reported Workbench discoverability defect: Wood Barricade was card 12 of 14 below the first viewport. A validated data priority now makes it the first visible card, while search and scrolling retain the full list.
- Replaced the direct-ID-only T66 assumption with actual Workbench modal and rendered-card evidence.

EXPECT:

This candidate proves the smallest connection between castle building and a strategic target. It does not claim campaign waves, production combat or final core fiction.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T66 | Visible Workbench recipe, two-cell placement, stable identity/integrity and repair | Real modal exposed 14 cards with Wood Barricade first; search returned exactly one matching card; rendered first page showed `READY`; recipe then produced one barricade, reserved `(6,0,38)` and `(6,1,38)`, and passed 30→24→30 repair | PASS | `artifacts/exported-p3b-recipe-fix-344367fb313c46899d9db36af3e50ab4/phase1/phase1.log`; `recipe_visual/p3b-workbench-recipe.png` and `recipe_visual.log` |
| T67 | Open route reaches core without incidental defense damage | Planner returned `OK`, a 15-cell route and target `core`; nearby barricade remained 30/30 | PASS | same phase1 log/result JSON |
| T68 | Full blockage selects and breaches one exact wooden entity | Five bounded six-damage hits reduced 30→0, released both cells, returned no refund and replanned `OK` to `core`; 22 exact changed cells observed across the fixture | PASS | same phase1 log/result JSON |
| T69 | Basic raider refuses castle structure; siege candidate distinguishes it | Gate-frame tags were `stone`/`fortification`; basic damage resolved to 0 and siege-candidate damage to 8 | PASS | same phase1 log/result JSON |
| T70 | Atomic save and clean-process Continue | Export saved core 18/30, raider 14/20, core target and barricade 24/30 in 24,462 bytes/170 ms; a second process restored those exact values and one barricade | PASS | `artifacts/exported-p3b-recipe-fix-344367fb313c46899d9db36af3e50ab4/persistence/save.log`, `restore.log` |
| T71 | Rendered readable core/barricade/opening/raider evidence | 1280×720 frame shows the cyan labelled core through the opening, brown damaged 24/30 barricade, red field-side raider and `RAIDER ROUTING TO CORE` HUD | PASS | `artifacts/exported-p3b-recipe-fix-344367fb313c46899d9db36af3e50ab4/core_visual/p3b-core-defense.png`, `core_visual.log` |
| P3 regression | Preserve accepted drill behavior | T57–T61 and T64–T65 all pass from the final matching export | PASS | `artifacts/exported-p3b-recipe-fix-344367fb313c46899d9db36af3e50ab4/p3_regression/p3_regression.log` |
| F5 regression | Preserve crafting contexts, search/autofill and graphics | T31, T33, T35 and T36 all pass from the final matching export | PASS | `artifacts/exported-p3b-recipe-fix-344367fb313c46899d9db36af3e50ab4/f5_regression/f5_regression.log` |
| Static | Preserve repository contracts | Foundation validator reports 11 blocks, 20 items, 15 recipes; 29/29 unit tests pass including optional recipe-priority type rejection | PASS | command output recorded during this checkpoint |
| Owner | Ultrawide graphical behavior and feel | Not yet run | NOT RUN | owner playtest requested |

LIMITATIONS/FAILURES:

- One raider and one prototype core only. No wave director, multiple attackers, player aggro/health, final core fiction, rewards, sound, animation or balance.
- Castle stone and castle-kit entities remain deliberately immune to the basic raider. Damageable voxel-region aggregation and real siege-unit attacks are not implemented.
- Existing ballista/catapult work remains outside this slice; the accepted practice drill is preserved separately.
- Visuals are original code-native prototype geometry and labels, not final artwork.
- The original T66 crafted by stable ID and therefore failed to prove the player-visible recipe path. Tony found the discrepancy; the gate now opens and inspects the actual modal and has a separate rendered check.
- The pinned executable reports a non-blocking Windows certificate-store warning inside the restricted agent session. Gameplay and all final gate records complete with exit code 0.

NEXT:

Tony tests the current exported build at 3440×1440. Record owner acceptance or exact correction evidence before activating another slice.

GIT/REPRODUCIBILITY:

- Repo, branch, commit, worktree: `D:\CODEX\Craft_and_Defend`; `feature/p3-core-defense`; source `188bf4d6606d20491a0e5fcb387169522e67f91b`; game tree `9a50c2158abb3bb71093b919a985ed7f955a892c`; `D:\CODEX\Craft_and_Defend\worktrees\p3-core-defense`.
- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`, `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`; unchanged by P3B.
- OS / CPU / GPU / RAM / resolution / renderer: Windows 11 Pro 10.0.26200; AMD Ryzen 9 7900X3D; NVIDIA RTX 5090 driver 610.88; 64 GB; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine executable version and SHA-256: `4.6.stable.custom_build.89cea1439`; extracted editor `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`; editor archive `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`.
- Export template version and SHA-256: Voxel Tools `1.6.0 Module` matching custom release template; extracted template `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`; archive `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`.
- Build artifact SHA-256: EXE `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `c44f83e6d4e9c8ef4d7a411afb321f85b66a1615c98f858654df203e4c53cc48`; built UTC `2026-09-13T14:22:02.2576057Z`.
- Commands, seed, world bounds, content version, save root: `tools/build_windows_f0.ps1`; diagnostic modes `phase1`, `recipe_visual`, `save`, `restore`, `visual`; seed `41026`; bounds min `(-32,-16,-64)`, size `(64,32,128)`; content `foundation-1`; final isolated root `artifacts/exported-p3b-recipe-fix-344367fb313c46899d9db36af3e50ab4`.
- Clean-process restart and editor-closed export tested: yes. No `godot.windows.editor.x86_64` process existed before the final exported gates; save and restore ran as distinct, serialized executable processes.

No merge, push or release was performed.
