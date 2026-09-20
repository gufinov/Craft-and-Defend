# Coaster rails — side project (slopes, the loop drag tool, the mine cart)

Owner idea (2026-09-19, verbatim intent): rails that climb 45 degrees so mine carts can go up mountains, and a "roller coaster" option — click-and-drag with keys held draws interesting shapes (a loop first; a DNA strand or corkscrew later): equip a loop rail, drag out the straight lead-in, hold Shift to start a loop, X / C make it smaller / bigger while the ghost re-sizes, release lays the loop with a trailing flat exit. Later the same rails may carry mine carts hauling ore.

This is a **modular side feature**: every new file carries a `coaster` name (`game/scripts/rails/coaster_rails.gd`, `game/scripts/rails/coaster_cart_service.gd`, `game/scripts/diagnostics/coaster_rails_automation.gd`, `TEST_COASTER_RAILS.cmd`, this contract and its evidence). The core game touches it in a handful of clearly commented lines; nothing in the core depends on it beyond the `CoasterRails.chain` call that reproduces the P4C rail chain for flat rails.

## Pieces (content)

| Entity | Item stack | Footprint | Support | Mount socket | Recipe (Workbench) | Attributes |
|---|---|---|---|---|---|---|
| `rail_slope` | 32 | 1×1, `"slope": 1` | the cell below | `rail_mount` | 1 iron ingot + 2 planks → 4 (order 204) | value 4, role `rail`, mount `any_solid_top`, space 1×1×1 |
| `rail_loop` | 64 | 1×1, `"coaster_tool": "loop"` | **none** (`support_offsets: []`, pieces float) | `rail_mount` | 3 iron ingot + 4 planks → 2 (order 205) | value 6, role `rail`, mount `any_solid_top` |
| `mine_cart` | 2 | 1×1, `"cart": {"rail_speed": 3.0}` | the cell below | mounts on `rail_mount` only | 2 iron ingot + 3 planks → 1 (order 206) | value 10, role `rail` |

All three carry `navigation` / `defense` blocks like the P4C rail (wood, breachable, 30 / 30 / 24 integrity) so raiders treat them like rails. `rail_slope` is **not** `linear` (its rotation is its rise direction, turned with W / R): at rotation 0 it rises toward its front (−z); rotation 1 toward +x, 2 toward +z, 3 toward −x — the same turn as the body yaw and `EntityFootprintService.rotate_offset`. The Workbench book is now 38 recipes = four pages.

Validator (`tools/validate_foundation.py`): `attributes.role` may be `rail`; `slope` must be `1` on a 1×1 non-linear entity; `coaster_tool` must be `loop` on a 1×1 non-linear entity with no support; an entity is a slope or a tool, never both; `cart` holds exactly a positive `rail_speed` and the entity mounts on `rail_mount` only.

Icons: drawn placeholders in `tools/generate_derived_icons.py` (`icon_rail_slope`, `icon_rail_loop`, `icon_mine_cart`) appended to `DERIVED` / `DERIVED_ORDER`; `derived_atlas_p4.png` grew to four rows.

## Chain model (`CoasterRails`, `game/scripts/rails/coaster_rails.gd`)

Every placed track piece (`rail`, `rail_slope`, `rail_loop`) lists the cells it offers a joint to (`connections(record)`); two pieces are joined only when **each lists the other's anchor** (mutual rule). `chain(stations, start)` returns `{cell: Array[Vector3i] joined cells}` for the connected track; `connected_cells`, `track_records`, `ride_point`, `loop_offsets` support the visuals, the cart and the drag tool.

- **Flat `rail`**: its four same-level neighbours, plus the cell diagonally below in each direction (so a slope climbing up to it can join). Flat-only chains are exactly the P4C 4-neighbour chains — `SiegeDefenseService._rail_chain` now calls `CoasterRails.chain`, and `_rail_step` / `_chain_degree` / `_chain_end_farthest` read the joined cells from the chain instead of stepping fixed offsets, so kettles ride flat chains as before (T133 / T154 / T155 PASS) and additionally climb slopes (their turret sits half a cell higher over a slope, `_rail_point`).
- **`rail_slope`** at `a` rising toward `h`: low end → `a − h` (a flat rail) or `a − h − UP` (a same-direction slope one lower); high end → `a + h + UP` (a flat rail one up and one forward, or the next slope). A wall-top rail never joins a rail on the ground beside the wall (the lower one only lists cells one level *down*).
- **`rail_loop`**: its four same-level neighbours (so a lead-in joins ordinary rails) plus the joints recorded in its station record by the drag tool — `coaster_joints`, a JSON-safe list of `[dx, dy, dz]` offsets to the previous and next cell of the drawn path (`WorkstationService.try_place(..., extra)` merges them; `restore` keeps unknown fields, so saves round-trip). A loop piece placed by hand (no recorded joints) falls back to the eight in-plane neighbours of its rotation's vertical plane. Recorded joints are necessary because a loop's risers sit directly above its lead-in and exit cells, which pure adjacency would wrongly join.

