# Nemesis / RTS / Perception direction — owner handoff, 2026-09-25

> **Authority and intent**
>
> This document records Tony's current owner direction from the 2026-09-25 design session. It is a **design handoff**, not a blanket implementation commission. Existing runtime truth, tests, contracts, and current local work remain authoritative until explicitly amended by a scoped backlog card. Claude or any coding agent must first reconcile this document against the **actual local checkout**, unpushed work, current `docs/STATUS.md`, active worktrees/branches, and existing contracts before implementation.
>
> **Do not reset, overwrite, rebase away, or otherwise disturb advanced local work merely to match this document or remote `main`.** This file was intentionally added on an isolated documentation branch so it can be fetched/read/cherry-picked safely.

---

## 1. Product direction in one sentence

Craft & Defend should evolve into a first-person voxel survival / fortress / RTS hybrid in which the player and a persistent enemy Nemesis begin weak, discover the same unknown world, gather from the same finite resources, build infrastructure and armies under comparable economic rules, scout and fight through fog of war, and eventually wage a territorial war that culminates in a real siege of the enemy Core.

The point is not to bolt RTS controls onto a survival game. The point is to let the game **grow naturally from solo survival into delegation, automation, military command, territorial conflict, and siege warfare**.

---

## 2. Core parity rule: the Nemesis must earn capabilities

The Nemesis must **not** begin with free scouts, free mines, free armies, free map knowledge, or a magical background income that the player cannot meaningfully contest.

At the conceptual start:

- Player: Core, one player character, minimal starting capability.
- Nemesis: enemy Core, one enemy commander character, minimal starting capability.
- Neither side initially knows the world beyond what it can perceive.
- Neither side initially owns scouts, barracks, mines, siege weapons, or a mature fortress unless a specific game mode later says otherwise.

The enemy commander is the enemy's initial gatherer/explorer, just as the player is the player's initial gatherer/explorer.

A scout only exists after the Nemesis has acquired the prerequisites and paid the cost to produce one. The same principle applies to workers, soldiers, archers, siege units, mines, logistics, towers, walls, and automation.

### Parity does not mean literal animation parity

The simulation may resolve distant enemy work mathematically, but the **time, resource, knowledge, and prerequisite constraints must remain comparable** to what the player would need.

A remote Nemesis gathering task may be represented as state such as:

- destination / source;
- travel time;
- work time;
- yield;
- return/delivery time;
- interruption state.

When the player is nearby, the same state should materialize into physical actors and structures where feasible.

---

## 3. Strategic opening: economy vs. defense vs. military

Early resources must create a real strategic fork for both sides.

A commander may invest in:

- **Economy** — tools, gathering, scouts, resource discovery, mines, logistics, automation.
- **Defense** — walls, gates, towers, guards, weapons, protected storage.
- **Military pressure** — barracks, archery range, soldiers, raiders, siege capability.
- **Balanced growth** — slower but less exposed.

Economy-first can snowball faster if not punished. Defense-first is safer but slows expansion. Military-first can harass an opponent but may leave the attacker's own economy and Core underdeveloped.

This is intended to be one of the central strategic tensions of the game.

### Difficulty philosophy

Difficulty should primarily change **decision quality**, not grant invisible economic cheats.

Examples:

- Beginner AI may overbuild walls, scout poorly, misallocate troops, react slowly, or leave production idle.
- Advanced AI may choose stronger priorities, exploit discovered opportunities, protect valuable sites, coordinate raids, and respond to threats more efficiently.

Do not default to stronger identical Orcs, free scouts, free stone, or arbitrary HP inflation as the main difficulty mechanism.

---

## 4. Nemesis commander cognition: perception → memory → goals → prerequisites → action

The Nemesis should behave as a planner operating from what it actually knows.

High-level loop:

