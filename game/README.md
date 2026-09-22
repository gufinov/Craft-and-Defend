# P3E candidate runtime

The Godot project contains the owner-accepted foundation through P3B and the combined P3C/P3D/P3E candidate. P3E adds explicit retained Furnace containers, familiar stack gestures and a closer match between inventory, held and placed item identity without claiming waves, player health, workers, rifts, multiplayer or campaign expansion.

## Play on this PC

From the repository or worktree root, double-click `START.cmd`. In a Git checkout it verifies the ignored portable export against the current tracked `game` tree and automatically rebuilds a missing, legacy, dirty or mismatched package before launch. A portable folder without Git launches its packaged executable normally. `START.cmd help` lists the other options (`sandbox`, `coastercraft`, `build`, `stop`).

1. Choose **Slot A** or **Slot B**, then **Start New**. Each slot owns independent terrain, inventory, player and workstation state; the player is not created before this action.
2. Use physical **E/D/S/F** to move, **Space** to jump, and the mouse to look.
3. Aim at grass, dirt or tree logs and left-click to gather. The two authored trunks contain enough logs to begin progression.
4. Press **Tab** for the icon-first inventory. Drag items between the 18 carried slots and nine-key held hotbar, or use the existing select/swap path. Filter and sort the carried area by item type. The armor panel remains visibly reserved; armor behavior is not implemented yet.
5. Press **B** for the 2×2 hand-crafting modal and make planks, sticks and a workbench. **Tab** opens inventory only. Click **Craft ×1** for one batch or hold **Shift** while clicking for exactly five complete immediate-recipe batches atomically. Select the workbench in the hotbar and right-click a supported empty cell to place it; right-click the placed workbench to open its 3×3 advanced recipes and craft a Wooden Pick or Wood Axe.
6. Equip a Wood Axe and left-click a tree trunk to gather its connected vertical logs. Mine stone with the Wooden Pick, then craft a Stone Pick and Furnace at the Workbench. Near Home, follow the visible **IRON VEIN — DIG 2 BLOCKS** marker; mine its iron ore with the Stone Pick. Place and right-click the Furnace. Double-click Iron Ore and Coal to move their full stacks into Raw Input and Fuel, start processing, close the panel so simulation time advances, then reopen it and double-click the retained Iron Ingot Output to collect it. Right-click picks up half or deposits one; right-drag distributes one per traversed slot. A non-empty/running Furnace refuses dismantling. Hand and Workbench recipes may be assembled manually without first finding their recipe card.
7. Craft an **Iron Sword** from two Iron Ingots and one Stick. Put it in keys 1–9, approach an active core raider and left-click to strike. Craft/place **Ballista** on supported ground or a Tower Platform; it fires only with direct line of sight. Craft/place **Catapult** on supported ground; it requires a clear arc between 8 and 34 metres. Both automatically target only the current core raider and begin with finite persisted ammunition.
8. The selected sword, pick or axe appears raised in hand; selected blocks appear lower. Aim at a supported destination to see a green placement ghost or a red invalid ghost, then right-click to commit. A truly floating block, player overlap, occupied cell, crafting without materials, wrong station or full output inventory must explain rejection and leave state unchanged.
9. Press **Escape**, open **Keybinds**, search or scroll through grouped action rows. Any implemented keyboard or mouse action can be changed; conflicts are explained and change nothing. Each row has its own **Reset**, and **Reset All Defaults** restores the exact ESDF contract. Escape always cancels capture.
10. Open **Settings** to change look sensitivity, vertical inversion, master volume or window mode. Fullscreen reports and uses the active monitor's native resolution and fills ultrawide displays. Explicit resolutions apply to Windowed mode; previews remain centered within the active monitor's usable area and revert after ten seconds unless confirmed.
11. From a paused game, expand **World Settings**. Enter a 24-hour time such as `0800` or `20:00`, choose whether the **Day/Night cycle** runs, then press **Apply World Settings**. New worlds begin at a visible 08:00 sunrise. The sun, sky, lighting and HUD update immediately; the chosen time and cycle state persist with the next normal save in that slot.
12. Choose **Save and Quit**, relaunch with `START.cmd`, choose the same slot, and choose **Continue**. Terrain, inventory/hotbar, transform, workstations, world time/cycle state and an in-progress furnace job must return without duplicate outputs. The main menu reports whether the selected slot has a complete checkpoint.
13. Press **F2** while playing to save the rendered game viewport in the background without pausing. The confirmation names the PNG. Change or reset this action in **Keybinds**; it is a global setting shared by save slots.
14. Press **Print Screen** while playing. The world freezes invisibly while Windows Snipping Tool owns focus, no Pause menu contaminates the capture, and play resumes after focus returns. Ordinary Alt-Tab/focus loss still opens Pause and requires explicit Resume.
15. If saving fails, use **Retry Save** or **Return to Paused Game**. The previously completed checkpoint remains available; the game does not label a failed save as successful.

Normal save data resolves to `C:\Users\Tony\AppData\Roaming\CraftAndDefend\` on the recorded PC. In-game captures resolve to its `screenshots` subfolder. Test automation uses isolated roots under the ignored `artifacts` folder.

## Rebuild

Double-click `START.cmd build`. The wrapper detects the pinned editor/template from environment variables or the required sibling `_tools` layout, generates ignored `game\export_presets.cfg`, and exports with the `Windows Desktop` preset. No machine-specific template path is committed. The completed `builds\CraftAndDefend` folder includes its own `START.cmd` and `README.txt`; copy that folder anywhere and keep its files together. (The former `BUILD_WINDOWS.cmd` / `BUILD_WINDOWS_F0.cmd` wrappers were folded into `START.cmd build` on 2026-09-22.)

Command-line equivalent:

```powershell
& .\tools\build_windows_f0.ps1
```

Launching from official/vanilla Godot is rejected before gameplay loads with `FATAL_TOOLCHAIN_MISMATCH` and the missing Voxel Tools classes. See `docs/evidence/F3_PERSISTENCE_HARDENING.md` for the accepted dependency baseline, `docs/evidence/P3D_TOOLS_AND_WORLD_FEEDBACK.md` for the preceding candidate and `docs/P3E_FURNACE_CONTAINERS_AND_VISUAL_IDENTITY.md` for this update's contract.
