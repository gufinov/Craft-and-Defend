# Evidence — P3E furnace containers and visual identity — 2026-09-14

STATUS: PASS — matching Windows export and automated runtime/render/regression gates pass; owner ultrawide playtest pending

DONE:

- Replaced invisible Furnace output delivery with persistent station-owned Raw Input, Fuel and Output stacks.
- Completed Iron Ingots remain in Output until the player explicitly collects them; non-empty Furnaces refuse dismantling.
- Added whole-stack double-click transfer, larger-half right-click pickup, one-item right-click deposit and one-per-slot right-drag distribution.
- Persisted the cursor-held stack and prevented Inventory/Crafting close from discarding it when no return capacity exists.
- Kept manual hand/Workbench pattern recognition independent from recipe-book selection or search.
- Replaced unrelated plain station/tool primitives with detailed placed Workbench/Furnace forms and transparent held references for Workbench, Furnace, Stone Pick and Wood Axe.
- Added `TEST_P3E_FURNACE.cmd` as the one-click exported diagnostic path.

EXPECT:

The Furnace visibly owns its processing state. Double-click compatible inventory stacks to load it, close the modal so simulation advances, then reopen and collect the completed Output. Container gestures preserve exact counts. A known recipe can still be assembled manually without locating its card first.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T84 | Whole stacks enter separate Furnace input/fuel | 7 Iron Ore and 6 Coal transferred with inventory counts reaching zero | PASS | `final-p3e-gate-4e4453e/gate.log` and JSON |
| T85 | Half/one/spread gestures preserve counts and cursor | 7 split as 4 held/3 remaining; cursor snapshot restored 4; one returned and three distributed once | PASS | same gate root |
| T86 | Output is retained and restored exactly once | One job consumed one ore/coal, retained one Ingot, restored it, and collection moved exactly one to inventory | PASS | same gate root; F3 two-process regression |
| T87 | Real slots and revised item identity exist | Modal exposed three slots; Furnace had 5 parts, Workbench 9; held Stone Pick used transparent reference | PASS | same gate root |
| T88 | Manual patterns remain valid | Manually staged Log recognized Planks with no selected recipe-book entry | PASS | same gate root |
| T89 | Player-facing presentation renders | 1280×720 Furnace and world/held images were produced and visually inspected; loaded Ore/Fuel are visible | PASS | `final-p3e-visual-4e4453e` |
| Static | Contracts and launch path remain valid | 11 blocks, 26 items, 21 recipes; 36/36 Python tests | PASS | final static commands |
| Regression | Affected accepted behavior remains green | F2 T19–T22; F3 T23–T26 across two processes; F5 T31/T33/T35/T36; P3D T79–T82; P3C T72–T77 | PASS | final regression roots below |
| Windows export | Matching custom release template with editor closed | Manifest records source `4e4453e...`, game tree `c1c2681...`; exported gate and render pass | PASS | build manifest and final P3E roots |

Rendered evidence: `p3e-furnace-container.png` SHA-256 `d855978015c32ce6fbc306a41cdf4a1acfff36eee8b6eb1df5f9579c80c825d1`; `p3e-world-and-held-identity.png` SHA-256 `11276f52d9581e03eb2e3fe59d6648d416b2eb9706c633426be2b0e323e5bdad`.

LIMITATIONS/FAILURES:

- Furnace processing remains one job at a time. There is no queue, automated transport, alternate fuel duration or additional ore family.
- The transparent held references and detailed geometric stations are prototype identity alignment, not final modeled/animated assets.
- The headless renderer cannot create viewport screenshots; T89 correctly runs through the graphical exported runtime. An initial T89 review caught blank first-frame Furnace slot cards; cached presentation state fixed that before the final export.
- The pinned build emits a non-blocking Windows certificate-store warning in restricted runs.

NEXT:

Tony should run the playable export at 3440×1440, load Ore/Fuel with both double-click and split gestures, close/reopen the Furnace around completion, collect retained Output, verify save/Continue, and compare station/held visuals with inventory icons. Correct any owner-reported issue before promotion.

GIT/REPRODUCIBILITY:

- Repo/worktree/branch/source: `D:\CODEX\Craft_and_Defend`; `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`; `feature/p3d-tools-world-feedback`; `4e4453ef9df245e1a73eb477b927b9da18bbc23c`.
- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`, `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`; unchanged.
- Game tree: `c1c268146bd0d326f5980fe22c2835f255d8f6eb`.
- Engine/runtime: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; Compatibility/OpenGL 3.3; NVIDIA RTX 5090 driver 610.88.
- Engine/template hashes: editor archive `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; extracted editor `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`; release-template archive `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Export: EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK `ebf12b6df9c753d152d059b60c0b6904442546a216f0eb00a38def7021bc9725`; built UTC `2026-09-14T08:46:15.0564191Z`.
- Generated reference: `game/assets/ui/world_item_reference_p3e.png`; SHA-256 `ef7ded31cea1ee18915e7bc822dccda48cba3cc9530feca07d4a40f0fb221599`; exact prompt and preserved source path are recorded beside the asset.
- Final roots: `artifacts/final-p3e-gate-4e4453e`, `artifacts/final-p3e-visual-4e4453e`, `artifacts/final-f2-regression-4e4453e`, `artifacts/final-f3-regression-4e4453e`, `artifacts/final-f5-regression-4e4453e`, `artifacts/final-p3d-regression-4e4453e`, `artifacts/final-p3c-regression-4e4453e`.
- No Godot process remained after verification. No merge, push or release was performed.
