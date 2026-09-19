# User experience and application lifecycle

The landing page is the **native game's main menu**, not a separate marketing website. The player chooses when to start and always has a route to settings, pause and exit. Build this shell before survival content.

| State | Behavior and allowed routes |
|---|---|
| Boot | Validate configuration/toolchain; route to main menu or readable diagnostic |
| Main menu | New Game/Start, Continue if a valid checkpoint exists, Settings, Keybinds, Quit |
| Loading | Show progress; block gameplay input; on failure return to menu without changing good saves |
| Playing | Capture pointer; movement and interaction enabled; HUD shows hotbar and current target |
| Inventory overlay | Tab-only item view/movement; release pointer; block world actions; pause simulation |
| Crafting/station modal | B opens limited hand crafting; right-click opens the targeted station interface; block world actions; pause simulation |
| Paused | Resume, Settings, Keybinds, Save and Exit to Menu, Save and Quit |
| Settings/keybind overlay | Preserve return state; gameplay stays paused until explicitly resumed |
| Saving | Disable edits and conflicting navigation; responsive feedback; success follows intended destination |
| Save/load error | Preserve last good checkpoint; Retry or safe return; no silent success |

Escape closes the top ordinary overlay first; from gameplay it pauses. Tab toggles inventory only. B toggles the limited hand-crafting modal. Right-click on a targeted workbench/furnace opens that station before the fallback placement action can run. Key-capture mode treats Escape as cancel rather than accidentally changing the pause binding. Pause and settings freeze clock, furnace jobs and gameplay timers, not just character movement. UI and the save coordinator continue processing while the scene tree is paused. Focus loss pauses the single-player session; focus return does not silently resume.

New Game must not overwrite an existing slot without a concrete confirmation. F0 can expose one user slot, but automated/manual isolation testing must exercise two distinct slots. Continue is disabled with a reason when no valid save exists. Quit from main menu requires no world save. Window close during play follows the same save workflow as the menu.

Settings minimum: mouse sensitivity, invert Y, master volume, windowed/fullscreen and resolution selection appropriate to the current monitor. Fullscreen uses and reports the active monitor's native resolution with an expanding canvas that fills non-16:9 displays; explicit size choices apply only to Windowed mode and must be hidden or disabled/explained in Fullscreen. A Fullscreen → Windowed transition preserves the active monitor and centers the complete decorated frame inside that monitor's usable work area, including when its virtual-desktop origin is negative or nonzero. Risky display changes use a confirmation countdown with automatic rollback; defer complex graphics options. Inspect ultrawide/high-DPI and multi-monitor behavior without assuming the user's resolution or monitor origin. Avoid stretching HUD elements to the screen edges; test 16:9 and ultrawide layouts.

World-specific controls live in a scrollable **World Settings** accordion inside Settings. They accept validated 24-hour `HHMM`/`HH:MM` time, enable or pause the day/night cycle, apply immediately to the active session and persist with that slot's next normal save. When no session exists the controls are disabled with a clear route. Do not add a fake command console or weather control before those systems exist.

Keybind screen: action label, current key, change, conflict explanation, reset defaults and back. A conflicting assignment cannot silently displace a required action. Support physical QWERTY defaults and show readable key names. Controls appear in a compact in-game help surface. See [keybind contract](KEYBINDS.md).

No decorative fake buttons, forced tutorial lock-in, unexplained blank world, hidden save failures, or gameplay actions leaking through UI. F0 uses plain functional UI; polished visual branding follows validated interaction.
