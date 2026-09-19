# P3E — furnace containers and visual identity

Status: PASS / OWNER ACCEPTED 2026-09-14

## Outcome

Make Furnace processing explicit and loss-resistant, give inventory containers familiar stack gestures, and bring the placed/held presentation of key items closer to the icon identity already shown in inventory.

## Furnace contract

- Every placed Furnace owns three persistent stacks: Raw Input, Fuel and Output.
- Iron Ore belongs only in Raw Input; Coal belongs only in Fuel; completed Iron Ingots remain in Output until the player removes them.
- Starting a job consumes exactly one ore and one fuel from the Furnace-owned stacks. The result is never silently inserted into an unrelated inventory slot.
- A running job survives a coherent save/restart with its remaining simulation time. Foundation still has no offline catch-up.
- A non-empty Furnace cannot be dismantled. This prevents stored input, fuel or output from being erased.
- Old in-progress jobs that used an inventory reservation are accepted by the compatibility path; their single reserved result is claimed into the Furnace Output stack on completion.

## Container gestures

- Double-left-click an inventory stack while a Furnace is open to move the whole compatible stack into Raw Input or Fuel.
- Double-left-click any Furnace stack to move the whole stack back to inventory, including completed Output.
- Right-click an unheld stack to pick up the larger half. Left-click deposits the held stack. Right-click deposits one. Holding right-click and dragging distributes one into each compatible traversed slot once.
- The held cursor stack is part of the coherent inventory snapshot. Closing Inventory or Crafting returns it to inventory; if no room exists, the panel remains open instead of discarding it.
- Ordinary Workbench and hand-crafting grids remain one-item patterns. Players may arrange a pattern manually; recipe-book selection/search is an accelerator, not a prerequisite for recipe recognition.

## Visual identity

- Placed Workbench and Furnace forms now have distinct functional silhouettes and material details rather than unrelated plain cubes.
- First-person Workbench, Furnace, Stone Pick and Wood Axe presentations use transparent three-quarter reference cutouts derived from the same visual language as their inventory icons.
- This is an identity-alignment pass, not final production modeling, animation or authored texture work.

## Gates

| Test | Required evidence |
|---|---|
| T84 — container transfer | Whole compatible inventory stacks move into distinct Furnace-owned input/fuel slots. |
| T85 — stack gestures | Half-pickup, one-item deposit and right-drag distribution preserve exact counts. |
| T86 — retained output | One job retains exactly one output across restore and collection moves it explicitly to inventory. |
| T87 — visual identity | The real three-slot modal, detailed world stations and transparent held reference exist. |
| T88 — manual discovery | A manually arranged valid pattern is recognized without recipe-book selection or search. |
| T89 — presentation | Rendered evidence shows the three-slot Furnace and revised world/held identity. |

## Boundaries

No parallel Furnace jobs, fuel-duration balance, multiple ore types, output automation, hoppers, chest/container UI, durability, animated hands, final 3D models or final icon set is claimed here.
