# Development Expo — Agent Implementation Handoff

Date: 2026-09-22  
Status: **OWNER-COMMISSIONED NEXT MILESTONE — planning/specification only; implementation must occur in a worktree and must not be merged without owner review.**

## Objective

Build a dedicated **Development Start** mode whose world is an expandable, organized, playable **Development Expo** for Craft-and-Defend.

The Expo exists so the owner can test current and future systems without replaying the survival progression, mining materials for hours, rebuilding test rigs, or depending on an old save. It is not a cheat menu layered onto the normal game. It is a separate development-world experience with its own save namespace and a deterministic canonical fixture.

The Expo must demonstrate what assets **do**, what they **depend on**, and what they **enable**. Do not create a warehouse full of disconnected props. Use object booths only where appropriate; use working demonstrations, terrain, production chains and scenarios where context matters.

The normal game remains the survival game. Development Start is a test/exhibition environment.

---

# 1. Read before editing

Read only what is needed to execute this milestone:

1. `AGENTS.md`
2. `docs/STATUS.md`
3. this document
4. `docs/INDUSTRY.md`
5. `docs/P4C_SIEGE_UNITS_AND_WAVES.md`
6. `docs/P4F_ENEMY_UNITS.md`
7. `docs/P4G_CORE_AND_LIGHTS.md`
8. `docs/COASTERCRAFT_TRACKS.md`
9. `docs/COASTER_CAR_AND_HERO.md`
10. `docs/WORLD_AND_OCCUPANCY.md`
11. relevant existing implementation files before changing them

Do not restart engine research. Do not redesign the current runtime architecture. Reuse existing services.

---

# 2. Current baseline to reuse

The repository already has the systems the Expo must exercise:

- finite editable voxel terrain;
- first-person movement and ESDF controls;
- inventory/hotbar;
- crafting, Workbench and Furnace;
- hills, trees, coal/iron/gold resource distribution;
- Castle Stone and castle kit pieces;
- drag building and blueprints;
- Chest, Ore Bin, Warehouse, storage networking;
- Miner, Foundry and automated material movement;
- Rail, Mine Cart and hauling;
- Ballista, Catapult, Turret Catapult, Turret Catapult Mk2, Cannon and Kettle;
- ammunition and adjacent-storage auto-reload;
- Core of Power and enemy core;
- orc/raider, brute and troll combat units;
- wave/far-attack drills and local pathing/breaching;
- torches, wall lanterns, post lanterns, campfire and blue/red light blocks;
- CoasterCraft rails, slopes, loops, switches, crossings, curves, climbs, carts and rideable coaster car;
- day/night, saves, settings, menus and Windows export/testing infrastructure.

The Expo must compose these existing systems. It must not fork them into parallel debug-only simulations.

---

# 3. Fix the lost-Core Continue failure first

There is a user-visible issue around continuing a save after the player's Core of Power has been destroyed.

Required behavior:

## Normal game

- A destroyed Core means **Game Over**.
- A lost-core save must never crash or hang on Continue.
- The save itself must remain readable.
- If the selected normal-game slot is conclusively in a lost/game-over state, the main menu must not present Continue as an ordinary resumable game.
- Show a clear status such as **Game Over — Start New** and provide the existing safe New Game path.
- Do **not** silently create a replacement Core in a normal save.
- Preserve compatibility with older saves where the defense drill references a missing/destroyed core. Normalize that state as ended/lost rather than treating the missing station as a fatal load error.

## Development mode

- Development Start is independent of normal-game loss state.
- A destroyed development Core may be restored by the Expo/Battlefield reset path.
- Development mode must never require survival grinding merely to recover the testing environment.

Add a regression test for the normal Continue path so a missing/destroyed Core cannot reintroduce a load crash.

---

# 4. Main-menu entry and save isolation

Add a clear main-menu action:

**Development Start**

Behavior:

