# F1 accepted runtime

The Godot project in this folder contains the owner-accepted F0 Windows integration spike and F1 interaction hardening. It intentionally contains no crafting, enemies, waves, workers, rifts, automation, multiplayer, or procedural world expansion.

## Play on this PC

From the repository or worktree root, double-click `START_GAME.cmd`. In a Git checkout it verifies the ignored portable export against the current tracked `game` tree and automatically rebuilds a missing, legacy, dirty or mismatched package before launch. A portable folder without Git launches its packaged executable normally. The old `START_F0.cmd` remains a compatibility wrapper.

1. Choose **Start**; the player is not created before this action.
2. Use physical **E/D/S/F** to move, **Space** to jump, and the mouse to look.
3. Aim at grass or dirt and left-click to break/gather exactly one dirt. Right-click a supported empty cell to place it.
4. Try placing into an occupied cell or the player's body; the world and dirt count must remain unchanged.
5. Press **Escape**, open **Keybinds**, and scroll through all implemented actions. Any keyboard or mouse binding can be changed; conflicts are explained and change nothing. **Reset Defaults** restores the exact ESDF contract. Escape always cancels capture.
6. Open **Settings** to change look sensitivity, vertical inversion, master volume or window mode. Fullscreen reports and uses the active monitor's native resolution and fills ultrawide displays. Explicit resolution choices apply to Windowed mode; previews remain centered within the active monitor's usable area. Display changes require confirmation and revert after ten seconds.
7. Press **Tab** in play to open the inventory overlay. Gameplay pauses and mouse input cannot edit the world until the overlay closes.
8. Choose **Save and Quit**, relaunch with `START_GAME.cmd`, and choose **Continue**. The edits, dirt count, transform, and bindings must return.

Normal save data resolves to `C:\Users\Tony\AppData\Roaming\CraftAndDefend\` on the recorded PC. Test automation uses isolated roots under the ignored `artifacts` folder.

## Rebuild

Double-click `BUILD_WINDOWS.cmd`. The wrapper detects the pinned editor/template from environment variables or the required sibling `_tools` layout, generates ignored `game\export_presets.cfg`, and exports with the `Windows Desktop` preset. No machine-specific template path is committed. The old `BUILD_WINDOWS_F0.cmd` remains a compatibility wrapper.

Command-line equivalent:

```powershell
& .\tools\build_windows_f0.ps1
```

Launching from official/vanilla Godot is rejected before gameplay loads with `FATAL_TOOLCHAIN_MISMATCH` and the missing Voxel Tools classes. See `docs/evidence/F0_WINDOWS_INTEGRATION.md` and `docs/evidence/F1_INTERACTION_HARDENING.md` for exact versions, hashes, logs, and test results.
