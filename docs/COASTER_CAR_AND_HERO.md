# Coaster car and hero — ride the roller coaster, set its speed, meet the character

Owner request (2026-09-19, verbatim intent): "I want to be able to speed up the roller coaster. I want to be able to ride the roller coaster. We should make a roller coaster car. Once inside, I can use the number keys to increase speed from 1-9. Perhaps it is also time to create a character."

Builds on the [coaster rails side project](COASTER_RAILS.md): the car rides the same track graph (`CoasterRails.chain`) through the same `CoasterCartService` as the mine cart. New files carry `coaster` / `hero` names: `game/scripts/rails/coaster_ride.gd` (`CoasterRide`), `game/scripts/player/hero_model.gd` (`HeroModel`), `game/scripts/diagnostics/coaster_car_automation.gd`, `TEST_COASTER_CAR.cmd`, this contract and [its evidence](evidence/COASTER_CAR_AND_HERO.md). Owner art: `docs/reference/owner_art/coaster_car.webp`, `hero_unarmored.webp`, `hero_armored.webp`.

## Content

| Entity | Item stack | Footprint | Mount | Recipe (Workbench) | Attributes |
|---|---|---|---|---|---|
| `coaster_car` | 2 | 1×1, `"cart": {"rail_speed": 3.0}`, support the cell below | `rail_mount` only (exactly like `mine_cart`) | 4 planks + 2 iron ingot + 1 castle stone → 1 (order **207**, after Mine Cart) | value 16, role `rail`, mount `any_solid_top`, space 1×1×1 |

Same `navigation` / `defense` blocks as the mine cart (wood, breachable, 30 / 30 integrity, planks repair). The Workbench book is 39 recipes, still four pages. Icon: the owner's `coaster_car.webp` through `tools/generate_derived_icons.py` (`OWNER_ICONS`, appended to `DERIVED` / `DERIVED_ORDER`; atlas cell 21, regions re-measured; 50 regions).

## The car (`GameSession._build_coaster_car_visual`)

Box / cylinder / cone primitives in the owner's style: four stone wheels with gold hubs, a dark stone chassis under an oak floor, oak side walls with stone side rails and stone corner posts carrying gold diamond studs, a high oak seat back framed in stone with a gold stud, an oak bench, a gold safety bar on stone brackets, and a stone nose sloping to the front with a blue banner (gold edges, a gold diamond in the middle — the fleur-de-lis of the art) and a gold spike. Everything sits under the `CartRig` node the cart service moves (origin at the wheel contact point, model faces −z); the rig's `Seat` node (in the cavity between bar and seat back) is where the riding hero is parented. Collision box as the mine cart.

## Riding (`CoasterRide`, `game/scripts/rails/coaster_ride.gd`)

- A placed car is registered **parked** (`CoasterCartService.register_cart(id, body, parked = true)`); a parked cart never moves. It waits where it is until a rider boards, and parks again where the rider leaves it.
- **Board:** aim at the car and press **Shift** (Interact). The raycast in `GameSession._defense_interact` recognises the car's station body before the repair path and calls `board_coaster_car` (so a car cannot be repaired with Shift; dismantle and re-place it instead). Boarding deactivates the player body (no physics, hidden hero), captures the pointer, seats a `HeroModel` on the car's `Seat` (`set_seated(true)`: arms on the bar, legs hidden by the body, sword stowed), un-parks the car, sets speed **3** and switches to the ride camera.
- **Camera:** a **three-quarter chase camera** (`RideCamera`, child of `CoasterRide`): 3.0 m behind the car's smoothed *horizontal* heading, 1.8 m to its right and 1.9 m up, looking at a point 0.6 m above and 0.3 m ahead of the car with world up. The heading is smoothed (rate 4 /s) and the position eased (rate 8 /s), so turns and loop exits swing the view gently; world-up means a loop never rolls the view. The side offset keeps the camera out of the loop's plane (a radius-3 loop swallowed a camera straight behind the car). The player body is dragged along under the car each frame so terrain keeps streaming around the player's `VoxelViewer`.
- **Speed:** number keys **1–9** set the car's speed in cells per second (`CoasterCartService.set_speed(id, n)` overrides the entity's `rail_speed` for that car; 1 = crawl, 9 = 9 cells/s; default 3 on boarding). The HUD's slot text becomes `RIDING · speed 3/9 · 1-9 speed · Shift leave`. While riding the hotbar keys never change the held slot; the held-item view is hidden.
- **Leave:** **Shift** again, or **Escape** (handled before the pause in `_handle_escape_recovery`). The car parks where it is; the player stands 1 m to the car's right at the floor of the rail cell (a car hanging in a loop leaves the player to drop). The previous first/third-person choice is restored.
- **Pause / save:** pausing keeps the rider seated (the car stops with `simulation_paused`; resuming re-captures the pointer without re-activating the body). The car is an ordinary station for save / restore; the ride itself is not persisted — a snapshot taken mid-ride stores the player beside the car (`_player_snapshot`), so a load puts the player on foot next to the parked car. Dismantling or destroying the ridden car, or dying, leaves the car first.

