# Architecture — proposed runtime boundaries

These are implementation contracts, not claims that modules already exist. Prefer direct, typed GDScript interfaces and signals over a generic service framework. Keep the Godot/Voxel Tools dependency at the terrain adapter boundary where practical; there is no need for an engine-agnostic game abstraction layer.

| Module | Owns | Inputs → outputs | Must not own |
|---|---|---|---|
| App/session | Menu/loading/playing/paused/saving/error transitions; active slot | UI intents → session lifecycle | Recipes, meshing |
| Settings/input | Named InputMap actions, bindings, audio/video config | validated settings → configuration + action events | Gameplay mutations |
| Player | Movement, camera, collision, aim | actions + world collision → transform/target | Inventory accounting, saves |
| World adapter | VoxelTerrain, viewer, generator, block library, engine APIs | coordinates/query/edit → cell data + dirty regions | Prices, crafting, menu logic |
| Placement/interaction | Bounds, reach, occupancy, six-face voxel support, entity-specific support, atomic edit commands | break/place requests → success or reason code | UI layout |
| Inventory | Slots/stacks/equipment and resource transactions | transaction request → committed inventory revision | Direct terrain writes |
| Crafting/workstations | Recipe checks, timers, jobs, station state | recipe + inventory + station → job/result | Direct file I/O |
| Simulation clock | Day phase, cycle-enabled state and gameplay time | unpaused delta or validated world-setting command → time/lighting | Wall-clock catch-up |
| Persistence | Slot identity, snapshot capture, terrain flush, metadata, recovery | save/load intents → completed snapshot or error | Inventing missing content |
| Content registry | Stable blocks/items/recipes; validated lookup | JSON/resources → immutable definitions | Per-save state |
| Presentation/UI | Menus, HUD, selection, inventory, feedback and game-viewport screenshots | state snapshots → display/files; user intent → commands | Authoritative game rules, desktop capture |

## Command flow

A primary/secondary action is routed through the input context to InteractionService. It checks the target and submits a command containing session ID, expected world/inventory revisions and the desired operation. The service validates all preconditions before changing either inventory or the world. Only a successful commit emits `world_changed(region)` and `inventory_changed(revision)`. UI redraws from results.

Keep the first implementation synchronous on the gameplay/main thread. Do not `await` halfway through a resource/world transaction. If engine editing cannot confirm completion synchronously, reserve resources and lock the target until the operation is confirmed, with an explicit rollback path. Do not grant items merely because a ray hit a block. See [occupancy](WORLD_AND_OCCUPANCY.md).

## Proposed interfaces

| Interface | Contract |
|---|---|
| `WorldAdapter.query_cell(cell)` | Returns OUT_OF_BOUNDS, UNLOADED, or loaded content/occupancy; unloaded is never air |
| `Interaction.try_break(target, expected_revision)` | Returns `{ok, reason, changes}`; one successful removal gives one configured drop |
| `Placement.try_place(definition_id, anchor, rotation)` | Validates entire footprint, support and player collision before committing |
| `Inventory.try_transaction(removals, additions)` | All counts/space verified; all-or-nothing commit or unchanged state |
| `Crafting.try_start(recipe_id, station_id)` | Checks station/range, tools, inputs, output capacity; commits one job or nothing |
| `Session.request_save(destination)` | Freezes mutation, saves a coherent state, reports success/failure before navigation |
| `Settings.apply(candidate)` | Validates action conflicts and safe escape; applies/persists only a valid map |

Error reasons should be stable symbols such as OUT_OF_BOUNDS, UNLOADED, OCCUPIED, PLAYER_OVERLAP, UNSUPPORTED, WRONG_TOOL, OUT_OF_REACH, NO_RESOURCE, INVENTORY_FULL, STALE_REVISION, SAVE_BUSY. Localized/user-friendly text belongs to UI.

Ordinary block placement accepts any loaded solid voxel on the destination's six orthogonal faces as support, enabling horizontal ledges and overhead attachment. It does not provide free-floating placement or general structural collapse. Entity definitions retain their own explicit support offsets; Foundation workbenches and furnaces still require floor support.

## Scene responsibilities

A persistent app root owns menu overlays and the save coordinator. A session root owns world, player, inventory, workstations and clock. Pause disables gameplay processing, while menus and persistence coordination remain responsive. Create a **new** terrain stream per session, never a scene-embedded shared stream reused by altering its path.

The screenshot service captures only the rendered game viewport after a completed draw and writes outside save slots under the global data root. It must not change application state, tree pause, simulation pause or mouse capture. Windows Print Screen focus handling remains a separate system path.

World Settings sends validated commands to `GameSession`, which delegates authoritative time/cycle mutation to the simulation clock and then refreshes presentation. The UI never writes save JSON directly. New worlds begin at 08:00 sunrise; existing saves restore their own phase and optional cycle-enabled state. A visible unshaded sun is presentation only and follows the authoritative solar direction.

Use a small flat deterministic generator before procedural hills/trees. Generator callbacks must not access mutable scene state or global random state from worker threads. Snapshot immutable generation parameters. Do not hot-edit a script generator while engine worker threads are using it.

Future enemies consume world-change events to invalidate relevant paths; they do not rebuild navigation through UI calls. Machines and templates should use the same placement/inventory commands as the player. These boundaries support later work without implementing those systems now.
