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
| `supply` | The Supply Depot's settings: `units_per_item`, `types_per_chest`, `slots_per_chest` and the `hidden_whitelist` of hidden ids the depot may stock |

### District

`id`, `name`, `owner_card`, `prepare` (`full` = built now, `connect` = avenue and
entrance sign only, its own card builds the rest), `origin` + `size` (a volume
whose floor sits at `ground_y`), `entrance` (a cell on the district edge),
`terrain`, `expansion_corridor` (a box at least one avenue wide, flush against
the district and overlapping nothing), `connections`, `expansion_priority`,
`sign`, `exhibits`, and optionally `sign_anchor` / `sign_facing`.

| field | meaning |
| --- | --- |
| `sign_anchor` | Optional (card D2): where this district's own entrance board stands instead of on its `entrance` cell — the same four forms an exhibit's anchor takes, a cell offset `[x, y, z]` being relative to the **district's** origin, plus `"centre"`, `"entrance"` and `"near:<exhibit_id>"`. `near:` must name an exhibit that exists |
| `sign_facing` | Optional (card D2): the compass direction the board reads towards, overriding "away from the district centre". The plaza uses it because a visitor is already standing inside the plaza — it is the spawn — so its board reads back at the spawn rather than at an arriving traveller |

### Exhibit

| Field | Meaning |
|---|---|
| `id` | Stable id, unique across the whole Expo |
| `kind` | `catalog`, `functional`, `system_demo`, `environmental`, `scenario`, `showcase` (the handoff's five scales) or `reserved` — a parcel that stays empty and signed |
| `footprint` | Requested volume `[w, h, d]` |
| `clearance` | Free cells kept on every side of it inside its district |
| `orientation` | `north` / `south` / `east` / `west` — which way a visitor reads it |
| `entities` / `items` | Referenced content ids; validation rejects an id that is not in the content registry |
| `placements` | Optional `[{entity, offset, rotation}]` — fixtures pinned at manifest offsets inside the parcel (the Industry chain, the light gallery). The entity must also appear in `entities` and the offset must lie inside the footprint; the builder places these instead of its own per-entity default geometry |
| `terrain` | What the builder authors here (see the terrain kinds below) |
| `connections` | Which path or line the exhibit must touch |
| `sign` | `{title, subtitle, lines, item, board}` — the sign card renders it; `item` must exist, `subtitle` is the optional stacked subheader (without it the first body line becomes the subheader), and `board` is `narrow`, `wide` (two cells) or `large` (three cells). A block that names no `board` takes the caller's default: the three-cell district board for a district's entrance sign, the two-cell wide board for an exhibit ([Signs](SIGNS.md)) |
| `sign_anchor` | Optional: where this exhibit's board stands instead of its parcel corner — a cell offset `[x, y, z]` inside the footprint, `"centre"`, `"entrance"` (the middle of the edge the `orientation` says a visitor reads from) or `"near:<exhibit_id>"` (one cell outside that exhibit's own reading edge, reading back at it). `near:` must name an exhibit that exists |
| `added_in` | Optional What's new stamp - an ISO date or a zero-padded version, compared as a string (section 9); set it on every exhibit a new card adds |
| `reset_group` | Optional named group for a partial rebuild |
| `expansion_priority` | Lower = kept, higher = first to move when the campus grows |
| `offset` | Optional anchor relative to the district origin, for terrain-bound exhibits (the mountain and everything inside it) |
| `nested` | This parcel is carved inside another exhibit's volume, so it is exempt from the overlap rule and must lie wholly inside a host parcel |

Terrain kinds: `level`, `natural`, `tree`, `forest`, `quarry`, `coal_seam`,
`surface_ore`, `ore_face`, `mountain`, `tunnel`, `ore_core`, `chamber`,
`pavilion`. `natural` authors nothing, which is what a parcel nested inside a
built structure (a light alcove inside the gallery) wants.

### Growth rule

A visible item must be exhibited somewhere, stocked in the Supply Depot or
listed in `deferred_items` against the card that will exhibit it. The depot
stocks every *classified* visible item, so what this rule now catches in
practice is an item nobody has given an Expo category: that fails
`validate_foundation.py` by name, and nothing can silently disappear from
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
| terrain `pavilion` | A roofed gallery: levelled castle-stone floor, a wall down each long side, a roof slab over the span, both ends open and a three-wide doorway through the near wall |
| `scatter_ore(origin, size, voxel, per_thousand, salt, label)` | Deliberate ore in stone; a deterministic cell hash, so the same box always gives the same ore |
| `plant_tree(base, height, label)` | Log trunk and leaf cap |
| `place_entity(entity_id, anchor, rotation, label)` | One free fixture |
| `sign_at(cell, facing, data, owner_id)` | Places a real `sign` station and writes its board (see below) |
| `register_reset_group(name, callable)` / `reset_group(name)` | What card A's `DevelopmentMode.reset_group` calls |
| `progress()` / `pending_ops()` / `deferred_ops()` / `failures()` / `pending_signs()` | State for diagnostics |

**Signs.** `sign_at` queues a `sign` op: the station (card B,
[Signs](SIGNS.md)) is placed free at the requested cell and its board is
written through `GameSession.configure_sign`. The manifest block translates
into the sign's own record — a block naming an `item` becomes Header + Item
Grid, a title with body lines becomes the stacked **Header + Subheader + Body**
(signs card 3: the subheader is the block's `subtitle`, or its first body line
when it names none), a bare title Single Text — and `board` chooses the width:
`large` the three-cell `sign_board_large`, `wide` the two-cell `sign_board`,
`narrow` the one-cell `sign` (`ExpoBuilder.sign_entity_for`). A block that asks
for no width takes the caller's default, which is the district board for a
district's own entrance sign and the wide board for an exhibit — the campus is
read from standing distance, so the Expo's boards are big by default. A rebuild
that finds a board of another width standing in the cell takes it down and lays
the right one.

**A board is never lost to its own width.** `_run_sign` walks a fallback chain,
widest first (`SIGN_BOARD_FALLBACK`): a district board that finds no run of
three free, supported cells anywhere in the ring around its anchor is laid as a
wide board instead, and a wide board as a narrow sign, rather than failing the
request. A depot plinth is two cells wide so both of a chest board's cells
stand on stone.

