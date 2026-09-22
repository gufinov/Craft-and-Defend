# Craft-and-Defend

First-person voxel survival and fortress building: **from forest to fortress**. Gather, dig, craft, build, automate, and eventually withstand a wizard-led final siege.

**Status (2026-09-19): baseline on `main`.** Playable Windows slice with ESDF first-person movement, finite editable voxel world with hills/trees/ore, hand/Workbench crafting, auto-running Furnace, Tab inventory, castle kit, right-drag wall building (Shift to build up), stamped castle blueprints (service level), a core-defense drill with one raider, and siege weapons that turn, throw and reload. Everything on `main` is owner-playtested unless `docs/STATUS.md` says otherwise. Craft-and-Defend is a working label; final branding is open.

**New here?** Read, in order: [AGENTS.md](AGENTS.md) → [docs/STATUS.md](docs/STATUS.md) (what is true right now) → [docs/DESIGN_DIRECTION_2026-09-18.md](docs/DESIGN_DIRECTION_2026-09-18.md) (where the game is going and which decisions are locked) → [docs/BACKLOG.md](docs/BACKLOG.md) (the next cards) → [docs/INDEX.md](docs/INDEX.md). Then double-click `START.cmd`. Every milestone has a contract in `docs/` and an evidence record in `docs/evidence/`; every runtime test has a `TEST_*.cmd` runner.

## Start here

1. Read [AGENTS.md](AGENTS.md) and [the handoff](docs/CODING_AGENT_HANDOFF.md).
2. Review [current status](docs/STATUS.md), [engine decision](docs/ENGINE_DECISION.md), and [prototype scope](docs/PROTOTYPE_SCOPE.md).
3. Double-click `START.cmd` for the local playable slice (`START.cmd help` lists its options: `sandbox`, `coastercraft`, `build`, `stop`), or follow [Windows setup](docs/WINDOWS_SETUP.md) to reproduce the toolchain and export.
4. Review the newest evidence records listed in [the documentation index](docs/INDEX.md) before promoting another milestone.

The exported portable folder is `builds\CraftAndDefend`. Keep its EXE, PCK, `START.cmd` (`START.cmd stop` closes a stuck game window) and manifest together; double-click its `START.cmd` on a Windows PC. It does not need the repository or Godot Editor. Saves and settings are in `%APPDATA%\CraftAndDefend`; F2 in-game screenshots are in `%APPDATA%\CraftAndDefend\screenshots`.

Proven candidate stack: **Godot 4.6 custom build + Zylann Voxel Tools 1.6 Module edition + GDScript**, Windows x86-64, offline single player. Exact release archives and publisher-reported SHA-256 values are in [tools/versions.json](tools/versions.json). The evidence records identify the locally verified hashes and runtime results. This is not a general performance or durability guarantee.

| Location | Purpose |
|---|---|
| [docs/INDEX.md](docs/INDEX.md) | All documentation and reading paths |
| [docs/PREFLIGHT.md](docs/PREFLIGHT.md) | Objective, context, dependencies, costs and decision |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Module boundaries and contracts |
| [docs/research/README.md](docs/research/README.md) | Original report and verification corrections |
| `contracts/` | Versioned design fixtures: world, controls, content, placement |
| `tools/` and `tests/` | Dependency-free Python validation and negative cases |
| [game/README.md](game/README.md) | Runtime, controls, save location, build and test entry points |

Run the available checks from the repository root with Python 3.11+:

```shell
python tools/validate_foundation.py
python -m unittest discover -s tests -v
```

These validate documentation links and starter data invariants. Windows runtime/export evidence is separate in `docs/evidence/`.

The exported-game test runners live in `tools\runners\` (moved out of the root on 2026-09-22). Double-click any `TEST_*.cmd` there (for example `TEST_P4_SIEGE_UNITS.cmd` for the siege machines and wave drill, `TEST_P3D_USABILITY.cmd` for crafting and held items) to run that milestone's exported gates; `tools\runners\RUN_ALL.cmd` runs every runner in order and prints a PASS/FAIL table (logs under `artifacts\run_all-<stamp>`). Each runner controls and closes the diagnostic itself, then opens its evidence image(s); use `START.cmd` for normal play.

`START.cmd` options: no argument prepares the provenance-matched export and plays (the main menu offers the real game and CoasterCraft); `START.cmd sandbox` = CoasterCraft plus the premade demo tracks with the data root `artifacts\coaster-sandbox`; `START.cmd coastercraft` = straight into CoasterCraft New (data root `artifacts\coastercraft`); `START.cmd dev` = straight into the [Development Expo](docs/DEVELOPMENT_EXPO.md), the owner's development world on its own save (data root `artifacts\development`); `START.cmd build` rebuilds the Windows export now; `START.cmd stop` closes every running game window; `START.cmd help` prints this list. The old `START_GAME`, `START_COASTER_SANDBOX`, `START_COASTERCRAFT`, `START_F0`, `STOP_GAME`, `BUILD_WINDOWS`, `BUILD_WINDOWS_F0` and `VIEW_NAVIGATION_SPIKE` launchers are gone.

Local convention: `D:\CODEX\Craft_and_Defend\main` is canonical and is where the owner plays; implementation branches live in worktrees under `D:\CODEX\Craft_and_Defend\worktrees` (`git worktree add -b feature/<name> ../worktrees/<name> main`). No unreviewed milestone goes directly into `main`; the owner authorises each merge. Developer tooling: the pinned editor runs any diagnostic headless (`godot --headless --path game -- --f0-data-root=<dir> --<suite>=<mode>`; run `godot --headless --path game --import` once in a fresh worktree), and `tools\start_game.ps1 -PrepareOnly` exports a provenance-matched build for the `TEST_*.cmd` runners.
