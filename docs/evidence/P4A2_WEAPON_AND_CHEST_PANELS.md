# Evidence — P4a-2 weapon and chest panels — 2026-09-19

STATUS: CANDIDATE — editor gate and visual PASS on branch `feature/p3d-tools-world-feedback` (worktree `D:\CODEX\Craft_and_Defend\worktrees\p3d-tools-world-feedback`); exported `TEST_P4_WEAPON_PANEL.cmd` NOT RUN; owner playtest NOT RUN.

DONE: Implemented [the P4a-2 contract](../P4A2_WEAPON_AND_CHEST_PANELS.md): `SiegeWeaponPanel` (`game/scripts/ui/siege_weapon_panel.gd`) and `ChestPanel` (`game/scripts/ui/chest_panel.gd`) as swap-in cards of the crafting modal in `app.gd` (`CRAFTING_STATION_TYPES`, `_apply_crafting_card_layout`, `_refresh_siege_panel_state` every frame, `_refresh_siege_legend`, siege / chest branches in `_on_crafting_stack_gesture` and `_on_crafting_item_dropped`, `_on_siege_ammo_slot_pressed`, `_on_chest_slot_pressed`, readable texts for `WRONG_AMMUNITION` / `AMMO_TYPE_LOADED` / `WEAPON_FULL` / `WEAPON_EMPTY` / `NO_RESOURCE` / `CONTAINER_FULL`); `_show_workstation` resolves the station type from the service when the session passes an entity id. `P4WeaponPanelAutomation` (`--p4-weapon-panel-automation=gate|visual`, T121–T123), `TEST_P4_WEAPON_PANEL.cmd`, TEST_PLAN rows, INDEX links, BACKLOG card.

EXPECT: Right-click a placed Catapult → "CATAPULT" panel: click Flame Shot in the inventory, click the Ammunition slot → "Loaded 1 Flame Shot — 1 / 5 in the weapon."; Shift+click the slot fills it; Unload returns the shot; Hold / Fire at will and the Target filter change `siege_status`; the SUPPLY line names a chest holding Stone Shot within 8 blocks. Right-click a Chest → "CHEST · N/9 SLOTS USED" grid: drag a stack in, click a tile to take one, Shift+click to take the stack. Escape or Back to Game closes either.

TEST:

| Test ID | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Static | validation + unittest | 148 links; 49/49 | PASS | this worktree |
| Parse | `--check-only` app.gd, siege_weapon_panel.gd, chest_panel.gd, p4_weapon_panel_automation.gd | clean (after `--import` rebuilt the class cache) | PASS | — |
| T121 | weapon panel handlers | select message, 1 → 5 flame, full / mixed / wrong-ammo texts, unload 5 back, hold → `hold`, filter → `raider`, supply "No chest with munitions within 8 blocks", drop and double-click load 5, Escape closes | PASS | `artifacts/dev-agent3-p4-gate/run.log` |
| T121_SUPPLY_READOUT | chest named with distance | "Chest 4.5 m · Stone Shot ×3" | PASS | same |
| T122 | chest panel handlers | header 0/9 → 1/9, +1 / +5 / take 1 / drop 14 / take all, totals conserved | PASS | same |
| T123 | rendered panels + real clicks + fit | flame tile click selects, slot click 3 → 4, Shift+click → 5, chest tile click 12 → 13; message bottom 664, supply 566, legend 678, chest grid 469 (≤ 720) | PASS | `artifacts/dev-agent3-p4-visual/p4-weapon-panel.png`, `p4-chest-panel.png` |
| P3G gate | T93–T97, T107, T114 | PASS | PASS | `artifacts/dev-agent3-p3g-gate` |
| P3G visual | T115, T98 modal fit | PASS | PASS | `artifacts/dev-agent3-p3g-visual` |
| P3E gate | T84–T88 | PASS | PASS | `artifacts/dev-agent3-p3e-gate` |
| P3C phase1 | T72–T77, T118–T120 | T73 FAIL ("Page 1 / 3" vs expected "/ 2", search count 2): the concurrent content change adds workbench recipes (`turret_catapult`, `cannon`, `rail`, `kettle`) so the recipe book now has three pages and "catapult" matches two recipes — not caused by this card; all other tests PASS | FAIL (pre-existing, content-driven) | `artifacts/dev-agent3-p3c-phase1/run.log` |
| Exported | `TEST_P4_WEAPON_PANEL.cmd` | NOT RUN | NOT RUN | — |
| Owner playtest | right-click a placed Catapult / Chest in the game | NOT RUN | NOT RUN | — |

LIMITATIONS/FAILURES: T73 fails on the concurrent uncommitted content (see table); the P3C expectation needs updating by whoever lands those recipes. No cursor-stack pickup from weapon or chest tiles. The session currently emits the entity id as the station type; the app resolves it through `WorkstationService.station_type`, so the panel opens either way, but the right-click path in the real game was verified only through `_show_workstation` in the diagnostic, not by an owner playtest. `--check-only` in this worktree required a one-off `godot --headless --path game --import` to register the new class names.

NEXT: run `TEST_P4_WEAPON_PANEL.cmd` on an exported provenance-matched build; owner playtest; update T73 once the new recipes land; P4a-4 fire evidence.

GIT/REPRODUCIBILITY: branch `feature/p3d-tools-world-feedback`, base `1804a84`; own files only (`app.gd`, two UI scripts, the diagnostic and its `.uid`, the runner, docs). Engine `D:\CODEX\_tools\GodotVoxel\4.6-1.6\editor\godot.windows.editor.x86_64.exe` (4.6). Not exported.
