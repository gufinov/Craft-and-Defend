# F4 candidate runtime

The Godot project contains owner-accepted F0/F1/F3, owner-confirmed F2 gathering/inventory/crafting, and the F4 Foundation-acceptance candidate. It intentionally contains no enemies, waves, workers, rifts, automation, multiplayer or procedural world expansion.

## Play on this PC

From the repository or worktree root, double-click `START_GAME.cmd`. In a Git checkout it verifies the ignored portable export against the current tracked `game` tree and automatically rebuilds a missing, legacy, dirty or mismatched package before launch. A portable folder without Git launches its packaged executable normally. The old `START_F0.cmd` remains a compatibility wrapper.

1. Choose **Slot A** or **Slot B**, then **Start New**. Each slot owns independent terrain, inventory, player and workstation state; the player is not created before this action.
2. Use physical **E/D/S/F** to move, **Space** to jump, and the mouse to look.
3. Aim at grass, dirt or tree logs and left-click to gather. The two authored trunks contain enough logs to begin progression.
4. Press **Tab** for the 27-slot inventory and recipe panel. Click a source slot then a destination slot to move/swap stacks. Slots 1–9 are the hotbar; number keys select them.
5. Craft planks, sticks and a workbench by hand. Select the workbench in the hotbar and right-click a supported empty cell to place it. Aim at it and hold **Shift** to open workbench recipes; craft a wooden pick.
6. Mine stone with the wooden pick, then craft a stone pick and furnace. Mine coal and iron ore with the stone pick. Place the furnace, hold **Shift** while aiming at it, and start ingot jobs. Furnace time freezes while inventory/pause owns input. A left-click dismantles an idle targeted station; a running furnace refuses dismantling.
7. Try invalid placement, crafting without materials, the wrong station and a full output inventory; each operation must explain rejection and leave state unchanged.
8. Press **Escape**, open **Keybinds**, search or scroll through grouped action rows. Any implemented keyboard or mouse action can be changed; conflicts are explained and change nothing. Each row has its own **Reset**, and **Reset All Defaults** restores the exact ESDF contract. Escape always cancels capture.
9. Open **Settings** to change look sensitivity, vertical inversion, master volume or window mode. Fullscreen reports and uses the active monitor's native resolution and fills ultrawide displays. Explicit resolutions apply to Windowed mode; previews remain centered within the active monitor's usable area and revert after ten seconds unless confirmed.
10. From a paused game, expand **World Settings**. Enter a 24-hour time such as `0800` or `20:00`, choose whether the **Day/Night cycle** runs, then press **Apply World Settings**. New worlds begin at a visible 08:00 sunrise. The sun, sky, lighting and HUD update immediately; the chosen time and cycle state persist with the next normal save in that slot.
11. Choose **Save and Quit**, relaunch with `START_GAME.cmd`, choose the same slot, and choose **Continue**. Terrain, inventory/hotbar, transform, workstations, world time/cycle state and an in-progress furnace job must return without duplicate outputs. The main menu reports whether the selected slot has a complete checkpoint.
12. Press **F2** while playing to save the rendered game viewport in the background without pausing. The confirmation names the PNG. Change or reset this action in **Keybinds**; it is a global setting shared by save slots.
13. Press **Print Screen** while playing. The world freezes invisibly while Windows Snipping Tool owns focus, no Pause menu contaminates the capture, and play resumes after focus returns. Ordinary Alt-Tab/focus loss still opens Pause and requires explicit Resume.
14. If saving fails, use **Retry Save** or **Return to Paused Game**. The previously completed checkpoint remains available; the game does not label a failed save as successful.

Normal save data resolves to `C:\Users\Tony\AppData\Roaming\CraftAndDefend\` on the recorded PC. In-game captures resolve to its `screenshots` subfolder. Test automation uses isolated roots under the ignored `artifacts` folder.

## Rebuild

Double-click `BUILD_WINDOWS.cmd`. The wrapper detects the pinned editor/template from environment variables or the required sibling `_tools` layout, generates ignored `game\export_presets.cfg`, and exports with the `Windows Desktop` preset. No machine-specific template path is committed. The completed `builds\CraftAndDefend` folder includes its own `START_GAME.cmd` and `README.txt`; copy that folder anywhere and keep its files together. The old `BUILD_WINDOWS_F0.cmd` remains a compatibility wrapper.

Command-line equivalent:

```powershell
& .\tools\build_windows_f0.ps1
```

Launching from official/vanilla Godot is rejected before gameplay loads with `FATAL_TOOLCHAIN_MISMATCH` and the missing Voxel Tools classes. See `docs/evidence/F3_PERSISTENCE_HARDENING.md` for the accepted dependency baseline and the F4 evidence record for this candidate's results.
