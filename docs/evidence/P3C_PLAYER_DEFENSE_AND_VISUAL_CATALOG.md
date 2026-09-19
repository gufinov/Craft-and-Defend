# Evidence — P3C player defense and visual catalog — 2026-09-13

STATUS: PASS — matching Windows export and automated presentation/runtime/persistence/regression gates pass; owner ultrawide playtest pending

DONE:

- Replaced the vertical Workbench recipe list with a deterministic 12-card, four-column icon catalog, search and Previous/Next paging.
- Added an original 1536×1024 item atlas whose stable regions cover all 25 registered items; inventory, crafting and live held slots render the icons and counts.
- Added validated Workbench recipes for Iron Sword, Ballista Bolts, Stone Shot, Ballista and Catapult.
- Added enemy-first sword input with bounded reach, damage and cooldown.
- Added 2×2 Ballista placement on terrain or the typed light-siege tower mount, direct line-of-sight gating and a visible bolt.
- Added 2×2 terrain-mounted Catapult placement, 8–34 m range gating, sampled clear ballistic arc and a visible stone shot.
- Persisted stable placed-siege identity, finite ammunition and cooldown in the existing atomic checkpoint envelope.
- Added the double-click `TEST_P3C_PLAYER_DEFENSE.cmd` exported-game gate.

EXPECT:

The candidate makes inventory and recipes visually scannable while providing the first direct player defense and two materially different player-built defenses against the one established P3B raider. It does not claim the later campaign, wave, armor or reload systems.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T72 | Every registered item has stable visual identity | 25 registered items resolved non-null atlas regions | PASS | final phase1 log/result JSON |
| T73 | Fixed icon cards, bounded paging and search | Workbench rendered 12 cards on Page 1/2, advanced to Page 2/2 and reduced `catapult` search to one selected card | PASS | final phase1 log/result JSON |
| T74 | Sword hit/miss/cooldown/victory is atomic | Clear hit reduced 20→13; immediate retry returned `MELEE_COOLDOWN`; off-axis swing returned `SWORD_MISS`; bounded later hits produced `WON` | PASS | final phase1 log/result JSON |
| T75 | Ballista supports ground/socket and requires line of sight | Terrain and tower placements passed; blocked ray retained 8 bolts; clear shot used one and reduced raider 20→14 | PASS | final phase1 log/result JSON |
| T76 | Catapult enforces range and clear arc | 2 m and 40 m targets were rejected; one clear sampled arc used one of five shots and reduced raider 14→5 | PASS | final phase1 log/result JSON |
| T77 | Siege/inventory survive atomic save and separate-process Continue | 24,625-byte checkpoint completed in 45 ms; a second exported process restored one sword, Ballista 7/1.5 s and Catapult 4/3.2 s | PASS | final persistence `save.log`, `restore.log`, checkpoint |
| T78 | Rendered card content is usable at 1280×720 | Image is 1280×720; all 12 children are populated icon/name/status cards; page reports 1/2 | PASS | final `visual/p3c-visual-catalog.png`, `visual.log` |
| Static | Validate new contracts and negative cases | 11 blocks, 25 items, 20 recipes; 33/33 unit tests pass, including invalid weapon, siege range and mount rejection | PASS | final local commands |
| Regression | Preserve accepted crafting and defense | P3B, P3 and F5 automation all pass from the final matching export | PASS | final regression root logs |
| Windows export | Matching custom release template with editor closed | Export succeeded and the one-click test accepted its provenance before all exported gates | PASS | build manifest, final manual test output |

Evidence locations are under `artifacts/manual-p3c-player-defense-2245022082`: `phase1/phase1.log`, `phase1/p3c_player_defense_results.json`, `persistence/save.log`, `persistence/restore.log`, checkpoint files, `visual/visual.log`, and `visual/p3c-visual-catalog.png`. Final regression logs are under `artifacts/exported-p3c-final-regression-7063fdc1f1b0453aa578c0d2ff4adc8b`.

LIMITATIONS/FAILURES:

- The only acquired target is the active P3B core raider. There is no player health/aggro, wave director, multiple enemies, manual siege aiming, crews, drops or campaign loop.
- Devices receive construction-provided finite ammunition. Bolt and shot recipes exist, but no reload action/UI consumes them yet.
- Armor remains reserved UI with no stats. The generated atlas is original prototype art, not final production artwork.
- Automated visual evidence is 1280×720; Tony's 3440×1440 gameplay/readability acceptance is pending.
- A first local render caught blank recipe-card content caused by pre-`_ready` configuration. The card now retains pending configuration, and T78 requires 12 populated cards rather than only 12 child nodes.
- One editor-only concurrent parse attempt hit a native custom-build crash before logging; actual runtime script loading, matching export and all final gates pass. Restricted headless runs also emit the known non-blocking certificate-store warning.

NEXT:

Tony should play the exported candidate at ultrawide resolution, craft/equip the sword, place both siege devices, start the core defense and judge readability/feedback. Correct any owner-found issue before P3C acceptance or promotion. Reloading and broader combat remain separate later work.

GIT/REPRODUCIBILITY:

- Repo, branch, commit, worktree: `D:\CODEX\Craft_and_Defend`; `feature/p3c-player-defense-ui`; export source `5ad176bb86c789bbbb476fc47111487b439e5a55`; game tree `458502d2bf0efbed980757b2609fc078566c778f`; `D:\CODEX\Craft_and_Defend\worktrees\p3c-player-defense-ui`.
- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`, `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`; unchanged.
- OS / CPU / GPU / RAM / resolution / renderer: Windows 11 Pro 10.0.26200; AMD Ryzen 9 7900X3D; NVIDIA RTX 5090 driver 610.88; 64 GB; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine executable version and SHA-256: `4.6.stable.custom_build.89cea1439`; extracted editor `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`; editor archive `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`.
- Export template version and SHA-256: Voxel Tools `1.6.0 Module`; extracted template `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`; archive `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`.
- Generated atlas SHA-256: `46fe4e30026f123cf5d008d82e88014f248dd688c6614bb530339f8ae28a3664`; original project-directed art, no third-party game asset reference supplied.
- Build artifact SHA-256: EXE `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `69052e9cb41f8d20e7b6f2a2c0e1c3e59df07eb0a87ae65b1a8eb60b857ef1fd`; built UTC `2026-09-13T15:39:54.8285542Z`.
- Commands, seed, world bounds, content version, save root: `tools/build_windows_f0.ps1`; `TEST_P3C_PLAYER_DEFENSE.cmd`; diagnostic modes `phase1`, `save`, `restore`, `visual`; seed `41026`; bounds min `(-32,-16,-64)`, size `(64,32,128)`; content `foundation-1`; final root `artifacts/manual-p3c-player-defense-2245022082`.
- Clean-process restart and editor-closed export tested: yes. Save and Continue ran as separate serialized exported processes; no Godot editor process existed during the final export/runtime gates.

No merge, push or release was performed.
