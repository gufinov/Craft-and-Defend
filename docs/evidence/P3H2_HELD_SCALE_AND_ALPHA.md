# Evidence — P3H.2 held scale, strike travel and unified alpha art — 2026-09-15

**STATUS:** CANDIDATE PASS / OWNER ULTRAWIDE PLAYTEST PENDING.

**DONE:** Unified recipe, inventory and held references on one versioned RGBA atlas while preserving all accepted designs and earlier assets. Picks, Wood Axe and Iron Sword now share one 0.00340 lower-right tool frame. Their use presentation sweeps 1.45 radians and travels left/up before returning. All low-held items use 0.00340—twice the former 0.00170—and a higher anchor, with a bounded placement nudge rather than the tool swing. Combat and inventory authority are unchanged.

**EXPECT:** The Sword/Picks/Axe appear at the marked-up scale and approximate position, the visible strike crosses toward center, and held blocks/stations are at least twice their former size without dropping behind the hotbar. Every active catalog cutout has genuine alpha rather than a baked background.

**TEST:** `TEST_P3F_PRESENTATION.cmd` passed from the provenance-matched Windows export. T90 preserved recipe order. Strengthened T91 verified all 26 references, one 1536×1024 RGBA runtime texture with alpha-zero corner, filter-clipped safe regions, 0.00340 tool/low scales, raised anchors, a 1.45-radian sweep and all voxel faces. T92 rendered eight held identities; T103 rendered both Workbench pages; T104 rendered ready Sword, active sweep and Furnace scale. `TEST_P3D_USABILITY.cmd` then passed T79–T83, including held Axe, block/ghost presentation and unchanged gathering/placement behavior. Static validation passed (11 blocks, 26 items, 21 recipes, 112 links); Python tests passed 40/40; diff check passed.

Visual inspection passed for:

- `artifacts/manual-p3f-presentation-3273310838/visual/p3h2-held-scale-and-swing.png` — SHA-256 `aa0eb1ea38b29b48ead936d08bf5dc5ace64610d477195b8803ee06df8d09b75`
- `artifacts/manual-p3f-presentation-3273310838/visual/p3f-held-item-contact-sheet.png` — SHA-256 `6f6849c34a041095abe26ae323ab7ec047e199fdd3f214f8bf6af9f969cdfdc4`
- Workbench page 1 / page 2 — SHA-256 `2d4448715bc49e8f716d05e154ca079c4157af62ccab6d8fd01f72bfba2e9657` / `2da946492da43b542e3d048c6a0f8488db684c09912b4b8d0674a93c3aa5c592`
- P3D held Axe / held Dirt block — SHA-256 `ed45cecf21af847b8ce29fea136a037d8c3970afce7b1b5f533993f02938e49e` / `1b706a5ba4966073f62cf04d956e7c17e786a16b09947ebcab26fb0002fd3b7c`

**LIMITATIONS/FAILURES:** Exact ultrawide feel requires Tony's graphical test. The cutouts are prototype sprites without visible hands, skeletal rigging or bespoke poses. Two built-in image-generation attempts kept the design but returned RGB files with baked checker pixels and were rejected; neither is committed or active. The accepted P3H.2 atlas is a non-destructive versioned copy of the already verified RGBA held source. One optional dirty-tree editor headless launch crashed before producing a log; it is not claimed as evidence. The clean release export and both required exported test paths passed. Restricted runs retain the known non-blocking certificate-store warning.

**NEXT:** Owner ultrawide playtest of ready/use Sword, Picks and Axe plus low-held blocks/stations/siege. If accepted, proceed to the separately bounded P3I storage-chest slice.

**GIT/REPRODUCIBILITY:** Worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`; branch `feature/p3d-tools-world-feedback`; implementation commit `ecfb3cca23e2f2a4be49ba93308f1a03eace54c8`; game tree `3c4a890d621a30d098813aa1d367e7ce59c99ec5`. Export EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `e59799f01b0cf6f23418bb0268f0b12fa25861a7939b95174d82f6ecf68e52f1`. Evidence roots are `artifacts/manual-p3f-presentation-3273310838` and `artifacts/manual-p3d-usability-9925539`. No merge, push or release was performed.
