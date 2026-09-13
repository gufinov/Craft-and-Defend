# Architecture — proposed runtime boundaries

These are implementation contracts, not claims that modules already exist. Prefer direct, typed GDScript interfaces and signals over a generic service framework. Keep the Godot/Voxel Tools dependency at the terrain adapter boundary where practical; there is no need for an engine-agnostic game abstraction layer.

| Module | Owns | Inputs → outputs | Must not own |
|---|---|---|---|
| App/session | Menu/loading/playing/paused/saving/error transitions; active slot | UI intents → session lifecycle | Recipes, meshing |
| Settings/input | Named InputMap actions, bindings, audio/video/graphics config | validated settings → configuration + action events | Gameplay mutations |
| Player | Movement, camera, collision, aim | actions + world collision → transform/target | Inventory accounting, saves |
| Defense targeting | Bounded threat objective, perception, route/obstruction selection, direct/indirect weapon validation | world/occupancy + actor state → explicit target/action | UI, inventory mutation outside committed commands |
| World adapter | VoxelTerrain, viewer, generator, block library, engine APIs | coordinates/query/edit → cell data + dirty regions | Prices, crafting, menu logic |
| Placement/interaction | Bounds, reach, occupancy, six-face voxel support, entity-specific support, atomic edit commands | break/place requests → success or reason code | UI layout |
| Inventory | Slots/stacks/equipment and resource transactions | transaction request → committed inventory revision | Direct terrain writes |
| Crafting/workstations | Recipe checks, timers, jobs, station and placed-structure state | recipe + inventory + placed entity → job/result | Direct file I/O |
| Simulation clock | Day phase, cycle-enabled state and gameplay time | unpaused delta or validated world-setting command → time/lighting | Wall-clock catch-up |
| Persistence | Slot identity, snapshot capture, terrain flush, metadata, recovery | save/load intents → completed snapshot or error | Inventing missing content |
| Content registry | Stable blocks/items/recipes; validated lookup | JSON/resources → immutable definitions | Per-save state |
| Navigation snapshot | Bounded immutable terrain/entity occupancy plus source revision | world queries/change events → local pathfinding input | Scene mutation, UI, global terrain ownership |
| Local navigation planner | One-agent standability, route validation and capability-specific obstruction intent | snapshot + start/goal/capability → route, attack intent or no route | Block damage commits, drops, animation, save I/O |
| Presentation/UI | Menus, HUD, inventory-only overlay, hand/station crafting modals, feedback and game-viewport screenshots | state snapshots → display/files; user intent → commands | Authoritative game rules, desktop capture |

## Command flow

A primary/secondary action is routed through the input context to InteractionService. Secondary first resolves a targeted station; if found it emits a station-open result without placing, otherwise it follows the placement path. The service checks the target and submits a command containing session ID, expected world/inventory revisions and the desired operation. It validates all preconditions before changing either inventory or the world. Only a successful commit emits `world_changed(region)` and `inventory_changed(revision)`. UI redraws from results.

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

Compatibility rendering remains the approved engine path. The viewport applies persisted MSAA while VSync is applied through DisplayServer; physics interpolation smooths fixed-step player/camera transforms and is reset after activation or restore. The visible sun can follow the player every rendered frame, but directional-light rotation and shadow-map inputs update only when the displayed game minute changes. Four blended shadow splits with a bounded near-field distance keep precision focused on the editable play area. These presentation controls do not change simulation time or saved terrain.

Crafting-grid contents are temporary UI staging, not inventory reservations. Drag/drop and recipe autofill may arrange stable item IDs only up to the counts currently held. Craft presses the existing atomic crafting/workstation service, which revalidates station, materials and output capacity before any mutation. Closing or clearing the modal therefore has nothing to refund and cannot duplicate items.

The Tab inventory presents one authoritative 27-slot inventory as two explicit surfaces: 18 unequipped carried slots above a single nine-slot hotbar row. Drag/drop and the two-click keyboard fallback both call the same exact-slot swap transaction, including moves between the two surfaces. Stable item-category metadata drives view-only Carried filters and a deterministic Carried-only sort; filtering never changes slots, and sorting commits at most one inventory revision while leaving slots 1–9 untouched. A separate full-height armor loadout presents helmet, breastplate, gauntlets, leggings, boots and shield positions. Those armor controls are disabled presentation placeholders until an equipment domain contract and persisted gear state exist; UI must not fabricate equipped items. Spatial or variable-footprint carried items remain an unapproved alternative because they would change inventory transactions, capacity, drag/drop and save data together.

The same authoritative hotbar snapshot is rendered as nine persistent held slots during live play. Defense target priority, player-built obstruction behavior, direct-fire line of sight and future indirect-fire boundaries are defined in [Defense, targeting and castle-obstacle contract](DEFENSE_TARGETING_CONTRACT.md).

The P1 castle kit reuses the entity owner map for stations and non-interactive structures. The historical `WorkstationService` name and `workstations` save envelope remain for compatibility, but each record's content definition decides whether it is a station or a structure. Only definitions with an explicit `station_type` open crafting or processing UI. Structure definitions own their occupied and support offsets, data-driven visual/collision box parts and optional typed mount sockets; the scene renderer remains an adapter rather than an authority for occupancy.

Placement preview calls the same validation without reserving cells or consuming inventory. Successful placement repeats validation, reserves the complete rotated footprint and then performs the inventory transaction; a failed transaction releases the reservation. One stored quarter-turn value drives footprint, support, visual and collision orientation. The candidate default is rebindable physical X and leaves the established ESDF controls unchanged.

The player controller owns a bounded step-up probe for stair traversal. A horizontal collision while grounded may raise the capsule by at most `0.55` block, but only when the raised horizontal path is clear and a floor exists immediately below the advanced position. Extended floor snap applies only on that step frame, preserving ordinary jump/landing behavior and preventing the helper from treating a full block as a stair. The stone-stair entity remains two matching box visual/collision parts, each one-half block deep with successive half-block heights.

P1 keeps the flat generator solely for pre-P1 save compatibility and selects a versioned seeded hills/trees/ore generator for new worlds. Generator callbacks must not access mutable scene state or global random state from worker threads. Snapshot immutable generation parameters and refuse unknown generator IDs. Do not hot-edit a script generator while engine worker threads are using it.

P2 establishes a bounded navigation-spike boundary rather than a global navigation service. `NavigationSnapshot` captures loaded voxel and placed-entity occupancy for a small AABB and records the source world revision. Exact voxel `cell_changed` events support incremental refresh; P3 must add the equivalent placed-entity change signal before relying on live invalidation. `LocalGridPathfinder` treats the agent as one cell wide and two cells high, validates headroom/floor support, permits only bounded cardinal step/drop transitions, and returns either a valid route, an explicit `ATTACK_OBSTRUCTION` intent allowed by capability tags, or `NO_ROUTE`. It never commits damage or fabricates a path through an intact block.

The pinned experimental `VoxelAStarGrid3D` adapter remains a terrain-only benchmark/reference. It is much faster in the tiny P2 fixture but does not see non-voxel castle entities and has no capability or attack semantics. P3 may prototype one physical attacker against the project-owned bounded snapshot/grid contract, with initial full capture outside critical gameplay moments and edit-driven incremental refresh afterward. Army-scale search, global unrestricted edits, sector routing, asynchronous scheduling and path sharing remain unproven; hybrid sector/local routing is only a hypothesis.

Future enemies consume world/entity-change events to invalidate relevant paths; they do not rebuild navigation through UI calls. Machines and templates should use the same placement/inventory commands as the player. These boundaries support later work without implementing those systems now.