- Opens/starts the Development Expo.
- Uses a dedicated development save namespace separate from Slot A, Slot B and CoasterCraft.
- Never overwrites or consumes a normal save.
- First use creates the canonical Expo fixture.
- Later Development Start resumes the saved Expo unless the owner chooses/reset commands request regeneration.
- The Expo is editable: the owner may move items, build, dig, change containers and otherwise experiment normally.
- Provide an explicit **Reset Expo** control that restores the current canonical Expo fixture.
- The normal pause/save lifecycle still applies.
- Ambient normal-game enemy pressure must be disabled in Development mode. Combat occurs only through explicit Expo demonstrations such as the Battlefield control.

A command-line convenience such as `START.cmd dev` is optional; the main-menu entry is required.

---

# 5. Expo design rule

The implementation must follow this rule:

> **The Expo is a playable exhibition of the game's systems. Every current asset should be shown in the context of what it does, what it depends on, or what it enables.**

Use these exhibit scales:

1. **Catalog booth** — what is it?
2. **Functional booth** — what does it do?
3. **System demonstration** — how does it interact with other systems?
4. **Environmental exhibit** — how does terrain/context affect it?
5. **Live scenario** — how does the complete loop behave?

Examples:

- Iron Pick: catalog/equipment booth.
- Furnace: functional booth.
- Miner → Ore Bin → Cart → Warehouse → Foundry: system demonstration.
- Mountain mine: environmental exhibit.
- Battlefield: live scenario.
- Grand Coaster: showcase/live scenario.

Do not force all content into identical square booths.

---

# 6. Responsive / expandable Expo architecture

The Expo must be designed for future growth.

Do not hard-code a final list of coordinates such as “Foundry is permanently at X=42, Z=17” throughout game code.

Create one authoritative, data-driven Expo definition/manifest using stable item/entity IDs. A reasonable location is `contracts/development_expo.json` with a runtime mirror if this matches existing content conventions.

The Expo definition should describe:

- districts;
- exhibit ID;
- exhibit kind;
- requested footprint/volume;
- minimum clearance;
- orientation;
- referenced item/entity IDs;
- terrain requirements;
- connection requirements;
- sign/label;
- optional demonstration/reset group;
- expansion priority.

The layout system must support variable-size exhibits and keep free growth space.

## Growth requirements

- Districts must have expansion corridors/edges rather than fixed final capacity.
- A new technology can request another booth/parcel without redesigning the whole map.
- Terrain-dependent exhibits reserve **volumes**, not just flat rectangles.
- Large demonstrations such as the mountain, battlefield and coaster reserve substantial buffers.
- Paths must remain navigable after new booths are added.
- The canonical world bounds should be computed/configured from the Expo layout plus expansion margin and rounded to safe chunk-aligned dimensions rather than assuming the normal-game dimensions are the final Expo size.
- Keep at least one visible reserved/future expansion area; do not populate it with fake content.

If a newly registered visible gameplay item has no Expo/supply classification, automated validation should report it. New content must not silently disappear from Development Start.

---

# 7. Suggested physical campus layout

The layout may adapt to actual dimensions, but preserve this relationship:

## Central Plaza / Spawn

Spawn in a clear, level central plaza.

Include:

- Development Core of Power;
- large **DEVELOPMENT EXPO** orientation sign/map;
- clear paths to major districts;
- Supply Depot immediately nearby;
- Reset Expo access.

The plaza is the navigation anchor and must remain uncluttered.

## Southwest / near plaza — Day One + Equipment

A small “Day One” survival progression exhibit:

Tree → Log → Planks → Sticks → Workbench → Wooden Pick → Stone → Stone Pick → Furnace → Iron → Iron Pick.

Next to it, an Equipment area showing current player-carried items:

- Wood Pick
- Stone Pick
- Iron Pick
- Wood Axe
- Iron Sword
- current future armor area reserved but empty until armor actually exists

The purpose is to demonstrate the early survival chain without requiring the owner to perform it before every other test.

## West / Northwest — Resources and Mining Mountain

Use real voxel terrain.

Include:

- small forest patch;
- stone/quarry exposure;
- coal seam;
- surface ore examples;
- a substantial mountain.

The mountain is a major environmental exhibit, not scenery.

### Mining Mountain

Build a broad mountain with a dense, deliberately authored deep ore core containing representative coal, iron and gold deposits.

Create a very large, well-lit tunnel/mine through the mountain:

