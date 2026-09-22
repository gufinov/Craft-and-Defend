# Development Expo

The owner's development world: one campus where every built system stands
assembled, ready to walk up to and try. The commission is
[the implementation handoff](DEVELOPMENT_EXPO_HANDOFF.md); this file is the
contract of what is built.

This page covers the **mode** (card A): how it is entered, where it saves,
its pause menu, its runtime rules, the seams the district cards build on and
the lost-Core Continue safety that had to be fixed before any of it. Later
cards append their district sections below.

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
```

- **`build_expo(session, fresh)`** runs on a fresh development world and on
  Reset Expo. It logs `EXPO_BUILD start …` / `EXPO_BUILD end …` around the
  registered builder and records `last_build` (`{ok, fresh, builder,
  seconds}`). With no builder registered it is a stub that changes nothing —
  card C registers the real `ExpoBuilder` with `set_builder`.
- **`reset_group(session, name)`** is the `ExpoResetService` seam: it
  restores one named district without touching the others. An unregistered
  name returns `{"ok": false, "reason": "NO_GROUP"}`. Card E registers
  `battlefield` with `register_reset_group`.
- **`EXPO_FIXTURE_VERSION`** is raised whenever the authored Expo changes in
  a way an existing development world should be rebuilt for.

---

## Checks

| Gate | Covers |
| --- | --- |
| `--f3-automation=phase1` | **T210** lost-Core Continue: a save is written with the defended core destroyed and a chest left over dug-away ground; the menu reports Game Over — Start New with Development Start still reachable and the file readable; Continue through the app's own path finishes inside a bounded number of frames with the drill restored as lost, no re-created core and the chest back in place |
| `--development-check` | the whole Development Start round trip: the submenu, New, `DEVELOPMENT DATA_ROOT <path>` under `<data root>/development`, the runtime rules (no waves after three seconds of play, no enemy core, hidden drill line, daytime clock with the cycle running, no creative top-up), the builder and reset-group seams, the pause menu without drills, the Reset Expo confirmation and rebuild, Save and Exit and Continue — and **T211_DEVELOPMENT_MODE_ISOLATION**: a marker written into a normal Slot A checkpoint reads back unchanged, with the same revision, after a Development New and a Reset Expo, and the CoasterCraft namespace is untouched |
