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
| T37 | P1 | New worlds select `terrain_p1_1` with seed 41026; metadata-free saves select legacy flat generation; unknown generator versions are refused |
| T38 | P1 | The pinned seed reproducibly yields hills, valleys, flat safe clearing, trees and coal/iron while fixed starter resources remain reachable |
| T39 | P1 | Exploring outside the clearing shows an updating home distance/bearing cue; returning reports `HOME CLEARING` |
| T40 | P1 | Save/full-process-restart/Continue restores terrain edit, player location and exact generator version/seed; legacy routing remains unchanged |
| T41 | P1 | Terrain is visually readable at 1280×720 and owner ultrawide; fixed exploration route records frame/edit/save evidence without blocking streaming |
| T42 | P1 | Workbench exposes stable IDs/recipes for stair, wall-walk slab, parapet merlon, tower platform and open gate frame; the platform has a typed future defense mount socket |
| T43 | P1 | Entity preview is non-mutating; quarter-turn rotation transforms occupied/support cells; unsupported, partial-overlap, unloaded and player-overlap placements reject atomically |
| T44 | P1 | A selected structural item shows a green/red world preview, X rotates it, right-click commits only a valid preview, and collision geometry matches the visible piece |
| T45 | P1 | Save/full-process-restart/Continue restores every structure once with anchor/orientation; dismantling releases the complete footprint and refunds exactly one item |
| T46 | P1 | First castle kit and workbench recipe list are legible at 1280×720 and owner ultrawide; stairs, wall walks, parapets, platform and gate opening support a useful small build |
| T47 | P1 | Tab separates 18 carried slots, one equipped 1–9 hotbar row and a full-height six-position armor loadout without changing the authoritative 27-slot accounting |
| T48 | P1 | The three-section inventory and original character guide are readable and unclipped at 1280×720 and the 1720×720 logical ultrawide viewport used for 3440×1440 fullscreen validation; unavailable armor interaction is stated truthfully |
| T49 | P1 | Drag/drop and the two-click keyboard fallback move or swap exact Carried/Hotbar slots; category filters are view-only; sorting reorders only the 18 Carried slots in one inventory revision; the resulting snapshot restores exactly |
| T50 | P1 | Stone stairs render and collide as exactly two half-block steps; sustained ordinary forward movement climbs both without Jump, while step-up remains capped below a full block |
| T51 | P2 | The pinned Module exposes the inspected `VoxelAStarGrid3D` API and the local spike contract fixes one cardinal 1×2-cell agent with bounded step/drop rules |
| T52 | P2 | Both planners route a single agent around a corridor wall; the local planner also accounts for a placed stair entity and validates every returned transition with zero stuck cases |
| T53 | P2 | A two-cell trench and one-cell tunnel clearance produce no unsafe route; removing one bridge cell invalidates the route and an incremental snapshot refresh observes the exact changed cell |
| T54 | P2 | A blocked unarmed agent reports `NO_ROUTE`; a basic raider attacks allowed earth/wood but not castle stone; a siege candidate can target fortification; no fake path is returned through an intact obstruction |
| T55 | P2 | The fixed 13×5×13 fixture records full/incremental snapshot cost, median/p95 query time, visited cells, route validation and a clearly labelled memory-scale estimate for both approaches where available |
| T56 | P2 | A rendered 1280×720 diagnostic visibly distinguishes start, goal, wall, local route and 1×2 probe at the goal; it is evidence only and does not imply production enemy locomotion |
| T57 | P3 | An explicit paused-menu action creates one practice barricade and one stationary mounted ballista, then gives a readable five-second warning before exactly one raider spawns |
| T58 | P3 | One physical 1×2 raider follows the selected P2 local obstruction plan; voxel and placed-entity add/remove events refresh only exact changed cells in its bounded snapshot |
| T59 | P3 | The raider visibly damages the barricade; Shift-use through the real physics target path consumes exactly one Planks item and restores six integrity; full/no-material attempts do not mutate state |
| T60 | P3 | The stationary ballista engages after the first wall hit, consumes exactly four visible bolts for four five-damage shots and defeats exactly one 20-health raider while retaining readable wall damage |
| T61 | P3 | Defense phase, arena, wall integrity, ammunition, raider health/position and navigation revision survive service snapshot/restore without duplicating fixtures |
| T62 | P3 | Save during an active attack and fully restart; Continue restores exact wall integrity, remaining bolts, raider health and one reconstructed physical raider |
| T63 | P3 | A rendered 1280×720 frame shows the physical raider, damaged barricade, mounted ballista and readable defense HUD; owner playtest decides readability/fun |
| T64 | P3 | The live gameplay HUD shows all nine held/hotbar slots, their key, item identity and count; changing keys moves the selected **HELD** state and mirrors the Tab inventory hotbar |
| T65 | P3 | A ballista shot requires a clear direct physics ray to the raider; an inserted solid blocker causes no damage or ammunition consumption, and a clear shot renders a visible travelling bolt |
| T66 | P3B | A workbench recipe creates one two-cell-high wooden barricade; ordinary placement consumes one item and creates one stable entity with data-driven wood tags, current/max integrity and exact occupied cells |
| T67 | P3B | One clearly labelled strategic-core prototype is the default target; when any valid route reaches its approach, the raider selects that route and does not damage a nearby wooden or castle defense |
| T68 | P3B | When wooden barricades close every valid local route, the basic raider selects one exact obstruction, deals bounded damage, destroys the whole entity without refund, releases its occupied cells once and replans toward the core |
| T69 | P3B | Basic-raider capability cannot select castle-stone voxels or castle-kit entities for damage; a bounded siege-candidate capability can identify the same fortification without fabricating a route through it |
| T70 | P3B | Save during an active core attack and fully restart; Continue restores exact core health, raider health/position, active target and every surviving player-built defense integrity once |
| T71 | P3B | Rendered 1280×720 evidence clearly shows the strategic core, field-side raider, an open entrance and player-built barricade health/target feedback; owner ultrawide playtest decides readability |
| T72 | P3C | Every registered item resolves a stable icon; inventory, hotbar and crafting expose graphical identity and counts |
| T73 | P3C/P3H.3 | Workbench recipe book shows at most 12 fixed cards per page with bounded buttons, wheel page-turning and deterministic search; insufficient-resource cards are red |
| T74 | P3C | Equipped sword performs one clear bounded raider hit; miss/cooldown do not mutate terrain or enemy state; lethal strike wins |
| T75 | P3C | Ballista accepts supported ground/typed tower socket, holds fire through obstruction and consumes one bolt only on a clear shot |
| T76 | P3C | Catapult rejects below-minimum/beyond-maximum/blocked arcs and consumes one shot only for a valid clear ballistic arc |
| T77 | P3C | Carried sword plus placed siege identity, ammunition and cooldown survive atomic save and separate-process Continue |
| T78 | P3C | Rendered 1280×720 Workbench shows 12 populated icon cards, paging and three distinct crafting panels |
| T79 | P3D | Shift+Click on an immediate recipe crafts exactly five batches in one revision; insufficient input changes nothing; timed jobs remain single |
| T80 | P3D/P3H.4 | Active sword, picks, axe and placeables share one lower-right hand column; tools hinge at the screen base and placeables sit above the hotbar; hotbar identity remains authoritative |
| T81 | P3D/P3H.3 | Wood Axe recipe is reachable; one use removes/gathers only the targeted Log while the upper trunk remains |
| T82 | P3D | Placeable blocks expose the same non-mutating validation in their green/red world ghost; the starter marker points to actual guaranteed iron ore |
| T83 | P3D | Rendered 1280×720 evidence visibly shows the held axe/iron marker and the low held block/world placement ghost; owner ultrawide test decides scale/readability |
| T84 | P3E | Whole compatible inventory stacks transfer into distinct persistent Furnace Raw Input and Fuel slots without duplication |
| T85 | P3E | Right-click takes the larger half; right-click deposit and right-drag distribute one per compatible slot with exact counts |
| T86 | P3E | Furnace consumes one input and one counted fuel operation, retains exactly one Output across clean restore and moves it only on explicit collection |
| T87 | P3E/P3H.3 | Furnace modal has three real slots, closes with one Escape while recipe search owns focus, and retains revised station/tool identity |
| T88 | P3E | Manual hand/workbench patterns are recognized without recipe-book selection or search |
| T89 | P3E | Rendered 1280×720 evidence visibly shows the three-slot Furnace and revised world/held identity |
| T90 | P3F | Workbench recipes use an exact stable progression order from hand fundamentals through tools, castle construction, iron equipment and siege recipes |
| T91 | P3F/P3H.4 | All 26 registered items resolve filter-clipped true-alpha references from measured art regions that do not overlap; Ballista Bolt and Stone Shot are isolated from each other; the held view hinges at the lower-right hand with the Sword normalised to `TOOL_HEIGHT`, ammunition to `LOW_HEIGHT` and a swing arc of at least 1.2 rad; all ten non-air voxel cubes keep complete face textures |
| T92 | P3F | Rendered contact sheet shows representative raised/low held items plus textured placed Castle Stone without opaque inventory-card backgrounds |
| T93 | P3G | Shift+Click moves the maximum compatible amount from inventory to Furnace and back without loss or duplication |
| T94 | P3G | Auto-load target independently fills scarce/available input and fuel, lowers transactionally and conserves exact totals |
| T95 | P3G | Per-item progress reaches a measurable midpoint, deposits one retained output and resets when the next loaded batch begins |
| T96 | P3G | Furnace progress advances while its modal is open while world, enemy and player simulation remain paused |
| T97 | P3G | Placed Catapult renders a distinct four-wheel chassis, axle, frame, throwing arm, basket and projectile without changing footprint/combat identity |
| T98 | P3G | Rendered evidence shows the auto-load/progress panel and revised placed Catapult |
| T99 | P3I | A Furnace holding input and fuel starts without a manual press on the next unpaused tick, never while paused, processes every input one at a time into retained Output and returns to idle when the input is spent |
| T99 | P3H | Named catalogue values drive the active Furnace, harvesting and defense services |
| T100 | P3H | One Coal funds exactly three outputs; residual work survives restore and no fourth output is free |
| T101 | P3H | W rotates clockwise, R counterclockwise and Left Shift remains Interact |
| T102 | P3H | Rendered evidence shows the counted fuel ratio/stored work and separate W/R Keybind rows |
| T103 | P3H.1 | Both rendered Workbench pages keep every complete item silhouette inside its own recipe card without neighboring fragments |
| T104 | P3H.2 | Exported three-panel evidence shows the enlarged ready Sword, broad active strike travel and doubled/higher low-held Furnace frame; the active 1536×1024 atlas is RGBA with alpha-zero background |
| T105 | P3H.3 | Placed Gate Frame and Wall Walk Slab mesh parts resolve the Castle Stone texture instead of a flat material |
| T106 | P3H.3 | Exported evidence visibly shows the Castle Stone skin on the placed Gate Frame and Wall Walk Slab |

## Performance evidence, not invented guarantees

Use the 64×32×128 fixture and a scripted or documented route with at least 100 edits and a save/reload. Record median/p95 frame time, longest edit hitch, memory and save duration. Suggested initial usability targets are 60 FPS with ordinary movement and visible edit response under 100 ms on the designated test PC; these are **provisional targets**, not a tested minimum specification. Record failures and determine cause before tuning or enlarging the world.

## Runtime test layers

Automate pure inventory/crafting/occupancy rules in GDScript tests; integration-test actual VoxelTerrain edits and save/load in the pinned engine. Add manual Windows tests for pointer, UI, export and failure recovery. Reuse or add a small test runner only when needed; no testing framework dependency has been selected. Port static placement fixtures into runtime tests, but do not mistake the Python oracle for a test of Godot physics or collision meshes.
