# Research verification and source register

Verified 2026-09-10. This is a focused verification of the supplied research, not another Deep Research run. [The original report](research/ORIGINAL_REPORT.md) is preserved unchanged; its internal citation tokens are not portable source links. Use the direct sources below for implementation decisions.

| ID | Primary source | Verified fact / relevance | Limit |
|---|---|---|---|
| S01 | [v1.6 release](https://github.com/Zylann/godot_voxel/releases/tag/v1.6) and [API metadata](https://api.github.com/repos/Zylann/godot_voxel/releases/tags/v1.6) | Godot 4.6 / Voxel Tools 1.6 Module pair; standard Windows editor and release template; archive sizes/digests recorded | Metadata proof, not binary/runtime test |
| S02 | [Release list](https://github.com/Zylann/godot_voxel/releases) | Newer 4.7.2 / 1.7 Module release exists | Do not describe 1.6 as latest |
| S03 | [Getting Voxel Tools](https://voxel-tools.readthedocs.io/en/latest/getting_the_module/) | Module requires custom editor/export pairing; extension alternative exists with less testing noted | Latest docs can differ from pin |
| S04 | [Pinned VoxelTerrain API](https://github.com/Zylann/godot_voxel/blob/595f52ee4e23203a865eeb981f115909f7aa92f4/doc/source/api/VoxelTerrain.md) | Bounds, edit access, mesh readiness and asynchronous save tracker | Not a ready-made game or enclosing boundary wall |
| S05 | [Pinned save tracker API](https://github.com/Zylann/godot_voxel/blob/595f52ee4e23203a865eeb981f115909f7aa92f4/doc/source/api/VoxelSaveCompletionTracker.md) | `is_complete`, `is_aborted`, task-count methods | No documented completion signal; not a cross-file transaction |
| S06 | [Streams](https://voxel-tools.readthedocs.io/en/latest/streams/) | Chunk persistence, asynchronous lifecycle and session/stream reuse hazards | Safe teardown and coherent game-state snapshot need testing |
| S07 | [SQLite stream API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelStreamSQLite/) | Single database; directories must exist; exported saves need writable paths | Does not serialize this game's inventory or workstations |
| S08 | [Navigation](https://voxel-tools.readthedocs.io/en/latest/navigation/) | Dynamic voxel navigation remains a special problem; available helper is experimental | No army-scale guarantee |
| S09 | [Godot license](https://godotengine.org/license/) | MIT engine, game-content ownership retained; notices apply | Project/asset licensing remains separate |
| S10 | [Pinned Voxel Tools license](https://github.com/Zylann/godot_voxel/blob/595f52ee4e23203a865eeb981f115909f7aa92f4/LICENSE.md) | MIT, copyright Marc Gilleron | Preserve notice for redistribution/copying |
| S11 | [Windows export, Godot 4.6](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_windows.html) | Native Windows export path | Module template still needs correct pairing |
| S12 | [InputEvent/InputMap, Godot 4.6](https://docs.godotengine.org/en/4.6/tutorials/inputs/inputevent.html) | Named/remappable actions; runtime mappings need persistence by the game | Physical keyboard behavior needs Windows tests |
| S13 | [Pause processing, Godot 4.6](https://docs.godotengine.org/en/4.6/tutorials/scripting/pausing_games.html) | Scene-tree pause and process modes support gameplay/UI separation | Choose timer/save-coordinator behavior explicitly |
| S14 | [voxelgame](https://github.com/Zylann/voxelgame) | Practical voxel examples, including blocky_game | Reference only; no source copied or compatible commit pinned here |
| S15 | [solar_system_demo](https://github.com/Zylann/solar_system_demo) | Editable voxel game example with persistence/menu patterns | Audit dependencies/assets before reuse; not a Foundation dependency |

## What we adopt

The selected architecture follows the report: Windows-first standalone, Godot/Voxel Tools, GDScript, a finite block world, minimum UI first and save/export proof before crafting. Luanti remains a fallback; Minecraft mod managers remain optional comparison tools. No commercial engine/plugin price assumptions from the report are required to proceed.

## Corrections and open evidence

The report's 1.6 pairing is still available but not latest. Repo emptiness was verified before bootstrap. Day/night is required in full Foundation. Save completion alone does not establish inventory/terrain checkpoint atomicity, and the tracker does not cover subsequent or independent unload-triggered tasks. The report's hybrid navigation suggestion is a hypothesis for a later spike, not an approved algorithm.

Do not copy current upstream master examples blindly into a pinned older module. Inspect their engine/API versions and choose a compatible immutable commit before importing code. Keep a minimal source ledger of copied paths, revision and license. Latest online docs are useful discovery; pinned source/classes determine actual APIs.

Not refreshed here: detailed Unity/Unreal prices, Minecraft mod/version compatibility, Luanti release/security assertions, benchmark scores or vendor comparisons. They are historical report content, not verified current recommendations. Refresh only the material facts if one of those routes becomes active.
