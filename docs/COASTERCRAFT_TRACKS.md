# CoasterCraft tracks — the smooth-track family (design, 2026-09-20)

Owner direction: "we can build rail systems with fluid, proper curves rather than blocky looking Frankenstein creations." The true loop proved the method: a track piece does not have to be a box — it occupies the cells its curve passes through, **rides and draws the curve itself**, and only its ends need to land on ordinary cells. This document is the plan for the whole family. Nothing below is built until its card is picked; the loop (draggable, pack-sized) is done.

## The one engine every piece shares: `TrackCurve`

Today the loop pieces carry ad-hoc fields (`helix_center`, `loop_center` …) and `CoasterRails.ride_point` / `GameSession._build_loop_track_visual` special-case them. Step one for the family is one description a piece can carry instead:

```
curve: {kind, origin, basis (along, side, up), params, t0, t1}
kinds: line | arc (radius, sweep, plane) | helix (radius, pitch, turns) |
       s_bend (length, lateral shift, height shift) | vertical_arc (radius, sweep)
```

- `CoasterRails.curve_point(curve, t)`, `curve_t(curve, point)` (nearest t) → `ride_point` = `curve_point(curve_t(cell centre))` for every curved piece; `lean_center` = the curve's centre of curvature at t (or straight up when the curve is straight) → riders lean into every bend, not just loops.
- A **lay tool** samples a curve finely, collects the cells it passes (in order), records each cell's `t0..t1` and its joints (previous / next cell; the ends join the cells beyond), validates every cell (`preview_placement`; loop pieces float, ground pieces need support only where the curve is at ground level), prices it (one Rail Loop item — or the piece's own item — per cell in the real game; free in creative), and lays it all-or-nothing. This is the loop tool generalised (`_replan_loop_element` / `_commit_loop_element` become `_replan_curve` / `_commit_curve`).
- The **visual** samples the piece's own `t0..t1` into sections and draws the rails + ties + outer spine we already have; a shared `_build_curve_track_visual` replaces the loop visual.
- Riders: `CoasterCartService` already follows joints and ride points; nothing changes. Kettles too.

With that in place every piece below is a curve description plus a drag gesture.

## Status

**Card 1 is in** (2026-09-20): `game/scripts/rails/track_curve.gd` (`TrackCurve`: `make_*`, `point`, `tangent`, `up_at`, `nearest_t`, `cells`, `pieces`, `piece_t`). A record with `curve` + `t0`/`t1` rides the curve (`CoasterRails.ride_point`), joins only its recorded joints (`connections`), leans by `TrackCurve.up_at` (`CoasterCartService._up_at`) and draws with `GameSession._build_loop_track_visual` (same-curve neighbours are followed along the curve). The true loop is `TrackCurve.make_helix` laid by `TrackCurve.pieces`; the classic loop ring still uses `loop_center` (fine, it is the fallback). Cards 2–6 and 8 are open for agents.

**Card 4 is in** (2026-09-20, `feature/coaster-curves`): the **Curve** item (`rail_curve`) lays the 90° curve, the U-turn and the free curve (45 / 90 / 135 / 180 by Shift-aim, left or right, radius 2..30) as one flat, banked `make_arc` of `rail_loop` pieces; see [COASTER_RAILS.md — Flat curves](COASTER_RAILS.md#flat-curves-90-u-turn-free-curve-coastercraft-card-4-2026-09-20). Open: a plain rail cannot join a diagonal (45 / 135) end — only another curve continues it.

## The pieces

| Piece | Curve | Drag gesture | Notes |
|---|---|---|---|
| **Loop** (done) | helix, 1 turn, drift 1 lane | Shift + aim distance = diameter; pack-capped | entry / exit on neighbouring lanes |
| **Smooth lane switcher** | s_bend: lateral shift of *n* lanes over length *L*, cosine profile | drag along = length, sideways = lanes | replaces the 4-block switcher's kinked diagonal; the block switcher stays for tight spots |
| **X crossing** | two s_bends crossing in the middle cell | drag like the switcher; Shift mirrors the second | one cell carries two tracks: the piece records two joint pairs; a rider keeps to the pair it arrived on |
| **90° curve** (done) | arc, sweep 90°, radius *R* | Shift-aim ahead-right; half the distance = R | banked: lean toward the inside |
| **U-turn** (done) | arc, sweep 180°, radius R | Shift-aim behind: lanes apart = 2R | |
| **Free curve** (done) | arc, 45 / 135 | Shift-aim ahead (45) or straight right (135); left mirrors | diagonal ends chain curve to curve |
| **Slope-in / slope-out** | vertical_arc (concave into a climb; convex over a crest) | drag up: the climb angle | any grade, not only 45°; pairs with the straight climb |
| **Straight climb** | line at a grade | Shift-drag up and along | the mountain straight |
| **Winding snake** (switchbacks) | macro: climb + banked U-turn, repeated | drag from the foot to the summit; the tool lays N switchbacks that fit | the mountain road |
| **Corkscrew** | helix around the travel axis (pitch = its length) | Shift + aim distance = length | the loop's cousin; riders invert sideways |
| **Splitter (Y)** and **merge** | two arcs leaving one cell | drag the branch; Shift toggles which way the switch points | a switch state on the piece; a lever later |
| **Supports** | — | automatic | trestle posts from floating pieces down to the ground (visual only); the biggest single prettiness gain after the curves |

Sizes are limited by the pack in the real game (one item per cell) and by the world ceiling; creative mode (the sandbox today, a game mode later) is free.

## Global: auto-clear terrain

A setting (Settings → World, and a pause-menu toggle, saved in settings.cfg): **Auto-clear terrain for track: on/off**. On: cells a track piece needs that are ground, tree or leaves are dug as the piece is laid (voxel → air; the block's drop goes to the pack as if mined, so it is not free) and the ghost shows those cells amber instead of red. Off (default): red ghost, nothing laid — exactly today. Protected blocks (bedrock, water, the cores, player-built stone) are never auto-cleared.

## Order of work (owner's list)

1. `TrackCurve` core + the lay tool generalised (the loop moves onto it; no visible change). *Me, integration worktree — the other cards depend on it.*
2. Smooth lane switcher. 3. X crossing. 4. 90° curve + U-turn. 5. Slope-in / slope-out + straight climb. 6. Auto-clear terrain. 7. Winding snake. 8. Supports. 9. Corkscrew. 10. Splitter / merge.

Cards 2–5 and 6 are independent once 1 is in and can go to agents in their own worktrees in parallel; 7 needs 4 and 5; 8 is independent.

## CoasterCraft as its own game

The rails module is already separable: `game/scripts/rails/*`, the coaster diagnostics, the sandbox, and the content entries under `attributes.role == "rail"`. A spin-off would take those plus the voxel world, the player, the hero and the car, and drop the defense layer. Nothing in the family above needs the defense side, so building it here keeps that door open.
