# Test and acceptance plan

Runtime rows begin **NOT RUN** and change only through recorded runtime evidence. T01–T12 are owner-accepted PASS as of 2026-09-10 in [the F0 evidence record](evidence/F0_WINDOWS_INTEGRATION.md). T13–T18 are owner-accepted PASS as of 2026-09-11 in [the F1 evidence record](evidence/F1_INTERACTION_HARDENING.md). Tony's ultrawide tests exposed and verified corrections for fixed-aspect pillarboxing and window placement that ignored a nonzero monitor origin. The final exported gate tests native fill, active-monitor identity, decorated bounds and negative virtual-desktop coordinates. Passing repository checks alone does not change a runtime gate. Record later results per test ID in an evidence file copied from [the template](evidence/TEMPLATE.md), including actual/expected behavior and artifacts. Use isolated disposable saves for failure injection.

## Existing repository checks (G0)

`python tools/validate_foundation.py` checks JSON structure/cross-references, unique stable IDs, tool/station progression reachability, default control conflicts, bounds/placement fixture expectations, release manifest shape, original-report hash and local Markdown link targets. `python -m unittest discover -s tests -v` tests rejection of invalid variants. These are static contract checks only; the reachability proof ignores finite resource quantities and spatial accessibility.

## Runtime gates

| ID | Gate | Test / required result |
|---|---|---|
| T01 | F0 | Record archive hashes, editor version, module classes and renderer; wrong editor fails clearly |
| T02 | F0 | Clean launch opens menu; player enters only by Start; Quit from menu works |
| T03 | F0 | Start loads correct finite bounds; collision-ready spawn never falls through unloaded terrain |
| T04 | F0 | E/D/S/F, jump, mouse look work; keyboard/pointer usable after pause/resume |
| T05 | F0 | Break dirt, receive exactly one dirt, place it elsewhere, consume exactly one |
| T06 | F0 | A block can attach to any solid side face with air below; truly floating, outside-bounds, occupied and player-overlap placements fail without inventory/world mutation |
| T07 | F0 | Escape pauses; menu/settings stay responsive; Resume restores intended state |
| T08 | F0 | Rebind forward, save settings, fully restart; new key works and default/reset behavior is clear |
| T09 | F0 | Save/exit/restart/Continue preserves edited cells, player transform and exact inventory counts |
| T10 | F0 | Move far enough to unload an edited chunk, reload it, save/quit/restart; edits remain |
| T11 | F0 | Export with custom release template; launcher rejects/rebuilds a stale checkout package; launch outside editor; repeat T02–T09 |
| T12 | F0 | Window-close/Alt-F4 during play follows coherent save workflow; failure stays visible |
| T13 | F1 | All defaults, conflict rejection, cancel capture and reset work; UI actions never mine/place |
| T14 | F1 | Inventory/settings/focus-loss pause; mouse capture restored only on explicit resume |
| T15 | F1 | Negative coordinates and all six bound faces/corners use half-open bounds; bottom protected |
| T16 | F1 | Rapid clicks/stale request/full inventory/wrong tool cause no duplication or resource loss |
| T17 | F1 | Multi-cell synthetic footprints reject partial overlap, unloaded cells, unsupported cells and player overlap; removal releases all owned cells once |
| T18 | F1 | Display changes revert if unconfirmed; fullscreen reports/fills the active monitor; windowed previews stay within that monitor's usable decorated bounds; 16:9/ultrawide/high-DPI menus remain usable |
| T19 | F2 | Empty-inventory player reaches wood pick → stone pick → smelted iron → iron pick with no debug grants |
| T20 | F2 | Insufficient input/tool/workstation/output capacity leaves inventory unchanged; recipe output exact |
| T21 | F2 | Bench/furnace placement consumes one item; support/dismantle rules prevent orphans/duplicates |
| T22 | F2 | Furnace consumes input/fuel once, pauses correctly, reserves output and completes once |
| T23 | F3 | A/B save slots and rapid menu/new/continue cycles have no terrain/state contamination |
| T24 | F3 | Inject denied write/full disk and interruption around checkpoint publication; previous complete checkpoint remains loadable |
| T25 | F3 | Malformed/newer/missing-content save is refused clearly without replacement; supported migration copies original |
| T26 | F3 | Save/restart midway through furnace job preserves remaining time and produces exactly one output |
| T27 | F4 | New world begins at visible 08:00 sunrise; validated World Settings apply `HHMM`/`HH:MM` and cycle toggle; day/night advances during play, freezes when disabled or in overlays/pause, restores phase/day/toggle; no offline catch-up |
| T28 | F4 | Blocks/resources distinguishable; selection, craft feedback and key help visible; rebindable F2 captures the rendered viewport in the background without pausing; no placeholder functional claims |
| T29 | F4 | Measure frame times, edit latency, memory, save size/latency in fixed scenario; record hardware/build/renderer/resolution |
| T30 | F4 | Fresh portable folder launch with editor closed runs full Foundation loop; README run/save-location instructions accurate |
| T31 | F5 | Tab opens inventory only; B opens/closes 2×2 hand crafting; both pause and block world mutations; B persists/rebinds safely |
| T32 | F5 | Right-clicked workbench opens 3×3 station modal without placing; Shift cannot bypass; non-station right-click still places; workbench recipe book contains both hand and advanced recipes |
| T33 | F5 | Furnace owns ore+fuel processing modal; recipe results remain atomic and timed jobs complete exactly once |
| T34 | F5 | Inventory and crafting presentations remain legible/keyboard-usable at 1280×720 and 3440×1440; labels do not imply unimplemented content |
| T35 | F5 | 4× MSAA, VSync and physics interpolation default on; quality preferences persist; sunlight shadow transforms remain stable within a visual minute and use bounded blended splits |
| T36 | F5 | Three-panel crafting shows inventory/grid/scrolling recipe book; inventory drag/click staging, recipe search+Enter autofill, manual recognition and atomic craft validation work |

## Performance evidence, not invented guarantees

Use the 64×32×128 fixture and a scripted or documented route with at least 100 edits and a save/reload. Record median/p95 frame time, longest edit hitch, memory and save duration. Suggested initial usability targets are 60 FPS with ordinary movement and visible edit response under 100 ms on the designated test PC; these are **provisional targets**, not a tested minimum specification. Record failures and determine cause before tuning or enlarging the world.

## Runtime test layers

Automate pure inventory/crafting/occupancy rules in GDScript tests; integration-test actual VoxelTerrain edits and save/load in the pinned engine. Add manual Windows tests for pointer, UI, export and failure recovery. Reuse or add a small test runner only when needed; no testing framework dependency has been selected. Port static placement fixtures into runtime tests, but do not mistake the Python oracle for a test of Godot physics or collision meshes.
