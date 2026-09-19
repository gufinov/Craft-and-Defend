# World, coordinates and occupancy

Canonical proposed fixture: [world.json](../contracts/world.json). Values are prototype assumptions and may change with evidence; persist the chosen generation parameters per save.

## Coordinates

- One voxel equals one logical unit; integer cell coordinates, Y up. World transform is identity in F0.
- Dimensions are **X width 64, Y height 32, Z length 128**. Origin/minimum is `(-32,-16,-64)`; maximum exclusive is `(32,16,64)`.
- Bounds are half-open: `min <= coordinate < min + size`. Valid Y spans -16 through 15. Sea-level reference is Y=0; flowing water is deferred.
- P1 new worlds use deterministic `terrain_p1_1` surface heights from Y=-4 through Y=5. The home clearing remains flat at Y=-1; bottom Y=-16 is protected bedrock. Spawn near `(0.5,2,40.5)`, on the friendly +Z side, only after collision is ready; coordinate is the player's feet convention. Pre-P1 checkpoints keep `flat_fixture_1`.
- The default test volume has 262,144 logical cells. Do not create that many scene nodes. Retain chunk loading/meshing from Voxel Tools.
- Chunk size is initially 16; boundaries and origin align to it. The terrain bounds limit generation but do **not** supply enclosing physical walls. Add player boundary handling plus clear edge feedback, and check bounds in every edit API.
- Use floor conversion for negative world coordinates. A point at X=-0.1 is in cell -1, not 0. Resolve placement using the voxel ray hit's neighboring position/normal, not arbitrary rounding.

## Loading and physics

An unloaded cell is unknown, not empty. Reject or briefly defer edits until data/collision is ready. Spawn must wait for a supported, unobstructed player volume and collision readiness; do not release gravity over unloaded terrain. Keep a loading screen with a recoverable failure path. Runtime tests cross chunk edges, corners, negative coordinates and the world floor/ceiling.

## P1 generation contract

`terrain_p1_1` is a pure blocky generator configured once from `world.json`: two seeded height-noise layers, a blended flat clearing, one deterministic tree candidate per grid cell, and deterministic ore clusters driven by the `terrain.ores` table (see [P4b resource distribution](P4B_RESOURCE_DISTRIBUTION.md)). Its worker callback reads immutable values and writes only the supplied voxel buffer. It never consults nodes, gameplay inventory, the global random stream or the active SQLite edit overlay. Fixed starter trees and ore patches take priority over procedural distribution to preserve the proven empty-inventory route.

Leaves use additive voxel ID 10 and drop sticks; IDs 0–9 are unchanged. The home HUD uses the saved spawn landmark as an orientation aid: `+Z` is treated as south, so the cue reports the direction back to the clearing plus rounded planar distance. It is guidance, not a waypoint/pathfinding system.

## Occupancy invariant

Each cell has at most one logical occupant: a solid voxel or one entity reservation. Air has none. Thin attachments reserve the full destination cell even if their rendered mesh is thin. Foundation does not enable stacking multiple attachments in a cell.

An entity owns an anchor, rotation, stable instance ID and explicit relative cell offsets. Rotate offsets with integer quarter-turn transforms around the declared anchor. An object is legal only when **all** occupied cells are loaded, in bounds, unoccupied and clear of the player's collision volume. Validate its support requirements separately; a support block is not owned by the supported object.

All cells reference the same entity owner. Removing one owned part must route to the entity, release the entire footprint and award at most one object drop. Do not leave orphan reservations. On load, rebuild/validate the occupancy map from authoritative entity records and reject conflicting saves rather than silently deleting items. An object represented by voxels must not also create a second conflicting reservation layer.

Workstations use 1-cell entity reservations in Foundation. A 2×2×2 synthetic footprint in [placement_cases.json](../contracts/placement_cases.json) tests the future contract only; it is not a catapult implementation. Side traps, supports removed under objects, rotations and tunnels get runtime tests before defense objects are added. Proposed Foundation support policy: refuse removing a block supporting a workstation until the station is dismantled. Do not implement general structural collapse.

## Resource/world transaction

Break: verify session, reach (initially 5 units), loaded target, tool tier, unprotected block and output capacity. Commit the terrain-to-air change and exact drop together. Failed or duplicate/stale requests leave both unchanged. If inventory is full, refuse the break in Foundation; dropped-world-item physics is deferred.

Place: verify selected item, full footprint, support, empty target, player overlap and resource count. An ordinary voxel block is supported when any of its six orthogonally adjacent cells contains a loaded solid voxel, so a player may extend a ledge from a side face or attach below a block. A destination with no adjacent solid voxel remains `UNSUPPORTED`; an unknown adjacent load state is never assumed to be air. Entity support remains definition-specific, so Foundation workbenches and furnaces still require the block below them. Consume only on confirmed placement. Cancellation consumes nothing. Data mutation occurs before presentation/mesh refresh; delayed collision updates must not permit embedding the player or repeated placement.

Foundation terrain leveling is repeated block removal/placement with a visible selection outline. No instant free flattening brush. Optional wall templates provide a costed preview, then use the same command path. Automated template building comes later.
