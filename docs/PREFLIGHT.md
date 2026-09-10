# Foundation preflight — 2026-09-10

**Decision: proceed with repository groundwork and a small Windows integration prototype.** The engine direction is supported; the runtime is not yet validated. This delivery preserves the requested supervisory role.

| Area | Established position | Evidence class |
|---|---|---|
| Objective | Independent first-person voxel survival fortress game | User direction |
| Immediate outcome | Documentation, contracts, starter data, tests and local-agent instructions | Current request |
| First runtime success | Menu → finite world → gather/place → save → quit → reopen Windows executable | Adopted gate |
| First users | Tony playtests; local coding agent implements | User workflow |
| Environment | Windows, keyboard/mouse, offline single player | Product direction |
| Hardware | Inspect local machine before setting minimum spec or performance claims | Unverified here |
| Sources | Supplied conversation, attached report, official releases/APIs/licenses | Retrieved and read |
| Destination | Existing public `gufinov/Craft-and-Defend` | GitHub metadata verified |
| Initial repo | Empty before minimal README bootstrap | Verified this session |
| Inputs/outputs | Actions/content → world state; local saves/settings; eventual executable | Proposed architecture |
| Dependencies | Matching custom editor/export template, Git, GDScript; Python for checks | Candidate release verified, not run |
| Providers | GitHub source; official upstream binaries/docs; no gameplay backend | Scope decision |
| Permission | Repo foundation authorized; no store publishing, purchases, content licensing or gameplay merge implied | Authorization scope |
| Costs | MIT engine components; no mandatory engine royalty. Development, agent usage, art and distribution costs unpriced | License fact + budget unknown |
| Lifecycle | Worktree → test/evidence → review → portable Windows prototype; installer/store later | User workflow + proposal |
| Success evidence | Static repository checks and owner-accepted Windows F0 complete; later Foundation gates remain | Explicit gates |

The cloud session cannot verify the user's Windows folders, installed engine, GPU performance or disk space. The local agent inspects them read-only. Standard root: `D:\CODEX\Craft-and-Defend`; if a differently named checkout already has the correct remote, reuse it and record its path instead of creating duplicates.

## Alternatives and consequences

Godot + Voxel Tools offers editable voxel infrastructure with general app/game control. F0 tests integration and persistence before content investment. Luanti remains a fallback gather/build experiment; recheck its version and package licenses only if activated. Minecraft mods remain an optional mechanics laboratory, not a product prerequisite. Browser, Unity and Unreal alternatives remain in the report; another broad research loop or paid dependency is not justified now.

If the stack fails, retain a minimal reproduction and attempt one bounded fix or separately pinned newer Module release before discussing a switch. If the loop is tedious, revise gathering/crafting pace before adding enemies.

## Reconciliation

1. Godot 4.6 / Voxel Tools 1.6 exists but is not the newest release. It is a reproducible candidate, not a validated toolchain.
2. Empty-repo setup was necessary once; later agents must inspect current state.
3. The user's day/night requirement is included in full Foundation F4. Wave scheduling is deferred despite the report's broader final exclusion wording.
4. `Tab` opens inventory; `Escape` supplies reliable pause/system escape. This resolves earlier ambiguous menu wording.
5. Real mining depth remains essential. The flat layered F0 fixture does not remove tunnels, trenches, hills or land shaping.
6. One occupant per cell and multi-cell footprints are project rules; analogies to Minecraft/Orcs Must Die are not architectural evidence.

AI navigation, final world size, save durability, balance, exploration/wave timing, death penalty and branding remain open. See [risks](RISKS_AND_DECISIONS.md).
