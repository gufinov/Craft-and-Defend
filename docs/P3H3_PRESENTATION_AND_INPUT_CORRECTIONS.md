# P3H.3 — first-person, castle skin and recipe-input corrections

## Outcome

Apply Tony's 2026-09-15 graphical correction without changing combat reach or placement authority. Every held item uses the same lower-right base region; raised tools face inward and seat their handle at the screen base. Dedicated ammunition art, readable placed castle skins, one-block axe harvesting, wheel recipe paging, one-press Furnace Escape and red missing-material cards correct the reported playtest defects.

## Runtime contract

- Sword, picks and Wood Axe use one shared scale, lower-right anchor and inward-facing orientation. Their handle reaches the screen base; the Sword is steeper than the rejected diagonal framing. The existing broad visual swing remains presentation-only.
- Non-tools use the same lower-right base region and retain their larger P3H.2 scale. They use a placement nudge, not a weapon swing.
- `ammunition_atlas_p3h3.png` is a true-alpha two-region atlas. Ballista Bolt resolves one heavy quarrel; Stone Shot resolves one round faceted rock. Neither aliases Stick or Stone-block art.
- Gate Frame and Wall Walk Slab use the Castle Stone face texture when placed. Gate Frame renders its seven occupied masonry cells separately so the texture is not stretched over a three-block column.
- Wood Axe removes and gathers only the targeted Log per use. The data-owned connected-trunk cap is one; upper Log blocks remain until individually harvested.
- Wheel down/up over the recipe-book panel advances/returns one bounded icon page. Wheel behavior over the inventory scroller remains inventory scrolling.
- One physical Escape is handled before focused GUI controls can consume it. A Furnace closes on that press even when its recipe search owns keyboard focus. The existing lossless cursor-stack guard may correctly keep a modal open when closing would discard items.
- Recipe cards whose current status is `INSUFFICIENT_INPUT` use a red background, border and `MISSING` label. Ready recipes remain green; other unavailable states remain neutral.

## Castle-piece intent

Wall Walk Slab is a half-height masonry walking surface for the inside/top of a wall. It is intended to form continuous defender and archer walkways behind parapets without requiring a full-height block at every step. This slice clarifies and skins that existing purpose; it does not add archer assignment or wall-path AI.

## Acceptance

- T73 covers bounded wheel paging and red missing-material cards.
- T80/T81 cover the shared held base and one targeted Log per Axe use.
- T87 covers one-press Furnace Escape while search has focus.
- T91/T103/T104 cover dedicated true-alpha ammunition art, recipe-card presentation, lower-right held framing and the active swing.
- T105/T106 cover runtime and rendered Gate Frame/Wall Walk Slab skins.

## Boundary

No hand/arm rig, per-tool animation set, attack timing change, durability, leaf decay, gate door behavior, archer system, chest runtime, save migration or final 3D production art is added.
