# Evidence — F5 crafting interface and presentation quality — 2026-09-11

STATUS: PARTIAL — revised candidate and matching Windows export pass; owner perceptual motion, hands-on drag/drop and 3440×1440 modal acceptance remain pending.

DONE:

- Preserved Tab-only inventory, rebindable B hand build, right-click-only workbench/furnace entry and atomic crafting transactions.
- Replaced the two-column recipe preview with three bounded panels: current inventory, staged crafting grid and searchable scrolling recipe book.
- Added inventory-to-grid drag/drop plus click/keyboard fallback, manual recipe recognition and recipe/search Enter auto-fill.
- Included basic hand recipes in the workbench book alongside advanced recipes. No recipes or content IDs were invented.
- Added persistent MSAA and VSync controls. Default is 4× MSAA with VSync enabled.
- Enabled physics interpolation for fixed-step player/camera motion and reset interpolation after player activation/restore.
- Stabilized sunlight shadows with four blended splits, a 48-unit shadow distance and one light-transform update per displayed game minute.

EXPECT:

Crafting opens as the correct modal for its context. Staged cells cannot exceed held counts and do not mutate inventory until Craft. Recipe search filters while typing and Enter loads the first held-material match. The workbench can load planks, sticks and workbench recipes as well as advanced items. Visual smoothing addresses edge/camera jitter without switching away from the approved Compatibility renderer. Shadow transforms remain stable between meaningful clock updates.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T31 | Tab inventory and B hand build remain separate; Build binding persists | Distinct paused contexts passed; B→V survived restart; reset restored B | PASS | `artifacts/f5-final-editor-closed/phase1.log`, `phase2.log` |
| T32 | Right-click workbench opens 3×3 and exposes basic plus advanced recipes | Eight expected recipes were enumerated; station entry priority and Shift rejection passed | PASS | `artifacts/f2-final-editor-closed/gate.log` |
| T33 | Furnace owns its two-input modal and remains exact-once | Furnace modal and F2 T22 transaction tests passed | PASS | `artifacts/f5-final-editor-closed/phase1.log`, `artifacts/f2-final-editor-closed/gate.log` |
| T34 | Three-panel modal is legible and reachable at 1280×720 and 3440×1440 | Exported 1280×720 render is unclipped with independent inventory/recipe scroll areas; owner ultrawide modal review pending | PARTIAL | `artifacts/f5-final-editor-closed/f5-workbench-crafting.png`, `visual.log` |
| T35 | Graphics defaults/persistence/interpolation/shadow stability | 4× MSAA, VSync and interpolation passed; 8×/VSync-off survived restart; blended 48-unit shadow splits and within-minute transform stability passed | PASS | `artifacts/f5-final-editor-closed/phase1.log`, `phase2.log` |
| T36 | Drag/click staging, manual recognition and search+Enter autofill work | Inventory drop handler staged Log, recognized Planks, and search loaded Workbench; all passed | PASS | `artifacts/f5-final-editor-closed/phase1.log` |
| Static | Foundation validator and Python suite | Validator PASS; 20/20 tests PASS | PASS | Commands below |
| Windows export | Matching custom release export and editor-closed regressions | Export PASS; F5, F2 gate/Continue, F4 and F1/display suites all exited 0 with editor count zero | PASS | `builds/CraftAndDefend/build_manifest.json`; `artifacts/f5-final-editor-closed/`, `f2-final-editor-closed/`, `f4-final-editor-closed/`, `f1-final-editor-closed/` |

Commands:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
& .\builds\CraftAndDefend\CraftAndDefend.exe -- --f0-data-root=<isolated-root> --f5-automation=phase1
& .\builds\CraftAndDefend\CraftAndDefend.exe -- --f0-data-root=<same-root> --f5-automation=phase2
```

LIMITATIONS/FAILURES:

- Tony's real-motion review is required; configuration tests and still images do not prove subjective jitter removal.
- 3440×1440 owner inspection of the revised modal remains pending.
- Crafting accepts ingredient counts in any grid order. Positional recipe shapes and split-stack quantities are future contract decisions.
- Text thumbnails are deliberate wireframes until original item art exists.
- Pinned editor runs emit nonblocking offline root-certificate and shader-cache warnings. They do not fail the test process.

NEXT:

Obtain Tony's motion, drag/drop and ultrawide acceptance before any promotion. Correct any owner-found defect in this isolated worktree. Do not merge, push or publish without separate authority.

GIT/REPRODUCIBILITY:

- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`; clean `main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\crafting-interface`; `feature/crafting-interface`; implementation/export source `27d8d39b1f9d00bd2b51b7d446b38c22b3656717`; game tree `8a44a257ddf98e868a1ed30c7e87ca2dc8365cd2`.
- Engine/Voxel Tools: Godot `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; Compatibility renderer.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; editor executable SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; template executable SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Final Windows export: PASS; EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `e0893bdf818ac8642a589de20309bb9f46d51730c875e1eff43221157c32c6c3`; built UTC `2026-09-11T15:04:59.9784769Z`.
- Exported runtime tests were repeated with zero `godot.windows.editor.x86_64` processes: PASS.
- Normal save root remains `%APPDATA%\CraftAndDefend`; all automated checks use isolated roots beneath the worktree.
- No merge, push or release performed.