## Loop drag tool (`InteractionService` mode `coaster_loop`)

Held item `rail_loop` → right-press starts the drag (`begin_coaster_loop_at`), like an entity line. Keys while dragging:

| Input | Effect |
|---|---|
| move the aim | stretches the flat lead-in along the dominant axis at the anchor's height (`set_drag_end`) |
| **Shift** (the Interact action) | adds the loop and **latches** it; while held the lead-in is frozen so dragging up does not stretch it |
| **X** / **C** | loop radius −1 / +1 within **2..6** (default **3**); one step per key press (edge-triggered) |
| release right mouse | commits every validated ghost cell (`COASTER_PLACED`); left press cancels as for any drag |

X and C are read as raw keys (`Input.is_key_pressed(KEY_X / KEY_C)`) by `GameSession._update_placement_preview` and handed to `interaction.coaster_loop_keys(x, c)` each frame; the service edge-triggers them. They are deliberately **not** InputMap actions: they only act during a loop drag, the keybind fixture / editor stay untouched, and X / C are unbound in the default map. Diagnostics drive `set_coaster_loop`, `resize_coaster_loop` and `coaster_loop_keys` directly.

Geometry: the loop is the ordered cells of a midpoint circle of the chosen radius in the vertical plane of the line (`CoasterRails.loop_offsets`), starting one cell past the lead-in with its bottom row at the lead-in's height, then a two-cell flat exit after the bottom row. Cell counts: radius 2 → 12 loop cells, 3 → 16, 4 → 24, 5 → 28, 6 → 32; a 4-cell lead-in with the default loop is 22 pieces. Every cell is validated with `WorkstationService.preview_placement` (air, loaded, not occupied, not the player); loop pieces need no support, so a coaster floats — accepted for the side project. The ghost reuses the P3J drag preview (green / amber / red cubes). `drag_state()` gains `loop`, `loop_radius`, `loop_cells`.

## Visuals (`GameSession`)

