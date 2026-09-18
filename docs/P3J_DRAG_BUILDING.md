# P3J — drag building

## Outcome

Walls are built by holding right-click and dragging (owner direction 2026-09-18). With a block item held, a right-press anchors a plan; moving the aim stretches it into a row, a column or a wall; release builds every affordable cell in one transaction; a left-press while still holding right cancels with nothing built.

## Runtime contract

- `InteractionService.begin_drag_place` anchors at the aimed placement cell for the active `places_block` item (`begin_drag_at` for a known cell). `update_drag_place` re-plans from the current aim each frame (`set_drag_end` for a known cell). `commit_drag_place` builds; `cancel_drag_place` discards. `drag_state()` exposes the plan for presentation.
- **Shape rule** (`drag_plan_cells`): the anchor→end delta picks the dominant horizontal axis (x or z); a horizontal delta alone is a *row*, a vertical delta alone a *column*, both a *wall* (rectangle in the vertical plane). Runs are clamped to `DRAG_MAX_SPAN` (16) per axis. Cells are ordered support-first: outward along the horizontal axis, then upward.
- **Per-cell validity** (`_drag_cell_reason`): the same rules as single placement — loaded, air, no station, no player overlap, six-face support — except that earlier planned cells count as support, so columns and walls rise from one anchor.
- **States**: `ok` (will build), `blocked` (invalid, skipped), `unaffordable` (valid but beyond the carried count; trimmed). Blocked cells do not break the chain for cells they would not have supported.
- **Commit** revalidates, writes each `ok` cell, then runs one inventory transaction for the count. Any failure rolls back every written cell. Result reason `DRAG_PLACED` with `cells`, `count`, `voxel_after` and `items`; `DRAG_EMPTY`, `INSUFFICIENT_BLOCKS`, `STALE_REVISION`, `WORLD_WRITE_FAILED`, `INVENTORY_COMMIT_FAILED` otherwise. `DRAG_CANCELLED` on cancel.
- **Input** (`PlayerController`): right-press → `secondary_press_from_view` (station opens as before; block item starts a drag; entity item places at once as before). Right-release → `secondary_release_from_view` commits. Left-press while a drag is active → cancel, and neither break nor melee fires. A simple click is a press+release on one cell and places one block on release.
- **Presentation** (`GameSession._update_drag_preview`): one ghost per planned cell — green (with the block texture) for `ok`, amber for `unaffordable`, red for `blocked` — each inside a dark translucent frame so the plan reads against grass.
- Diagnostics and other services keep the direct `try_place_item` / `secondary_from_view` API.

## Acceptance

- T108 (P3D gate): row of 6, column of 3 rising from planned support, 4×3 wall with one pre-blocked cell skipped and one trimmed by stock, exact inventory accounting, cancel leaves world revision and inventory unchanged.
- T109 (P3D visual): rendered multi-cell ghost.
- T42–T45/T50 castle kit, T72–T77 P3C, T79–T83 P3D, T90/T91/T105 P3F unchanged and passing.

## Boundary

No post-build undo, no entity (multi-cell footprint) dragging, no free-floating placement, no diagonal or filled-volume shapes, no drag-break.
