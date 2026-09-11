# Evidence — F1 launcher/build-provenance recovery — 2026-09-11

STATUS: AUTOMATED PASS — owner canonical-launch confirmation pending

DONE:

Recovered the canonical one-click path after it launched a stale ignored F0 export following F1 promotion. F1 source and all accepted commits were intact on local and remote `main`; no rollback or source loss occurred. Windows builds now receive an ignored provenance manifest, and `START_GAME.cmd` validates the packaged game against the current tracked `game` tree before launch. Missing, unversioned, mismatched or dirty checkout packages rebuild with the pinned Godot/Voxel Tools pair. Portable packages outside Git remain directly runnable.

EXPECT:

Double-clicking `D:\CODEX\Craft_and_Defend\main\START_GAME.cmd` rebuilds the legacy unstamped canonical package once, then opens the F1 menu with Start, Continue, Settings, Keybinds and Quit. Subsequent starts reuse the package while the tracked game tree is unchanged. A future game-code commit triggers another rebuild instead of launching an older ignored package.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Recovery truth | F1 source/history remains recoverable | Local and `origin/main` both contained `805c3bc`–`6c4083d`; F1 settings, diagnostics and evidence files were present | PASS | Git/source inspection in this session |
| Incident reproduction | Identify the visible F0 cause without altering saves | Canonical ignored EXE/PCK were dated 2026-09-10 21:07; launcher preferred them without identity validation | PASS | canonical build/launcher inspection |
| Missing package | Build before launch | `-PrepareOnly` exported the current game and wrote a manifest | PASS | recovery console output |
| Matching package | Avoid needless rebuild | Second preparation reported a provenance match and preserved PCK timestamp | PASS | recovery console output |
| Mismatched manifest | Reject and repair stale identity | Synthetic all-zero game-tree identity forced rebuild and restored the tracked tree hash | PASS | recovery console output |
| Legacy package | Reject existing EXE/PCK with no manifest | Removing only the ignored manifest forced rebuild and recreated valid provenance | PASS | recovery console output |
| Exported F1 identity | Package contains F1 rather than F0 | F1 display automation accessed Settings/native-resolution controls and passed all fullscreen/windowed assertions in both the recovery worktree and rebuilt canonical package | PASS | `artifacts/launcher_recovery_f1_display.log`, `artifacts/canonical_recovery_f1_display_runtime.log` |
| F1 regression | Full accepted interaction behavior remains | Both F1 automation phases passed after rebuild | PASS | `artifacts/launcher_recovery_f1_phase1.log`, `artifacts/launcher_recovery_f1_phase2.log` |
| F0 regression | Core world/save loop remains | Both F0 automation phases passed after rebuild | PASS | `artifacts/launcher_recovery_f0_phase1.log`, `artifacts/launcher_recovery_f0_phase2.log` |
| Static | Contracts and launcher guard remain present | Foundation validator and all 18 unit tests passed; PowerShell scripts parsed | PASS | command output in this session |

LIMITATIONS/FAILURES:

- The previous closeout tested Git promotion but failed to test the canonical checkout's ignored executable before declaring the graphical path ready. That omission allowed an old F0 package to mask intact F1 source.
- Two first-pass recovery executions exported successfully but the helper treated an unset PowerShell `$LASTEXITCODE` as failure. The preserved reproduction was corrected by validating Git object output as a 40-character hash; all four provenance states then passed.
- The exact one-click command selected and spawned the current package. In this automation host the manually launched process reported no closable main-window handle, so graphical menu confirmation remains Tony's test; exported F1 automation independently proved the package identity and UI contracts.

NEXT:

1. Tony double-clicks canonical `main\START_GAME.cmd` and confirms the visible F1 menu.
2. Keep F2 unstarted until a separate instruction.

GIT/REPRODUCIBILITY:

- Incident baseline: local and remote `main` `6c4083df75a327756f5f0516638a4a89e34ae808`.
- Recovery worktree/branch: `D:\CODEX\Craft_and_Defend\worktrees\launcher-recovery`; `fix/launcher-build-provenance`.
- Launcher implementation checkpoint: `3a93a8a31deb57c404bd1bfbd23d23c0edc1eb23`.
- Engine/template: Godot `4.6.stable.custom_build.89cea1439`; Voxel Tools `1.6.0 Module`; matching custom release template.
- Tested tracked game-tree identity: `7ee41b6ea736d2c7bbff3db8ba168eaebd30b711`.
- Executable SHA-256: `4ac128729e86108904e6d038d161322404d42d71892b1cc0dca751039aa7e4b2`.
- Canonical rebuilt game-tree identity: `af7eb1b58ff5edab922b4b0e384a3ac42e391f92`.
- Canonical rebuilt PCK SHA-256: `96780159eb89e2d866d8d027ccf41ac836b91bff15ae90a2352bbcc8d5c70124`.
- User save root was not deleted or migrated. All automation used isolated ignored roots under `artifacts`.
