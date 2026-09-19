# Evidence — P3F recipe order and held visual catalog — 2026-09-14

STATUS: PASS — matching Windows export and affected automated runtime/render/regression gates pass; owner accepted 2026-09-14

DONE:

- Replaced temporary recipe prominence overrides with stable ascending `recipe_book_order` values across all 21 recipes.
- Ordered the Workbench catalog from Planks, Sticks and Workbench through wooden tools, stone/castle construction, iron equipment and siege content.
- Replaced the old mixed primitive/opaque-card first-person paths with one transparent catalog-derived held atlas covering all 26 registered item identities.
- Kept tools and the sword raised while blocks, materials, stations and siege pieces sit lower for carrying and placement.
- Corrected every Voxel Tools cube model to declare its authored 1×1 atlas geometry, so placed blocks render the complete masonry, ore, wood or terrain face rather than one nearly uniform texel region.
- Added `TEST_P3F_PRESENTATION.cmd` as the one-click exported diagnostic and render path.

EXPECT:

The Workbench opens with inexpensive fundamentals on its first page and advances toward castle, iron and siege content. Every hotbar item has a clean first-person identity consistent with the inventory catalog. Placed Castle Stone and the other voxel blocks show their authored face patterns.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T90 | Workbench order progresses from basic materials/tools to siege | Exact 20-entry sequence begins Planks, Sticks, Workbench and ends Ballista Bolt, Stone Shot, Ballista, Catapult | PASS | `manual-p3f-presentation-1258628327/gate/gate.log` and JSON |
| T91 | Every carried identity is transparent and every voxel cube maps its complete face | 26/26 held identities resolved; all ten non-air voxel models passed 1×1 atlas validation | PASS | same gate root |
| T92 | Player-facing presentation renders | Inspected 1920×720 contact sheet contains six clean views and a visibly textured placed Castle Stone | PASS | `manual-p3f-presentation-1258628327/visual/p3f-held-item-contact-sheet.png` |
| Static | Catalogs, tests and launchers remain valid | 11 blocks, 26 items, 21 ordered recipes; 37/37 Python tests; diff check clean | PASS | final source validation |
| Regression | Accepted player defense, held/placement and Furnace behavior remains green | P3C T72–T78, P3D T79–T83 and P3E T84–T89 pass from the matching export | PASS | final roots below |
| Windows export | Current game tree runs from the pinned custom release template | Manifest records source `b519d5c...`, game tree `8e0120d...`; exported P3F and affected gates pass | PASS | build manifest and final roots below |

Rendered contact sheet SHA-256: `f07423e7dbdca88552df8ed079f7b49a914e9129df550c830669fa9c9f3beb71`.

LIMITATIONS/FAILURES:

- Recipe discovery/unlock triggers and their save behavior are not yet defined; all current recipes remain visible. The ordering is ready for later discovery without claiming it exists now.
- The transparent held atlas is prototype first-person identity art, not final 3D models, hands, rigging or animation.
- Ballista Bolt and Stone Shot intentionally share the existing Stick and Stone identities until dedicated ammunition art is commissioned.
- The pinned build can emit a non-blocking Windows certificate-store warning in restricted runs.

NEXT:

Tony accepted the recipe progression and revised carried/placed identities after ultrawide playtesting. P3G now owns the reported Furnace usability and placed-Catapult presentation follow-up. Recipe discovery still needs its own accepted trigger and persistence contract before implementation.

GIT/REPRODUCIBILITY:

- Repo/worktree/branch/source: `D:\CODEX\Craft_and_Defend`; `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`; `feature/p3d-tools-world-feedback`; implementation commit `b519d5ca3f28df16216021dab7d76c90f3885de8`.
- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`, `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`; unchanged.
- Game tree: `8e0120d12cace7ddaab065e7c9f5a3ff499967f0`.
- Engine/runtime: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; Compatibility/OpenGL 3.3; NVIDIA RTX 5090 driver 610.88.
- Export: EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `437e75850fc2cccc15905fe976661d5c5adeed3a525099034c00a182c272703d`; built UTC `2026-09-14T10:19:40.4258492Z`.
- Generated held atlas: `game/assets/ui/held_item_atlas_p3f.png`; SHA-256 `7e5269144f0e7bdf3b8b29067472c7aafb0da52fb164068536c71806a6d721bc`; exact prompt, method and preserved source path are recorded beside the asset.
- Final roots: `artifacts/manual-p3f-presentation-1258628327`, `artifacts/manual-p3e-furnace-1272731757`, `artifacts/manual-p3d-usability-127508692`, `artifacts/manual-p3c-player-defense-127697646`.
- No Godot process remained after verification. No merge, push or release was performed.
