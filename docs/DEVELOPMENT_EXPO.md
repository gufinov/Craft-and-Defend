# Development Expo

The owner's development world: one campus where every built system stands
assembled, ready to walk up to and try. The commission is
[the implementation handoff](DEVELOPMENT_EXPO_HANDOFF.md); this file is the
contract of what is built.

Read it in this order: the **mode** (how it is entered, where it saves, its
pause menu and runtime rules, and the lost-Core Continue safety that had to
be fixed before any of it), then the **manifest**, the **layout engine**, the
**builder**, the **campus** those three produce, and the **growth rule** new
features follow. The district cards still to come append their sections
below.

---

## Lost-Core Continue safety (§3)

A destroyed Core of Power means **Game Over**, never a broken save.

- **The save always loads or fails visibly.** `WorkstationService.restore`
  no longer refuses a whole snapshot because one station record cannot be
  replaced. A record that is malformed, names content this build does not
  have, or collides with an already restored station is **dropped** and
  reported in the result's `skipped` list (also printed as
  `STATION_RESTORE_SKIPPED …` and kept on `GameSession.restore_skipped`).
  Only a snapshot that cannot be read at all still fails, and that failure
  now reaches the app through `GameSession.load_failed`, which leaves the
  loading screen showing the reason with **Back to Main Menu**. The endless
  "Loading finite world… Station restore failed: INVALID_STATION_SNAPSHOT"
  screen is gone.
- **The world may change under a station.** A saved station whose cells no
  longer pass a placement check (its supporting ground was dug or blasted
  away, its chunk has not streamed in yet) is restored where it stood, with
  `EntityFootprintService.force_reserve`. That is what the running game does
  too - digging under a chest does not delete the chest - so a reload must
  not disagree with it.
- **Integrity is normalised, not fatal.** A saved integrity outside the
  entity's sheet is clamped into range. A station that actually reached zero
  was erased when it was destroyed, so such a record is stale bookkeeping.
- **The drill ends as lost.** A core-defense snapshot naming a core station
  that no longer exists restores as `FAILED` with the line "Your Core of
  Power is gone; the last defense counts as lost." Any other unrestorable
  drill (core or barricade) is cleared with a message instead of failing the
  load.
- **No core is ever re-created in a normal save.**
- **The main menu says so.** `GameSession.game_over_report(snapshot)` reads
  the checkpoint the menu already loaded: the slot is over when no
  `core_of_power` station is saved **and** either the core-defense state is
  `failed` or the core the drill defended is missing. Such a slot shows
  `Game Over — Start New`, its Continue button disabled, with the ordinary
  Start New path beside it. Nothing is written to the slot.

Regression: **T210** in `--f3-automation=phase1`.

---

## Development Start (§4)

Main menu → **Development Start** (after CoasterCraft) opens the Development
submenu: **Continue** (enabled only when a development save exists), **New
(build the canonical Expo)**, **Back**. `START.cmd dev` (`--development`)
goes straight in: Continue when the Expo is saved, otherwise New.

`DevelopmentMode` (`game/scripts/app/development_mode.gd`) is modelled on
`CoasterCraftMode` and owns entry, the save namespace, the fixture version
and reset:

| Member | Meaning |
| --- | --- |
| `SAVE_DIR := "development"` | its own `SaveCoordinator` at `<data root>/development` |
| `EXPO_FIXTURE_VERSION` | the canonical fixture this build generates |
| `START_TIME := "09:00"` | the clock a fresh Expo opens at |
| `setup(app)` / `has_save()` / `data_root()` | as CoasterCraft's |
| `begin(continue_existing)` | New / Continue through the app's ordinary `_open_session` |
| `leave()` | the session left the mode |
| `on_session_ready(fresh)` | stamps the fixture version, sets the daytime clock and builds the Expo on a fresh world |
| `active` | a session of the mode is open |

**Save isolation.** The mode never reads or writes Slot A, Slot B or the
CoasterCraft namespace: `CraftAndDefendApp.active_saves()` returns the
mode's coordinator while it is active, and that coordinator's root is
`<data root>/development`. Settings (keybinds, graphics, hero armour, track
auto-clear) stay shared, as they are for CoasterCraft.

### Pause menu

Its own panel (`DEVELOPMENT EXPO · PAUSED`), one column, **no drill
column**: Resume, Save (checkpoint in place), **Reset Expo**, Save and Exit
to Menu, Save and Quit, Settings, Keybinds, Hero armour, Track auto-clear.