- large enough for the player to run comfortably;
- high/wide enough for rail and future equipment;
- visibly lit;
- rail system inside;
- clear manual-mining area;
- separate automated-mining area;
- enough ore that the Miner can run for a useful period without immediately exhausting the demonstration;
- safe player circulation around the machines.

Think “large aquifer/cavern-scale passage,” not a one-block diagnostic tunnel.

## North — Industry / Logistics

The Mining Mountain should feed naturally into Industry.

Build a working chain:

**Ore deposit → Miner → Ore Bin → Mine Cart/Rail → Warehouse → Foundry → Ingots**

Also demonstrate storage-network behavior:

- Warehouse touching Chest;
- Warehouse daisy-chain;
- Foundry touching storage;
- Furnace touching storage;
- empty containers at initial canonical state where practical so the owner can watch them fill;
- signs explaining each stage.

The chain must actually operate under current service logic.

Where possible, let the player physically follow the ore from source to destination.

## Northeast — Construction Yard

Show individual construction assets and then show them assembled.

Current exhibit content:

- Castle Stone;
- Stone Stair;
- Wall-walk Slab;
- Parapet Merlon;
- Tower Platform;
- Gate Frame;
- Wood Barricade;
- representative drag-built wall;
- representative blueprint/stamped structure.

Build at least one small castle/tower demonstration using these pieces so the owner can see “piece → assembly → defensive structure.”

Reserve expansion for future gates, roofs, bridges, tower caps and other castle technology.

## East — Defense Range

Give each siege/defense machine a functional booth with room to operate:

- Ballista;
- Catapult;
- Turret Catapult;
- Turret Catapult Mk2;
- Cannon;
- Kettle on rail.

Each booth should include the things needed to demonstrate it, not merely the object:

- correct support/mount;
- suitable ammunition;
- adjacent chest/storage when relevant;
- safe target/range marker;
- enough clear line/arc space;
- sign identifying the weapon and ammunition type.

Use existing firing/reload services.

## Far East / buffered area — Battlefield

Create a large dedicated battlefield far enough from ordinary Expo traffic that active combat does not interfere with other exhibits.

Player side:

- blue Core of Power;
- small defensive fortification;
- representative wall/tower;
- Ballista;
- Catapult;
- Cannon;
- turret weapon(s);
- ammunition/storage;
- room reserved for future archers/soldiers.

Enemy side:

- red enemy Core;
- controlled spawn/staging area;
- current enemy kinds: orc/raider, brute, troll;
- room for future enemy types.

Between them: clear traversable battlefield with enough distance to exercise current far/local routing.

### Battlefield controls

Place an in-world Development Battlefield control station/pedestal with:

- **START ATTACK**
- **RESET BATTLEFIELD**

START ATTACK launches a representative mixed current enemy assault using existing attack/wave services.

RESET BATTLEFIELD must restore the battlefield fixture without resetting the rest of the Expo:

- stop/remove active attackers;
- restore blue Core;
- restore enemy Core;
- restore default player-side defensive structures;
- restore destroyed/damaged Expo siege machines in that reset group;
- restore ammunition/storage fixture;
- reset relevant enemy state;
- restore the battlefield to its known initial state.

Design this reset as a reusable reset-group mechanism so future scenarios can have their own reset boundary.

## South / outer area — Lighting + Utilities

Demonstrate:

- Torch;
- Wall Lantern;
- Post Lantern;
- Campfire;
- Blue Light Block;
- Red Light Block.

Use a small path/tunnel/pavilion where the differences are visible.

Development mode may default to a stable daylight time for inspection; the existing World Settings can still be used to inspect the lighting at night. Do not invent a new weather or time system.

## Southeast / large outer reserve — CoasterCraft

This must be a showcase, not a tiny diagnostic track.

Two parts:

### Component Gallery

Show current track technology individually:

- Rail;
- Rail Slope;
- Rail Loop;
- Rail Switch;
- Rail Cross;
- Rail Curve;
- Rail Climb;
- Mine Cart;
- Coaster Car;
- CoasterCraft Shop.

### Grand Demonstration Coaster

Build one substantial, rideable coaster using all applicable current track capabilities in a visually coherent circuit.

