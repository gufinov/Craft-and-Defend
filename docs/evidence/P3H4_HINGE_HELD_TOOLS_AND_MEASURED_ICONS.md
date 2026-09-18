# Evidence — P3H.4 hinge-based held tools, measured icon regions and masonry skins — 2026-09-18

STATUS: PASS (candidate) — exported provenance-matched gates pass; owner playtest pending.

DONE: Implemented [the P3H.4 contract](../P3H4_HINGE_HELD_TOOLS_AND_MEASURED_ICONS.md). `tools/measure_item_atlas.py` produced `game/data/item_atlas_regions.json` (26 regions, α > 128, longest-run isolation). `ItemIconCatalog` resolves measured regions and pads card icons to centred squares. `HeldItemView` hinges the sprite's bottom-left corner in the lower-right of the view with per-class height normalisation and a counter-clockwise strike about the hinge. Furnace visual rebuilt in Castle Stone masonry with a stepped ember arch; Tower Platform parts textured with Castle Stone. `ContentRegistry` balance accessors typed `Variant` so the pinned editor runs headless diagnostics again. T80/T91 strengthened; `tests/test_item_atlas_regions.py` added.

EXPECT: Tools rest pointing north-east from a hand at the lower-right screen base and swing about that hand toward the crosshair. Stone Shot and Ballista Bolt are item-sized with no fragment of the other visible. Every inventory, hotbar, crafting and recipe icon is centred in its card at one visual size. Placed Furnace shows masonry with a glowing arch on its front face; Tower Platform shows Castle Stone.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | `validate_foundation` + unittest | 11 blocks, 26 items, 21 recipes, 118 links; 44/44 tests | PASS | this commit |
| Editor headless | P3F gate, P3F visual, P3D phase1 in the pinned editor on the working tree | T90/T91/T105; T92/T103/T104/T106; T79–T82 | PASS | `artifacts/dev-p3h4-*` |
| T90 | recipe progression order | unchanged order | PASS | `artifacts/manual-p3f-presentation-268251316/gate/gate.log` |
| T91 | 26 measured non-overlapping regions; bolt/shot isolated; hinge model; Sword 0.62 high, Stone Shot 0.46 high and < 0.6 wide; arc ≥ 1.2 rad | sword sprite 0.517×0.62; shot sprite 0.465×0.46; bolt region (154,98,785,698); shot region (1128,244,465,460) | PASS | same log |
| T105 | Gate Frame / Wall Walk Slab castle skin | textured, 14 + 2 parts | PASS | same log |
| T92 | eight-item held contact sheet | Pick, Sword, Axe hinge at the base pointing NE; Stick, Castle Stone, Gate Frame, Ballista, Catapult above the hotbar | PASS | `…/visual/p3f-held-item-contact-sheet.png` |
| T104 | ready / mid-swing / Furnace panels | sword rotates about the handle toward the crosshair; Furnace icon above the hotbar | PASS | `…/visual/p3h2-held-scale-and-swing.png` |
| T103 | Workbench pages, icons inside cards | both pages; icons centred and uniformly sized; Bolt and Stone Shot at item scale | PASS | `…/visual/p3f-workbench-page-1.png`, `-2.png` |
| T106 | rendered castle skins | gate and slab textured | PASS | `…/visual/p3h3-placed-castle-skins.png` |
| T79–T83 | P3D usability, exported | T80 now asserts the shared hand column with tools below placeables | PASS | `artifacts/manual-p3d-usability-2685121767` |
| T93–T98 | P3G furnace usability, exported | all pass; T98 frame shows the new furnace body at distance | PASS | `artifacts/manual-p3g-furnace-2694916539` |
| P3C, P3E, P3H suites | exported | NOT RUN this checkpoint | NOT RUN | — |
| Owner playtest | ultrawide hinge feel, close-up Furnace/Tower skins | pending | NOT RUN | — |

ROUND 2 (owner ultrawide playtest, same day): hand moved one block inward; Tab inventory tiles conformed to the crafting tiles. Editor headless: P3F gate T90/T91/T105 PASS (T91 hinge assertion given a 0.001 float32 tolerance), castle-kit `inventory` T47/T49 PASS, `inventory_ultrawide` T47/T48/T49 PASS with `artifacts/dev-p3h5-castle-kit-automation/p1-inventory-loadout-1720x720.png` showing square tiles with centred icons and `C1 · Dirt`-style captions, P3D phase1 T79–T82 PASS, P3F visual T92/T103/T104/T106 PASS. Exported round-2 results are appended below.

LIMITATIONS/FAILURES: The placed Furnace skin is only evidenced at distance and from the rear in T98; no automation renders a close-up of the front arch or the Tower Platform, so Tony's playtest is the visual acceptance for both. The hinge constants (`HINGE_RIGHT_FRACTION`, `TOOL_HINGE_DOWN_FRACTION`, `TOOL_SWING_ARC_RADIANS`) were tuned on 1280×720 renders; ultrawide clamps the hand to `HINGE_RIGHT_MAX` and may need a nudge. Held items remain camera-facing raster billboards. Running a `TEST_*.cmd` from a nested pwsh→cmd shell failed to locate `build_windows_f0.ps1` when a rebuild was required; the same rebuild succeeded when `start_game.ps1` was invoked directly and in Tony's own double-click run, so this is an invocation quirk of the automation host, not a launcher defect, and was not changed.

NEXT: Tony launches `START_GAME.cmd`, holds each tool and swings, holds Stone Shot and Ballista Bolt, opens the Workbench book, and walks up to a placed Furnace and Tower Platform. Then P3I (Furnace auto-processing), P3J (drag building), P4 (siege rework) per the backlog cards.

GIT/REPRODUCIBILITY:
- Repo, branch, commit, worktree: `gufinov/Craft-and-Defend`, `feature/p3d-tools-world-feedback`, implementation `1ff190d`, `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`
- OS / GPU / renderer: Windows 11 Pro 26200; RTX 5090; OpenGL Compatibility
- Engine: `4.6.stable.custom_build.89cea1439`, Voxel Tools 1.6.0 Module (pinned `D:\CODEX\_tools\GodotVoxel\4.6-1.6`)
- Export EXE SHA-256: `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2` (unchanged); PCK SHA-256: `31547340d943dc7c3195d0a2a85637cab8f14b8aaa572ad53ea7010997ba1681`
- Commands: `python tools/measure_item_atlas.py`; `python tools/validate_foundation.py`; `python -m unittest discover -s tests`; `powershell -File tools\start_game.ps1 -PrepareOnly`; `TEST_P3F_PRESENTATION.cmd`, `TEST_P3D_USABILITY.cmd`, `TEST_P3G_FURNACE_USABILITY.cmd` with `*_DIAGNOSTIC_NO_OPEN=1`
- Clean-process editor-closed export tested: yes (all three suites ran the exported executable)