**Reset Expo** asks first — "Rebuild the canonical Expo? Development-world
changes are lost" — and on **Rebuild the Expo** drops the open world without
saving and opens a new one on the same save file, rebuilt from the canonical
fixture. The checkpoint on disk is replaced by the next ordinary save (Save,
Save and Exit, Save and Quit), so a reset pressed by accident costs nothing
and no other save is involved. **Keep this world** returns to the pause menu.

### Runtime rules (§13)

The Expo is the real game, with only these differences (all behind
`GameSession.development`, mirroring the `coastercraft` flag):

- no ambient or random enemy pressure — nothing schedules a wave, and the
  enemy Core of Power is not placed by wandering into the enemy base;
  combat happens only through an explicit Expo control;
- the defense-drill HUD line is hidden and the enemy-base compass and
  minimap marker with it; the navigation line reads `DEVELOPMENT EXPO`;
- a fresh world starts at 09:00 — day/night is **not** removed, the cycle
  runs on from there;
- the live-menu contract is untouched: only the pause menu (and saving)
  pauses the world;
- saving and loading are normal, so the owner's changes to the Expo persist;
- the starter "IRON VEIN" markers of a normal new game are not planted;
- **inventory is not infinite** — no creative placement, no top-up. The
  Expo's Supply Depot (card G) provides test stock. Fixture placement during
  generation may bypass item costs (`extra["_free"] = true`), because that is
  authored world initialization, not player crafting.

The session snapshot records `"mode": "development"` and
`"expo": {"fixture_version": …}` so a later card can detect a world built
from an outdated fixture.

---

## Seams the district cards use (§14)

Keep these small; they are the whole public surface of the mode.

```gdscript
DevelopmentMode.set_builder(builder: Callable)      # builder.call(session, fresh) -> Dictionary
DevelopmentMode.build_expo(session, fresh) -> Dictionary
DevelopmentMode.register_reset_group(name: String, handler: Callable)  # handler.call(session)
DevelopmentMode.reset_group(session, name) -> Dictionary
DevelopmentMode.reset_groups() -> Array[String]
DevelopmentMode.world_bounds() -> Dictionary                # {min, size} or {}
DevelopmentMode.layout / DevelopmentMode.expo_builder       # the wired pair
```

- **`build_expo(session, fresh)`** runs on a fresh development world and on
  Reset Expo. It logs `EXPO_BUILD start …` / `EXPO_BUILD end …` around the
  registered builder and records `last_build` (`{ok, fresh, builder,
  seconds}`). `setup()` loads the manifest into `layout`, creates the
  canonical `ExpoBuilder` and registers it through `set_builder`, so
  Development New and Reset Expo both build the campus; a card may still
  replace the builder for a test.
- **`world_bounds()`** is the layout's chunk-aligned canonical world size plus
  its expansion margin (§6). The app passes it into the session, which hands
  it to `WorldAdapter.initialize` as `bounds_override`; a normal or
  CoasterCraft session passes `{}` and keeps `world.json`.
- **`reset_group(session, name)`** is the `ExpoResetService` seam: it
  restores one named district without touching the others. An unregistered
  name returns `{"ok": false, "reason": "NO_GROUP"}`. The builder's own
  per-district groups (`district:<id>`) are registered here after a build;
  card E adds `battlefield` with `register_reset_group`.
- **`EXPO_FIXTURE_VERSION`** is raised whenever the authored Expo changes in
  a way an existing development world should be rebuilt for.

---


## 1. The manifest

| | |
|---|---|
| Source of truth | `contracts/development_expo.json` |
| Runtime mirror | `game/data/development_expo.json` (byte-identical copy; `validate_foundation.py` fails if the two differ) |
| Loaded by | `ExpoLayout.read_manifest()` from `res://data/development_expo.json` |
| Validated by | `validate_development_expo()` in `tools/validate_foundation.py`, plus `DevelopmentExpoTests` in `tests/test_foundation.py` |

`tools/format_content.py` only rewrites `content.json`, so the Expo manifest is
not run through it; it is hand-maintained in a readable one-record-per-line
shape and copied to the mirror. No coordinates live in game code: the manifest
and the layout engine own placement.

### Campus header

| Field | Meaning |
|---|---|
| `ground_y` | The top solid cell of the level campus grade (-1: the player walks at y 0) |
| `floor_y` | Bedrock level; the computed world never rises above it |
| `spawn_feet` | Where Development Start puts the player (the plaza) |
| `chunk_size` | The world bounds are rounded outward to this (16) |
| `expansion_margin` / `vertical_margin` | Free world kept around and above the campus |
| `avenue_width` / `local_path_width` | Main avenues between districts; paths inside one |
| `clear_height` / `fill_bottom` | How far a levelled pad is cleared above and underpinned below |
| `deferred_items` | item id -> the card that will exhibit it (see **Growth rule**) |

