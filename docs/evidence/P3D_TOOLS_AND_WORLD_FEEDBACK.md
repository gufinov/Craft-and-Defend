# Evidence — P3D tools and world feedback — 2026-09-13

STATUS: PASS — matching Windows export and automated runtime/render/regression gates pass; owner ultrawide playtest pending

DONE:

- Added exact atomic Shift+Click five-batch crafting for immediate recipes; Furnace processing remains single-job.
- Added persistent camera-relative held models for blocks, picks, Wood Axe, Iron Sword and fallback carried items.
- Added green/red block placement ghosts using the same non-mutating validation as committing placement.
- Added a validated Wood Axe item/recipe, distinct atlas icon and bounded atomic vertical-tree felling.
- Added a visible marker tied to the unchanged fixed iron vein and explicit “DIG 2 BLOCKS” direction.
- Added the double-click `TEST_P3D_USABILITY.cmd` exported-game gate.

EXPECT:

The candidate reduces repetitive craft clicks, makes selected tools/building material visible during play, previews block placement before committing, gives tree harvesting a purpose-built starter tool, and makes the already-existing starter iron discoverable without changing saved terrain identity.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T79 | Shift+Click is exactly five atomic batches | Five Logs became 20 Planks in one revision; four Logs returned `INSUFFICIENT_INPUT` with identical snapshot | PASS | `manual-p3d-usability-49982156/phase1` log/JSON |
| T80 | Active item is visible; block held lower | Axe rendered three model parts at y=-0.29; Dirt rendered one block at y=-0.48 and tracked selected identity | PASS | phase1 log/JSON and rendered images |
| T81 | Axe fells bounded vertical trunk once | Four authored log cells became air and four Logs entered inventory in one transaction | PASS | phase1 log/JSON |
| T82 | Preview and iron cue reflect real world truth | Dirt preview returned valid/block/voxel 2; marker says `DIG 2 BLOCKS`; cell (-8,-4,35) resolved iron voxel 7 | PASS | phase1 log/JSON |
| T83 | Rendered presentation is visible at 1280×720 | Axe/marker and held Dirt/green ghost images were written and visually inspected | PASS | two PNGs under final/manual visual roots |
| Static | Contracts and rejection tests pass | 11 blocks, 26 items, 21 recipes; 35/35 unit tests | PASS | final Python commands |
| Regression | Accepted crafting/combat/build behavior remains green | P3C T72–T77, P3B T66–T69 and F5 T31/T33/T35/T36 pass from final export | PASS | `final-p3c-regression-8d50e0f`, `final-p3b-regression-8d50e0f`, `final-f5-regression-8d50e0f` |
| Windows export | Matching custom release template with editor closed | Provenance check accepted game tree `427edf8...`; phase and visible-render processes passed | PASS | build manifest and one-click output |

Final one-click root: `artifacts/manual-p3d-usability-49982156`. Its independently inspected renders are `visual/p3d-held-axe-iron-marker.png` SHA-256 `ac63ead780afbd999f76f0fb599515e9cfa063600861dd0b1f3486af3dffd1fa` and `visual/p3d-held-block-placement-ghost.png` SHA-256 `b5eb8b276d33d9237a41f012583a2d394c1fef9d53e4f32731c86e38672c0090`.

LIMITATIONS/FAILURES:

- The visuals are prototype geometric forms and original atlas art, not final animated character rigs or production assets.
- Axe felling is intentionally limited to six vertically connected logs. It does not remove branches or flood-fill structures.
- The marker covers only the guaranteed starter vein; procedural ore remains exploration/mining content.
- A first packaged diagnostic run exposed GDScript type-inference parse errors in the new held-view/diagnostic scripts. Explicit types corrected them at checkpoint `f7d1e24`; all final packaged runs pass.
- The pinned build emits a non-blocking Windows certificate-store warning in restricted runs. No Godot editor process was used for final runtime gates.

NEXT:

Tony should play at 3440×1440, judge held-item scale/position and ghost contrast, verify Shift+Click with real inventory, craft/use the Wood Axe, and follow the marker to mine iron with a Stone Pick. Correct any owner-reported issue before promotion.

GIT/REPRODUCIBILITY:

- Repo, branch, commit, worktree: `D:\CODEX\Craft_and_Defend`; `feature/p3d-tools-world-feedback`; implementation/export source `8d50e0f56650a981134a48ea0932989be49be9bf`; game tree `427edf8d76aea9bcc612d992b546fc1ae9b606fb`; `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`.
- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`, `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`; unchanged.
- OS / CPU / GPU / RAM / resolution / renderer: Windows 11 Pro 10.0.26200; AMD Ryzen 9 7900X3D; NVIDIA RTX 5090 driver 610.88; 64 GB; owner display 3440×1440; OpenGL 3.3 Compatibility.
- Engine/version/hashes: `4.6.stable.custom_build.89cea1439`; editor archive `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; extracted editor `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Template/version/hashes: Voxel Tools `1.6.0 Module`; release archive `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Build artifact SHA-256: EXE `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `a49b33ca50e11fb6983beb8d6e2cecec01235e5b65ed3320b8a51d6ec12c62ef`; built UTC `2026-09-13T16:57:46.6262329Z`.
- P3D atlas: `game/assets/ui/item_icon_atlas_p3d.png`; SHA-256 `46f46eb49e3ad8be4477a1ffdbae333860d60f2281800dfdd5c31c028ded85cf`; built-in image generation precise-object edit, prompt intent recorded in the P3D contract and atlas provenance file.
- Commands/data: `python tools/validate_foundation.py`; `python -m unittest discover -s tests -v`; `tools/start_game.ps1 -PrepareOnly`; `TEST_P3D_USABILITY.cmd`; seed `41026`; world bounds min `(-32,-16,-64)`, size `(64,32,128)`; content `foundation-1`.
- Clean-process restart and editor-closed export tested: yes for the matching export and isolated P3D phase/render processes. This slice does not change save schema; accepted P3C persistence remains covered by the final P3C regression.

No merge, push or release was performed.