1. **Observe** currently perceptible world state.
2. **Update memory / fog-of-war knowledge.**
3. **Assess needs and strategic priorities.**
4. **Generate candidate goals.**
5. **Check prerequisites and costs.**
6. **Select a goal based on strategy and current risk.**
7. **Decompose the goal into tasks.**
8. **Execute / delegate.**
9. **Re-evaluate when state changes.**

Example:

- Goal: build first wall.
- Requires: enough stone, wood, and construction capability.
- Missing: stone.
- Known stone source? If yes, acquire it. If no, explore.
- Return/deliver.
- Build wall.
- Reassess next objective.

The same dependency reasoning applies to barracks, scouts, archers, mines, warehouses, rails/logistics, towers, weapons, and later automation.

### Implementation direction

Use deterministic/game-system logic (world knowledge + dependency graph + utility/priority scoring + task execution), not an LLM in the runtime loop.

---

## 5. Fog of war and the Perception Model

"Radius" must not be treated as one universal mechanic. The important concept is **Perception Model**.

### Commander perception

The commander has a current visual/perception envelope. It moves with the commander.

If the commander needs wood and sees no trees, it may choose an unexplored direction and move until new terrain enters perception. Once it discovers something useful, that information enters memory.

### Memory states

At minimum distinguish:

- unknown;
- currently visible;
- discovered / remembered;
- potentially stale intelligence.

The Nemesis must not magically know that a remembered location has changed while nobody is observing it.

Example: if the enemy once discovered an ore mountain, then later the player fortifies that mountain while no enemy observer is present, the Nemesis should not automatically know about the new defenses.

### Perception should eventually be multi-channel

Primary channels:

- **Vision** — directional, affected by distance, line of sight, day/night, lighting, concealment.
- **Hearing** — largely radial, affected by sound intensity, surface material, movement, environment, obstructions/masking.
- **Shared intelligence / alarms** — one observer can report knowledge to nearby/group/faction actors according to communication rules.

This is a broad architectural direction. Vision should come first; acoustic perception can be implemented later without changing the core concept.

---

## 6. Day/night, stealth, thieves, and acoustic terrain

### Stealth should not be binary

A thief is not simply "invisible". Detection is a contest between observer capability, thief stealth, distance, lighting, terrain, facing, movement, and sound.

Possible states:

- unaware;
- suspicious;
- detected;
- alarmed.

A guard may hear something and investigate before gaining visual identification.

### Day/night

Night should substantially reduce visual detection ranges unless compensated by light, tower capability, special units, magic, or equipment.

Example direction only:

- tower has long daytime vision;
- thief detection is shorter than general vision;
- at night both general and stealth detection shrink further.

Exact distances are tuning, not locked here.

### Acoustic terrain

Terrain can be a defensive tool.

Examples:

- grass: relatively quiet;
- gravel / loose stone / dry leaves / wood planks: louder;
- sprinting: louder than walking;
- heavy armor: louder than light clothing;
- rain, waterfalls, battle, machinery: can mask sound.

A ring of gravel around a warehouse is therefore a cheap passive early-warning system, not a trap.

### Guard behavior

A `Guard Warehouse` order should normally create patrol behavior around the protected structure/area rather than a statue-like guard standing forever in one orientation. Patrol movement creates openings for stealth while still providing coverage.

### Thief role

A thief is a fragile specialist, not a general fighter.

Potential mission:

- infiltrate target area;
- avoid detection;
- steal from a specified storage/bin/chest;
- escape;
- return stolen resources to friendly storage.

If discovered, the thief should usually be in severe danger.

---

## 7. RTS command layer and mission vocabulary

The player should eventually be able to produce and command units through an RTS-style mode while remaining a character who physically inhabits the same world.

Possible production relationships:

- Barracks → Scout, Swordsman / basic infantry.
- Archery Range → Archer.
- Siege Yard / Foundry-equivalent → siege units or siege crews.

Units should physically emerge / become present in-world rather than existing only as UI counters.

### Selection and formations

RTS mode should support the familiar pattern of:

- select individual / group;
- drag-select;
- assign destination or target;
- line up units / choose formations;
- station forces at gates, towers, mines, roads, outposts, or staging areas.

### Core command vocabulary

Commands discussed in this session include:

- Move.
- Fight-move / attack-ground style movement.
- Patrol.
- Guard structure / area.
- Scout area.
- Wave Attack / Core Assault.
- Sabotage.
- Attack specific target.
- Return Home.
- Await Orders / Hold after mission.

Waypoint chains / shift-click style queued movement should be considered later where useful.

---

## 8. Wave Attack is a mission, not a free spawn

Do **not** rely on free daily minion waves as the long-term model.

A `Wave Attack` / `Core Assault` order should use troops the commander actually produced and can afford to risk.

Mission behavior:

- strategic objective: enemy Core;
- advance toward the Core;
- respond to genuine threats encountered on the route;
- destroy tactically relevant blocking/attacking assets according to unit capability;
- after neutralizing the immediate threat, resume the advance;
- continue until destroyed, recalled, or successful.

Both player and Nemesis can issue this class of mission.

This preserves the economic question: **How often can I afford to send meaningful attacks without crippling my economy or leaving my own Core exposed?**

Randomness can affect timing, scouting, opportunity, or strategic choice, but the units themselves should not be created from nowhere.

---

## 9. Sabotage / special-operations missions

Sabotage is distinct from a Core Assault.

A sabotage group may be ordered to:

- attack one specific structure and return;
- attack infrastructure in a designated area and return;
- attack infrastructure in an area and await further orders;
- patrol/clear an economic route.

### Area sabotage behavior

When assigned to an area rather than one exact object:

1. travel to the designated area;
2. use Perception Model to identify valid enemy infrastructure;
3. attack discovered mission-relevant targets;
4. from each new position, perceive additional nearby targets;
5. continue while valid targets remain / mission constraints permit;
6. when no additional relevant targets are perceived, execute post-mission policy (`return_home`, `hold`, etc.).

This provides "click and forget" convenience without making units mindless. The mission itself tells them how much autonomy they have.

---

## 10. Resource discovery, mines, logistics, and territorial economy

Both factions should participate in the same world economy at a meaningful strategic level.

A resource site should not become an enemy mine simply because the map generator contains ore there.

Intended chain:

1. actor/scout discovers promising terrain or exposed resource evidence;
2. faction learns the location;
3. faction evaluates usefulness, danger, distance, and current needs;
4. if worthwhile and affordable, faction establishes extraction;
5. storage / logistics are established;
6. guards / patrols protect the site;
7. production feeds the faction economy.

### Resource sites are strategic targets

A mine / quarry / logging site may include:

- extraction point;
- workers / automation state;
- warehouse / bin / stockpile;
- local guards;
- patrols;
- transport route;
- nearby outpost / camp.

The player must be able to raid this network and materially hurt the enemy.

Possible effects:

- destroy mine → production stops;
- destroy warehouse → stored resources lost;
- break transport route → local stock accumulates but delivery to stronghold stops;
- defeat guards → site becomes vulnerable;
- leave only a minor route break → enemy may send a repair/engineering mission;
- occupy/destroy the site deeply enough → longer-term denial.

The same class of logic should apply to player automation and enemy sabotage.

### Off-screen simulation

Distant production/logistics should be mathematical state, not thousands of fully simulated actors.

Example state:

- production rate;
- local storage;
- route connectivity;
- delivery rate;
- guards / patrol state;
- interruption / damage state.

When the player approaches, the state should materialize plausibly.

---

## 11. Encampments and outposts

Existing encampments are useful primitives but are **not the complete final enemy-economy design**.

Long-term, camps/outposts can serve different functions:

- patrol projection;
- scout staging;
- resource extraction support;
- forward supply;
- territorial control;
- reinforcement / attack staging.