### District

`id`, `name`, `owner_card`, `prepare` (`full` = built now, `connect` = avenue and
entrance sign only, its own card builds the rest), `origin` + `size` (a volume
whose floor sits at `ground_y`), `entrance` (a cell on the district edge),
`terrain`, `expansion_corridor` (a box at least one avenue wide, flush against
the district and overlapping nothing), `connections`, `expansion_priority`,
`sign`, `exhibits`.

### Exhibit

| Field | Meaning |
|---|---|
| `id` | Stable id, unique across the whole Expo |
| `kind` | `catalog`, `functional`, `system_demo`, `environmental`, `scenario`, `showcase` (the handoff's five scales) or `reserved` — a parcel that stays empty and signed |
| `footprint` | Requested volume `[w, h, d]` |
| `clearance` | Free cells kept on every side of it inside its district |
| `orientation` | `north` / `south` / `east` / `west` — which way a visitor reads it |
| `entities` / `items` | Referenced content ids; validation rejects an id that is not in the content registry |
| `terrain` | What the builder authors here (see the terrain kinds below) |
| `connections` | Which path or line the exhibit must touch |
| `sign` | `{title, lines, item}` — the sign card renders it; `item` must exist |
| `reset_group` | Optional named group for a partial rebuild |
| `expansion_priority` | Lower = kept, higher = first to move when the campus grows |
| `offset` | Optional anchor relative to the district origin, for terrain-bound exhibits (the mountain and everything inside it) |
| `nested` | This parcel is carved inside another exhibit's volume, so it is exempt from the overlap rule and must lie wholly inside a host parcel |

Terrain kinds: `level`, `natural`, `tree`, `forest`, `quarry`, `coal_seam`,
`surface_ore`, `ore_face`, `mountain`, `tunnel`, `ore_core`, `chamber`.

### Growth rule

A visible item must be exhibited somewhere or listed in `deferred_items`
against the card that will exhibit it. Registering new content without doing
either fails `validate_foundation.py`, so nothing can silently disappear from
Development Start (handoff section 6).

---

## 2. Layout engine — `game/scripts/expo/expo_layout.gd` (`ExpoLayout`)

Pure data in, pure data out; it never touches the world. The same manifest
always solves to the same layout (`fingerprint()` is the determinism check).

**Parcel packing.** An exhibit with an explicit `offset` is anchored there.
The rest are shelf packed in manifest order inside the district's usable
rectangle (the district inset by `local_path_width` on all sides): rows run
along +x, each exhibit surrounded by its `clearance`, a `local_path_width` gap
between neighbours, wrapping to a new row past the deepest cell of the row
above. A district that cannot hold its exhibits is a validation failure, not a
silent overlap. `expo_parcels()` in `tools/validate_foundation.py` is the
Python oracle of the same rule — change one and you must change the other.

**Avenues.** One L-shaped avenue per district, `avenue_width` wide at ground
level, from the plaza's centre along x and then along z to the district's
`entrance`. The builder paves them in castle stone, which is what makes the
routes from the plaza readable.

**Expansion corridors.** Each district declares one; validation requires it to
touch the district, to be at least an avenue wide and to overlap nothing. New
booths grow into it without re-cutting the campus.

**World bounds.** The union of every district, corridor and avenue, plus
`expansion_margin` horizontally and `vertical_margin` above, with the floor
held at `floor_y`, rounded outward to whole chunks. With the current manifest
that is **min `(-160, -16, -96)`, size `(384, 48, 320)`** — computed, not the
normal game's `(-160, -16, -192)` / `(320, 48, 384)`. `WorldAdapter.initialize`
takes a `bounds_override` for exactly this; an ordinary session passes `{}` and
keeps `world.json`, so a normal game is unaffected.

**API.** `load_layout(manifest := {})`, `district_ids()`, `district(id)`,
`district_bounds(id)`, `district_corridor(id)`, `district_avenue(id)`,
`exhibit_ids(district_id := "")`, `exhibit(id)`, `parcel_for(id)` ->
`{origin, size, orientation, district, nested}`, `reserved_parcels()`,
`world_bounds()` -> `{min, size}`, `sign_data(id)`, `ground_y()`,
`spawn_feet()`, `report()`, `fingerprint()`.

---

## 3. Builder — `game/scripts/expo/expo_builder.gd` (`ExpoBuilder`)

Applies the layout through the authoritative services only: voxels through
`WorldAdapter.set_cell`, fixtures through
`WorkstationService.try_place(..., {"_free": true})` (authored development-world
initialisation, handoff section 13 — not player crafting). Everything stays an
ordinary editable voxel; there is no decorative mesh anywhere in the campus.

**Streamed, budgeted build.** Work is queued as ops and drained
`UNITS_PER_FRAME` at a time from `_process`, the way `CoasterCraftMode` levels
its plate, so a build never freezes the frame. A column whose chunks are not
streamed in yet is retried; after a few fruitless passes its op is parked and
re-queued once the player moves. A district on the far side of the campus
therefore finishes when someone reaches it — `progress()` reports
`pending` / `deferred` / `cells` / `entities` / `failures`, and the gate waits
on both counts reaching zero.

**API for the other cards**

| Call | Does |
|---|---|
| `configure(layout)` / `bind_session(session)` | Attach the solved layout and the open session |
| `build_all()` | Every `prepare: "full"` district, plus the avenues of the rest |
| `build_district(session, district_id)` | One district: avenue, pad, its exhibits, its signs; registers the reset group `district:<id>` |
| `place_exhibit(session, exhibit_id)` | One exhibit: terrain, fixtures, sign |
| `level_area(origin, width, depth, surface, clear, label)` | `origin.y` becomes the top solid cell, `clear` cells above it are emptied, air or water below is underpinned to `fill_bottom` |
| `fill_box(origin, size, voxel, replace_air_only, label)` | Solid box |
| `carve_box(origin, size, label)` | Box to air |
| `carve_tunnel(from, to, width, height, label)` | Axis-aligned passage with a solid floor under it |
| `scatter_ore(origin, size, voxel, per_thousand, salt, label)` | Deliberate ore in stone; a deterministic cell hash, so the same box always gives the same ore |
| `plant_tree(base, height, label)` | Log trunk and leaf cap |
| `place_entity(entity_id, anchor, rotation, label)` | One free fixture |
| `sign_at(cell, facing, data, owner_id)` | Places a real `sign` station and writes its board (see below) |
| `register_reset_group(name, callable)` / `reset_group(name)` | What card A's `DevelopmentMode.reset_group` calls |
| `progress()` / `pending_ops()` / `deferred_ops()` / `failures()` / `pending_signs()` | State for diagnostics |

**Signs.** `sign_at` queues a `sign` op: the `sign` station (card B,
[Signs](SIGNS.md)) is placed free at the requested cell and its board is
written through `GameSession.configure_sign`. The manifest block translates
into the sign's own record — a block naming an `item` becomes Header + Item
Grid, a title with body lines becomes Split Text, a bare title Single Text.
The requested cell is an exhibit's corner, so it may be taken (the mine rail
runs along it) or buried (the mountain mass is solid rock): the sign then
takes the nearest free cell in the ring around it, climbing to the first air
cell with solid ground under it. A rebuild rewrites the board of the sign
already standing there rather than adding a second one. `sign_requests()` is
the full list with each request's placed instance id; `pending_signs()` is
whatever is still unfulfilled — T215 asserts it is empty. The current campus
places 45 signs.