- `_build_rail_slope_visual`: oak deck and two iron rails inclined 45° between the low end (flat-rail top, +0.05) and the high end (+1.05 at the front edge), four ties, stone corner posts with gold studs at the low end and taller trestle posts at the high end; a tilted collision box.
- `_build_rail_loop_visual`: a piece whose joints all lie flat is drawn as the owner's rail block (`_build_rail_visual` with the arm mask from `_track_arm_mask`); otherwise a hub with a short pair of rails and a tie toward every joined cell, pitched to the joint's direction, so the ring reads as a polygonal loop. Shapes derive from the joints, not stored tangents.
- `_build_mine_cart_visual`: an oak-and-iron cart on four wheels under a `CartRig` node that the cart service moves; the model faces −z.
- `_rail_neighbour_mask` now follows the chain joints (a slope's high end puts an arm on the rail above it); `_refresh_rail_neighbours` rebuilds every track piece in the 3×3×3 neighbourhood of a laid or removed piece.

## The cart (`CoasterCartService`, `game/scripts/rails/coaster_cart_service.gd`)

A Node that `GameSession` adds only when the first `mine_cart` is placed and frees when the last one goes; `advance(delta, paused)` runs from `GameSession._process` beside the siege service. Each cart rides the chain under its own cell at `cart.rail_speed` cells/s (no gravity, constant speed) and turns around at each end. Traversal: pick the joined cell with the smallest turn from the arrival direction, never the cell it came from; a *curved* loop piece (a `rail_loop` with a joint on another level) that is unvisited and within a 90° turn wins over a flat continuation (so the cart climbs into the loop instead of running straight through the shared bottom row), while a curved piece already ridden this pass is shunned (so it leaves onto the exit); at a dead end it turns and forgets what it visited. The cart's up vector is the curvature normal on loop pieces (it leans in and hangs upside down over the top) and straight up elsewhere; the collision shapes ride along so dismantling aims at the cart. `rider_cell(id)` / `trail(id)` for diagnostics. The kettle's `_ride_rails` is not touched.

## Tests

`--coaster-rails-automation=gate` (headless): **T160** content, icons, recipes; **T161** slope chain joins two levels (six cells, control pair stays apart), the kettle router steps up through the slope, a cart rides to the top and back; **T162** loop drag ghost (4-cell lead-in; Shift → radius 3, 16 loop cells, 22 cells, frozen lead-in; X → 2 / 18; C to the limit 6 / 38; held key resizes once), commit lays 22 pieces as one chain, a curved piece draws `LoopArms` and the lead-in `RailArms`, a cart rides over the loop's top before taking the exit and returns home. `=visual` (windowed): **T163** `coaster-rails.png`. `TEST_COASTER_RAILS.cmd` runs both against the export. Regressions kept: P4 siege units gate (T133 / T154 / T155 kettles), P3D phase1, P3K gate, P3F gate + visual, P3C phase1 + visual (`EXPECTED_WORKBENCH_ORDER` and the "Page n / 4" labels updated).

## Limits — what is NOT done

- No corkscrew / DNA strand / helix; only the vertical loop. No lateral offset: the loop shares its bottom row with the entry and exit, so it is a circle of cells, not a true self-crossing loop.
- Top-row loop pieces whose joints all lie flat draw as ordinary rail blocks (rails on top), so the cart hangs under a "floor" of rail blocks over the top.
- The lead-in and exit are `rail_loop` pieces (one item, as the owner described), not ordinary `rail` items.
- Slopes are placed one at a time with W / R for the rise direction; no slope drag. A slope needs support below; loop pieces never do (floating coasters are accepted).
- Kettles climb slopes but do not route through vertical or diagonal loop joints (their junction rule keeps stepping "straight" by offset).
- No gravity, momentum or speed change; no ore hauling, no cart inventory, no right-click panel for the cart.
- Placeholder icons and box-part models; no owner art yet. Pressing X / C outside a loop drag does nothing and they cannot be rebound.

## Owner sandbox

`START_COASTER_SANDBOX.cmd` (this worktree) launches the export with `--coaster-sandbox` (`CoasterSandbox`): a new game, a stone plate beside the spawn with a premade lead-in + radius-3 loop and a slope run over a two-block step (a mine cart on each), and a pack that refills every second with rails, slopes, loops, carts, kettles, castle stone, planks, picks, sword, shot, torches and chests — nothing to mine. Its saves go to `artifacts\coaster-sandbox` so ordinary saves are untouched.

## Offset loop (owner 2026-09-20)

"In the real world a loop starts on one side and shifts so it exits parallel to the other track, not on it." The loop drag now lays: lead-in → a 45° joint one cell to the **right** of travel into the circle's plane → the circle → a 45° joint right again → the exit run, parallel to the lead-in two cells over. The circle's bottom row is still shared by the climb and the descent (that is the circle itself), but the entry and exit tracks never overlap. Pieces with a diagonal joint draw arms toward their joined cells (`GameSession._build_rail_loop_visual`); carts and kettles follow the recorded joints. Cell count is unchanged (radius 3: 4 + 16 + 2 = 22). The sandbox circuit closes from the offset exit. T162 expects the shifted cells.

## Lane Switcher (owner 2026-09-20)

Owner drawing: four blocks — an entry block, two blocks side by side in the middle carrying a 45° diagonal, an exit block one lane over — shift the track one lane. Item **Rail Switch** (Workbench 208, 2 iron + 3 planks → 4; a switcher spends four). Hold it and right-press: the four-cell ghost follows the aim, W / R turn it, release lays all four as `rail_switch` pieces with roles `in` / `mid_a` / `mid_b` / `out` and recorded joints (`CoasterRails.switch_layout`). The shift is to the **right of travel**. Entry and exit join plain rails only along the travel axis (a rail beside them in the other lane stays separate); the middles join only each other and their entry / exit. The middles' ride points sit a quarter cell onto the diagonal (`switch_mid_shift`), so carts, coaster cars and kettles (`_rail_point` now uses `ride_point`) cross in a smooth Z: straight → 45° → straight. Middle pieces draw the diagonal rails through their ride point (`_build_rail_switch_visual`). T168; sandbox demo at the plate's far edge with a mine cart (`--coaster-sandbox-switch-check` prints the crossing). Next: rebuild the loop tool on top of it (lead-in → switcher → circle → switcher → exit) — the current offset loop stays until then.

## Loop snap on a foundation (owner 2026-09-20)

Owner method: lay the loop's **base** yourself — a straight row of rails with a **Rail Slope at each end rising outward** — then aim **Rail Loop** at the base and right-click: the arch snaps up in one go (`InteractionService._snap_loop_on_base`, `CoasterRails.loop_arch_offsets`). The loop's size is fixed by the base: with the slopes 2h cells apart the arch is the upper part of a circle of radius h + 1 whose vertical sides start at the slope tops (5 rails between the slopes → radius 4, 15 pieces, 7 high). The slopes must be an even number of cells apart (an odd count of rails between them) or the snap is refused (`LOOP_BASE_ODD`); the snap needs that many Rail Loop items and free air above. The arch pieces join in order and to the two slopes, so a cart circulates: base → right slope → up → over → down the left slope → base. Entry and exit are up to the builder: two Lane Switchers put the entry lane and the exit lane beside the base row (the car enters the base from the first switcher's exit heading toward one slope, and after the loop leaves the base through the second switcher's entry), e.g. row A → switcher → base row (the loop) → switcher → row C, the second switcher one column further along so the two never share a cell. Aiming Rail Loop anywhere else still starts the old drag tool. T169; sandbox foundation on row z=41 (`--coaster-sandbox-loop-snap-check`).

### Round arch (owner: "very broken build", 2026-09-20)

The snapped arch pieces now carry the loop's true circle (`loop_center`, `loop_radius` in their records). Their ride points are the cell centres projected onto that circle (`CoasterRails.arc_point`), and each piece draws its rails as short sections of the circle from halfway to the previous piece to halfway to the next (`GameSession._build_loop_arc_visual`), so the loop reads as a smooth ring instead of a cell-centre zigzag; carts and cars ride the same projected points. The old drag-tool loop keeps the arm look.

## The Loop element (owner method, 2026-09-20) — replaces the drag tool and the base snap

Rail Loop is one element: hold it, aim at the ground where the **entry** goes and hold Right Mouse — the ghost of a **complete loop with its foundation** appears: on the entry lane the first Lane Switcher's entry and middle; the base row one lane to the right of travel holding the second switcher's middle, the first switcher's middle, plain filler pieces and a **Rail Slope at each end rising outward**; the second switcher's middle and exit on the lane two over; and the **circle** continuing the slopes' 45° incline (radius = size / √2, centred over the base's middle) as round `rail_loop` pieces that ride and draw the true circle. **4–9** (or X / C) set the base width in cells while the ghost shows (4 = the smallest: slope, two switcher middles, slope); **W / R** turn it. Release lays every piece for **one Rail Loop item** (`_free` placement); a cell in the way (ground, tree, hill, block) shows red and nothing is laid (`LOOP_BLOCKED`). Plain rails join the entry (behind it) and the exit (ahead, two lanes over). Riders: entry → switcher → base → far slope → up, over the top, down the near slope → base → switcher → exit; a closed circuit needs only rails from the exit round to the entry. `CoasterRails.loop_element_layout`, `InteractionService._replan_loop_element` / `_commit_loop_element`; T162 (sizes, item, chain, ride, blocked, save round-trip), T163 (render), sandbox size-6 loop with a circuit (`--coaster-sandbox-facing-check`: 0 reversals). Base-row fillers are `rail_switch` pieces with role `fill` (join only along the row). The base-snap and drag-lead-in methods are gone.

