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

Implemented inventory: 27 slots including a 9-slot hotbar; ordinary stacks 64, tools one per slot. Tab is inventory only. B opens a distinct 2×2 hand-crafting modal; right-clicking a placed workbench opens its 3×3 modal, while a furnace opens its ore-and-fuel processing modal. Hand and Workbench crafting retain the three-panel inventory, one-item pattern grid and paged searchable recipe book. Inventory items can be dragged to the grid or selected and placed by keyboard/click. Selecting a recipe—or pressing Enter on its search result—auto-fills the staged grid when inventory has sufficient materials, but manually arranging a known valid pattern is independently recognized. The workbench recipe book includes the basic planks, sticks and workbench recipes alongside advanced recipes, but only right-clicking the placed workbench opens it. Hand/Workbench staging does not consume inventory; the authoritative transaction runs only when Craft is pressed. Ingredient counts are recognized regardless of staged cell order; positional recipe shapes remain deferred. Tool durability, encumbrance and dropped-item physics are deferred. Gathering is rejected when output cannot fit. Hotbar indexes refer to inventory slots rather than duplicate independent stacks.

UI shows recipes and why unavailable: missing materials, wrong workstation, missing tool or no output room. A craft request validates the entire transaction. Workbench crafting is immediate. Every Furnace owns persistent Raw Input, Fuel and Output stacks; jobs consume one input/fuel exactly once and retain completed output until explicit collection. Whole-stack double-click transfer, larger-half right-click pickup, one-item right-click deposit and one-per-slot right-drag distribution preserve exact counts. Refuse dismantling a running or non-empty station so stored contents cannot be erased.

Recipe-book progression is data-driven through a nonnegative `recipe_book_order`; lower values appear first and display name breaks ties deterministically. Workbench books include hand recipes, keeping Planks, Sticks and Workbench ahead of wooden tools, stone/castle construction, iron equipment and siege content. New accepted recipes should normally receive a later order unless their approved progression tier places them among the fundamentals. Search and paging remain available for the complete current list. This ordering prepares for future discovery, but no recipe-learning trigger or hidden-recipe persistence exists yet.

No survival hunger, damage, armor or weapons are implemented yet. Their eventual item definitions must use the same registry/transaction layer. Original placeholder textures are enough; preserve the numerical voxel mapping across saves. Never persist display labels as IDs. The approved content direction and staged castle kit are recorded in [Castle construction and crafting](CASTLE_CONSTRUCTION_AND_CRAFTING.md).