A camp should not exist only to spawn enemies. Its reason for existing should ideally relate to territory, resources, scouting, defense, or military strategy.

Camp density should naturally increase toward the enemy homeland and/or along important resource/supply corridors as the faction develops.

---

## 12. Stronghold growth and the endgame

The enemy stronghold must not be a static final hut while only camps grow around it.

It should develop as the Nemesis economy develops.

### Blueprint-driven stronghold

Use one of several authored/master stronghold plans rather than asking the runtime AI to invent competent architecture voxel-by-voxel.

Example phased plan:

- Core shelter / inner keep;
- first wall ring + gate;
- towers / barracks / storage;
- second defensive ring;
- ballista / catapult positions;
- siege yard;
- outer defenses / later rings;
- maximum designed fortress state.

The blueprint says **what can be built and where**. The economy and planner decide **when it can be afforded and which objective has priority**.

### Existing locked construction rule must be preserved

Blueprints stamp ordinary voxel blocks. Once stamped, castle walls/towers remain ordinary world blocks for destruction, replacement, pathfinding, and breaching. Do not replace this with a monolithic indestructible `WallEntity`/`TowerEntity` model.

Higher-level metadata/grouping may be useful for UI/planning/analysis, but voxel state remains physical authority unless a later contract explicitly changes that rule. Machines and siege assets may remain entities as already established.

### Fortress growth has a ceiling

The stronghold should have a designed maximum footprint/configuration rather than infinite wall generation.

After reaching maximum fortress development, additional economic strength feeds:

- troop replacement;
- patrols;
- new/stronger forward sites;
- siege engines;
- ammunition;
- repairs;
- offensive armies.

### Final campaign

The player's endgame is a true invasion:

- cross increasingly hostile territory;
- dismantle / bypass camps and resource networks;
- fight field forces;
- bring an army / siege capability;
- breach defensive rings;
- enter the fortress;
- destroy the enemy Core.

The final fortress should reflect what that particular Nemesis managed to build during that particular campaign.

---

## 13. Siege, supply, and finite reserves

Once a stronghold is genuinely besieged and supply connections are cut, it should not receive magical catch-up resources simply because time passes.

Long-term model:

- external mines / sites produce resources;
- connected logistics deliver them;
- stronghold holds finite stockpiles;
- construction, repairs, troops, siege equipment, ammunition consume stockpiles;
- a true blockade / encirclement cuts external income;
- stronghold must fight from stored reserves plus any bounded internal production.

Player presence alone should not toggle this. The **military/logistics situation** should.

If supply routes remain open, the fortress can still receive help. If the player closes them, the siege becomes materially finite.

---

## 14. Targeting, breaching, walls, gates, and complete enclosure

Do not use the permanent tower-defense rule "the player may never completely seal the Core."

If the player completely encloses the Core with walls and no gate, that should eventually be legal gameplay. The consequence is that attackers must breach.

High-level enemy logic:

- valid route exists → use it;
- gate/door provides sensible access → prefer/attack according to tactical rules and durability;
- no valid route → breach is required;
- choose a viable obstruction/breach plan based on unit capability and tactical value.

Current prototype restrictions may temporarily require a route while breaching is incomplete, but that must be documented as a **temporary implementation limitation**, not the final design rule.

### Threat response

Destructible does not mean automatically targetable.

A unit/group attacks a structure because doing so advances its current mission or responds to a threat.

Examples:

- Ballista fires on patrol → group shares threat awareness; capable units respond to the Ballista/tower access problem.
- Empty tower not blocking mission → often ignore.
- Gate blocks Core assault → attack/breach.
- Unrelated wall beside an open route → ignore.

Traps remain hidden/reactive under the existing trap rules unless a future specialist-detection system explicitly changes this.

---

## 15. Towers, weapons, access topology

Structured towers should have meaningful access topology:

- ground;
- door / gate;
- interior;
- stairs;
- top deck;
- mounted weapon.