It should include, at minimum:

- straights;
- major rise/climb;
- descent;
- curves;
- a true loop;
- switch;
- crossing;
- supports/trestles;
- meaningful elevation change;
- rideable Coaster Car;
- station/start area.

The intention is “showpiece amusement-park ride,” not “one of each piece placed next to each other.”

Reuse the existing CoasterCart/CoasterRide/track systems. Do not create a separate debug vehicle.

---

# 8. Supply Depot

Create a dedicated Supply Depot near spawn.

Purpose: the owner can obtain every current testable item immediately.

## Generation rule

- Enumerate all current non-hidden player-visible items from the canonical content registry.
- Group them by Expo category.
- Put **8 units of each item type** into supply chests.
- Each supply chest carries at most **8 distinct item types**, intentionally leaving any extra chest slot unused if the current Chest has nine slots.
- Continue creating chests until every current visible item is represented.
- Keep stable deterministic ordering so contents do not shuffle between runs.
- Hidden/internal-only items such as `enemy_core` are excluded from the public supply row unless explicitly whitelisted as a development asset.
- The battlefield may place hidden/internal entities directly through its fixture.

Suggested Expo supply categories:

1. Natural Resources
2. Ores & Fuel
3. Processed Materials
4. Ammunition
5. Tools & Personal Weapons
6. Construction
7. Workstations & Industry
8. Siege & Defense
9. Rail & Coaster
10. Lighting & Utility
11. Special/Core
12. Future Food
13. Future Armor
14. Unassigned

Do not create fake Food/Armor items. Empty future categories may exist only as reserved signage/space.

A visible item that lands in Unassigned should be surfaced by validation so the next feature author classifies it.

---

# 9. Sign system

Implement a real reusable `sign` item and Workbench recipe.

Prototype recipe: **2 Planks + 1 Stick → 1 Sign**. This is balance-tunable; do not copy any external game asset.

The same sign item supports:

- ground placement with a post;
- wall placement with no post.

Use existing support, placement and occupancy rules. Do not allow sign geometry to overlap an occupied logical cell merely because the visible panel is thin.

## Sign interaction

Right-click opens a dedicated sign editor using the game's existing modal/panel visual language.

The editor must support these display modes:

1. **Single Text** — one text field.
2. **Split Text** — two side-by-side text fields.
3. **Item Grid** — up to eight item entries in a 4-row × 2-column layout.
4. **Header + Item Grid** — short text heading plus the same item grid.

For item selection:

- do not use a conventional tiny dropdown;
- reuse the icon-first catalog presentation language from inventory/recipes;
- first choose/category-filter visually;
- then choose an item by icon + readable name;
- categories must be derived from the Expo/category mapping with stable fallbacks;
- item entries display icon and name;
- the editor permits replacing/removing a selected slot;
- save sign contents as stable IDs/text, not display labels or scene paths.

The Supply Depot signs must be automatically configured to display the exact eight item types contained in the chest behind/below them.

A ground Supply-Depot sign should visually stand above its chest and be large enough to read the 4×2 item presentation. A wall-mounted sign has no post.

Signs are ordinary reusable gameplay assets after this feature; they are not Development-mode-only props.

---

# 10. Current asset demonstrations to cover

At minimum, the first Expo build must account for the current canonical catalog.

## Resources

- Dirt
- Stone
- Log
- Planks
- Castle Stone
- Stick
- Coal
- Iron Ore
- Iron Ingot
- Gold Ore
- Gold Ingot

## Tools / player weapon

- Wood Pick
- Stone Pick
- Iron Pick
- Wood Axe
- Iron Sword

## Crafting / stations / storage

- Workbench
- Furnace
- Chest
- Miner
- Ore Bin
- Warehouse
- Foundry
- CoasterCraft Shop

## Castle / construction

- Stone Stair
- Wall-walk Slab
- Parapet Merlon
- Tower Platform
- Gate Frame
- Wood Barricade
- normal block placement
- drag wall construction
- existing blueprint/stamp capability

## Siege / defense

