# Development Expo

The playable exhibition of the game's systems that opens from Development
Start. The commission is [the Development Expo handoff](DEVELOPMENT_EXPO_HANDOFF.md);
this file is the implementation record. Sections are added per card — the
manifest, layout engine, builder and the western half of the campus (card C)
are below; the entry/mode, signs, industry, defense, coaster and supply cards
append their own.

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
| `sign_at(cell, facing, data)` | The sign card's `configure_sign` when present (see below) |
| `register_reset_group(name, callable)` / `reset_group(name)` | What card A's `DevelopmentMode.reset_group` calls |
| `progress()` / `pending_ops()` / `deferred_ops()` / `failures()` / `pending_signs()` | State for diagnostics |

**Sign adapter.** The sign card (card B) owns `configure_sign`. Until it lands,
`sign_at` records the request (`pending_signs()`), prints one warning and
carries on; the layout does not change when the real service arrives, because
the cells and the sign data are already decided here. 44 sign requests are
recorded by the current campus.

**`DevelopmentMode` stub.** `game/scripts/app/development_mode.gd` is a card C
stub, clearly marked as such: the save namespace `<data root>/development/`,
the Expo-sized `world_bounds()`, `set_builder()` and `reset_group()`, plus
`--development` on the command line to open a fresh Expo world. Card A's
version replaces it and keeps those four seams. `app.gd` holds the
`DevelopmentMode` node, the `--development-expo-automation=` dispatch, the save
coordinator switch in `active_saves()`, the bounds hand-off in `_open_session`
and the `on_session_ready` call.

---

## 4. The campus this card built

Spawn is the plaza at `(0.5, 2.0, 40.5)`; north is -z, west is -x.

| District | Box (x, z) | State |
|---|---|---|
| Central Plaza | -16..15, 26..53 | Built: level castle-stone plaza, development Core of Power, orientation sign listing every route, avenues out to every district, the Reset Expo access parcel reserved for card A |
| Supply Depot | -16..15, 8..21 | Pad and avenue built; the chest wall is card G's |
| Reserved — future districts | 24..47, 26..53 | Deliberately empty and signed, in full view east of the plaza |
| Day One | -60..-17, 56..95 | The eleven-step chain tree -> log -> planks -> sticks -> workbench -> wood pick -> stone -> stone pick -> furnace -> iron -> iron pick, each on its own signed parcel, read along +x and then down the rows |
| Equipment | -9..24, 60..93 | Wood/stone/iron pick, wood axe, iron sword as catalog booths, and the empty signed future-armour parcel |
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

## 6. Tests

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