**Wiring.** `DevelopmentMode.setup()` loads the manifest into `layout`, creates
the `ExpoBuilder` and registers it through card A's `set_builder` seam, so
Development New and Reset Expo both build the campus and the builder's
`district:<id>` reset groups reach `DevelopmentMode.reset_group`. `app.gd`
holds the `DevelopmentMode` node, the `--development-expo-automation=`
dispatch, the save coordinator switch in `active_saves()`, the bounds hand-off
in `_open_session` and the `on_session_ready` call.

---

## 4. The campus this card built

Spawn is the plaza at `(0.5, 2.0, 40.5)`; north is -z, west is -x.

| District | Box (x, z) | State |
|---|---|---|
| Central Plaza | -16..15, 26..53 | Built: level castle-stone plaza, development Core of Power, orientation sign listing every route, avenues out to every district, the Reset Expo access parcel reserved for card A |
| Supply Depot | -16..15, 8..21 | Pad and avenue built; the chest wall is card G's |
| Reserved — future districts | 24..47, 26..53 | Deliberately empty and signed, in full view east of the plaza |
| Day One | -60..-17, 56..95 | The eleven-step chain tree -> log -> planks -> sticks -> workbench -> wood pick -> stone -> stone pick -> furnace -> iron -> iron pick, each on its own signed parcel, read along +x and then down the rows |
| Equipment | -9..24, 60..93 | Wood/stone/iron pick, wood axe, iron sword as catalog booths, a functional Sign booth (a real writable sign beside its label), and the empty signed future-armour parcel |
| Resources | -88..-49, 8..47 | Forest patch, stepped quarry, coal seam, surface iron and gold outcrops |
| Mining Mountain | -124..-53, -68..3 | A 72x72 voxel mass rising to y 23, a deliberately authored deep ore core (coal, iron, gold), a 9-wide 7-high tunnel lit end to end by post lanterns with a 64-cell rail line inside, a manual-mining chamber and a separate automated-mining chamber with a Miner and an Ore Bin on a deep ore face |
| Industry, Construction Yard, Defense Range, Battlefield, Lighting, CoasterCraft | see the manifest | Parcels, entrances, corridors and avenues reserved; cards D, E and F build them |

