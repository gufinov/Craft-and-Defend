# Keybind contract

Canonical fixture: [keybinds.json](../contracts/keybinds.json). Bind named actions through Godot InputMap, using physical QWERTY positions for movement. Runtime rebinding must persist, detect conflicts by active context and provide reset defaults.

F5 candidate status: every currently implemented action below except reserved `reload` has a grouped, searchable editor row with Change and per-action Reset. The centered scrollable panel keeps Reset All available and reports capture/conflict state clearly. Changes persist across a full process restart. Invalid/conflicting stored maps recover to the complete safe default map; live conflicts mutate neither action.

| Action ID | Default | Context |
|---|---|---|
| move_forward | E | gameplay |
| move_backward | D | gameplay |
| strafe_left | S | gameplay |
| strafe_right | F | gameplay |
| sprint | A | gameplay |
| crouch | Z | gameplay |
| jump | Space | gameplay |
| interact | Shift | gameplay |
| inventory | Tab | gameplay |
| build | B | gameplay |
| rotate_build_clockwise | W | gameplay |
| rotate_build_counterclockwise | R | gameplay |
| pause | Escape | system |
| hotbar_1 … hotbar_9 | 1 … 9 | gameplay |
| reload | G | gameplay, reserved until relevant |
| primary | MouseLeft | gameplay |
| secondary | MouseRight | gameplay |
| capture_screenshot | F2 | gameplay |

`Z` implements crouch; prone is deferred. Sprint is hold-to-run initially. `G` is reserved; do not invent a reload mechanic for a pickaxe. Left mouse breaks/dismantles. Right mouse first opens a targeted station and otherwise places the selected item. Shift remains the general Interact action but does not open current crafting/processing stations; targeting one explains that right-click is required. P3H assigns separate W clockwise and R counterclockwise preview rotation actions. W is intentionally a build control, not forward movement; physical E remains forward under the ESDF layout.

Coaster rails side project ([contract](COASTER_RAILS.md)): while a Rail Loop drag is active, **X** shrinks and **C** grows the loop radius (while a Climb drag is active they lower / raise the rise). They are read as raw keys only during that drag, are not InputMap actions and cannot be rebound; X and C are otherwise unbound.

CoasterCraft curves ([contract](COASTER_RAILS.md#flat-curves-90-u-turn-free-curve-coastercraft-card-4-2026-09-20)): while a Curve (`rail_curve`) ghost shows, **4–9** set the bend's radius (they do not change the hotbar slot), **X** / **C** shrink / grow it, **W** / **R** turn the entry heading, and **Shift** held aims the arc (the aim's angle from the travel direction picks 45° / 90° / 135° / 180°, aiming left of travel mirrors the bend, half the aim's distance is the radius). X and C are raw keys as for the loop.

Coaster car and hero ([contract](COASTER_CAR_AND_HERO.md)): **Shift** (Interact) aimed at a parked Coaster Car boards it; while riding, **1–9** set the car's speed in cells per second (they do not change the hotbar slot) and **Shift** or **Escape** leaves the car (Escape leaves before it pauses). On foot, **V** toggles third person (chase camera with the hero visible). V is read as a raw key like X / C: not an InputMap action, not rebindable, otherwise unbound.

Tab toggles inventory only. B toggles the limited hand-build/crafting modal; a workbench or processing-station modal is entered only by right-clicking that world object. Escape closes the active modal before pausing. F2 captures the game viewport to the global `screenshots` folder without pausing gameplay; it can be rebound like every other implemented action and remains separate from Windows Print Screen focus handling. Preserve an Escape recovery/cancel path even if users rebind their preferred pause action. UI navigation may use conventional keys only while the UI owns input; ESDF gameplay input must not leak through it.

Tests: every required action responds; forward is E (not W); a changed movement key persists after full restart; conflicting assignment is rejected/explained; reset restores these defaults; escape from capture/modal/pause works; repeated UI open/close does not leave mouse capture stuck. Test keyboard layout behavior on Windows rather than assuming logical key codes equal physical positions.

- **While riding a Coaster Car**: mouse turns the head (±110° / ±60°, no turning around); **1–9** speed; **arrow keys** outside views (↑ behind, ↓ front, ← → sides; same arrow again = seat); **Shift** / Escape leave.

- **U or Ctrl+Z - Undo**: takes back the newest placement - a whole lay (loop, curve, climb, switch, crossing, rail line) or a single piece / block: its pieces go, terrain it auto-cleared comes back (the mined blocks leave the pack), and the items it cost return (what fits in the pack). Twelve steps deep, this session only (not saved). Raw key like V / X / C, not rebindable.
- **Every coaster tool** (loop, climb, curve, bend / cross, switch): the aimed cell is the piece's **entry** and the piece heads **the way you face** when you press (the ghost extends away from you); **W / R** turn it afterwards; a **Shift-drag re-aims** a climb or loop along the drag, and a bend / cross dragged behind its entry flips to head that way.
- **Rail Loop held**: hold Right Mouse for the loop ghost (a true helix loop); **hold Shift and aim further away** to size it (or 4–9 / X / C); **L** classic foundation loop; **W / R** turn it; release to build.
- **Climb held**: hold Right Mouse at the entry for the whole climb's ghost (slope-in, grade, slope-out); **hold Shift and aim at the landing** (a hilltop; below the entry for a descent) to set its length and rise; **4–9 / X / C** set the rise; **W / R** turn it; release to build.
- **Rail Bend (Smooth Switch) / Rail Cross (Crossing) held**: hold Right Mouse for the S-bend ghost (the crossing: two S-bends that swap lanes); **hold Shift and aim where the exit goes** — forward distance = length (3–40), sideways offset = lanes (−6..6, left or right); **4–9 / X / C** length; **W / R** turn it; release to lay it (one item per piece, all or nothing).
- **Pause menu - Track auto-clear: on/off** (`[track] auto_clear` in settings.cfg, off by default): when on, every track lay tool (loop, lane switcher, rail line, single rail / slope) shows natural terrain in its way amber-orange and mines it on release (drops to the pack); water, bedrock, castle stone, planks and entity cells stay red. See [Coaster rails](COASTER_RAILS.md).
