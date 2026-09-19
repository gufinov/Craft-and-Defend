# Current checkpoint — 2026-09-19 (baseline merged to `main`)

**STATUS:** **BASELINE. Owner authorised merging `feature/p3d-tools-world-feedback` to `main` on 2026-09-19.** Everything from F2 through P4a-1 (see the checkpoints below) is on `main` and pushed. The core-defense drill works as a baseline and needs more work later (owner statement); it is not being polished further before the next milestones. Claude is the implementing agent; a new developer can start from `main` with the README's reading order.

**DONE (since the previous checkpoint):** catapult modelled from the owner reference with a 2×4 footprint (`5bb8ac9`); siege motion — turntable facing, throw, wind-back, loaded stone, bucket muzzle (`ca7599f`, T118); diagnostics ignore focus-loss pauses (`098ceb1`); README and handoff refreshed for new developers.

**EXPECT:** `main\START_GAME.cmd` rebuilds the export once (provenance) and opens the playable slice described in the README.

**TEST:** Exported at `ca7599f` (PCK `903ddc26…`): `TEST_P3C` (T72–T78, T118) and `TEST_P3G` (T93–T98, T107, T114, T115) PASS; earlier the same day `TEST_P3D`, `TEST_P3F`, `TEST_P3K`, `TEST_P3E`, `TEST_P3H` PASS on their respective builds. Static PASS. Owner playtested P3H.4–P3J and the catapult; core-defense drill confirmed working as a baseline.

**LIMITATIONS/FAILURES:** Held items are still 2D billboards (3D proposal in the design direction §10). Blueprints have no player entry point yet (P3K slice 2). Siege supply, weapon panel and fire are cards (P4a-2..4). Ballista has no draw/release animation. The 2-cell ammo trough is not yet part of the siege footprint.

**NEXT:** P3K slice 2 (Blueprints in the B menu) or P4a-2 weapon panel — owner's choice; then P4a-3 supply/auto-reload, P4a-4 flame shot and fire, 3D held items.