- Ballista
- Catapult
- Turret Catapult
- Turret Catapult Mk2
- Cannon
- Kettle
- Ballista Bolt
- Stone Shot
- Flame Shot
- Cannonball
- Hot Oil

## Rail / coaster

- Rail
- Rail Slope
- Rail Loop
- Rail Switch
- Rail Cross
- Rail Curve
- Rail Climb
- Mine Cart
- Coaster Car

## Core / lighting

- Core of Power
- enemy core in Battlefield
- Torch
- Wall Lantern
- Post Lantern
- Campfire
- Blue Light Block
- Red Light Block

## Enemies

- current ordinary orc/raider
- brute
- troll

Do not add nonexistent food, armor, magic or allied units simply to fill the Expo.

---

# 11. Terrain requirements

The Expo is not a flat test plate.

Use terrain intentionally:

- central plaza, construction yard, defense range and battlefield: mostly level;
- forest/resource area: natural terrain;
- quarry: cut/exposed rock;
- Mining Mountain: large elevated mass with deep ore;
- mine tunnel: broad, lit and traversable;
- coaster: use elevation where it improves the ride;
- keep clear pathing between districts.

The Expo should feel like a curated miniature world.

Terrain-dependent exhibits must remain editable with the ordinary voxel systems so they can test digging, tunneling, rail placement and future machines.

Do not create the Mining Mountain as decorative mesh scenery detached from voxel interaction.

---

# 12. Expo paths and wayfinding

Use generous main avenues between districts and smaller local paths inside them.

Every district gets:

- large category sign;
- clear entrance;
- readable route from the Central Plaza;
- sufficient spacing around interactive machines;
- expansion edge/corridor.

Use signs to explain process flow where helpful, for example:

**ORE → MINER → ORE BIN → CART → WAREHOUSE → FOUNDRY**

The path system should help the player understand progression:

Resources → Processing → Construction/Defense → Battlefield.

CoasterCraft is a separate entertainment/showcase branch.

---

# 13. Development-world runtime rules

- No ambient/random enemy attacks outside explicit combat scenarios.
- Machines and world simulation continue under inventory/station menus according to the existing live-menu contract.
- Pause menu still pauses.
- Development mode begins with a readable/stable daytime by default; do not remove day/night functionality.
- Player can edit terrain and structures normally.
- Development inventory is not automatically infinite. The Supply Depot provides abundant test stock and canonical reset.
- Do not special-case every gameplay transaction as free; reuse actual systems so testing remains meaningful.
- Expo fixture placement may bypass ordinary recipe costs during generation because it is authored development-world initialization, not player crafting.
- Save/load must persist owner changes to the development world.
- Reset Expo intentionally discards those development-world changes and rebuilds the current canonical fixture after confirmation.

---

# 14. Recommended implementation boundaries

Use the existing architecture and keep Development-specific orchestration isolated.

A reasonable shape is:

- **DevelopmentMode / DevelopmentWorldCoordinator**  
  owns entry, dedicated save namespace, canonical fixture version and safe reset.

- **ExpoDefinition / ExpoLayout**  
  loads the data-driven districts/exhibits, computes parcels/volumes and expansion-safe placement.

- **ExpoBuilder**  
  applies authored voxel terrain and places existing entities through authoritative world/workstation APIs.

- **SignService / SignPanel**  
  owns sign content, item picker, persistence and rendering.

- **ExpoResetService**  
  restores a named reset group such as `battlefield` without touching other districts.

Names may follow current project conventions; do not build a generic framework if smaller modules fit existing patterns.

The authoritative game services remain responsible for inventory, workstations, storage, siege, carts, terrain and enemies.

---

# 15. Validation requirements

Add a focused Development Expo automation and Windows runner rather than relying only on manual inspection.

Minimum automated gates:

## Core/Continue

- normal save with destroyed/missing Core does not crash/hang on load inspection;
- main menu reports the slot as Game Over / not ordinary Continue;
- Development Start is still available.

## Development isolation

- Expo uses a separate save namespace;
- reset/restart never mutates Slot A, Slot B or CoasterCraft data.

## Supply Depot