A tower does not magically increase a mounted weapon's own HP. It protects the weapon through:

- elevation;
- cover;
- range / line-of-sight advantage;
- melee inaccessibility;
- support structure.

If the support tower is destroyed to the point the mounted weapon can no longer exist, the mounted asset can be destroyed as a consequence without requiring full physical collapse simulation.

---

## 16. Simulation LOD: the world remains active when the player is elsewhere

The world must not rely on "things only happen near the player" for strategic systems.

Use simulation tiers:

### Full physical — nearby

- models;
- physics;
- pathfinding;
- perception;
- projectiles;
- detailed combat;
- physical workers/guards where appropriate.

### Regional/coarse — medium distance

- actor/group positions;
- missions;
- health/state;
- production/transport state;
- encounter resolution;
- sabotage/repair events;
- periodic rather than per-frame updates.

### Strategic — far away

- abstract faction/task/resource records;
- mathematical production;
- ETA-based movement;
- mission/event resolution;
- stockpiles / territory / readiness.

As the player approaches, strategic state materializes into plausible physical state.

This applies to both factions' automation, patrols, mines, and economic chains.

---

## 17. Water, load, mobility, and environmental simulation — later roadmap

This is explicitly **not current implementation scope**, but should be preserved as future direction.

### Movement burden

Worn equipment can eventually influence:

- run speed;
- stamina;
- jumping;
- swimming;
- sinking;
- underwater mobility.

A simple category system is preferable initially to exact kilograms.

Example conceptual states:

- light → swim normally;
- burdened → reduced swim / stamina;
- overburdened → sink, cannot swim upward, can walk along bottom.

A heavily armored character who falls into deep water may need to:

- walk up a slope / steps;
- remove/drop enough equipment to become swimmable;
- use specialized gear/magic.

Dropped equipment should remain recoverable where technically reasonable, creating later recovery expeditions rather than arbitrary deletion.

### Mundane and magical solutions can coexist

Possible later equipment/magic:

- flippers → improve swim mobility / offset modest burden;
- snorkel / hose / breathing gear → affects oxygen, not necessarily buoyancy;
- diving/recovery gear → supports salvage;
- water-breathing / buoyancy magic → alternate progression path.

Full plate should not become freely swimmable merely because flippers are equipped.

### Moats and water traps

Water can become real defensive terrain:

- light thief may swim;
- heavy infantry may sink/wade;
- siege machines may need bridges/engineering;
- vertical-sided deep moat is more dangerous than a sloped bank;
- concealed weak covering over a water pit can become a trap.

Again: roadmap direction only.

---

## 18. Terrain as a systemic gameplay input

The broader design principle from this session is:

> Terrain should influence what actors can perceive, traverse, conceal themselves in, survive, and do tactically.

Examples:

- gravel → acoustic detection;
- darkness → visual detection;
- forest → concealment / line of sight;
- water → mobility / burden / routing;
- walls → routing / breaching;
- height/elevation → sight and weapons;
- roads/rails → logistics and strategic value.

Avoid implementing each as isolated special-case logic if a shared system can represent it.

---

## 19. Multiplayer/co-op horizon — do not implement now, do not foreclose

The symmetric command/economy model naturally supports later modes:

- 1 player vs AI Nemesis;
- PvP 1v1;
- 2v2;
- co-op players vs matching number / strength of AI commanders;
- larger team modes later.

This is a future horizon. Current work should remain single-player-first, but state/commands should avoid needless assumptions that only one human-controlled faction can ever exist.

---

## 20. Relationship to existing systems in the repo

This handoff must be reconciled, not blindly layered over existing work.

Known current facts from remote `main` at the time this document was authored:

- the project already has working enemy units, siege units, traps, encampments, sabotage behavior, Expo fixtures, automation tests, and extensive contracts;
- current encampments are implementation primitives and should not be deleted merely because the long-term Nemesis model is richer;
- blueprints stamping ordinary blocks is already locked owner direction and must be preserved;
- current targeting/pathing/breaching contracts must be inspected before any new threat logic;
- the local Claude environment may be **ahead of remote `main`** with unpushed work.

