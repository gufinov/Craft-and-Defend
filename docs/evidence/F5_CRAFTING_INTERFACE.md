# Evidence — F5 crafting interface — 2026-09-11

STATUS: PARTIAL — candidate implementation and exported automation pass; owner 3440×1440 graphical acceptance is pending.

DONE:

- Separated Tab inventory and B hand crafting into distinct paused application states.
- Added persistent, conflict-checked Build rebinding with physical B as the ESDF default.
- Added a centered 2×2 Field Build modal, 3×3 Workbench modal and furnace ore/fuel modal backed by the existing data-driven recipes and atomic transactions.
- Made right-click station interaction take priority over ordinary placement; Shift cannot open a station.
- Preserved existing saves, inventory, station jobs, capture, time/world settings and side-face placement behavior.
- Added a staged castle construction, defenses, equipment, logistics and possible-magic plan. No unapproved content was represented as implemented.

EXPECT:

Tab opens inventory only. B opens limited hand crafting. Only right-clicking a placed workbench opens advanced crafting. Right-clicking a furnace opens its processing interface. Station targeting does not place or consume a block. Escape returns to play. Existing save slots Continue without migration.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T31 | Tab inventory and B hand crafting are separate; Build rebind persists | Distinct paused contexts passed; B→V survived a complete process restart; per-action reset restored B | PASS | `artifacts/f5-final-export-v5/phase1.log`, `phase2.log`; `artifacts/f2-final-export/gate.log` |
| T32 | Right-click workbench opens 3×3 without placement; Shift cannot bypass | `OPEN_STATION`, 3×3 modal and `SECONDARY_REQUIRED` all passed | PASS | `artifacts/f2-final-export/gate.log` |
| T33 | Furnace owns ore/fuel modal; processing remains atomic and exact once | Furnace 2-cell processing modal passed; T22 consumed/reserved/completed once and rejected duplicate/busy dismantle | PASS | `artifacts/f5-final-export-v5/phase1.log`; `artifacts/f2-final-export/gate.log` |
| T34 | Interfaces legible and keyboard-usable at 1280×720 and 3440×1440 | Automated 1280×720 workbench capture passed; native 3440×1440 owner review not yet run | PARTIAL | `artifacts/f5-final-export-visual/f5-workbench-crafting.png`, `visual.log` |
| Regression | F2 gathering/crafting/save and F4 time/capture/placement remain intact | Exported F2 gate/Continue and F4 phase1/phase2 passed on the same product implementation | PASS | `artifacts/f2-final-export/gate.log`, `continue.log`; `artifacts/f4-final-export/phase1.log`, `phase2.log` |
| Static | Foundation validator and Python suite | Validator PASS; 20/20 unit tests PASS | PASS | Commands below |

Commands:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
& .\builds\CraftAndDefend\CraftAndDefend.exe -- --f0-data-root=<isolated-root> --f5-automation=phase1
& .\builds\CraftAndDefend\CraftAndDefend.exe -- --f0-data-root=<same-root> --f5-automation=phase2
```

LIMITATIONS/FAILURES:

- Native 3440×1440 graphical acceptance remains with Tony; no automated 1280×720 capture is presented as ultrawide evidence.
- The 2×2 and 3×3 surfaces visualize selected recipes. Free-form ingredient placement, drag-and-drop and positional recipe discovery are not implemented.
- The existing content registry is unchanged. Torches, castle pieces, defensive weapons, gear and magic are roadmap work requiring data, art and balance decisions.
- The exported runtime logs Godot's Windows root-certificate warning. It did not prevent any local offline gate.
- A direct editor headless probe crashed while opening its Godot user log; it is excluded from acceptance. The provenance-matched release export completed and its F5 automation exited 0.

NEXT:

Tony checks Tab, B, workbench right-click, furnace right-click, Escape and modal legibility at 3440×1440 from `START_GAME.cmd`. Correct owner-found defects before F5 promotion. Do not merge, push or publish without explicit authority.

GIT/REPRODUCIBILITY:

- Canonical checkout: `D:\CODEX\Craft_and_Defend\main`; clean `main` and `origin/main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\crafting-interface`; `feature/crafting-interface`; base accepted F4 `ae9ced35ab10e95ea29c31b85044e6c8a752628d`.
- Product/UI commit: `9adb551c8c8ca9a95a5e62aefb314d8e42c3d06e`; final automation/export source: `9fabd9945f611965ef6485c08b90d0e83cd0ab6a`; game tree: `380e219a9ec7dd910b8eb31111cef110afdd2fa5`.
- OS/hardware: Windows 11 Pro `10.0.26200`; AMD Ryzen 9 7900X3D; 64 GB RAM; NVIDIA GeForce RTX 5090; OpenGL Compatibility; owner display 3440×1440.
- Engine/Voxel Tools: Godot `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`, source commit `595f52ee4e23203a865eeb981f115909f7aa92f4`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; editor executable SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; template executable SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Final Windows export: PASS. EXE SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`; PCK SHA-256 `4e0258f3fa671b84c94d394526d26440a4cc4bc3896938a03c874e4e6358b92f`; built UTC `2026-09-11T14:12:24.6676980Z`.
- Seed/world/content: seed `41026`; half-open bounds 64×32×128; content version `foundation-1`; normal save root `%APPDATA%\CraftAndDefend`.
- Editor closed during the exported checks: PASS. F5 clean-process restart: PASS. Existing exported F2/F4 clean-process Continue regression: PASS. No merge, push or release performed.
