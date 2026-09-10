# Craft-and-Defend

First-person voxel survival and fortress building: **from forest to fortress**. Gather, dig, craft, build, automate, and eventually withstand a wizard-led final siege.

**Status: F0 Windows integration spike implemented and passed on the recorded Windows test PC.** The playable slice is intentionally limited to the native shell, finite editable voxel world, ESDF controller, dirt break/place loop, key rebinding, coherent normal checkpoints, restart/Continue, and portable Windows export. Craft-and-Defend is a working label, formerly discussed as Block Castle Siege; final branding is open.

## Start here

1. Read [AGENTS.md](AGENTS.md) and [the handoff](docs/CODING_AGENT_HANDOFF.md).
2. Review [current status](docs/STATUS.md), [engine decision](docs/ENGINE_DECISION.md), and [prototype scope](docs/PROTOTYPE_SCOPE.md).
3. Double-click `START_F0.cmd` for the local playable slice, or follow [Windows setup](docs/WINDOWS_SETUP.md) to reproduce the toolchain and export.
4. Review [F0 evidence](docs/evidence/F0_WINDOWS_INTEGRATION.md) before authorizing any later milestone.

Proven F0 stack: **Godot 4.6 custom build + Zylann Voxel Tools 1.6 Module edition + GDScript**, Windows x86-64, offline single player. Exact release archives and publisher-reported SHA-256 values are in [tools/versions.json](tools/versions.json). The evidence record identifies the locally verified hashes and runtime results. This is an F0 result, not a general performance or durability guarantee.

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

These validate documentation links and starter data invariants. Windows runtime/export evidence is separate in `docs/evidence/F0_WINDOWS_INTEGRATION.md`.

Local convention: `D:\CODEX\Craft_and_Defend\main` is canonical; later commissioned implementation belongs under `D:\CODEX\Craft_and_Defend\worktrees`. F0 is owner accepted on `main`. No later milestone or unvalidated gameplay goes directly into `main`.
