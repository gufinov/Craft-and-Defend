# CoasterCraft — the coaster building game mode

Owner (2026-09-21): "You can add this as a game mode in the game menu and call it CoasterCraft. Clear the entire foundation you laid out for testing. I don't want anything on it. And double its size. User should be able to continue or start new. It should have a menu of its own for saving and restarting, exit, etc. This is a coaster building mode, no monsters are needed." Plan: [INDUSTRY_PLAN.md](INDUSTRY_PLAN.md) (wave 1, card *CoasterCraft mode*).

## What it is

Main menu → **CoasterCraft** (between Continue and Settings) opens the mode's submenu, title **COASTERCRAFT**:

- **Continue** — resumes the mode's last checkpoint (enabled only when one exists).
- **New** — a fresh world on the fixed seed (41026, the one the diagnostics use) with a **bare 60 × 100 stone plate** beside the spawn: x −29..30, z 22..121, stone at y 0, air above, nothing on it — no demo tracks, no mountain, no lead-ins, no starter markers, no Core of Power.
- **Back** — the main menu (Escape does the same).

In the mode: **creative placement** (track tools and stations cost nothing), an **infinite pack** — every second each item of the stock list is topped up to its stack size; on a new plate the hotbar is arranged in stock order: Rail, Rail Slope, Rail Loop, Rail Switch, Rail Cross, Rail Curve, Rail Climb, Mine Cart, Coaster Car, then Kettle, Castle Stone, Planks, Iron Pick, Iron Sword, Stone Shot, Flame Shot, Torch, Chest, Wood Axe, Dirt, Stone in the pack (`CoasterCraftMode.STOCK`). **No monsters**: no defense drills, no waves, no far attack, no enemy core is placed, the HUD's drill line and the enemy-base compass are hidden and the minimap does not mark the enemy base. The navigation line reads `COASTERCRAFT · infinite stock · …`. Everything else plays as the real game (keys in [KEYBINDS.md](KEYBINDS.md); all track tools and the coaster car in [COASTER_RAILS.md](COASTER_RAILS.md) / [COASTER_CAR_AND_HERO.md](COASTER_CAR_AND_HERO.md)).

The plate is levelled by `CoasterCraftMode` as the terrain streams in (120 columns a frame; the spawn's corner at once, the far end within a few seconds). Call made here: the card levels y 1..13, but the far end of a 100-deep plate reaches terrain that can carry mountains and lakes, so each column is cleared **up to the world ceiling (y 31)** and underpinned with stone down to **y −8** where the ground was air or water — nothing floats over or under the plate. A continued save re-runs the same pass (a no-op on the saved plate; it finishes any far end that was never streamed in before the save).

## Saves

The mode has its own `SaveCoordinator` at **`<data root>/coastercraft/`** (`slots/a/…`, the same checkpoint format as the game), so the game's slots A / B are untouched; settings (`settings.cfg`) are shared. The submenu shows the path. `DATA_ROOT` is still printed for the app's root; the check prints `COASTERCRAFT DATA_ROOT <path>`. Snapshots carry `"mode": "coastercraft"`.

## Pause menu (Escape)

Title **COASTERCRAFT · PAUSED**, one column, no drills: **Resume** · **Save** (checkpoint and stay in the paused game — the world stream reattaches to the working database, the same path a recovered failed save uses) · **Save and Restart (new bare plate)** (checkpoint, then a fresh plate; Continue then resumes whichever plate was saved last) · **Save and Exit to Menu** · **Save and Quit** · Settings · Keybinds · Hero: Armour on/off · Track auto-clear on/off. Escape resumes, as in the game.

## Launch

- `START.cmd coastercraft` (repo root): prepares the export and starts it straight into the mode's **New** (`--coastercraft`) with the data root `artifacts\coastercraft` (so the mode's saves land in `artifacts\coastercraft\coastercraft\`); the main menu's CoasterCraft button in the ordinary `START_GAME` uses the normal data root.
- `START.cmd sandbox` / `--coaster-sandbox` (`CoasterSandbox`) is **this mode plus the demo tracks**: it starts the mode through the same path as the New button, levels the old 30 × 50 demo area (x −14..15, z 22..71) at once and lays the loop, circuit, curves, mountain climb, smooth switch and crossing there; every `--coaster-sandbox-*` check works as before.

## Code

`game/scripts/app/coastercraft_mode.gd` (`CoasterCraftMode`: coordinator, `begin`, `on_session_ready`, plate levelling, `stock_pack`, `plate_bare_report`), `app.gd` (`_build_coastercraft_menu`, `_build_coastercraft_pause`, `_on_coastercraft_new_pressed` / `_on_coastercraft_continue_pressed`, `active_saves()`, `_coastercraft_save`, `_coastercraft_save_and_restart`, `_save_then(quit_after, restart_coastercraft)`), `game_session.gd` (`coastercraft` flag: no enemy core, no enemy-base hint, no starter markers, blank drill line, mode navigation line), `minimap_overlay.gd` (`show_enemy_base`).

## Tests

- `--coastercraft-check` (`CoasterCraftCheck`, headless): boots the app and walks the mode through its buttons' paths — submenu (Continue gated), New, the mode's coordinator under `<data root>/coastercraft`, fixed seed, plate bare across a 5-cell sample grid (240 columns: stone at y 0, air at y 1..2, no stations), spawn on the plate, stock and hotbar order, HUD lines, no enemy core / drill, the pause menu's buttons (no drill / attack button), Save in place (revision 1, same session, rail kept, streaming back), Save and Restart (revision 2, new bare plate), Save and Exit to Menu (revision 3, game slot untouched), Continue (the rail placed on the second plate is back, creative, stock). Prints `COASTERCRAFT_CHECK ok=true …`, quits 0 / 1: `godot --headless --path game --log-file <dir>\run.log -- --f0-data-root=<dir> --coastercraft-check`.
- **T191_COASTERCRAFT_MODE** in `--coaster-rails-automation=gate`: the gate's session saves and exits to the menu, then the same `CoasterCraftCheck.exercise` runs in-process.
- Sandbox gate: `--coaster-sandbox --coaster-sandbox-facing-check` (all demos laid on the mode's plate, `reversals=0`).
