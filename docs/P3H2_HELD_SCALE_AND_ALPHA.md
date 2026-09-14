# P3H.2 — held scale, strike travel and unified alpha art

## Outcome

Match Tony's 2026-09-15 marked-up first-person presentation target without changing combat authority. Picks, axes and the sword share one enlarged lower-right frame. Tool use visibly travels through a broad strike arc. Blocks, stations, materials and placeable siege items remain low-held but render at least twice the former P3H.1 scale and slightly higher. Inventory, recipes and held presentation resolve from one true-alpha PNG atlas.

## Runtime contract

- Tool position, rotation, pixel scale and swing travel are named constants owned by `HeldItemView`.
- Sword, all pick tiers and the Wood Axe use the same tool profile; item art keeps its authored proportions.
- Tool use animates through a 1.45-radian visual arc, then returns to ready. Attack range, damage, recovery and authoritative hit timing remain unchanged.
- Non-tools use a short placement nudge instead of the weapon swing.
- Low-held items use a 0.00340 pixel scale, exactly twice the former 0.00170 value, and a higher base anchor.
- The active card and world-reference paths both resolve `item_atlas_p3h2.png`. Every extracted region remains filter-clipped and no RGB card-background atlas is active.
- Earlier atlases remain preserved for recovery. Rejected generated RGB/checker candidates never enter the runtime path.

## Boundary

This slice does not add a hand or arm model, skeletal animation, per-tool bespoke poses, hit trails, camera shake, new items, damage changes, durability, chest behavior or final 3D assets. Tony's ultrawide playtest remains the acceptance authority for exact feel and framing.

## Acceptance

T91 machine-checks the active RGBA source, alpha corner, exact dimensions, common tool frame, doubled low-held scale and minimum broad arc. T92 retains the eight-item visual catalog. T103 retains both Workbench pages. T104 renders a ready sword, active swing and Furnace scale comparison from the exported runtime.