**GIT/REPRODUCIBILITY:** `main` = merge of `feature/p3d-tools-world-feedback` (`ca7599f` + doc refresh), pushed to `origin/main`. Superseded worktrees removed (branches kept). Engine `4.6.stable.custom_build.89cea1439`, Voxel Tools 1.6.0 Module; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`.

---

## Previous checkpoint — 2026-09-18 (playtest round 4)

**STATUS:** **ROUND-5 PLAYTEST CORRECTIONS — CANDIDATE PASS ON THE EXPORT (PCK `9935113a…`, commit `bcbd6c6`); OWNER RE-PLAYTEST PENDING.** Round 5: axe back to north-east, hand lower and further left, Tab-inventory message moved into the header, hold-to-repeat strikes. Owner confirmed the rest of round 4. Open design question recorded: held items are 2D billboards of the icon art while placed machines are 3D; proposal to make held items 3D box-part models is in the design direction. Axe mirrored toward the crosshair (per-item mirror, no art regeneration); held blocks smaller and above the hotbar; Shift-held drag builds upward; square hotbar tiles with a bottom margin; item captions without slot numbers; windowed frame fitted inside the usable screen (the real cause of the clipped hotbar); P3K stamp registry, save envelope and socket snapping. Work split between the integrator and a subagent (hotbar/captions), reviewed and export-verified. No merge to `main`, no release.

**DONE:** `d520f0e` axe mirror, low-held position, Shift vertical drag (T108, T91); `e654a53` P3K stamps/sockets (T117); `4458500` (subagent) square 80 px hotbar tiles anchored 14 px above the bottom, captions name-only, Tab hotbar key labels top-left (T83, T83_HOTBAR_ULTRAWIDE); `ffc2722` windowed client size clamped to the screen's usable rectangle; `18b1001` P3K slice-2 contract. See [P3J](P3J_DRAG_BUILDING.md), [P3H.4](P3H4_HINGE_HELD_TOOLS_AND_MEASURED_ICONS.md), [P3K](P3K_BLUEPRINTS.md).

**EXPECT:** Axe blade faces the crosshair. Blocks held lower-right, fully visible above the hotbar. Drag sideways, hold Shift, raise the aim → wall rises even with the aim on the ground. Nine square hotbar tiles with a gap below them at any aspect. Tiles show names and ×n only. A windowed game never extends under the taskbar. Blueprints (service-level) snap to stamped sockets and survive save/load.

**TEST:** Static PASS (49/49). Exported on PCK `f0840c9f…`: `TEST_P3D` (T79–T83, T83_HOTBAR_ULTRAWIDE, T108, T109), `TEST_P3F` (T90–T92, T103–T106), `TEST_P3G` (T93–T98, T107, T114, T115), `TEST_P3K` (T110–T113, T117), `TEST_P3C` (T72–T78) PASS. Editor rendered: F1 visual T18 suite PASS after the window-fit change. Owner playtest pending.

**LIMITATIONS/FAILURES:** The window-fit change is verified by the F1 display suite and by reasoning, not on the owner's 3440×1440 desktop; if the hotbar still clips there, re-check `settings_store._apply_display`. Blueprint entry point still absent (slice 2 next).

**NEXT:** P3K slice 2 — Blueprints column in the B menu, W/R rotation, right-click stamp, socket-snapped ghost — then parapet block and Tower Platform retirement.

**GIT/REPRODUCIBILITY:** Worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, HEAD after this commit, clean, pushed. Canonical `main` unchanged at `c085c013…`. Engine `4.6.stable.custom_build.89cea1439`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `f0840c9f76504916904316dc6797c822349e7629a64e827adf41e7d0286dc08d`. Evidence roots `artifacts/manual-p3d-usability-1830826926`, `artifacts/manual-p3f-presentation-183313860`, `artifacts/manual-p3g-furnace-1835724312`, `artifacts/manual-p3k-blueprints-1837623266`, `artifacts/manual-p3c-player-defense-1839622221`.

---

## Previous checkpoint — 2026-09-18 (furnace round 3 + P3K slice 1)

**STATUS:** **FURNACE ROUND 3 AND P3K BLUEPRINTS SLICE 1 — CANDIDATE PASS ON THE MERGED EXPORT; OWNER PLAYTEST PENDING.** Furnace: the lit Coal stays until the last job it funds completes; the panel fits 720; select-then-add works without the recipe book (delegated to a subagent, reviewed and verified by the integrator). P3K: blueprint catalogue and stamp engine for castle pieces made of ordinary blocks, with sockets and diagnostics; no player entry point yet. No merge to `main`, no release.

**DONE:** Furnace round 3 (`ca2ac0b`, `5cba9e2`, `1f7502a`): `furnace_fuel_burning` flag, Coal released on `JOB_COMPLETED`, additive Load ×1/×5, gold-highlight selection, inferred recipe, T114/T115. P3K slice 1 (`feature/p3k-blueprints`, merged `c323630`): `tools/generate_blueprints.py` → `contracts/blueprints.json` + runtime mirror (foundation_4, tower_segment_4, cap_4/6/8, wall_4 with top/side sockets); `InteractionService` blueprint planning/commit generalised from P3J with fixpoint support ordering and per-type budgets; per-cell ghost textures; `P3KBlueprintAutomation` T110–T113; `TEST_P3K_BLUEPRINTS.cmd`; `tests/test_blueprints.py`. See [P3I evidence](evidence/P3I_FURNACE_AUTO_PROCESSING.md) and [P3K evidence](evidence/P3K_BLUEPRINTS.md).

**EXPECT:** Furnace: click ore → gold highlight; click Raw Input +1 (Shift +5); Load ×1 works with no recipe chosen; the Coal stays in its slot until the third bar completes. Drag building extends into open sky. Blueprints are service-level only (diagnostics stamp a tower); the player cannot select one yet.

**TEST:** Static PASS (140 links; 45/45). Exported on the merged build (PCK `957aebc8…`): `TEST_P3K` T110–T113, `TEST_P3D` T79–T83/T108/T109, `TEST_P3G` T93–T98/T107/T114/T115, `TEST_P3F` T90–T92/T103–T106 PASS; `TEST_P3E` and `TEST_P3H` PASS on the pre-merge furnace build `4eac9a46…`. Owner playtest pending.

**LIMITATIONS/FAILURES:** No blueprint entry point yet (slice 2). Spiral steps are jumpable full blocks, not stair entities. No parapet auto-connect block. Load ×1 is additive (never returns items) — deliberate change from the target-based slider semantics. The furnace click gestures are covered by a real-click diagnostic (T115) at 1280×720; ultrawide is owner-verified.

**NEXT:** Tony playtests furnace gestures and drag-to-sky. Then P3K slice 2: Blueprints page in the B menu with W/R rotation and right-click stamp, socket ghosting on look; then parapet block and Tower Platform retirement; then P4a siege on stamped caps.

**GIT/REPRODUCIBILITY:** Integration worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, HEAD after this commit, clean, pushed. Side branch `feature/p3k-blueprints` (worktree `worktrees\p3k-blueprints`) merged and pushed. Canonical `main` unchanged at `c085c013…`. Engine `4.6.stable.custom_build.89cea1439`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `957aebc87391fa49c7cbdf51432ff1cce508df8dba4fb8b432179e1ccba18e76`. Evidence roots `artifacts/manual-p3k-blueprints-1198625691`, `artifacts/manual-p3d-usability-1200524645`, `artifacts/manual-p3g-furnace-120281580`, `artifacts/manual-p3f-presentation-12048535`, `artifacts/manual-p3e-furnace-117316515`, `artifacts/manual-p3h-balance-1175416218`.

---

## Previous checkpoint — 2026-09-18 (P3I + P3J)

**STATUS:** **P3I FURNACE AUTO-PROCESSING AND P3J DRAG BUILDING — CANDIDATE PASS (ROUND 2 AFTER OWNER PLAYTEST); OWNER RE-PLAYTEST PENDING.** Round 2: the burning Coal now stays in the Fuel slot until burnt out; furnace +1/+5 click gestures and Load ×1/×5; drag building extends into open sky along the row's vertical plane; chained furnace jobs carry leftover time. Both owner-directed slices are implemented on the exported, provenance-matched build with new gate and render tests. The 2026-09-18 design decisions (one game in three tiers, loss as a pillar, blueprints stamp blocks with machines as entity exceptions, Market as core, growing province with a neglect leash) are locked in [the design direction](DESIGN_DIRECTION_2026-09-18.md). Claude is the implementing agent. No merge to `main`, no release.

**DONE:** P3I — idle Furnaces start themselves from deposited input and fuel (`WorkstationService._auto_start_idle_furnaces`), never while paused; the furnace button became **Load from Inventory**; T107. P3J — right-drag plans rows, columns and walls of the held block with support-first ordering, skips blocked cells, trims to stock, commits one world edit plus one inventory transaction with rollback, cancels on left-press; framed green/amber/red ghosts; T108/T109. Repaired the stale F2_KEYBIND_UI test. P3D visual checks now wait for the ghost. See [P3I evidence](evidence/P3I_FURNACE_AUTO_PROCESSING.md) and [P3J evidence](evidence/P3J_DRAG_BUILDING.md).

**EXPECT:** Drop ore and coal into a Furnace and walk away; ingots accumulate in Output. Hold dirt/stone/castle stone, right-press and drag along the ground for a row, upward for a column, both for a wall; release builds the green cells; left-click while holding right cancels. Held tools strike toward the crosshair and vanish down-left (P3H.4 round 3); Tab inventory tiles match the crafting screens.

**TEST:** Static PASS (131 links; 44/44). Exported: `TEST_P3G` (T93–T98, T107), `TEST_P3E` (T84–T89), `TEST_P3D` ×3 (T79–T83, T108, T109), `TEST_P3C` (T72–T78), `TEST_P3F` (T90–T92, T103–T106) PASS. Editor headless: F2 gate, F3 phase1, castle-kit phase1 PASS. Not re-run: P3H balance suite. Owner playtest of P3H.4/P3I/P3J pending.

**LIMITATIONS/FAILURES:** A plain right-click now places on release, not press. No post-build undo, no entity dragging. Furnace auto-start polls each idle furnace every tick (negligible with one recipe). Placed Furnace/Tower skins still lack a close-up render. The Tower Platform entity is slated to retire under P3K blueprints.

**NEXT:** Tony playtests. Then P3K (parapet auto-connect, blueprint model with sockets, first pieces) → P4a siege on stamped caps → P4b Market/gold → P4c army director.

**GIT/REPRODUCIBILITY:** Worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, HEAD after this commit, clean, tracking origin (pushed). Canonical `main` unchanged at `c085c013…`. Engine `4.6.stable.custom_build.89cea1439`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `f0c296b2832f8b4c719037152a6d93c5ff717691f03126180895fd5f6cd81ab7` (round 2, commit `620b368`). Evidence roots: `artifacts/manual-p3g-furnace-2406315692`, `artifacts/manual-p3h-balance-2408214646`, `artifacts/manual-p3d-usability-2410213601`, `artifacts/manual-p3e-furnace-2412212555`; round 1: `artifacts/manual-p3g-furnace-568724137`, `artifacts/manual-p3e-furnace-570723092`, `artifacts/manual-p3d-usability-883220165` (+2), `artifacts/manual-p3c-player-defense-851526145`.

---

## Previous checkpoint — 2026-09-18 (P3H.4)

**STATUS:** **P3H.4 HINGE HELD TOOLS / MEASURED ICONS / MASONRY SKINS — CANDIDATE PASS (ROUND 3); OWNER RE-PLAYTEST PENDING.** Round 3: the strike is now a keyframed path (toward the crosshair, whip down-left out of sight, rise back). Tony's wider vision (tower cap sizes, build wheel, gold economy/Foundry/Market, daily waves and breaching, food) is recorded in [the design direction](DESIGN_DIRECTION_2026-09-18.md) with proposals marked not-commissioned. Round 2 after Tony's ultrawide playtest: hand moved one block inward; Tab inventory tiles conformed to the crafting tiles Tony approved. Tony's playtest of the P3H.3 build reported wrong tool hinge and sweep, oversized ammunition with a bolt fragment beside the Stone Shot, off-centre card icons and unskinned Furnace/Tower Platform. All positioning defects traced to fixed cell geometry; they are now driven by measured art regions and a hand hinge. Four follow-up cards (P3I Furnace auto-processing, P3J drag building, P4 siege rework, plus the P3H.4 record) are in the backlog. Claude is the implementing agent from this checkpoint; no merge, push to `main` or release is authorized or performed.

**DONE:** `tools/measure_item_atlas.py` → `game/data/item_atlas_regions.json` (26 tight regions, guarded by `tests/test_item_atlas_regions.py`). `ItemIconCatalog` resolves measured regions and centres card icons in a padded square. `HeldItemView` hinges each item's bottom-left corner at a lower-right hand: tools rest north-east with the handle at the screen base and strike counter-clockwise about the hinge toward the crosshair; low items sit above the hotbar; sprite height is normalised per class so ammunition matches item scale. Furnace visual rebuilt in Castle Stone masonry with an ember arch; Tower Platform textured. `ContentRegistry` accessors typed so headless editor diagnostics run again. T80/T91 strengthened. See [the P3H.4 evidence](evidence/P3H4_HINGE_HELD_TOOLS_AND_MEASURED_ICONS.md).

**EXPECT:** Holding Sword, Picks or Axe shows the handle at the lower-right base pointing up-right; using it swings the head left through the crosshair region and back. Stone Shot and Ballista Bolt are item-sized with nothing else visible. Every icon is centred in its card. A placed Furnace is brick masonry with a glowing arch on its front; Tower Platform is Castle Stone.

**TEST:** Static PASS (118 links; 44/44). Editor headless P3F gate/visual and P3D phase1 PASS on the working tree. Exported provenance-matched `TEST_P3F_PRESENTATION.cmd` (T90–T92, T103–T106), `TEST_P3D_USABILITY.cmd` (T79–T83) and `TEST_P3G_FURNACE_USABILITY.cmd` (T93–T98) PASS. P3C, P3E and P3H suites not re-run. Owner playtest pending.

**LIMITATIONS/FAILURES:** Furnace front arch and Tower Platform skin are not rendered close-up by automation. Hinge constants were tuned at 1280×720; ultrawide may need a nudge. Held items remain raster billboards. A nested pwsh→cmd invocation of a `TEST_*.cmd` failed to find the rebuild script once; direct and double-click launches rebuild correctly and the launcher was not changed.

**NEXT:** Tony playtests the items above. Then P3I → P3J → P4 in backlog order.

**GIT/REPRODUCIBILITY:** Worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, implementation `1ff190d`, round 2 `67f0e8a`, round 3 `2415c6e`, plus documentation commits, tracking `origin/feature/p3d-tools-world-feedback`. Canonical `main` unchanged at `c085c013…`. Engine `4.6.stable.custom_build.89cea1439`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `54f822a3b530b6fc53bf4d3c2ee5e76a9c4452a6a86a2168175be60ab05c5909` (round 3). Evidence roots `artifacts/manual-p3f-presentation-137818283`, `artifacts/manual-p3d-usability-1380728734`, and earlier rounds `artifacts/manual-p3f-presentation-268251316`, `artifacts/manual-p3d-usability-2685121767`, `artifacts/manual-p3g-furnace-2694916539`.

---

## Previous checkpoint — 2026-09-18 (recovery)

**STATUS:** **P3H.3 WORK-IN-PROGRESS CHECKPOINTED; LAUNCHER AND RUNTIME GATE RECOVERED; OWNER PLAYTEST PENDING.** The previous Codex session ran out of tokens mid-P3H.3 and left the `game/` tree dirty, which made `START_GAME.cmd` and every `TEST_*.cmd` fail at the clean-tree provenance guard. A third-party audit by Claude committed that work as-is, restored one-click launch, pushed the branch to GitHub for the first time, and recorded findings in [the audit](AUDIT_2026-09-18.md). No merge to `main` and no release occurred.

**DONE:** Committed the P3H.3 candidate (`3a05452`): shared lower-right held base with inward-facing raised tools, dedicated true-alpha ammunition atlas, Castle Stone skins on Gate Frame and Wall Walk Slab, one Log per Axe use, wheel recipe paging, one-press Furnace Escape and red MISSING recipe cards. Added `safe.directory` for the project so Tony's account can use git in the sandbox-owned worktrees. Pushed `feature/p3d-tools-world-feedback` with upstream tracking. Wrote the audit with measured atlas-alignment data, code-quality findings and combat direction.

**EXPECT:** `START_GAME.cmd` in this worktree reports matching provenance and opens the P3H.3 candidate. Tools sit at the lower-right with the handle at the screen base and the head facing inward; Ballista Bolt and Stone Shot show their own art; placed Gate Frame and Wall Walk Slab use the Castle Stone face; the Axe removes one Log per swing; the mouse wheel pages the recipe book; Escape closes a Furnace in one press even with the search focused; recipes lacking materials show red cards.

**TEST:** Foundation validation PASS (11 blocks, 26 items, 21 recipes, 113 links). Python tests PASS 40/40. `start_game.ps1 -PrepareOnly` PASS after one rebuild with manifest `game_tree` = `HEAD:game`. Exported `TEST_P3F_PRESENTATION.cmd` PASS: T90, T91, T92, T103, T104, T105, T106 (`artifacts/manual-p3f-presentation-969719652`). P3C, P3D, P3E, P3G and P3H runtime suites were not re-run at this commit. Owner playtest not yet performed.

**LIMITATIONS/FAILURES:** The P3H.3 commit is a checkpoint of interrupted work, not an owner-accepted milestone; its evidence record has not been written. Canonical `main` documentation still describes F1 because promotion requires review. The ten superseded worktrees remain on disk. Held items remain camera-facing raster billboards anchored at their atlas-cell centre; the audit measures why icon and held positioning drift and proposes anchor metadata rather than further constant tuning. The launcher still refuses a dirty `game/` tree by design; relaxing that is an open proposal.

**NEXT:** Tony launches this worktree's `START_GAME.cmd` and playtests the P3H.3 items above at ultrawide. Then decide the audit proposals in order: launcher dirty-tree behaviour, worktree cleanup, promotion toward `main`, icon/held anchor metadata, defense-service consolidation before any wave/invasion card, `app.gd` split.

**GIT/REPRODUCIBILITY:** Worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`, HEAD `3a05452de91a3ea74c20f8572c674ff226ce6482` plus this documentation commit, clean, tracking `origin/feature/p3d-tools-world-feedback` (pushed). Canonical `main` unchanged at `c085c013d39b2b64321ea6c5a696b96fe2efd45c` local and remote. Game tree `cddb74a2bd16a26c24ffbb4a4cf22745a9e9c8ec`; engine `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `763591684d8618d1fe4b177ddca47ce736090af484d3209ac96fb29475da4e26`. Another machine can now clone the branch and rebuild from repository truth. No merge, release or publication performed.

---

## Previous checkpoint — 2026-09-15

**STATUS:** **P3H.2 HELD-SCALE / UNIFIED-ALPHA CANDIDATE PASS — OWNER ULTRAWIDE PLAYTEST PENDING.** The matching Windows export uses one true-alpha atlas for inventory, recipes and first-person references. Tools are enlarged and share one frame; their visual use has a broad strike arc. Low-held items are twice the prior scale and higher. P3G Furnace usability, P3H balance/fuel/controls and P3H.1 alignment remain passing candidates. No merge, push or release is authorized or performed.

**DONE:** Added the non-destructive `item_atlas_p3h2.png` successor from the verified RGBA P3H.1 source and removed the RGB atlas from the active runtime path. Named tool/low-held framing and motion constants now own presentation. Sword, all Picks and Wood Axe use 0.00340 scale at a common lower-right anchor and a 1.45-radian use sweep. Blocks, materials, stations and siege references use 0.00340—exactly twice P3H.1's 0.00170—at a higher anchor; they receive a short placement nudge instead of a weapon swing. T104 adds a ready/swing/Furnace render to the existing catalog and Workbench-page diagnostic.

**EXPECT:** Inventory and recipe cards show clean cutouts without baked card backgrounds. Iron Sword, Wood Axe and all Picks are approximately the marked-up sword size and location; using a tool visibly travels toward the center before returning. Blocks and stations are substantially larger, higher and remain above the hotbar. No combat damage, recovery, reach or hit timing changed.

**TEST:** Foundation validation PASS: 11 blocks, 26 items, 21 recipes and 112 local links. Python tests PASS 40/40. Provenance-matched exported T90, strengthened T91/T92/T103 and new T104 PASS. Exported P3D T79–T83 regression PASS. The two Workbench pages, eight-item held sheet, three-panel Sword/swing/Furnace comparison, Axe/iron-marker frame and held-block/ghost frame were visually inspected and are clean. See [the P3H.2 evidence record](evidence/P3H2_HELD_SCALE_AND_ALPHA.md).

**LIMITATIONS/FAILURES:** Owner ultrawide gameplay remains required for exact scale/feel. This remains camera-facing prototype raster art, not a hand/arm rig, modeled equipment or per-tool animation set. Two generated transparency candidates were correctly rejected because they baked checker pixels into RGB images; the active asset is the verified alpha source copy. An optional dirty-tree editor headless launch crashed before it could write a log and is not counted as evidence; the authoritative clean provenance-matched release gate passed. The pinned engine emits a non-blocking certificate-store warning in restricted runs. Storage chests remain planned, not implemented.

**NEXT:** Tony should launch the prepared build, hold Sword/Picks/Axe and use each, then hold a block, Workbench, Furnace, Ballista and Catapult at ultrawide resolution. If framing is accepted, P3I remains the next planned runtime slice: small and large persistent storage chests with lossless container transfers and separately playtested capacities/footprints.

**GIT/REPRODUCIBILITY:** Canonical checkout `D:\CODEX\Craft_and_Defend\main` remains on `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`. Active worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`, branch `feature/p3d-tools-world-feedback`; P3H.2 implementation commit `ecfb3cca23e2f2a4be49ba93308f1a03eace54c8`, game tree `3c4a890d621a30d098813aa1d367e7ce59c99ec5`. Engine `4.6.stable.custom_build.89cea1439`, Voxel Tools `1.6.0 Module`, Compatibility renderer. Export EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `e59799f01b0cf6f23418bb0268f0b12fa25861a7939b95174d82f6ecf68e52f1`. Final evidence roots: `artifacts/manual-p3f-presentation-3273310838` and `artifacts/manual-p3d-usability-9925539`. Exact alpha-source provenance and rejected generation attempts are recorded beside the asset. No merge, push or release performed.