**A fallback is loud, and for a district it is a failure** (card D2). The
builder records the width each request asked for beside the width it got;
`board_fallbacks()` lists every request that shrank and the run prints
`EXPO_SIGN_BOARD_FALLBACK owner=… wanted=… placed=…` as it happens. **T233
fails** when a *district* board is in that list: the campus directory is the
first thing the owner reads, and it must not quietly become the smallest board
on the campus. An exhibit's board may still fall back; it is reported, not
fatal.

**Where a district's board stands** (card D2). By default it stands on the
manifest's `entrance` cell, facing away from the district centre — the way a
visitor arriving from outside reads it. Two things used to keep the central
plaza's board at the two-cell width, and both are fixed:

1. the board was queued **before** the district's pad was levelled, so the
   only guaranteed ground under it was the avenue and there was no run of
   three supported cells. `build_district` now queues a `full` district's
   board **after** its pad (a `connect`-only district, which has nothing but
   an avenue, still queues it straight away);
2. `sign_anchor` was an exhibit-level field only. A district may now carry its
   own, resolved by `ExpoBuilder.district_sign_anchor_for(district_id)` /
   `district_sign_spot(district_id)` under exactly the rules the exhibit field
   uses. The plaza's is `[23, 1, 10]` with `sign_facing: "south"`: its board
   stands on its own levelled pad north-east of the spawn, three cells wide,
   reading back at the player standing at the Core — and its `sign.board` is
   `large`, not `wide`. **T246** is the check.

**Sign anchors.** An exhibit's board would otherwise stand at its parcel's
origin corner, which is wrong for a parcel the size of an arena. `sign_anchor`
(above) moves it: `ExpoBuilder.sign_anchor_for(exhibit_id)` resolves the field
to `{cell, facing}` and `place_exhibit` uses that instead of the corner, for a
plain exhibit, a reserved parcel and an authored `build` routine alike. The
Battlefield's arena sign is anchored `near:battlefield_fortification`, so it
stands one cell outside the curtain wall's gate reading back at it, where a
visitor walking out of their own core meets it face on, instead of tens of
cells away at the corner of the field.
The requested cell is an exhibit's corner, so it may be taken (the mine rail
runs along it) or buried (the mountain mass is solid rock): the sign then
takes the nearest free cell in the ring around it, climbing to the first air
cell with solid ground under it. A rebuild rewrites the board of the sign
already standing there rather than adding a second one. `sign_requests()` is
the full list with each request's placed instance id; `pending_signs()` is
whatever is still unfulfilled — T215 asserts it is empty. The current campus
places 126 signs, 24 of them in the Supply Depot.

**Wiring.** `DevelopmentMode.setup()` loads the manifest into `layout`, creates
the `ExpoBuilder` and registers it through card A's `set_builder` seam, so
Development New and Reset Expo both build the campus and the builder's
`district:<id>` reset groups reach `DevelopmentMode.reset_group`. `app.gd`
holds the `DevelopmentMode` node, the `--development-expo-automation=`
dispatch, the save coordinator switch in `active_saves()`, the bounds hand-off
in `_open_session` and the `on_session_ready` call.

### Streaming and the exported build

Two faults that only appeared in the exported build, where streaming is slower
than in the editor, and the rule they leave behind for every future exhibit.

**A district is built only when its own ground has settled** (`8c21abf`). The
gate once called a district done while a rail line was still arriving — T216
counted a short line. `_wait_built` now settles the builder before it declares
a district built, so a district is never reported on mid-stream.

**A far parcel waits; it does not fail** (`32dad5e`, `b788a8c`). The exported
build gave up on the CoasterCraft pad while the player still stood in the
plaza: every district's wait advanced the whole queue, so the pad spent its
requeues without its region ever streaming in, and the plaza's own wait then
reported that global failure as its own. Now `_region_loaded` checks the op's
own cell, and an op whose region has not streamed in does not spend a requeue
(`MAX_REQUEUES` is 120, and it only ends an op whose region *is* loaded — a
write that will not take is a real fault, an absent chunk is not).

**The rule for a new exhibit:** a district's build wait fails only on its own
districts' failures (`_wait_built(label, owners)` with the district ids it
owns, matched by `_failure_owned`), and an op whose region has not streamed in
waits instead of spending a retry. A parcel across the campus finishes when
someone walks to it; that is expected, not an error. Never widen a wait to the
whole campus to make a far district finish sooner, and never treat the global
`failures()` list as one district's verdict.

**A cell that is not free yet is not a cell that will never be free** (T244).
This is the fault behind the Expo gate's long-running intermittent failure.
Reproduced at the pre-fix head `34949eb`, from fresh data roots: 2 failures in
20 runs, one of each historical shape.

*T216, the rail line one cell short.* `EntityFootprintService` answers
`OCCUPIED` for two quite different things — a station already owns the cell, or
**the cell still holds a solid voxel**. An authored fixture and the carve that
opens ground for it are separate queued ops, and a parcel whose chunks have not
streamed in is deferred and taken up later, so the rail could reach its cell
before the tunnel carve cleared it. `try_place` answered `OCCUPIED`,
`_run_place` retired the op on the spot with nothing recorded (only a `strict`
op treated OCCUPIED-by-another as a collision), and the line stood short:
`rails: 106` of 107, `rail_chained: false`, **not one builder failure**. The
exported build showed the same thing six cells wide (`-87..-82`), naming
`OCCUPIED by TERRAIN(stone)` once the message was made honest.

The builder cannot tell a temporary obstruction from a permanent one from
there, so it now does what it does for ground: it waits, through
`_spend_attempt`, and reports only once the campus has no terrain work left to
lay. `_blocker_at` names what is in the way — the entity standing there, or the
voxel still filling the cell. **Rule for a new exhibit: a fixture refused on
ground its own build has not finished is a fixture that waits, never one that
is dropped, and never one that is dropped quietly.**

*T214, the tunnel floor reported missing.* The campus surface is `ground_y` =
-1, the **top** cell of the data block `y ∈ [-16, -1]`, while a walker standing
in the tunnel is at `y = 0`, the **bottom** cell of the block above it. The
floor therefore always lives in a different data block from the feet and the
head and arrives on its own schedule. The walk waited for the feet and head
cells and then read the floor through `query_cell(...).get("voxel_id", AIR)`,
so a floor block that had not arrived was read as air — authored stone reported
missing. The reproduction shows it exactly: sixteen consecutive cells at
`floor 0 / feet 0 / head 0` in a run whose ore-core sample had collapsed from
1372 cells to 140, i.e. a run where whole regions were still absent.
`_read_voxel` now returns -1 for a cell that could not be read, the walk waits
for the floor's block too, and `T214_EXPO_MOUNTAIN` carries `unread` (steps
that never became readable, counted separately and never scored as terrain) and
`floor_late` (steps that passed through the exact window the old walk broke out
on) as standing evidence.

