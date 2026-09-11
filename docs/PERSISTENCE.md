# Persistence and recovery design

**Status: F3 implementation gate PASS; owner playtest/promotion pending.** The coordinator publishes terrain, player, full inventory/hotbar and workstation/job state in one checkpoint. Independent A/B slots, interrupted publication recovery, invalid-save refusal, legacy-layout copy migration, mid-job restart and injected denied-write/full-disk behavior pass in the provenance-matched Windows export.

## Ownership and format

Use a dedicated custom Godot user-data directory such as `CraftAndDefend` and save under `user://`, outside the executable/project. Development, automated tests and normal play use different user-data roots. The exact resolved Windows path must be shown in diagnostics/evidence. A slot ID is a generated stable identifier, not an arbitrary user-supplied filesystem path.

| Data | Storage responsibility |
|---|---|
| Voxel edits | VoxelStreamSQLite database, fresh stream per active session |
| Slot identity/config | Versioned metadata: slot ID, schema, seed, generator version, bounds, content version |
| Gameplay snapshot | Player transform, inventory/hotbar, equipment, entities/workstations, jobs, simulation clock phase/day/cycle-enabled state, snapshot revision |
| Settings | ConfigFile/equivalent outside slots: bindings, audio, video, sensitivity |

Store explicit schema and content versions. Keep block numeric IDs stable; never reorder them across existing saves. Unknown/newer schema or missing content produces a readable refusal, not an empty replacement world. A migration copies the slot and reports a new version; it does not mutate the sole original copy.

## Minimum coherent checkpoint approach to prove

For the tiny Foundation world, favor simplicity over storage efficiency: keep a working session database separate from the last published checkpoint. A committed checkpoint directory contains **both** voxel data and gameplay state with one manifest. Load copies/opens an appropriate working copy so continuous chunk saves do not mutate the last good checkpoint. F3 keeps two completed checkpoints and prunes older generations only after the new pointer is published.

Saving freezes gameplay mutations, workstations, clock and viewer movement, captures one state revision, drains terrain saves, then obtains a verified consistent database snapshot. Write to a new temporary checkpoint directory, validate metadata/database compatibility, and only then publish a manifest/pointer to that completed directory. Returning to menu/quit proceeds after the coherent checkpoint is complete. Pending generations are ignored/reported on restart.

**The exact safe database snapshot/close barrier is an F0 investigation, not an assumed API.** Do not copy an open SQLite database with ordinary file copy, ignore possible journal/WAL companions, or assume a node being freed means all asynchronous I/O is finished. Use a supported consistent backup or verified stream-close/drain approach; document source evidence and force-stop tests. If that cannot be made reliable cheaply, propose a different save design before extending gameplay.

This checkpoint plan introduces bounded disk overhead for the tiny world. The final provenance-matched export measured 23,229–23,652 bytes per checkpoint and 45–66 ms per F3 save on the recorded test machine; this is not a final large-world storage architecture. No promise of power-loss durability is made merely because rename succeeds. The practical Foundation requirement is reliable normal saves and preserving the prior complete checkpoint on interrupted saves.

## Voxel-specific hazards

The pinned [VoxelTerrain API](https://github.com/Zylann/godot_voxel/blob/595f52ee4e23203a865eeb981f115909f7aa92f4/doc/source/api/VoxelTerrain.md) returns a `VoxelSaveCompletionTracker` from `save_modified_blocks()`. Poll `is_complete()` with frame-yielding coordination and check `is_aborted()`; do not invent a completion signal. The tracker does not cover later saves, and unloading chunks may schedule independent writes. A tracker completion by itself is **not** a cross-file commit or an all-stream-work barrier.

The [stream documentation](https://voxel-tools.readthedocs.io/en/latest/streams/) explains asynchronous writes and stream reuse hazards. Allocate streams at runtime, never repoint one while tasks may still reference it. Keep the old session/stream alive through safe teardown. Do not use a fixed sleep as correctness proof.

## Save UI and failure behavior

Show Saving with a responsive progress/status surface; block repeated save/load requests. On error/timeout, keep the session recoverable and the previous completed checkpoint intact. Offer Retry or return to the paused session. A forced discard/quit must explicitly say unsaved progress will be lost; never mark a failed save successful. Window-close/Alt-F4 uses the same coordinator as Quit; the editor Stop button is a force-kill, not a normal save test.

Furnace inputs/fuel are consumed once when a job starts. Save job identity, reserved output, remaining simulation time and completion status so reload neither duplicates output nor consumes inputs twice. No offline catch-up in Foundation. Global input/audio/display settings persist independently; World Settings deliberately mutate the active slot and persist through its next coherent world checkpoint.

## Required evidence

Normal exit/reopen; repeated saves; A/B slot isolation; edited chunk unload/reload; rapid new/continue cycles; denied-write and full-disk simulation; interrupted checkpoint before/after publication; malformed/newer metadata; missing content; no pending-write contamination. Prove that terrain changes and inventory counts come from the same completed checkpoint. See [test plan](TEST_PLAN.md).
