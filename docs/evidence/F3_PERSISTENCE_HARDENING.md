# Evidence — F3 persistence hardening — 2026-09-11

STATUS: PASS — implementation and exported regression gates complete; owner graphical playtest and promotion pending.

DONE:

- Added explicit Slot A/B selection and checkpoint status to the native main menu.
- Preserved working-session isolation while publishing timestamped terrain/gameplay checkpoint pairs through a backed-up pointer; retained the current and one prior completed checkpoint.
- Added recoverable Retry Save and Return to Paused Game choices after a failed save.
- Refused malformed, newer-schema and missing-content saves without changing them; copied the supported legacy `slots/default` layout to Slot A while preserving the original.
- Persisted active furnace identity, reservation and remaining simulation time so restart completes the job exactly once.
- Preserved the F2 Print Screen focus repair and all established F0–F2 behavior.
- Repaired the one-click launcher/build provenance checks for sandbox-created worktree ownership by applying Git trust only to the resolved repository and only for each internal command.

EXPECT:

Slot A and B never contaminate one another. Denied writes, simulated full disk and interruption before/after checkpoint or pointer publication never replace the last complete checkpoint. Unsupported saves are not silently reset. A supported migration retains its source. Mid-furnace restart preserves remaining time and produces one output. The matching Windows export behaves the same with the editor closed.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| T23 | A/B slots and repeated start/continue/save cycles remain isolated | A removed `(0,-1,38)` only; B removed `(2,-1,38)` only; each restored dirt `1` and only its own terrain edit | PASS | `artifacts/f3-final-phase1.log`, `artifacts/f3-final-phase2.log` |
| T24 recovery UI | Failed save offers retry or safe paused return | Injected denied write showed both actions; return restored PAUSED session | PASS | `T24_RECOVERABLE_UI` |
| T24 publication | Previous checkpoint survives five failure boundaries | Disk-full, before/after checkpoint publish, before pointer publish and during pointer publish all left revision 1 loadable | PASS | `T24_FAILURE_RECOVERY` |
| T24 retention | Successful repeated saves advance and keep two completed generations | Revisions 2 and 3 published; completed checkpoint directory count `2` | PASS | `T24_RETENTION` |
| T25 refusal | Malformed/newer/missing-content data is clear and unchanged | Returned `MALFORMED_POINTER`, `UNSUPPORTED_SAVE_SCHEMA`, `MISSING_CONTENT_VERSION`; fixtures remained unchanged | PASS | `artifacts/f3-final-validation.log`; `T25_INVALID_REFUSAL` |
| T25 migration | Supported legacy migration copies the original | `slots/default` copied to `slots/a`; source pointer byte-for-byte unchanged and source directory preserved | PASS | same validation root; `T25_LAYOUT_MIGRATION` |
| T26 | Mid-job restart preserves remaining time and completes once | Saved at `3.0` seconds; no output at `2.9`; one output after `0.11`; still one after another `10.0` | PASS | `T26_MIDJOB_SAVED`, `T26_MIDJOB_CONTINUE` |
| Save measurements | Record size and latency in fixed scenario | F3 checkpoint bytes `23,229–23,652`; save latency `45–66 ms` | PASS | `artifacts/f3-final-phase1.log` |
| F2 regression | Progression, slots, crafting, stations and Continue remain valid | Gate and separate Continue process returned `F2_AUTOMATION_PASS T19-T22` | PASS | `artifacts/f3-final-f2-*.log` |
| F1 regression | Keybind/settings/focus/boundary/transaction behavior remains valid | phase1/phase2 passed; `T14_PRINT_SCREEN` and ordinary `T14_FOCUS_LOSS` both PASS | PASS | `artifacts/f3-final-f1-*.log` |
| F0 regression | Menu, ESDF, edits, rejection, coherent save/restart remain valid | phase1/phase2 result payloads report `passed:true` | PASS | `artifacts/f3-final-f0-*.log` |
| Launcher ownership | Tony-owned double-click process can inspect the sandbox-created worktree without global Git changes | Builder, `-PrepareOnly`, direct launch and exact `START_GAME.cmd` each passed with `GIT_CONFIG_*` trust overrides removed; one game process launched and closed cleanly | PASS | launcher-fix commit and console evidence; `test_git_ownership_exception_is_repository_scoped` |
| Static | Foundation contracts and negative cases remain valid | validator PASS; 19/19 unittest PASS | PASS | commands below |
| Visual | New menu, gameplay and pause render at 1280×720 | All three GPU PNG captures saved at expected size; menu shows slot selector/status with no clipping | PASS | `artifacts/f3-visual-20260911a/*.png`, `artifacts/f3-visual.log` |
| Windows export | Matching custom release template builds exact committed game tree | Export PASS; manifest records source/game tree; all runtime gates ran with matching editor process count `0` | PASS | `builds/CraftAndDefend/build_manifest.json` |

