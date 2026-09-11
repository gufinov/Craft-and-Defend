# Craft-and-Defend

First-person voxel survival and fortress building: **from forest to fortress**. Gather, dig, craft, build, automate, and eventually withstand a wizard-led final siege.

**Status: F1 is owner accepted on `main`; F2 is a passing candidate awaiting owner playtest on `feature/f2-inventory-progression`.** The candidate adds the finite gathering/tool progression, 27-slot inventory, crafting, workbench/furnace and improved keybind UI while retaining the native shell, exact ESDF controller, coherent checkpoints, restart/Continue and portable Windows export. Craft-and-Defend is a working label; final branding is open.

## Start here

1. Read [AGENTS.md](AGENTS.md) and [the handoff](docs/CODING_AGENT_HANDOFF.md).
2. Review [current status](docs/STATUS.md), [engine decision](docs/ENGINE_DECISION.md), and [prototype scope](docs/PROTOTYPE_SCOPE.md).
3. Double-click `START_GAME.cmd` for the local playable slice, or follow [Windows setup](docs/WINDOWS_SETUP.md) to reproduce the toolchain and export.
4. Review [F0 evidence](docs/evidence/F0_WINDOWS_INTEGRATION.md), [F1 evidence](docs/evidence/F1_INTERACTION_HARDENING.md), the [launcher recovery](docs/evidence/F1_LAUNCHER_RECOVERY.md), and [F2 candidate evidence](docs/evidence/F2_INVENTORY_PROGRESSION.md) before promoting another milestone.

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

Local convention: `D:\CODEX\Craft_and_Defend\main` is canonical; commissioned implementation belongs under `D:\CODEX\Craft_and_Defend\worktrees`. F0 and F1 are owner accepted on `main`. No unreviewed milestone goes directly into `main`.
