# P4E — the big world, the enemy base and far attacks

## Outcome

Owner direction (2026-09-19): "randomize the world generation and ensure ore is more abundant, even on the ground; expand the map 5x; add mountains and water; put an enemy core and spawn location at a random location far from my base; enemies spawn from there unless we use Start Drill (NEAR)"; plus the pathing complaints (huddles, stuck on a tree, identical every run).

## World (`contracts/world.json` → `game/data/world.json`, `WorldAdapter`, `P1TerrainGenerator`)

- **Bounds** 320 × 48 × 384 (min −160, −16, −192) — five times the previous area. `WorldAdapter.WORLD_MIN / WORLD_SIZE` are read from `world.json` at `initialize()` and handed to the generator (`bounds_min/bounds_size`), which uses them for trees, bedrock and the enemy base margin.
- **Seed**: every new game draws a random seed (`SaveCoordinator.random_world_seed`); diagnostics keep 41026 (the app clears the flag under any `--*-automation=` argument). Continuing a save keeps its seed.
- **Mountains**: a slow mask (`mountain_frequency` 0.0075) above `mountain_threshold` 0.30 lifts the ground with `ramp × (1.2 + ramp) × mountain_height` up to `max_surface_y` 24; from `rock_surface_y` 12 the surface is bare stone. Ordinary rolling ground never dips below −1 on its own.
- **Lakes**: a lake mask (`lake_frequency` 0.014, `lake_threshold` 0.42, ≈7 % of the map) digs the floor 1–5 blocks under the water line and fills it with **water** (block 12: non-solid, protected, translucent, no collision — the player walks on the lake bed for now). Trees never grow in water or on rock. Neither clearing floods.
- **Ore**: bands iron 32 / coal 60 / gold 9 per thousand to depth 48, plus **surface ore** (`surface_ores`: coal 9‰, iron 5‰ columns, 2×2 clusters) showing on the ground outside the home clearing.
- **Enemy base**: `_pick_enemy_base()` puts a round flat clearing (radius 10, blend 10) 150–200 cells from home at a seed-chosen bearing, inside the bounds by 24; `enemy_base_cell()` is its centre on the surface. The compass line reads `HOME 42 m S · ENEMY BASE 161 m NW`.
- Generation cost: per-column facts (water, exposed ore, nearby tree roots) are resolved once per column, not per voxel — the 5× world loads in ~2 s headless and a checkpoint saves in under a second. Readiness waits in diagnostics are time-based (45 s) and the checkpoint timeout is 60 s.

## Far attacks (`SurfaceRouter`, `CoreDefenseService.far_mode`, `BasicRaider.ground_loaded`)

- `start_prototype({"from_enemy_base": true, ...})` (pause menu **Start Attack from the Enemy Base (far)**: 8 raiders, 2 brutes, 2 trolls). The wave spawns spread around the enemy base and follows a **surface route**: A* over generator column heights (4-neighbours, one step up/down, no water, no trunks, budgeted; ~100 ms for 190 cells) to a point `MARCH_HANDOVER` 18 cells from the arena.
- Where the terrain is not loaded the body **ghost-walks** the route kinematically (`BasicRaider.ground_loaded` callback; y from the route cell); physics resumes as chunks stream in near the player.
- Arriving inside `LOCAL_RADIUS` 20 the local voxel planner takes over (capture region 41 × 24 × 41 around the arena). A march that ends early (budget) re-routes; stuck marchers re-route from where they stand; marching bodies ignore local re-plans; save/restore re-marches bodies still outside the local area.
- **Start Drill (NEAR): single raider** and the wave/siege drills keep spawning on the old near lines.

## Pathing (owner playtest fixes)

- Raiders are on collision layer 4 with a world-only mask: they never shove each other (the player's mask includes 4, so you still bump them). Rays that must see raiders use mask `1 | 4`.
- `BasicRaider.stuck` fires after 1.6 s without progress toward the next route cell; the drill re-captures and re-plans from the body's real position (or re-marches).
- Wave offsets come from a randomized RNG per drill (lateral ±4, up to three rows back), so no two waves line up the same way.

## Core of Power (`P4G` entity, `CoreDefenseService.core_station_id`)

- With a placed `core_of_power` station the drill's arena centres on it (`arena_center + (0, 0, 5)` is the core's centre column), raiders route to the nearest free cell beside the 3×3 footprint, hits go through `WorkstationService.try_damage` (visual and save follow) and destroying the core (by any path) fails the drill. Without one the prototype core cell remains.
- New games start with one Core of Power in the pack (outside automation). The red `enemy_core` is placed on a levelled stone slab at the enemy base the first time its cells are loaded.

## Aggro, player health, view distance (owner round-2 notes)

- **Sword**: the swing first ray-casts along the aim on layers 1|4 (raiders live on 4); a raider it touches is hit. Otherwise the nearest raider inside a 3.25 reach cone (37°) is hit unless something solid sits more than 0.9 from it on the line. Raiders stay targetable after a lost drill so you can finish them.
- **Aggro** (`CoreDefenseService.notify_raider_provoked`, `ATTENTION_SECONDS` 8, `ATTENTION_RANGE` 14): a raider hurt by the player chases the player and hits (melee 6/10, trolls shoot); one hurt by a machine chases that machine and smashes it; when attention lapses or the target leaves range it re-plans to the core. Siege impacts pass the machine's instance id as the provoker.
- **Player health** (`PlayerController.health`, 100): HUD `HP 100/100`; regenerates 2/s after 6 s without damage; at 0 you respawn beside your core (or home) with full health.
- **Navigation**: water is impassable for raiders (they path around lakes).
- **View distance**: Settings → Graphics → Terrain view distance (64/128/192/256/320 blocks, default 128; `WorldAdapter.set_view_distance`, saved in settings.cfg).

## Round-3 owner notes: fence, minimap, kettle, mountains

- **No invisible fence**: the player clamp uses the world.json edge (`PlayerController._position_inside_world`), so every generated cell is reachable.
- **Minimap** (`MinimapOverlay`, top-right; **M** toggles the full world map): generator heights coloured by elevation (contours every 4 blocks, lakes blue, rock grey to snow), home marker, placed cores (blue/red), enemy base (red), player heading arrow. Heights are cached per column and the image is rebuilt in row slices, so it never hitches; player edits are not drawn (topology of the generated world).
- **Kettle placement**: the placement aim (`InteractionService.placement_anchor_from_view`) now stops at entity-owned cells too, so aiming at a rail lands the kettle on the cell above it instead of "inside" the rail (which the voxel raycast saw through).
- **Patrol** stance (rail weapons only; panel button appears for them): while idle the kettle rides its connected rail chain end to end (`_chain_end_farthest`) and still fires at will; with a target it rides to the nearest rail cell as before.
- **Mountains**: no mountain lift within 30–55 cells of home and along an 8–20 cell corridor between home and the enemy base, so raiders (one step up/down) always have a way in and the player is never ringed by peaks.

## Acceptance

T151 (far attack from the enemy base), T152 (placed core defended) in `--p4-siege-units-automation=gate`; world tests T137/T138 follow the new bands; F0 T03/T06 follow the bounds; the P1 visual shows a lake beside the clearing.

## Boundary and next

No swimming (water is walk-through). Trolls still shoot without line of sight. The enemy base has no camp structures beyond the red core, and raiders do not yet defend it. The long march ignores player structures until the local area; a wall built 30 cells out is walked around only once inside it. Next: swim/float, camp props and enemy patrols, attacking the enemy core as a win condition, per-player core colours.