The Mining Mountain's east mouth faces the campus and its rail line points at
the Industry district's entrance, which is what card D's chain is expected to
continue.

---

## 5. Adding an exhibit for a new feature (handoff section 19)

1. Add the item/entity to `contracts/content.json` as usual.
2. Add an exhibit record to the district that owns it in
   `contracts/development_expo.json` — id, kind, footprint, clearance,
   orientation, the referenced ids, terrain, connections and a sign — or, if it
   is not ready to be shown, add its id to `deferred_items` against the card
   that will. Nothing else in the file changes: the layout engine re-packs the
   district and grows into its expansion corridor.
3. Copy the file to `game/data/development_expo.json`.
4. Run `python tools/validate_foundation.py` and
   `python -m unittest discover -s tests`, then
   `--development-expo-automation=gate`.

If the district is full, widen it (and its corridor) in the manifest or claim
the reserved parcel — the validator says which exhibit did not fit.

---

## Checks

| Gate | Covers |
| --- | --- |
| `--f3-automation=phase1` | **T210** lost-Core Continue: a save is written with the defended core destroyed and a chest left over dug-away ground; the menu reports Game Over — Start New with Development Start still reachable and the file readable; Continue through the app's own path finishes inside a bounded number of frames with the drill restored as lost, no re-created core and the chest back in place |
| `--development-check` | the whole Development Start round trip: the submenu, New, `DEVELOPMENT DATA_ROOT <path>` under `<data root>/development`, the runtime rules (no waves after three seconds of play, no enemy core, hidden drill line, daytime clock with the cycle running, no creative top-up), the builder and reset-group seams, the pause menu without drills, the Reset Expo confirmation and rebuild, Save and Exit and Continue — and **T211_DEVELOPMENT_MODE_ISOLATION**: a marker written into a normal Slot A checkpoint reads back unchanged, with the same revision, after a Development New and a Reset Expo, and the CoasterCraft namespace is untouched |

`game/scripts/diagnostics/development_expo_automation.gd`, dispatched as
`--development-expo-automation=gate` (headless) and `=visual` (windowed,
renders the plaza and the tunnel). This suite is the milestone's home; later
cards add their records to it.

- **T213_EXPO_LAYOUT** — the manifest parses, every referenced id exists, no
  two districts, corridors or parcels overlap, every district has an expansion
  corridor, the reserved parcels are empty and signed, the chunk-aligned world
  bounds hold every parcel plus the expansion margin, and two loads solve
  identically.
- **T214_EXPO_PLAZA_AND_DAY_ONE** and **T214_EXPO_MOUNTAIN** — after a
  Development New: the plaza is level and clear around the spawn, the Core
  stands, all eleven Day One exhibits are built in chain order with the
  Workbench and Furnace standing; the ore core holds coal, iron and gold, a
  56-cell straight walk down the tunnel is unobstructed, floored and lit the
  whole way, the rail line chains cell by cell and the automated-mining Miner
  and Ore Bin stand.
- **T215_EXPO_SIGNS_PLACED** — after a Development New every district and
  exhibit sign request in the manifest is a real placed `sign` station whose
  `sign_data` carries the manifest's title, lines and item; nothing is left
  unfulfilled in the builder's sign queue. The plaza orientation sign and one
  district sign are read back field by field.
- **T215V_SIGN_VIEW** (`=visual`) — `development-expo-sign.png`, the plaza's
  orientation board framed from in front of it, close enough to read.
