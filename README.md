# Craft-and-Defend

First-person voxel survival and fortress building: **from forest to fortress**. Gather, dig, craft, build, automate, and eventually withstand a wizard-led final siege.

**Status: F0–F5 and P1–P3B are owner accepted; P3C is a matching-export candidate awaiting Tony's playtest.** P3C adds a paged icon-first catalog, an Iron Sword, and craftable/player-placeable Ballista and Catapult defenses while retaining the accepted ESDF controls, two-slot persistence, world editing, castle construction and core-defense foundation. Craft-and-Defend is a working label; final branding is open.

## Start here

1. Read [AGENTS.md](AGENTS.md) and [the handoff](docs/CODING_AGENT_HANDOFF.md).
2. Review [current status](docs/STATUS.md), [engine decision](docs/ENGINE_DECISION.md), and [prototype scope](docs/PROTOTYPE_SCOPE.md).
3. Double-click `START_GAME.cmd` for the local playable slice, or follow [Windows setup](docs/WINDOWS_SETUP.md) to reproduce the toolchain and export.
4. Review [current P3C evidence](docs/evidence/P3C_PLAYER_DEFENSE_AND_VISUAL_CATALOG.md) and the earlier records in [the documentation index](docs/INDEX.md) before promoting another milestone.

The exported portable folder is `builds\CraftAndDefend`. Keep its EXE, PCK, `START_GAME.cmd` and manifest together; double-click its `START_GAME.cmd` on a Windows PC. It does not need the repository or Godot Editor. Saves and settings are in `%APPDATA%\CraftAndDefend`; F2 in-game screenshots are in `%APPDATA%\CraftAndDefend\screenshots`.

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

Double-click `TEST_P3C_PLAYER_DEFENSE.cmd` to run the matching exported sword, siege, clean-process Continue and rendered recipe-book gates. It controls and closes the diagnostic itself, then opens its evidence image; use `START_GAME.cmd` for normal play.

Local convention: `D:\CODEX\Craft_and_Defend\main` is canonical; commissioned implementation belongs under `D:\CODEX\Craft_and_Defend\worktrees`. F0 and F1 are owner accepted on `main`. No unreviewed milestone goes directly into `main`.