- every non-hidden visible canonical item appears exactly once in the generated supply catalog;
- each has count 8;
- no chest contains more than eight distinct supplied item types;
- every supply chest sign lists the same item IDs as that chest;
- adding a visible unclassified item causes a clear validation failure/unassigned report.

## Sign

- ground sign and wall sign both place legally;
- right-click editor persists mode/text/item IDs;
- item grid supports eight entries;
- saved/reloaded sign contents match exactly.

## Industry

- Miner extracts authored Expo ore;
- Ore Bin receives material;
- Mine Cart can haul to Warehouse;
- Foundry can pull ore/fuel and produce ingot;
- storage-network adjacency remains functional.

## Battlefield

- START ATTACK produces a representative mixed current assault;
- units route toward the intended development Core;
- player siege defenses can engage;
- RESET BATTLEFIELD removes active combat state and restores both cores, default units/defenses/ammo without rebuilding the entire Expo.

## Coaster

- the canonical showcase course contains each required current track family;
- Coaster Car can board and traverse the course;
- the ride uses existing CoasterRide behavior.

## Regression

Run:

- `python tools/validate_foundation.py`
- `python -m unittest discover -s tests -v`
- the new Development Expo runner;
- relevant existing Industry, Siege, Enemy, Coaster and Core/asset runners;
- exported Windows runtime validation with the pinned toolchain.

Do not claim PASS from static parsing alone.

---

# 16. Owner playtest checklist

The owner should be able to:

1. Start the program and click **Development Start**.
2. Spawn in a clear Central Plaza with an Expo map.
3. Walk directly to a Supply Depot containing every current player-visible item without gathering anything first.
4. Read sign icons/names and take test items from organized chests.
5. Enter the Mining Mountain and run through the large lit tunnel.
6. Observe Miner → Ore Bin → Cart → Warehouse → Foundry operating.
7. Inspect construction pieces and a small assembled castle/tower.
8. Test individual siege machines at the Defense Range.
9. Walk to the Battlefield, press START ATTACK, observe combat, then press RESET BATTLEFIELD and immediately repeat.
10. Walk to CoasterCraft, inspect current track pieces, board the showcase coaster and ride it.
11. Move/build/dig freely and save/reload the Development world.
12. Reset the Expo when a clean canonical environment is desired.
13. Lose a Core in a normal save without causing Continue to crash.

---

# 17. Boundaries — do not expand this milestone

Do **not** use this commission to add:

- food gameplay;
- armor mechanics;
- magic;
- allied workers;
- new enemy classes;
- new siege weapon classes;
- economy/market gameplay;
- multiplayer;
- final art pass;
- new engine/plugin versions;
- redesigned inventory/crafting architecture;
- a generic developer console;
- a second parallel implementation of existing services.

Only add new gameplay content required by this milestone:

- Development Start / Expo orchestration;
- reusable Sign item/editor;
- Expo fixture/data;
- battlefield start/reset control;
- lost-Core Continue safety behavior.

Everything else is composition of existing systems.

---

# 18. Git/worktree execution

Use the repository's normal discipline:

- canonical checkout: `D:\CODEX\Craft-and-Defend\main`
- worktrees: `D:\CODEX\Craft-and-Defend\worktrees`

Create a dedicated implementation worktree/branch from the current reviewed `main`, for example:

`feature/development-expo`

Do not implement directly in `main`.

Commit coherent checkpoints.

Do not merge until owner playtest/authorization.

Final handoff must report:

**STATUS / DONE / EXPECT / TEST / LIMITATIONS-FAILURES / NEXT / GIT-REPRODUCIBILITY**

Include exact branch, worktree, commit, tests run and Windows export evidence.

---

# 19. Design principle for future features

The Expo is expected to grow with the game.

Whenever a future feature is added, its author must answer:

1. What Expo category/district does it belong to?
2. Is it best shown as a booth, system demonstration, environmental exhibit, scenario or showcase?
3. What current systems does it interact with?
4. What visible demonstration proves it works?
5. What parcel/volume does it require?
6. Does its addition require a new district or simply another expandable booth?

New technology should gain an Expo presentation through data/configuration and a bounded fixture update, not through ad-hoc redesign of the whole map.

The Expo is a living systems showroom and development test bench.