### Sandbox cleared; steady heading (owner 2026-09-20)

The sandbox plate holds only the size-6 loop, its circuit and the coaster car. A cart's body heading now follows the chord from the previous cell's point to the target's point, eased at `HEADING_RATE` 10/s (`CoasterCartService._ride`); aiming at the very next point made the body flick sideways where two points sit close together on the circle or across a switcher.

### Octagon loop; no roll (owner 2026-09-20)

The loop element's ring is now an **octagon** of straight pieces (owner: "build it more like an octagon so the rails remain flat"): from each slope's top a vertical run of size − 2 pieces one column outside the slope, then a flat top row of `size` pieces whose end pieces join the runs diagonally; as wide as the base plus the runs and as tall as it is wide. Every piece rides its cell centre; the top row draws as rail pieces, the runs and corners as loop arms. The ride view rolled because a cart's up vector was the cell-quantised curvature normal (departure − arrival), which flips on stair-step cells; loop pieces now carry the loop's centre (`loop_up_center`, `CoasterRails.lean_center`) and riders lean straight at it (`CoasterCartService._up_at`): upright on the runs' outer side, inverted over the top, never sideways. The true-circle arc code (`loop_center`, `_build_loop_arc_visual`) stays available but unused by the element.

### Two ring shapes, one track style (owner 2026-09-20: "improve this one and still experiment with the round one")