**Two more of the same family**, found while measuring and fixed with them:

- `ExpoBuilder._run_column`'s air-only pre-read defaulted an UNLOADED cell to
  the fill voxel, so a cell whose chunk had not arrived counted as already
  solid and the column retired as fully written — a silent lost write. It now
  leaves the job unfinished instead.
- `PLACE_ATTEMPTS` / `STOCK_ATTEMPTS` were not region-gated the way
  `MAX_REQUEUES` is, so a fixture on the far side of the campus could burn its
  sixty attempts while the builder laid ground elsewhere and then be dropped
  with a failure recorded against a district nobody was waiting on.
  `_spend_attempt` holds the count while any terrain op is still queued or
  parked anywhere.

**And one invariant worth having:** every authored `place` op claims its anchor
when it is queued, and `_sign_stand` skips a claimed cell whether or not the
fixture has arrived yet. A board never stands on a cell the manifest gave to a
fixture. All 137 sign requests still place.

**What the world itself is trusted for.** `WorldAdapter.set_cell` is honest: it
refuses a write to an unloaded cell and reads the cell back before it reports
success, so a write is never issued and lost at the moment it is made. What no
project code can assert away is loss *after* the fact, in the engine's own
streaming — a modified block evicted and reloaded from the generator rather
than from the SQLite stream. The mitigation for that is verification, not
faith: `T244_EXPO_BUILD_VERIFIED` samples one authored cell in
`ExpoBuilder.AUDIT_SAMPLE` (1500) as the builder writes, drops any cell the
running game later changes, and after the whole campus has been built, walked
and long since evicted it stands on each sample in turn and reads it back,
naming the cell, the district, the authored value and the value found. It reads
back ~325 cells across 15 districts, and has never found a mismatch or an
unreadable cell. If the Expo gate ever fails on authored terrain again, T244's
evidence is what says whether the world lost a write or the gate misread one.

---

## 4. Districts — the western campus (§7)

Spawn is the plaza at `(0.5, 2.0, 40.5)`; north is -z, west is -x.

