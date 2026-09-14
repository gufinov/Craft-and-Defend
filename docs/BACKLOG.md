# Coding-agent backlog

G0, F0 and owner-accepted F1 are complete. Each card is independently reviewable with a checkpoint and evidence. Do not rebuild these documents or create a second bootstrap.

## F0 — Windows integration spike (PASS 2026-09-10)

**Recorded result:** T01–T12 passed on the recorded Windows machine. See [the F0 evidence record](evidence/F0_WINDOWS_INTEGRATION.md). Stop for owner review before F1.

**Objective:** prove the stack can support the intended loop before content investment.

1. Inspect Windows/repo state; establish the implementation worktree from the foundation branch. Validate starter files.
2. Acquire exact candidate editor and release template from the recorded release; verify archives with `tools/verify_toolchain.py`; record executable version, SHA-256, class availability and template path.
3. Study pinned Voxel Tools docs and minimal `voxelgame/project/blocky_game` patterns. Check sample compatibility before copying; record source commit/notices for any copied code.
4. Create `game/project.godot`, boot/menu, input actions and a lightweight first-person controller.
5. Set up finite VoxelTerrain, block library, deterministic layered generator, collision-ready spawning and dirt gathering/placement through an inventory transaction.
6. Implement the minimal save coordinator and coherent checkpoint experiment; resolve the actual stream drain/snapshot barrier from source/API evidence.
7. Implement pause, one runtime rebind and persistence; clean exit/reopen.
8. Configure a Windows export preset using the matching custom release template. Export and repeat the loop outside the editor.

**Outputs:** small runtime, exact setup/export commands, F0 evidence, source notices, status checkpoint. **Tests:** T01–T12. **Stop condition:** unexplained save corruption, missing module export, or collision failure. Preserve the reproduction; avoid crafting to conceal the blocker.

## F1 — shell and interaction hardening (PASS; OWNER ACCEPTED 2026-09-11)

Complete keybind UI/reset/conflicts, settings with display rollback, mouse capture/focus loss, window close, inventory overlay, boundary feedback and edit reason codes. Add entity footprint service with synthetic tests. Run T13–T18. Deliver no new content beyond that needed to validate contracts.

**Recorded result:** Tony confirmed all non-display F1 behavior, corrected ultrawide fullscreen fill and corrected multi-monitor Windowed placement. The final implementation preserves the active monitor, centers the decorated frame inside its usable rectangle and shows the detected native size in Fullscreen. The exported runtime proved 1920×1080, 1280×720 and 1600×900 placement on the 3440×1440 active monitor; complete F1/F0 regressions and static tests pass. A post-promotion [launcher recovery](evidence/F1_LAUNCHER_RECOVERY.md) prevents an ignored stale export from masking the current accepted source. F2 requires its own implementation start; this acceptance does not activate it automatically.

## F2 — inventory, progression and workstations

Load the canonical registry; implement slots/stacks/hotbar as one inventory, reachable crafting, workstation placement, immediate bench recipes and timed furnace jobs. Add original distinguishable placeholder textures. Test empty-inventory progression without debug grants, insufficient tool/capacity and double-click duplication. Run T19–T22.

**Recorded candidate result:** T19–T22 pass in the pinned editor and provenance-matched Windows export, including a clean-process Continue restore. Keybind usability was upgraded in the same bounded milestone using read-only MinionClash presentation evidence: grouped/searchable rows and per-action reset preserve Craft-and-Defend's exact ESDF and conflict-rejection contract. Tony confirmed harvesting, hotbar placement and inventory accumulation on 2026-09-11. The subsequent Print Screen focus repair passes exported automation; owner OS-overlay retest remains pending. F3 is authorized as the next isolated update; promotion still requires explicit authority.

## F3 — persistence hardening

Persist all Foundation state and settings. Exercise independent slots, checkpoint recovery, furnace job continuation and invalid/newer saves. Retain prior complete checkpoint on failure. Record storage/latency measurements and safe close semantics. Run T23–T26 plus T09–T12. Never add an untested migration to recover a sole user save.

**Recorded result:** T23–T26 and the F0–F2 exported regressions pass with the pinned editor closed. A/B slots are independent; five injected write/publication failures retain the previous checkpoint; malformed/newer/missing-content saves are refused unchanged; legacy `default` data is copied to Slot A with the source preserved; an in-progress furnace resumes with 3.0 seconds remaining and delivers exactly one output. The final provenance-matched export measured F3 checkpoints at 23,229–23,652 bytes and 45–66 ms. Tony confirmed independent Slot A/B save-exit-Continue cycles and the real Windows Print Screen/Snipping Tool path on 2026-09-11. F4 is authorized as the next isolated update; merge, push and publication still require separate authority.

