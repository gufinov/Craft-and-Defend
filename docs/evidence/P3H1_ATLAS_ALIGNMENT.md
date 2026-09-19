# P3H.1 item atlas and held framing evidence

Recorded: 2026-09-14

**STATUS:** CANDIDATE PASS / OWNER ULTRAWIDE PLAYTEST PENDING.

**DONE:** Replaced the misaligned recipe/held atlas pair with non-destructive P3H.1 successors, kept the stable 24-cell item map, filter-clipped every `AtlasTexture`, isolated the third-row cards from bottom-row artwork and gave the six long bottom-row silhouettes a transparent recovery region. Recipe cards now clip their contents. Raised and low-held presentation anchors were lowered and reduced slightly. Added Workbench page-one/page-two screenshots to the existing presentation diagnostic. Recorded small and large persistent storage chests as the next bounded P3I slice; no chest capacity or automatic pairing rule was invented.

**EXPECT:** Workbench, Furnace, castle-piece, gate, sword, axe, Ballista and Catapult icons remain inside their own cards. No card shows part of the icon below it. The Iron Sword is complete in the catalog and first-person view. Held tools remain inside the viewport above the hotbar.

**TEST:** `TEST_P3F_PRESENTATION.cmd` PASS from the provenance-matched Windows export. T90 retained basic-to-advanced recipe order. Strengthened T91 resolved all 26 item identities, validated filter clipping and exact isolated source regions, and confirmed the raised held anchor. T92 rendered eight representative held identities. T103 rendered both 1280×720 Workbench pages. All three images were visually inspected: there are no neighboring fragments and the bottom-row gate, sword, axe, Ballista and Catapult are complete. Static validation PASS (11 blocks, 26 items, 21 recipes); Python tests PASS 40/40; diff check clean.

**LIMITATIONS/FAILURES:** The source is game-ready prototype raster art rather than final modeled equipment. Bottom-row catalog items use their transparent atlas companion while earlier rows retain the warm icon-card background, so final art direction can still unify card backgrounds later. The Godot Windows runtime emits a non-blocking certificate-store warning in the restricted diagnostic. Owner ultrawide gameplay remains required.

**NEXT:** Tony should open the Workbench at ultrawide resolution, inspect both pages, then hold the Iron Sword, Wood Axe, Ballista and Catapult. If accepted, P3I should implement small and large storage chests with persistent contents and lossless familiar stack transfers; capacities, footprints and recipes remain the bounded playtest decision.

**GIT/REPRODUCIBILITY:** Worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`; branch `feature/p3d-tools-world-feedback`; implementation commit `55650a6bb919552e23f5c553b0701072849b0ca2`; game tree `307dcea937d1193d9c6784c5d9259312f9773d5e`. Export EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `e09967554471943a9fe3a87a804470985d18b84333868490f9eeddf8920cb1a9`. Evidence root: `artifacts/manual-p3f-presentation-839420725`. Contact sheet SHA-256 `41a4b8ba4aa88dd9b8265609c680904eb70576904eedd7d16b1febb07d41a5df`; Workbench pages `4db44245846d9d81a1182cdbc8ff99bfffa5a2b35932195996ef2dbf97bf70f3` and `96e12ca6fe6d6e2f57375fb25bda0e0c0435cd70160d71e3210a50304eec56d1`. The two exact image-generation prompts, methods, hashes and preserved source paths are recorded beside the assets. No merge, push or release was performed.
