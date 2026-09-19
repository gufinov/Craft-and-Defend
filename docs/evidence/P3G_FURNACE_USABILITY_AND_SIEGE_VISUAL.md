# Evidence — P3G Furnace usability and placed siege identity — 2026-09-14

STATUS: PASS — matching Windows export, T93–T98, rendered inspection and affected regressions pass; owner ultrawide playtest pending

> Historical evidence note: this records the original P3G 1:1 loading behavior and remains valid for that commit. P3H supersedes only the fuel ratio with one Coal to three operations; see the current status and P3H evidence for active behavior.

DONE:

- Added maximum-legal-amount Shift+Click transfer in Furnace/inventory surfaces while retaining drag, split and one-item gestures.
- Added a reversible 0–64 Furnace auto-load target that fills each ingredient independently from available material.
- Added live per-item progress, retained Output, and automatic continuation through already-loaded complete batches.
- Allowed only the active Furnace appliance clock to advance while its modal keeps world simulation paused.
- Replaced the placed Catapult's generic boxes with an original detailed low-poly prototype.
- Added `TEST_P3G_FURNACE_USABILITY.cmd`.

EXPECT:

Shift+Click Ore or Coal to move it into the proper Furnace slot and Shift+Click a Furnace stack to return it. Choosing Iron Ingot enables Auto-load; setting 15 with 15 Ore/10 Coal stages 15/10. Start once and watch one progress bar reset for each retained ingot. The world remains paused behind the panel. A placed Catapult is visibly a wheeled siege engine.

TEST:

| Test ID | Result | Evidence |
|---|---|---|
| T93 | Maximum legal amount transfers both directions | PASS — a 4-item partial fill capped the Furnace at 64; all 64 returned and total remained 70 | `manual-p3g-furnace-61759051/gate` |
| T94 | 15 Ore/10 Coal loads 15/10 and safely lowers to 4/4 | PASS — exact totals conserved and reported limit remained 15 | same gate root |
| T95 | Per-item progress and sequential reset | PASS — 50% at 2.5s, Output 1, next job reset to 0% | same gate root |
| T96 | Furnace advances in open modal while world stays paused | PASS — live bar reached 50%, completion retained Output and next item began | same gate root |
| T97 | Detailed placed Catapult | PASS — 14 runtime parts including four named wheels | same gate root |
| T98 | Exported Furnace/Catapult presentation | PASS — both 1280×720 images generated and inspected | `manual-p3g-furnace-61759051/visual` |
| Static | Catalogs, docs and launcher remain valid | PASS — 11 blocks, 26 items, 21 recipes, 102 links; 38/38 Python tests | final validation |
| Regression | Existing Furnace and held/block catalog behavior remains green | PASS — exported P3E T84–T89 and P3F T90–T92 | roots below |
| Windows export | Current committed game tree runs from the pinned custom template | PASS — source `7b88c7b...`, game tree `6ed036e...` | build manifest |

LIMITATIONS/FAILURES:

- Owner ultrawide gameplay remains required. Automated checks do not replace manual feel/readability judgment.
- The engine emits a non-blocking certificate-store warning in restricted runs.

NEXT:

Tony should play at 3440×1440 through `START_GAME.cmd`, exercise manual/Shift/auto-load flows, watch several sequential items, collect Output and inspect a placed Catapult. Correct any owner-reported issue before promotion.

GIT/REPRODUCIBILITY:

- Active worktree: `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`; branch `feature/p3d-tools-world-feedback`; implementation commit `7b88c7be5a7247efb5e730934dcd65c8a02e7ca0`.
- Canonical main remained `c085c013d39b2b64321ea6c5a696b96fe2efd45c`; unchanged.
- Game tree `6ed036e4a84bfc07bbdafb9b2e78d5b9477b8cb7`; exported PCK SHA-256 `aba9b47bfbc09799cfdd84268f4aa1bad9ce5bde8145b7c2f01a2dbc010521d9`; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`.
- Inspected image hashes: Furnace `41e291f17e63165a67f835f668e046134e949c6e51512e631fc42cfcc2792031`; Catapult `44ccdbcfc84452a4028f0195c5f1a3f4f56d191d73f99216fb74a71058cd4bf0`.
- Final roots: `artifacts/manual-p3g-furnace-61759051`, `artifacts/manual-p3e-furnace-642028750`, `artifacts/manual-p3f-presentation-650513296`.
- No Godot process remained after verification.
- No merge, push or release authorized or performed.