## F4 — Foundation acceptance package

Add basic day/night tied to simulation time; keep terrain readable at night. Review UI on 16:9 and ultrawide, confirm no input leaks. Add a globally persisted, rebindable in-game screenshot action (default F2) that writes a rendered gameplay frame in the background without pausing simulation. Produce a portable Windows folder and fresh-machine-style launch without editor dependence. Run T27–T30 and prior acceptance. Optional wall preview follows required checks only.

**Recorded result:** Tony accepted the revised day/night and World Settings behavior and confirmed the side-face placement repair on 2026-09-11. The implementation starts new worlds at visible 08:00 sunrise, persists time/cycle state per slot, accepts blocks attached to any solid neighboring face and rejects truly floating, occupied, out-of-bounds and player-overlap placement. Weather/console controls remain deferred until implemented systems justify them.

## F5 — crafting interface and castle-system planning

Separate inventory from making things. Tab opens inventory only; rebindable B opens a paused 2×2 hand-crafting modal. Right-clicking a placed workbench is the sole entry to its 3×3 advanced crafting modal and takes priority over block placement. Other processing stations own purpose-specific interfaces rather than sharing the Settings presentation. Preserve data-driven recipes, atomic inventory transactions, exact-once furnace jobs and all existing saves. Document the staged castle construction, defense, equipment and possible-magic content families before adding them. Run T31–T34 plus F2–F4 regressions.

**Recorded result:** the split interface, persistent B binding, workbench right-click priority and furnace-specific processing modal were accepted by Tony as the P1 baseline on 2026-09-12. Crafting uses three panels: visible draggable inventory, staged 2×2/3×3 input, and searchable scrolling recipe book. Recipe selection or search+Enter fills the grid only when held materials suffice; the workbench lists hand and advanced recipes. Graphics default to 4× MSAA, VSync and physics interpolation; sunlight shadow transforms use a stable cadence with bounded blended cascades. Torches, armor, weapons and castle pieces remain roadmap content, not placeholder buttons.

## P1 — deterministic terrain and exploration

Replace the new-world flat fixture with a finite, versioned, seeded generator while retaining the proven VoxelTerrain, VoxelMesherBlocky and VoxelStreamSQLite architecture. New worlds contain gentle hills and valleys, a flat protected spawn clearing, distributed trees with harvestable leaves, and deterministic coal/iron clusters. Preserve the fixed starter trees and ore patches so the empty-inventory progression remains testable. Add a lightweight home distance/bearing cue for exploration and return pacing.

Persist generator version and seed in every new checkpoint. A pre-P1 save with no generator metadata must continue with `flat_fixture_1`; `terrain_p1_1` must reproduce the same untouched cells after restart; unknown generator versions must fail rather than silently reinterpret the SQLite edit overlay. Generator callbacks may use only immutable configuration and thread-safe resource reads; they must not access the scene tree or mutable gameplay services from Voxel Tools worker threads.

Run T37–T41 plus the complete F0–F5 regression and matching exported-runtime gates. Castle structural pieces remain a separate P1 content slice because positional recipe behavior, rotation/snapping, tower-cap footprints and collapse policy are still open decisions; do not guess them inside the terrain change.

**P1A result:** editor and matching Windows export pass T37–T40 plus automated T41 rendering on `feature/p1-terrain-exploration`; prior F0–F5 gates remain green. Tony accepted the terrain after physical playtesting on 2026-09-12.

**P1B accepted result:** `feature/p1-castle-kit` adds the first original construction set: existing full castle-stone masonry plus stone stair, wall-walk slab, parapet merlon, a whole 2×2 tower platform with typed `light_siege` mount socket, and an open three-cell gate frame. All non-voxel pieces use explicit footprints/support, green/red non-mutating previews, rebindable X quarter-turn rotation, collision, whole-entity dismantle/refund and coherent persistence. Tony accepted the final two-step stair and ordinary no-jump traversal on 2026-09-13. Recipes remain count-based and provisional; no collapse simulation, moving gate, siege weapon or combat was added. Promotion, merge and push require a separate instruction.

## P2 — navigation spike result

`feature/p2-navigation-spike` compares the pinned experimental voxel helper with a bounded project-owned snapshot/grid planner using one 1×2-cell agent, terrain edits, corridor/wall, trench, placed stairs, bridge removal, tunnel clearance and capability-specific obstruction attacks. T51–T56 pass in the pinned editor runtime. On the 13×5×13 fixture the pinned terrain-only helper is substantially faster, while the local planner is the only candidate that includes placed entity occupancy and returns an explicit allowed attack or `NO_ROUTE`. A real two-cell plank obstruction opens after exactly eight diagnostic hits; ordinary raiders refuse castle stone while the siege candidate can target it.