Speed table (cells per second = key): 1 → 1.0, 2 → 2.0, 3 → 3.0 (default), … 9 → 9.0. T165 measures 2.00 and 6.00 cells/s along the lead-in.

## The hero (`HeroModel`, `game/scripts/player/hero_model.gd`)

Node3D built from primitives like `BasicRaider` (feet at the origin, front −z, about 1.8 tall). **Unarmoured:** brown hair (cap, fringe, sides), skin face with blue eyes and brows, blue tunic with a gold hem and seam and a gold lion-crest rectangle on the chest, blue front and back tabards with gold trim and a gold lion, blue scarf with a tail, brown baldric with gold buckle, brown belt with a gold buckle and a pouch, blue sleeves with gold trim over cream forearms, brown bracers with gold buckles, dark trousers, brown boots with cuffs and buckles, and a sword in the right hand (leather grip, gold pommel and cross guard with a blue gem, silver blade and tip). **`set_armored(true)`** rebuilds the plate look: silver breastplate with gold collar and hem and a large gold chest diamond, blue tabard with a gold lion, brown belt with a silver buckle and gold diamond, blue pauldrons with gold trim and gold shoulder diamonds, silver upper arms and vambraces with gold trim, gauntlets, cuisse plates, silver greaves with gold trim and toe caps, the scarf and gorget. `animate_walk(delta, moving, distance)` scissors the legs and counter-swings the arms from the distance travelled (`walk_phase`, blended in and out like the raiders). `set_seated(true)` hides the legs, pitches both arms forward onto the bar and stows the sword.

Used in two places: seated in the coaster car while riding, and on foot in **third person**.

## Third person (V)

**V** (a raw key read in `GameSession._unhandled_input`, like X / C during a loop drag — not an InputMap action, not rebindable) toggles `PlayerController.set_third_person`: the camera moves 3.5 m behind the eye along its own aim, 0.45 m over the right shoulder and 0.6 m higher, still pitched by the mouse; the hero model (`player.hero`) is visible only then and walks with the body. Aim rays (break, place, interact, previews) start from `view_origin()` — the eye point on the camera's ray — so reach and targets are the same as in first person. The first-person held-item presentation is unchanged and hidden in third person. The chase camera does not avoid walls (it can clip into blocks behind the player).

## Hero armour setting

Pause menu → **Hero: Armour on/off** (`_toggle_hero_armor`) flips `SettingsStore.hero_armored` (`[hero] armored` in `settings.cfg`, default off) and re-dresses both the on-foot hero and a seated rider (`GameSession.set_hero_armored`). It is purely cosmetic for now.

## Tests

`--coaster-car-automation=gate` (headless): **T164** content / icon / recipe; **T165** a parked car on a loop fixture stays put, Shift through the interaction raycast boards it (player parked, ride camera current, seated hero on `Seat`, speed 3/9 HUD), speed 2 then 6 measure 2.00 / 6.00 cells/s, the `hotbar_5` action sets speed 5 without touching the hotbar, `interact` leaves the player 1 m beside the parked car, a mid-ride snapshot saves the player beside the car; **T166** hero parts, armoured swap, walk cycle, seated pose, V toggle (camera behind / above, hero visible, aim from the eye), `hero_armored` persisted in `settings.cfg` and applied. `=visual` (windowed): **T167** `coaster-car.png` — the hero riding the car into the sandbox-style loop from the ride camera, 1280×720. `TEST_COASTER_CAR.cmd` runs both against the export. See [TEST_PLAN](TEST_PLAN.md).

Sandbox: `--coaster-sandbox` (`START_COASTER_SANDBOX.cmd`) now parks a coaster car at the start of the premade loop's lead-in (the loop's mine cart moved off; the slope run keeps its mine cart) and stocks `coaster_car` in the hotbar after Mine Cart — walk up, Shift, press 1–9.

## Limits — what is NOT done

- No momentum or gravity: the speed is exactly the key pressed. The car reverses at track ends like the mine cart.
- One rider, no passengers; the seated hero has no idle animation; the sword is hidden while seated.
- The ride camera has no collision with terrain and does not avoid walls; on a loop it swings around the car as the heading reverses over the top. First person from the seat is not offered.
- The third-person chase camera does not avoid walls; the hero's first-person body is still invisible (no visible feet). V is a raw key, not rebindable.
- Repairing a coaster car with Shift is not possible (Shift boards). No car panel, no cart inventory, no hauling.
- Hero armour is a cosmetic toggle in the pause menu, not earned from iron or the inventory.
- The ride is not saved: a save mid-ride reloads with the player beside the parked car.