| District | Box (x, z) | State |
|---|---|---|
| Central Plaza | -16..15, 26..53 | Built: level castle-stone plaza, development Core of Power, orientation sign listing every route, avenues out to every district, the Reset Expo access parcel reserved for card A |
| Supply Depot | -48..15, 8..21 | Built: 22 generated supply chests in two rows, eight units of every visible item, each under its own Header + Item Grid board, plus the two reserved future-category stands (see **The Supply Depot** below) |
| Reserved — future districts | 24..47, 26..53 | Deliberately empty and signed, in full view east of the plaza |
| Day One | -60..-17, 56..95 | The eleven-step chain tree -> log -> planks -> sticks -> workbench -> wood pick -> stone -> stone pick -> furnace -> iron -> iron pick, each on its own signed parcel, read along +x and then down the rows |
| Equipment | -9..24, 60..93 | Wood/stone/iron pick, wood axe, iron sword as catalog booths, a functional Sign booth (a real writable sign beside its label), and the empty signed future-armour parcel |
| Resources | -88..-49, 8..47 | Forest patch, stepped quarry, coal seam, surface iron and gold outcrops |
| Mining Mountain | -124..-53, -68..3 | A 72x72 voxel mass rising to y 23, a deliberately authored deep ore core (coal, iron, gold), a 9-wide 7-high tunnel lit end to end by post lanterns with a 68-cell rail line inside (it now runs to the district edge so card D's line continues it), a manual-mining chamber and a separate automated-mining chamber with a Miner and an Ore Bin on a deep ore face |
| Industry | -52..15, -44..-5 | The working chain, built by card D (below) |
| Lighting and Utilities | -8..35, 96..127 | The roofed light walk, built by card D (below) |
| Construction Yard, Defense Range, Battlefield, CoasterCraft | see the manifest | Parcels, entrances, corridors and avenues reserved; cards E and F build them |

The Mining Mountain's east mouth faces the campus and its rail line runs out to
the district edge, where the Industry district (flush against it) picks the
same line up.

---

## 5. Districts — Industry / Logistics and Lighting + Utilities (§7, card D)

Two districts, both built from the manifest alone: no new gameplay, no second
implementation of anything — the chain is the shipped services composed in
authored positions (`placements`).

### Industry — one chain, walked west to east

The district is flush against the Mining Mountain (`-52..15, -44..-5`), so the
**one rail line** is literally one line: the mountain's 68 cells (x -120..-53)
and the yard's 39 (x -52..-14) chain cell by cell along `z -34` at `y 0`. The
stages stand along it in reading order, each its own signed exhibit:

| Exhibit | What stands there |
|---|---|
| `industry_ore_face` **1 ORE > MINER > ORE BIN** | An authored iron-and-coal face at the mountain foot, a **Miner** two cells off it and an **Ore Bin** beside the miner *and* beside the track |
| `industry_rail` **2 MINE CART ON RAIL** | The yard's rail cells and a **Mine Cart** on them. The cart loads at the bin, rides east and unloads at the dock |
| `industry_warehouse` **3 WAREHOUSE > FOUNDRY** | The **Warehouse** beside the track and a **Foundry** touching it: the foundry pulls the ore and the coal out of the warehouse and pushes the ingots back |
| `industry_ingots` **4 INGOTS** | A catalog plinth for Iron and Gold Ingot, the chain's output |
| `industry_net_chest` / `_chain` / `_foundry` / `_furnace` | The four storage-network demonstrations, one signed booth each: Warehouse + Chest, two Warehouses daisy-chained, a Foundry touching storage, a Furnace touching storage |
| `industry_expansion` | The reserved expansion edge, levelled and signed, kept clear |

**Every container and every foundry slot is empty as built** (handoff §7): the
builder stocks nothing, so the owner watches the bin fill, the cart carry and
the ingots arrive. The avenue from the plaza enters at `(-12, 0, -5)` and the
whole southern half of the district is open ground between it and the booths.

### Lighting and Utilities — the light walk

One `pavilion`: a castle-stone gallery 40 x 12, walls down both long sides, a
roof over the whole span, both ends open and a doorway on the plaza side. Six
alcoves nested inside it hold **Torch, Wall Lantern, Post Lantern, Campfire,
Blue Light Block, Red Light Block** side by side, each on its own signed
parcel; the Wall Lantern hangs on the gallery wall (the placement is beside it,
so the ordinary wall-mount rule takes over). The shade is the whole point — the
differences read at 09:00 as well as at midnight. No weather and no new time
system: World Settings still own the clock.

---

## 6. Districts — Construction Yard, Defense Range and Battlefield (§7, §14, §15)

The eastern half of the campus. All three are `prepare: "full"`; the
Battlefield's own district terrain is `natural`, because the arena it needs is
one authored parcel inside it rather than a pad the size of the district.

### Composite exhibits

A weapon is not demonstrable on its own: it needs the mount its sheet allows,
its munition, the storage that reloads it and something to shoot at. These
districts therefore use **composite terrain kinds** — `wall_demo`,
`blueprint_demo`, `castle_demo`, `siege_booth`, `field`, `camp`, `battery`,
`fortification`, `magazine`. A composite exhibit's declared `entities` are
placed by its own terrain builder (`ExpoBuilder.COMPOSITE_TERRAIN`), not one
per parcel by `_build_entities`, so the manifest still owns **what** is shown
and the builder owns only **how** it stands. Two builder helpers came with
them: `stock_container(cell, items, per_item)` fills an authored chest, and
`queue_action(label, callable)` runs one step in its turn in the build order.

| District | Box (x, z) | What stands there |
|---|---|---|
| Construction Yard | 28..71, -44..-5 | Castle Stone, Stone Stair, Wall-walk Slab, Parapet Merlon, Tower Platform, Gate Frame, **Gate** and Wood Barricade each on their own signed booth; then the same pieces assembled — a drag-built run of castle stone with a wall-walk deck and merlons, the blueprint stack FOUNDATION 4 / TOWER SEGMENT 4 / CAP 4 stamped as ordinary voxels and recorded as stamps, the **Wall Kit** exhibit showing what one stamp leaves behind (base course, wall-walk, merlons and a stair up at each end), and a small castle with a curtain wall, a gate, a stair and a tower platform; a signed, empty parcel for future castle technology |
| Defense Range | 56..110, 12..51 | Seven booths in a row, each 28 cells deep: Ballista and both Turret Catapults on tower platforms, Catapult and Cannon on the ground, Kettle and the **Rail Turret** each on a rail along a wall top; each with its munition chest touching it, a castle-stone target at the far end of its own lane and a sign naming the weapon and its ammunition; a signed, empty parcel for future machines |
| Battlefield | 112..183, -16..55 | One `field` parcel of open dirt with everything else nested in it: the enemy core and its muster ground to the north, the west and east batteries, the curtain wall with its tower and its **working gate**, hung shut, the Core of Power, the magazine and the control pedestal to the south, and signed empty parcels for future enemy kinds and for allied archers and soldiers |

### The Battlefield control station

`battlefield_control` is an entity with no item: not craftable, not in the
recipe book, placed only by the fixture. Right-clicking it opens a live
two-button panel (`AppState.BATTLEFIELD`; the world keeps running behind it,
as it does for the sign editor).

- **START ATTACK** — `CraftAndDefendApp.battlefield_start_attack()` calls
  `CoreDefenseService.start_prototype` with six attackers, two brutes, two
  trolls and a spawn distance of 28. No new wave code: this is the ordinary
  drill. The Expo has **two** Cores of Power standing, so the drill gained one
  option — `core_station_id` — and the control station names the core inside
  the Battlefield's reset boundary. Without it the first placed core wins,
  exactly as before.
- **RESET BATTLEFIELD** — `battlefield_reset()` calls
  `DevelopmentMode.reset_group(session, "battlefield")`.

Development mode has no ambient pressure, so this pedestal is the only thing
in the whole Expo that starts a fight.

### The reset-group pattern — `ExpoResetService`

Step 3 of a reset (`_restore_standing`) puts everything still standing inside
the boundary back to the state its fixture opens in: full integrity, a siege
weapon's opening clip and — since [the defence sets card](DEFENSE_SETS.md) —
every **gate hung shut again**. So RESET BATTLEFIELD restores the curtain
wall's gate closed, whatever the last fight left it as.

`game/scripts/expo/expo_reset_service.gd` is the §14 seam's implementation and
is **not** Battlefield-specific. Any exhibit may name a `reset_group` in the
manifest; every named group becomes a **scenario** with its own boundary, and
`ExpoBuilder.build_district` registers each one so it reaches
`DevelopmentMode.reset_group`. A group may share its district's name — the
district's own group is `district:<id>`, which rebuilds the avenue and the
whole pad with it.

A scenario's **boundary** is the union of its parcels (plus the pad under them
and the cleared headroom over them). Resetting one is three steps:

1. **Live state inside the boundary stops.** A core-defense drill whose arena
   centre lies in the box is cleared through the ordinary
   `clear_for_other_mode()` — attackers removed, drill back to idle. A drill
   anywhere else in the Expo is left running. This step is immediate.
2. **The fixture is rebuilt.** Each of the group's exhibits is re-placed
   through `ExpoBuilder.place_exhibit`, in manifest order, so its terrain is
   levelled again and anything destroyed is placed again; a fixture still
   standing reports `OCCUPIED` and is kept. The Battlefield's `field` parcel is
   first in the manifest, so the arena floor is restored before everything
   standing on it.
3. **What survived is restored.** Every station inside the boundary goes back
   to full integrity and every siege weapon to its opening clip, through two
   new free calls on `WorkstationService` — `restore_integrity(id)` and
   `restore_siege_ammo(id)` (authored fixture restore: no item cost, because a
   scenario rebuilds what it owns rather than being repaired by hand). The
   ammunition chests are refilled by their own exhibit builders in step 2.

Steps 2 and 3 are queued on the builder and drained a budget per frame like
any other build, so a reset never freezes the frame. To give a future scenario
its own boundary, name a new `reset_group` on its exhibits — nothing else.

**Call made:** `_build_fortification` leaves the gateway of the curtain wall
open. A wave that cannot walk in stands and chews castle stone instead of
showing the routing the Battlefield exists to show; the Wood Barricades in
front of the gate are what the wave meets first.

---
## 6b. District — the Trap Range (traps card)