**P3 candidate boundary:** prototype one attacker with bounded local snapshots, edit-driven incremental refresh and route invalidation. Keep `VoxelAStarGrid3D` as a benchmark/reference. Do not expand this result into global or army-scale pathfinding, production combat, damage animation, drops or raid behavior. Placed-entity change signals, physical enemy locomotion and persistence remain required P3 work. Hybrid sector/local routing remains a hypothesis.

**Owner decision:** Tony accepted the corrected P2 rendered/automation result on 2026-09-13 and authorized P3.

## P3 — bounded defense slice

Prove the smallest readable defense loop before adding campaign scale: one explicit five-second warning, one physical basic raider using the selected P2 local planner, one stationary mounted practice ballista with finite ammunition, one damageable plank barricade, and player repair that consumes an existing material atomically. Propagate exact placed-entity occupied cells into route invalidation and persist all live drill state in the existing checkpoint envelope. Run T57–T65 plus all prior regressions in the matching Windows export with the editor closed.

**Owner-accepted result:** `feature/p3-defense-slice` passes T57–T65 in the pinned runtime and matching editor-closed export. The live HUD shows the authoritative nine-slot held loadout. The raider enters from the field side; the raised practice ballista renders travelling bolts and damages only through a clear direct physics ray, while a blocker consumes neither health nor ammunition. Shift-use on the damaged practice barricade consumes exactly one Planks item and restores six integrity. A clean-process Continue restores an attacking drill with exact wall, ammunition and raider state. Tony confirmed the revision works at ultrawide resolution and marked it PASS on 2026-09-13. The accepted future direction is recorded in [the defense targeting contract](DEFENSE_TARGETING_CONTRACT.md), but player-built structure durability, king/core targeting, waves and catapult ballistics are not implemented by this slice. The practice ballista is not yet a craftable P1 socket-mounted inventory item.

## P3B — core and player-built breach prototype

Add a deliberately labelled strategic-core prototype as the raider's default destination without choosing final throne/power-source fiction. Add one data-driven, craftable and player-placeable two-cell-high wooden barricade using the existing recipe, inventory, placement, occupancy, interaction and save paths. Its stable instance record owns current/max integrity and material capability tags. Shift-use repair consumes Planks atomically; raider damage destroys the whole entity without a refund, releases its exact occupied cells once and replans toward the core.

The raider must first ask for a valid open route. It may select a wooden obstruction only when no open route reaches the core approach and must never damage a nearby defense merely because it exists. Existing castle-stone voxels and castle-kit entities remain impassable to the basic raider; a later siege-capable unit is required to breach them. Persist the core, active target, raider and player-built integrity in the existing envelopes and prove clean-process Continue. Run T66–T71 plus the accepted P3 and prior regression gates in the matching editor-closed Windows export.

**Boundary:** one raider only. No player aggro, multiple units, wave director, damageable voxel-region aggregation, moving/craftable ballista, catapult, rewards, drops, armor combat or campaign progression.

**Owner-accepted result:** `feature/p3-core-defense` passes T66–T71 in the pinned runtime and matching editor-closed Windows export. The Workbench creates a two-cell player-placeable wooden barricade with 30 persisted integrity and atomic Planks repair. The single field-side raider prefers an open core route, breaches one exact wooden barricade only when the local lane is fully blocked, releases both occupied cells without refund and replans through the opening. Castle-kit entities remain outside basic-raider damage while the siege-candidate material rule remains distinguishable. Tony accepted the repaired visible-recipe build on 2026-09-13.

## P3C — player defense and visual catalog

Replace the text-heavy inventory and vertical recipe list with an original icon-first, paged interface while retaining the accepted three-panel crafting and three-section inventory contracts. Add one usable carried sword and craftable/player-placeable ballista and catapult entities. The sword must prioritize a valid raider strike over terrain edits. The ballista must require direct physics line of sight; the catapult must use a clear sampled ballistic arc plus minimum/maximum range. Persist finite siege ammunition with the placed entity. Run T72–T78 plus P3B and prior regression gates.

**Boundary:** one active P3B raider remains the only combat target. Do not claim player health, armor behavior, waves, army-scale targeting, drops, magic, campaign balance or final art. See [the P3C contract](P3C_PLAYER_DEFENSE_AND_VISUAL_CATALOG.md).

**Owner-accepted result:** T72–T78 and accepted regressions pass from the provenance-matched Windows export. Tony subsequently exercised the sword/siege catalog and accepted the integrated result on 2026-09-14.