Therefore the first coding-agent action is **reconciliation**, not implementation.

---

## 21. Required Claude / coding-agent preflight before acting

When Tony hands this branch/document to Claude:

1. Inspect local repository status, current branch, remotes, worktrees, uncommitted changes, and commits ahead/behind remote.
2. Read current local `AGENTS.md`, `docs/STATUS.md`, `docs/BACKLOG.md`, `docs/DESIGN_DIRECTION_2026-09-18.md`, `docs/ARCHITECTURE.md`, targeting/pathing/trap/encampment docs, and any newer local docs.
3. Fetch this docs branch **without resetting or overwriting local state**.
4. Read this file as owner direction.
5. Reconcile conflicts between:
   - current tested implementation;
   - current local unpushed work;
   - existing locked contracts;
   - this newer owner direction.
6. Produce a concise reconciliation note identifying:
   - already implemented pieces;
   - compatible extensions;
   - superseded assumptions;
   - architectural seams that should be preserved now;
   - items that belong only on the long roadmap.
7. Only then create/update backlog cards for the next bounded implementation slices.
8. Do **not** begin implementing the entire Nemesis/RTS roadmap in one pass.

---

## 22. Recommended sequencing from this direction

This is a sequencing recommendation, not an automatic commission.

### Near-term foundation to preserve/build toward

1. **Attack / threat behavior correctness** — mission-driven targeting, route/breach behavior, group threat sharing, capability-aware responses.
2. **Common dependency/cost data** — clear requirements for units, buildings, tools, walls, siege, and infrastructure so both player and AI can reason from one rulebook.
3. **Command model** — explicit mission/state vocabulary (`guard`, `patrol`, `scout`, `wave_attack`, `sabotage`, `return_home`, etc.) independent of UI.
4. **Perception foundation** — vision/fog-of-war memory first; acoustic channel later.
5. **RTS unit production/control** — only after the underlying units, costs, mission model, and interfaces are stable.
6. **Nemesis planner** — goals/prerequisites/utility/task execution using discovered knowledge and the same economy.
7. **Strategic/off-screen simulation** — production/logistics/patrol state outside the active region.

### Medium-term

- player scouts and military formations;
- faction resource sites;
- repairs and sabotage missions;
- enemy resource/economy parity;
- growing blueprint-driven enemy fortress;
- supply routes and siege stockpiles;
- player-led offensive army and final invasion loop.

### Long-term / deep roadmap

- acoustic terrain;
- thieves / infiltration;
- sophisticated lighting/night detection;
- water burden / sinking / salvage;
- diving gear / magical mobility;
- advanced environmental stealth;
- multiplayer/co-op.

---

## 23. Product-level summary

The intended end state is not a scripted tower-defense map with a fixed boss castle.

It is a persistent systemic rivalry:

1. both commanders start weak;
2. both explore through fog of war;
3. both acquire resources from the world;
4. both choose how much to spend on economy, defense, military, and expansion;
5. both can scout, patrol, raid, sabotage, defend, repair, and launch Core assaults;
6. distant activity remains strategically active through abstract simulation;
7. resource networks collide and create territorial conflict;
8. fortresses and armies grow because their economies support them;
9. player action against enemy infrastructure materially reduces enemy capability;
10. the game culminates in an invasion and siege of the enemy stronghold/Core that grew during that campaign.

The goal is a world that feels authored by **systems and decisions**, not by a prebuilt sequence of map events.

---

## 24. Safety note for repository integration

This document was intentionally authored as a **new file only** on a separate docs branch. It should be merged or cherry-picked only after the local agent has reconciled its advanced/unpushed state. No existing gameplay/code/doc file needs to be overwritten to consume this handoff.