Commands:

```powershell
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\validate_foundation.py
& 'C:\Users\Tony\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests -v
& .\tools\build_windows_f0.ps1
& .\builds\CraftAndDefend\CraftAndDefend.exe --headless -- --f0-data-root=<isolated-root> --f3-automation=phase1
& .\builds\CraftAndDefend\CraftAndDefend.exe --headless -- --f0-data-root=<same-root> --f3-automation=phase2
```

LIMITATIONS/FAILURES:

- Tony must retest the real Print Screen/Snipping Tool overlay; automation proves the intended focus-event sequence but cannot invoke the OS overlay.
- Tony has not yet accepted the visible F3 slot/recovery experience.
- Failure injection validates application boundaries, not sudden physical power removal, filesystem hardware guarantees or large-world performance.
- The initial `dubious ownership` failure came from Tony's launcher process reading Git metadata owned by the isolated Codex sandbox account. Commit `a1172cb` makes the launcher and builder pass the exact resolved worktree as a command-scoped trust value; no global Git configuration or filesystem owner was changed.
- Two orphaned headless Godot processes from an earlier parse-error run were identified by exact command line and terminated before editor-closed export validation.

NEXT:

Tony launches `D:\CODEX\Craft_and_Defend\worktrees\f3-persistence\START_GAME.cmd`, tests both slots, saves/restarts during one furnace job, and confirms Print Screen no longer exposes or sticks Pause. Fix any defect before promotion. Do not begin F4, merge, push or publish without explicit authority.

GIT/REPRODUCIBILITY:

- Canonical repo: `D:\CODEX\Craft_and_Defend\main`; clean `main` and `origin/main` at `c085c013d39b2b64321ea6c5a696b96fe2efd45c`.
- Worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\f3-persistence`; `feature/f3-persistence-hardening`.
- Built source commit: `a1172cbc3d6b5041077aab85428eb227f9ccd3da`; game tree `498ad7ea30fd5066aa659b2c7c50e174e2c5f1a1`.
- Platform: Windows 11 Pro `10.0.26200`, AMD Ryzen 9 7900X3D, 64 GB RAM, NVIDIA GeForce RTX 5090 driver `32.0.16.1088`; owner display 3440×1440; visual evidence OpenGL 3.3 Compatibility at 1280×720.
- Engine/Voxel Tools: `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`, source commit `595f52ee4e23203a865eeb981f115909f7aa92f4`.
- Editor archive SHA-256: `dae425d64dbf3b4f9e06f05a5f108f1f27eca708856e93bc46490151b0ffac0c`; extracted editor SHA-256: `e41a056ab022e600ec400767bfe9e80cf8dcda122512622a58dbff27a38b3d5b`.
- Release-template archive SHA-256: `9556c3893a07f39451c654789e16a057eec3d344428044b0d3e7ed44ae905857`; extracted template SHA-256: `58f53f6ce83c5093a5554a681122faff59fa8a8ae3ccfd2c5ba7163747c67d8b`.
- Export EXE: `builds\CraftAndDefend\CraftAndDefend.exe`; SHA-256 `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`.
- Export PCK: `builds\CraftAndDefend\CraftAndDefend.pck`; SHA-256 `cc55ec84bd9c35bc57690cc64a4028087ed1a7e44e7e9f1c94d991834915d73d`.
- Seed/world/content: deterministic seed `8675309`; half-open bounds 64×32×128; content version `foundation-1`; normal data root `%APPDATA%\CraftAndDefend`; automation used new isolated roots under ignored `artifacts`.
- Windows export: PASS. Matching editor closed during exported F3 and F0–F2 regressions: PASS. Clean-process restart: PASS.