While the loop ghost shows, **L** toggles the ring shape: **octagon** (default; straight runs and 45° corners) or **round** (the true circle, tangent to the slopes' rail corners at `SLOPE_RAIL_TOP` 1.04, pieces riding the circle). Both are drawn with one track style (`GameSession._build_loop_track_visual`): two iron rails with wooden ties and a stone spine on the outer side, running from each piece's point to halfway toward its neighbours (arc sections for round pieces) and all the way to a slope's rail corner (`CoasterRails.slope_rail_corner`) so the ring continues the incline without a kink - no posts or floating rail blocks (the owner's alignment screenshot). Both shapes lean riders at the loop's centre. Sandbox: `--coaster-sandbox-round` lays the round one; both traced with 0 reversals and a smooth up vector. T162 checks the round ghost.

### Round ring locked in (owner 2026-09-20: "the round ring is best ... lock this in")

The loop element's ring is the true circle only; the octagon and the L toggle are gone. Two fixes for "raise the loop slightly and it would fit": (1) a ring piece's point never drops below the slopes' rail corners (`loop_corner_y`; `CoasterRails.arc_point` snaps the first and last pieces to the corner instead of dipping under it), and (2) the slope's high-end trestle posts now stop just under its rails (they used to poke half a block above the rail corner, which made the ring look too low where it meets the slope). Verified: ring end at the slope corner in a zoomed render; 0 reversals, smooth up vector on a lap.

### Ring fit A / B / C (owner comparison, 2026-09-20)

While the loop ghost shows, **L** cycles the ring fit: **A** tangent at the slopes' rail corners (the default), **B** the circle raised 0.25 above them, **C** raised 0.5 (`CoasterRails.LOOP_LIFTS`, `loop_lift` on the ring pieces; the last bit of rail bridges the lift down to the slope corner). All three ride the same (traced, 0 reversals apart from the approach). Once the owner picks one it becomes the only fit. Sandbox: `--coaster-sandbox-lift=1|2`.

## The TRUE loop (owner 2026-09-20) — default Rail Loop

"A true loop that starts in one lane, loops up and over while gradually changing lanes so that both end points land on the foundation side by side, like a real coaster loop." Rail Loop now lays a **helix**: one turn of a circle in the vertical plane of travel whose track drifts one lane to the right of travel while going round (`CoasterRails.helix_layout` / `helix_point` / `helix_theta`). It touches the ground only at the **entry** cell (the aim) and the **exit** cell one lane over; every other piece floats and rides / draws the helix itself (`ride_point` projects the cell centre onto the helix; the track style is the rails + ties + outer spine). Size = the circle's diameter in cells, 3..64: **hold Shift while the ghost shows and aim further from the entry** (the aim's distance sets the diameter), or 4-9 / X / C. W / R turn it. Plain rails join the entry (behind it) and the exit (ahead, one lane right); the entry and exit pieces join nothing else, so the two lanes never short-circuit. Riders lean at the (drifting) circle centre - upright at the bottom, inverted over the top. **L** while the ghost shows switches to the classic foundation loop (switchers, slopes, ring at fit C - the owner's pick) and back. Sandbox: diameter-8 true loop in a closed circuit (`--coaster-sandbox-classic` for the other); traced 0 reversals. T162 covers both.

### Pack-sized loops (owner 2026-09-20)

In the real game a true loop costs **one Rail Loop item per piece**, drawn from anywhere in the pack, and the Shift-drag stops at the largest diameter the pack can pay for (`InteractionService.loop_diameter_limit`) and never above the world's ceiling. Pieces the pack cannot afford show amber. The sandbox is **creative** (`interaction.creative`): free and sky-limited only. The family of smooth pieces that follows is planned in [CoasterCraft tracks](COASTERCRAFT_TRACKS.md).
