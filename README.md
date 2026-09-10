# Craft-and-Defend

First-person voxel survival and fortress building: **from forest to fortress**. Gather, dig, craft, build, automate, and eventually withstand a wizard-led final siege.

**Status: foundation documentation and starter data/tooling. No playable game or Windows build yet.** Runtime implementation is assigned to the local coding agent. Craft-and-Defend is a working label, formerly discussed as Block Castle Siege; final branding is open.

## Start here

1. Read [AGENTS.md](AGENTS.md) and [the handoff](docs/CODING_AGENT_HANDOFF.md).
2. Review [current status](docs/STATUS.md), [engine decision](docs/ENGINE_DECISION.md), and [prototype scope](docs/PROTOTYPE_SCOPE.md).
3. Follow [Windows setup](docs/WINDOWS_SETUP.md), then implement **F0: Windows integration spike** from [the backlog](docs/BACKLOG.md).
4. Record evidence against [the test plan](docs/TEST_PLAN.md) before advancing.

Candidate stack: **Godot 4.6 custom build + Zylann Voxel Tools 1.6 Module edition + GDScript**, Windows x86-64, offline single player. Exact release archives and publisher-reported SHA-256 values are in [tools/versions.json](tools/versions.json). The pairing is selected for validation, not yet proven on this project. Luanti is a fallback evaluation route.

| Location | Purpose |
|---|---|
| [docs/INDEX.md](docs/INDEX.md) | All documentation and reading paths |
| [docs/PREFLIGHT.md](docs/PREFLIGHT.md) | Objective, context, dependencies, costs and decision |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Module boundaries and contracts |
| [docs/research/README.md](docs/research/README.md) | Original report and verification corrections |
| `contracts/` | Versioned design fixtures: world, controls, content, placement |
| `tools/` and `tests/` | Dependency-free Python validation and negative cases |
| [game/README.md](game/README.md) | Runtime entry point; no project.godot yet |

Run the available checks from the repository root with Python 3.11+:

```shell
python tools/validate_foundation.py
python -m unittest discover -s tests -v
```

These validate documentation links and starter data invariants. They do **not** validate Godot, gameplay, persistence, performance, or Windows export.

Local convention: `D:\CODEX\Craft-and-Defend\main` is canonical; implementation lives under `D:\CODEX\Craft-and-Defend\worktrees`. This foundation is on `docs/foundation-groundwork`; branch `prototype/foundation` from it while it awaits review. No unvalidated gameplay goes into `main`.
