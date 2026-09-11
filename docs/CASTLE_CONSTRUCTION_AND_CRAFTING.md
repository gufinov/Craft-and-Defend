# Castle construction and crafting plan

This plan records Tony's accepted product direction without claiming that the listed content is implemented or balanced. Craft-and-Defend may use familiar voxel-game interaction conventions, but its code, assets, names, recipes, progression and presentation remain original. Minecraft is a public mechanics reference only: Mojang's own crafting overview distinguishes limited personal crafting from a fuller crafting-table flow, while its EULA prohibits distributing copies or substantial copies of Minecraft content. No Minecraft code or assets are used here.

Sources: [Minecraft crafting overview](https://www.minecraft.net/en-us/article/how-craft), [Minecraft EULA](https://www.minecraft.net/en-us/eula).

## Accepted interaction contract

- **Tab — Inventory:** view, select, move and swap the one authoritative 27-slot inventory. It does not expose recipes.
- **B — Field Build:** open a modal 2×2 hand-crafting surface for simple survival starts. The initial implemented set remains planks, sticks and workbench. Torches are next only when placeable light behavior exists.
- **Right-click workbench:** the only entry to its modal 3×3 advanced recipe surface. A targeted station takes priority over placing the selected hotbar item.
- **Right-click processing station:** open that station's own task-specific surface. Furnace is ore + fuel + timed output; a later oven is food + fuel + timed output. A chest is storage, an anvil/forge is equipment work, and none should masquerade as the generic workbench.
- Inventory remains visible as material context in crafting, but crafting and inventory are separate application states. Escape returns to live play.

The implemented 2×2 and 3×3 surfaces visualize the selected data-driven recipe and execute the existing atomic craft command. Inventory items can be dragged or selected into count-based staging slots, while recipe search/selection can auto-fill held ingredients. They do not yet claim free-form positional recipe discovery.

## Historical construction vocabulary

English Heritage's castle surveys support a kit organized around defensible systems rather than decorative cubes: curtain walls and projecting towers, gatehouses and barbicans, battlements, arrow loops, wall galleries/hoardings, drawbridges, portcullises, inner/outer wards and protected approaches. Projecting towers and wall-top positions matter because they create fields of fire and let defenders act along or below a wall face.

Sources: [Castles Through Time](https://www.english-heritage.org.uk/castles/castles-through-time/), [Dunstanburgh Castle description](https://www.english-heritage.org.uk/visit/places/dunstanburgh-castle/history/description/), [Beeston Castle description](https://www.english-heritage.org.uk/visit/places/beeston-castle-and-woodland-park/history/description/), [Etal Castle history](https://www.english-heritage.org.uk/visit/places/etal-castle/history/).

This history informs gameplay vocabulary; it is not a promise of archaeological simulation.

## Content families and functional contracts

Each piece needs a stable ID, footprint, support rule, orientation, placement preview, recipe/station requirement, durability/material class, dismantle/refund rule, navigation effect and save schema before implementation.

### Structural masonry

- foundation/fill block, dressed wall block and reinforced castle stone;
- half block/slab, stair, ramp and wall-walk surface;
- inner/outer corners, arch and buttress;
- crenellated parapet with merlon/gap variants;
- round/square tower wall segments;
- **tower cap / weapon platform:** a functional top piece spanning a declared footprint, providing walkable surface and one or more typed mount sockets for a ballista, catapult or later defense. It must validate the full support footprint and cannot be only cosmetic;
- gatehouse shell, portcullis channel, drawbridge anchor and barbican pieces;
- arrow slit, murder-hole/machicolation or hoarding/gallery pieces only after ranged and below-wall targeting exist.

### Field and fixed defenses

- palisade, stakes, barricade and repairable gate;
- archer post and protected firing position;
- ballista mount, catapult/trebuchet platform and ammunition store;
- traps only after enemy navigation understands their occupied cells and failure behavior.

Siege devices should be entities with footprints, mount requirements, aim/fire/reload state and ammunition contracts—not ordinary voxels. The first defense slice should use one stationary weapon before mobile siege equipment.

### Logistics and stations

- workbench: general 3×3 construction/tool recipes;
- chest: persistent storage with transfer rules;
- furnace/forge: fuel + ore and timed metal output;
- oven/hearth: fuel + food and timed cooked output;
- anvil/smithy: equipment creation, repair or upgrade after durability is decided;
- armory, barracks and supply store only when units and provisioning have real consumers;
- well and fire/light infrastructure only when their world systems exist.

### Player tools, weapons and armor

Before adding gear, define equipment slots, damage types, armor mitigation, durability/repair, tool-vs-weapon roles, death/recovery and whether shields are active or passive. A candidate slot set is main hand, off hand/shield, head, torso, hands, legs and feet. Material tiers can reuse the existing wood/stone/iron resource path, but recipes and values require a separate balance decision.

Museum evidence shows medieval equipment evolved through combinations of mail, shields, helmets, plate elements and full plate, and that interchangeable armor components could serve different kinds of combat. Maces and war hammers also matter once armor types create meaningful weapon choices.

Sources: [Met Museum: Arms and Armor in Medieval Europe](https://www.metmuseum.org/essays/arms-and-armor-in-medieval-europe), [Met Museum: armor garniture](https://www.metmuseum.org/art/collection/search/22741), [Met Museum: mace](https://www.metmuseum.org/art/collection/search/32223).

### Magic — candidate track, not yet accepted implementation

Potential castle-defense roles include a rune table or focus altar, ward anchors, defensive sigils, detection beacons and mana conduits. Decide first whether magic is player equipment, castle infrastructure, enemy threat, or some combination; define cost, cooldown, range, counterplay and save state before adding recipes. Magic must not bypass the resource/placement/occupancy contracts.

## Staged delivery

1. **F5 interface:** inventory/crafting separation, B hand modal, right-click workbench/furnace modals, truthful recipe visualization. No new content IDs.
2. **P1 terrain and first building kit:** improve terrain/resources; prototype wall, stair/slab, parapet, tower cap/platform and gate pieces with placement previews. Validate building feel before combat.
3. **P2 navigation spike:** prove one attacker understands the new footprints, openings, stairs, gates and removable supports.
4. **P3 defense slice:** one warned wave, one stationary mounted defense, ammunition, damage/repair and readable attack paths.
5. **Equipment slice:** player health/combat contract, equipment slots, one armor progression and a small weapon/tool set.
6. **Expanded stations/logistics:** chest, forge/anvil and oven only as their dependent systems arrive.
7. **Magic review:** approve or reject a bounded magic role before implementation.

## Decisions still required

- positional recipes versus recipe-driven auto-fill;
- whether tower caps are crafted whole, assembled from segments, or both;
- structural integrity/collapse rules beyond current adjacent-face support;
- rotation and snapping model for non-cubic castle pieces;
- exact mounted-weapon footprints, crew requirements and ammunition;
- combat, equipment, durability, repair and death/recovery contracts;
- whether magic belongs in the first campaign slice or a later expansion.
