# F0 runtime

The Godot project in this folder is the passed F0 Windows integration spike. It intentionally contains no crafting, enemies, waves, workers, rifts, automation, multiplayer, or procedural world expansion.

## Play on this PC

From the worktree root, double-click `START_F0.cmd`. It prefers the ignored portable export at `builds\CraftAndDefend\CraftAndDefend.exe` and otherwise uses the pinned external custom editor when present.

1. Choose **Start**; the player is not created before this action.
2. Use physical **E/D/S/F** to move, **Space** to jump, and the mouse to look.
3. Aim at grass or dirt and left-click to break/gather exactly one dirt. Right-click a supported empty cell to place it.
4. Try placing into an occupied cell or the player's body; the world and dirt count must remain unchanged.
5. Press **Escape**, open **Keybinds**, change Forward, return, and Resume.
6. Choose **Save and Quit**, relaunch with `START_F0.cmd`, and choose **Continue**. The edits, dirt count, transform, and binding must return.

Normal save data resolves to `C:\Users\Tony\AppData\Roaming\CraftAndDefend\` on the recorded PC. Test automation uses isolated roots under the ignored `artifacts` folder.

## Rebuild

Double-click `BUILD_WINDOWS_F0.cmd`. The wrapper detects the pinned editor/template from environment variables or the required sibling `_tools` layout, generates ignored `game\export_presets.cfg`, and exports with the `Windows Desktop` preset. No machine-specific template path is committed.

Command-line equivalent:

```powershell
& .\tools\build_windows_f0.ps1
```

Launching from official/vanilla Godot is rejected before gameplay loads with `FATAL_TOOLCHAIN_MISMATCH` and the missing Voxel Tools classes. See `docs/evidence/F0_WINDOWS_INTEGRATION.md` for exact versions, hashes, logs, and test results.
