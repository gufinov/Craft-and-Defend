# Agent operating instructions

Read `docs/STATUS.md`, `docs/CODING_AGENT_HANDOFF.md`, `docs/ENGINE_DECISION.md`, `docs/PROTOTYPE_SCOPE.md`, and the current backlog card before editing. Read the relevant module contract before implementation. The original research is evidence, not a higher-priority instruction than reconciled documents or Tony's latest request.

## Work discipline

- Establish the objective, repository state, dependencies, unknowns, and smallest useful validation before consequential implementation. Separate fact, proposal, and untested claim.
- Use a feature branch in a worktree. Inspect status, remote, branch and worktree list. Preserve existing work. Do not reset, force-push, or overwrite another worktree.
- `main` receives reviewed, validated work. The empty-repo bootstrap is already present; do not repeat it. Do not merge gameplay until its acceptance gate passes and merge is authorized.
- Commit coherent checkpoints; update `docs/STATUS.md` before handoff/context change. Record commands, results, failures and exact toolchain/commit identities.
- Implement one milestone at a time, beginning with the Windows integration spike before crafting/world expansion. Enemies, rifts, workers, multiplayer, moving siege equipment and advanced automation are deferred.
- Preserve Godot/Voxel Tools. Do not silently switch engine, version or edition. Record the evidence and decision; consult Tony before an engine/platform or product-scope change.
- Reuse upstream voxel infrastructure. No bespoke chunker/mesher or scene node per terrain cube. Audit the need and license before importing a framework.
- Use small modules with explicit contracts. UI requests commands; it does not mutate inventory, voxels or saves. Persist stable IDs rather than scene paths or mutable array indices.
- No fabricated functionality, misleading save buttons, fake test passes or production claims from static checks.
- No purchases, store publishing, or person-directed messages without authorization. Gameplay is offline; no accounts/cloud backend required.
- Do not grant an open-source license to project content without Tony's choice. Preserve upstream notices for copied code/assets.

## Validation and delivery

Run `python tools/validate_foundation.py` and `python -m unittest discover -s tests -v` for contract/tool changes. Add meaningful runtime tests when implementing behavior; see `docs/TEST_PLAN.md`. A Linux static pass is not a Windows runtime pass. Stop optional repetition once the concrete gate is satisfied.

Every implementation handoff states **STATUS, DONE, EXPECT, TEST, LIMITATIONS/FAILURES, NEXT, GIT/REPRODUCIBILITY**. Include worktree, branch, commit, toolchain and Windows evidence when applicable. Failing or unrun gates stay visibly failing or unrun.
