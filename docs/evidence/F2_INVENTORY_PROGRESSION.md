# Evidence — F2 inventory, progression and workstations — 2026-09-11

STATUS: PASS — implementation gate complete; owner graphical playtest and promotion pending.

DONE:

- Implemented the canonical content registry, finite authored resource path, tool-gated harvesting, 27-slot inventory/9-slot hotbar, atomic crafting, one-cell workbench/furnace placement, idle dismantling, timed furnace reservation/completion and coherent F2 checkpoint restore.
- Added original SVG placeholder textures and attribution; no MinionClash assets were copied.
- Adapted read-only MinionClash M01 presentation evidence into a Craft-specific grouped/searchable keybind editor, per-row reset, visible capture/conflict state and centered responsive work column. Exact ESDF defaults and conflict rejection remain authoritative.
- Hardened Windows export so a Git checkout cannot silently emit a manifest without source commit and game-tree provenance.

EXPECT:

An empty Start reaches iron-pick progression using only authored world resources and normal craft/station operations. Every failed operation is non-mutating. Paused furnace work does not advance. Save/quit and a separate Continue process restore terrain, inventory/hotbar and idle stations without duplication. The Windows export behaves the same with the matching editor closed.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| F2-UI | 21 grouped keybind rows; search filters; individual reset restores E | Search `forward` exposed only Move Forward; R rebound persisted in-memory then per-row reset restored E | PASS | `artifacts/f2-exported-final-20260911-2/gate.log` |
| Print Screen focus | Windows capture does not expose/stick the Pause menu; ordinary focus loss remains safe | Synthetic Print Screen focus cycle froze invisibly and resumed after the click-through guard; normal focus loss still required explicit Resume | PASS (automation); owner Windows retest pending | `artifacts/print-screen-fix-20260911-1/f1-phase1.log`; `T14_PRINT_SCREEN`, `T14_FOCUS_LOSS` |
| T19 | Empty inventory reaches wood pick, stone pick, three ingots and iron pick with no grants | Authored logs/stone/coal/iron were mined and the complete chain succeeded | PASS | same gate log; `T19_WORLD_READY`, `T19_PROGRESSION` |
| T20 | Insufficient/capacity/double activation/wrong station are atomic; slots/hotbar work | All rejection snapshots unchanged; one exact output; slot 0→10, hotbar selection and invalid-slot no-op passed | PASS | same gate log; all `T20_*` records |
| T21 | Station placement consumes once; invalid duplicate/support/dismantle rules hold | Workbench consumed once, support was owned, duplicate refused and idle dismantle returned one | PASS | same gate log; `T21_PLACE_DISMANTLE` |
| T22 | Furnace consumes once, reserves once, pauses, finishes once, refuses busy dismantle | Remaining time stayed 5.0 while paused; exactly one ingot delivered | PASS | same gate log; `T22_FURNACE` |
| F2 checkpoint | Terrain/gameplay publish together | revision 1; 3 terrain tracker tasks; database SHA-256 `e2ff44c05c21fd3962805242855be1a757ba049b190d4cba39d7f418b2401926`; gameplay SHA-256 `b8e69fdad96791a64a266e9c8b0ca9fcd3f541172388a3b33d965a6e0a93b3ad` | PASS | same gate log; `F2_CHECKPOINT` |
| F2 Continue | Separate process restores progression and two idle stations without duplicates | iron pick 1; workbench 1; furnace 1; jobs empty | PASS | `artifacts/f2-exported-final-20260911-2/continue.log` |
| F1 regression | Settings, complete keybinds, contexts, boundaries, transactions and footprints remain valid | phase1 and phase2 exited 0; T13–T18 passed | PASS | `artifacts/f1-exported-final-20260911-2/*.log` |
| F0 regression | Menu, ESDF, collision, edit rejection, save and restart remain valid | phase1 and phase2 exited 0; T02–T10 passed | PASS | `artifacts/f0-exported-final-20260911-2/*.log` |
| Visual | Keybind and inventory screens fit at 1280×720 | Actual GPU captures show complete panels without bottom clipping | PASS | `artifacts/f2-local-artifacts/f2-visual-20260911-2/f2-keybinds.png`, `f2-inventory.png` |
| Static | Foundation contracts and negative tests remain valid | validator PASS; 18/18 unittest PASS | PASS | commands below |
| Windows export | Matching custom release template produces current package | export PASS; provenance manifest records commit and game tree | PASS | `builds/CraftAndDefend/build_manifest.json` |

Commands:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
```

Runtime automation used isolated `--f0-data-root` folders under `artifacts`, then launched `CraftAndDefend.exe` separately for `--f2-automation=gate`, `continue`, F1 `phase1`/`phase2` and F0 `phase1`/`phase2`.

LIMITATIONS/FAILURES:

- Tony has not yet performed the F2 graphical feel/usability playtest. Automation cannot accept appearance, pacing or control feel.
- F3 interruption recovery, A/B slot isolation, mid-furnace restart and injected storage failure are not claimed.
- Headless Godot logs `Failed to read the root certificate store`; the application is offline and all affected gates exit 0, but the warning is retained rather than concealed.
- An unrelated Godot 4.7.2 process was left untouched during the final export regression; the matching pinned Godot 4.6 editor process was confirmed closed.

NEXT:

Tony launches this worktree with `START_GAME.cmd` and tests the visible F2 loop. Fix any F2 defect before promotion. Do not begin F3, merge, push or publish without explicit authority.

GIT/REPRODUCIBILITY:

- Repo: `D:\CODEX\Craft_and_Defend\main`; clean canonical `main` and `origin/main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c` when the gate was recorded.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\f2-inventory`; `feature/f2-inventory-progression`.
- Verified package source commit: `41d1e6cd2eb08e0032f02f45edb841db424344fd`; game tree `bd105da67bcafc489eb684ed2a6b3add7c0acba1`. The final evidence correction is docs-only and does not change that game tree.
- Reference only: MinionClash worktree `D:\CODEX\MinionClash\worktrees\milestone-01-move-look-bind-place`, commit `8457e9e4f68d26f6f291eb5e1df9465d542991c0`; its pre-existing dirty state was preserved.
- Platform: Microsoft Windows build `10.0.26200.9445`; AMD64 Family 25 Model 97; NVIDIA GeForce RTX 5090; owner display 3440×1440; OpenGL 3.3 Compatibility renderer. RAM was not available through the restricted diagnostic interface.
- Engine/Voxel Tools: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`, source commit `595f52ee4e23203a865eeb981f115909f7aa92f4`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`.
- Export EXE: `builds\CraftAndDefend\CraftAndDefend.exe`; SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`.
- Export PCK: `builds\CraftAndDefend\CraftAndDefend.pck`; SHA-256 `0f7d94cf2472fbae49032c40ef57756167c4237296889310f6ca99919c8e3a9b`.
- Seed/world/content: deterministic seed `8675309`; half-open bounds 64×32×128; content version `foundation-1`; normal saves resolve to `%APPDATA%\CraftAndDefend`, while tests used isolated roots.
- Editor-closed export test: PASS for the matching pinned editor; clean-process restart: PASS.