## P3D — tools and world feedback

Make the immediate craft/build loop readable in first person without expanding campaign scope. Shift+Click crafts exactly five complete immediate-recipe batches atomically. The active hotbar item renders in hand, with tools/weapons raised and blocks held lower. All placeable blocks expose the same green/red non-mutating world preview used by real placement. Add one craftable Wood Axe that fells a bounded connected vertical trunk atomically, and make the existing guaranteed starter iron vein discoverable without changing generator identity or accepted saves. Run T79–T83 plus P3C/P3B/F5 regressions in the matching editor-closed export.

**Boundary:** no durability, variable mining speed, enchantment, animation rig, general ore detector, branch-recursive tree physics, resource respawn, player health, waves or campaign systems. Timed furnace jobs do not support five-batch queueing. See [the P3D contract](P3D_TOOLS_AND_WORLD_FEEDBACK.md).

**Owner-accepted result:** T79–T83 and the accepted regressions pass from the provenance-matched Windows export. Tony exercised held tools/blocks, Wood Axe, iron discovery and placement, then accepted the integrated result on 2026-09-14.

## P3E — furnace containers and visual identity

Replace the Furnace's invisible inventory reservation with three persistent station-owned stacks: Raw Input, Fuel and Output. A completed result remains visible in Output until explicitly collected. Add conventional whole-stack, half-stack, one-item and right-drag distribution gestures without allowing cursor-held items to disappear on panel close or save. Preserve manual recipe-pattern recognition independently of recipe-book search. Align the placed Workbench/Furnace and held Workbench/Furnace/Stone Pick/Wood Axe with the established inventory visual language. Run T84–T89 plus F2/F3/F5/P3D regressions in the matching editor-closed export.

**Boundary:** no job queue, multiple smelting recipes, automated item transport, general chest UI, final 3D asset production, animation rig or durability. See [the P3E contract](P3E_FURNACE_CONTAINERS_AND_VISUAL_IDENTITY.md).

**Owner-accepted result:** T84–T89 and F2/F3/F5/P3D/P3C affected regressions pass from the provenance-matched Windows export. Completed output is station-owned and explicitly collected; exact cursor/container counts survive restore. Tony confirmed the improved behavior works and marked it PASS on 2026-09-14.

## P3F — recipe progression order and held visual catalog

Replace temporary high-priority recipe promotion with an explicit basic-to-advanced progression order. Keep hand materials and starter tools first, castle construction in the middle, and iron/siege recipes later. Give every registered carried item a transparent first-person reference matching the inventory catalog, with tools/weapons raised and placeables/materials low. Correct the Voxel Tools cube UV contract so each placed block maps its complete authored face texture. Run T90–T92 plus P3C/P3D/P3E affected regressions in the matching editor-closed export.

**Boundary:** ordering prepares for future recipe discovery but does not invent unlock triggers or persistence. No final 3D models, hand rig, animation set, dedicated ammunition art, PBR material overhaul, new block IDs or save migration.

**Candidate result:** T90–T92, static validation, 37 Python tests and P3C/P3D/P3E affected gates pass from the provenance-matched Windows export. The inspected contact sheet confirms transparent held identities for representative tools, materials, blocks and siege pieces plus textured placed Castle Stone. Owner ultrawide playtest remains required.

**Owner-accepted result:** Tony confirmed the revised recipe order, held identities and placed block visuals work and marked the update PASS on 2026-09-14.

## P3G — Furnace usability and placed siege identity

Add maximum-compatible Shift+Click transfer between player inventory and Furnace slots while retaining drag, split, single-item and distribution gestures. Add a reversible 0–64 auto-load target that independently fills each selected-recipe ingredient from available stock. Run one persisted timed item at a time, expose progress, retain each output and automatically continue only through already-loaded complete batches. Keep world simulation paused while allowing the open Furnace appliance to advance. Replace the placed Catapult's generic box stack with a recognizable original low-poly prototype. Run T93–T98 plus P3E/P3F affected regressions.

**Boundary:** no transport/chest automation, parallel processing, offline catch-up, recipe unlocking, final 3D production art, siege animation, waves or campaign expansion. See [the P3G contract](P3G_FURNACE_USABILITY_AND_SIEGE_VISUAL.md).

**Candidate result:** provenance-matched exported T93–T98, inspected Furnace/Catapult renders, 38 Python tests and exported P3E/P3F regressions pass. Owner ultrawide playtest remains required.

## Card completion discipline

Update relevant contracts/tests, source ledger and `docs/STATUS.md`; record exact commands/results/limitations; commit a coherent increment. Future systems remain backlog items until their gate is active. Do not automatically merge or publish builds.
