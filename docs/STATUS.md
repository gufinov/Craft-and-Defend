# Current checkpoint — 2026-09-10

**STATUS:** G0 supervisory groundwork complete; **F0 runtime integration NOT STARTED**. No playable game, Godot project, Windows executable or runtime pass is claimed.

**DONE:** Recovered the original research and preserved its bytes. Verified the public repository, created the minimal bootstrap, reconciled the brief, recorded the candidate engine release and publisher archive digests, and prepared game/technical docs, module contracts, content/control/world fixtures, 30 runtime test cases, validation tooling and a local-agent handoff. CI is configured for static checks only.

**EXPECT:** The next local agent should read this checkpoint and the handoff, create/reuse the implementation worktree and prove F0 before crafting. The repo contains a small proposed data model, not functioning gameplay. Optional wall templates and all enemy systems remain deferred.

**TEST:** Python 3.12.14 in the Linux preparation environment. Static validation and 16 unit tests pass; see [G0 evidence](evidence/G0_FOUNDATION.md). Candidate release metadata and published SHA-256 values were checked against upstream. Actual engine archives were not downloaded/hashed/run. CI execution is a separate remote status; its configuration alone is not a run result.

**LIMITATIONS/FAILURES:** Windows folder/hardware/tool availability is unverified here. Godot parsing, actual collision/editing, coherent save recovery, performance, input behavior and export all remain NOT RUN. Original report citation tokens are retained as historical text; direct verified sources are in the source register. No project license has been selected. No runtime blocker has been diagnosed because runtime has not started.

**NEXT:** Execute only the F0 card in [BACKLOG.md](BACKLOG.md), following [CODING_AGENT_HANDOFF.md](CODING_AGENT_HANDOFF.md). Record T01–T12 and stop at the gate before content expansion.

**GIT/REPRODUCIBILITY:** Repository `gufinov/Craft-and-Defend`; groundwork branch `docs/foundation-groundwork`, based on bootstrap `1a94cffc82280f485f6f877a5e64567159ddd3af`. The exact groundwork commit is the commit containing this checkpoint; obtain it with `git rev-parse HEAD` after checkout. Local implementation belongs on `prototype/foundation` in `D:\CODEX\Craft-and-Defend\worktrees\foundation`; canonical checkout is `D:\CODEX\Craft-and-Defend\main`. No gameplay merge to main is authorized by this checkpoint.