`trap_range` (x 56..96, z 60..86, east of the Defense Range's corridor), one
`scenario` exhibit and one reserved parcel. Its `trap_range` composite terrain
authors a walled lane with three rows of three Spike Traps in the floor, the
Core of Power at the far end and a `battlefield_control` pedestal beside the
mouth; the reserved parcel is signed for the four traps that do not exist yet.

The pedestal is the Battlefield's entity, and since this card the control panel
follows whichever pedestal was opened: it resolves the reset group containing
that pedestal (`CraftAndDefendApp.control_group`) and starts that group's wave
at that group's Core, and RESET restores only that group. Called without a
pedestal — as the gates do — it is still the Battlefield.

**Call made:** the lane stands east of the CoasterCraft avenue. An avenue is
levelled when its own district is built, and CoasterCraft is built after the
Trap Range, so a lane under that avenue had its walls cleared away again.

---
## 6c. District — the Frontier (encampments card)

`frontier` (x 104..160, z 60..86, east of the Trap Range's corridor), one
`scenario` exhibit and one reserved parcel. Its `frontier_camp` composite
terrain authors a levelled dirt clearing with a camp site in the middle, a
twelve-piece player **rail line** eight cells away — inside the camp's sight
radius — and a `battlefield_control` pedestal beside the entrance. The reserved
parcel is signed for the next ambient-pressure card.

The encampment is **registered, not lit**. `ExpoBuilder` calls
`EncampmentService.register_camp` for it and nothing else: no fire burns, no
garrison exists and nothing patrols until the pedestal's **START ENCAMPMENT**,
which is what keeps Development mode free of ambient pressure (T211). The same
pedestal entity and the same panel serve it — `control_group()` resolves to
`frontier`, so the panel reads FRONTIER CONTROL with START ENCAMPMENT and
RESET FRONTIER — and `ExpoResetService` now stops every camp inside a reset
group's boundary before rebuilding its fixture. See [Encampments](ENCAMPMENTS.md).

---

## 7. Districts — CoasterCraft: the component gallery and the Grand Coaster (§7, card F)

The south-east reserve (`coastercraft`, origin `(64, -1, 88)`, size
`(88, 24, 96)` — the largest parcel on the campus) is built in full. Its
district is now `prepare: "full"` with `terrain: "level"`: the whole park is
one levelled pad, so a booth never stands on a cliff the generator happened
to raise there (the parcel was `natural` while nothing stood on it).

**The manifest's `build` field.** A track element cannot be described by an
entity list — it is a curve sampled into cells with recorded joints. An
exhibit may therefore name an authored routine, `"build": "<name>"`, and that
routine owns its whole parcel: its levelling, its terrain, its fixtures and
where its sign stands (`ExpoBuilder.place_exhibit` skips the generic terrain
and entity paths for it). The routines live in **`game/scripts/expo/expo_coaster.gd`
(`ExpoCoaster`)**, one per exhibit, and are pure composition: every piece
comes from a real lay tool's layout — `CoasterRails.helix_layout`,
`climb_layout`, `curve_layout`, `bend_layout`, `cross_layout`, all over
`TrackCurve` — and is placed by the new seam
**`ExpoBuilder.place_track(pieces, label)`**, which writes each piece's curve,
its `t0`/`t1` range and its recorded joints exactly as
`InteractionService._commit_curve_tool` does once the items are paid. Nothing
is hand-placed as blocks, so the auto-shaping, the banking, the flush ends and
the trestle trusses all apply. A track op is **strict**: a cell already taken
by something else is a build failure the gate sees (a rebuild finding its own
piece standing is not).

### Component gallery

Eleven booths on their own parcels, each levelled, signed and read along +x:
an **arrival plaza** (paved, two post lanterns, the routes on its board), then
**Rail** (a straight run), **Rail Slope** (rails, the slope, rails on the bank
one level up), **Rail Loop** (a diameter-5 true loop between its entry and
exit rails), **Rail Switch** (the default 4 × 1 smooth lane switcher),
**Rail Cross** (the default 8 × 2 crossing with a rail on each of its four
ends), **Rail Curve** (a banked 90° arc of radius 3), **Rail Climb** (length 8,
rise 4, onto its landing), **Mine Cart**, **Coaster Car** (parked, boardable)
and the **CoasterCraft Shop**, placed and usable — right-click opens its own
recipe book.

### Grand Demonstration Coaster

One closed, rideable circuit on an 80 × 26 parcel. In plan it is a **figure
eight**: the boarding lane runs east past the **lift hill** (Climb, +6), a
**crest** (the same tool at rise 0, so the track flies on its trusses), the
**drop** (Climb, −6) and the **true loop** (Rail Loop, diameter 8, which lands
one lane over); a **Rail Switch** shifts it back onto its lane; the **Rail
Cross** (16 long, 6 lanes) carries it onto the return lane; a **180° Rail
Curve** turns it back west onto the boarding lane, where it rides the *other*
track of the same crossing — both tracks of the crossing are ridden on one
lap, so it is a real crossing and not a spur — and a second 180° curve at the
west end returns it to the station. The station is a castle-stone platform
beside the boarding rails with the ride's sign on it and a **Coaster Car**
parked ready to board (Shift on it, 1–9 for speed): the ordinary
`CoasterCartService` / `CoasterRide` path, with no demo vehicle of its own.
The two U-turn radii set the lane spacing (radius 3 → the legs six lanes
apart), so the whole shape is one constant away from being widened.

**Waiting for one district.** The park is 200 cells from the plaza — further
than the terrain streams — so its ops are parked until someone walks there,
and a diagnostic can no longer wait on the whole queue from the spawn. The
builder answers `pending_for(owners)` (district and exhibit ids; every op's
label is `<what>:<owner>`), and the suite's `_wait_built(label, owners)` waits
on the district it is standing in. Passing no owners keeps the old
whole-campus wait.

Calls made by this card: the park is levelled rather than laid over natural
terrain (above); the elevation comes from the authored lift hill, crest and
loop rather than from a generated hill, because a track that must pass its own
gate cannot depend on what the noise put there; and the crossing is sized
`6` lanes (the tool's maximum) to match the U-turns' lane spacing.

## 8. Districts — the Supply Depot (§8, §9)

The district north of the plaza, one straight walk down the avenue from the
spawn: **eight units of every item the game has today**, so the owner can test
anything without first crafting it. Nothing in it is hand-listed — the chests,
their contents and their boards are generated from the content registry, so a
new item joins the depot by being registered and classified and by nothing
else.

| | |
|---|---|
| Generator | `game/scripts/expo/supply_depot.gd` (`SupplyDepot`), pure data in / data out |
| Placement | `ExpoBuilder._build_supply_depot`, reached through the exhibit's `terrain: "supply_depot"` |
| Parcel | the `supply_depot_stock` exhibit of the `supply_depot` district |
| Settings | the manifest's `supply` block: `units_per_item`, `types_per_chest`, `slots_per_chest`, `hidden_whitelist` |
| Python oracle | `supply_catalog()` in `tools/validate_foundation.py` — change one and you must change the other |
| Checks | **T223** (`--development-expo-automation=gate`), **T223V** (`=visual`), `validate_foundation.py`, `SupplyDepotTests` in `tests/test_foundation.py` |

### The rules

- **Every non-hidden item of the registry is stocked, exactly once, eight
  units of it.** A hidden id (`enemy_core`) stays out unless the manifest's
  `hidden_whitelist` names it as a development asset.
- **One category per chest**, because the chest's board is that category's
  sign. The fourteen categories and the item → category map live in
  `game/scripts/ui/item_categories.gd` — the one source both the sign editor's
  item picker and the depot read.
- **At most eight distinct types in a chest, filling at most eight of its nine
  slots**, so the ninth stays visibly empty. Eight units of something that does
  not stack (a pick, the Core) take eight slots, so such a chest carries that
  one type alone. That is why the rule is *at most* eight types.
- **Deterministic order**: category order, then registry order inside a
  category. A chest fills in that order until the next item would exceed the
  type or slot budget, then a new chest starts. Contents never shuffle between
  runs, and a chest is numbered `2/6` on its board when its category needs
  several.
- **Future Food and Future Armour** are reserved signage, on the same stands
  with no chest under them. No fake items, ever.
- The depot is **idempotent**: Reset Expo (or a `district:supply_depot` reset)
  re-runs the same build, which tops a chest the owner emptied back up and
  leaves a full one alone.

### What it looks like on the ground

Each **stand** is a two-cell stone plinth with the chest in front of it and the
sign on top, so the board stands above the chest and reads back at a visitor
walking in from the plaza. Stands run along +x, four cells apart; rows run
back from the entrance, four cells apart (plinth, chest, two cells of aisle).
The parcel is 58 x 8, which holds 28 stands; the current catalog uses 24 (22
chests and the two reserved boards). When the catalog outgrows the parcel,
`validate_foundation.py` says so by name and the district widens into its
expansion corridor.

### How a new item joins the depot

1. Register it in `contracts/content.json` as usual.
2. Give it a category in `ItemCategories.ITEM_CATEGORY`. This is the only
   manual step, and skipping it is a **failure**, not a default: an item with
   no entry is `unassigned`, which fails `validate_foundation.py` naming the
   item and the file, and which T223 proves the classifier reports rather than
   bucketing.
3. Run `python tools/validate_foundation.py`, `python -m unittest discover -s
   tests` and `--development-expo-automation=gate`. The depot rebuilds itself;
   no coordinates and no item lists change anywhere.

`ItemCategories` has two readings of the same map on purpose:
`category_of` falls back to the item's content category so the sign editor's
picker never shows a gap, while `classify` is explicit-only so the depot can
report what nobody has classified.

---

## 9. The Directory, What's new and the test notes (card D1)

The owner's own testing tool, and Development mode only: *"I want to be able to
search for anything in the expo and teleport to it … You could keep a log of
all the elements and comments and what is verified, working, broken,
approved."*

**K opens it** ([Keybinds](KEYBINDS.md)) in a running Development world. It is
a raw key like V and M, not an InputMap action, and outside Development mode it
only says `The Expo Directory (K) is a Development mode tool.` K or Escape
closes it. It is a **live panel** in the game's existing panel language - the
same `_full_panel` / card / icon-tile vocabulary as the sign editor - so the
world keeps running behind it and the live-menu contract is untouched.

### 1. The list

`game/scripts/expo/expo_directory.gd` (`ExpoDirectory`) turns the solved
layout into one row per district and per exhibit; it is pure data in, data out,
so the gate reads exactly what the panel draws. A row carries `id`, `kind`,
`name` (the sign's title), `district`, the sign's body as its **description**
(this is how the owner learns what a Wall Kit is without hunting for it), an
`icon_item` (the sign's item, else the first item, else the first entity, drawn
through `ItemIconCatalog` so a row looks like the rest of the game), its
`ItemCategories` category, its `added_in` stamp and its note `status` and
newest `remark`.

**Search** matches a lowercased substring of everything above - ids, display
names, the sign's words, the district - and filters live as it is typed.
**Filters**: district, category, **What's new** and status, each a toggle;
`Clear filters` resets them.

**Paged, not capped** (card D2). The list draws 60 rows at a time and the
**◀ Previous / Next ▶** pager under it reaches the rest, so every entry of the
campus is reachable without first guessing a search term. The count line reads
`showing 1-60 of 110` (and, when a filter is on, `(of 110 entries)` after it),
with `PAGE 1 OF 2` between the two buttons; the buttons grey out at the ends.
Changing the search or any filter goes back to page 1, and a page that a
narrower filter has emptied clamps to the last page that still exists.
`directory_page_ids()`, `directory_page_count()` and `directory_page_summary()`
are the seam **T247** walks the whole list through.

### 2. Teleport

A row's **Teleport** takes the player to `ExpoBuilder.approach_for(id)`: the
middle of the edge the parcel's `orientation` says it is read from, two cells
outside it, looking back at the parcel's centre - the same `entrance`
resolution the boards use, so the owner arrives where the sign is read rather
than inside the exhibit. A district's row uses the manifest's own `entrance`.

The streaming rules above apply: a far district's ground is simply **not there
yet**. The teleport therefore parks the player over the column, waits for that
column to report `LOADED`, then finds the settled surface and stands the player
on it. If the chunk never arrives the panel says so and the player is not
dropped into unloaded ground.

### 3. What's new

An exhibit may carry an optional **`added_in`** - an ISO date (`"2026-09-24"`)
or a zero-padded version string; stamps are compared as strings, so the newest
one wins. **Every card that adds an exhibit should set it.** The What's new
filter shows the exhibits stamped newer than the last list the owner dismissed
(closing the panel with the filter on records that), and the newest stamp
itself when nothing is newer, so it is never silently empty. Backfilled for the
exhibits added since the Expo shipped: `cy_gate`, `cy_wall_kit` and
`dr_rail_turret` (the defence sets card; signs v2 added no exhibit of its own).

### 4. Test notes and the status log

`game/scripts/expo/expo_notes.gd` (`ExpoNotes`) keeps the notes per **subject
id** - an exhibit id, or a placed station's instance id:

- a note is a **remark plus a status** (`untested | verified | working |
  broken | approved`), timestamped and **appended**: the log is a history, not
  one overwritten line. `Set status only` changes the status and keeps the
  newest remark, so a verdict never costs a retyped remark;
- the Directory lists and filters by status, shows the newest remark on the
  row and its status as a badge;
- a **station** gets its own notes through the `Notes` button its panel shows
  in Development mode (the station modal and the sign editor); it closes that
  panel and opens the Directory's notes editor on that instance id;
- notes live in the **development save's own namespace**:
  `GameSession.snapshot()` writes `expo_notes` only while `development` is
  true, so they survive save / load and a normal or CoasterCraft save carries
  no such key at all (T236 proves both);
- and they are **written through to disk the moment they are saved** (card
  D2), so a crash or a Quit-without-save cannot take a finding with it.

**The journal.** `<data root>/development/expo_notes.json` is the notes' own
store, beside the development save and outside the world checkpoint — a
checkpoint is megabytes of voxels written when the owner says so, the journal
is a few kilobytes written on every change. `ExpoNotes.flush()` writes it to a
`.tmp` file and moves that over the real one, so a crash mid-write leaves
either the old journal or the temporary file and `load_store()` reads both; a
malformed journal is ignored rather than fatal.

`DevelopmentMode.bind_notes(session)` binds it at Development start, **after**
the world snapshot has been restored, and **merges** rather than replaces:
neither side is a subset of the other after a Reset Expo, so the store ends up
holding the union. An entry is the same entry when its timestamp, status and
remark all match, which is what makes reading the journal twice a no-op. The
panel says `Written to disk — it survives a crash.` when a note is saved, and
says so loudly when it could not be. **T245** is the check, and
`--expo-notes-export` reads the journal on top of the checkpoint, so a handoff
table can be written from notes no world save ever saw.

**Export.** The panel's `Export Notes`, and the headless switch
`--expo-notes-export` (which reads the development checkpoint and opens no
world at all), write **`artifacts/expo_notes.md`**: a table of subject, status,
newest remark and date, with every historical remark underneath. From an
exported build, where `res://..` is inside the package, it lands in
`<data root>/artifacts/` instead; the path is printed as
`EXPO_NOTES_EXPORT <path> subjects=<n>`.

### 5. Checks

**T234_DIRECTORY_SEARCH**, **T235_DIRECTORY_TELEPORT**, **T236_EXPO_NOTES**,
**T245_NOTES_DURABLE** and **T247_DIRECTORY_PAGING** in
`--development-expo-automation=gate`; **T234V_DIRECTORY_VIEW**
(`development-expo-directory.png`) and **T247V_DIRECTORY_PAGING_VIEW**
(`development-expo-directory-page2.png`, the last page with its count line and
pager) in `=visual`.

### 6. Calls made by this card

- **K, not F**: F is `strafe_right` in the ESDF layout.
- A row's **Teleport** button is the selection, beside its **Notes** button;
  the row itself is not one big button, because two verbs share it.
- A **station's** Notes button lives in the station's own panel header and
  hands over to the Directory's notes editor rather than growing a second
  editor of its own.
- The manifest's mojibaked em dashes and middle dot (`â€”`, `Â·`, which
  predate this card) are repaired to `-` and `·` in the same pass, because the
  Directory is the first thing to render a district's `name`.

---

## 10. Growth rule — adding an exhibit for a new feature (§6, handoff section 19)

1. Add the item/entity to `contracts/content.json` as usual.
2. Add an exhibit record to the district that owns it in
   `contracts/development_expo.json` — id, kind, footprint, clearance,
   orientation, the referenced ids, terrain, connections, a sign and an
   `added_in` stamp so it shows in the Directory's **What's new** — or, if it
   is not ready to be shown, add its id to `deferred_items` against the card
   that will. Nothing else in the file changes: the layout engine re-packs the
   district and grows into its expansion corridor.
3. Copy the file to `game/data/development_expo.json`.
4. Run `python tools/validate_foundation.py` and
   `python -m unittest discover -s tests`, then
   `--development-expo-automation=gate`.

If the district is full, widen it (and its corridor) in the manifest or claim
the reserved parcel — the validator says which exhibit did not fit. The
defence sets card is the worked example: the Defense Range grew from 48 to 55
cells wide to take the Rail Turret booth, and its expansion corridor moved to
the range's south side.

---

## 11. Checks

| Gate | Covers |
| --- | --- |
| `--f3-automation=phase1` | **T210** lost-Core Continue: a save is written with the defended core destroyed and a chest left over dug-away ground; the menu reports Game Over — Start New with Development Start still reachable and the file readable; Continue through the app's own path finishes inside a bounded number of frames with the drill restored as lost, no re-created core and the chest back in place |
| `--development-check` | the whole Development Start round trip: the submenu, New, `DEVELOPMENT DATA_ROOT <path>` under `<data root>/development`, the runtime rules (no waves after three seconds of play, no enemy core, hidden drill line, daytime clock with the cycle running, no creative top-up), the builder and reset-group seams, the pause menu without drills, the Reset Expo confirmation and rebuild, Save and Exit and Continue — and **T211_DEVELOPMENT_MODE_ISOLATION**: a marker written into a normal Slot A checkpoint reads back unchanged, with the same revision, after a Development New and a Reset Expo, and the CoasterCraft namespace is untouched |

`game/scripts/diagnostics/development_expo_automation.gd`, dispatched as
`--development-expo-automation=gate` (headless) and `=visual` (windowed,
renders the plaza, the tunnel, the coaster gallery and the showpiece). This
suite is the milestone's home; later cards add their records to it.

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
  whole way (the tunnel is longer than one streaming region, so the gate walks
  the player down it cell by cell rather than reading it from the mouth), the
  rail line chains cell by cell and the automated-mining Miner and Ore Bin
  stand.
- **T215_EXPO_SIGNS_PLACED** — after a Development New every district and
  exhibit sign request in the manifest is a real placed `sign` station whose
  `sign_data` carries the manifest's title, lines and item; nothing is left
  unfulfilled in the builder's sign queue. The plaza orientation sign and one
  district sign are read back field by field.
- **T215V_SIGN_VIEW** (`=visual`) — `development-expo-sign.png`, the plaza's
  orientation board framed from in front of it, close enough to read.
- **T225_SIGN_ANCHORS** — the Battlefield's arena sign stands within four cells
  of the gate its `sign_anchor` names (it used to stand at the corner of the
  whole field), the plaza's orientation board and the Supply Depot's chest
  boards are the two-cell wide board, a wide board owns both of its cells, and
  nothing is left in the sign queue.
- **T216_EXPO_INDUSTRY** — the chain stands (miner, ore bin, the rail chaining
  unbroken from the mountain's first cell to the yard's last, the cart, the
  warehouse, the foundry), every container and foundry slot is empty as built,
  and the chain **runs**: the gate advances the miner, the cart service and the
  foundry itself and asserts ore in the bin, ore in the warehouse and an ingot
  back in storage. The four storage-network booths are read through
  `StorageNetwork.network_of` and must pool exactly as their signs say. The
  gate reads the whole fixture with the simulation paused, so "empty as built"
  is a fact about the fixture and not about how fast the run went; it hands the
  simulation back before the live scenarios (T219's reload, T220's drill,
  T222's ride) that need the services running.
- **T217_EXPO_LIGHTING** — all six light entities stand in the gallery on their
  own signed parcels, each carries an `OmniLight3D` with the colour, range and
  a positive energy its content sheet declares, and each has the gallery roof
  over it.
- **T216V_INDUSTRY_VIEW** / **T217V_LIGHTING_VIEW** (`=visual`) —
  `development-expo-industry.png` (the ore face, the miner and bin, the line
  east to the yard) and `development-expo-lighting.png` (the shaded walk with
  the six sources receding).
- **T218_EXPO_CONSTRUCTION** — every castle piece stands on its own signed
  booth; the drag-built wall carries its deck and merlons; the blueprint stack
  is stamped and recorded in `InteractionService.stamps_snapshot()`; the small
  castle has its gate frame, its stair and its tower platform; the future
  parcel is signed and empty.
- **T219_EXPO_DEFENSE_RANGE** — each of the six booths has the mount its sheet
  allows, its munition in a container the real `StorageNetwork` reports beside
  it, a target down its lane and a sign; draining the Cannon back to its
  opening clip is topped up to capacity again by the unmodified siege reload,
  and the munition leaves the chest.
- **T220_EXPO_BATTLEFIELD** — START ATTACK musters a mixed wave at the
  Battlefield's own Core, its distance to that Core shrinks and a player siege
  weapon engages; RESET BATTLEFIELD then clears the fight and restores both
  cores, the batteries, their ammunition and the magazine, while damage done to
  the plaza Core and to a Defense Range weapon stays exactly as it was; a
  second START ATTACK straight afterwards is accepted.
- **T218V / T219V / T220V** (`=visual`) — `development-expo-construction.png`,
  `development-expo-range.png` and `development-expo-battlefield.png`, the last
  one taken mid-attack.
- **T221_EXPO_COASTER_GALLERY** (card F) — every gallery booth stands in its
  own parcel with its placed sign, each track specimen carrying the curve its
  real lay tool writes, and the CoasterCraft Shop opens its own recipe book.
- **T222_EXPO_GRAND_COASTER** (card F) — the showpiece holds a piece of every
  track family (straight, climb, curve, true loop, lane switcher, crossing)
  read from the records' curves; its 208 pieces are one connected chain
  through the station and nothing else; and the parked Coaster Car boards
  through `CoasterRide`, rides every cell of the circuit, comes home, and
  never hangs upside down outside the loop.
- **T221V_COASTER_GALLERY_VIEW** / **T222V_GRAND_COASTER_VIEW** (`=visual`) —
  `development-expo-coaster-gallery.png` and `development-expo-coaster.png`.
- **T223_SUPPLY_DEPOT** — after a Development New every non-hidden visible item
  of the registry is stocked exactly once, eight units of it, in a chest of at
  most eight distinct types that still has a free slot; every chest's board is
  a Header + Item Grid whose ids are exactly the chest's, in the chest's order;
  the walk from the spawn down the avenue and along the depot's front aisle is
  unobstructed, floored and clear at head height; and a registry carrying an
  unclassified item reports it as `unassigned` instead of bucketing it.
- **T234_DIRECTORY_SEARCH** (card D1) — K opens the Directory in Development
  mode and is refused in the ordinary game; the owner's own search ("wall
  kit") answers the wall-kit exhibit with the description its sign carries and
  the panel draws exactly those rows; the district and category filters narrow
  the list to that district / that category only; and What's new answers the
  manifest's newest stamp and nothing older.
- **T235_DIRECTORY_TELEPORT** — selecting an exhibit stands the player on
  loaded, solid ground with head room within six cells of its parcel, looking
  at it, for three districts: the Construction Yard, Lighting, and the far
  CoasterCraft park whose terrain has to stream in first.
- **T245_NOTES_DURABLE** (card D2) — a note saved in the panel is in the
  journal on disk before anything else happens, with **no** development
  checkpoint written; a store reopened the way the next Development start
  reopens it still carries it; reading the journal twice never duplicates it;
  the markdown export carries it; and an ordinary game writes neither an
  `expo_notes` key nor a journal of its own.
- **T246_PLAZA_BOARD** (card D2) — the central plaza's orientation board is
  the three-cell District Board, standing within four cells of the
  district-level `sign_anchor` the manifest gives it and owning all three of
  its cells, and no district board on the campus has fallen back to a
  narrower width.
- **T247_DIRECTORY_PAGING** (card D2) — paging the unfiltered Directory from
  the first page to the last reaches every entry exactly once (the union is
  the whole entry list), the drawn row count matches the page, and the count
  line reads the right `showing a-b of n` on every page.
- **T236_EXPO_NOTES** — a remark and a status are stored per subject and
  appended as a history (a status change keeps the newest remark); the row in
  the panel shows both; the notes go through the development save's own
  namespace and back out of a real checkpoint on disk; the same session asked
  for an ordinary game's snapshot writes no `expo_notes` key at all; and the
  export writes the table with every historical remark under it.
- **T234V_DIRECTORY_VIEW** (`=visual`) — `development-expo-directory.png`, the
  Directory open over the running world with a search typed into it.
- **T223V_SUPPLY_VIEW** (`=visual`) — `development-expo-supply.png`, a supply
  chest framed from the aisle with its board above it, close enough to read the
  4 x 2 grid against the chest.

The exported-game runner for all of this is
`tools\runners\TEST_DEVELOPMENT_EXPO.cmd` (gate then visual, four screenshots,
prints `DEVELOPMENT EXPO TEST: PASS|FAIL`); `tools\runners\RUN_ALL.cmd`
includes it in the sweep.
