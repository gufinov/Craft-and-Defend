# Starter content and crafting

[content.json](../contracts/content.json) is the canonical Foundation balance fixture and remains non-final tuning. F2 loads a byte-equivalent runtime mirror at `game/data/content.json` and validates it against this source. The hands → wood → stone → iron loop is implemented and reachable without creative-mode items. Stable IDs are more important than current quantities.

| Voxel ID | Block | Drop | Minimum pick tier |
|---:|---|---|---:|
| 0 | air | none | not mineable |
| 1 | grass | dirt | 0 |
| 2 | dirt | dirt | 0 |
| 3 | stone | stone | 1 |
| 4 | log | log | 0 |
| 5 | planks | planks | 0 |
| 6 | coal ore | coal | 2 |
| 7 | iron ore | iron_ore | 2 |
| 8 | castle stone | castle_stone | 1 |
| 9 | bedrock | none | protected |

Tier 0 is hands, 1 wooden pick, 2 stone pick, 3 iron pick. Coal is fuel and does not place a coal-ore block. Iron ore can be smelted; raw ore is not granted by failed mining with an insufficient tool. Bedrock prevents digging through the world bottom, in addition to command boundary checks.

## Reachable progression

1. Harvest logs by hand; convert 1 log into 4 planks and 2 planks into 4 sticks by hand.
2. Craft a workbench from 4 planks by hand. Place it on support.
3. At the workbench craft a wooden pick from 3 planks and 2 sticks.
4. Mine stone; craft a stone pick from 3 stone and 2 sticks, and a furnace from 8 stone.
5. Mine coal and iron ore with the stone pick. Place the furnace.
6. Process 1 iron ore plus 1 coal into 1 ingot in 5 simulation seconds (fixture value).
7. Craft an iron pick from 3 ingots and 2 sticks at the workbench.

Castle stone (1 stone → 1 castle stone at workbench) is an optional visual building block. No reverse conversion loop or free resources. Initial gathering spots are explicit patches in the test world; procedural ore distribution and full trees come later.

Implemented inventory: 27 slots including a 9-slot hotbar; ordinary stacks 64, tools one per slot. Tab is inventory only. B opens a distinct 2×2 hand-crafting modal; right-clicking a placed workbench opens its 3×3 modal, while a furnace opens its ore-and-fuel processing modal. Each crafting view has an inventory panel, a staged input grid and a vertically scrolling recipe book with search and wireframe thumbnails. Inventory items can be dragged to the grid or selected and placed by keyboard/click. Selecting a recipe—or pressing Enter on its search result—auto-fills the staged grid when the inventory has sufficient materials. The workbench recipe book includes the basic planks, sticks and workbench recipes alongside advanced recipes, but only right-clicking the placed workbench opens it. Staging does not consume inventory; the authoritative transaction runs only when Craft is pressed. Ingredient counts are recognized regardless of staged cell order; positional recipe shapes remain deferred. Tool durability, encumbrance and dropped-item physics are deferred. Gathering is rejected when output cannot fit. Hotbar indexes refer to inventory slots rather than duplicate independent stacks.

UI shows recipes and why unavailable: missing materials, wrong workstation, missing tool or no output room. A craft request validates the entire transaction. Workbench crafting is immediate; furnace jobs reserve an output slot and consume inputs/fuel exactly once. On cancel/dismantle, use one documented refund rule, tested for duplicate-item exploits. Simplest Foundation rule: refuse dismantling a running station; idle station dismantling returns the station item and stored contents only if inventory can hold everything.

Recipe-book prominence is data-driven through an optional nonnegative `recipe_book_priority`; higher-priority entries appear before the normal alphabetical order. Use it only for a currently important, player-testable recipe that would otherwise be hidden below the first visible recipe-book page. Search and scrolling remain available for the complete list. P3B pins Wood Barricade so its required graphical acceptance path begins on the visible Workbench page.

No survival hunger, damage, armor or weapons are implemented yet. Their eventual item definitions must use the same registry/transaction layer. Original placeholder textures are enough; preserve the numerical voxel mapping across saves. Never persist display labels as IDs. The approved content direction and staged castle kit are recorded in [Castle construction and crafting](CASTLE_CONSTRUCTION_AND_CRAFTING.md).
