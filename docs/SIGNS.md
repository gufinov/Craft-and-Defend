# Signs

Owner commission: [Development Expo handoff](DEVELOPMENT_EXPO_HANDOFF.md) section 9. A sign is an ordinary reusable gameplay asset — craftable, placeable, dismantleable, saved — not a development-only prop. The Expo's Supply Depot and district signs use the same item and the same API.

## The item

| | |
| --- | --- |
| Item / entity id | `sign` (category `building`, stacks to 16) |
| Workbench recipe | 2 Planks + 1 Stick → 1 Sign (`recipe_book_order` 218, last in the book) |
| Footprint | one cell (`occupied_offsets` `[[0, 0, 0]]`), support below for the ground variant |
| Integrity | 8, repaired with 2 Planks |
| Icon | `icon_sign` in `tools/generate_derived_icons.py` (derived atlas cell 31) |

Balance is tunable; nothing here copies an external game's asset.

## Placement

The sign uses the existing mount rules (`WorkstationService.try_place` / `_wall_side`, the same path as the Torch and the Wall Lantern), so `mount.allowed` is `["ground", "wall"]`:

- **ground** — the cell below is solid: the board stands on an oak post with a stone foot, turned by the ordinary build rotation (W / R);
- **wall** — no ground below, a solid block on one side: the board hangs flat on that block on two iron brackets, with no post, rotated to face away from the wall.

The chosen mount is stored on the station record as `"mount": "wall"` (absent means ground) so a reload does not ask a wall sign for ground support. Every part of the board, post and collision stays **inside the sign's own logical cell**: a thin panel can never reach into a cell another entity owns, and a sign cannot be placed into an occupied cell (`OCCUPIED`). To hang a sign above a chest, place it in the cell above — the Expo's authored fixtures do exactly that.

The board faces local +X, so a ground sign turns with the build rotation and a wall sign faces the room.

## Content model

The station record carries one `sign` block of stable ids and text — never a label, a scene path or an array index:

```
"sign": {
  "mode": "text" | "split" | "items" | "header_items",
  "text_a": String,   # the single text, the left text, or the heading
  "text_b": String,   # the right text of a split sign
  "items": [item_id, ...]   # up to 8 item ids, in board order
}
```

It is saved by `workstations.snapshot()` with the rest of the record and normalised on `restore()`: an unknown mode falls back to `text`, text is trimmed to 64 characters and unknown or surplus item ids are dropped. A record written before this feature (or an authored one without the block) **migrates** to an empty single-text sign instead of failing the load.

## The four display modes

1. **Single Text** — `text_a` centred on the board.
2. **Split Text** — `text_a` and `text_b` side by side with a carved divider.
3. **Item Grid** — up to eight entries as icon + readable name, 4 rows × 2 columns, filled left column top-to-bottom then right column.
4. **Header + Item Grid** — `text_a` as a heading above the same grid.

The board renders with `Label3D` text and `Sprite3D` item icons (the same `ItemIconCatalog` art the inventory uses), the project's existing in-world text approach. Captions carry a pale outline so the grid reads at 3–6 m.

## The editor panel

Right-click a placed sign (the ordinary station interaction) and the SIGN panel opens in the app's existing modal language — `AppState.SIGN`, the world still running under it (the live-menu contract; only the pause menu pauses). Escape or **Close** leaves without writing; **Save** writes the record.

The panel holds the four mode buttons, the text field(s) of the active mode, the eight item slots (each a tile showing icon + name) and the item picker. It is **not** a dropdown: a category strip comes first, then an icon + readable-name grid, exactly like the inventory and recipe book. Click a slot, then an item, and the selection walks to the next slot; **Clear Selected Slot** and **Clear All Slots** empty them. Clearing a slot in the middle closes the gap when the record is written — the board shows the remaining entries in order.

## Categories

`game/scripts/ui/item_categories.gd` (`ItemCategories`) owns the single mapping from item id to Expo category (handoff section 8): an explicit per-item table, a fallback from the content `category` field, and `unassigned` for anything neither places, so a new visible item is surfaced rather than lost. `ItemCategories.category_of(item_id, content_category)`, `label_of(category_id)` and `grouped(registry)` are the API. The Supply Depot card owns the depot's own use of this mapping and may extend it; existing ids and their order stay.

## API for other systems

```
GameSession.configure_sign(instance_id, data) -> Dictionary   # {"ok", "reason", "details": {"sign": …}}
GameSession.sign_data(instance_id) -> Dictionary              # the normalised block, {} when not a sign
```

`data` may carry any subset of `mode` / `text_a` / `text_b` / `items`; what it omits keeps its current value. An unknown mode (`INVALID_SIGN_MODE`), an unknown item id (`UNKNOWN_SIGN_ITEM`) or a ninth item (`INVALID_SIGN_ITEMS`) is rejected without changing the record. `WorkstationService.configure_sign` / `sign_data` / `sign_mount` are the service-level calls underneath; configuring through the session also rebuilds the board's face.

## Tests

`T212_SIGN_PLACEMENT_AND_EDITOR` (`--p3d-usability-automation=phase1`) and its rendered evidence `T212_SIGN_PRESENTATION` (`--p3d-usability-automation=visual`, `p3d-sign-item-grid.png`). See [the test plan](TEST_PLAN.md).
